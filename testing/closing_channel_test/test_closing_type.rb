require_relative "../miscellaneous/libs/gpctest.rb"
require "minitest/autorun"
require "mongo"
require "bigdecimal"

Mongo::Logger.logger.level = Logger::FATAL

class Closing < Minitest::Test
  def closing(file_name)
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
    settle_fee_unilateral = data_json[:settle_fee_unilateral].to_i
    closing_fee_unilateral = data_json[:closing_fee_unilateral].to_i

    funding_amount_A = BigDecimal(data_json[:funding_amount_A]) / 10 ** 8
    funding_amount_B = BigDecimal(data_json[:funding_amount_A]) / 10 ** 8

    closing_type = data_json[:closing_type]
    expect = JSON.parse(data_json[:expect_info], symbolize_names: true) if data_json[:expect_info] != nil if data_json[:expect_info] != nil
    payment_type = data_json[:payment_type]
    payments = data_json[:payments]

    # simple testing in ckb.
    tests = Gpctest.new("test")
    tests.setup()

    balance_A_begin, balance_B_begin = tests.get_account_balance_ckb()

    begin
      channel_id, @monitor_A, @monitor_B = tests.create_ckb_channel(funding_amount_A, funding_amount_B, funding_fee_A, funding_fee_B, settle_fee_A)

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
        else
          return false
        end
      end

      amount_diff = amount_B_A - amount_A_B

      # update settlement and closing fee.
      tests.update_command(:closing_fee_unilateral, closing_fee_unilateral)
      tests.update_command(:settle_fee_unilateral, settle_fee_unilateral)

      # B send the close request to A.
      tests.closing_B_A(channel_id, settle_fee_B, closing_type)

      balance_A_after_payment, balance_B_after_payment = tests.get_account_balance_ckb()

      if closing_type == "bilateral"
        assert_equal(-amount_diff * 10 ** 8 + funding_fee_A + settle_fee_A, balance_A_begin - balance_A_after_payment, "A'balance after payment is wrong.")
        assert_equal(amount_diff * 10 ** 8 + funding_fee_B + settle_fee_B, balance_B_begin - balance_B_after_payment, "B'balance after payment is wrong.")
      elsif closing_type == "unilateral"
        assert(((-amount_diff * 10 ** 8 + funding_fee_A + settle_fee_unilateral == balance_A_begin - balance_A_after_payment) && (amount_diff * 10 ** 8 + funding_fee_B + closing_fee_unilateral == balance_B_begin - balance_B_after_payment)) || ((-amount_diff * 10 ** 8 + funding_fee_A == balance_A_begin - balance_A_after_payment) && (amount_diff * 10 ** 8 + funding_fee_B + closing_fee_unilateral + settle_fee_unilateral == balance_B_begin - balance_B_after_payment)), "balance after payments wrong.")
      end

      if expect != nil
        for expect_iter in expect
          result_json = tests.load_json_file(@path_to_file + "result.json").to_json
          assert_match(expect_iter.to_json[1..-2], result_json, "#{expect_iter[1..-2]}")
        end
      end
    rescue Exception => e
      raise e
    ensure
      tests.close_all_thread(@monitor_A, @monitor_B, @db)
    end
  end

  def test_unilateral()
    closing("closing_unilateral.json")
  end

  def test_bilateral()
    closing("closing_bilateral.json")
  end
end
