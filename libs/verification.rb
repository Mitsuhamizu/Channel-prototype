require "../libs/ckb_interaction.rb"

def generate_msg_from_info(info, flag)
  if flag == "closing"
    num = 1
  elsif flag == "settlement"
    num = 2
  else
    puts "the flag is invalid."
    return false
  end

  counter = 0
  msg_signed = "0x"

  for output in info[:outputs]
    break if counter == num
    msg_signed += CKB::Serializers::OutputSerializer.new(output).serialize[2..]
    counter += 1
  end

  counter = 0
  for data in info[:outputs_data]
    break if counter == num
    msg_signed += data[2..]
    counter += 1
  end

  return msg_signed
end

def verify_info(info, flag, pubkey, sig_index)

  # load signature
  info_witness = @tx_generator.parse_witness(info[:witness][0])
  info_witness_lock = @tx_generator.parse_witness_lock(info_witness.lock)
  signature = case sig_index
    when 0
      info_witness_lock[:sig_A]
    when 1
      info_witness_lock[:sig_B]
    end

  # generate the msg.
  msg_signed = generate_msg_from_info(info, flag)

  # add the length of witness.
  witness_len = (info[:witness][0].bytesize - 2) / 2
  witness_len = CKB::Utils.bin_to_hex([witness_len].pack("Q<"))[2..-1]

  # add the empty witness.
  empty_witness = @tx_generator.generate_empty_witness(info_witness_lock[:id], info_witness_lock[:flag],
                                                       info_witness_lock[:nounce], info_witness.input_type,
                                                       info_witness.output_type)
  empty_witness = CKB::Serializers::WitnessArgsSerializer.from(empty_witness).serialize[2..-1]
  msg_signed = (msg_signed + witness_len + empty_witness).strip

  return verify_signature(msg_signed, signature, pubkey) ? -1 : 0
end

def verify_signature(msg, sig, pubkey)
  data = CKB::Blake2b.hexdigest(CKB::Utils.hex_to_bin(msg))
  unrelated = MyECDSA.new

  signature_bin = CKB::Utils.hex_to_bin("0x" + sig[0..127])
  recid = CKB::Utils.hex_to_bin("0x" + sig[128..129]).unpack("C*")[0]

  sig_reverse = unrelated.ecdsa_recoverable_deserialize(signature_bin, recid)
  pubkey_reverse = unrelated.ecdsa_recover(CKB::Utils.hex_to_bin(data), sig_reverse, raw: true)
  pubser = Secp256k1::PublicKey.new(pubkey: pubkey_reverse).serialize
  pubkey_reverse = CKB::Utils.bin_to_hex(pubser)

  pubkey_verify = CKB::Key.blake160(pubkey_reverse)
  return pubkey_verify[2..] == pubkey ? true : false
end

def verify_change(tx, input_cells, input_capacity, fee, pubkey)
  remote_change = 0

  for output in tx.outputs
    remote_change += output.capacity if pubkey == output.lock.args
  end

  local_change = get_total_capacity(input_cells) - CKB::Utils.byte_to_shannon(input_capacity) - fee

  return remote_change == local_change ? true : false
end
