#!/usr/bin/ruby -w

require "socket"
require "json"
require "rubygems"
require "bundler/setup"
require "ckb"
require "digest/sha1"
require "mongo"
require "set"
require "../libs/tx_generator.rb"
require "../libs/mongodb_operate.rb"
require "../libs/verification.rb"

class Communication
  def initialize(private_key)
    @key = CKB::Key.new(private_key)
    @api = CKB::API::new
    @wallet = CKB::Wallet.from_hex(@api, @key.privkey)
    @tx_generator = Tx_generator.new(@key)
    @cell_min_capacity = 61

    # it is for testing
    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC_copy")
    @db = @client.database
    @db.drop()
    # copy the db
    copy_db("GPC", "GPC_copy")
    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC_copy")

    @lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: CKB::Key.blake160(@key.pubkey), hash_type: CKB::ScriptHashType::TYPE)
    @lock_hash = @lock.compute_hash

    # @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database
    @coll_sessions = @db[@key.pubkey + "_session_pool"]
  end

  def copy_db(src, trg)
    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => src)
    @client2 = Mongo::Client.new(["127.0.0.1:27017"], :database => trg)
    @db_src = @client.database
    @db_trg = @client2.database
    for coll_name in @db_src.collection_names
      @coll_src = @db_src[coll_name]
      @coll_trg = @db_trg[coll_name]
      view = @coll_src.find { }
      view.each do |doc|
        @coll_trg.insert_one(doc)
      end
    end
  end

  def generate_text_msg(id, text)
    return { type: 0, id: id, text: text }.to_json
  end

  # These two functions are used to parse-construct ctx_info and stx_info.
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

  def find_type(type_script_hash)
    type_script = nil
    decoder = nil
    encoder = nil
    type_dep = nil

    # we need more options, here I only consider this case.
    if type_script_hash == "0x4128764be3d34d0f807f59a25c29ba5aff9b4b9505156c654be2ec3ba84d817d"
      type_script = CKB::Types::Script.new(code_hash: "0x2a02e8725266f4f9740c315ac7facbcc5d1674b3893bd04d482aefbb4bdfdd8a",
                                           args: "0x32e555f3ff8e135cece1351a6a2971518392c1e30375c1e006ad0ce8eac07947",
                                           hash_type: CKB::ScriptHashType::DATA)
      out_point = CKB::Types::OutPoint.new(
        tx_hash: "0xec4334e8a25b94f2cd71e0a2734b2424c159f4825c04ed8410e0bb5ee1dc6fe8",
        index: 0,
      )
      type_dep = CKB::Types::CellDep.new(out_point: out_point, dep_type: "code")
      decoder = method(:decoder)
      encoder = method(:encoder)
    end

    return { type_script: type_script, type_dep: type_dep, decoder: decoder, encoder: encoder }
  end

  def process_recv_message(client, msg)
    type = msg[:type]
    view = @coll_sessions.find({ id: msg[:id] })
    if view.count_documents() == 0 && type != 1
      msg_reply = generate_text_msg(msg[:id], "sry, the msg's type is inconsistent with the type in local database!")
      client.puts (msg_reply)
      return false
    elsif view.count_documents() == 1 && (![-2, -1, 0].include? type)
      view.each do |doc|
        if doc["status"] != type
          msg_reply = generate_text_msg(msg[:id], "sry, the msg's type is inconsistent with the type in local database!")
          client.puts (msg_reply)
          return false
        end
      end
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

    when -1
      msg_reply_json = @coll_sessions.find({ id: msg[:id] }).first[:msg_cache]
      msg_reply = JSON.parse(msg_reply_json, symbolize_names: true)
      client.puts (msg_reply)
      return true
    when 0 # Just the plain text.
      puts msg[:text]
      return true
    when 1

      # parse the msg
      remote_pubkey = msg[:pubkey]
      remote_cells = msg[:cells].map { |cell| CKB::Types::Input.from_h(cell) }
      remote_fee = msg[:fee]
      remote_change = hash_to_cell(msg[:change])
      remote_asset = msg[:asset]
      remote_stx_info = json_to_info(msg[:stx_info])
      timeout = msg[:timeout].to_i
      local_pubkey = CKB::Key.blake160(@key.pubkey)
      lock_hashes = [@lock_hash]
      refund_lock_script = @lock

      # find the type hash and decoder.
      local_type_script_hash = remote_asset.keys.first.to_s
      remote_type_script_hash = remote_asset.keys.first.to_s
      remote_amount = remote_asset[remote_asset.keys.first]

      local_type = find_type(local_type_script_hash)
      remote_type = find_type(remote_type_script_hash)

      # check remote cells.
      remote_cell_check = check_cells(remote_cells, remote_amount, remote_fee, remote_change, remote_stx_info, remote_type_script_hash, remote_type[:decoder])

      if !remote_cell_check
        client.puts(generate_text_msg(msg[:id], "sry, your capacity is not enough or your cells are not alive."))
        return false
      end

      # Ask whether willing to accept the request, the capacity is same as negotiations.
      puts "#{remote_pubkey} wants to establish channel with you. The remote fund amount: #{remote_amount}. The type script hash #{remote_type_script_hash}."
      puts "Tell me whether you are willing to accept this request"

      # It should be more robust.
      while true
        # testing
        # response = STDIN.gets.chomp
        response = "yes"
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
        # local_amount = 0
        # local_fee = 0
        local_amount = 44
        local_fee = 1000
        local_amount = local_type_script_hash == nil ? CKB::Utils.byte_to_shannon(local_amount) : local_amount
        # local_amount = STDIN.gets.chomp.to_i
        # local_fee = STDIN.gets.chomp.to_i
        break
      end

      # gather local fund inputs.
      local_cells = gather_inputs(local_amount, local_fee, lock_hashes, local_type_script_hash, local_type[:decoder], 15000)
      local_cells_h = local_cells.map(&:to_h)

      local_empty_stx = @tx_generator.generate_empty_settlement_info(local_amount, refund_lock_script, local_type[:type_script], local_type[:encoder])
      refund_capacity = local_empty_stx[:outputs][0].capacity
      local_empty_stx_json = info_to_json(local_empty_stx)

      # check the one way channel.
      if local_cells != []
        local_cell_check = check_cells(local_cells, local_type_script_hash, local_amount, local_fee, local_type[:decoder])
        local_change = @tx_generator.construct_change_output(local_cells, local_cell_check, local_amount, local_fee, lock_script, local_type[:type_script], local_type[:encoder])
      else
        local_change = []
      end

      gpc_capacity = get_total_capacity(local_cells + remote_cells)

      outputs = Array.new()
      outputs_data = Array.new()
      for cell in local_change + remote_change
        outputs << cell[:output]
        outputs_data << cell[:output_data]
      end

      for output in outputs
        gpc_capacity -= output.capacity
      end

      # generate the info of gpc output
      gpc_capacity -= (remote_fee + local_fee)
      gpc_type_script = local_type[:type_script]

      gpc_cell = @tx_generator.construct_gpc_output(gpc_capacity, local_amount + remote_amount,
                                                    msg[:id], timeout, remote_pubkey, gpc_type_script, local_type[:encoder])

      outputs.insert(0, gpc_cell[:output])
      outputs_data.insert(0, gpc_cell[:output_data])
      # generate the info of fund.
      fund_cells = remote_cells + local_cells
      fund_witnesses = Array.new()
      for iter in fund_cells
        fund_witnesses << CKB::Types::Witness.new       # the witness will be customized in UDT.
      end

      # Let us create the fund tx!
      fund_tx = @tx_generator.generate_fund_tx(fund_cells, outputs, outputs_data, fund_witnesses, local_type[:type_dep])

      # send it
      msg_reply = { id: msg[:id], type: 2, fee: local_fee, fund_tx: fund_tx.to_h,
                    amount: local_amount, pubkey: local_pubkey }.to_json
      client.puts(msg_reply)

      # update database.
      doc = { id: msg[:id], local_pubkey: local_pubkey, remote_pubkey: remote_pubkey,
              status: 3, nounce: 0, ctx: 0, stx: 0, gpc_script: CKB::Serializers::ScriptSerializer.new(fund_tx.outputs[0].lock).serialize,
              local_cells: local_cells_h, fund_tx: fund_tx.to_h, msg_cache: msg_reply,
              timeout: timeout.to_s, local_amount: local_amount, stage: 0, settlement_time: 0,
              sig_index: 1, closing_time: 0 }

      return insert_with_check(@coll_sessions, doc) ? true : false
    when 2

      # parse the msg.
      fund_tx = CKB::Types::Transaction.from_h(msg[:fund_tx])
      remote_amount = msg[:amount]
      remote_fee = msg[:fee]
      local_cells = @coll_sessions.find({ id: msg[:id] }).first[:local_cells]
      local_cells = local_cells.map { |cell| JSON.parse(cell.to_json, symbolize_names: true) }
      remote_cells = fund_tx.inputs.map(&:to_h) - local_cells
      local_cells = local_cells.map { |cell| CKB::Types::Input.from_h(cell) }
      remote_cells = remote_cells.map { |cell| CKB::Types::Input.from_h(cell) }

      remote_pubkey = msg[:pubkey]
      local_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:local_pubkey]
      local_asset = @coll_sessions.find({ id: msg[:id] }).first[:local_asset]
      local_fee = @coll_sessions.find({ id: msg[:id] }).first[:fee]
      local_change = hash_to_cell(@coll_sessions.find({ id: msg[:id] }).first[:local_change])

      timeout = @coll_sessions.find({ id: msg[:id] }).first[:timeout].to_i
      type_script_hash = local_asset.keys.first
      remote_type = find_type(type_script_hash)
      local_type = find_type(type_script_hash)
      gpc_output = fund_tx.outputs[0]
      gpc_output_data = fund_tx.outputs_data[0]
      # About the one way channel.
      if remote_cells.length == 0
        puts "It is a one-way channel, tell me whether you want to accept it."
        while true
          # testing
          # response = STDIN.gets.chomp
          response = "yes"
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

      local_cell_lock_lib = Set[]
      for cell in local_cells
        output = @api.get_live_cell(cell.previous_output).cell.output
        local_cell_lock_lib.add(output.lock.compute_hash)
      end

      # check there is no my cells in remote cell. So, we need to
      for cell in remote_cells
        output = @api.get_live_cell(cell.previous_output).cell.output
        return false if local_cell_lock_lib.include? output.lock.compute_hash
      end

      # compute the gpc script by myself, and check it. So here, we can make sure that the GPC args are right.
      init_args = @tx_generator.generate_lock_args(msg[:id], 0, timeout, 0, local_pubkey[2..-1], remote_pubkey[2..-1])
      gpc_lock_script = CKB::Types::Script.new(code_hash: @tx_generator.gpc_code_hash, args: init_args, hash_type: CKB::ScriptHashType::DATA)
      if CKB::Serializers::ScriptSerializer.new(gpc_output.lock).serialize != CKB::Serializers::ScriptSerializer.new(gpc_lock_script).serialize
        client.puts(generate_text_msg(msg[:id], "sry, the gpc lock is inconsistent with my verison."))
        return false
      end

      # check the cells are alive and the capacity is enough.
      remote_cell_check = check_cells(remote_cells, type_script_hash, remote_amount, remote_fee, remote_type[:decoder])
      if !remote_cell_check
        client.puts(generate_text_msg(msg[:id], "sry, your amount is not enough or your cells are not alive."))
        return false
      end

      # get local contribution.

      local_change_output = local_change.map { |cell| cell[:output] }
      local_capacity_residual = get_total_capacity(local_cells) - local_change_output.map { |output| output.capacity }.sum - local_fee

      # generate gpc by myself.

      gpc_minimal_capacity = 2 * gpc_output.calculate_min_capacity(gpc_output_data)
      if type_script_hash == "" && gpc_output.capacity != gpc_minimal_capacity + local_amount + remote_amount
        msg_reply = generate_text_msg(msg[:id], "sry, gpc output is not right.")
        client.puts(msg_reply)
        return false
      else
        # capacity is minimal
        if gpc_output.capacity != gpc_minimal_capacity
          msg_reply = generate_text_msg(msg[:id], "sry, gpc output is not right.")
          client.puts(msg_reply)
          return false
        end
        gpc_amount = local_type[:encoder].call(local_amount + remote_amount)
        puts "11"
      end
      # check change is right!
      verify_result = verify_change(fund_tx, local_cells, local_amount,
                                    local_fee, CKB::Key.blake160(@key.pubkey))
      if !verify_result
        client.puts(generate_text_msg(msg[:id], "sry, my change has problem"))
        return false
      end

      verify_result = verify_change(fund_tx, remote_fund_cells, remote_capacity,
                                    remote_fee, remote_pubkey)
      if !verify_result
        client.puts(generate_text_msg(msg[:id], "sry, your change has problem"))
        return -false
      end

      # check gpc capacity is right!
      total_fund_capacity = local_capacity + remote_capacity
      if CKB::Utils.byte_to_shannon(total_fund_capacity) != fund_tx.outputs[0].capacity
        client.puts(generate_text_msg(msg[:id], "sry, the gpc_capacity has problem"))
        return false
      end

      #-------------------------------------------------
      # I think is is unnecessary to do...
      # just verify the other part (version, deps, )
      # verify_result = verify_tx(fund_tx)
      # if verify_result == -1
      #   client.puts(generate_text_msg("sry, the fund tx has some problem..."))
      #   return -1
      # end

      # check the remote capcity is satisfactory.
      puts "#{remote_pubkey} replys your channel establishment request. The remote fund amount: #{remote_capacity}. The remote fee:#{remote_fee}"
      puts "Tell me whether you are willing to accept this request"
      while true
        response = STDIN.gets.chomp
        if response == "yes"
          break
        elsif response == "no"
          client.puts(generate_text_msg(msg[:id], "sry, remote node refuses your request."))
          return false
        else
          puts "your input is invalid"
        end
      end

      # generate the output locks in closing tx.
      init_args = fund_tx.outputs[0].lock.args
      lock_info = @tx_generator.parse_lock_args(init_args)
      lock_info[:nounce] += 1

      # generate the output locks in settlement tx.
      local_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                                  args: "0x" + lock_info[:pubkey_A], hash_type: CKB::ScriptHashType::TYPE)
      remote_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                                   args: "0x" + lock_info[:pubkey_B], hash_type: CKB::ScriptHashType::TYPE)

      # generate the output info in settlement tx.
      local = { capacity: CKB::Utils.byte_to_shannon(local_capacity), data: "0x", lock: local_default_lock }
      remote = { capacity: CKB::Utils.byte_to_shannon(remote_capacity), data: "0x", lock: remote_default_lock }

      closing_capacity = fund_tx.outputs[0].capacity

      input_type = ""
      output_type = ""
      closing_output_data = "0x"

      witness_closing = @tx_generator.generate_empty_witness(msg[:id], 1, lock_info[:nounce], input_type, output_type)
      witness_settlement = @tx_generator.generate_empty_witness(msg[:id], 0, lock_info[:nounce], input_type, output_type)

      # generate and sign ctx and stx.
      ctx_info = @tx_generator.generate_closing_info(msg[:id], lock_info, closing_capacity, closing_output_data, witness_closing, 0)
      stx_info = @tx_generator.generate_settlement_info(msg[:id], local, remote, witness_settlement, 0)

      stx_info_json = info_to_json(stx_info)
      ctx_info_json = info_to_json(ctx_info)

      # send the info
      msg_reply = { id: msg[:id], type: 3, ctx: ctx_info_json, stx: stx_info_json, capacity: local_capacity }.to_json
      client.puts(msg_reply)

      # update the database.
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { gpc_script: CKB::Serializers::ScriptSerializer.new(gpc_lock_script).serialize,
                                                                        remote_pubkey: remote_pubkey, fund_tx: msg[:fund_tx], ctx: ctx_info_json,
                                                                        stx: stx_info_json, status: 4, msg_cache: msg_reply, nounce: 1 } })

      return true
    when 3
      fund_tx = @coll_sessions.find({ id: msg[:id] }).first[:fund_tx]
      local_capacity = @coll_sessions.find({ id: msg[:id] }).first[:local_capacity]
      remote_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:remote_pubkey]
      sig_index = @coll_sessions.find({ id: msg[:id] }).first[:sig_index]
      fund_tx = CKB::Types::Transaction.from_h(fund_tx)
      remote_capacity = msg[:capacity]
      closing_output_data = "0x"

      remote_ctx_info = json_to_info(msg[:ctx])
      remote_stx_info = json_to_info(msg[:stx])

      # veirfy the remote signature is right.
      # verify the args are right.

      remote_ctx_result = verify_info_sig(remote_ctx_info, "closing", remote_pubkey, 1 - sig_index)
      remote_stx_result = verify_info_sig(remote_stx_info, "settlement", remote_pubkey, 1 - sig_index)

      if !remote_ctx_result || !remote_stx_result
        client.puts(generate_text_msg(msg[:id], "The signatures are invalid."))
        return false
      end

      # just check it is same as the remote one.
      # TO-DO, check the ctx and stx is right.
      init_args = fund_tx.outputs[0].lock.args
      lock_info = @tx_generator.parse_lock_args(init_args)
      lock_info[:nounce] += 1

      local_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                                  args: "0x" + lock_info[:pubkey_B], hash_type: CKB::ScriptHashType::TYPE)
      remote_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                                   args: "0x" + lock_info[:pubkey_A], hash_type: CKB::ScriptHashType::TYPE)

      local = { capacity: CKB::Utils.byte_to_shannon(local_capacity),
                data: "0x", lock: local_default_lock }
      remote = { capacity: CKB::Utils.byte_to_shannon(remote_capacity),
                 data: "0x", lock: remote_default_lock }
      closing_capacity = fund_tx.outputs[0].capacity

      input_type = ""
      output_type = ""
      closing_output_data = "0x"

      witness_closing = @tx_generator.generate_empty_witness(msg[:id], 1, lock_info[:nounce], input_type, output_type)
      witness_settlement = @tx_generator.generate_empty_witness(msg[:id], 0, lock_info[:nounce], input_type, output_type)

      # generate and sign ctx and stx.
      ctx_info = @tx_generator.generate_closing_info(msg[:id], lock_info, closing_capacity, closing_output_data, witness_closing, 1)
      stx_info = @tx_generator.generate_settlement_info(msg[:id], remote, local, witness_settlement, 1)

      if !verify_info_args(ctx_info, remote_ctx_info) || !verify_info_args(stx_info, remote_stx_info)
        client.puts(generate_text_msg(msg[:id], "sry, the args of closing or settlement transaction have problem."))
        return false
      end

      # sign
      ctx_info = @tx_generator.generate_closing_info(msg[:id], lock_info, closing_capacity,
                                                     closing_output_data, remote_ctx_info[:witness][0], 1)
      stx_info = @tx_generator.generate_settlement_info(msg[:id], remote, local,
                                                        remote_stx_info[:witness][0], 1)

      ctx_info_json = info_to_json(ctx_info)
      stx_info_json = info_to_json(stx_info)

      # send the info
      msg_reply = { id: msg[:id], type: 4, ctx: ctx_info_json, stx: stx_info_json }.to_json
      client.puts(msg_reply)

      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { ctx: ctx_info_json,
                                                                        stx: stx_info_json, status: 5, msg_cache: msg_reply, nounce: 1 } })

      return true
    when 4
      remote_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:remote_pubkey]
      local_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:local_pubkey]
      sig_index = @coll_sessions.find({ id: msg[:id] }).first[:sig_index]

      # check the data is not modified!
      local_ctx_info = json_to_info(@coll_sessions.find({ id: msg[:id] }).first[:ctx])
      local_stx_info = json_to_info(@coll_sessions.find({ id: msg[:id] }).first[:stx])

      remote_ctx_info = json_to_info(msg[:ctx])
      remote_stx_info = json_to_info(msg[:stx])

      local_ctx_sig = @tx_generator.parse_witness_lock(@tx_generator.parse_witness(local_ctx_info[:witness][0]).lock)[:sig_A]
      remote_ctx_sig = @tx_generator.parse_witness_lock(@tx_generator.parse_witness(remote_ctx_info[:witness][0]).lock)[:sig_A]

      local_stx_sig = @tx_generator.parse_witness_lock(@tx_generator.parse_witness(local_stx_info[:witness][0]).lock)[:sig_A]
      remote_stx_sig = @tx_generator.parse_witness_lock(@tx_generator.parse_witness(remote_stx_info[:witness][0]).lock)[:sig_A]

      local_ctx_result = verify_info_sig(local_ctx_info, "closing", local_pubkey, sig_index)
      local_stx_result = verify_info_sig(local_stx_info, "settlement", local_pubkey, sig_index)

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

      fund_tx = @tx_generator.sign_tx(fund_tx).to_h

      msg_reply = { id: msg[:id], type: 5, fund_tx: fund_tx }.to_json
      client.puts(msg_reply)

      # update the database
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { fund_tx: fund_tx,
                                                                        ctx: msg[:ctx], stx: msg[:stx],
                                                                        status: 6, msg_cache: msg_reply,
                                                                        stx_pend: 0, ctx_pend: 0 } })
      client.close
      return "done"
    when 5
      remote_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:remote_pubkey]
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

      fund_tx = @tx_generator.sign_tx(fund_tx_remote)

      # send the fund tx to chain.
      while true
        exist = @api.get_transaction(fund_tx.hash)
        break if exist != nil
        puts @api.send_transaction(fund_tx)
      end
      # update the database
      # @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { fund_tx: fund_tx.to_h, status: 6, latest_tx_hash: tx_hash } })
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { fund_tx: fund_tx.to_h, status: 6, stx_pend: 0, ctx_pend: 0 } })
      return 0
    when 6
      id = msg[:id]
      sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
      msg_type = msg[:msg_type]
      remote_pubkey = @coll_sessions.find({ id: id }).first[:remote_pubkey]
      stage = @coll_sessions.find({ id: id }).first[:stage]

      if stage != 1
        puts "the fund tx is not on chain, so the you can not make payment now..."
        puts id
        puts stage
        return false
      end

      if msg_type == "payment"
        local_pubkey = @coll_sessions.find({ id: id }).first[:local_pubkey]
        sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
        amount = msg[:amount]
        # all the information below should guarantee the stage is 1..

        # recv the new signed stx and unsigned ctx.
        remote_ctx_info = json_to_info(msg[:ctx_info])
        remote_stx_info = json_to_info(msg[:stx_info])
        amount = msg[:amount]

        local_stx_info = json_to_info(@coll_sessions.find({ id: msg[:id] }).first[:stx])
        local_ctx_info = json_to_info(@coll_sessions.find({ id: msg[:id] }).first[:ctx])

        local_update_stx_info = @tx_generator.update_stx(amount, local_stx_info, remote_pubkey, local_pubkey)
        local_update_ctx_info = @tx_generator.update_ctx(amount, local_ctx_info)

        # check the updated info is right.
        ctx_result = verify_info_args(local_update_ctx_info, remote_ctx_info)
        stx_result = verify_info_args(local_update_stx_info, remote_stx_info) &&
                     verify_info_sig(remote_stx_info, "settlement", remote_pubkey, 1 - sig_index)

        return false if !ctx_result || !stx_result

        # ask users whether the payments are right.

        puts "The remote node wants to pay you #{amount}."
        puts "Tell me whether you are willing to accept this payment."
        while true
          response = STDIN.gets.chomp
          if response == "yes"
            break
          elsif response == "no"
            client.puts(generate_text_msg(msg[:id], "sry, remote node refuses your request."))
            return false
          else
            puts "your input is invalid"
          end
        end

        msg_signed = generate_msg_from_info(remote_stx_info, "settlement")
        # sign ctx and stx and send them.
        witness_new = Array.new()
        for witness in remote_stx_info[:witness]
          witness_new << @tx_generator.generate_witness(id, 1, witness, msg_signed, sig_index)
        end
        remote_stx_info[:witness] = witness_new

        msg_signed = generate_msg_from_info(remote_ctx_info, "closing")
        # sign ctx and stx and send them.
        witness_new = Array.new()
        for witness in remote_ctx_info[:witness]
          witness_new << @tx_generator.generate_witness(id, 0, witness, msg_signed, sig_index)
        end
        remote_ctx_info[:witness] = witness_new
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
        terminal_tx = CKB::Types::Transaction.from_h(msg[:terminal_tx])
        local_stx_info = json_to_info(@coll_sessions.find({ id: msg[:id] }).first[:stx])

        # check the amount is right as local.
        for index in (0..local_stx_info[:outputs].length - 1)
          if terminal_tx.outputs[index].to_h != local_stx_info[:outputs][index].to_h
            client.puts(generate_text_msg(msg[:id], "sry, the output is not right."))
            return false
          end
        end

        puts "#{remote_pubkey} wants to close the channel with id #{id}."
        puts "Tell me whether you are willing to accept this request"

        while true
          response = STDIN.gets.chomp
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

        terminal_tx.witnesses[0] = @tx_generator.generate_witness(id, 0, terminal_tx.witnesses[0],
                                                                  terminal_tx.hash, sig_index)
        while true
          exist = @api.get_transaction(terminal_tx.hash)
          break if exist != nil
          puts @api.send_transaction(terminal_tx)
        end

        @coll_sessions.find_one_and_update({ id: id }, { "$set" => { stage: 2 } })
        return true
      end
    when 7
      # recv the signed ctx and stx, just check.
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

      # send the signed ctx.
      msg_signed = generate_msg_from_info(remote_ctx_info, "closing")
      # sign ctx and stx and send them.
      witness_new = Array.new()
      for witness in remote_ctx_info[:witness]
        witness_new << @tx_generator.generate_witness(id, 0, witness, msg_signed, sig_index)
      end
      remote_ctx_info[:witness] = witness_new

      ctx_info_json = info_to_json(remote_ctx_info)
      stx_info_json = info_to_json(remote_stx_info)

      msg = { id: id, type: 8, ctx_info: ctx_info_json }.to_json
      client.puts(msg)

      # update the local database.
      @coll_sessions.find_one_and_update({ id: id }, { "$set" => { ctx: ctx_info_json,
                                                                  stx: stx_info_json,
                                                                  nounce: nounce + 1,
                                                                  stx_pend: 0, ctx_pend: 0,
                                                                  status: 6, msg_cache: msg } })
      client.close
      return "done"
    when 8
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

      @coll_sessions.find_one_and_update({ id: id }, { "$set" => { ctx: ctx_info_json, stx: stx_pend,
                                                                  status: 6, stx_pend: 0, ctx_pend: 0, nounce: nounce + 1 } })
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

  def decoder(data)
    result = CKB::Utils.hex_to_bin(data).unpack("Q<")[0]
    return result.to_i
  end

  def encoder(data)
    return CKB::Utils.bin_to_hex([data].pack("Q<"))
  end

  def send_establish_channel(remote_ip, remote_port, amount, fee, timeout, type_script_hash = "", refund_lock_script = @lock)
    s = TCPSocket.open(remote_ip, remote_port)
    change_lock_script = refund_lock_script
    lock_hashes = [@lock_hash]
    local_type = find_type(type_script_hash)

    # prepare the msg components.
    local_cells = gather_inputs(amount, fee, lock_hashes, type_script_hash, local_type[:decoder], 17000)
    asset = { type_script_hash => amount }

    local_cells_h = local_cells.map(&:to_h)
    local_pubkey = CKB::Key.blake160(@key.pubkey)

    # get id.
    msg_digest = local_cells.to_json
    session_id = Digest::MD5.hexdigest(msg_digest)

    local_empty_stx = @tx_generator.generate_empty_settlement_info(amount, refund_lock_script, local_type[:type_script], local_type[:encoder])
    refund_capacity = local_empty_stx[:outputs][0].capacity
    local_empty_stx_json = info_to_json(local_empty_stx)

    local_change = @tx_generator.construct_change_output(local_cells, amount, fee, refund_capacity, change_lock_script,
                                                         local_type[:type_script], local_type[:encoder], local_type[:decoder])
    local_change_h = cell_to_hash(local_change)

    msg = { id: session_id, type: 1, pubkey: local_pubkey, cells: local_cells_h, fee: fee,
            timeout: timeout, asset: asset, change: local_change_h, stx_info: local_empty_stx_json }.to_json

    # send the msg.
    s.puts(msg)

    #insert the doc into database.
    doc = { id: session_id, local_pubkey: local_pubkey, remote_pubkey: "", status: 2,
            nounce: 0, ctx_tx: 0, stx_info: local_empty_stx_json, gpc_script: 0, local_cells: local_cells_h,
            timeout: timeout.to_s, msg_cache: msg.to_json, local_asset: asset, fee: fee,
            stage: 0, settlement_time: 0, sig_index: 0, closing_time: 0, local_change: local_change_h }
    return false if !insert_with_check(@coll_sessions, doc)

    # just keep listen
    while (1)
      msg = JSON.parse(s.gets, symbolize_names: true)
      ret = process_recv_message(s, msg)
      break if ret == "done"
    end
  end

  def send_payments(remote_ip, remote_port, id, amount)
    # s = TCPSocket.open(remote_ip, remote_port)

    remote_pubkey = @coll_sessions.find({ id: id }).first[:remote_pubkey]
    local_pubkey = @coll_sessions.find({ id: id }).first[:local_pubkey]
    sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
    stage = @coll_sessions.find({ id: id }).first[:stage]
    stx = @coll_sessions.find({ id: id }).first[:stx]
    ctx = @coll_sessions.find({ id: id }).first[:ctx]
    nounce = @coll_sessions.find({ id: id }).first[:nounce]

    stx_info = json_to_info(stx)
    ctx_info = json_to_info(ctx)

    if stage != 1
      puts "the fund tx is not on chain, so the you can not make payment now..."
      return false
    end

    # just read and update the latest stx, the new
    stx_info = @tx_generator.update_stx(amount, stx_info, local_pubkey, remote_pubkey)
    ctx_info = @tx_generator.update_ctx(amount, ctx_info)

    # sign the stx.
    msg_signed = generate_msg_from_info(stx_info, "settlement")

    # the msg ready.
    witness_new = Array.new()
    for witness in stx_info[:witness]
      witness_new << @tx_generator.generate_witness(id, 1, witness, msg_signed, sig_index)
    end
    stx_info[:witness] = witness_new

    ctx_info_json = info_to_json(ctx_info)
    stx_info_json = info_to_json(stx_info)

    # send the msg.
    msg = { id: id, type: 6, ctx_info: ctx_info_json, stx_info: stx_info_json, amount: amount, msg_type: "payment" }.to_json
    s.puts(msg)

    # update the local database.
    @coll_sessions.find_one_and_update({ id: id }, { "$set" => { stx_pend: stx_info_json, ctx_pend: ctx_info_json,
                                                                nounce: nounce, status: 7, msg_cache: msg } })
    while (1)
      msg = JSON.parse(s.gets, symbolize_names: true)
      ret = process_recv_message(s, msg)
      break if ret == "done"
    end
  end

  def send_closing_request(remote_ip, remote_port, id, fee = 10000)
    s = TCPSocket.open(remote_ip, remote_port)
    current_height = @api.get_tip_block_number
    remote_pubkey = @coll_sessions.find({ id: id }).first[:remote_pubkey]
    local_pubkey = @coll_sessions.find({ id: id }).first[:local_pubkey]
    sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
    stage = @coll_sessions.find({ id: id }).first[:stage]
    stx = @coll_sessions.find({ id: id }).first[:stx]
    ctx = @coll_sessions.find({ id: id }).first[:ctx]
    nounce = @coll_sessions.find({ id: id }).first[:nounce]
    fund_tx = @coll_sessions.find({ id: id }).first[:fund_tx]
    fund_tx = CKB::Types::Transaction.from_h(fund_tx)
    # require the stage is 1.
    if stage != 1
      puts "payment time passed."
      return false
    end

    # construct the input according to the fund tx.

    input_fund = @tx_generator.convert_input(fund_tx, 0, 0)
    fee_cell = gather_inputs(@cell_min_capacity, fee).inputs
    fee_cell_capacity = get_total_capacity(fee_cell)
    inputs = [input_fund] + fee_cell

    # constrcut the output......
    stx_info = json_to_info(stx)
    local_change_output = CKB::Types::Output.new(
      capacity: fee_cell_capacity - fee,
      lock: default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                                  args: CKB::Key.blake160(@key.pubkey), hash_type: CKB::ScriptHashType::TYPE),
      type: nil,
    )
    outputs = stx_info[:outputs]
    outputs << local_change_output

    outputs_data = stx_info[:outputs_data]
    outputs_data << "0x"

    witnesses = stx_info[:witness]

    for iter in fee_cell
      witnesses << CKB::Types::Witness.new
    end
    witnesses = witnesses.map do |witness|
      case witness
      when CKB::Types::Witness
        witness
      else
        @tx_generator.parse_witness(witness)
      end
    end
    # send
    terminal_tx = @tx_generator.generate_terminal_tx(id, nounce, inputs, outputs, outputs_data, witnesses, sig_index)

    msg = { id: id, type: 6, terminal_tx: terminal_tx.to_h, msg_type: "closing" }.to_json
    s.puts(msg)
    # update database.
    @coll_sessions.find_one_and_update({ id: id }, { "$set" => { stage: 2, status: 6, msg_cache: msg,
                                                                closing_time: current_height + 20 } })
    # s.close
    return "done"
  end
end
