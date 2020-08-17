require_relative "../libs/gpctest.rb"
require "mongo"
require "bigdecimal"

# A sends the establishmeng request to B.

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
expect = data_json[:expect_info]
tests.check_investment_fee(investment_A, investment_B, funding_fee_A, funding_fee_B, expect, "ckb")
