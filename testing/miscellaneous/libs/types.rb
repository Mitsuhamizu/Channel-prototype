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
  if type_script_hash == "0x993f830ecf003a9053c9af7c1d422dd9f612924a6e92aed153461725f19967b4"
    decoder = method(:decoder)
    encoder = method(:encoder)
  end

  return { decoder: decoder, encoder: encoder }
end
