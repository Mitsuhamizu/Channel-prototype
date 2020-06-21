require "rubygems"
require "bundler/setup"
require "ckb"
require "json"

api = CKB::API.new

prikey_A = "82dede298f916ced53bf5aa87cea8a7e44e8898eaedcff96606579f7bf84d99d"
prikey_B = "d986d7bf901e50368cbe565f239c224934cd554805357338abcef177efadc08d"

pubkey_A = CKB::Key.blake160(CKB::Key.pubkey("0x" + prikey_A))[2..-1]
pubkey_B = CKB::Key.blake160(CKB::Key.pubkey("0x" + prikey_B))[2..-1]

def assemble_witness_args(flag, version)
  result = [flag, version].pack("cQ")
  result = CKB::Utils.bin_to_hex(result)[2..-1]
  puts result
  return result
end

def assemble_lock_args(status, timeout, nounce)
  result = [status, timeout, nounce].pack("cQQ")
  result = CKB::Utils.bin_to_hex(result)[2..-1]
  return result
end

def generate_lock_args(status, timeout, nounce, pubkey_A, pubkey_B)
  assemble_result = assemble_lock_args(status, timeout, nounce)
  return "0x" + assemble_result + pubkey_A + pubkey_B
end

def generate_witness(flag, version, witness, message, prikey, sig_index)
  sig_A = "00" * 65
  sig_B = "00" * 65
  message = message[2..-1]
  assemble_result = assemble_witness_args(flag, version)
  empty_witness = CKB::Serializers::WitnessArgsSerializer.new(witness_for_input_lock: "0x" + assemble_result + sig_A + sig_B).serialize[2..-1]
  witness_len = CKB::Utils.hex_to_bin(witness).length
  witness_len = CKB::Utils.bin_to_hex([witness_len].pack("Q<"))[2..-1]
  message = (message + witness_len + empty_witness).strip
  message = CKB::Blake2b.hexdigest(CKB::Utils.hex_to_bin("0x" + message))
  key = CKB::Key.new("0x" + prikey)
  signature = key.sign_recoverable(message)[2..-1]
  s = 60 + sig_index * 65 * 2
  e = s + 65 * 2 - 1
  #verify the witness is consistent
  witness[s..e] = signature
  empty_witness = "0x" + empty_witness
  if witness[0..59] != empty_witness[0..59]
    puts "The witness args are inconsistent, now we just give you the version of your."
    empty_witness[s..e] = signature
    witness = empty_witness
  end
  return witness
end

def parse_lock_args(args_ser)
  assemble_result = args_ser[0..35]
  pubkey_A = args_ser[36..75]
  pubkey_B = args_ser[76, 115]
  assemble_result = CKB::Utils.hex_to_bin(assemble_result)

  result = assemble_result.unpack("cQQ")
  return result[0], result[1], result[2], pubkey_A, pubkey_B
end

witness = "0x9f000000100000009f0000009f0000008b00000000640000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"

flag = 0
version = 0
message = "0xf8e25bfc6a78397fd96c80bafaa49dad1e4bfea5308bd4a049bdcbeaa1cd5a0c"
prikey = prikey_B
sig_index = 1

witness = generate_witness(flag, version, witness, message, prikey, sig_index)
# # puts witness
# key = CKB::Key.new("0x" + prikey_A)
# puts key.privkey
# lock_args = generate_lock_args(100, 100, 0, pubkey_A, pubkey_B)

# puts parse_lock_args(lock_args)