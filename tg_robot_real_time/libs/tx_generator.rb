#!/usr/bin/ruby -w

require "rubygems"
require "bundler/setup"
require "ckb"
require "json"
require "secp256k1"
require_relative "ckb_interaction.rb"

class MyECDSA < Secp256k1::BaseKey
  include Secp256k1::Utils, Secp256k1::ECDSA

  def initialize
    super(nil, Secp256k1::ALL_FLAGS)
  end
end

class Tx_generator
  attr_reader :gpc_code_hash, :gpc_tx, :gpc_hash_type

  def initialize(key)
    @key = key
    @path_to_file = __dir__ + "/../miscellaneous/files/"
    data_raw = File.read(@path_to_file + "contract_info.json")
    data_json = JSON.parse(data_raw, symbolize_names: true)
    @api = CKB::API::new
    @gpc_code_hash = data_json[:gpc_code_hash]
    @gpc_tx = data_json[:gpc_tx_hash]
    @gpc_hash_type = "data"
    @logger = Logger.new(@path_to_file + "gpc.log")
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
      return nil
    end
    if input_type_length_check != input_type_length
      return nil
    end
    if output_type_length_check != output_type_length
      return nil
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
  def generate_witness(id, witness, message, sig_index)
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
    # set signature to zero.
    empty_witness.lock[prefix_len..-1] = "00" * 130
    empty_witness = CKB::Serializers::WitnessArgsSerializer.from(empty_witness).serialize[2..-1]
    witness_len = CKB::Utils.hex_to_bin("0x" + empty_witness).length
    witness_len = CKB::Utils.bin_to_hex([witness_len].pack("Q<"))[2..-1]
    message = (message + witness_len + empty_witness).strip
    message = CKB::Blake2b.hexdigest(CKB::Utils.hex_to_bin(message))

    # sign
    signature = @key.sign_recoverable(message)[2..-1]
    s = prefix_len + sig_index * 65 * 2
    e = s + 65 * 2 - 1
    witness_recover.lock[s..e] = signature
    witness_recover = CKB::Serializers::WitnessArgsSerializer.from(witness_recover).serialize

    return witness_recover
  end

  # def group_tx_input(tx)
  #   group = Hash.new()
  #   index = 0
  #   for input in tx.inputs
  #     validation = @api.get_live_cell(input.previous_output)
  #     return false if validation.status != "live"
  #     lock_args = validation.cell.output.lock.args
  #     if !group.keys.include?(lock_args)
  #       group[lock_args] = Array.new()
  #     end
  #     group[lock_args] << index
  #     index += 1
  #   end
  #   return group
  # end

  # convert the output of tx into inputs.
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

  # group inputs.
  # The output is
  # {lock_script: [input positions]}
  def group_input(inputs_tuple)
    group = Hash.new()
    for input_tuple in inputs_tuple
      input = input_tuple[1]
      validation = @api.get_live_cell(input.previous_output)
      return false if validation.status != "live"
      lock_hash = validation.cell.output.lock.compute_hash
      if !group.keys.include?(lock_hash)
        group[lock_hash] = Array.new()
      end
      group[lock_hash] << input_tuple[0]
    end
    return group
  end

  def sign_tx(tx, inputs_local)
    # puts inputs_local.map(&:to_h)
    # sort local inputs according to the order in tx.
    # it maybe confusing, but is is very hard to explain. I will intruduce the rationl
    # in next meeting.
    index = 0
    inputs_tuple = []
    for input_fund in tx.inputs
      for input_local in inputs_local
        inputs_tuple << [index, input_local] if input_local.to_h == input_fund.to_h
      end
      index += 1
    end

    input_group = group_input(inputs_tuple)
    return false if !input_group

    @logger.info("sign_tx: finish input_group.")
    for key in input_group.keys
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

      @logger.info("sign_tx: include the first witness.")

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

      @logger.info("sign_tx: include the witness in the same group.")

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

      @logger.info("sign_tx: include other witnesses.")

      message = blake2b.hexdigest
      tx.witnesses[first_index] = case tx.witnesses[first_index]
        when CKB::Types::Witness
          tx.witnesses[first_index]
        else
          parse_witness(tx.witnesses[first_index])
        end
      tx.witnesses[first_index].lock = @key.sign_recoverable(message)
      tx.witnesses[first_index] = CKB::Serializers::WitnessArgsSerializer.from(tx.witnesses[first_index]).serialize
      @logger.info("sign_tx: sign successfully.")
    end

    @logger.info("sign_tx: all done.")
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
    tx.cell_deps += type_dep

    tx.hash = tx.compute_hash
    return tx
  end

  def generate_closing_info(id, output, output_data, witness, sig_index)
    org_args = parse_lock_args(output.lock.args)
    org_args[:nounce] += 1
    output.lock.args = generate_lock_args(id, 1, org_args[:timeout], org_args[:nounce],
                                          org_args[:pubkey_A], org_args[:pubkey_B])

    msg = CKB::Serializers::OutputSerializer.new(output).serialize + output_data[2..]
    witness = generate_witness(id, witness, msg, sig_index)
    result = { outputs: [output], outputs_data: [output_data], witnesses: [witness] }
    return result
  end

  # def generate_empty_settlement_info(amount, lock, type, encoder)
  # I assume the first funding is the max
  def generate_empty_settlement_info(funding_type_script_version, refund_lock_script)
    type = find_type(funding_type_script_version.keys[0])
    type_script = type[:type_script]
    output = CKB::Types::Output.new(
      capacity: 0,
      lock: refund_lock_script,
      type: type_script,
    )

    output_data = type_script == nil ? "0x" : type[:encoder].call(funding_type_script_version.values[0])
    output.capacity = output.calculate_min_capacity(output_data)
    for current_type_script_hash in funding_type_script_version.keys
      output.capacity += funding_type_script_version[current_type_script_hash] if current_type_script_hash == ""
    end
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

    msg = "0x" + part1 + part2

    witness = generate_witness(id, witness, msg, sig_index)
    result = { outputs: stx_info[:outputs], outputs_data: stx_info[:outputs_data], witnesses: [witness] }
    return result
  end

  def generate_no_input_tx(inputs, closing_info, type_dep = nil)
    tx = CKB::Types::Transaction.new(
      version: 0,
      cell_deps: [],
      inputs: inputs,
      outputs: closing_info[:outputs],
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
    tx.cell_deps += type_dep

    tx.hash = tx.compute_hash

    return tx
  end

  # can only accept one payment.
  def update_stx(payments, stx_info, pubkey_payer, pubkey_payee)

    # update the balance after payment.
    for payment_type_hash in payments.keys()
      for index in (0..stx_info[:outputs].length - 1)
        @logger.info("update_stx: begin.")
        output = stx_info[:outputs][index]
        output_data = stx_info[:outputs_data][index]
        @logger.info("update_stx: output: #{output}, output_data: #{output_data}")
        type = find_type(payment_type_hash)
        amount = payments[payment_type_hash]
        if payment_type_hash == ""
          @logger.info("update_stx: ckb branch.")
          return (output.capacity - output.calculate_min_capacity(output_data)) - amount if output.capacity - amount < output.calculate_min_capacity(output_data) && output.lock.args == pubkey_payer
          stx_info[:outputs][index].capacity = output.capacity - amount if output.lock.args == pubkey_payer
          stx_info[:outputs][index].capacity = output.capacity + amount if output.lock.args == pubkey_payee
        elsif payment_type_hash == "0xecc762badc4ed2a459013afd5f82ec9b47d83d6e4903db1207527714c06f177b"
          @logger.info("update_stx: udt branch.")
          return type[:decoder].call(output_data) - amount if type[:decoder].call(output_data) - amount < 0
          stx_info[:outputs_data][index] = type[:encoder].call(type[:decoder].call(output_data) - amount) if output.lock.args == pubkey_payer
          stx_info[:outputs_data][index] = type[:encoder].call(type[:decoder].call(output_data) + amount) if output.lock.args == pubkey_payee
        else
          return "not support"
        end
      end
    end

    witness_new = Array.new()
    for witness in stx_info[:witnesses]
      witness = parse_witness(witness)
      lock = parse_witness_lock(witness.lock)
      witness_new << generate_empty_witness(lock[:id], lock[:flag], lock[:nounce] + 1, witness.input_type, witness.output_type)
    end

    stx_info[:witnesses] = witness_new

    return stx_info
  end

  def update_ctx(ctx_info)
    for output in ctx_info[:outputs]
      lock = parse_lock_args(output.lock.args)
      output.lock.args = generate_lock_args(lock[:id], lock[:status],
                                            lock[:timeout], lock[:nounce] + 1,
                                            lock[:pubkey_A], lock[:pubkey_B])
    end

    witness_new = Array.new()
    for witness in ctx_info[:witnesses]
      witness = parse_witness(witness)
      lock = parse_witness_lock(witness.lock)
      witness_new << generate_empty_witness(lock[:id], lock[:flag], lock[:nounce] + 1, witness.input_type, witness.output_type)
    end
    ctx_info[:witnesses] = witness_new
    return ctx_info
  end

  def generate_terminal_tx(id, nounce, inputs, outputs, outputs_data, witness, sig_index, type_dep)
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
    tx.cell_deps += type_dep

    tx.hash = tx.compute_hash
    empty_witness = generate_empty_witness(id, 0, nounce, witness[0].input_type, witness[0].output_type)
    tx.witnesses[0] = generate_witness(id, empty_witness, tx.hash, sig_index)

    return tx
  end

  def encoder(data)
    return CKB::Utils.bin_to_hex([data].pack("Q<"))
  end

  def construct_change_output(input_cells, funding_type_script_version, fee, refund_capacity, change_lock_script)
    type_info = find_type(funding_type_script_version.keys[0])
    type_script = type_info[:type_script]
    total_capacity = get_total_capacity(input_cells)

    if type_script == nil
      asset_output_data = "0x"
    else
      total_amount = get_total_amount(input_cells, type_script.compute_hash, type_info[:decoder])
      asset_output_data = type_info[:encoder].call(total_amount - funding_type_script_version.values[0])
    end

    change_capacity = total_capacity - fee - refund_capacity

    # construct asset change output.
    asset_change_output = CKB::Types::Output.new(
      capacity: 0,
      lock: change_lock_script,
      type: type_script,
    )

    # calculate the residual ckb.
    asset_change_output.capacity = asset_change_output.calculate_min_capacity(asset_output_data)
    change_capacity_residual = change_capacity - asset_change_output.capacity

    # construct the ckb refund.
    ckb_change_output = CKB::Types::Output.new(
      capacity: 0,
      lock: change_lock_script,
      type: nil,
    )

    if change_capacity_residual < 0
      @logger.ino("there is a problem in construct_change_output.")
      return change_capacity_residual
    end

    # construct the ckb refund.
    if change_capacity_residual < ckb_change_output.calculate_min_capacity("0x")
      asset_change_output.capacity += change_capacity_residual
      return [{ output: asset_change_output, output_data: asset_output_data }]
    else
      ckb_change_output.capacity = change_capacity_residual
      return [{ output: asset_change_output, output_data: asset_output_data }, { output: ckb_change_output, output_data: "0x" }]
    end
  end

  def construct_gpc_output(gpc_capacity, total_asset, id, timeout, pubkey1, pubkey2)
    init_args = generate_lock_args(id, 0, timeout, 0, pubkey1, pubkey2)

    type_set = total_asset.keys()
    type_hash_except_ckb = (type_set - [""])[0]
    type_except_ckb = find_type(type_hash_except_ckb)
    gpc_output_data = type_except_ckb[:encoder] == nil ? "0x" : type_except_ckb[:encoder].call(total_asset[type_hash_except_ckb])
    gpc_output = CKB::Types::Output.new(
      capacity: gpc_capacity,
      lock: CKB::Types::Script.new(code_hash: @gpc_code_hash, args: init_args, hash_type: CKB::ScriptHashType::DATA),
      type: type_except_ckb[:type_script],
    )

    return { output: gpc_output, output_data: gpc_output_data }
  end
end
