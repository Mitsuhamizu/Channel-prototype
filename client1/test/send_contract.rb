require "rubygems"
require "bundler/setup"
require "ckb"
require "json"

api = CKB::API.new
prikey = "d00c06bfd800d27397002dca6fb0993d5ba6399b4238b2f29ee9deb97593d2bc"
key = CKB::Key.new("0x" + prikey)
wallet = CKB::Wallet.from_hex(api, key.privkey)
data = File.read("main")
# data = File.read("carrot")

gpc_data_hash = CKB::Blake2b.hexdigest(data)

puts gpc_data_hash

gpc_tx_hash = wallet.send_capacity(wallet.address, CKB::Utils.byte_to_shannon(90000), CKB::Utils.bin_to_hex(data), fee: 10 ** 6)

puts gpc_tx_hash
