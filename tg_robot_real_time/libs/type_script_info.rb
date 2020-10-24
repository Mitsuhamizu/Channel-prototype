# find the type_script, type_dep, decoder and encoder by type_script_hash.
# the decoder and encoder denotes the logic of udt. Here, we only parse the
# first 8 bytes.
def decoder(data)
  result = CKB::Utils.hex_to_bin(data).unpack("Q<")[0]
  return result.to_i
end

def encoder(data)
  return CKB::Utils.bin_to_hex([data].pack("Q<"))
end

def find_type(type_script_hash)
  @path_to_file = __dir__ + "/../miscellaneous/files/"
  type_script = nil
  decoder = nil
  encoder = nil
  type_dep = nil

  # load the type in the file...
  data_raw = File.read(@path_to_file + "contract_info.json")
  data_json = JSON.parse(data_raw, symbolize_names: true)
  type_script_json = data_json[:type_script]
  type_script_h = JSON.parse(type_script_json, symbolize_names: true)
  type_script_in_file = CKB::Types::Script.from_h(type_script_h)

  # we need more options, here I only consider this case.
  if type_script_hash == type_script_in_file.compute_hash
    type_script = type_script_in_file
    out_point = CKB::Types::OutPoint.new(
      tx_hash: data_json[:udt_tx_hash],
      index: 0,
    )
    type_dep = CKB::Types::CellDep.new(out_point: out_point, dep_type: "code")
    decoder = method(:decoder)
    encoder = method(:encoder)
  end

  return { type_script: type_script, type_dep: type_dep, decoder: decoder, encoder: encoder }
end
