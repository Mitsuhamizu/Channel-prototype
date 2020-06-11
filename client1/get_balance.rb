require "rubygems"
require "bundler/setup"
require "ckb"

api = CKB::API.new

private_key1 = "0xd986d7bf901e50368cbe565f239c224934cd554805357338abcef177efadc08d"
private_key2 = "0x82dede298f916ced53bf5aa87cea8a7e44e8898eaedcff96606579f7bf84d99d"
# private_key = "0xd00c06bfd800d27397002dca6fb0993d5ba6399b4238b2f29ee9deb97593d2bc"

sender = CKB::Wallet.from_hex(api, private_key1)
receiver = CKB::Wallet.from_hex(api, private_key2)

# puts sender.address
# puts receiver.address
tx = sender.generate_tx(receiver.address, CKB::Utils.byte_to_shannon(100), fee: 5000)

# wallet = CKB::Wallet.from_hex(api, CKB::Key.random_private_key) # 新钱包
# wallet2 = CKB::Wallet.from_hex(api, CKB::Key.random_private_key) # 新钱包

# miner.send_capacity(wallet.address, 10000*(10**8), fee: 1000) # 转账

# data = File.read("carrot")

# data.bytesize # 此处字节长度是 7765，字符串的长度，以字节为单位

# carrot_tx_hash = wallet.send_capacity(wallet.address, CKB::Utils.byte_to_shannon(8000), CKB::Utils.bin_to_hex(data), fee: 10**6)
