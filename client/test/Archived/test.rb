#!/usr/bin/ruby
require "rubygems"
require "bundler/setup"
require "ckb"
require "mongo"

api = CKB::API.new

# here, you need to set the private key to you local account.
prikey = "0xd00c06bfd800d27397002dca6fb0993d5ba6399b4238b2f29ee9deb97593d2bc"
key = CKB::Key.new(prikey)
wallet = CKB::Wallet.from_hex(api, key.privkey)

previous_tx_hash = "0x113048f8aae47361f44cead782d53c6a9348a1d4e3664961c147d0de6103dcf5"
# read the contract.
gpc_tx_hash = wallet.send_capacity(wallet.address, CKB::Utils.byte_to_shannon(100), fee: 0)
# previous_tx = api.get_transaction(previous_tx_hash)
# puts previous_tx.transaction.hash
# puts previous_tx.tx_status.status
# puts gpc_tx_hash
