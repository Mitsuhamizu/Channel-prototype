require "./libs/gpctest.rb"
require "mongo"
require "bigdecimal"

Mongo::Logger.logger.level = Logger::FATAL
$VERBOSE = nil

tests = Gpctest.new("test")

# here is the ckb version.
investment_fee = []
tests.preparation_before_test()
balance_A, balance_B = tests.get_account_balance_ckb()
# 1. test the investment
base = 2 * 61 * 10 ** 8
fee_A = 5000
fee_B = 5000

# For the first five testings, it is unnecessary to care about the amount of B's funding.

# A investment + fee + 2 * base_capacity > total_capacity
# both gather_funding and gather_fee
# note: because the asset type is ckb. So if the gather_funding can not supply the amount
# the gather_fee can not also. So there is only one case about it.
investment_A = BigDecimal((balance_A - base - fee_A + 1).to_s) / 10 ** 8
investment_B = BigDecimal((balance_B - 10 ** 8 - fee_B).to_s) / 10 ** 8
expect = :sender_gather_funding_error_insufficient
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# A investment + fee + 2 * base_capacity < total_capacity
# both gather_funding and gather_fee
# the same about above case, here gather_fuding and gather_fee are binding.
investment_A = BigDecimal((balance_A - base - fee_A - 1).to_s) / 10 ** 8
investment_B = BigDecimal((balance_B - 10 ** 8 - fee_B).to_s) / 10 ** 8
expect = :sender_gather_funding_success
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# A investment = 0
investment_A = BigDecimal(0.to_s)
investment_B = BigDecimal((balance_B - 10 ** 8 - fee_B).to_s) / 10 ** 8
expect = :sender_gather_funding_success
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# A investment < 0
investment_A = BigDecimal((-1).to_s) / 10 ** 8
investment_B = BigDecimal((balance_B - 10 ** 8 - fee_B).to_s) / 10 ** 8
expect = :sender_gather_funding_error_negtive
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# A fee < 0
fee_A = -1
investment_A = BigDecimal((balance_A - base - fee_A - 1).to_s) / 10 ** 8
investment_B = BigDecimal((balance_B - 10 ** 8 - fee_B).to_s) / 10 ** 8
expect = :sender_gather_funding_error_negtive
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]
fee_A = 5000

#---------------------------------------------------------------------------------------------------------------------

# B investment + fee + 2 * base_capacity > total_capacity
# both gather_funding and gather_fee
investment_A = BigDecimal((balance_A - base - fee_A).to_s) / 10 ** 8
investment_B = BigDecimal((balance_B - base - fee_B + 1).to_s) / 10 ** 8
expect = :receiver_gather_funding_error_insufficient
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# B investment + fee + 2 * base_capacity < total_capacity
# both gather_funding and gather_fee
investment_A = BigDecimal((balance_A - base - fee_A).to_s) / 10 ** 8
investment_B = BigDecimal((balance_B - base - fee_B - 1).to_s) / 10 ** 8
expect = :receiver_gather_funding_success

investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# B investment < 0
investment_A = BigDecimal((balance_A - base - fee_A).to_s) / 10 ** 8
investment_B = BigDecimal((-1).to_s) / 10 ** 8
expect = :receiver_gather_funding_error_negtive
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# B investment = 0
investment_A = BigDecimal(0.to_s) / 10 ** 8
investment_B = BigDecimal((balance_B - 10 ** 8 - fee_B).to_s) / 10 ** 8
expect = :receiver_gather_funding_success
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# B fee < 0
fee_B = -1
investment_A = BigDecimal((balance_A - base - fee_A).to_s) / 10 ** 8
investment_B = BigDecimal((balance_B - base - fee_B - 1).to_s) / 10 ** 8
expect = :receiver_gather_funding_error_negtive
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]
fee_B = 5000

counter = 0
for record in investment_fee
  puts record, counter
  tests.preparation_before_test
  tests.check_investment_fee(record[0], record[1], record[2], record[3], record[4], "ckb")
  counter = counter + 1
end
