require "rubygems"
require "bundler/setup"
require "ckb"
require "json"

@api = CKB::API.new

tx = @api.get_transaction("0xb5d46715b12ce9e32411efce95ea773afc9cf97045947f30b4f21122903b9e9a").transaction
output = tx.outputs[0]
puts CKB::Serializers::OutputSerializer.new(output).serialize
# lock = output.lock
# puts lock.compute_hash
# type = output.type
# ser = CKB::Serializers::ScriptSerializer.new(type).serialize
# puts output.calculate_min_capacity("0x")
# puts ser.bytesize
