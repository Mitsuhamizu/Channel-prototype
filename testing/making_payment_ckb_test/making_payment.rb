require_relative "../libs/gpctest.rb"
require "mongo"
require "bigdecimal"
require "logger"

Mongo::Logger.logger.level = Logger::FATAL
$VERBOSE = nil

@client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
@db = @client.database

file = ARGV[0]
data_raw = File.read(file)
data_json = JSON.parse(data_raw, symbolize_names: true)

container_min = data_json[:container_min].to_i
funding_fee_A = data_json[:funding_fee_A].to_i
funding_fee_B = data_json[:funding_fee_B].to_i
settle_fee_A = data_json[:settle_fee_A].to_i
settle_fee_B = data_json[:settle_fee_B].to_i
funding_amount_A = data_json[:funding_amount_A].to_i
funding_amount_B = data_json[:funding_amount_B].to_i
closing_type = data_json[:closing_type]
payments = data_json[:payments]

# simple testing in ckb.
tests = Gpctest.new("test")
tests.setup()
balance_A_begin, balance_B_begin = tests.get_account_balance_ckb()

begin
  channel_id, @monitor_A, @monitor_B = tests.create_ckb_channel(funding_amount_A, funding_amount_B, funding_fee_A, funding_fee_B, settle_fee_A)
  balance_A_after_funding, balance_B_after_funding = tests.get_account_balance_ckb()

  # B send the close request to A.

  amount_A_B_ckb = 0
  amount_B_A_ckb = 0

  amount_A_B_udt = 0
  amount_B_A_udt = 0

  for payment in payments
    payment = payment[1]
    sender = payment[:sender]
    receiver = payment[:receiver]
    amount = payment[:amount]
    payment_type = payment[:payment_type]

    if sender == "A" && receiver == "B" && payment_type == "ckb"
      amount_A_B_ckb += amount
      tests.make_payment_ckb_A_B(channel_id, amount)
    elsif sender == "B" && receiver == "A" && payment_type == "ckb"
      amount_B_A_ckb += amount
      tests.make_payment_ckb_B_A(channel_id, amount)
    elsif sender == "A" && receiver == "B" && payment_type == "udt"
      amount_B_A_udt += amount
      tests.make_payment_udt_B_A(channel_id, amount)
    elsif sender == "B" && receiver == "A" && payment_type == "udt"
      amount_B_A_udt += amount
      tests.make_payment_udt_B_A(channel_id, amount)
    else
      return false
    end
  end

  amount_diff = amount_B_A_ckb - amount_A_B_ckb
  tests.closing_B_A(channel_id, settle_fee_B, closing_type)

  balance_A_after_payment, balance_B_after_payment = tests.get_account_balance_ckb()
  # @logger.info("after payment:#{balance_A_after_payment1}")

  # tests.assert_equal(-amount_diff * 10 ** 8 + funding_fee_A + settle_fee_A, balance_A_begin - balance_A_after_payment, "A'balance after payment is wrong.")
  # tests.assert_equal(amount_diff * 10 ** 8 + funding_fee_B + settle_fee_B, balance_B_begin - balance_B_after_payment, "B'balance after payment is wrong.")
rescue Exception => e
  raise e
ensure
  tests.close_all_thread(@monitor_A, @monitor_B, @db)
end
