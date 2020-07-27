require "rubygems"
require "bundler/setup"
require "ckb"
require "json"
require "mongo"
Mongo::Logger.logger.level = Logger::FATAL

api = CKB::API.new

def get_total_capacity(cells)
  api = CKB::API.new
  total_capacity = 0
  for cell in cells
    validation = api.get_live_cell(cell.previous_output)
    total_capacity += validation.cell.output.capacity
    if validation.status != "live"
      return -1
    end
  end
  return total_capacity
end

private_key = "0xd986d7bf901e50368cbe565f239c224934cd554805357338abcef177efadc08d"
@key = CKB::Key.new(private_key)
@client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
@db = @client.database
@coll_sessions = @db[@key.pubkey + "_session_pool"]
fund_tx = @coll_sessions.find({ gpc_script: "0x7e0000001000000030000000310000006d44e8e6ebc76927a48b581a0fb84576f784053ae9b53b8c2a20deafca5c4b7b00490000006356544db6ff06861dfb2587df9918160064000000000000000000000000000000c6a8ae902ac272ea0ec6378f7ab8648f76979ce296a11bf182b0e952f6fcc685b43ae50e13951b78" }).first[:fund_tx]
fund_tx = CKB::Types::Transaction.from_h(fund_tx)
# puts get_total_capacity(fund_tx.inputs)

output_capa = 0
for output in fund_tx.outputs
  output_capa += output.capacity
  break
end

# puts fund_tx.outputs[0].lock.compute_hash

# puts output_capa
hash = api.send_transaction(fund_tx)
puts hash
