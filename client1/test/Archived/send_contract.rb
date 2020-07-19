require "rubygems"
require "bundler/setup"
require "ckb"
require "json"

api = CKB::API.new

# here, you need to set the private key to you local account.
prikey = "0xd00c06bfd800d27397002dca6fb0993d5ba6399b4238b2f29ee9deb97593d2bc"
key = CKB::Key.new(prikey)
wallet = CKB::Wallet.from_hex(api, key.privkey)

# read the contract.
data = File.read("../binary/main")
gpc_data_hash = CKB::Blake2b.hexdigest(data)
gpc_tx_hash = wallet.send_capacity(wallet.address, CKB::Utils.byte_to_shannon(100000), CKB::Utils.bin_to_hex(data), fee: 10 ** 6)

puts gpc_data_hash
puts gpc_tx_hash
