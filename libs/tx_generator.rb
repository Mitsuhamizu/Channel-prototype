#!/usr/bin/ruby -w

require "rubygems"
require "bundler/setup"
require "ckb"
require "secp256k1"
require "../libs/ckb_interaction.rb"

class MyECDSA < Secp256k1::BaseKey
  include Secp256k1::Utils, Secp256k1::ECDSA

  def initialize
    super(nil, Secp256k1::ALL_FLAGS)
  end
end

class Tx_generator
  attr_reader :gpc_code_hash, :gpc_tx

  def initialize(key)
    @key = key
    @api = CKB::API::new
    @gpc_code_hash = "0x00ef823681069daee2e08edad2d3d100d57d6693d0017d73d05bc9725bed547d"
    @gpc_tx = "0x7d258b18155b3301c568055c6195888b320085b0c6cb1ba1c84228b799be29da"
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
    assemble_result = CKB::Utils.hex_to_bin("0x" + lock[34..51])
    result = assemble_result.unpack("cQ")
    result = { id: lock[2..33], flag: result[0], nounce: result[1], sig_A: lock[52..181], sig_B: lock[182..311] }
    return result
  end

  # need modification
  def generate_empty_witness(id, flag, nounce, input_type = "", output_type = "")
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
    puts message
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
      return false if validation.status != "live"
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
    return false if !input_group
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

  # def generate_fund_tx(id, fund_inputs, gpc_capacity, local_change, remote_change, remote_pubkey, timeout, type_script, fund_witnesses)
  def generate_fund_tx(inputs, outputs, outputs_data, witnesses, type_dep = nil)
    tx = CKB::Types::Transaction.new(
      version: 0,
      cell_deps: [],
      inputs: inputs,
      outputs: outputs,
      outputs_data: outputs_data,
      witnesses: witnesses,
    )

    tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_code_out_point, dep_type: "code")
    tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_data_out_point, dep_type: "code")
    tx.cell_deps << type_dep if type_dep != nil
    tx.hash = tx.compute_hash
    return tx
  end

  def generate_closing_info(id, output, output_data, witness, sig_index)
    org_args = parse_lock_args(output.lock.args)
    org_args[:nounce] += 1
    output.lock.args = generate_lock_args(id, 1, org_args[:timeout], org_args[:nounce],
                                          org_args[:pubkey_A], org_args[:pubkey_B])
    msg = CKB::Serializers::OutputSerializer.new(output).serialize + output_data[2..]
    witness = generate_witness(id, 1, witness, msg, sig_index)
    result = { outputs: [output], outputs_data: [output_data], witnesses: [witness] }
    return result
  end

  # def generate_closing_info(id, gpc_lock, capacity, gpc_output_data, witness, sig_index)

  #   # load the args
  #   args = generate_lock_args(id, 1, gpc_lock[:timeout], gpc_lock[:nounce], gpc_lock[:pubkey_A], gpc_lock[:pubkey_B])
  #   gpc_output = CKB::Types::Output.new(
  #     capacity: capacity,
  #     lock: CKB::Types::Script.new(code_hash: @gpc_code_hash, args: args, hash_type: CKB::ScriptHashType::DATA),
  #   )

  #   outputs = [gpc_output]
  #   outputs_data = [gpc_output_data]

  #   # I need to generate the witness!
  #   msg = CKB::Serializers::OutputSerializer.new(gpc_output).serialize

  #   # Also, the outputdata
  #   msg += outputs_data[0][2..]

  #   witness = generate_witness(id, 1, witness, msg, sig_index)

  #   result = { outputs: outputs, outputs_data: outputs_data, witness: [witness] }
  #   return result
  # end

  def generate_empty_settlement_info(amount, lock, type, encoder)
    output = CKB::Types::Output.new(
      capacity: 0,
      lock: lock,
      type: type,
    )
    output_data = type == nil ? "0x" : encoder.call(amount)
    output.capacity = output.calculate_min_capacity(output_data)
    output.capacity += amount if type == nil
    witness = CKB::Types::Witness.new
    outputs = [output]
    outputs_data = [output_data]
    witnesses = [witness]
    return { outputs: outputs, outputs_data: outputs_data, witnesses: witnesses }
  end

  def sign_settlement_info(id, stx_info, witness, sig_index)
    part1 = ""
    part2 = ""
    for index in 0..(stx_info[:outputs].length - 1)
      part1 += CKB::Serializers::OutputSerializer.new(stx_info[:outputs][index]).serialize[2..-1]
      part2 += stx_info[:outputs_data][index][2..]
    end

    # for info in stx_info
    #   outputs << info[:outputs][0]
    #   outputs_data << info[:outputs_data][0]
    #   part1 += CKB::Serializers::OutputSerializer.new(info[:outputs][0]).serialize[2..-1]
    #   part2 += info[:outputs_data][0][2..]
    # end
    msg = "0x" + part1 + part2

    witness = generate_witness(id, 0, witness, msg, sig_index)
    result = { outputs: stx_info[:outputs], outputs_data: stx_info[:outputs_data], witnesses: [witness] }
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

  def generate_no_input_tx(inputs, closing_info, type_dep = nil)
    tx = CKB::Types::Transaction.new(
      version: 0,
      cell_deps: [],
      inputs: inputs,
      outputs: closing_info[:outputs], # If you add more cell, you should add more output!!!
      outputs_data: closing_info[:outputs_data],
      witnesses: closing_info[:witnesses],
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
    tx.cell_deps << type_dep if type_dep != nil

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

  def generate_terminal_tx(id, nounce, inputs, outputs, outputs_data, witness, sig_index)
    tx = CKB::Types::Transaction.new(
      version: 0,
      cell_deps: [],
      inputs: inputs,
      outputs: outputs,
      outputs_data: outputs_data,
      witnesses: witness,
    )

    out_point = CKB::Types::OutPoint.new(
      tx_hash: @gpc_tx,
      index: 0,
    )

    tx.cell_deps << CKB::Types::CellDep.new(out_point: out_point, dep_type: "code")
    tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_code_out_point, dep_type: "code")
    tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_data_out_point, dep_type: "code")

    tx.hash = tx.compute_hash
    empty_witness = generate_empty_witness(id, 0, nounce, witness[0].input_type, witness[0].output_type)
    tx.witnesses[0] = generate_witness(id, 0, empty_witness, tx.hash, sig_index)
    tx = sign_tx(tx)

    return tx
  end

  def encoder(data)
    return CKB::Utils.bin_to_hex([data].pack("Q<"))
  end

  def construct_change_output(input_cells, amount, fee, refund_capacity, change_lock_script, type_script = nil, encoder = nil, decoder = nil)
    total_capacity = get_total_capacity(input_cells)
    if type_script == nil
      change_capacity = total_capacity - fee - refund_capacity
      output_data = "0x"
    else
      total_amount = get_total_amount(input_cells, type_script.compute_hash, decoder)
      refund_amount = total_amount - amount
      change_capacity = total_capacity - fee - refund_capacity
      output_data = encoder.call(refund_amount)
    end

    # construct asset change output.
    change_output = CKB::Types::Output.new(
      capacity: change_capacity,
      lock: change_lock_script,
      type: type_script,
    )
    return { output: change_output, output_data: output_data }
  end

  def construct_gpc_output(gpc_capacity, amount, id, timeout, pubkey1, pubkey2, type_script, encoder)
    init_args = generate_lock_args(id, 0, timeout, 0, pubkey1, pubkey2)
    gpc_output = CKB::Types::Output.new(
      capacity: gpc_capacity,
      lock: CKB::Types::Script.new(code_hash: @gpc_code_hash, args: init_args, hash_type: CKB::ScriptHashType::DATA),
      type: type_script,
    )
    gpc_output_data = encoder == nil ? "0x" : encoder(amount)
    return { output: gpc_output, output_data: gpc_output_data }
  end
end
