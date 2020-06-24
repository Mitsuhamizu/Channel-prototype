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
fund_tx = @coll_sessions.find({ gpc_scirpt_hash: "0xd628e375884c5184d51257fef9b77e6fa560d835f826010579cd326407da2f93" }).first[:fund_tx]

fund_tx = CKB::Types::Transaction.from_h(fund_tx)
# puts get_total_capacity(fund_tx.inputs)

output_capa = 0
for output in fund_tx.outputs
  output_capa += output.capacity
  break
end

puts fund_tx.outputs[0].lock.compute_hash
# puts output_capa
hash = api.send_transaction(fund_tx)
puts hash
