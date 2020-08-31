require "rubygems"
require "bundler/setup"
require "ckb"
require "json"

@api = CKB::API.new

tx = @api.get_transaction("0xb995c493f02090311dc82ca824124f8edab99fd2855c9c1e56b5c73a793fb2d9").transaction
puts tx.to_h.to_json
# lock = output.lock
# puts lock.compute_hash
# type = output.type
# ser = CKB::Serializers::ScriptSerializer.new(type).serialize
# puts output.calculate_min_capacity("0x")
# puts ser.bytesize
