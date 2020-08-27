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

    container_min = data_json[:container_min].to_i
    funding_fee_A = data_json[:funding_fee_A].to_i
    funding_fee_B = data_json[:funding_fee_B].to_i
    settle_fee_A = data_json[:settle_fee_A].to_i
    settle_fee_B = data_json[:settle_fee_B].to_i

    funding_amount_A = data_json[:funding_amount_A]
    funding_amount_B = data_json[:funding_amount_B]

    closing_type = data_json[:closing_type]
    expect = data_json[:expect_info]
    payment_type = data_json[:payment_type]
    payments = data_json[:payments]

    # simple testing in ckb.
    tests = Gpctest.new("test")
    tests.setup()

    if payment_type == "ckb"
      balance_A_begin, balance_B_begin = tests.get_account_balance_ckb()
    elsif payment_type == "udt"
      balance_A_begin, balance_B_begin = tests.get_account_balance_udt()
      capacity_A_begin, capacity_B_begin = tests.get_account_balance_ckb()
    end

    begin
      if payment_type == "ckb"
        channel_id, @monitor_A, @monitor_B = tests.create_ckb_channel(funding_amount_A, funding_amount_B, funding_fee_A, funding_fee_B, settle_fee_A)
      elsif payment_type == "udt"
        channel_id, @monitor_A, @monitor_B = tests.create_udt_channel(funding_amount_A, funding_amount_B, funding_fee_A, funding_fee_B, settle_fee_A)
      end

      # make payments.
      amount_A_B = 0
      amount_B_A = 0

      for payment in payments
        payment = payment[1]
        sender = payment[:sender]
        receiver = payment[:receiver]
        amount = payment[:amount]
        success = payment[:success]
        if sender == "A" && receiver == "B" && payment_type == "ckb"
          tests.make_payment_ckb_A_B(channel_id, amount)
          amount_A_B += amount if success
        elsif sender == "B" && receiver == "A" && payment_type == "ckb"
          tests.make_payment_ckb_B_A(channel_id, amount)
          amount_B_A += amount if success
        elsif sender == "A" && receiver == "B" && payment_type == "udt"
          tests.make_payment_udt_A_B(channel_id, amount)
          amount_A_B += amount if success
        elsif sender == "B" && receiver == "A" && payment_type == "udt"
          tests.make_payment_udt_B_A(channel_id, amount)
          amount_B_A += amount if success
        else
          return false
        end
      end

      @logger.info("amount_B_A: #{amount_B_A}")
      @logger.info("amount_A_B: #{amount_A_B}")

      amount_diff = amount_B_A - amount_A_B

      # B send the close request to A.
      tests.closing_B_A(channel_id, settle_fee_B, closing_type)

      if payment_type == "ckb"
        balance_A_after_payment, balance_B_after_payment = tests.get_account_balance_ckb()
      elsif payment_type == "udt"
        balance_A_after_payment, balance_B_after_payment = tests.get_account_balance_udt()
        capacity_A_after_payment, capacity_B_after_payment = tests.get_account_balance_ckb()
      end

      if payment_type == "ckb"
        assert_equal(-amount_diff * 10 ** 8 + funding_fee_A + settle_fee_A, balance_A_begin - balance_A_after_payment, "A'balance after payment is wrong.")
        assert_equal(amount_diff * 10 ** 8 + funding_fee_B + settle_fee_B, balance_B_begin - balance_B_after_payment, "B'balance after payment is wrong.")
      elsif payment_type == "udt"
        assert_equal(-amount_diff, balance_A_begin - balance_A_after_payment, "A'balance after payment is wrong.")
        assert_equal(amount_diff, balance_B_begin - balance_B_after_payment, "B'balance after payment is wrong.")

        assert_equal(funding_fee_A + settle_fee_A, capacity_A_begin - capacity_A_after_payment, "A'capacity after payment is wrong.")
        assert_equal(funding_fee_B + settle_fee_B, capacity_B_begin - capacity_B_after_payment, "B'capacity after payment is wrong.")
      end

      if expect != nil
        result_json = tests.load_json_file(@path_to_file +"result.json").to_json
        assert_match(expect[1..-2], result_json, "#{expect}")
      end
    rescue Exception => e
      raise e
    ensure
      tests.close_all_thread(@monitor_A, @monitor_B, @db)
    end
  end

  def test_success()
    make_payment("making_payment_success.json")
  end

  def test_negtive()
    make_payment("making_payment_negtive.json")
  end

  def test_insufficient()
    make_payment("making_payment_insufficient.json")
  end
end
