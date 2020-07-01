require "rubygems"
require "bundler/setup"
require "ckb"
require "json"
require "mongo"
require "../libs/tx_generator.rb"
require "../libs/ckb_interaction.rb"

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
@wallet = CKB::Wallet.from_hex(@api, @key.privkey)
@tx_generator = Tx_generator.new(@key)
@client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
@db = @client.database
@coll_sessions = @db[@key.pubkey + "_session_pool"]
ctx_info = @coll_sessions.find({ gpc_script: "0x7e0000001000000030000000310000006d44e8e6ebc76927a48b581a0fb84576f784053ae9b53b8c2a20deafca5c4b7b0049000000def717339e3cf9a98f7f5f172f41d4530064000000000000000000000000000000c6a8ae902ac272ea0ec6378f7ab8648f76979ce296a11bf182b0e952f6fcc685b43ae50e13951b78" }).first[:ctx]
ctx_info = json_to_info(ctx_info)
local_pubkey = CKB::Key.blake160(@key.pubkey)
local_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                            args: local_pubkey, hash_type: CKB::ScriptHashType::TYPE)

fund_tx_hash = "0xea44ca05b726397d7a4bfe8fe5906a89fa7ce6888096d63df05f8394f3ddd22c"

capa = 61

fee_cell = gather_inputs(capa, 100000)

local_change_output = CKB::Types::Output.new(
  capacity: capa,
  lock: local_default_lock,
  type: nil,
)

out_point = CKB::Types::OutPoint.new(
  tx_hash: fund_tx_hash,
  index: 0,
)

closing_input = CKB::Types::Input.new(
  previous_output: out_point,
  since: 0,
)

local_pubkey = CKB::Key.blake160(@key.pubkey)
closing_input = [closing_input, fee_cell.inputs[0]]

ctx = @tx_generator.generate_closing_tx(closing_input, ctx_info)
# puts ctx.outputs[0].lock.compute_hash
hash = @api.send_transaction(ctx)
# puts hash
# CKB::MockTransactionDumper.new(@api, ctx).write("../ckb-gpc-contract/ckb-standalone-debugger/bins//GPC.json")
# CKB::MockTransactionDumper.new(@api, ctx).write("./ckb-standalone-debugger/bins/GPC.json")
