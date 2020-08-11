require "./libs/gpctest.rb"
require "mongo"
require "bigdecimal"

Mongo::Logger.logger.level = Logger::FATAL
$VERBOSE = nil

tests = Gpctest.new("test")

# simple testing in udt.
tests.preparation_before_test()
balance_A, balance_B = tests.get_account_balance_udt()
capacity_A, capacity_B = tests.get_account_balance_ckb()
begin
  id, @monitor_A, @monitor_B, @db = tests.create_udt_channel(100, 100)
  balance_A_after_funding, balance_B_after_funding = tests.get_account_balance_udt()

  amount_A_B = 10
  amount_B_A = 20
  tests.make_payment_udt_A_B(id, amount_A_B)
  tests.make_payment_udt_B_A(id, amount_B_A)
  tests.closing_A_B(id)

  amount = amount_B_A - amount_A_B
  balance_A_after_payment1, balance_B_after_payment1 = tests.get_account_balance_udt()
  tests.assert_equal(amount, balance_A - balance_A_after_payment1, "balance after payment is wrong.")
  tests.assert_equal(-amount, balance_B - balance_B_after_payment1, "balance after payment is wrong.")
rescue Exception => e
  raise e
ensure
  tests.close_all_thread(@monitor_A, @monitor_B, @db)
end

# # simple testing in ckb.
# tests.preparation_before_test()
# balance_A, balance_B = tests.get_account_balance_ckb()
# begin
#   id, @monitor_A, @monitor_B, @db = tests.create_ckb_channel(1000, 1000)
#   balance_A_after_funding, balance_B_after_funding = tests.get_account_balance_ckb()

#   amount_A_B = 10
#   amount_B_A = 20
#   tests.make_payment_ckb_A_B(id, amount_A_B)
#   tests.make_payment_ckb_B_A(id, amount_B_A)
#   tests.closing_A_B(id)

#   amount = amount_B_A - amount_A_B
#   balance_A_after_payment1, balance_B_after_payment1 = tests.get_account_balance_ckb()
#   tests.assert_equal(amount * 10 ** 8, balance_A - balance_A_after_payment1, "balance after payment is wrong.")
#   tests.assert_equal(-amount * 10 ** 8, balance_B - balance_B_after_payment1, "balance after payment is wrong.")
# rescue Exception => e
#   raise e
# ensure
#   tests.close_all_thread(@monitor_A, @monitor_B, @db)
# end
