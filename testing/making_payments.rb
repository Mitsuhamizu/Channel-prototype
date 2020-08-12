require "./libs/gpctest.rb"
require "mongo"
require "bigdecimal"
require "logger"

Mongo::Logger.logger.level = Logger::FATAL
$VERBOSE = nil
@client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
@db = @client.database
@logger = Logger.new("gpc1.log")
tests = Gpctest.new("test")

fee_A = 4000
fee_B = 2000
fee_settlement_A = 2000
fee_settlement_B = 1000
# # simple testing in udt.
# tests.setup()
# balance_A, balance_B = tests.get_account_balance_udt()
# capacity_A, capacity_B = tests.get_account_balance_ckb()
# begin
#   container_min = 134 * 10 ** 8
#   id, @monitor_A, @monitor_B = tests.create_udt_channel(100, 100)
#   balance_A_after_funding, balance_B_after_funding = tests.get_account_balance_udt()
#   capacity_A_after_funding, capacity_B_after_funding = tests.get_account_balance_ckb()

#   amount_A_B = 10
#   amount_B_A = 20
#   tests.make_payment_udt_A_B(id, amount_A_B)
#   tests.make_payment_udt_B_A(id, amount_B_A)

#   tests.assert_db_filed_A(id, :nounce, 3)
#   tests.assert_db_filed_B(id, :nounce, 3)

#   tests.closing_A_B(id)

#   amount = amount_B_A - amount_A_B
#   balance_A_after_payment1, balance_B_after_payment1 = tests.get_account_balance_udt()
#   capacity_A_after_payment1, capacity_B_after_payment1 = tests.get_account_balance_ckb()

#   tests.assert_equal(-amount, balance_A - balance_A_after_payment1, "A'balance after payment is wrong.")
#   tests.assert_equal(amount, balance_B - balance_B_after_payment1, "B'balance after payment is wrong.")

#   tests.assert_equal(fee_A + fee_settlement_A, capacity_A - capacity_A_after_payment1, "A'capacity after payment is wrong.")
#   tests.assert_equal(fee_B + fee_settlement_B, capacity_B - capacity_B_after_payment1, "B'capacity after payment is wrong.")
# rescue => e
#   puts e
#   raise e
# ensure
#   tests.close_all_thread(@monitor_A, @monitor_B, @db)
# end

# simple testing in ckb.
tests.setup()
balance_A, balance_B = tests.get_account_balance_ckb()
@logger.info("before funding:#{balance_A}")
begin
  id, @monitor_A, @monitor_B = tests.create_ckb_channel(1000, 1000, fee_A, fee_B)
  balance_A_after_funding, balance_B_after_funding = tests.get_account_balance_ckb()
  @logger.info("after funding:#{balance_A_after_funding}")

  amount_A_B = 10
  amount_B_A = 20
  tests.make_payment_ckb_A_B(id, amount_A_B)
  tests.make_payment_ckb_B_A(id, amount_B_A)
  tests.closing_B_A(id)
  amount = amount_B_A - amount_A_B

  balance_A_after_payment1, balance_B_after_payment1 = tests.get_account_balance_ckb()
  @logger.info("after payment:#{balance_A_after_payment1}")
  tests.assert_equal(-amount * 10 ** 8 + fee_A + fee_settlement_A, balance_A - balance_A_after_payment1, "A'balance after payment is wrong.")
  tests.assert_equal(amount * 10 ** 8 + fee_B + fee_settlement_B, balance_B - balance_B_after_payment1, "B'balance after payment is wrong.")
rescue Exception => e
  raise e
ensure
  tests.close_all_thread(@monitor_A, @monitor_B, @db)
end

# # simple testing in ckb.
# tests.setup()
# balance_A, balance_B = tests.get_account_balance_ckb()
# begin
#   id, @monitor_A, @monitor_B = tests.create_ckb_channel(1000, 1000, fee_A, fee_B)
#   balance_A_after_funding, balance_B_after_funding = tests.get_account_balance_ckb()

#   amount_A_B = 10
#   amount_B_A = 20
#   tests.make_payment_ckb_A_B(id, amount_A_B)
#   tests.make_payment_ckb_B_A(id, amount_B_A)

#   tests.closing_A_B(id)

#   amount = amount_B_A - amount_A_B

#   balance_A_after_payment1, balance_B_after_payment1 = tests.get_account_balance_ckb()

#   tests.assert_equal(-amount * 10 ** 8 + fee_A + fee_closing + fee_settlement, balance_A - balance_A_after_payment1, "balance after payment is wrong.")
#   tests.assert_equal(amount * 10 ** 8 + fee_B, balance_B - balance_B_after_payment1, "balance after payment is wrong.")
# rescue Exception => e
#   raise e
# ensure
#   tests.close_all_thread(@monitor_A, @monitor_B, @db)
# end
