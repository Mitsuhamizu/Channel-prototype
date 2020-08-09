require "./libs/gpctest.rb"
require "mongo"
require "bigdecimal"

def record_error(msg)
  file = File.new("./files/errors.json", "w")
  file.syswrite(msg.to_json)
  file.close()
end

def record_success(msg)
  file = File.new("./files/successes.json", "w")
  file.syswrite(msg.to_json)
  file.close()
end

Mongo::Logger.logger.level = Logger::FATAL
$VERBOSE = nil

tests = Gpctest.new("test")

# here is the ckb version.
investment_fee = []
tests.preparation_before_test()
balance_A, balance_B = tests.get_account_balance_udt()
capacity_A, capacity_B = tests.get_account_balance_ckb()

# test the investment
fee_A = 5000
fee_B = 5000

# A investment  > total_udt
investment_A = BigDecimal((balance_A + 1).to_s)
investment_B = BigDecimal((balance_B - 100).to_s)
expect = :sender_gather_funding_error_insufficient
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# A investment = total_udt && fee < total_capacity
investment_A = BigDecimal(balance_A.to_s)
investment_B = BigDecimal((balance_B - 100).to_s)
expect = :sender_gather_funding_success
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# A investment = total_udt && fee >total_capacity
fee_A = capacity_A + 1
investment_A = BigDecimal(balance_A.to_s)
investment_B = BigDecimal((balance_B - 100).to_s)
expect = :sender_gather_funding_error_insufficient
investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]
fee_A = 5000

# # A investment + fee + 2 * base_capacity < total_capacity
# investment_A = BigDecimal((balance_A - base - fee_A - 1).to_s) / 10 ** 8
# investment_B = BigDecimal((balance_B - 10 ** 8 - fee_B).to_s) / 10 ** 8
# success_type = :sender_gather_funding_success
# investment_fee << [investment_A, investment_B, fee_A, fee_B, success_type]

# # A investment + fee + 2 * base_capacity == total_capacity
# investment_A = BigDecimal((balance_A - base - fee_A).to_s) / 10 ** 8
# investment_B = BigDecimal((balance_B - 10 ** 8 - fee_B).to_s) / 10 ** 8
# error_type = :sender_gather_funding_success
# investment_fee << [investment_A, investment_B, fee_A, fee_B, error_type]
# # A investment < 0
# investment_A = BigDecimal((-1).to_s) / 10 ** 8
# investment_B = BigDecimal((balance_B - 10 ** 8 - fee_B).to_s) / 10 ** 8
# error_type = :sender_gather_funding_error_negtive
# investment_fee << [investment_A, investment_B, fee_A, fee_B, error_type]

# # B investment + fee + 2 * base_capacity > total_capacity
# investment_A = BigDecimal((balance_A - base - fee_A).to_s) / 10 ** 8
# investment_B = BigDecimal((balance_B - base - fee_B + 1).to_s) / 10 ** 8
# error_type = :receiver_gather_funding_error_insufficient
# investment_fee << [investment_A, investment_B, fee_A, fee_B, error_type]

# # B investment + fee + 2 * base_capacity < total_capacity
# investment_A = BigDecimal((balance_A - base - fee_A).to_s) / 10 ** 8
# investment_B = BigDecimal((balance_B - base - fee_B - 1).to_s) / 10 ** 8
# error_type = :receiver_gather_funding_error_insufficient
# investment_fee << [investment_A, investment_B, fee_A, fee_B, error_type]

# # B investment + fee + 2 * base_capacity == total_capacity
# investment_A = BigDecimal((balance_A - base - fee_A).to_s) / 10 ** 8
# investment_B = BigDecimal((balance_B - base - fee_B).to_s) / 10 ** 8
# error_type = :receiver_gather_funding_error_insufficient
# investment_fee << [investment_A, investment_B, fee_A, fee_B, error_type]

# # B investment + fee + 2 * base_capacity == total_capacity
# investment_A = BigDecimal((balance_A - base - fee_A).to_s) / 10 ** 8
# investment_B = BigDecimal((-1).to_s) / 10 ** 8
# error_type = :receiver_gather_funding_error_negtive
# investment_fee << [investment_A, investment_B, fee_A, fee_B, error_type]

# here is the UDT version.
for record in investment_fee
  tests.check_investment_fee(record[0], record[1], record[2], record[3], record[4], "udt")
end
# tests.test3()
# tests.test4()
# tests.test5()
