require "rubygems"
require "bundler/setup"
require "ckb"
require "json"
require "secp256k1"

privkey = "0x82dede298f916ced53bf5aa87cea8a7e44e8898eaedcff96606579f7bf84d99d"
api = CKB::API.new
key = CKB::Key.new(privkey)

class MyECDSA < Secp256k1::BaseKey
  include Secp256k1::Utils, Secp256k1::ECDSA

  def initialize
    super(nil, Secp256k1::ALL_FLAGS)
  end
end

# data = File.read("data.txt").strip
# data = File.read("data2.txt").strip
# data = CKB::Blake2b.hexdigest(CKB::Utils.hex_to_bin("0x" + data))

# puts data
data = "0x11"

data = CKB::Blake2b.hexdigest(data)
unrelated = MyECDSA.new
privkey_bin = CKB::Utils.hex_to_bin(privkey)
secp_key = Secp256k1::PrivateKey.new(privkey: privkey_bin)

signature_bin, recid = secp_key.ecdsa_recoverable_serialize(
  secp_key.ecdsa_sign_recoverable(CKB::Utils.hex_to_bin(data), raw: true)
)
sig = CKB::Utils.bin_to_hex(signature_bin + [recid].pack("C*"))

signature_bin_new = CKB::Utils.hex_to_bin("0x" + sig[2..129])
recid_new = CKB::Utils.hex_to_bin("0x" + sig[130..131]).unpack("C*")[0]

# given data and sig, verify.
sig_reverse = unrelated.ecdsa_recoverable_deserialize(signature_bin, recid)
pubkey = unrelated.ecdsa_recover(CKB::Utils.hex_to_bin(data), sig_reverse, raw: true)

pubser = Secp256k1::PublicKey.new(pubkey: pubkey).serialize
result = CKB::Utils.bin_to_hex(pubser)
puts result

puts "0x02ce9deada91368642e7b4343dea5046cb7f1553f71cab363daa32aa6fcea17648"
# pubkey=Secp256k1::PublicKey.new(pubkey: pubkey)
# result = pubkey.read_string
# puts CKB::Utils.bin_to_hex(result)
# pubkey = unrelated.ecdsa_recover CKB::Utils.hex_to_bin(data), sig_reverse

# pubser = Secp256k1::PublicKey.new(pubkey: pubkey).serialize
# # pubser = Secp256k1::PublicKey.new(pubkey: pubkey)

# puts pubser
# puts CKB::Utils.hex_to_bin(key.pubkey)
puts key.pubkey
# puts key.sign_recoverable(data)

# puts
# signature = key.sign_recoverable(data)

# puts CKB::Key.pubkey("0x" + private_key)
# @key = CKB::Key.new("0x" + private_key)
# puts @key.pubkey
