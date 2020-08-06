#!/usr/bin/ruby -w

require "socket"
require "json"
require "rubygems"
require "bundler/setup"
require "ckb"
require "digest/sha1"
require "mongo"
require "set"
require "timeout"
require "../libs/tx_generator.rb"
require "../libs/verification.rb"

$VERBOSE = nil

class Communication
  def initialize(private_key)
    $VERBOSE = nil
    @key = CKB::Key.new(private_key)
    @api = CKB::API::new
    @tx_generator = Tx_generator.new(@key)
    @lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: CKB::Key.blake160(@key.pubkey), hash_type: CKB::ScriptHashType::TYPE)
    @lock_hash = @lock.compute_hash

    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database
    @coll_sessions = @db[@key.pubkey + "_session_pool"]
    @coll_cells = @db[@key.pubkey + "_cell_pool"]
    @command_string = File.read("../testing/files/commands.json")
    @command_json = JSON.parse(@command_string, symbolize_names: true)
  end

  # Generate the plain text msg, client will print it.
  def generate_text_msg(id, text)
    return { type: 0, id: id, text: text }.to_json
  end

  # These two functions are used to parse and construct ctx_info and stx_info.
  # Info structure. outputs:[], outputs_data:[], witnesses:[].
  def info_to_json(info)
    info_json = info
    info_json[:outputs] = info_json[:outputs].map(&:to_h)
    info_json[:witnesses] = info_json[:witnesses].map do |witness|
      case witness
      when CKB::Types::Witness
        CKB::Serializers::WitnessArgsSerializer.from(witness).serialize
      else
        witness
      end
    end

    info_json = info_json.to_json

    return info.to_json
  end

  def json_to_info(json)
    info_h = JSON.parse(json, symbolize_names: true)
    info_h[:outputs] = info_h[:outputs].map { |output| CKB::Types::Output.from_h(output) }
    return info_h
  end

  # two method to convert hash to cell and cell to hash.
  # cell structure. output:[], outputs_data[].
  def hash_to_cell(cell_h)
    cell = cell_h
    cell[:output] = CKB::Types::Output.from_h(cell[:output])
    return cell
  end

  def cell_to_hash(cell)
    cell_h = cell
    cell_h[:output] = cell_h[:output].to_h
    return cell_h
  end

  # merge local and remote info.
  def merge_stx_info(info1, info2)
    outputs = []
    outputs_data = []
    for info in [info1, info2]
      outputs << info[:outputs][0]
      outputs_data << info[:outputs_data][0]
    end
    witnesses = info1[:witnesses][0]
    result = { outputs: outputs, outputs_data: outputs_data, witnesses: [witnesses] }
    return result
  end

  def load_command()
    command_raw = File.read("./files/commands.json")
    command_json = JSON.parse(command_raw, symbolize_names: true)
    return command_json
  end

  def record_error(msg)
    file = File.new("./files/errors.json", "w")
    file.syswrite(msg.to_json)
    file.close()
  end

  def record_success(msg)
    file = File.new("./files/successes.json", "w")
    file.syswrite(msg.to_json)
    file.close()
  end

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
    type_script = nil
    decoder = nil
    encoder = nil
    type_dep = nil

    # load the type in the file...
    data_raw = File.read("./files/contract_info.json")
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

  # The main part of communcator
  def process_recv_message(client, msg)

    # msg has two fixed field, type and id.
    type = msg[:type]
    view = @coll_sessions.find({ id: msg[:id] })

    # if there is no record and the msg is not the first step.
    if view.count_documents() == 0 && type != 1
      msg_reply = generate_text_msg(msg[:id], "sry, the msg's type is inconsistent with the type in local database!")
      client.puts (msg_reply)
      return false
      # if there is a record, just check the msg type is same as local status.
    elsif view.count_documents() == 1 && (![-2, -1, 0].include? type)
      view.each do |doc|
        if doc["status"] != type
          msg_reply = generate_text_msg(msg[:id], "sry, the msg's type is inconsistent with the type in local database!")
          client.puts (msg_reply)
          return false
        end
      end
      # one id, one record.
    elsif view.count_documents() > 1
      msg_reply = generate_text_msg(msg[:id], "sry, there are more than one record about the id.")
      client.puts (msg_reply)
      return false
    end

    case type

    # when -2 # Reset the status.
    #   recover_stage = msg[:recover_stage]

    #   # case 1: revert to the establishment stage.

    #   # case 2: revert to the
    #   local_stage < 6
    #   # get the nearest camp.

    # re-send
    when -1
      msg_reply_json = @coll_sessions.find({ id: msg[:id] }).first[:msg_cache]
      msg_reply = JSON.parse(msg_reply_json, symbolize_names: true)
      client.puts (msg_reply)
      return true
      # Just the plain text.
    when 0
      puts msg[:text]
      return true
    when 1

      # parse the msg
      remote_pubkey = msg[:pubkey]
      remote_cells = msg[:cells].map { |cell| CKB::Types::Input.from_h(cell) }
      remote_fee_fund = msg[:fee_fund]
      remote_change = hash_to_cell(msg[:change])
      remote_asset = msg[:asset]
      remote_stx_info = json_to_info(msg[:stx_info])
      timeout = msg[:timeout].to_i
      local_pubkey = CKB::Key.blake160(@key.pubkey)
      lock_hashes = [@lock_hash]
      refund_lock_script = @lock
      change_lock_script = refund_lock_script

      # find the type hash and decoder.
      local_type_script_hash = remote_asset.keys.first.to_s
      remote_type_script_hash = remote_asset.keys.first.to_s
      remote_amount = remote_asset[remote_asset.keys.first]

      local_type = find_type(local_type_script_hash)
      remote_type = find_type(remote_type_script_hash)

      remote_cell_check = check_cells(remote_cells, remote_amount, remote_fee_fund, remote_change, remote_stx_info, remote_type_script_hash, remote_type[:decoder])

      # check remote cells.
      if !remote_cell_check
        client.puts(generate_text_msg(msg[:id], "sry, your capacity is not enough or your cells are not alive."))
        return false
      end

      # Ask whether willing to accept the request, the capacity is same as negotiations.
      amount_print = local_type_script_hash == "" ? remote_amount / (10 ** 8) : remote_amount
      puts "#{remote_pubkey} wants to establish channel with you. The remote fund amount: #{amount_print}. The type script hash #{remote_type_script_hash}."
      puts "The fund fee is #{remote_fee_fund}."
      puts "Tell me whether you are willing to accept this request."

      commands = load_command()

      # read data from json file.

      # It should be more robust.
      while true
        # testing
        response = commands[:recv_reply]
        # response = "yes"
        if response == "yes"
          break
        elsif response == "no"
          msg_reply = generate_text_msg(msg[:id], "sry, remote node refuses your request.")
          client.puts(msg_reply)
          return false
        else
          puts "your input is invalid"
        end
      end

      # Get the capacity and fee. These code need to be more robust.
      while true
        puts "Please input the amount and fee you want to use for funding"
        local_amount = BigDecimal(commands[:recv_fund])
        local_fee_fund = commands[:recv_fee].to_i
        puts local_amount
        # CKB to shannon.
        local_amount = local_type_script_hash == "" ? local_amount * 10 ** 8 : local_amount
        break
      end
      puts local_amount
      # puts local_amount.to_i
      # gather local fund inputs.
      local_cells = gather_inputs(local_amount, local_fee_fund, lock_hashes, change_lock_script,
                                  refund_lock_script, local_type, @coll_cells)
      # puts local_cells.map(&:to_h)

      if local_cells == nil
        errors_msg = { receiver_gather_funding_error_insufficient: 1 }
        record_error(errors_msg)
        return false
      end

      return false if local_cells == nil

      # generate the settlement infomation.

      local_empty_stx = @tx_generator.generate_empty_settlement_info(local_amount, refund_lock_script, local_type[:type_script], local_type[:encoder])
      stx_info = merge_stx_info(remote_stx_info, local_empty_stx)
      refund_capacity = local_empty_stx[:outputs][0].capacity
      stx_info_json = info_to_json(stx_info)
      local_empty_stx_json = info_to_json(local_empty_stx)

      # calculate change.
      local_change = @tx_generator.construct_change_output(local_cells, local_amount, local_fee_fund, refund_capacity, change_lock_script,
                                                           local_type[:type_script], local_type[:encoder], local_type[:decoder])
      gpc_capacity = get_total_capacity(local_cells + remote_cells)

      outputs = Array.new()
      outputs_data = Array.new()
      for cell in [remote_change] + [local_change]
        outputs << cell[:output]
        outputs_data << cell[:output_data]
      end

      for output in outputs
        gpc_capacity -= output.capacity
      end

      # generate the info of gpc output
      gpc_capacity -= (remote_fee_fund + local_fee_fund)
      gpc_type_script = local_type[:type_script]

      gpc_cell = @tx_generator.construct_gpc_output(gpc_capacity, local_amount + remote_amount,
                                                    msg[:id], timeout, remote_pubkey[2..-1], local_pubkey[2..-1],
                                                    gpc_type_script, local_type[:encoder])

      outputs.insert(0, gpc_cell[:output])
      outputs_data.insert(0, gpc_cell[:output_data])

      # generate the inputs and witness of fund tx.
      fund_cells = remote_cells + local_cells
      fund_witnesses = Array.new()
      for iter in fund_cells
        fund_witnesses << CKB::Types::Witness.new
      end

      # Let us create the fund tx!
      fund_tx = @tx_generator.generate_fund_tx(fund_cells, outputs, outputs_data, fund_witnesses, local_type[:type_dep])
      local_cells_h = local_cells.map(&:to_h)
      # send it
      msg_reply = { id: msg[:id], type: 2, amount: local_amount, fee_fund: local_fee_fund,
                    fund_tx: fund_tx.to_h, stx_info: local_empty_stx_json, pubkey: local_pubkey }.to_json
      client.puts(msg_reply)

      # update database.
      doc = { id: msg[:id], local_pubkey: local_pubkey, remote_pubkey: remote_pubkey,
              status: 3, nounce: 0, ctx_info: 0, stx_info: stx_info_json,
              local_cells: local_cells_h, fund_tx: fund_tx.to_h, msg_cache: msg_reply,
              timeout: timeout.to_s, local_amount: local_amount, stage: 0, settlement_time: 0,
              sig_index: 1, closing_time: 0, stx_info_pend: 0, ctx_info_pend: 0, type_hash: remote_type_script_hash }
      record_success({ sender_gather_funding_success: 1 })
      return insert_with_check(@coll_sessions, doc) ? true : false
    when 2

      # parse the msg.
      fund_tx = CKB::Types::Transaction.from_h(msg[:fund_tx])
      remote_amount = msg[:amount]
      remote_pubkey = msg[:pubkey]
      remote_fee_fund = msg[:fee_fund]
      timeout = @coll_sessions.find({ id: msg[:id] }).first[:timeout].to_i
      remote_stx_info = json_to_info(msg[:stx_info])

      # load local info.
      local_cells = (@coll_sessions.find({ id: msg[:id] }).first[:local_cells]).map(&:to_h)
      local_cells = local_cells.map { |cell| JSON.parse(cell.to_json, symbolize_names: true) }
      local_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:local_pubkey]
      local_asset = JSON.parse(@coll_sessions.find({ id: msg[:id] }).first[:local_asset])
      local_fee_fund = @coll_sessions.find({ id: msg[:id] }).first[:fee_fund]
      local_change = hash_to_cell(JSON.parse(@coll_sessions.find({ id: msg[:id] }).first[:local_change], symbolize_names: true))
      local_stx_info = json_to_info(@coll_sessions.find({ id: msg[:id] }).first[:stx_info])
      sig_index = @coll_sessions.find({ id: msg[:id] }).first[:sig_index]

      # get type.
      type_script_hash = local_asset.keys.first
      local_amount = local_asset[type_script_hash]

      remote_type = find_type(type_script_hash)
      local_type = find_type(type_script_hash)

      # get remote cells.
      remote_cells = fund_tx.inputs.map(&:to_h) - local_cells
      remote_cells = remote_cells.map { |cell| CKB::Types::Input.from_h(cell) }
      local_cells = local_cells.map { |cell| CKB::Types::Input.from_h(cell) }

      # load gpc output.
      gpc_output = fund_tx.outputs[0]
      gpc_output_data = fund_tx.outputs_data[0]

      # require the outputs number.
      if fund_tx.outputs.length != 3
        client.puts(generate_text_msg(msg[:id], "sry, the number of outputs in fund tx is illegal."))
        return false
      end

      # require there is no my cells in remote cells.
      # otherwise, if remote party uses my cell as his funding.
      # My signature is misused.
      local_cell_lock_lib = Set[]
      for cell in local_cells
        output = @api.get_live_cell(cell.previous_output).cell.output
        local_cell_lock_lib.add(output.lock.compute_hash)
      end

      commands = load_command()

      # About the one way channel.
      if remote_amount == 0
        puts "It is a one-way channel, tell me whether you want to accept it."
        while true
          # response = STDIN.gets.chomp
          response = commands[:sender_one_way_permission]
          if response == "yes"
            break
          elsif response == "no"
            msg_reply = generate_text_msg(msg[:id], "sry, remote node refuses your request, since it is one-way channel.")
            client.puts(msg_reply)
            return false
          else
            puts "your input is invalid"
          end
        end
      end

      # check there is no my cells in remote cell.
      for cell in remote_cells
        output = @api.get_live_cell(cell.previous_output).cell.output
        return false if local_cell_lock_lib.include? output.lock.compute_hash
      end

      # the local change
      fund_tx_cell_1 = { output: fund_tx.outputs[1], output_data: fund_tx.outputs_data[1] }
      remote_change = { output: fund_tx.outputs[2], output_data: fund_tx.outputs_data[2] }

      # local change checked.
      if !(fund_tx_cell_1[:output].to_h == local_change[:output].to_h &&
           fund_tx_cell_1[:output_data] == local_change[:output_data])
        client.puts(generate_text_msg(msg[:id], "sry, my change goes wrong."))
        return false
      end

      # check the cells remote party providing is right.
      remote_cell_check = check_cells(remote_cells, remote_amount, remote_fee_fund, remote_change, remote_stx_info, type_script_hash, remote_type[:decoder])

      if !remote_cell_check
        client.puts(generate_text_msg(msg[:id], "sry, your capacity is not enough or your cells are not alive."))
        return false
      end

      # gpc outptu checked.
      gpc_capacity = local_stx_info[:outputs][0].capacity + remote_stx_info[:outputs][0].capacity

      # regenerate the cell by myself, and check remote one is same as it.
      gpc_cell = @tx_generator.construct_gpc_output(gpc_capacity, local_amount + remote_amount,
                                                    msg[:id], timeout, local_pubkey[2..-1], remote_pubkey[2..-1],
                                                    local_type[:type_script], local_type[:encoder])
      if !(gpc_cell[:output].to_h == gpc_output.to_h &&
           gpc_cell[:output_data] == gpc_output_data)
        client.puts(generate_text_msg(msg[:id], "sry, my change goes wrong."))
        return false
      end

      #-------------------------------------------------
      # I think is is unnecessary to do in a prototype...
      # just verify the other part (version, deps, )
      # verify_result = verify_tx(fund_tx)
      # if verify_result == -1
      #   client.puts(generate_text_msg("sry, the fund tx has some problem..."))
      #   return -1
      # end

      # check the remote capcity is satisfactory.
      amount_print = local_type_script_hash == "" ? remote_amount / (10 ** 8) : remote_amount
      puts "#{remote_pubkey} wants to establish channel with you. The remote fund amount: #{amount_print}. The type script hash #{remote_type_script_hash}."
      puts "The fund fee is #{remote_fee_fund}."
      puts "Tell me whether you are willing to accept this request"
      while true
        response = commands[:sender_reply]
        # response = STDIN.gets.chomp
        if response == "yes"
          break
        elsif response == "no"
          client.puts(generate_text_msg(msg[:id], "sry, remote node refuses your request."))
          return false
        else
          puts "your input is invalid"
        end
      end

      # generate empty witnesses.
      # the two magic number is flag of witness and the nounce.
      # The nounce of first pair of stx and ctx is 1.
      witness_closing = @tx_generator.generate_empty_witness(msg[:id], 1, 1)
      witness_settlement = @tx_generator.generate_empty_witness(msg[:id], 0, 1)

      # merge the stx_info.
      stx_info = merge_stx_info(local_stx_info, remote_stx_info)

      # generate and sign ctx and stx.
      ctx_info = @tx_generator.generate_closing_info(msg[:id], gpc_output, gpc_output_data, witness_closing, sig_index)
      stx_info = @tx_generator.sign_settlement_info(msg[:id], stx_info, witness_settlement, sig_index)

      # convert the info into json to store and send.
      stx_info_json = info_to_json(stx_info)
      ctx_info_json = info_to_json(ctx_info)

      # send the info
      msg_reply = { id: msg[:id], type: 3, ctx_info: ctx_info_json, stx_info: stx_info_json }.to_json
      client.puts(msg_reply)

      # update the database.
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { remote_pubkey: remote_pubkey, fund_tx: msg[:fund_tx], ctx_info: ctx_info_json,
                                                                        stx_info: stx_info_json, status: 4, msg_cache: msg_reply, nounce: 1 } })

      return true
    when 3

      # load many info...
      fund_tx = @coll_sessions.find({ id: msg[:id] }).first[:fund_tx]
      local_stx_info = json_to_info(@coll_sessions.find({ id: msg[:id] }).first[:stx_info])
      remote_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:remote_pubkey]
      sig_index = @coll_sessions.find({ id: msg[:id] }).first[:sig_index]
      fund_tx = CKB::Types::Transaction.from_h(fund_tx)

      remote_ctx_info = json_to_info(msg[:ctx_info])
      remote_stx_info = json_to_info(msg[:stx_info])

      # veirfy the remote signature is right.
      # sig_index is the the signature index. 0 or 1.
      # So I just load my local sig_index, 1-sig_index is the remote sig_index.
      remote_ctx_result = verify_info_sig(remote_ctx_info, "closing", remote_pubkey, 1 - sig_index)
      remote_stx_result = verify_info_sig(remote_stx_info, "settlement", remote_pubkey, 1 - sig_index)

      if !remote_ctx_result || !remote_stx_result
        client.puts(generate_text_msg(msg[:id], "The signatures are invalid."))
        return false
      end

      # check the ctx_info and stx_info args are right.
      # just generate it by myself and compare.
      witness_closing = @tx_generator.generate_empty_witness(msg[:id], 1, 1)
      witness_settlement = @tx_generator.generate_empty_witness(msg[:id], 0, 1)
      output = Marshal.load(Marshal.dump(fund_tx.outputs[0]))
      local_ctx_info = @tx_generator.generate_closing_info(msg[:id], output, fund_tx.outputs_data[0], witness_closing, sig_index)
      local_stx_info = @tx_generator.sign_settlement_info(msg[:id], local_stx_info, witness_settlement, sig_index)

      # check the args are same.
      if !verify_info_args(local_ctx_info, remote_ctx_info) || !verify_info_args(local_stx_info, remote_stx_info)
        client.puts(generate_text_msg(msg[:id], "sry, the args of closing or settlement transaction have problem."))
        return false
      end

      output = Marshal.load(Marshal.dump(fund_tx.outputs[0]))

      # sign
      ctx_info = @tx_generator.generate_closing_info(msg[:id], output, fund_tx.outputs_data[0], remote_ctx_info[:witnesses][0], sig_index)
      stx_info = @tx_generator.sign_settlement_info(msg[:id], local_stx_info, remote_stx_info[:witnesses][0], sig_index)

      ctx_info_json = info_to_json(ctx_info)
      stx_info_json = info_to_json(stx_info)

      # send the info
      msg_reply = { id: msg[:id], type: 4, ctx_info: ctx_info_json, stx_info: stx_info_json }.to_json
      client.puts(msg_reply)

      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { ctx_info: ctx_info_json, stx_info: stx_info_json,
                                                                        status: 5, msg_cache: msg_reply, nounce: 1 } })

      return true
    when 4
      remote_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:remote_pubkey]
      local_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:local_pubkey]
      local_inputs = @coll_sessions.find({ id: msg[:id] }).first[:local_cells]
      local_inputs = local_inputs.map { |cell| CKB::Types::Input.from_h(cell) }

      sig_index = @coll_sessions.find({ id: msg[:id] }).first[:sig_index]

      # check the data is not modified!
      # the logic is
      # 1. my signature is not modified
      # 2. my signature can still be verified.
      local_stx_info = json_to_info(@coll_sessions.find({ id: msg[:id] }).first[:stx_info])
      local_ctx_info = json_to_info(@coll_sessions.find({ id: msg[:id] }).first[:ctx_info])

      remote_ctx_info = json_to_info(msg[:ctx_info])
      remote_stx_info = json_to_info(msg[:stx_info])

      local_ctx_sig = @tx_generator.parse_witness_lock(@tx_generator.parse_witness(local_ctx_info[:witnesses][0]).lock)[:sig_A]
      remote_ctx_sig = @tx_generator.parse_witness_lock(@tx_generator.parse_witness(remote_ctx_info[:witnesses][0]).lock)[:sig_A]

      local_stx_sig = @tx_generator.parse_witness_lock(@tx_generator.parse_witness(local_stx_info[:witnesses][0]).lock)[:sig_A]
      remote_stx_sig = @tx_generator.parse_witness_lock(@tx_generator.parse_witness(remote_stx_info[:witnesses][0]).lock)[:sig_A]

      local_ctx_result = verify_info_sig(remote_ctx_info, "closing", local_pubkey, sig_index)
      local_stx_result = verify_info_sig(remote_stx_info, "settlement", local_pubkey, sig_index)

      if !local_ctx_result || !local_stx_result ||
         local_ctx_sig != remote_ctx_sig ||
         local_stx_sig != remote_stx_sig
        client.puts(generate_text_msg(msg[:id], "The data is modified."))
        return false
      end

      # check the remote signature
      remote_ctx_result = verify_info_sig(remote_ctx_info, "closing", remote_pubkey, 1 - sig_index)
      remote_stx_result = verify_info_sig(remote_stx_info, "settlement", remote_pubkey, 1 - sig_index)

      if !remote_ctx_result || !remote_stx_result
        client.puts(generate_text_msg(msg[:id], "The signatures are invalid."))
        return false
      end

      # sign and send the fund_tx
      fund_tx = @coll_sessions.find({ id: msg[:id] }).first[:fund_tx]
      fund_tx = CKB::Types::Transaction.from_h(fund_tx)

      # the logic is, I only sign the inputs in my local cells.
      fund_tx = @tx_generator.sign_tx(fund_tx, local_inputs).to_h

      msg_reply = { id: msg[:id], type: 5, fund_tx: fund_tx }.to_json
      client.puts(msg_reply)

      # update the database
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { fund_tx: fund_tx, ctx_info: msg[:ctx_info], stx_info: msg[:stx_info],
                                                                        status: 6, msg_cache: msg_reply } })
      client.close
      return "done"
    when 5
      remote_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:remote_pubkey]
      local_inputs = @coll_sessions.find({ id: msg[:id] }).first[:local_cells]
      local_inputs = local_inputs.map { |cell| CKB::Types::Input.from_h(cell) }
      fund_tx_local = @coll_sessions.find({ id: msg[:id] }).first[:fund_tx]
      fund_tx_local = CKB::Types::Transaction.from_h(fund_tx_local)

      fund_tx_remote = msg[:fund_tx]
      fund_tx_remote = CKB::Types::Transaction.from_h(fund_tx_remote)

      # check signature.
      fund_tx_check_result = verify_fund_tx_sig(fund_tx_remote, remote_pubkey)
      if !fund_tx_check_result
        client.puts(generate_text_msg(msg[:id], "The signatures are invalid."))
        return false
      end

      fund_tx_local_hash = fund_tx_local.compute_hash
      fund_tx_remote_hash = fund_tx_remote.compute_hash

      if fund_tx_local_hash != fund_tx_remote_hash
        client.puts(generate_text_msg(msg[:id], "fund tx is not consistent."))
        return false
      end

      fund_tx = @tx_generator.sign_tx(fund_tx_remote, local_inputs)

      # send the fund tx to chain.
      while true
        exist = @api.get_transaction(fund_tx.hash)
        break if exist != nil
        @api.send_transaction(fund_tx)
      end
      # update the database
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { fund_tx: fund_tx.to_h, status: 6 } })
      return "done"
    when 6
      id = msg[:id]
      sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
      msg_type = msg[:msg_type]
      remote_pubkey = @coll_sessions.find({ id: id }).first[:remote_pubkey]
      stage = @coll_sessions.find({ id: id }).first[:stage]

      # check the stage.
      if stage != 1
        puts "the fund tx is not on chain, so the you can not make payment now..."
        return false
      end

      # there are two type msg when type is 6.
      # 1. payment request.
      # 2. closing request.
      if msg_type == "payment"
        local_pubkey = @coll_sessions.find({ id: id }).first[:local_pubkey]
        sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
        type_hash = @coll_sessions.find({ id: id }).first[:type_hash]
        payment_type_hash = msg[:payment_type]
        payment_type = find_type(payment_type_hash)
        amount = msg[:amount]

        # recv the new signed stx and unsigned ctx.
        remote_ctx_info = json_to_info(msg[:ctx_info])
        remote_stx_info = json_to_info(msg[:stx_info])

        local_stx_info = json_to_info(@coll_sessions.find({ id: msg[:id] }).first[:stx_info])
        local_ctx_info = json_to_info(@coll_sessions.find({ id: msg[:id] }).first[:ctx_info])

        local_update_stx_info = @tx_generator.update_stx(amount, local_stx_info, remote_pubkey, local_pubkey, payment_type)
        local_update_ctx_info = @tx_generator.update_ctx(amount, local_ctx_info)

        if local_update_stx_info == false
          errors_msg = { Insufficient_amount_to_pay: 1 }
          record_error(errors_msg)
          return false
        end

        # check the updated info is right.
        ctx_result = verify_info_args(local_update_ctx_info, remote_ctx_info)
        stx_result = verify_info_args(local_update_stx_info, remote_stx_info) &&
                     verify_info_sig(remote_stx_info, "settlement", remote_pubkey, 1 - sig_index)

        return false if !ctx_result || !stx_result

        commands = load_command()

        # ask users whether the payments are right.
        amount_print = payment_type_hash == "" ? amount / (10 ** 8) : amount
        puts "The remote node wants to pay you #{amount_print} with type hash #{payment_type_hash} in channel #{id}."
        puts "Tell me whether you are willing to accept this payment."
        while true
          response = commands[:payment_reply]
          # response = STDIN.gets.chomp
          if response == "yes"
            break
          elsif response == "no"
            client.puts(generate_text_msg(msg[:id], "sry, remote node refuses your request."))
            return false
          else
            puts "your input is invalid"
          end
        end

        # generate the signed message.
        # In closing, it is the first output, output_data and witness.
        # In settlement, it is the first two outputs, outputs_data and first witness.
        msg_signed = generate_msg_from_info(remote_stx_info, "settlement")

        # sign ctx and stx and send them.
        witness_new = Array.new()
        for witness in remote_stx_info[:witnesses]
          witness_new << @tx_generator.generate_witness(id, 1, witness, msg_signed, sig_index)
        end
        remote_stx_info[:witnesses] = witness_new
        msg_signed = generate_msg_from_info(remote_ctx_info, "closing")

        # sign ctx and stx and send them.
        witness_new = Array.new()
        for witness in remote_ctx_info[:witnesses]
          witness_new << @tx_generator.generate_witness(id, 0, witness, msg_signed, sig_index)
        end
        remote_ctx_info[:witnesses] = witness_new

        # update the database.
        ctx_info_json = info_to_json(remote_ctx_info)
        stx_info_json = info_to_json(remote_stx_info)

        msg = { id: id, type: 7, ctx_info: ctx_info_json, stx_info: stx_info_json }.to_json
        client.puts(msg)

        # update the local database.
        @coll_sessions.find_one_and_update({ id: id }, { "$set" => { ctx_pend: ctx_info_json,
                                                                    stx_pend: stx_info_json,
                                                                    status: 8, msg_cache: msg } })
      elsif msg_type == "closing"
        fund_tx = @coll_sessions.find({ id: id }).first[:fund_tx]
        fund_tx = CKB::Types::Transaction.from_h(fund_tx)
        local_stx_info = json_to_info(@coll_sessions.find({ id: msg[:id] }).first[:stx_info])
        remote_change = CKB::Types::Output.from_h(msg[:change])
        remote_fee_cells = msg[:fee_cell].map { |cell| CKB::Types::Input.from_h(cell) }
        remote_fee = get_total_capacity(remote_fee_cells) - remote_change.capacity
        nounce = @coll_sessions.find({ id: id }).first[:nounce]
        type_hash = @coll_sessions.find({ id: id }).first[:type_hash]
        current_height = @api.get_tip_block_number
        type_info = find_type(type_hash)

        puts "#{remote_pubkey} wants to close the channel with id #{id}. Remote fee is #{remote_fee}"
        puts "Tell me whether you are willing to accept this request"
        commands = load_command()
        while true
          response = commands[:closing_reply]
          # response = STDIN.gets.chomp
          if response == "yes"
            break
          elsif response == "no"
            msg_reply = generate_text_msg(msg[:id], "sry, remote node refuses your request.")
            client.puts(msg_reply)
            return false
          else
            puts "your input is invalid"
          end
        end
        while true
          puts "Please input fee you want to use for settlement"
          local_fee = commands[:recv_fee].to_i
          break
        end
        local_change_output = CKB::Types::Output.new(
          capacity: 0,
          lock: @lock,
          type: nil,
        )
        total_fee = local_change_output.calculate_min_capacity("0x") + local_fee
        local_fee_cell = gather_fee_cell([@lock_hash], total_fee, @coll_cells, 0)
        fee_cell_capacity = get_total_capacity(local_fee_cell)
        return false if local_fee_cell == nil
        local_change_output.capacity = fee_cell_capacity - local_fee

        input_fund = @tx_generator.convert_input(fund_tx, 0, 0) # index and since.
        inputs = [input_fund] + remote_fee_cells + local_fee_cell

        outputs = local_stx_info[:outputs] + [remote_change, local_change_output]
        outputs_data = local_stx_info[:outputs_data] + ["0x", "0x"]
        witnesses = local_stx_info[:witnesses]

        # add witnesses of change.
        witnesses << CKB::Types::Witness.new
        witnesses << CKB::Types::Witness.new

        witnesses = witnesses.map do |witness|
          case witness
          when CKB::Types::Witness
            witness
          else
            @tx_generator.parse_witness(witness)
          end
        end
        terminal_tx = @tx_generator.generate_terminal_tx(id, nounce, inputs, outputs, outputs_data, witnesses, sig_index, type_info[:type_dep])
        terminal_tx = @tx_generator.sign_tx(terminal_tx, local_fee_cell).to_h
        msg_reply = { id: msg[:id], type: 9, terminal_tx: terminal_tx }.to_json
        client.puts(msg_reply)
        @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { stage: 2, closing_time: current_height + 20 } })
      end
    when 7

      # It is the feedback msg of payments.
      id = msg[:id]
      remote_pubkey = @coll_sessions.find({ id: id }).first[:remote_pubkey]
      local_pubkey = @coll_sessions.find({ id: id }).first[:local_pubkey]
      sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
      stage = @coll_sessions.find({ id: id }).first[:stage]
      stx_pend = @coll_sessions.find({ id: id }).first[:stx_pend]
      ctx_pend = @coll_sessions.find({ id: id }).first[:ctx_pend]
      nounce = @coll_sessions.find({ id: id }).first[:nounce]

      local_ctx_info = json_to_info(ctx_pend)
      local_stx_info = json_to_info(stx_pend)

      remote_ctx_info = json_to_info(msg[:ctx_info])
      remote_stx_info = json_to_info(msg[:stx_info])

      if stage != 1
        puts "the fund tx is not on chain, so the you can not make payment now..."
        return false
      end

      # check both the signatures are right.
      ctx_result = verify_info_args(local_ctx_info, remote_ctx_info) &&
                   verify_info_sig(remote_ctx_info, "closing", remote_pubkey, 1 - sig_index)
      stx_result = verify_info_args(local_stx_info, remote_stx_info) &&
                   verify_info_sig(remote_stx_info, "settlement", remote_pubkey, 1 - sig_index)

      if !ctx_result || !stx_result
        client.puts(generate_text_msg(msg[:id], "sry, the args of closing or settlement transaction have problem."))
        return false
      end

      # generate the signed msg from info.
      msg_signed = generate_msg_from_info(remote_ctx_info, "closing")
      witness_new = Array.new()
      for witness in remote_ctx_info[:witnesses]
        witness_new << @tx_generator.generate_witness(id, 0, witness, msg_signed, sig_index)
      end
      remote_ctx_info[:witnesses] = witness_new

      ctx_info_json = info_to_json(remote_ctx_info)
      stx_info_json = info_to_json(remote_stx_info)

      msg = { id: id, type: 8, ctx_info: ctx_info_json }.to_json
      client.puts(msg)

      # update the local database.
      @coll_sessions.find_one_and_update({ id: id }, { "$set" => { ctx_info: ctx_info_json,
                                                                  stx_info: stx_info_json,
                                                                  nounce: nounce + 1,
                                                                  stx_pend: 0, ctx_pend: 0,
                                                                  status: 6, msg_cache: msg } })
      client.close
      return "done"
    when 8
      # it is the final step of making payments.
      # the payer just check the remote signatures are right,
      # and send the signed ctx to him.
      id = msg[:id]
      remote_pubkey = @coll_sessions.find({ id: id }).first[:remote_pubkey]
      local_pubkey = @coll_sessions.find({ id: id }).first[:local_pubkey]
      sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
      stage = @coll_sessions.find({ id: id }).first[:stage]
      ctx_pend = @coll_sessions.find({ id: id }).first[:ctx_pend]
      stx_pend = @coll_sessions.find({ id: id }).first[:stx_pend]
      nounce = @coll_sessions.find({ id: id }).first[:nounce]

      local_ctx_info = json_to_info(ctx_pend)
      remote_ctx_info = json_to_info(msg[:ctx_info])

      ctx_result = verify_info_args(local_ctx_info, remote_ctx_info)
      return false if !ctx_result

      ctx_info_json = info_to_json(remote_ctx_info)

      @coll_sessions.find_one_and_update({ id: id }, { "$set" => { ctx_info: ctx_info_json, stx_info: stx_pend,
                                                                  status: 6, stx_pend: 0, ctx_pend: 0,
                                                                  nounce: nounce + 1 } })
      return "done"
    when 9
      id = msg[:id]
      terminal_tx = CKB::Types::Transaction.from_h(msg[:terminal_tx])
      sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
      local_fee_cell = @coll_sessions.find({ id: id }).first[:settlement_fee_cell]
      local_change_output = JSON.parse(@coll_sessions.find({ id: msg[:id] }).first[:settlement_fee_change], symbolize_names: true)
      remote_pubkey = @coll_sessions.find({ id: id }).first[:remote_pubkey]
      local_stx_info = json_to_info(@coll_sessions.find({ id: msg[:id] }).first[:stx_info])
      fund_tx = @coll_sessions.find({ id: id }).first[:fund_tx]
      fund_tx = CKB::Types::Transaction.from_h(fund_tx)
      local_fee_cell = local_fee_cell.map { |cell| JSON.parse(cell.to_json, symbolize_names: true) }
      input_fund = @tx_generator.convert_input(fund_tx, 0, 0)

      for output in local_stx_info[:outputs].map(&:to_h)
        if !terminal_tx.outputs.map(&:to_h).include? output
          msg_reply = generate_text_msg(msg[:id], "sry, the settlement outputs are inconsistent with my local one.")
          client.puts(msg_reply)
          return false
        end
      end

      terminal_tx = CKB::Types::Transaction.from_h(msg[:terminal_tx])
      remote_fee_cell = terminal_tx.inputs.map(&:to_h) - local_fee_cell - [input_fund.to_h]
      remote_fee_cell = remote_fee_cell.map { |cell| CKB::Types::Input.from_h(cell) }
      remote_change_output = terminal_tx.outputs.map(&:to_h) - [local_change_output] - local_stx_info[:outputs].map(&:to_h)

      remote_change_output = remote_change_output.map { |output| CKB::Types::Output.from_h(output) }
      remote_fee = get_total_capacity(remote_fee_cell) - remote_change_output.map(&:capacity).inject(0, &:+)

      puts "#{remote_pubkey} wants to close the channel with id #{id}. Remote fee is #{remote_fee}"
      puts "Tell me whether you are willing to accept this request"
      commands = load_command()
      while true
        response = commands[:closing_reply]
        # response = STDIN.gets.chomp
        if response == "yes"
          break
        elsif response == "no"
          msg_reply = generate_text_msg(msg[:id], "sry, remote node refuses your request.")
          client.puts(msg_reply)
          return false
        else
          puts "your input is invalid"
        end
      end

      # add my signature and send it to blockchain.
      local_fee_cell = local_fee_cell.map { |cell| CKB::Types::Input.from_h(cell) }
      terminal_tx = @tx_generator.sign_tx(terminal_tx, local_fee_cell)
      terminal_tx.witnesses[0] = @tx_generator.generate_witness(id, 0, terminal_tx.witnesses[0], terminal_tx.hash, sig_index)

      exist = @api.get_transaction(terminal_tx.hash)

      begin
        @api.send_transaction(terminal_tx) if exist == nil
      rescue
      end
      return "done"
    end
  end

  def listen(src_port)
    puts "listen start"
    server = TCPServer.open(src_port)
    loop {
      Thread.start(server.accept) do |client|

        #parse the msg
        while (1)
          msg = JSON.parse(client.gets, symbolize_names: true)
          ret = process_recv_message(client, msg)
          break if ret == 100
        end
      end
    }
  end

  def send_establish_channel(remote_ip, remote_port, amount, fee_fund, timeout, type_script_hash = "", refund_lock_script = @lock)
    s = TCPSocket.open(remote_ip, remote_port)
    change_lock_script = refund_lock_script
    lock_hashes = [@lock_hash]
    local_type = find_type(type_script_hash)

    # prepare the msg components.
    local_cells = gather_inputs(amount, fee_fund, lock_hashes, change_lock_script,
                                refund_lock_script, local_type, @coll_cells)

    if local_cells == nil
      record_error({ sender_gather_funding_error_insufficient: 1 })
      return false
    end
    asset = { type_script_hash => amount }

    local_pubkey = CKB::Key.blake160(@key.pubkey)

    # get id.
    msg_digest = (local_cells.map(&:to_h)).to_json
    session_id = Digest::MD5.hexdigest(msg_digest)

    local_empty_stx = @tx_generator.generate_empty_settlement_info(amount, refund_lock_script, local_type[:type_script], local_type[:encoder])
    refund_capacity = local_empty_stx[:outputs][0].capacity
    local_empty_stx_json = info_to_json(local_empty_stx)

    local_change = @tx_generator.construct_change_output(local_cells, amount, fee_fund, refund_capacity, change_lock_script,
                                                         local_type[:type_script], local_type[:encoder], local_type[:decoder])
    local_change_h = cell_to_hash(local_change)
    local_cells_h = local_cells.map(&:to_h)
    msg = { id: session_id, type: 1, pubkey: local_pubkey, cells: local_cells_h, fee_fund: fee_fund,
            timeout: timeout, asset: asset, change: local_change_h, stx_info: local_empty_stx_json }.to_json

    # send the msg.
    s.puts(msg)

    #insert the doc into database.
    doc = { id: session_id, local_pubkey: local_pubkey, remote_pubkey: "", status: 2,
            nounce: 0, ctx_info: 0, stx_info: local_empty_stx_json, local_cells: local_cells_h,
            timeout: timeout.to_s, msg_cache: msg.to_json, local_asset: asset.to_json, fee_fund: fee_fund,
            stage: 0, settlement_time: 0, sig_index: 0, closing_time: 0, local_change: local_change_h.to_json,
            stx_pend: 0, ctx_pend: 0, type_hash: type_script_hash }
    return false if !insert_with_check(@coll_sessions, doc)

    record_success({ sender_gather_funding_success: 1 })

    begin
      timeout(5) do
        while (1)
          msg = JSON.parse(s.gets, symbolize_names: true)
          ret = process_recv_message(s, msg)
          if ret == "done"
            s.close()
            break
          end
        end
      end
    rescue Timeout::Error
      puts "Timed out!"
    end
  end

  def send_payments(remote_ip, remote_port, id, amount, type_script_hash = "")
    s = TCPSocket.open(remote_ip, remote_port)

    remote_pubkey = @coll_sessions.find({ id: id }).first[:remote_pubkey]
    local_pubkey = @coll_sessions.find({ id: id }).first[:local_pubkey]
    sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
    stage = @coll_sessions.find({ id: id }).first[:stage]
    stx = @coll_sessions.find({ id: id }).first[:stx_info]
    ctx = @coll_sessions.find({ id: id }).first[:ctx_info]
    type_hash = @coll_sessions.find({ id: id }).first[:type_hash]
    type_info = find_type(type_hash)

    stx_info = json_to_info(stx)
    ctx_info = json_to_info(ctx)

    if stage != 1
      puts "the fund tx is not on chain, so the you can not make payment now..."
      return false
    end

    # just read and update the latest stx, the new
    stx_info = @tx_generator.update_stx(amount, stx_info, local_pubkey, remote_pubkey, type_info)
    ctx_info = @tx_generator.update_ctx(amount, ctx_info)

    if stx_info == false
      errors_msg = { Insufficient_amount_to_pay: 1 }
      record_error(errors_msg)
      return false
    end

    # sign the stx.
    msg_signed = generate_msg_from_info(stx_info, "settlement")

    # the msg ready.
    witness_new = Array.new()
    for witness in stx_info[:witnesses]
      witness_new << @tx_generator.generate_witness(id, 1, witness, msg_signed, sig_index)
    end
    stx_info[:witnesses] = witness_new

    ctx_info_json = info_to_json(ctx_info)
    stx_info_json = info_to_json(stx_info)

    # send the msg.
    msg = { id: id, type: 6, ctx_info: ctx_info_json, stx_info: stx_info_json,
            amount: amount, msg_type: "payment", payment_type: type_hash }.to_json
    s.puts(msg)

    # update the local database.
    @coll_sessions.find_one_and_update({ id: id }, { "$set" => { stx_pend: stx_info_json, ctx_pend: ctx_info_json,
                                                                status: 7, msg_cache: msg } })

    begin
      timeout(5) do
        while (1)
          msg = JSON.parse(s.gets, symbolize_names: true)
          ret = process_recv_message(s, msg)
          if ret == "done"
            s.close()
            break
          end
        end
      end
    rescue Timeout::Error
      puts "Timed out!"
    end
  end

  def send_closing_request(remote_ip, remote_port, id, fee = 1000)
    s = TCPSocket.open(remote_ip, remote_port)
    current_height = @api.get_tip_block_number

    local_change_output = CKB::Types::Output.new(
      capacity: 0,
      lock: @lock,
      type: nil,
    )
    total_fee = local_change_output.calculate_min_capacity("0x") + fee
    fee_cell = gather_fee_cell([@lock_hash], total_fee, @coll_cells, 0)
    return false if fee_cell == nil

    fee_cell_capacity = get_total_capacity(fee_cell)
    local_change_output.capacity = fee_cell_capacity - fee
    fee_cell_h = fee_cell.map(&:to_h)
    msg = { id: id, type: 6, fee: fee, fee_cell: fee_cell_h, change: local_change_output.to_h, msg_type: "closing" }.to_json
    s.puts(msg)
    @coll_sessions.find_one_and_update({ id: id }, { "$set" => { stage: 2, status: 9, msg_cache: msg, closing_time: current_height + 20, settlement_fee_cell: fee_cell_h, settlement_fee_change: local_change_output.to_h.to_json } })

    begin
      timeout(5) do
        while (1)
          msg = JSON.parse(s.gets, symbolize_names: true)
          ret = process_recv_message(s, msg)
          if ret == "done"
            s.close()
            break
          end
        end
      end
    rescue Timeout::Error
      puts "Timed out!"
    end

    return "done"
  end
end
