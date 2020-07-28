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
  if type_script_hash == "0x4128764be3d34d0f807f59a25c29ba5aff9b4b9505156c654be2ec3ba84d817d"
    decoder = method(:decoder)
    encoder = method(:encoder)
  end

  return { decoder: decoder, encoder: encoder }
end
