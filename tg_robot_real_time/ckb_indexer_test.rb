require "./miscellaneous/libs/setup.rb"

@api = CKB::API::new
@rpc = CKB::RPC.new(host: "http://localhost:8116", timeout_config: {})

# @secp_args = "0xf261ea0fca37e5dbaf797640d36d382ca66c22f5"
@secp_args = "0x470dcdc5e44064909650113a274b3b36aecb6dc7"
@default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                       args: @secp_args, hash_type: CKB::ScriptHashType::TYPE)
search_key = { script: @default_lock.to_h, script_type: "lock" }

cells_indexer = @rpc.get_cells(search_key, "asc", "0x64")

cells_api = @api.get_cells_by_lock_hash(@default_lock.compute_hash, 0, 60000000)
puts cells[:objects][0]
