require "./libs/gpctest.rb"
require "mongo"
require "bigdecimal"

Mongo::Logger.logger.level = Logger::FATAL
$VERBOSE = nil

tests = Gpctest.new("test")

# here is the udt version.
investment_fee = []
tests.preparation_before_test()
balance_A, balance_B = tests.get_account_balance_udt()
capacity_A, capacity_B = tests.get_account_balance_ckb()
# begin
#   id, @monitor_A, @monitor_B, @db = tests.create_udt_channel(100, 100)
#   balance_A_after_funding, balance_B_after_funding = tests.get_account_balance_udt()
#   amount = 10
#   tests.make_payment_udt_A_B(id, amount)
#   tests.closing_A_B(id)

#   balance_A_after_payment1, balance_B_after_payment1 = tests.get_account_balance_udt()
#   tests.assert_equal(-amount, balance_A_after_funding - balance_A_after_payment1, "balance after payment is wrong.")
#   tests.assert_equal(amount, balance_B_after_funding - balance_B_after_payment1, "balance after payment is wrong.")
# rescue => exception
# ensure
#   tests.close_all_thread(@monitor_A, @monitor_B, @db)
# end
