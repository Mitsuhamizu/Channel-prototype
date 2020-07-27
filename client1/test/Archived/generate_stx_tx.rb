require "rubygems"
require "bundler/setup"
require "ckb"
require "json"
require "mongo"
require "../libs/tx_generator.rb"
Mongo::Logger.logger.level = Logger::FATAL

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

def json_to_info(json)
  info_h = JSON.parse(json, symbolize_names: true)
  info = info_h
  info[:outputs] = info_h[:outputs].map { |output| CKB::Types::Output.from_h(output) }
  return info
end

private_key = "0xd986d7bf901e50368cbe565f239c224934cd554805357338abcef177efadc08d"
@key = CKB::Key.new(private_key)
@api = CKB::API::new
@tx_generator = Tx_generator.new(@key)
@client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
@db = @client.database
@coll_sessions = @db[@key.pubkey + "_session_pool"]
stx_info = @coll_sessions.find({ gpc_scirpt_hash: "0xd628e375884c5184d51257fef9b77e6fa560d835f826010579cd326407da2f93" }).first[:stx]
stx_info = json_to_info(stx_info)

for output in stx_info[:outputs]
  output.lock.args = "0x" + output.lock.args
end
closing_tx_hash = "0xad8881060103c40cbf4ff804e39e3ebf0719193b86dc69fed10bf9bc037ef9f4"

out_point = CKB::Types::OutPoint.new(
  tx_hash: closing_tx_hash,
  index: 0,
)

settlement_input = CKB::Types::Input.new(
  previous_output: out_point,
  since: 100,
)

stx_info[:witness] = [stx_info[:witness]]
settlement_input = [settlement_input]

stx = @tx_generator.generate_settlement_tx(settlement_input, stx_info)

hash = @api.send_transaction(stx)
puts stx.compute_hash
# puts hash
