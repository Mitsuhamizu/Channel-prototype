require_relative "../miscellaneous/libs/gpctest.rb"
require "minitest/autorun"
require "mongo"
require "bigdecimal"

Mongo::Logger.logger.level = Logger::FATAL

class Making_payment_udt < Minitest::Test
  def make_payment(file_name)
    @path_to_file = __dir__ + "/../miscellaneous/files/"
    @logger = Logger.new(@path_to_file + "gpc.log")
    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database

    data_raw = File.read(__dir__ + "/" + file_name)
    data_json = JSON.parse(data_raw, symbolize_names: true)

    funding_fee_A = data_json[:A][:funding_fee].to_i
    funding_fee_B = data_json[:B][:funding_fee].to_i
    settle_fee_A = data_json[:A][:settle_fee].to_i
    settle_fee_B = data_json[:B][:settle_fee].to_i
    container_min = data_json[:container_min].to_i

    # may have multiple amount, one for udt, one for ckb.
    funding_amount_A = data_json[:A][:funding_amount].map { |key, value| key == :ckb ? [key, BigDecimal(value.to_i) / 10 ** 8] : [key, value.to_i] }.to_h
    funding_amount_B = data_json[:B][:funding_amount].map { |key, value| key == :ckb ? [key, BigDecimal(value.to_i) / 10 ** 8] : [key, value.to_i] }.to_h

    expect = JSON.parse(data_json[:expect_info], symbolize_names: true) if data_json[:expect_info] != nil
    settle_fee_unilateral = data_json[:settle_fee_unilateral].to_i
    closing_fee_unilateral = data_json[:closing_fee_unilateral].to_i
    channel_type = data_json[:channel_type]
    closing_type = data_json[:closing_type]
    payments = data_json[:payments]

    # simple testing in ckb.
    tests = Gpctest.new("test")
    tests.setup()

    udt_A_begin, udt_B_begin = tests.get_account_balance_udt()
    ckb_A_begin, ckb_B_begin = tests.get_account_balance_ckb()

    begin
      # create channel.
      channel_id, @monitor_A, @monitor_B = tests.create_channel(funding_amount_A, funding_amount_B, channel_type, container_min, funding_fee_A, funding_fee_B)

      @logger.info("making_payment_udt: channel established.")
      # make payments.
      ckb_transfer_A_to_B = 0
      ckb_transfer_B_to_A = 0
      udt_transfer_A_to_B = 0
      udt_transfer_B_to_A = 0

      for payment in payments
        sender = payment[:sender]
        receiver = payment[:receiver]
        amount = payment[:amount]
        success = payment[:success]
        payment_type = payment[:payment_type]

        # send payment.
        if sender == "A" && receiver == "B"
          tests.make_payment_A_B(channel_id, payment_type, amount)
          if success
            if payment_type == "ckb"
              ckb_transfer_A_to_B += amount
            elsif payment_type == "udt"
              udt_transfer_A_to_B += amount
            end
          end
        elsif sender == "B" && receiver == "A"
          tests.make_payment_B_A(channel_id, payment_type, amount)
          if success
            if payment_type == "ckb"
              ckb_transfer_B_to_A += amount
            elsif payment_type == "udt"
              udt_transfer_B_to_A += amount
            end
          end
        else
          return false
        end
      end

      @logger.info("making_payment_udt: payments all sent.")

      ckb_A_B = ckb_transfer_A_to_B - ckb_transfer_B_to_A
      udt_A_B = udt_transfer_A_to_B - udt_transfer_B_to_A

      # B send the close request to A.
      tests.closing_B_A(channel_id, settle_fee_B, settle_fee_A, closing_fee_unilateral, settle_fee_unilateral, closing_type)

      ckb_A_after_closing, ckb_B_after_closing = tests.get_account_balance_ckb()
      udt_A_after_closing, udt_B_after_closing = tests.get_account_balance_udt()

      # assert udt
      assert_equal(udt_A_B, udt_A_begin - udt_A_after_closing, "A'udt after payment is wrong.")
      assert_equal(-udt_A_B, udt_B_begin - udt_B_after_closing, "B'udt after payment is wrong.")

      # assert ckb
      assert_equal(ckb_A_B * 10 ** 8 + funding_fee_A + settle_fee_A, ckb_A_begin - ckb_A_after_closing, "A'ckb after payment is wrong.")
      assert_equal(-ckb_A_B * 10 ** 8 + funding_fee_B + settle_fee_B, ckb_B_begin - ckb_B_after_closing, "B'ckb after payment is wrong.")
      if expect != nil
        for expect_iter in expect
          result_json = tests.load_json_file(@path_to_file + "result.json").to_json
          assert_match(expect_iter.to_json[1..-2], result_json, "#{expect_iter[1..-2]}")
        end
      end
    rescue Exception => e
      puts e
      raise e
    ensure
      tests.close_all_thread(@monitor_A, @monitor_B, @db)
    end
  end

  def test_success()
    make_payment("making_payment_success.json")
  end
end
