require "rubygems"
require "bundler/setup"
require "ckb"
require "json"

@api = CKB::API.new
tx_fund_file = File.new("./tx_to_be_reversed.json", "r")
tx_fund = tx_fund_file.sysread(50000)
tx_fund_file.close

tx_fund = JSON.parse(tx_fund, symbolize_names: true)
tx_fund = CKB::Types::Transaction.from_h(tx_fund)
tx_fund.header_deps = []
tx_hash = tx_fund.compute_hash
for output in tx_fund.outputs
  data = CKB::Serializers::OutputSerializer.new(output).serialize
  puts data
  # data = CKB::Blake2b.hexdigest(CKB::Utils.hex_to_bin(data))
  # type_hash = output.type.compute_hash
  # puts type_hash
end

# Just get the serilize of output.
# CKB::Serializers::OutputSerializer()
