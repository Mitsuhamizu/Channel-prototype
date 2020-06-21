#!/usr/bin/ruby -w

require "rubygems"
require "bundler/setup"
require "ckb"
require "secp256k1"

class MyECDSA < Secp256k1::BaseKey
  include Secp256k1::Utils, Secp256k1::ECDSA

  def initialize
    super(nil, Secp256k1::ALL_FLAGS)
  end
end

class Tx_generator
  def initialize(key)
    @key = key
    @api = CKB::API::new
    @gpc_code_hash = "0x3982bfaca9cd36a652f7133ae47e2f446d543bac449d20a9f1e7f7a6fd484dc0"
    @gpc_tx = "0x7f6a792503f9bc4a73f6db61afa7fadf5332cc7ecf21140ff75b6312356e0ac5"
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

  def parse_lock_args(args_ser)
    assemble_result = args_ser[0..35]
    assemble_result = CKB::Utils.hex_to_bin(assemble_result)
    pubkey_A = args_ser[36..75]
    pubkey_B = args_ser[76, 115]
    result = assemble_result.unpack("cQQ")
    result = { status: result[0], timeout: result[1], nounce: result[2], pubkey_A: pubkey_A, pubkey_B: pubkey_B }

    return result
  end

  def assemble_witness_args(flag, nounce)
    result = [flag, nounce].pack("cQ")
    result = CKB::Utils.bin_to_hex(result)[2..-1]
    return result
  end

  def parse_witness(witness)
    assemble_result = CKB::Utils.hex_to_bin("0x" + witness[42..59])
    result = assemble_result.unpack("cQ")
    result = { flag: result[0], nounce: result[1], sig_A: witness[60..189], sig_B: witness[190..319] }
    return result
  end

  def generate_raw_witness(flag, nounce)
    sig_A = "00" * 65
    sig_B = "00" * 65
    assemble_result = assemble_witness_args(flag, nounce)
    empty_witness = CKB::Serializers::WitnessArgsSerializer.new(witness_for_input_lock: "0x" + assemble_result + sig_A + sig_B).serialize[2..-1]
    return empty_witness
  end

  def generate_witness(flag, nounce, witness, message, sig_index)
    empty_witness = generate_raw_witness(flag, nounce)
    witness_len = CKB::Utils.hex_to_bin("0x" + empty_witness).length
    witness_len = CKB::Utils.bin_to_hex([witness_len].pack("Q<"))[2..-1]
    message = (message + witness_len + empty_witness).strip
    message = CKB::Blake2b.hexdigest(CKB::Utils.hex_to_bin(message))
    signature = @key.sign_recoverable(message)[2..-1]
    s = 60 + sig_index * 65 * 2
    e = s + 65 * 2 - 1
    #verify the witness is consistent
    if witness == 0
      witness = "0x" + empty_witness
    end
    witness[s..e] = signature
    return witness
  end

  def group_tx_input(tx)
    group = Hash.new()
    index = 0
    for input in tx.inputs
      validation = @api.get_live_cell(input.previous_output)
      lock_hash = validation.cell.output.lock.compute_hash
      if !group.keys.include?(lock_hash)
        group[lock_hash] = Array.new()
      end
      group[lock_hash] << index
      index += 1
    end
    return group
  end

  def sign_tx(tx, sign_pos_array)
    input_group = group_tx_input(tx)

    for key in input_group.keys
      if sign_pos_array & input_group[key] == []
        next
      end
      first_index = input_group[key][0]

      # include the content needed sign.
      blake2b = CKB::Blake2b.new
      blake2b.update(CKB::Utils.hex_to_bin(tx.hash))

      # include the first witness.
      emptied_witness = tx.witnesses[first_index].dup
      emptied_witness.lock = "0x#{"0" * 130}"
      emptied_witness_data_binary = CKB::Utils.hex_to_bin(CKB::Serializers::WitnessArgsSerializer.from(emptied_witness).serialize)
      emptied_witness_data_size = emptied_witness_data_binary.bytesize
      blake2b.update([emptied_witness_data_size].pack("Q<"))
      blake2b.update(emptied_witness_data_binary)

      #include the witness in the same group
      for index in input_group[key][1..]
        witness = tx.witnesses[index]
        data_binary = case witness
          when CKB::Types::Witness
            CKB::Utils.hex_to_bin(CKB::Serializers::WitnessArgsSerializer.from(witness).serialize)
          else
            CKB::Utils.hex_to_bin(witness)
          end
        data_size = data_binary.bytesize
        blake2b.update([data_size].pack("Q<"))
        blake2b.update(data_binary)
      end

      # include other witness
      witnesses_len = tx.witnesses.length()
      input_len = tx.inputs.length()
      witness_no_input_index = (input_len..witnesses_len - 1).to_a
      for index in witness_no_input_index
        witness = tx.witnesses[index]
        data_binary = case witness
          when CKB::Types::Witness
            CKB::Utils.hex_to_bin(CKB::Serializers::WitnessArgsSerializer.from(witness).serialize)
          else
            CKB::Utils.hex_to_bin(witness)
          end
        data_size = data_binary.bytesize
        blake2b.update([data_size].pack("Q<"))
        blake2b.update(data_binary)
      end

      message = blake2b.hexdigest

      tx.witnesses[first_index].lock = @key.sign_recoverable(message)
    end

    return tx
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

  def generate_fund_tx(fund_inputs, gpc_capacity, local_change, remote_change, remote_pubkey, timeout)
    local_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: CKB::Key.blake160(CKB::Key.pubkey(@key.privkey)), hash_type: CKB::ScriptHashType::TYPE)
    remote_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: remote_pubkey, hash_type: CKB::ScriptHashType::TYPE)
    fund_witnesses = Array.new()
    for iter in fund_inputs
      fund_witnesses << CKB::Types::Witness.new
    end
    use_dep_group = true

    local_pubkey = (CKB::Key.blake160(CKB::Key.pubkey(@key.privkey)))[2..-1]
    remote_pubkey = remote_pubkey[2..-1]
    init_args = generate_lock_args(0, timeout, 0, remote_pubkey, local_pubkey)
    gpc_output = CKB::Types::Output.new(
      capacity: CKB::Utils.byte_to_shannon(gpc_capacity),
      lock: CKB::Types::Script.new(code_hash: @gpc_code_hash, args: init_args, hash_type: CKB::ScriptHashType::DATA),
    )
    gpc_output_data = "0x"

    # init the change output the lock should be customized.
    remote_change_output = CKB::Types::Output.new(
      capacity: remote_change,
      lock: remote_default_lock,
    )
    remote_change_output_data = "0x"

    local_change_output = CKB::Types::Output.new(
      capacity: local_change,
      lock: local_default_lock,
    )
    local_change_output_data = "0x"

    outputs = [gpc_output, remote_change_output, local_change_output]
    outputs_data = [gpc_output_data, remote_change_output_data, remote_change_output_data]

    tx = CKB::Types::Transaction.new(
      version: 0,
      cell_deps: [], #it should be the GPC lock script cell.
      inputs: fund_inputs,
      outputs: outputs,
      outputs_data: outputs_data,
      witnesses: fund_witnesses,
    )

    if use_dep_group
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_group_out_point, dep_type: "dep_group")
    else
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_code_out_point, dep_type: "code")
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_data_out_point, dep_type: "code")
    end
    tx.hash = tx.compute_hash
    return tx
  end

  def generate_closing_info(gpc_lock, capacity, gpc_output_data, witness, sig_index)

    # load the args
    args = generate_lock_args(1, gpc_lock[:timeout], gpc_lock[:nounce], gpc_lock[:pubkey_A], gpc_lock[:pubkey_B])

    gpc_output = CKB::Types::Output.new(
      capacity: CKB::Utils.byte_to_shannon(capacity),
      lock: CKB::Types::Script.new(code_hash: @gpc_code_hash, args: args, hash_type: CKB::ScriptHashType::DATA),
    )

    outputs = [gpc_output]
    outputs_data = [gpc_output_data]

    # I need to generate the witness!

    msg = CKB::Serializers::OutputSerializer.new(gpc_output).serialize
    witness = generate_witness(1, gpc_lock[:nounce], witness, msg, sig_index)

    result = { outputs: outputs, outputs_data: outputs_data, witness: witness }
    return result
  end

  def generate_settlement_info(a, b, nounce, witness, sig_index)
    output_A = CKB::Types::Output.new(
      capacity: CKB::Utils.byte_to_shannon(a[:capacity]),
      # lock: CKB::Types::Script.new(code_hash: @gpc_code_hash, args: args, hash_type: CKB::ScriptHashType::DATA),
      lock: a[:lock],
    )

    output_B = CKB::Types::Output.new(
      capacity: CKB::Utils.byte_to_shannon(b[:capacity]),
      # lock: CKB::Types::Script.new(code_hash: @gpc_code_hash, args: args, hash_type: CKB::ScriptHashType::DATA),
      lock: b[:lock],
    )

    outputs = [output_A, output_B]
    outputs_data = [a[:data], b[:data]]

    # I need to generate the witness!
    msg = "0x"
    for output in outputs
      data = CKB::Serializers::OutputSerializer.new(output).serialize[2..-1]
      msg += data
    end
    witness = generate_witness(0, nounce, witness, msg, sig_index)
    result = { outputs: outputs, outputs_data: outputs_data, witness: witness }

    return result
  end

  def generate_closing_tx(inputs, closing_info)
    tx = CKB::Types::Transaction.new(
      version: 0,
      cell_deps: [],
      inputs: inputs,
      outputs: closing_info[0], # If you add more cell, you should add more output!!!
      outputs_data: closing_info[1],
      witnesses: closing_info[2],
    )

    if use_dep_group
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_group_out_point, dep_type: "dep_group")
    else
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_code_out_point, dep_type: "code")
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_data_out_point, dep_type: "code")
    end
    tx.cell_deps << CKB::Types::CellDep.new(out_point: gpc_tx, dep_type: "code")

    tx.hash = tx.compute_hash
    return tx
  end

  def generate_settlement_tx(inputs, settlement_info)
    tx = CKB::Types::Transaction.new(
      version: 0,
      cell_deps: [],
      inputs: inputs,
      outputs: settlement_info[0], # If you add more cell, you should add more output!!!
      outputs_data: settlement_info[1],
      witnesses: settlement_info[2],
    )

    if use_dep_group
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_group_out_point, dep_type: "dep_group")
    else
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_code_out_point, dep_type: "code")
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_data_out_point, dep_type: "code")
    end
    tx.cell_deps << CKB::Types::CellDep.new(out_point: gpc_tx, dep_type: "code")

    tx.hash = tx.compute_hash
    return tx
  end

  def generate_terminal_tx()
    # fund_witnesses = Array.new()
    # for iter in fund_inputs
    #   fund_witnesses << CKB::Types::Witness.new
    # end
    # use_dep_group = true
    # read from database, to get the latest version

    init_args = generate_lock_args(0, timeout, 0, remote_pubkey, local_pubkey)
    gpc_output = CKB::Types::Output.new(
      capacity: CKB::Utils.byte_to_shannon(gpc_capacity),
      lock: CKB::Types::Script.new(code_hash: @gpc_code_hash, args: init_args, hash_type: CKB::ScriptHashType::DATA),
    )

    gpc_output_data = "0x"

    outputs = [gpc_output]
    outputs_data = [gpc_output_data]

    tx = CKB::Types::Transaction.new(
      version: 0,
      cell_deps: [], #it should be the GPC lock script cell.
      inputs: fund_inputs, # it is very easy, just uses the output of fund transaction. It is very easy to contain.
      outputs: outputs, # just like the input of funding transaction.
      outputs_data: outputs_data, # now, it is empty
      witnesses: fund_witnesses, # will, users should sign the correct position.
    )

    if use_dep_group
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_group_out_point, dep_type: "dep_group")
    else
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_code_out_point, dep_type: "code")
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_data_out_point, dep_type: "code")
    end
    tx.hash = tx.compute_hash
    return tx
  end
end
