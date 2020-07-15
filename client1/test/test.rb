require "rubygems"
require "bundler/setup"
require "ckb"
require "json"

@api = CKB::API.new

tx = @api.get_transaction("0x9135a9e56b79d98336f428f80d397a1ab307f73daf4813c8906194fb92d4bf88").transaction
output = tx.outputs[0]
type = output.type
ser = CKB::Serializers::ScriptSerializer.new(type).serialize
puts output.calculate_min_capacity("0x")
puts ser.bytesize