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

# test the investment
fee_A = 5000
fee_B = 5000

# A investment  > total_udt
# only gather_funding
investment_A = BigDecimal((balance_A + 1).to_s)
investment_B = BigDecimal((balance_B - 100).to_s)
expect = :sender_gather_funding_error_insufficient
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# A investment = total_udt && fee < total_capacity
# both gather_funding and gather_fee
investment_A = BigDecimal(balance_A.to_s)
investment_B = BigDecimal((balance_B - 100).to_s)
expect = :sender_gather_funding_success
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect, 0]

# A investment = total_udt && fee >total_capacity
# both gather_funding and gather_fee
fee_A = capacity_A + 1
investment_A = BigDecimal(balance_A.to_s)
investment_B = BigDecimal((balance_B - 100).to_s)
expect = :sender_gather_funding_error_insufficient
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]
fee_A = 5000

#---------------------------------------------------------------------------------------------------------------------


# B investment = total_udt && fee < total_capacity
# both gather_funding and gather_fee
investment_A = BigDecimal((balance_A - 100).to_s)
investment_B = BigDecimal((balance_B).to_s)
expect = :receiver_gather_funding_success
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# B investment = total_udt && fee >total_capacity
# both gather_funding and gather_fee
fee_A = capacity_A + 1
investment_A = BigDecimal(balance_A.to_s)
investment_B = BigDecimal((balance_B).to_s)
expect = :receiver_gather_funding_error_insufficient
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]
fee_A = 5000

# here is the UDT version.
for record in investment_fee
  tests.preparation_before_test
  tests.check_investment_fee(record[0], record[1], record[2], record[3], record[4], "udt")
end