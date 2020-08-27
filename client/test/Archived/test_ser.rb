require "rubygems"
require "bundler/setup"
require "ckb"
require "json"

api = CKB::API.new

def parse_witness(witness_ser)
  total_length = [witness_ser[2..9]].pack("H*").unpack("V")[0] * 2 + 2
  input_lock_start = ([witness_ser[10, 17]].pack("H*").unpack("V")[0]) * 2 + 2
  input_type_start = ([witness_ser[18, 25]].pack("H*").unpack("V")[0]) * 2 + 2
  output_type_start = ([witness_ser[26, 33]].pack("H*").unpack("V")[0]) * 2 + 2

  input_lock_length = (input_type_start - input_lock_start) / 2 - 4
  input_lock_length_check = input_lock_length > 0 ? [witness_ser[input_lock_start..input_lock_start + 7]].pack("H*").unpack("V")[0] : input_lock_length

  input_type_length = (output_type_start - input_type_start) / 2 - 4
  input_type_length_check = input_type_length > 0 ? [witness_ser[input_type_start..input_type_start + 7]].pack("H*").unpack("V")[0] : input_type_length

  output_type_length = (total_length - output_type_start) / 2 - 4
  output_type_length_check = output_type_length > 0 ? [witness_ser[output_type_start..output_type_start + 7]].pack("H*").unpack("V")[0] : output_type_length

  if input_lock_length_check != input_lock_length
    return -1
  end
  if input_type_length_check != input_type_length
    return -1
  end
  if output_type_length_check != output_type_length
    return -1
  end

  length = 8

  lock = input_lock_length > 0 ? witness_ser[input_lock_start + length..input_lock_start + length + input_lock_length * 2 - 1] : ""
  input_type = input_type_length > 0 ? witness_ser[input_type_start + length..input_type_start + length + input_type_length * 2 - 1] : ""
  output_type = output_type_length > 0 ? witness_ser[output_type_start + length..output_type_start + length + output_type_length * 2 - 1] : ""

  return CKB::Types::Witness.new(lock: "0x" + lock, input_type: "0x" + input_type, output_type: "0x" + output_type)
end

empty_witness = CKB::Serializers::WitnessArgsSerializer.new(witness_for_input_lock: "1234", witness_for_input_type: "", witness_for_output_type: "").serialize

witness = parse_witness(empty_witness)

puts "11"
