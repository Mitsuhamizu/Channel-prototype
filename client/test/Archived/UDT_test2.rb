require "rubygems"
require "bundler/setup"
require "ckb"
require "json"

api = CKB::API.new

prikey = "0xd986d7bf901e50368cbe565f239c224934cd554805357338abcef177efadc08d"
key = CKB::Key.new(prikey)
wallet = CKB::Wallet.from_hex(api, key.privkey)

udt_tx_hash = "0xec4334e8a25b94f2cd71e0a2734b2424c159f4825c04ed8410e0bb5ee1dc6fe8"
udt_code_hash = "0x239c1c39cfb6e3b96c205688ebb59ac74a1d63440efca6f0c38d637e54c2c5e4"
udt_out_point = CKB::Types::CellDep.new(out_point: CKB::Types::OutPoint.new(tx_hash: udt_tx_hash, index: 0))

# input
previous_out_point = CKB::Types::OutPoint.new(tx_hash: "0xe57accd69b29e7464de144eec324005686c0f7063d3fe83d87445275603eb93d", index: 1)
inputs = CKB::Types::Input.new(
  previous_output: previous_out_point,
  since: 0,
)

inputs = [inputs]

# output
default_lock_1 = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                        args: "0xc6a8ae902ac272ea0ec6378f7ab8648f76979ce2", hash_type: CKB::ScriptHashType::TYPE)
default_lock_2 = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                        args: "0x96a11bf182b0e952f6fcc685b43ae50e13951b78", hash_type: CKB::ScriptHashType::TYPE)
# construct outputs and outputs data.

cell = api.get_live_cell(inputs[0].previous_output)
first_output = cell.cell.output
first_output.capacity /= 2
first_output.capacity -= 1000

second_output = first_output.dup

outputs = [first_output, second_output]

outputs_data = [CKB::Utils.bin_to_hex([50].pack("Q<")), CKB::Utils.bin_to_hex([51].pack("Q<"))]

tx = CKB::Types::Transaction.new(
  version: 0,
  cell_deps: [],
  inputs: inputs,
  outputs: outputs,
  outputs_data: outputs_data,
  witnesses: [CKB::Types::Witness.new],
)

tx.cell_deps << CKB::Types::CellDep.new(out_point: api.secp_code_out_point, dep_type: "code")
tx.cell_deps << CKB::Types::CellDep.new(out_point: api.secp_data_out_point, dep_type: "code")
tx.cell_deps << udt_out_point

first_output.lock = default_lock_1
second_output.lock = default_lock_2

signed_tx = tx.sign(wallet.key)
signed_tx.witnesses = [CKB::Types::Witness.new]
root_udt_tx_hash = api.send_transaction(signed_tx)
puts root_udt_tx_hash
