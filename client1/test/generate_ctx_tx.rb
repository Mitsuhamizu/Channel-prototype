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
ctx_info = @coll_sessions.find({ gpc_scirpt_hash: "0xd628e375884c5184d51257fef9b77e6fa560d835f826010579cd326407da2f93" }).first[:ctx]
ctx_info = json_to_info(ctx_info)

# fund_tx_hash = "0x344343259038179e1e2a530890a3452e1a6a2c0f8916b2484936d555f06ffadb"
fund_tx_hash = "0x2dd1f002f43681faaf38db12d29e3b80c7262982344c60ef9bd150192114a558"

out_point = CKB::Types::OutPoint.new(
  tx_hash: fund_tx_hash,
  index: 0,
)

closing_input = CKB::Types::Input.new(
  previous_output: out_point,
  since: 0,
)
closing_input = [closing_input]

ctx_info[:witness] = [ctx_info[:witness]]

ctx = @tx_generator.generate_closing_tx(closing_input, ctx_info)
# puts ctx.outputs[0].lock.compute_hash
hash = @api.send_transaction(ctx)
puts hash
# CKB::MockTransactionDumper.new(@api, ctx).write("../GPC/ckb-standalone-debugger/bins/GPC.json")
# CKB::MockTransactionDumper.new(@api, ctx).write("./ckb-standalone-debugger/bins/GPC.json")
