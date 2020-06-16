require "rubygems"
require "bundler/setup"
require "ckb"
require "json"

private_key = "82dede298f916ced53bf5aa87cea8a7e44e8898eaedcff96606579f7bf84d99d"
api = CKB::API.new

data = File.read("data.txt").strip
data = CKB::Blake2b.hexdigest(CKB::Utils.hex_to_bin("0x" + data))
# puts data
key = CKB::Key.new("0x" + private_key)
signature = key.sign_recoverable(data)


puts CKB::Key.blake160(CKB::Key.pubkey("0x"+private_key))
# puts CKB::Key.pubkey("0x"+private_key))

puts signature
