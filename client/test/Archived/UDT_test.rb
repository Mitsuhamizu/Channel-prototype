require "rubygems"
require "bundler/setup"
require "ckb"
require "json"

api = CKB::API.new

prikey = "0xd00c06bfd800d27397002dca6fb0993d5ba6399b4238b2f29ee9deb97593d2bc"
key = CKB::Key.new(prikey)
wallet = CKB::Wallet.from_hex(api, key.privkey)

udt_tx_hash = "0xec4334e8a25b94f2cd71e0a2734b2424c159f4825c04ed8410e0bb5ee1dc6fe8"
udt_code_hash = "0x239c1c39cfb6e3b96c205688ebb59ac74a1d63440efca6f0c38d637e54c2c5e4"
udt_out_point = CKB::Types::CellDep.new(out_point: CKB::Types::OutPoint.new(tx_hash: udt_tx_hash, index: 0))
tx = wallet.generate_tx(wallet.address, CKB::Utils.byte_to_shannon(20000), fee: 1000)
tx.cell_deps.push(udt_out_point.dup)

# get type script.
for input in tx.inputs
  cell = api.get_live_cell(input.previous_output)
  next if cell.status != "live"
  input_lock = cell.cell.output.lock
  input_lock_ser = input_lock.compute_hash
  type_script = CKB::Types::Script.new(code_hash: udt_code_hash,
                                       args: input_lock_ser, hash_type: CKB::ScriptHashType::DATA)
end

default_lock_1 = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                        args: "0xc6a8ae902ac272ea0ec6378f7ab8648f76979ce2", hash_type: CKB::ScriptHashType::TYPE)
default_lock_2 = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                        args: "0x96a11bf182b0e952f6fcc685b43ae50e13951b78", hash_type: CKB::ScriptHashType::TYPE)
# construct outputs and outputs data.

outputs = tx.outputs
first_output = outputs[0]
first_output.capacity /= 2
first_output.type = type_script
second_output = first_output.dup

first_output.lock = default_lock_1
second_output.lock = default_lock_2

tx.outputs.delete_at(0)
tx.outputs.insert(0, first_output)
tx.outputs.insert(0, second_output)

tx.outputs_data[0] = CKB::Utils.bin_to_hex([100].pack("Q<"))
tx.outputs_data[1] = CKB::Utils.bin_to_hex([200].pack("Q<"))
tx.outputs_data << "0x"
signed_tx = tx.sign(wallet.key)
root_udt_tx_hash = api.send_transaction(signed_tx)
puts root_udt_tx_hash
