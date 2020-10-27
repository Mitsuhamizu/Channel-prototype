require_relative "../libs/initialization.rb"
require_relative "../libs/communication.rb"
require_relative "../libs/chain_monitor.rb"
require "mongo"
require "thor"
Mongo::Logger.logger.level = Logger::FATAL

def hash_to_info(info_h)
  info_h[:outputs] = info_h[:outputs].map { |output| CKB::Types::Output.from_h(output) }
  return info_h
end

def parse_lock_args(args_ser)
  id = args_ser[2..33]
  assemble_result = "0x" + args_ser[34..67]
  assemble_result = CKB::Utils.hex_to_bin(assemble_result)
  pubkey_A = args_ser[68..107]
  pubkey_B = args_ser[108, 147]
  result = assemble_result.unpack("cQQ")
  result = { id: id, status: result[0], timeout: result[1], nounce: result[2], pubkey_A: pubkey_A, pubkey_B: pubkey_B }
  return result
end

def parse_witness_lock(lock)
  assemble_result = CKB::Utils.hex_to_bin("0x" + lock[34..51])
  result = assemble_result.unpack("cQ")
  result = { id: lock[2..33], flag: result[0], nounce: result[1], sig_A: lock[52..181], sig_B: lock[182..311] }
  return result
end
private_key = "0x85ce75a6b678c6930a4f0938588f0240784971bb03632f1a2f1b25102b7cf5f0"
# private_key = "0x63d86723e08f0f813a36ce6aa123bb2289d90680ae1e99d4de8cdb334553f24d"
id = "702fae0cf50868ae1349e94c755c0f83"

@key = CKB::Key.new(private_key)
@client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
@db = @client.database
@coll_sessions = @db[@key.pubkey + "_session_pool"]
ctx_info = hash_to_info(JSON.parse(@coll_sessions.find({ id: id }).first[:ctx_info], symbolize_names: true))
stx_info = hash_to_info(JSON.parse(@coll_sessions.find({ id: id }).first[:stx_info], symbolize_names: true))
remote_pubkey = @coll_sessions.find({ id: id }).first[:remote_pubkey]
local_pubkey = @coll_sessions.find({ id: id }).first[:local_pubkey]
# @tx_generator = Tx_generator.new(@key)
# fund_tx = @coll_sessions.find({ id: id }).first[:fund_tx]
# fund_tx = CKB::Types::Transaction.from_h(fund_tx)
# puts verify_info_sig(ctx_info, "closing", remote_pubkey, 0)
# puts verify_info_sig(ctx_info, "closing", local_pubkey, 1)

# witness = @tx_generator.parse_witness(ctx_info[:witnesses][0])
witness = parse_witness(ctx_info[:witnesses][0])
parsed_lock = parse_witness_lock(witness.lock)

puts parsed_lock

# @secp_args = "0xf261ea0fca37e5dbaf797640d36d382ca66c22f5"
# @secp_args = "0x470dcdc5e44064909650113a274b3b36aecb6dc7"
# @default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
#                                        args: @secp_args, hash_type: CKB::ScriptHashType::TYPE)

# puts fund_tx.outputs[0].lock.compute_hash
