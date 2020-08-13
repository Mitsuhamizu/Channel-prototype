require_relative "../libs/gpctest.rb"
require "mongo"
require "bigdecimal"

Mongo::Logger.logger.level = Logger::FATAL
$VERBOSE = nil

# load the json
path = ARGV[0]
data_raw = File.read(path)
data_json = JSON.parse(data_raw, symbolize_names: true)

container_min = data_json[:container_min].to_i
funding_fee_A = data_json[:funding_fee_A].to_i
funding_fee_B = data_json[:funding_fee_B].to_i
funding_amount_A = data_json[:funding_amount_A].to_i
funding_amount_B = data_json[:funding_amount_B].to_i

# # prepare the test
tests = Gpctest.new("test")
tests.setup()

investment_A = BigDecimal(funding_amount_A) / 10 ** 8
investment_B = BigDecimal(funding_amount_B) / 10 ** 8
expect = data_json[:expect_info].to_sym
tests.check_investment_fee(investment_A, investment_B, funding_fee_A, funding_fee_B, expect, "ckb")

# # A investment + fee + 2 * container_min > total_capacity
# # both gather_funding and gather_fee
# # note: because the asset type is ckb. So if the gather_funding can not supply the amount
# # the gather_fee can not also. So there is only one case about it.
# investment_A = BigDecimal((balance_A - container_min - fee_A).to_s) / 10 ** 8
# investment_B = BigDecimal((balance_B - 10 ** 8 - fee_B).to_s) / 10 ** 8
# expect = :sender_gather_funding_error_insufficient
# investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# # A investment + fee + 2 * container_min < total_capacity
# # both gather_funding and gather_fee
# # the same about above case, here gather_fuding and gather_fee are binding.
# investment_A = BigDecimal((balance_A - container_min - fee_A - 1).to_s) / 10 ** 8
# investment_B = BigDecimal((balance_B - 10 ** 8 - fee_B).to_s) / 10 ** 8
# expect = :sender_gather_funding_success
# investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# # A investment = 0
# investment_A = BigDecimal(0.to_s)
# investment_B = BigDecimal((balance_B - 10 ** 8 - fee_B).to_s) / 10 ** 8
# expect = :sender_gather_funding_success
# investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# # A investment < 0
# investment_A = BigDecimal((-1).to_s) / 10 ** 8
# investment_B = BigDecimal((balance_B - 10 ** 8 - fee_B).to_s) / 10 ** 8
# expect = :sender_gather_funding_error_negtive
# investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# # A fee < 0
# fee_A = -1
# investment_A = BigDecimal((balance_A - container_min - fee_A - 1).to_s) / 10 ** 8
# investment_B = BigDecimal((balance_B - 10 ** 8 - fee_B).to_s) / 10 ** 8
# expect = :sender_gather_funding_error_negtive
# investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]
# fee_A = 5000

# #---------------------------------------------------------------------------------------------------------------------

# # B investment + fee + 2 * container_min > total_capacity
# # both gather_funding and gather_fee
# investment_A = BigDecimal((balance_A - container_min - fee_A).to_s) / 10 ** 8
# investment_B = BigDecimal((balance_B - container_min - fee_B + 1).to_s) / 10 ** 8
# expect = :receiver_gather_funding_error_insufficient
# investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# # B investment + fee + 2 * container_min < total_capacity
# # both gather_funding and gather_fee
# investment_A = BigDecimal((balance_A - container_min - fee_A).to_s) / 10 ** 8
# investment_B = BigDecimal((balance_B - container_min - fee_B - 1).to_s) / 10 ** 8
# expect = :receiver_gather_funding_success

# investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# # B investment < 0
# investment_A = BigDecimal((balance_A - container_min - fee_A).to_s) / 10 ** 8
# investment_B = BigDecimal((-1).to_s) / 10 ** 8
# expect = :receiver_gather_funding_error_negtive
# investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# # B investment = 0
# investment_A = BigDecimal(0.to_s) / 10 ** 8
# investment_B = BigDecimal((balance_B - 10 ** 8 - fee_B).to_s) / 10 ** 8
# expect = :receiver_gather_funding_success
# investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]

# # B fee < 0
# fee_B = -1
# investment_A = BigDecimal((balance_A - container_min - fee_A).to_s) / 10 ** 8
# investment_B = BigDecimal((balance_B - container_min - fee_B - 1).to_s) / 10 ** 8
# expect = :receiver_gather_funding_error_negtive
# investment_fee << [investment_A, investment_B, fee_A, fee_B, expect]
# fee_B = 5000

# counter = 0
# for record in investment_fee
#   puts record, counter
#   tests.preparation_before_test
#   tests.check_investment_fee(record[0], record[1], record[2], record[3], record[4], "ckb")
#   counter = counter + 1
# end
