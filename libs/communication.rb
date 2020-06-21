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
    @gpc_code_hash = "0x3982bfaca9cd36a652f7133ae47e2f446d543bac449d20a9f1e7f7a6fd484dc0"
    @gpc_tx = "0x7f6a792503f9bc4a73f6db61afa7fadf5332cc7ecf21140ff75b6312356e0ac5"
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

  def verify_info(info, sig_index)
    fund_tx = @coll_sessions.find({ id: info[:id] }).first[:fund_tx]
    fund_tx = CKB::Types::Transaction.from_h(fund_tx)

    # load the blake2b hash of remote pubkey.
    gpc_lock = fund_tx.outputs[0].lock.args
    lock_info = @tx_generator.parse_lock_args(gpc_lock)
    remote_pubkey = lock_info[:pubkey_A]

    ctx_info_h = JSON.parse(info[:ctx], symbolize_names: true)

    ctx_info_h[:outputs] = ctx_info_h[:outputs].map { |output| CKB::Types::Output.from_h(output) }

    # verify the ctx.

    # get the signature
    remote_closing_witness = @tx_generator.parse_witness(ctx_info_h[:witness])
    remote_sig_closing = case sig_index
      when 0
        remote_closing_witness[:sig_A]
      when 1
        remote_closing_witness[:sig_B]
      end

    # generate the signed content.
    msg_signed_closing = CKB::Serializers::OutputSerializer.new(ctx_info_h[:outputs][0]).serialize

    # add the length of witness
    witness_len = (ctx_info_h[:witness].bytesize - 2) / 2
    witness_len = CKB::Utils.bin_to_hex([witness_len].pack("Q<"))[2..-1]

    # add the empty witness
    empty_witness = @tx_generator.generate_raw_witness(remote_closing_witness[:flag], remote_closing_witness[:nounce])
    msg_signed_closing = (msg_signed_closing + witness_len + empty_witness).strip

    # verify stx
    stx_info_h = JSON.parse(info[:stx], symbolize_names: true)
    stx_info_h[:outputs] = stx_info_h[:outputs].map { |output| CKB::Types::Output.from_h(output) }

    # load the signature of settlement info.
    remote_settlement_witness = @tx_generator.parse_witness(stx_info_h[:witness])
    remote_sig_settlement = case sig_index
      when 0
        remote_settlement_witness[:sig_A]
      when 1
        remote_settlement_witness[:sig_B]
      end

    # generate the msg of settlement
    msg_signed_settlement = "0x"
    for output in stx_info_h[:outputs]
      data = CKB::Serializers::OutputSerializer.new(output).serialize[2..-1]
      msg_signed_settlement += data
    end

    # add the length of witness
    witness_len = (stx_info_h[:witness].bytesize - 2) / 2
    witness_len = CKB::Utils.bin_to_hex([witness_len].pack("Q<"))[2..-1]

    # add the empty witness
    empty_witness = @tx_generator.generate_raw_witness(remote_settlement_witness[:flag], remote_settlement_witness[:nounce])
    msg_signed_settlement = (msg_signed_settlement + witness_len + empty_witness).strip

    if @tx_generator.verify_signature(msg_signed_closing, remote_sig_closing, remote_pubkey) != 0
      return -1
    end

    if @tx_generator.verify_signature(msg_signed_settlement, remote_sig_settlement, remote_pubkey) != 0
      return -1
    end

    return 0
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
    when 1 # 1. check the msg.  2. accept the opening request and generate the unsign fund tx.
      # parse the msg
      remote_pubkey = msg[:pubkey]
      remote_capacity = msg[:fund_capacity]
      remote_fee = msg[:fee]
      remote_fund_cells = msg[:fund_cells].map { |cell| CKB::Types::Input.from_h(cell) }
      timeout = msg[:timeout]

      # check the cell is live and the capacity is enough.
      capacity_check = check_cells(remote_fund_cells, remote_capacity + remote_fee)
      if capacity_check == -1
        msg = generate_text_msg("sry, your capacity is not enough or your cells are not alive.")
        client.puts msg
        client.close
        return -1
      end
      remote_change = capacity_check - remote_capacity - remote_fee

      #Ask whether willing to accept the request.
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

      #the capacity and fee.
      while true
        puts "Please input the capacity and fee you want to use for funding"       #these code need to be more robust.
        local_capacity = command_file.gets.gsub("\n", "").to_i
        local_fee = command_file.gets.gsub("\n", "").to_i
        break
      end

      #gather the fund input.
      local_fund_cells = gather_inputs(local_capacity, local_fee)
      local_fund_cells_h = local_fund_cells.inputs.map(&:to_h)

      local_change = local_fund_cells.capacities - local_capacity - local_fee
      gpc_capacity = remote_capacity + local_capacity

      #merge the fund cells and the witness.
      fund_cells = remote_fund_cells + local_fund_cells.inputs

      # Let us create the tx.
      fund_tx = @tx_generator.generate_fund_tx(fund_cells, gpc_capacity, local_change, remote_change, remote_pubkey, timeout)

      # create new record.
      doc = { id: msg[:id], privkey: @key.privkey, status: 3, nounce: 0, ctx: 0, stx: 0, gpc_scirpt_hash: fund_tx.outputs[0].lock.compute_hash, local_fund_cells: local_fund_cells_h, fund_tx: fund_tx.to_h }
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

      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { gpc_scirpt_hash: fund_tx.outputs[0].lock.compute_hash } })

      capacity_check = check_cells(remote_fund_cells, remote_capacity + remote_fee)
      if capacity_check == -1
        msg = generate_text_msg("sry, your capacity is not enough or your cells are not alive.")
        client.puts msg
        client.close
        return -1
      end

      # I need the pubkey!!!!
      init_args = fund_tx.outputs[0].lock.args
      lock_info = @tx_generator.parse_lock_args(init_args)

      local_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: lock_info[:pubkey_A], hash_type: CKB::ScriptHashType::TYPE)
      remote_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: lock_info[:pubkey_B], hash_type: CKB::ScriptHashType::TYPE)

      fee = 1000

      local = { capacity: fund_tx.outputs[1].capacity - fee / 2, data: "0x", lock: local_default_lock }
      remote = { capacity: fund_tx.outputs[2].capacity - fee / 2, data: "0x", lock: remote_default_lock }
      closing_capacity = local[:capacity] + remote[:capacity]

      # generate and sign ctx and stx.
      ctx_info = @tx_generator.generate_closing_info(lock_info, closing_capacity, "0x", 0, 0) # 0: output 1: output_data 2: witness
      stx_info = @tx_generator.generate_settlement_info(local, remote, lock_info[:nounce], 0, 0) # 0: output 1: output_data 2: witness
      ctx_info_h = ctx_info
      stx_info_h = stx_info
      ctx_info_h[:outputs] = ctx_info[:outputs].map(&:to_h)
      stx_info_h[:outputs] = stx_info[:outputs].map(&:to_h)
      ctx_info_h = ctx_info_h.to_json
      stx_info_h = stx_info_h.to_json

      # update the database.
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { ctx: ctx_info_h } })
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { stx: ctx_info_h } })
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { status: 4 } })

      # send the info
      msg = { id: msg[:id], type: 3, ctx: ctx_info_h, stx: stx_info_h, fee: fee, closing_capacity: closing_capacity }.to_json
      client.puts(msg)
      # now, we have the enough info of
    when 3
      fund_tx = @coll_sessions.find({ id: msg[:id] }).first[:fund_tx]
      fund_tx = CKB::Types::Transaction.from_h(fund_tx)
      closing_capacity = msg[:closing_capacity]

      remote_ctx_info_h = JSON.parse(msg[:ctx], symbolize_names: true)
      remote_ctx_info_h[:outputs] = remote_ctx_info_h[:outputs].map { |output| CKB::Types::Output.from_h(output) }

      remote_stx_info_h = JSON.parse(msg[:stx], symbolize_names: true)
      remote_stx_info_h[:outputs] = remote_stx_info_h[:outputs].map { |output| CKB::Types::Output.from_h(output) }
      # verify the ctx and stx.

      verify_result = verify_info(msg, 0)

      if verify_result != 0
        puts "The signatures are invalid."
        return -1
      end

      # verify the amoutn is right.
      fee = msg[:fee]

      # sign the ctx and stx.
      init_args = fund_tx.outputs[0].lock.args
      lock_info = @tx_generator.parse_lock_args(init_args)

      local_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: lock_info[:pubkey_B], hash_type: CKB::ScriptHashType::TYPE)
      remote_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: lock_info[:pubkey_A], hash_type: CKB::ScriptHashType::TYPE)

      local = { capacity: fund_tx.outputs[2].capacity - fee / 2, data: "0x", lock: local_default_lock }
      remote = { capacity: fund_tx.outputs[1].capacity - fee / 2, data: "0x", lock: remote_default_lock }

      ctx_info = @tx_generator.generate_closing_info(lock_info, closing_capacity, "0x", remote_ctx_info_h[:witness], 1) # 0: output 1: output_data 2: witness
      stx_info = @tx_generator.generate_settlement_info(local, remote, lock_info[:nounce], remote_stx_info_h[:witness], 1) # 0: output 1: output_data 2: witness
      ctx_info_h = ctx_info
      stx_info_h = stx_info
      ctx_info_h[:outputs] = ctx_info[:outputs].map(&:to_h)
      stx_info_h[:outputs] = stx_info[:outputs].map(&:to_h)
      ctx_info_h = ctx_info_h.to_json
      stx_info_h = stx_info_h.to_json

      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { ctx: ctx_info_h } })
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { stx: ctx_info_h } })
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { status: 5 } })

      # send the info
      msg = { id: msg[:id], type: 4, ctx: ctx_info_h, stx: stx_info_h }.to_json
      client.puts(msg)
    when 4
      # just check the ctx and stx is same as the local except the witness

      # just check the witenss!

      # sign and send the tx_fund
      fund_tx = @coll_sessions.find({ id: msg[:id] }).first[:fund_tx]
      fund_tx = CKB::Types::Transaction.from_h(fund_tx)

      fund_tx = @tx_generator.sign_tx(fund_tx, 0)
      # update the database

    when 5

      # just check the fund_tx is same as local except the witness

      # sign the fund_tx and send it to chain
      fund_tx = @coll_sessions.find({ id: msg[:id] }).first[:fund_tx]
      fund_tx = CKB::Types::Transaction.from_h(fund_tx)

      fund_tx = @tx_generator.sign_tx(fund_tx, 0)
      # update the database

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
    #gather the input.
    s = TCPSocket.open(remote_ip, remote_port)
    local_fund_cells = gather_inputs(capacity, fee)
    local_fund_cells = local_fund_cells.inputs.map(&:to_h)

    #init the msg
    msg_digest = local_fund_cells.to_json
    session_id = Digest::MD5.hexdigest(msg_digest)
    msg = { id: session_id, type: 1, pubkey: CKB::Key.blake160(@key.pubkey), fund_cells: local_fund_cells, fund_capacity: capacity, fee: fee, timeout: 100 }.to_json
    #insert the doc into database.
    doc = { id: session_id, privkey: @key.privkey, status: 2, nounce: 0, ctx: 0, stx: 0, gpc_scirpt_hash: 0, local_fund_cells: local_fund_cells }
    ret = insert_with_check(@coll_sessions, doc)
    s.puts(msg)
    if ret == -1
      puts "double insert."
      return -1
    end

    while (1)
      msg = JSON.parse(s.gets, symbolize_names: true)
      process_recv_message(s, msg, command_file)
    end
  end
end
