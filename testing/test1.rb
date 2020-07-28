require "./libs/minitest.rb"
require "./libs/types.rb"
require "json"

# finish the setup work.
test1 = Minitest.new()
test1.setup

# load the type script and lock script.

# type of asset.
data_raw = File.read("./files/contract_info.json")
data_json = JSON.parse(data_raw, symbolize_names: true)
type_script_json = data_json[:type_script]
type_script_h = JSON.parse(type_script_json, symbolize_names: true)
type_script = CKB::Types::Script.from_h(type_script_h)
type_script_hash = type_script.compute_hash
type_info = find_type(type_script_hash)

# locks
default_lock_A = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                        args: "0xc8328aabcd9b9e8e64fbc566c4385c3bdeb219d7", hash_type: CKB::ScriptHashType::TYPE)
default_lock_B = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                        args: "0x470dcdc5e44064909650113a274b3b36aecb6dc7", hash_type: CKB::ScriptHashType::TYPE)

lock_hashes_A = [default_lock_A.compute_hash]
lock_hashes_B = [default_lock_B.compute_hash]

# printing the current balance of A and B.
balance_begin_A = test1.get_balance(lock_hashes_A, type_script_hash, type_info[:decoder])
balance_begin_B = test1.get_balance(lock_hashes_B, type_script_hash, type_info[:decoder])
# balance_begin_A =test1.get_balance(lock_hashes_A)
# balance_begin_B =test1.get_balance(lock_hashes_B)

# run monitor
# run listener

# prepare the commands.
commands = { sender_reply: "yes", recv_reply: "yes", recv_fund: "100", recv_fee: "1000" }
file = File.new("./files/commands.json", "w")
file.syswrite(commands.to_json)
file.close()

system("ruby ../client1/GPC")
# Create channel

# making payments

# closing

# keep reading when the settlement onchain
