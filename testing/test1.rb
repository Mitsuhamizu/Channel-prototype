require "./libs/gpctest.rb"
require "./libs/types.rb"
require "mongo"
require "json"
# require "open4"

Mongo::Logger.logger.level = Logger::FATAL
$VERBOSE = nil

secp_args_A = "0x470dcdc5e44064909650113a274b3b36aecb6dc7"
private_key_A = "0x63d86723e08f0f813a36ce6aa123bb2289d90680ae1e99d4de8cdb334553f24d"
pubkey_A = "0x038d3cfceea4f9c2e76c5c4f5e99aec74c26d6ac894648b5700a0b71f91f9b5c2a"

secp_args_B = "0xc8328aabcd9b9e8e64fbc566c4385c3bdeb219d7"
private_key_B = "0xd00c06bfd800d27397002dca6fb0993d5ba6399b4238b2f29ee9deb97593d2bc"
pubkey_B = "0x03fe6c6d09d1a0f70255cddf25c5ed57d41b5c08822ae710dc10f8c88290e0acdf"

# create databse.
@client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
@db = @client.database
@db.drop()

@client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
@db = @client.database

# finish the setup work.
test1 = Gpctest.new("test")
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
                                        args: secp_args_A, hash_type: CKB::ScriptHashType::TYPE)
default_lock_B = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                        args: secp_args_B, hash_type: CKB::ScriptHashType::TYPE)

lock_hashes_A = [default_lock_A.compute_hash]
lock_hashes_B = [default_lock_B.compute_hash]

# printing the current balance of A and B.
balance_begin_A = test1.get_balance(lock_hashes_A, type_script_hash, type_info[:decoder])
balance_begin_B = test1.get_balance(lock_hashes_B, type_script_hash, type_info[:decoder])
# balance_begin_A =test1.get_balance(lock_hashes_A)
# balance_begin_B =test1.get_balance(lock_hashes_B)

listen_port_A = 1000
listen_port_B = 2000
fee_A = 4000
fee_B = 2000
funding_A = balance_begin_A
funding_B = 100
since = "9223372036854775908"

# prepare the commands.
commands = { sender_reply: "yes", recv_reply: "yes", recv_fund: funding_B, recv_fee: fee_B, sender_one_way_permission: "yes" }
file = File.new("./files/commands.json", "w")
file.syswrite(commands.to_json)
file.close()

spawn ("ruby ../client1/GPC init #{private_key_A}")
spawn ("ruby ../client1/GPC init #{private_key_B}")

monitor_A = spawn("ruby ../client1/GPC monitor #{pubkey_A}")
monitor_B = spawn("ruby ../client1/GPC monitor #{pubkey_B}")

# Create channel
listener_B = spawn("ruby ../client1/GPC listen #{pubkey_B} #{listen_port_B}")

# give enough time for listener to start.
sleep(2)

sender_A = spawn("ruby ../client1/GPC send_establishment_request --pubkey #{pubkey_A} --ip 127.0.0.1 --port #{listen_port_B} --amount #{funding_A} --fee #{fee_A} --since #{since} --type_script_hash #{type_script_hash}")

Process.wait sender_A

balance_after_funding_A = test1.get_balance(lock_hashes_A, type_script_hash, type_info[:decoder])
balance_after_funding_B = test1.get_balance(lock_hashes_B, type_script_hash, type_info[:decoder])

test1.assert_equal(funding_A, balance_begin_A - balance_after_funding_A, "funding not right")
system("kill #{monitor_A}")
system("kill #{monitor_B}")
system("kill #{listener_B}")

# making payments

# closing

# keep reading when the settlement onchain
# listener_A.exit
# listener_B.exit

# delete database
@db.drop()
