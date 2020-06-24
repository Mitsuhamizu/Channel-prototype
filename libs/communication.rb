#!/usr/bin/ruby -w

require "socket"
require "json"
require "rubygems"
require "bundler/setup"
require "ckb"
require "../libs/tx_generator.rb"
require "digest/sha1"
require "mongo"

Mongo::Logger.logger.level = Logger::FATAL

class Communication
  def initialize(private_key)
    @key = CKB::Key.new(private_key)
    @api = CKB::API::new
    @wallet = CKB::Wallet.from_hex(@api, @key.privkey)
    @tx_generator = Tx_generator.new(@key)
    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database
    @coll_sessions = @db[@key.pubkey + "_session_pool"]
    @gpc_code_hash = "0xf3bdd1340f8db1fa67c3e87dad9ee9fe39b3cecc5afcfb380805245184bbc36f"
    @gpc_tx = "0x411d9b0b468d650cb0a577b3d93a18eac6ccff7b7515c41bd59b906606981568"
  end

  def insert_with_check(coll, doc)
    view = coll.find({ id: doc[:id] })
    if view.count_documents() != 0
      puts "sry, there is an record already, please using reset msg."
      return -1
    end
    coll.insert_one(doc)
    return 0
  end

  def gather_inputs(capacity, fee, from_block_number: 0)
    lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: CKB::Key.blake160(@key.pubkey), hash_type: CKB::ScriptHashType::TYPE)

    capacity = CKB::Utils.byte_to_shannon(capacity)

    output_GPC = CKB::Types::Output.new(
      capacity: capacity,
      lock: lock, #it should be the GPC lock script
    )
    output_GPC_data = "0x" #it should be the GPC data, well, it could be empty.

    output_change = CKB::Types::Output.new(
      capacity: 0,
      lock: lock,
    )

    # The capacity is only the capcity of GPC, we should add the fee to it is the total_capacity.
    output_change_data = "0x"

    i = @wallet.gather_inputs(
      capacity,
      output_GPC.calculate_min_capacity(output_GPC_data),
      output_change.calculate_min_capacity(output_change_data),
      fee,
      from_block_number: from_block_number,
    )
    return i
  end

  def generate_text_msg(text)
    return { type: 0, text: text }.to_json
  end

  def get_total_capacity(cells)
    total_capacity = 0
    for cell in cells
      validation = @api.get_live_cell(cell.previous_output)
      total_capacity += validation.cell.output.capacity
      if validation.status != "live"
        return -1
      end
    end
    return total_capacity
  end

  def check_cells(cells, capacity)
    capacity_check = get_total_capacity(cells)
    if capacity > capacity_check || capacity_check == -1
      return -1
    end
    return capacity_check
  end

  def verify_cell_dep(tx) # make sure the tx can be accepted by blockchain.
    # deps has is right.

    # about the outputdata, just ignore it.

  end

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

    if @tx_generator.verify_signature(msg_signed_closing, remote_sig_closing, remote_pubkey) != 0
      return -1
    end

    if @tx_generator.verify_signature(msg_signed_settlement, remote_sig_settlement, remote_pubkey) != 0
      return -1
    end

    return 0
  end

  def info_to_json(info)
    info_h = info
    info_h[:outputs] = info[:outputs].map(&:to_h)
    info_json = info_h.to_json
    return info_json
  end

  def json_to_info(json)
    info_h = JSON.parse(json, symbolize_names: true)
    info = info_h
    info[:outputs] = info_h[:outputs].map { |output| CKB::Types::Output.from_h(output) }
    return info
  end

  def process_recv_message(client, msg, command_file)
    # re calcualte and check the id is correct!
    type = msg[:type]
    view = @coll_sessions.find({ id: msg[:id] })
    if view.count_documents() == 0 && type != 1
      puts "sry, the msg's type is inconsistent with the type in local database!"
      return -1
    elsif view.count_documents() == 1
      view.each do |doc|
        if doc["status"] != type
          puts "sry, the msg's type is inconsistent with the type in local database!"
          return -1
        end
      end
    else
      puts "sry, there are more than one record about the id."
    end
    case type
    when -1 # Reset the status.
    when 0 # Just the plain text.
      puts msg[:text]
    when 1 # 1. check the msg.  2. accept the opening request and generate the unsigned fund tx.

      # parse the msg
      remote_pubkey = msg[:pubkey]
      remote_capacity = msg[:fund_capacity]
      remote_fee = msg[:fee]
      remote_fund_cells = msg[:fund_cells].map { |cell| CKB::Types::Input.from_h(cell) }
      timeout = msg[:timeout]

      # the type_script is nil in CkByte
      type_script = nil

      # check the cell is live and the capacity is enough.
      capacity_check = check_cells(remote_fund_cells, CKB::Utils.byte_to_shannon(remote_capacity) + remote_fee)
      if capacity_check == -1
        client.puts = generate_text_msg("sry, your capacity is not enough or your cells are not alive.")
        client.close
        return -1
      end

      remote_change = capacity_check - CKB::Utils.byte_to_shannon(remote_capacity) - remote_fee

      # ask whether willing to accept the request, the capacity is same as negotiations.
      puts "The remote capacity: #{remote_capacity}. The remote fee:#{remote_fee}"
      puts "Tell me whether you are willing to accept this request"
      while true
        # response = STDIN.gets.chomp
        response = command_file.gets.gsub("\n", "")
        if response == "yes"
          break
        elsif response == "no"
          puts "reject it "
          return -1
        else
          puts "your input is invalid"
        end
      end

      # get the capacity and fee.
      while true
        puts "Please input the capacity and fee you want to use for funding"       #these code need to be more robust.
        local_capacity = command_file.gets.gsub("\n", "").to_i
        local_fee = command_file.gets.gsub("\n", "").to_i
        break
      end

      #gather the fund input.
      local_fund_cells = gather_inputs(local_capacity, local_fee)
      local_fund_cells_h = local_fund_cells.inputs.map(&:to_h)
      local_change = local_fund_cells.capacities - CKB::Utils.byte_to_shannon(local_capacity) - local_fee

      # generate the info of fund.
      gpc_capacity = remote_capacity + local_capacity
      fund_cells = remote_fund_cells + local_fund_cells.inputs
      fund_witnesses = Array.new()
      for iter in fund_cells
        fund_witnesses << CKB::Types::Witness.new       # the witness will be customized in UDT.
      end

      # Let us create the fund tx!
      fund_tx = @tx_generator.generate_fund_tx(fund_cells, gpc_capacity, local_change, remote_change, remote_pubkey, timeout, type_script, fund_witnesses)

      # update database.
      doc = { id: msg[:id], privkey: @key.privkey, local_pubkey: CKB::Key.blake160(@key.pubkey), remote_pubkey: remote_pubkey, status: 3, nounce: 0, ctx: 0, stx: 0, gpc_scirpt_hash: fund_tx.outputs[0].lock.compute_hash, local_fund_cells: local_fund_cells_h, fund_tx: fund_tx.to_h, timeout: timeout }
      ret = insert_with_check(@coll_sessions, doc)
      if ret == -1
        puts "double insert."
        return -1
      end

      # send it
      msg = { id: msg[:id], type: 2, fee: local_fee, fund_tx: fund_tx.to_h, capacity: local_capacity }.to_json
      client.puts(msg)
    when 2 # 1. check the msg. 2 generate and sign ctx and stx.
      fund_tx = CKB::Types::Transaction.from_h(msg[:fund_tx])
      remote_capacity = msg[:capacity]
      remote_fee = msg[:fee]
      local_fund_cells = @coll_sessions.find({ id: msg[:id] }).first[:local_fund_cells]
      remote_fund_cells = fund_tx.inputs.map(&:to_h) - local_fund_cells
      remote_fund_cells = remote_fund_cells.map { |cell| CKB::Types::Input.from_h(cell) }
      local_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:local_pubkey]
      timeout = @coll_sessions.find({ id: msg[:id] }).first[:timeout]

      # check the depend cells, version, input since, type.

      # get the remote pubkey (blake120). Assumption, there are only two pubkey.
      input_group = @tx_generator.group_tx_input(fund_tx)
      for key in input_group.keys
        if key != CKB::Key.blake160(@key.pubkey)
          remote_pubkey = key
        end
      end

      # compute the gpc script hash by myself, and check it. So here, we can make sure that the GPC args are right.
      init_args = @tx_generator.generate_lock_args(0, timeout, 0, local_pubkey[2..-1], remote_pubkey[2..-1])
      gpc_lock_script = CKB::Types::Script.new(code_hash: @gpc_code_hash, args: init_args, hash_type: CKB::ScriptHashType::DATA)

      if fund_tx.outputs[0].lock.compute_hash != gpc_lock_script.compute_hash
        return -1
      end
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { gpc_scirpt_hash: gpc_lock_script.compute_hash, remote_pubkey: remote_pubkey } })

      # check the cells are alive and the capacity is enough.
      capacity_check = check_cells(remote_fund_cells, CKB::Utils.byte_to_shannon(remote_capacity) + remote_fee)
      if capacity_check == -1
        msg = generate_text_msg("sry, your capacity is not enough or your cells are not alive.")
        client.puts msg
        client.close
        return -1
      end

      # check the remote capcity is satisfactory.
      puts "remote capacity #{remote_capacity}, remote fee: #{remote_fee}"

      # generate the output locks in closing tx.
      init_args = fund_tx.outputs[0].lock.args
      lock_info = @tx_generator.parse_lock_args(init_args)
      lock_info[:nounce] += 1

      # generate the output locks in settlement tx.
      local_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: "0x" + lock_info[:pubkey_A], hash_type: CKB::ScriptHashType::TYPE)
      remote_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: "0x" + lock_info[:pubkey_B], hash_type: CKB::ScriptHashType::TYPE)

      fee = 20000

      # generate the output info in settlement tx.
      local = { capacity: fund_tx.outputs[0].capacity - CKB::Utils.byte_to_shannon(remote_capacity) - fee, data: "0x", lock: local_default_lock }
      remote = { capacity: CKB::Utils.byte_to_shannon(remote_capacity) - fee, data: "0x", lock: remote_default_lock }
      closing_capacity = fund_tx.outputs[0].capacity - fee

      input_type = ""
      output_type = ""
      closing_output_data = "0x"

      witness_closing = @tx_generator.generate_empty_witness(1, lock_info[:nounce], input_type, output_type)
      witness_settlement = @tx_generator.generate_empty_witness(0, lock_info[:nounce], input_type, output_type)

      # generate and sign ctx and stx.
      ctx_info = @tx_generator.generate_closing_info(lock_info, closing_capacity, closing_output_data, witness_closing, 0) # 0: output 1: output_data 2: witness
      stx_info = @tx_generator.generate_settlement_info(local, remote, witness_settlement, 0) # 0: output 1: output_data 2: witness

      ctx_info_json = info_to_json(ctx_info)
      stx_info_json = info_to_json(stx_info)

      # update the database.
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { fund_tx: msg[:fund_tx], ctx: ctx_info_json, stx: ctx_info_json, status: 4 } })

      # send the info
      msg = { id: msg[:id], type: 3, ctx: ctx_info_json, stx: stx_info_json, fee: fee, capacity: fund_tx.outputs[0].capacity / (10 ** 8) - remote_capacity }.to_json
      client.puts(msg)
    when 3
      fund_tx = @coll_sessions.find({ id: msg[:id] }).first[:fund_tx]
      fund_tx = CKB::Types::Transaction.from_h(fund_tx)
      remote_capacity = msg[:capacity]

      remote_ctx_info = json_to_info(msg[:ctx])
      remote_stx_info = json_to_info(msg[:stx])

      closing_output_data = "0x"

      # verify the signatures of ctx and stx.
      verify_result = verify_info(msg, 0)
      if verify_result != 0
        puts "The signatures are invalid."
        return -1
      end

      # verify the amount of ctx and stx are right.
      fee = msg[:fee]

      # sign the ctx and stx.

      # just check these information are same as the remote one.
      init_args = fund_tx.outputs[0].lock.args
      lock_info = @tx_generator.parse_lock_args(init_args)
      lock_info[:nounce] += 1

      local_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: "0x" + lock_info[:pubkey_B], hash_type: CKB::ScriptHashType::TYPE)
      remote_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: "0x" + lock_info[:pubkey_A], hash_type: CKB::ScriptHashType::TYPE)

      local = { capacity: fund_tx.outputs[0].capacity - CKB::Utils.byte_to_shannon(remote_capacity) - fee, data: "0x", lock: local_default_lock }
      remote = { capacity: CKB::Utils.byte_to_shannon(remote_capacity) - fee, data: "0x", lock: remote_default_lock }
      closing_capacity = fund_tx.outputs[0].capacity - fee

      # check the outputs in stx are right.

      ctx_info = @tx_generator.generate_closing_info(lock_info, closing_capacity, closing_output_data, remote_ctx_info[:witness], 1) # 0: output 1: output_data 2: witness
      stx_info = @tx_generator.generate_settlement_info(remote, local, remote_stx_info[:witness], 1) # 0: output 1: output_data 2: witness

      ctx_info_json = info_to_json(ctx_info)
      stx_info_json = info_to_json(stx_info)

      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { ctx: ctx_info_json, stx: stx_info_json, status: 5 } })

      # send the info
      msg = { id: msg[:id], type: 4, ctx: ctx_info_json, stx: stx_info_json }.to_json
      client.puts(msg)
    when 4
      # just check the ctx and stx is same as the local except the witness

      # just set the remote witness to empty and compare it with local version.

      # just check the witenss!

      # check the data is not modified!
      verify_result = verify_info(msg, 0)
      if verify_result != 0
        puts "The data is modified."
        return -1
      end

      # check the remote signature
      verify_result = verify_info(msg, 1)
      if verify_result != 0
        puts "The signatures are invalid."
        return -1
      end

      # sign and send the tx_fund
      fund_tx = @coll_sessions.find({ id: msg[:id] }).first[:fund_tx]
      fund_tx = CKB::Types::Transaction.from_h(fund_tx)

      fund_tx = @tx_generator.sign_tx(fund_tx).to_h

      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { fund_tx: fund_tx, ctx: msg[:ctx], stx: msg[:stx], status: 6 } })

      # update the database
      msg = { id: msg[:id], type: 5, fund_tx: fund_tx }.to_json
      client.puts(msg)
    when 5

      # just check the fund_tx is same as local except the witness

      # sign the fund_tx and send it to chain
      fund_tx_local = @coll_sessions.find({ id: msg[:id] }).first[:fund_tx]
      fund_tx_local = CKB::Types::Transaction.from_h(fund_tx_local)

      fund_tx_remote = msg[:fund_tx]
      fund_tx_remote = CKB::Types::Transaction.from_h(fund_tx_remote)

      fund_tx_local_hash = fund_tx_local.compute_hash
      fund_tx_remote_hash = fund_tx_remote.compute_hash

      if fund_tx_local_hash != fund_tx_remote_hash
        puts "fund tx is not consistent."
        return -1
      end

      fund_tx = @tx_generator.sign_tx(fund_tx_remote)

      # update the database
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { fund_tx: fund_tx.to_h, status: 6 } })
      # @api.send_transaction(fund_tx)
      # now it is time to send the fund tx.
    when 6

      # just check the witness is valid.

      # add the local witness

      # update the database.
    when 7

      # just check the witness is valid.

      # add the local witness

      # send it to chain.
    end
  end

  # def send(pbk, trg_ip, trg_port, capacity, fee)
  # end

  def listen(src_port, command_file)
    puts "listen start"
    api = CKB::API::new
    stage = 0
    server = TCPServer.open(src_port)
    loop {
      Thread.start(server.accept) do |client|
        #parse the msg
        while (1)
          msg = JSON.parse(client.gets, symbolize_names: true)
          ret = process_recv_message(client, msg, command_file)
          if ret == 100
            break
          end
        end
      end
    }
  end

  def send_establish_channel(remote_ip, remote_port, capacity, fee, command_file)
    s = TCPSocket.open(remote_ip, remote_port)

    # prepare the msg.
    local_fund_cells = gather_inputs(capacity, fee)
    local_fund_cells = local_fund_cells.inputs.map(&:to_h)
    local_pubkey = CKB::Key.blake160(@key.pubkey)
    lock_timeout = 100
    # get id.
    msg_digest = local_fund_cells.to_json
    session_id = Digest::MD5.hexdigest(msg_digest)

    msg = { id: session_id, type: 1, pubkey: local_pubkey, fund_cells: local_fund_cells, fund_capacity: capacity, fee: fee, timeout: lock_timeout }.to_json
    #insert the doc into database.
    doc = { id: session_id, privkey: @key.privkey, local_pubkey: local_pubkey, remote_pubkey: "", status: 2, nounce: 0, ctx: 0, stx: 0, gpc_scirpt_hash: 0, local_fund_cells: local_fund_cells, timeout: lock_timeout }
    ret = insert_with_check(@coll_sessions, doc)
    if ret == -1
      puts "double insert."
      return -1
    end

    # send the msg.
    s.puts(msg)

    while (1)
      msg = JSON.parse(s.gets, symbolize_names: true)
      process_recv_message(s, msg, command_file)
    end
  end
end
