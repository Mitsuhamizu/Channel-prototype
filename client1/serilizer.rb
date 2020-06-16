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

def assemble_lock_args(state, timeout,nounce)
  result = [state, timeout,nounce].pack("cQQ")
  result = CKB::Utils.bin_to_hex(result)[2..-1]
  return result
end

pubkey_A = "f7ce69b80c80851a541f7cc50c785d367100d1406be7da68bb6748f46d9cacba"
pubkey_B = "39d4ecb0f07467415f9d6d034149a407f10a18c361f741d12076e0aae3690fd2"

# result = assemble(1, 2)
result = assemble_lock_args(1, 666,210)

# puts CKB::Serializers::WitnessArgsSerializer.new(witness_for_input_lock: "0x" + result + "b406ee7c5bc265d13be0476e2b128de659ab492a63b7535209ba3e823ed634e6629361200c7a57a54b42a7a50487dfc683215d140e50fbfac5549e01950d098800" + "5dd2876d6b464d9e57337440b2cd6fdf30207d031532d53eb62853eedcd82b2d275715bae3c55ffa9fbc79841a99ae18b44db72ee8ae3ebd49832befe7a9872700").serialize
# 001027000000000000
# puts CKB::Serializers::ArgSerializer.new("0x" + result + pubkey_A + pubkey_B + nounce).serialize
# puts CKB::Serializers::ArgSerializer.new(result).serialize
# 0x09000000001027000000000000
puts "0x" + result + pubkey_A + pubkey_B 

# 0x51000000001027000000000000f7ce69b80c80851a541f7cc50c785d367100d1406be7da68bb6748f46d9cacba39d4ecb0f07467415f9d6d034149a407f10a18c361f741d12076e0aae3690fd20000000000000000
