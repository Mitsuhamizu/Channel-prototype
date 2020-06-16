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
puts tx_hash
