def decoder(data)
  result = CKB::Utils.hex_to_bin(data).unpack("Q<")[0]
  return result.to_i
end

def encoder(data)
  return CKB::Utils.bin_to_hex([data].pack("Q<"))
end

def find_type(type_script_hash)
  decoder = nil
  encoder = nil

  # we need more options, here I only consider this case.
  if type_script_hash == "0xecc762badc4ed2a459013afd5f82ec9b47d83d6e4903db1207527714c06f177b"
    decoder = method(:decoder)
    encoder = method(:encoder)
  end

  return { decoder: decoder, encoder: encoder }
end
