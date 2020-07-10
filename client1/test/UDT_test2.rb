require "rubygems"
require "bundler/setup"
require "ckb"
require "json"

api = CKB::API.new

prikey = "0xd986d7bf901e50368cbe565f239c224934cd554805357338abcef177efadc08d"
key = CKB::Key.new(prikey)
wallet = CKB::Wallet.from_hex(api, key.privkey)

udt_tx_hash = "0xb0e1ade40b8a12edaf9ae4521dac6594da3d7527666fcc687a5f421856a7e45e"
udt_code_hash = "0x2a02e8725266f4f9740c315ac7facbcc5d1674b3893bd04d482aefbb4bdfdd8a"
udt_out_point = CKB::Types::CellDep.new(out_point: CKB::Types::OutPoint.new(tx_hash: udt_tx_hash, index: 0))

# input
previous_out_point = CKB::Types::OutPoint.new(tx_hash: "0x518cb3a242df69a90c9da8b68f1fa537038321c09e1a0b6bcb90e35764649993", index: 0)
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

outputs_data = [CKB::Utils.bin_to_hex([50].pack("Q<")), CKB::Utils.bin_to_hex([50].pack("Q<"))]

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
# signed_tx.witnesses = [CKB::Types::Witness.new]
root_udt_tx_hash = api.send_transaction(signed_tx)
puts root_udt_tx_hash
