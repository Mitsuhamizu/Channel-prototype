require "rubygems"
require "bundler/setup"
require "ckb"
require "json"

api = CKB::API.new

def assemble(flag, version)
  result = [flag, version].pack("cQ")
  result = CKB::Utils.bin_to_hex(result)[2..-1]
  return result
end

def assemble_lock_args(status, timeout, nounce)
  result = [status, timeout, nounce].pack("cQQ")
  result = CKB::Utils.bin_to_hex(result)[2..-1]
  return result
end

prikey_A = "82dede298f916ced53bf5aa87cea8a7e44e8898eaedcff96606579f7bf84d99d"
prikey_B = "d986d7bf901e50368cbe565f239c224934cd554805357338abcef177efadc08d"

sig_A = "d2796881aa3e78dada2df5070809c7ab35ec64053c6bfe6bcb4539c7bcf90caf76261ab06a3ffee971a3759da71c4d39c0e06a64658fd40cfb4a407dc17b33a001"
# sig_B = "5dd2876d6b464d9e57337440b2cd6fdf30207d031532d53eb62853eedcd82b2d275715bae3c55ffa9fbc79841a99ae18b44db72ee8ae3ebd49832befe7a9872700"
# sig_A = "00" * 65
sig_B = "00" * 65
# just try to get the signature.

# result = assemble(0, 1)
# witness = CKB::Serializers::WitnessArgsSerializer.new(witness_for_input_lock: "0x" + result + sig_A + sig_B).serialize
# puts CKB::Utils.hex_to_bin(witness).length
# puts witness
# puts CKB::Utils.bin_to_hex([159].pack("Q<"))

# init args.
result = assemble_lock_args(0, 666, 210)
puts "0x" + result + CKB::Key.blake160(CKB::Key.pubkey("0x" + prikey_A))[2..-1] + CKB::Key.blake160(CKB::Key.pubkey("0x" + prikey_B))[2..-1]

# 70ab2145ecb9bf255f146514a124b23220f74b97f7e45f8a973199ea94abf90
# 70ab2145ecb90b0f255f146514a124b23220f74b97f7e45f8a973199ea94abf9
