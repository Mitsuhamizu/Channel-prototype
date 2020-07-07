#!/usr/bin/ruby -w

require "socket"
require "json"
require "rubygems"
require "bundler/setup"
require "ckb"
require "digest/sha1"
require "mongo"
require "../libs/tx_generator.rb"
require "../libs/mongodb_operate.rb"
require "../libs/mongodb_operate.rb"
require "../libs/ckb_interaction.rb"
require "../libs/verification.rb"

class Communication
  def initialize(private_key)
    @key = CKB::Key.new(private_key)
    @api = CKB::API::new
    @wallet = CKB::Wallet.from_hex(@api, @key.privkey)
    @tx_generator = Tx_generator.new(@key)

    # it is for testing
    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC_copy")
    @db = @client.database
    @db.drop()
    # copy the db
    copy_db("GPC", "GPC_copy")
    # @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC_copy")

    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
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
    info[:outputs] = info[:outputs].map(&:to_h)
    info[:witness] = info[:witness].map do |witness|
      case witness
      when CKB::Types::Witness
        CKB::Serializers::WitnessArgsSerializer.from(witness).serialize
      else
        witness
      end
    end
    return info.to_json
  end

  def json_to_info(json)
    info_h = JSON.parse(json, symbolize_names: true)
    info_h[:outputs] = info_h[:outputs].map { |output| CKB::Types::Output.from_h(output) }
    return info_h
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
      remote_capacity = msg[:fund_capacity]
      remote_fee = msg[:fee]
      remote_fund_cells = msg[:fund_cells].map { |cell| CKB::Types::Input.from_h(cell) }
      timeout = msg[:timeout].to_i

      # the type_script is nil in CKByte
      type_script = nil

      # check the cell is live and the capacity is enough.
      capacity_check = check_cells(remote_fund_cells, CKB::Utils.byte_to_shannon(remote_capacity) + remote_fee)

      if !capacity_check
        client.puts(generate_text_msg(msg[:id], "sry, your capacity is not enough or your cells are not alive."))
        return false
      end

      # Ask whether willing to accept the request, the capacity is same as negotiations.
      puts "#{remote_pubkey} wants to establish channel with you. The remote fund amount: #{remote_capacity}. The remote fee:#{remote_fee}"
      puts "Tell me whether you are willing to accept this request"

      # It should be more robust.
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

      # Get the capacity and fee. These code need to be more robust.
      while true
        puts "Please input the capacity and fee you want to use for funding"
        local_capacity = STDIN.gets.chomp.to_i
        local_fee = STDIN.gets.chomp.to_i
        break
      end

      # gather the fund inputs.
      local_fund_cells = gather_inputs(local_capacity, local_fee)
      local_fund_cells_h = local_fund_cells.inputs.map(&:to_h)
      local_change = local_fund_cells.capacities - CKB::Utils.byte_to_shannon(local_capacity) - local_fee

      # calcualte the remote change.
      remote_change = capacity_check - CKB::Utils.byte_to_shannon(remote_capacity) - remote_fee

      # generate the info of fund.
      gpc_capacity = remote_capacity + local_capacity
      fund_cells = remote_fund_cells + local_fund_cells.inputs
      fund_witnesses = Array.new()
      for iter in fund_cells
        fund_witnesses << CKB::Types::Witness.new       # the witness will be customized in UDT.
      end

      # Let us create the fund tx!
      fund_tx = @tx_generator.generate_fund_tx(msg[:id], fund_cells, gpc_capacity, local_change, remote_change,
                                               remote_pubkey, timeout, type_script, fund_witnesses)

      # send it
      msg_reply = { id: msg[:id], type: 2, fee: local_fee, fund_tx: fund_tx.to_h,
                    capacity: local_capacity }.to_json
      client.puts(msg_reply)

      # update database.
      doc = { id: msg[:id], local_pubkey: CKB::Key.blake160(@key.pubkey), remote_pubkey: remote_pubkey,
              status: 3, nounce: 0, ctx: 0, stx: 0, gpc_script: CKB::Serializers::ScriptSerializer.new(fund_tx.outputs[0].lock).serialize,
              local_fund_cells: local_fund_cells_h, fund_tx: fund_tx.to_h, msg_cache: msg_reply,
              timeout: timeout.to_s, local_capacity: local_capacity, stage: 0, settlement_time: 0,
              sig_index: 1 }

      return insert_with_check(@coll_sessions, doc) ? true : false
    when 2

      # parse the msg.
      fund_tx = CKB::Types::Transaction.from_h(msg[:fund_tx])
      remote_capacity = msg[:capacity]
      remote_fee = msg[:fee]
      local_fund_cells = @coll_sessions.find({ id: msg[:id] }).first[:local_fund_cells]
      local_fund_cells = local_fund_cells.map { |cell| JSON.parse(cell.to_json, symbolize_names: true) }
      remote_fund_cells = fund_tx.inputs.map(&:to_h) - local_fund_cells
      remote_fund_cells = remote_fund_cells.map { |cell| CKB::Types::Input.from_h(cell) }
      local_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:local_pubkey]
      local_capacity = @coll_sessions.find({ id: msg[:id] }).first[:local_capacity]
      local_fee = @coll_sessions.find({ id: msg[:id] }).first[:local_fee]
      timeout = @coll_sessions.find({ id: msg[:id] }).first[:timeout].to_i

      # get the remote pubkey (blake160). Assumption, there are only two pubkey.
      remote_pubkey = nil
      input_group = @tx_generator.group_tx_input(fund_tx)
      for key in input_group.keys
        if key != CKB::Key.blake160(@key.pubkey)
          remote_pubkey = key
          break
        end
      end

      # About the one way channel.
      if remote_pubkey == nil
        puts "It is a one-way channel......."
      end

      # compute the gpc script by myself, and check it. So here, we can make sure that the GPC args are right.
      init_args = @tx_generator.generate_lock_args(msg[:id], 0, timeout, 0, local_pubkey[2..-1], remote_pubkey[2..-1])
      gpc_lock_script = CKB::Types::Script.new(code_hash: @tx_generator.gpc_code_hash, args: init_args, hash_type: CKB::ScriptHashType::DATA)
      if CKB::Serializers::ScriptSerializer.new(fund_tx.outputs[0].lock).serialize != CKB::Serializers::ScriptSerializer.new(gpc_lock_script).serialize
        client.puts(generate_text_msg(msg[:id], "sry, the gpc lock is inconsistent with my verison."))
        return false
      end

      # check the cells are alive and the capacity is enough.
      capacity_check = check_cells(remote_fund_cells, CKB::Utils.byte_to_shannon(remote_capacity) + remote_fee)
      if !capacity_check
        client.puts(generate_text_msg(msg[:id], "sry, your capacity is not enough or your cells are not alive."))
        return false
      end

      # check change is right!
      local_fund_cells = local_fund_cells.map { |cell| CKB::Types::Input.from_h(cell) }
      verify_result = verify_change(fund_tx, local_fund_cells, local_capacity,
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

      ctx_info_json = info_to_json(ctx_info)
      stx_info_json = info_to_json(stx_info)

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

      return true
    when 5
      remote_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:remote_pubkey]

      # sign the fund_tx.
      fund_tx_local = @coll_sessions.find({ id: msg[:id] }).first[:fund_tx]
      fund_tx_local = CKB::Types::Transaction.from_h(fund_tx_local)

      fund_tx_remote = msg[:fund_tx]
      fund_tx_remote = CKB::Types::Transaction.from_h(fund_tx_remote)

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
      @api.send_transaction(fund_tx)

      # update the database
      # @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { fund_tx: fund_tx.to_h, status: 6, latest_tx_hash: tx_hash } })
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { fund_tx: fund_tx.to_h, status: 6, stx_pend: 0, ctx_pend: 0 } })
      return 0
    when 6
      id = msg[:id]
      remote_pubkey = @coll_sessions.find({ id: id }).first[:remote_pubkey]
      local_pubkey = @coll_sessions.find({ id: id }).first[:local_pubkey]
      sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
      stage = @coll_sessions.find({ id: id }).first[:stage]
      amount = msg[:amount]

      # all the information below should guarantee the stage is 1..
      if stage != 1
        puts "the fund tx is not on chain, so the you can not make payment now..."
        return false
      end

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
                                                                  status: 6, msg_cache: msg,
                                                                  stx_pend: 0, ctx_pend: 0, nounce: nounce + 1 } })
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

  def send_establish_channel(remote_ip, remote_port, capacity, fee, timeout)
    s = TCPSocket.open(remote_ip, remote_port)

    # prepare the msg components.
    local_fund_cells = gather_inputs(capacity, fee)
    local_fund_cells = local_fund_cells.inputs.map(&:to_h)
    local_pubkey = CKB::Key.blake160(@key.pubkey)
    lock_timeout = timeout

    # get id.
    msg_digest = local_fund_cells.to_json
    session_id = Digest::MD5.hexdigest(msg_digest)
    msg = { id: session_id, type: 1, pubkey: local_pubkey, fund_cells: local_fund_cells,
            fund_capacity: capacity, fee: fee, timeout: lock_timeout }.to_json

    # send the msg.
    s.puts(msg)

    #insert the doc into database.
    doc = { id: session_id, local_pubkey: local_pubkey, remote_pubkey: "", status: 2,
            nounce: 0, ctx: 0, stx: 0, gpc_script: 0, local_fund_cells: local_fund_cells,
            timeout: lock_timeout.to_s, msg_cache: msg.to_json, local_capacity: capacity,
            local_fee: fee, stage: 0, settlement_time: 0, sig_index: 0 }
    return false if !insert_with_check(@coll_sessions, doc)

    # just keep listen
    while (1)
      msg = JSON.parse(s.gets, symbolize_names: true)
      process_recv_message(s, msg)
    end
  end

  def send_payments(remote_ip, remote_port, id, amount)
    s = TCPSocket.open(remote_ip, remote_port)

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
    msg = { id: id, type: 6, ctx_info: ctx_info_json, stx_info: stx_info_json, amount: amount }.to_json
    s.puts(msg)

    # update the local database.
    @coll_sessions.find_one_and_update({ id: id }, { "$set" => { stx_pend: stx_info_json,
                                                                ctx_pend: ctx_info_json,
                                                                nounce: nounce,
                                                                status: 7, msg_cache: msg } })
    while (1)
      msg = JSON.parse(s.gets, symbolize_names: true)
      process_recv_message(s, msg)
    end
  end
end
