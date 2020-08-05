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
# tests.test1()

# party_stage_type_info.
# 519873491499995001

# here is the ckb version.
investment_fee = []
tests.preparation_before_test()
balance_A, balance_B = tests.get_account_balance_ckb()
# 1. test the investment
base = 2 * 61 * 10 ** 8
fee_A = 5000
fee_B = 5000

# 1.1 A investment + fee + 2 * base_capacity > total_capacity
puts balance_A - base - fee_A + 1
investment_A = BigDecimal((balance_A - base - fee_A + 1).to_s) / 10 ** 8
investment_B = (balance_B - 10 ** 8 - fee_B).to_f / 10 ** 8
error_type = :sender_gather_funding_error_insufficient
investment_fee << [investment_A, investment_B, fee_A, fee_B, error_type]
# # 1.2 A investment + fee + 2 * base_capacity < total_capacity
# investment_A = (balance_A - base - fee_A - 1).to_f / 10 ** 8
# investment_B = (balance_B - 10 ** 8 - fee_B).to_f / 10 ** 8
# success_type = :sender_gather_funding_success
# investment_fee << [investment_A, investment_B, fee_A, fee_B, success_type]
# # 1.3 A investment + fee + 2 * base_capacity == total_capacity
# investment_A = (balance_A - base - fee_A).to_f / 10 ** 8
# investment_B = (balance_B - 10 ** 8 - fee_B).to_f / 10 ** 8
# error_type = :sender_gather_funding_success1
# investment_fee << [investment_A, investment_B, fee_A, fee_B, error_type]

# 1.4 B investment + fee + 2 * base_capacity > total_capacity
# 1.5 B investment + fee + 2 * base_capacity < total_capacity
# 1.6 B investment + fee + 2 * base_capacity == total_capacity

# here is the UDT version.
for record in investment_fee
  record_error({})
  record_success({})
  tests.check_investment_fee(record[0], record[1], record[2], record[3], record[4], "ckb")
end
# tests.test3()
# tests.test4()
# tests.test5()
