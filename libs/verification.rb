def verify_info(info, sig_index)
  fund_tx = @coll_sessions.find({ id: info[:id] }).first[:fund_tx]
  fund_tx = CKB::Types::Transaction.from_h(fund_tx)

  # for UDT.
  input_type = ""
  output_type = ""

  # load the blake2b hash of remote pubkey.
  gpc_lock = fund_tx.outputs[0].lock.args
  lock_info = @tx_generator.parse_lock_args(gpc_lock)
  remote_pubkey = case sig_index
    when 0
      lock_info[:pubkey_A]
    when 1
      lock_info[:pubkey_B]
    end

  ctx_info = json_to_info (info[:ctx])

  # verify the ctx.

  # get the signature
  remote_closing_witness = @tx_generator.parse_witness(ctx_info[:witness])
  remote_closing_witness_lock = @tx_generator.parse_witness_lock(remote_closing_witness.lock)
  remote_sig_closing = case sig_index
    when 0
      remote_closing_witness_lock[:sig_A]
    when 1
      remote_closing_witness_lock[:sig_B]
    end

  # generate the signed content.
  msg_signed_closing = CKB::Serializers::OutputSerializer.new(ctx_info[:outputs][0]).serialize

  # add the length of witness
  witness_len = (ctx_info[:witness].bytesize - 2) / 2
  witness_len = CKB::Utils.bin_to_hex([witness_len].pack("Q<"))[2..-1]

  # add the empty witness
  empty_witness = @tx_generator.generate_empty_witness(remote_closing_witness_lock[:flag], remote_closing_witness_lock[:nounce], input_type, output_type)
  empty_witness = CKB::Serializers::WitnessArgsSerializer.from(empty_witness).serialize[2..-1]
  msg_signed_closing = (msg_signed_closing + witness_len + empty_witness).strip

  # verify stx

  stx_info = json_to_info (info[:stx])

  # load the signature of settlement info.

  remote_settlement_witness = @tx_generator.parse_witness(stx_info[:witness])
  remote_settlement_witness_lock = @tx_generator.parse_witness_lock(remote_settlement_witness.lock)
  remote_sig_settlement = case sig_index
    when 0
      remote_settlement_witness_lock[:sig_A]
    when 1
      remote_settlement_witness_lock[:sig_B]
    end

  # generate the msg of settlement
  msg_signed_settlement = "0x"
  for output in stx_info[:outputs]
    data = CKB::Serializers::OutputSerializer.new(output).serialize[2..-1]
    msg_signed_settlement += data
  end

  # add the length of witness
  witness_len = (stx_info[:witness].bytesize - 2) / 2
  witness_len = CKB::Utils.bin_to_hex([witness_len].pack("Q<"))[2..-1]

  # add the empty witness
  empty_witness = @tx_generator.generate_empty_witness(remote_settlement_witness_lock[:flag], remote_settlement_witness_lock[:nounce], input_type, output_type)
  empty_witness = CKB::Serializers::WitnessArgsSerializer.from(empty_witness).serialize[2..-1]
  msg_signed_settlement = (msg_signed_settlement + witness_len + empty_witness).strip

  if verify_signature(msg_signed_closing, remote_sig_closing, remote_pubkey) != 0
    return -1
  end

  if verify_signature(msg_signed_settlement, remote_sig_settlement, remote_pubkey) != 0
    return -1
  end

  return 0
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
  if pubkey_verify[2..] != pubkey
    return -1
  else
    return 0
  end
end

def verify_cell_dep(tx) # make sure the tx can be accepted by blockchain.
  # deps has is right.

  # about the outputdata, just ignore it.

end
