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
    @gpc_code_hash = "0x6d44e8e6ebc76927a48b581a0fb84576f784053ae9b53b8c2a20deafca5c4b7b"
    @gpc_tx = "0xeda5b9d9c6d5db2d4ed894fd5419b4dbbfefdf364783593dbf62a719f650e020"
  end

  def assemble_lock_args(status, timeout, nounce)
    result = [status, timeout, nounce].pack("cQQ")
    result = CKB::Utils.bin_to_hex(result)[2..-1]
    return result
  end

  def generate_lock_args(id, status, timeout, nounce, pubkey_A, pubkey_B)
    assemble_result = assemble_lock_args(status, timeout, nounce)
    return "0x" + id + assemble_result + pubkey_A + pubkey_B
  end

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

  def parse_lock_args(args_ser)
    id = args_ser[2..33]

    assemble_result = "0x" + args_ser[34..67]
    assemble_result = CKB::Utils.hex_to_bin(assemble_result)
    pubkey_A = args_ser[68..107]
    pubkey_B = args_ser[108, 147]
    result = assemble_result.unpack("cQQ")
    result = { id: id, status: result[0], timeout: result[1], nounce: result[2], pubkey_A: pubkey_A, pubkey_B: pubkey_B }

    return result
  end

  def assemble_witness_args(flag, nounce)
    result = [flag, nounce].pack("cQ")
    result = CKB::Utils.bin_to_hex(result)[2..-1]
    return result
  end

  def parse_witness_lock(lock)
    prefix_len = 52
    assemble_result = CKB::Utils.hex_to_bin("0x" + lock[34..51])
    result = assemble_result.unpack("cQ")
    result = { id: lock[2..33], flag: result[0], nounce: result[1], sig_A: lock[52..181], sig_B: lock[182..311] }
    return result
  end

  # need modification
  def generate_empty_witness(id, flag, nounce, input_type, output_type)
    sig_A = "00" * 65
    sig_B = "00" * 65
    assemble_result = assemble_witness_args(flag, nounce)
    empty_witness = CKB::Types::Witness.new(lock: "0x" + id + assemble_result + sig_A + sig_B, input_type: input_type, output_type: output_type)
    return empty_witness
  end

  # need modification
  def generate_witness(id, flag, witness, message, sig_index)
    prefix_len = 52

    witness_recover = case witness
      when CKB::Types::Witness
        witness
      else
        parse_witness(witness)
      end

    empty_witness = witness_recover
    witness_recover = case witness
      when CKB::Types::Witness
        witness
      else
        parse_witness(witness)
      end
    empty_witness.lock[prefix_len..-1] = "00" * 130
    empty_witness = CKB::Serializers::WitnessArgsSerializer.from(empty_witness).serialize[2..-1]
    witness_len = CKB::Utils.hex_to_bin("0x" + empty_witness).length
    witness_len = CKB::Utils.bin_to_hex([witness_len].pack("Q<"))[2..-1]
    message = (message + witness_len + empty_witness).strip
    message = CKB::Blake2b.hexdigest(CKB::Utils.hex_to_bin(message))
    signature = @key.sign_recoverable(message)[2..-1]
    s = prefix_len + sig_index * 65 * 2
    e = s + 65 * 2 - 1
    witness_recover.lock[s..e] = signature
    witness_recover = CKB::Serializers::WitnessArgsSerializer.from(witness_recover).serialize
    # load the sig
    return witness_recover
  end

  def group_tx_input(tx)
    group = Hash.new()
    index = 0
    for input in tx.inputs
      validation = @api.get_live_cell(input.previous_output)
      return -1 if validation.status != "live"
      lock_args = validation.cell.output.lock.args
      if !group.keys.include?(lock_args)
        group[lock_args] = Array.new()
      end
      group[lock_args] << index
      index += 1
    end
    return group
  end

  def convert_input(tx, index, since)
    out_point = CKB::Types::OutPoint.new(
      tx_hash: tx.hash,
      index: index,
    )
    input = CKB::Types::Input.new(
      previous_output: out_point,
      since: since,
    )
    return input
  end

  def sign_tx(tx)
    input_group = group_tx_input(tx)
    return -1 if input_group == -1
    for key in input_group.keys
      if key != CKB::Key.blake160(@key.pubkey)
        next
      end

      first_index = input_group[key][0]

      # include the content needed sign.
      blake2b = CKB::Blake2b.new
      blake2b.update(CKB::Utils.hex_to_bin(tx.hash))

      # include the first witness, I need to parse the witness!
      emptied_witness = case tx.witnesses[first_index]
        when CKB::Types::Witness
          tx.witnesses[first_index]
        else
          parse_witness(tx.witnesses[first_index])
        end
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

      tx.witnesses[first_index] = case tx.witnesses[first_index]
        when CKB::Types::Witness
          tx.witnesses[first_index]
        else
          parse_witness(tx.witnesses[first_index])
        end
      tx.witnesses[first_index].lock = @key.sign_recoverable(message)
      tx.witnesses[first_index] = CKB::Serializers::WitnessArgsSerializer.from(tx.witnesses[first_index]).serialize
    end

    return tx
  end

  def generate_fund_tx(id, fund_inputs, gpc_capacity, local_change, remote_change, remote_pubkey, timeout, type_script, fund_witnesses)
    local_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: CKB::Key.blake160(@key.pubkey), hash_type: CKB::ScriptHashType::TYPE)
    remote_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: remote_pubkey, hash_type: CKB::ScriptHashType::TYPE)

    use_dep_group = true

    local_pubkey = (CKB::Key.blake160(CKB::Key.pubkey(@key.privkey)))[2..-1]
    remote_pubkey = remote_pubkey[2..-1]
    init_args = generate_lock_args(id, 0, timeout, 0, remote_pubkey, local_pubkey)
    gpc_output = CKB::Types::Output.new(
      capacity: CKB::Utils.byte_to_shannon(gpc_capacity),
      lock: CKB::Types::Script.new(code_hash: @gpc_code_hash, args: init_args, hash_type: CKB::ScriptHashType::DATA),
      type: type_script,
    )
    gpc_output_data = "0x"

    # init the change output the lock should be customized.
    remote_change_output = CKB::Types::Output.new(
      capacity: remote_change,
      lock: remote_default_lock,
      type: type_script,
    )
    remote_change_output_data = "0x"

    local_change_output = CKB::Types::Output.new(
      capacity: local_change,
      lock: local_default_lock,
      type: type_script,
    )
    local_change_output_data = "0x"

    outputs = [gpc_output, remote_change_output, local_change_output]
    outputs_data = [gpc_output_data, remote_change_output_data, remote_change_output_data]

    tx = CKB::Types::Transaction.new(
      version: 0,
      cell_deps: [],
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

  def generate_closing_info(id, gpc_lock, capacity, gpc_output_data, witness, sig_index)

    # load the args
    args = generate_lock_args(id, 1, gpc_lock[:timeout], gpc_lock[:nounce], gpc_lock[:pubkey_A], gpc_lock[:pubkey_B])
    gpc_output = CKB::Types::Output.new(
      capacity: capacity,
      lock: CKB::Types::Script.new(code_hash: @gpc_code_hash, args: args, hash_type: CKB::ScriptHashType::DATA),
    )

    outputs = [gpc_output]
    outputs_data = [gpc_output_data]

    # I need to generate the witness!
    msg = CKB::Serializers::OutputSerializer.new(gpc_output).serialize

    # Also, the outputdata
    msg += outputs_data[0][2..]

    witness = generate_witness(id, 1, witness, msg, sig_index)

    result = { outputs: outputs, outputs_data: outputs_data, witness: [witness] }
    return result
  end

  def generate_settlement_info(id, a, b, witness, sig_index)
    output_A = CKB::Types::Output.new(
      capacity: a[:capacity],
      # lock: CKB::Types::Script.new(code_hash: @gpc_code_hash, args: args, hash_type: CKB::ScriptHashType::DATA),
      lock: a[:lock],
    )

    output_B = CKB::Types::Output.new(
      capacity: b[:capacity],
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

    for data in outputs_data
      msg += data[2..]
    end

    witness = generate_witness(id, 0, witness, msg, sig_index)
    result = { outputs: outputs, outputs_data: outputs_data, witness: [witness] }

    return result
  end

  def generate_no_input_tx(inputs, closing_info)
    tx = CKB::Types::Transaction.new(
      version: 0,
      cell_deps: [],
      inputs: inputs,
      outputs: closing_info[:outputs], # If you add more cell, you should add more output!!!
      outputs_data: closing_info[:outputs_data],
      witnesses: closing_info[:witness],
    )
    use_dep_group = false
    if use_dep_group
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_group_out_point, dep_type: "dep_group")
    else
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_code_out_point, dep_type: "code")
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_data_out_point, dep_type: "code")
    end
    out_point = CKB::Types::OutPoint.new(
      tx_hash: @gpc_tx,
      index: 0,
    )
    tx.cell_deps << CKB::Types::CellDep.new(out_point: out_point, dep_type: "code")

    tx.hash = tx.compute_hash
    return tx
  end

  def update_stx(amount, stx_info, local_pubkey, remote_pubkey)
    for output in stx_info[:outputs]
      output.capacity = output.capacity + amount * (10 ** 8) if output.lock.args == remote_pubkey
      output.capacity = output.capacity - amount * (10 ** 8) if output.lock.args == local_pubkey
    end

    witness_new = Array.new()
    for witness in stx_info[:witness]
      witness = parse_witness(witness)
      lock = parse_witness_lock(witness.lock)
      witness_new << generate_empty_witness(lock[:id], lock[:flag], lock[:nounce] + 1, witness.input_type, witness.output_type)
    end
    stx_info[:witness] = witness_new

    return stx_info
  end

  def update_ctx(amount, ctx_info)
    for output in ctx_info[:outputs]
      lock = parse_lock_args(output.lock.args)
      output.lock.args = generate_lock_args(lock[:id], lock[:status],
                                            lock[:timeout], lock[:nounce] + 1,
                                            lock[:pubkey_A], lock[:pubkey_B])
    end

    witness_new = Array.new()
    for witness in ctx_info[:witness]
      witness = parse_witness(witness)
      lock = parse_witness_lock(witness.lock)
      witness_new << generate_empty_witness(lock[:id], lock[:flag], lock[:nounce] + 1, witness.input_type, witness.output_type)
    end
    ctx_info[:witness] = witness_new

    return ctx_info
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
