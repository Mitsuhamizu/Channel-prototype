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
require "date"
require_relative "tx_generator.rb"
require_relative "verification.rb"
require_relative "type_script_info.rb"
require "telegram/bot"
$VERBOSE = nil

class Communication
  def initialize(private_key)
    $VERBOSE = nil
    @key = CKB::Key.new(private_key)
    @api = CKB::API::new
    @rpc = CKB::RPC.new(host: "http://localhost:8116", timeout_config: {})
    @tx_generator = Tx_generator.new(@key)
    @lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: CKB::Key.blake160(@key.pubkey), hash_type: CKB::ScriptHashType::TYPE)
    @lock_hash = @lock.compute_hash

    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database
    @coll_sessions = @db[@key.pubkey + "_session_pool"]
    @coll_cells = @db[@key.pubkey + "_cell_pool"]

    @path_to_file = __dir__ + "/../miscellaneous/files/"
    @logger = Logger.new(@path_to_file + "gpc.log")
    @token = "896274990:AAEOmszCWLd2dLCL7PGWFlBjJjtxQOHmJpU"
    @group_id = -1001372639358
  end

  # Generate the plain text msg, client will print it.
  def generate_text_msg(id, text)
    return { type: 0, id: id, text: text }.to_json
  end

  def convert_text_to_hash(funding)
    udt_type_script_hash = load_type()
    funding_type_script_version = {}
    for key in funding.keys()
      if key == :ckb
        type_script = ""
      elsif key == :udt
        type_script = udt_type_script_hash
      end
      funding_type_script_version[type_script] = funding[key]
    end
    return funding_type_script_version
  end

  # def generate_investment_info(asset)
  def convert_hash_to_text(asset)
    udt_type_script_hash = load_type()
    remote_investment = ""

    for asset_type_hash in asset.keys()
      if asset_type_hash == ""
        asset_type = "ckb"
      elsif asset_type_hash == udt_type_script_hash
        asset_type = "udt"
      end
      remote_investment += "#{asset_type}: #{asset_type_hash == "" ? asset[asset_type_hash] / 10 ** 8 : asset[asset_type_hash]} "
    end
    return remote_investment
  end

  # These two functions are used to parse and construct ctx_info and stx_info.
  # Info structure. outputs:[], outputs_data:[], witnesses:[].
  def info_to_hash(info)
    info_h = info
    info_h[:outputs] = info_h[:outputs].map(&:to_h)
    info_h[:witnesses] = info_h[:witnesses].map do |witness|
      case witness
      when CKB::Types::Witness
        CKB::Serializers::WitnessArgsSerializer.from(witness).serialize
      else
        witness
      end
    end

    return info_h
  end

  def hash_to_info(info_h)
    info_h[:outputs] = info_h[:outputs].map { |output| CKB::Types::Output.from_h(output) }
    return info_h
  end

  # two method to convert hash to cell and cell to hash.
  # cell structure. output:[], outputs_data[].
  def hash_to_cell(cells_h)
    cells = []
    for cell_h in cells_h
      cell_h[:output] = CKB::Types::Output.from_h(cell_h[:output])
      cells << cell_h
    end
    return cells
  end

  def cell_to_hash(cells)
    cells_h = []
    for cell in cells
      cell[:output] = cell[:output].to_h
      cells_h << cell
    end
    return cells_h
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

  def load_json_file(path)
    data_raw = File.read(path)
    data_json = JSON.parse(data_raw, symbolize_names: true)
    return data_json
  end

  def load_type()
    # type of asset.
    data_json = load_json_file(@path_to_file + "contract_info.json")
    type_script_json = data_json[:type_script]
    type_script_h = JSON.parse(type_script_json, symbolize_names: true)
    type_script = CKB::Types::Script.from_h(type_script_h)
    type_script_hash = type_script.compute_hash
    return type_script_hash
  end

  def record_result(result)
    data_hash = {}
    if File.file?(@path_to_file + "result.json")
      data_raw = File.read(@path_to_file + "result.json")
      data_hash = JSON.parse(data_raw, symbolize_names: true)
    end
    data_hash = data_hash.merge(result)
    data_json = data_hash.to_json
    file = File.new(@path_to_file + "result.json", "w")
    file.syswrite(data_json)
  end

  def get_balance_in_channel(stx_info, type_info, pubkey)
    balance = nil
    for index in (0..stx_info[:outputs].length - 1)
      output = stx_info[:outputs][index]
      output_data = stx_info[:outputs_data][index]
      if output.lock.args == pubkey
        balance = type_info[:type_script] == nil ? output.capacity - output.calculate_min_capacity(output_data) : type_info[:decoder].call(output_data)
        break
      end
    end
    return balance
  end

  # The main part of communcator
  def process_recv_message(client, msg)

    # msg has two fixed field, type and id.
    type = msg[:type]
    view = @coll_sessions.find({ id: msg[:id] })

    # if there is no record and the msg is not the first step.
    @logger.info("#{@key.pubkey} msg#{type} comes, the number of record in the db is #{view.count_documents()}, id: #{msg[:id]}")
    if view.count_documents() == 0 && type != 1
      msg_reply = generate_text_msg(msg[:id], "sry, the msg's type is inconsistent with the type in local database!")
      client.puts (msg_reply)
      return false
      # if there is a record, just check the msg type is same as local status.
    elsif view.count_documents() == 1 && (![-2, -1, 0].include? type)
      view.each do |doc|
        if doc["status"] != type
          msg_reply = generate_text_msg(msg[:id], "sry, the msg's type is inconsistent with the type in local database! Your version is #{type} I expect #{doc["status"]}")
          @logger.info("sry, the msg's type is inconsistent with the type in local database! Your version is #{type} I expect #{doc["status"]}")
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
      @logger.info("#{@key.pubkey} receive msg 1.")
      # parse the msg
      remote_pubkey = msg[:pubkey]
      remote_cells = msg[:cells].map { |cell| CKB::Types::Input.from_h(cell) }
      remote_fee_fund = msg[:fee_fund]
      remote_change = hash_to_cell(msg[:change])
      remote_asset = msg[:asset]
      remote_stx_info = hash_to_info(msg[:stx_info])
      timeout = msg[:timeout].to_i
      local_pubkey = CKB::Key.blake160(@key.pubkey)
      locks = [@lock]
      refund_lock_script = @lock
      change_lock_script = refund_lock_script

      @logger.info("#{@key.pubkey} check msg_1: msg parse finished.")

      remote_asset = remote_asset.map() { |key, value| [key.to_s, value] }.to_h

      remote_investment = convert_hash_to_text(remote_asset)

      @logger.info("#{@key.pubkey} check msg_1: checking negtive remote input begin.")

      for amount in remote_asset.values()
        if amount < 0
          record_result({ "sender_step1_error_amount_negative": amount })
          return false
        end
      end

      record_result({ "sender_step1_error_fee_negative": remote_fee_fund }) if remote_fee_fund < 0
      return false if remote_fee_fund < 0

      @logger.info("#{@key.pubkey} check msg_1: checking negtive remote input finished.")
      remote_cell_check_result, remote_cell_check_value = check_cells(remote_cells, remote_asset, remote_fee_fund, remote_change, remote_stx_info)

      # check remote cells.
      if remote_cell_check_result != "success"
        client.puts(generate_text_msg(msg[:id], "sry, there are some problem abouty your cells."))
        record_result({ "receiver_step1_" + remote_cell_check_result => remote_cell_check_value })
        return false
      end

      # Ask whether willing to accept the request, the capacity is same as negotiations

      @logger.info("#{@key.pubkey} check msg_1: finished.")

      # read data from json file.
      while true
        # testing
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
        local_funding = { ckb: 0, udt: 2000000 }
        for asset_type in local_funding.keys()
          local_funding[asset_type] = asset_type == :ckb ? CKB::Utils.byte_to_shannon(BigDecimal(local_funding[asset_type])) : BigDecimal(local_funding[asset_type])
          local_funding[asset_type] = local_funding[asset_type].to_i
        end
        local_fee_fund = 3000
        break
      end
      local_asset = convert_text_to_hash(local_funding)

      @logger.info("#{@key.pubkey} send msg_2: input finished.")

      # check all amount are positive.
      for funding_amount in local_asset.values()
        if funding_amount < 0
          record_result({ "receiver_gather_funding_error_negative": funding_amount }) if funding_amount < 0
          return false
        end
      end

      if local_fee_fund < 0
        record_result({ "receiver_gather_fee_error_negative": local_fee_fund })
        return false
      end

      @logger.info("#{@key.pubkey} send msg_2: gather input begin.")
      # gather local fund inputs.

      local_cells = gather_inputs(local_asset, local_fee_fund, locks, change_lock_script,
                                  refund_lock_script, @coll_cells)

      if local_cells.is_a? Numeric
        record_result({ "receiver_gather_funding_error_insufficient": local_cells })
        return false
      end

      @logger.info("#{@key.pubkey} send msg_2: gather input finished.")

      return false if local_cells == nil

      msg_digest = ((remote_cells + local_cells).map(&:to_h)).to_json
      channel_id = Digest::MD5.hexdigest(msg_digest)

      @logger.info("#{@key.pubkey} send msg_2: generate settlement info and change: begin")

      local_asset = local_asset.sort.reverse.to_h

      # generate the settlement infomation.
      local_empty_stx = @tx_generator.generate_empty_settlement_info(local_asset, refund_lock_script)
      stx_info = merge_stx_info(remote_stx_info, local_empty_stx)
      stx_info_h = info_to_hash(Marshal.load(Marshal.dump(stx_info)))
      refund_capacity = local_empty_stx[:outputs][0].capacity
      local_empty_stx_h = info_to_hash(Marshal.load(Marshal.dump(local_empty_stx)))

      # calculate change.
      local_change = @tx_generator.construct_change_output(local_cells, local_asset, local_fee_fund, refund_capacity, change_lock_script)

      gpc_capacity = get_total_capacity(local_cells + remote_cells)

      @logger.info("#{@key.pubkey} send msg_2: generate settlement info and change: finished.")
      @logger.info("#{@key.pubkey} send msg_2: generate fund tx: begin.")

      outputs = Array.new()
      outputs_data = Array.new()
      for cell in remote_change + local_change
        outputs << cell[:output]
        outputs_data << cell[:output_data]
      end

      for output in outputs
        gpc_capacity -= output.capacity
      end

      # generate the info of gpc output
      gpc_capacity -= (remote_fee_fund + local_fee_fund)

      udt_type_script_hash = load_type()
      total_asset = {}

      total_asset[""] = [local_asset, remote_asset].map { |h| h[""] }.sum
      total_asset[udt_type_script_hash] = [local_asset, remote_asset].map { |h| h[udt_type_script_hash] }.sum

      gpc_cell = @tx_generator.construct_gpc_output(gpc_capacity, total_asset,
                                                    channel_id, timeout, remote_pubkey[2..-1], local_pubkey[2..-1])

      @logger.info("#{@key.pubkey} send msg_2: gpc output generation: finished.")
      outputs.insert(0, gpc_cell[:output])
      outputs_data.insert(0, gpc_cell[:output_data])

      # generate the inputs and witness of fund tx.
      fund_cells = remote_cells + local_cells
      fund_witnesses = Array.new()
      for iter in fund_cells
        fund_witnesses << CKB::Types::Witness.new
      end

      type_dep = []
      for asset_type in total_asset.keys()
        current_type = find_type(asset_type)
        type_dep.append(current_type[:type_dep]) if current_type[:type_dep] != nil
      end

      # Let us create the fund tx!
      fund_tx = @tx_generator.generate_fund_tx(fund_cells, outputs, outputs_data, fund_witnesses, type_dep)
      local_cells_h = local_cells.map(&:to_h)
      @logger.info("#{@key.pubkey} send msg_2: generate fund tx: finished.")
      # send it
      msg_reply = { id: msg[:id], updated_id: channel_id, type: 2, asset: local_asset,
                    fee_fund: local_fee_fund, fund_tx: fund_tx.to_h, stx_info: local_empty_stx_h,
                    pubkey: local_pubkey }.to_json
      client.puts(msg_reply)

      # update database.
      doc = { id: channel_id, local_pubkey: local_pubkey, remote_pubkey: remote_pubkey,
              status: 3, nounce: 0, ctx_info: 0, stx_info: stx_info_h.to_json,
              local_cells: local_cells_h, fund_tx: fund_tx.to_h, msg_cache: msg_reply,
              timeout: timeout.to_s, local_asset: local_asset, stage: 0, settlement_time: 0,
              sig_index: 1, closing_time: 0, stx_info_pend: 0, ctx_info_pend: 0 }
      record_result({ "id" => channel_id })
      @logger.info("#{@key.pubkey} send msg_2: insert record #{channel_id}")
      return insert_with_check(@coll_sessions, doc) ? true : false
    when 2
      @logger.info("#{@key.pubkey} receive msg 2.")

      # parse the msg.
      fund_tx = CKB::Types::Transaction.from_h(msg[:fund_tx])
      remote_asset = msg[:asset].map() { |key, value| [key.to_s, value] }.to_h
      remote_pubkey = msg[:pubkey]
      remote_fee_fund = msg[:fee_fund]
      timeout = @coll_sessions.find({ id: msg[:id] }).first[:timeout].to_i
      remote_stx_info_h = msg[:stx_info]
      remote_stx_info = hash_to_info(Marshal.load(Marshal.dump(remote_stx_info_h)))
      remote_updated_id = msg[:updated_id]

      # load local info.
      local_cells = (@coll_sessions.find({ id: msg[:id] }).first[:local_cells]).map(&:to_h)
      local_cells = local_cells.map { |cell| JSON.parse(cell.to_json, symbolize_names: true) }
      local_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:local_pubkey]
      local_asset = JSON.parse(@coll_sessions.find({ id: msg[:id] }).first[:local_asset])
      local_fee_fund = @coll_sessions.find({ id: msg[:id] }).first[:fee_fund]
      local_change = hash_to_cell(JSON.parse(@coll_sessions.find({ id: msg[:id] }).first[:local_change], symbolize_names: true))
      local_stx_info = hash_to_info(JSON.parse(@coll_sessions.find({ id: msg[:id] }).first[:stx_info], symbolize_names: true))
      sig_index = @coll_sessions.find({ id: msg[:id] }).first[:sig_index]

      # generate investment info
      remote_investment = convert_hash_to_text(remote_asset)

      # get remote cells.
      remote_cells = fund_tx.inputs.map(&:to_h) - local_cells
      remote_cells = remote_cells.map { |cell| CKB::Types::Input.from_h(cell) }
      local_cells = local_cells.map { |cell| CKB::Types::Input.from_h(cell) }

      # load gpc output.
      gpc_output = fund_tx.outputs[0]
      gpc_output_data = fund_tx.outputs_data[0]

      # construct total asset.
      udt_type_script_hash = load_type()

      total_asset = {}
      total_asset[""] = [local_asset, remote_asset].map { |h| h[""] }.sum
      total_asset[udt_type_script_hash] = [local_asset, remote_asset].map { |h| h[udt_type_script_hash] }.sum

      @logger.info("#{@key.pubkey} check msg_2: msg parsed.")

      # check updated_id.

      msg_digest = ((local_cells + remote_cells).map(&:to_h)).to_json
      local_updated_id = Digest::MD5.hexdigest(msg_digest)
      if local_updated_id != remote_updated_id
        client.puts(generate_text_msg(msg[:id], "sry, the channel ids are inconsistent."))
        record_result({ "sender_step2_id_inconsistent" => true })
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

      # About the one way channel.

      # if remote_asset.values().sum == 0
      #   puts "It is a one-way channel, tell me whether you want to accept it."
      #   while true
      #     # response = STDIN.gets.chomp
      #     response = STDIN.gets.chomp
      #     if response == "yes"
      #       break
      #     elsif response == "no"
      #       msg_reply = generate_text_msg(msg[:id], "sry, remote node refuses your request since it is one-way channel.")
      #       client.puts(msg_reply)
      #       return false
      #     else
      #       puts "your input is invalid"
      #     end
      #   end
      # end

      # check there is no my cells in remote cell.
      for cell in remote_cells
        if @api.get_live_cell(cell.previous_output).status != "live"
          client.puts(generate_text_msg(msg[:id], "sry, cell dead."))
          record_result({ "sender_step2_error_cell_dead" => true })
          return false
        end
        output = @api.get_live_cell(cell.previous_output).cell.output
        return false if local_cell_lock_lib.include? output.lock.compute_hash
      end

      change_outputs_all = fund_tx.outputs[1..-1]
      change_outputs_data_all = fund_tx.outputs_data[1..-1]
      change_all = []

      for index in (0..(change_outputs_all.length() - 1))
        change_all << { output: change_outputs_all[index], output_data: change_outputs_data_all[index] }
      end

      # the local change.
      change_all_h = cell_to_hash(change_all)
      local_change_h = cell_to_hash(local_change)
      change_all_set = change_all_h.to_set()
      local_change_set = local_change_h.to_set()

      if !local_change_set.subset?(change_all_set)
        client.puts(generate_text_msg(msg[:id], "sry, something wrong with my local change."))
        record_result({ "sender_step2_local_change_modified" => true })
        return false
      end

      remote_change_h = (change_all_set - local_change_set).to_a
      remote_change = hash_to_cell(remote_change_h)

      @logger.info("#{@key.pubkey} check msg_2: separte remote change.")

      # assemble remote change
      @logger.info("#{@key.pubkey} check msg_2: start to check remote cells.")
      # check the cells remote party providing is right.
      remote_cell_check_result, remote_cell_check_value = check_cells(remote_cells, remote_asset, remote_fee_fund, remote_change, remote_stx_info)

      if remote_cell_check_result != "success"
        client.puts(generate_text_msg(msg[:id], "sry, there are some problem abouty your cells."))
        record_result({ "sender_step2_" + remote_cell_check_result => remote_cell_check_value })
        return false
      end

      @logger.info("#{@key.pubkey} check msg_2: remote cells have been checked.")

      # gpc outptu checked.
      gpc_capacity = local_stx_info[:outputs][0].capacity + remote_stx_info[:outputs][0].capacity

      # regenerate the cell by myself, and check remote one is same as it.

      gpc_cell = @tx_generator.construct_gpc_output(gpc_capacity, total_asset,
                                                    local_updated_id, timeout, local_pubkey[2..-1], remote_pubkey[2..-1])

      if !(gpc_cell[:output].to_h == gpc_output.to_h && gpc_cell[:output_data] == gpc_output_data)
        client.puts(generate_text_msg(msg[:id], "sry, gpc output goes wrong."))
        record_result({ "sender_step2_error_gpc_modified": true })
        return false
      end

      @logger.info("#{@key.pubkey} check msg_2: gpc output has been checked.")
      #-------------------------------------------------
      # I think is is unnecessary to do in a prototype...
      # just verify the other part (version, deps, )
      # verify_result = verify_tx(fund_tx)
      # if verify_result == -1
      #   client.puts(generate_text_msg("sry, the fund tx has some problem..."))
      #   return -1
      # end
      # check the remote capcity is satisfactory.

      @logger.info("#{@key.pubkey} check msg_2: read input finished.")

      # generate empty witnesses.
      # the two magic number is flag of witness and the nounce.
      # The nounce of first pair of stx and ctx is 1.
      witness_closing = @tx_generator.generate_empty_witness(local_updated_id, 1, 1)
      witness_settlement = @tx_generator.generate_empty_witness(local_updated_id, 0, 1)
      # merge the stx_info.
      stx_info = merge_stx_info(local_stx_info, remote_stx_info)
      # generate and sign ctx and stx.
      ctx_info = @tx_generator.generate_closing_info(local_updated_id, gpc_output, gpc_output_data, witness_closing, sig_index)
      stx_info = @tx_generator.sign_settlement_info(local_updated_id, stx_info, witness_settlement, sig_index)

      # convert the info into json to store and send.
      ctx_info_h = info_to_hash(Marshal.load(Marshal.dump(ctx_info)))
      stx_info_h = info_to_hash(Marshal.load(Marshal.dump(stx_info)))

      @logger.info("#{@key.pubkey} send msg_3: stx and ctx construction finished.")

      # send the info
      msg_reply = { id: local_updated_id, type: 3, ctx_info: ctx_info_h, stx_info: stx_info_h }.to_json
      client.puts(msg_reply)

      @logger.info("#{@key.pubkey} send msg_3: msg sent.")

      # update the database.
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { remote_pubkey: remote_pubkey, fund_tx: msg[:fund_tx], ctx_info: ctx_info_h.to_json,
                                                                        stx_info: stx_info_h.to_json, status: 4, msg_cache: msg_reply, nounce: 1, id: local_updated_id } })
      return true
    when 3
      @logger.info("#{@key.pubkey} receive msg 3.")
      # load many info...
      fund_tx = @coll_sessions.find({ id: msg[:id] }).first[:fund_tx]
      local_stx_info = hash_to_info(JSON.parse(@coll_sessions.find({ id: msg[:id] }).first[:stx_info], symbolize_names: true))
      remote_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:remote_pubkey]
      sig_index = @coll_sessions.find({ id: msg[:id] }).first[:sig_index]
      fund_tx = CKB::Types::Transaction.from_h(fund_tx)
      remote_ctx_info = hash_to_info(msg[:ctx_info])
      remote_stx_info = hash_to_info(msg[:stx_info])

      # check the ctx_info and stx_info args are right.
      # just generate it by myself and compare.
      witness_closing = @tx_generator.generate_empty_witness(msg[:id], 1, 1)
      witness_settlement = @tx_generator.generate_empty_witness(msg[:id], 0, 1)

      output = Marshal.load(Marshal.dump(fund_tx.outputs[0]))
      local_ctx_info = @tx_generator.generate_closing_info(msg[:id], output, fund_tx.outputs_data[0], witness_closing, sig_index)
      local_stx_info = @tx_generator.sign_settlement_info(msg[:id], local_stx_info, witness_settlement, sig_index)

      # set the witness to empty and then check everything is consistent.
      if !verify_info_args(local_ctx_info, remote_ctx_info) || !verify_info_args(local_stx_info, remote_stx_info)
        client.puts(generate_text_msg(msg[:id], "sry, the args of closing or settlement transaction have problem."))
        record_result({ "receiver_step3_error_info_modified": true })
        return false
      end

      # veirfy the remote signature is right.
      # sig_index is the the signature index. 0 or 1.
      # So I just load my local sig_index, 1-sig_index is the remote sig_index.
      remote_ctx_result = verify_info_sig(remote_ctx_info, "closing", remote_pubkey, 1 - sig_index)
      remote_stx_result = verify_info_sig(remote_stx_info, "settlement", remote_pubkey, 1 - sig_index)
      if !remote_ctx_result || !remote_stx_result
        client.puts(generate_text_msg(msg[:id], "The signatures are invalid."))
        record_result({ "receiver_step3_error_signature_invalid": true })
        return false
      end

      output = Marshal.load(Marshal.dump(fund_tx.outputs[0]))

      # sign
      ctx_info = @tx_generator.generate_closing_info(msg[:id], output, fund_tx.outputs_data[0], remote_ctx_info[:witnesses][0], sig_index)
      stx_info = @tx_generator.sign_settlement_info(msg[:id], local_stx_info, remote_stx_info[:witnesses][0], sig_index)

      ctx_info_h = info_to_hash(ctx_info)
      stx_info_h = info_to_hash(stx_info)

      # send the info
      msg_reply = { id: msg[:id], type: 4, ctx_info: ctx_info_h, stx_info: stx_info_h }.to_json
      client.puts(msg_reply)

      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { ctx_info: ctx_info_h.to_json, stx_info: stx_info_h.to_json,
                                                                        status: 5, msg_cache: msg_reply, nounce: 1 } })

      return true
    when 4
      @logger.info("#{@key.pubkey} receive msg 4.")
      remote_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:remote_pubkey]
      local_pubkey = @coll_sessions.find({ id: msg[:id] }).first[:local_pubkey]
      local_inputs = @coll_sessions.find({ id: msg[:id] }).first[:local_cells]
      local_inputs = local_inputs.map { |cell| CKB::Types::Input.from_h(cell) }

      sig_index = @coll_sessions.find({ id: msg[:id] }).first[:sig_index]

      # check the data is not modified!
      # the logic is
      # 1. my signature is not modified
      # 2. my signature can still be verified.
      local_ctx_info_h = JSON.parse(@coll_sessions.find({ id: msg[:id] }).first[:ctx_info], symbolize_names: true)
      local_stx_info_h = JSON.parse(@coll_sessions.find({ id: msg[:id] }).first[:stx_info], symbolize_names: true)

      local_ctx_info = hash_to_info(Marshal.load(Marshal.dump(local_ctx_info_h)))
      local_stx_info = hash_to_info(Marshal.load(Marshal.dump(local_stx_info_h)))

      remote_ctx_info = hash_to_info(msg[:ctx_info])
      remote_stx_info = hash_to_info(msg[:stx_info])

      local_ctx_sig = @tx_generator.parse_witness_lock(@tx_generator.parse_witness(local_ctx_info[:witnesses][0]).lock)[:sig_A]
      remote_ctx_sig = @tx_generator.parse_witness_lock(@tx_generator.parse_witness(remote_ctx_info[:witnesses][0]).lock)[:sig_A]

      local_stx_sig = @tx_generator.parse_witness_lock(@tx_generator.parse_witness(local_stx_info[:witnesses][0]).lock)[:sig_A]
      remote_stx_sig = @tx_generator.parse_witness_lock(@tx_generator.parse_witness(remote_stx_info[:witnesses][0]).lock)[:sig_A]

      local_ctx_result = verify_info_sig(remote_ctx_info, "closing", local_pubkey, sig_index)
      local_stx_result = verify_info_sig(remote_stx_info, "settlement", local_pubkey, sig_index)

      # make sure my signatures are consistent.
      if local_ctx_sig != remote_ctx_sig ||
         local_stx_sig != remote_stx_sig
        client.puts(generate_text_msg(msg[:id], "Signature inconsistent."))
        record_result({ "sender_step4_error_signature_inconsistent": true })
        return false
      end

      # verify signature to make sure the data is not modified
      if !local_ctx_result || !local_stx_result
        record_result({ "sender_step4_error_info_modified": true })
        client.puts(generate_text_msg(msg[:id], "The data is modified."))
        return false
      end

      # check the remote signature
      remote_ctx_result = verify_info_sig(remote_ctx_info, "closing", remote_pubkey, 1 - sig_index)
      remote_stx_result = verify_info_sig(remote_stx_info, "settlement", remote_pubkey, 1 - sig_index)

      if !remote_ctx_result || !remote_stx_result
        record_result({ "sender_step4_error_signature_invalid": true })
        client.puts(generate_text_msg(msg[:id], "The signatures are invalid."))
        return false
      end

      # sign and send the fund_tx
      fund_tx = @coll_sessions.find({ id: msg[:id] }).first[:fund_tx]
      fund_tx = CKB::Types::Transaction.from_h(fund_tx)

      # the logic is, I only sign the inputs in my local cells.
      fund_tx = @tx_generator.sign_tx(fund_tx, local_inputs).to_h

      remote_ctx_info_h = info_to_hash(remote_ctx_info)
      remote_stx_info_h = info_to_hash(remote_stx_info)

      msg_reply = { id: msg[:id], type: 5, fund_tx: fund_tx }.to_json
      client.puts(msg_reply)
      # update the database
      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { fund_tx: fund_tx, ctx_info: remote_ctx_info_h.to_json, stx_info: remote_stx_info_h.to_json,
                                                                        status: 6, msg_cache: msg_reply } })

      client.close()
      puts "channel is established, please wait the transaction on chain."
      return "done"
    when 5
      @logger.info("#{@key.pubkey} receive msg 5.")
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
        record_result({ "receiver_step5_error_signature_invalid": true })
        client.puts(generate_text_msg(msg[:id], "The signatures are invalid."))
        return false
      end

      fund_tx_local_hash = fund_tx_local.compute_hash
      fund_tx_remote_hash = fund_tx_remote.compute_hash

      if fund_tx_local_hash != fund_tx_remote_hash
        record_result({ "receiver_step5_error_fund_tx_modified": true })
        client.puts(generate_text_msg(msg[:id], "fund tx is not consistent."))
        return false
      end

      fund_tx = @tx_generator.sign_tx(fund_tx_remote, local_inputs)

      # send the fund tx to chain.

      begin
        while true
          exist = @api.get_transaction(fund_tx.hash)
          break if exist != nil
          @api.send_transaction(fund_tx) if exist == nil
        end
      rescue Exception => e
        # puts e
      end
      # update the database

      @coll_sessions.find_one_and_update({ id: msg[:id] }, { "$set" => { fund_tx: fund_tx.to_h, status: 6 } })

      puts "channel is established, please wait the transaction is on chain."

      return "done"
    when 6
      id = msg[:id]
      sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
      msg_type = msg[:msg_type]
      remote_pubkey = @coll_sessions.find({ id: id }).first[:remote_pubkey]
      stage = @coll_sessions.find({ id: id }).first[:stage]

      @logger.info("#{@key.pubkey} check msg 6: basic value parsed.")

      # there are two type msg when type is 6.
      # 1. payment request.
      # 2. closing request.
      if msg_type == "payment"
        # check the stage.
        if stage != 1
          puts "the fund tx is not on chain, so the you can not make payment now..."
          return false
        end

        @logger.info("#{@key.pubkey} check msg 6: branch payment.")
        local_pubkey = @coll_sessions.find({ id: id }).first[:local_pubkey]
        sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
        type_hash = @coll_sessions.find({ id: id }).first[:type_hash]
        payment = msg[:payment].map() { |key, value| [key.to_s, value] }.to_h
        remote_investment = convert_hash_to_text(payment)
        tg_msg = nil

        # recv the new signed stx and unsigned ctx.
        remote_ctx_info = hash_to_info(msg[:ctx_info])
        remote_stx_info = hash_to_info(msg[:stx_info])

        @logger.info("#{@key.pubkey} check msg 6 payment: msg parsed.")
        local_ctx_info = @coll_sessions.find({ id: id }).first[:ctx_info]
        local_stx_info = @coll_sessions.find({ id: id }).first[:stx_info]

        local_ctx_info = hash_to_info(JSON.parse(local_ctx_info, symbolize_names: true))
        local_stx_info = hash_to_info(JSON.parse(local_stx_info, symbolize_names: true))
        # check the value is right.
        # payment
        if payment.length == 1
          tg_msg = msg[:tg_msg]
          if payment.values()[0] < 0
            record_result({ "receiver_step6_make_payments_error_negative": payment_value })
            return false
          end
          # exchange
        elsif payment.length == 2
          if payment["0xecc762badc4ed2a459013afd5f82ec9b47d83d6e4903db1207527714c06f177b"] * 10 ** 8 != -payment[""]
            puts "The data is wrong."
          end
        end

        @logger.info("#{@key.pubkey} check msg 6 payment: load local ctx and stx.")

        local_update_stx_info = @tx_generator.update_stx(payment, local_stx_info, remote_pubkey, local_pubkey)
        local_update_ctx_info = @tx_generator.update_ctx(local_ctx_info)

        @logger.info("#{@key.pubkey} check msg 6 payment: construct local stx and ctx.")

        # check the balance is enough.
        if local_update_stx_info.is_a? Numeric
          record_result({ "receiver_step6_make_payments_error_insufficient": local_update_stx_info })
          return false
        end

        # this is becase the output capacity is not consistent.
        if !verify_info_args(local_update_ctx_info, remote_ctx_info) || !verify_info_args(local_update_stx_info, remote_stx_info)
          record_result({ "receiver_step6_make_payments_error_info_inconsistent": true })
          return false
        end
        if !verify_info_sig(remote_stx_info, "settlement", remote_pubkey, 1 - sig_index)
          record_result({ "receiver_step6_make_payments_error_signature_invalid": true })
          return false
        end

        @logger.info("#{@key.pubkey} check msg 6 payment: check stx and ctx are consistent.")

        # generate the signed message.
        msg_signed = generate_msg_from_info(remote_stx_info, "settlement")

        # sign ctx and stx and send them.
        witness_new = Array.new()
        for witness in remote_stx_info[:witnesses]
          witness_new << @tx_generator.generate_witness(id, witness, msg_signed, sig_index)
        end
        remote_stx_info[:witnesses] = witness_new
        msg_signed = generate_msg_from_info(remote_ctx_info, "closing")

        # sign ctx and stx and send them.
        witness_new = Array.new()
        for witness in remote_ctx_info[:witnesses]
          witness_new << @tx_generator.generate_witness(id, witness, msg_signed, sig_index)
        end
        remote_ctx_info[:witnesses] = witness_new

        # update the database.
        ctx_info_h = info_to_hash(remote_ctx_info)
        stx_info_h = info_to_hash(remote_stx_info)

        msg = { id: id, type: 7, ctx_info: ctx_info_h, stx_info: stx_info_h }.to_json
        client.puts(msg)
        @logger.info("#{@key.pubkey} send msg_7: msg sent.")
        # update the local database.
        @coll_sessions.find_one_and_update({ id: id }, { "$set" => { ctx_pend: ctx_info_h.to_json,
                                                                    stx_pend: stx_info_h.to_json,
                                                                    status: 8, msg_cache: msg, tg_msg: tg_msg } })
      elsif msg_type == "closing"
        @logger.info("#{@key.pubkey} check msg 6: branch closing.")

        fund_tx = @coll_sessions.find({ id: id }).first[:fund_tx]
        fund_tx = CKB::Types::Transaction.from_h(fund_tx)
        local_stx_info = hash_to_info(JSON.parse(@coll_sessions.find({ id: id }).first[:stx_info], symbolize_names: true))
        remote_change = CKB::Types::Output.from_h(msg[:change])
        remote_fee_cells = msg[:fee_cell].map { |cell| CKB::Types::Input.from_h(cell) }

        nounce = @coll_sessions.find({ id: id }).first[:nounce]
        type_hash = @coll_sessions.find({ id: id }).first[:type_hash]
        current_height = @api.get_tip_block_number

        @logger.info("#{@key.pubkey} check msg 6 closing: msg parsed.")

        # check cell is live.
        for cell in remote_fee_cells
          validation = @api.get_live_cell(cell.previous_output)
          if validation.status != "live"
            record_result({ "receiver_step6_error_cell_dead": true })
            client.puts(generate_text_msg(msg[:id], "sry, the cells you offer are dead."))
            return false
          end
        end

        remote_fee = get_total_capacity(remote_fee_cells) - remote_change.capacity
        # check sufficient.
        if remote_fee < 0
          record_result({ "receiver_step6_error_fee_negative": remote_fee })
          client.puts(generate_text_msg(msg[:id], "sry, you fee is not enough as you claimed."))
          return false
        end
        # check container sufficient.
        if remote_change.capacity < 61 * 10 ** 8
          record_result({ "receiver_step6_error_change_container_insufficient": remote_change.capacity - 61 * 10 ** 8 })
          client.puts(generate_text_msg(msg[:id], "sry, the container of change is not enough."))
          return false
        end

        while true
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
        while true
          local_fee = 3000
          break
        end

        @logger.info("#{@key.pubkey} check msg 6 closing: fee get.")

        local_change_output = CKB::Types::Output.new(
          capacity: 0,
          lock: @lock,
          type: nil,
        )

        get_total_capacity = local_change_output.calculate_min_capacity("0x") + local_fee
        local_fee_cell = gather_fee_cell([@lock], get_total_capacity, @coll_cells)
        fee_cell_capacity = get_total_capacity(local_fee_cell)

        @logger.info("#{@key.pubkey} check msg 6 closing: get fee cell.")

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

        @logger.info("#{@key.pubkey} check msg 6 closing: witness get.")

        type_dep = []

        for output in local_stx_info[:outputs]
          if output.type != nil
            current_type = find_type(output.type.compute_hash)
            type_dep.append(current_type[:type_dep]) if current_type[:type_dep] != nil
          end
        end
        type_dep = type_dep.map(&:to_h)
        type_dep = type_dep.to_set.to_a
        type_dep = type_dep.map { |dep| CKB::Types::CellDep.from_h(dep) }

        terminal_tx = @tx_generator.generate_terminal_tx(id, nounce, inputs, outputs, outputs_data, witnesses, sig_index, type_dep)
        terminal_tx = @tx_generator.sign_tx(terminal_tx, local_fee_cell).to_h

        @logger.info("#{@key.pubkey} check msg 6 closing: terminal_tx .")

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
      local_ctx_info = hash_to_info(JSON.parse(@coll_sessions.find({ id: msg[:id] }).first[:ctx_pend], symbolize_names: true))
      local_stx_info = hash_to_info(JSON.parse(@coll_sessions.find({ id: msg[:id] }).first[:stx_pend], symbolize_names: true))
      nounce = @coll_sessions.find({ id: id }).first[:nounce]

      remote_ctx_info = hash_to_info(msg[:ctx_info])
      remote_stx_info = hash_to_info(msg[:stx_info])

      if stage != 1
        puts "the fund tx is not on chain, so the you can not make payment now..."
        return false
      end
      @logger.info("#{@key.pubkey} check msg 7: begin to check the info.")

      verify_info_sig(remote_stx_info, "settlement", remote_pubkey, 1 - sig_index)
      # check both the signatures are right.
      if !verify_info_args(local_ctx_info, remote_ctx_info) || !verify_info_args(local_stx_info, remote_stx_info)
        record_result({ "sender_step7_error_info_inconsistent": true })
        client.puts(generate_text_msg(msg[:id], "sry, the args of closing or settlement transaction have problem."))
        client.close()
        return false
      end

      if !verify_info_sig(remote_ctx_info, "closing", remote_pubkey, 1 - sig_index) || !verify_info_sig(remote_stx_info, "settlement", remote_pubkey, 1 - sig_index)
        record_result({ "sender_step7_error_signature_invalid": true })
        client.puts(generate_text_msg(msg[:id], "sry, the sig of closing or settlement transaction have problem."))
        client.close()
        return false
      end

      # generate the signed msg from info.
      msg_signed = generate_msg_from_info(remote_ctx_info, "closing")
      witness_new = Array.new()
      for witness in remote_ctx_info[:witnesses]
        witness_new << @tx_generator.generate_witness(id, witness, msg_signed, sig_index)
      end
      remote_ctx_info[:witnesses] = witness_new

      ctx_info_h = info_to_hash(remote_ctx_info)
      stx_info_h = info_to_hash(remote_stx_info)

      msg = { id: id, type: 8, ctx_info: ctx_info_h }.to_json
      client.puts(msg)

      # update the local database.
      @coll_sessions.find_one_and_update({ id: id }, { "$set" => { ctx_info: ctx_info_h.to_json,
                                                                  stx_info: stx_info_h.to_json,
                                                                  nounce: nounce + 1,
                                                                  stx_pend: 0, ctx_pend: 0,
                                                                  status: 6, msg_cache: msg } })
      client.close
    when 8
      # it is the final step of making payments.
      # the payer just check the remote signatures are right,
      # and send the signed ctx to him.
      id = msg[:id]
      remote_pubkey = @coll_sessions.find({ id: id }).first[:remote_pubkey]
      local_pubkey = @coll_sessions.find({ id: id }).first[:local_pubkey]
      sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
      stage = @coll_sessions.find({ id: id }).first[:stage]
      local_ctx_info_pend = hash_to_info(JSON.parse(@coll_sessions.find({ id: msg[:id] }).first[:ctx_pend], symbolize_names: true))
      local_stx_info_pend = hash_to_info(JSON.parse(@coll_sessions.find({ id: msg[:id] }).first[:stx_pend], symbolize_names: true))
      nounce = @coll_sessions.find({ id: id }).first[:nounce]

      tg_msg = @coll_sessions.find({ id: id }).first[:tg_msg]

      @logger.info("#{@key.pubkey} check msg 8: msg parsed.")

      remote_ctx_info = hash_to_info(msg[:ctx_info])

      @logger.info("#{@key.pubkey} check msg 8: ctx_info checked.")

      if !verify_info_args(local_ctx_info_pend, remote_ctx_info)
        record_result({ "receiver_step8_error_info_inconsistent": true })
        client.puts(generate_text_msg(msg[:id], "sry, the args of closing transaction have problem."))
        return false
      end

      if !verify_info_sig(remote_ctx_info, "closing", remote_pubkey, 1 - sig_index)
        record_result({ "receiver_step8_error_signature_invalid": true })
        client.puts(generate_text_msg(msg[:id], "sry, the sig of closing transaction have problem."))
        return false
      end

      ctx_info_h = info_to_hash(remote_ctx_info)
      stx_info_h = info_to_hash(local_stx_info_pend)

      @logger.info("#{@key.pubkey} check msg 8: finished.")

      @coll_sessions.find_one_and_update({ id: id }, { "$set" => { ctx_info: ctx_info_h.to_json, stx_info: stx_info_h.to_json,
                                                                  status: 6, stx_pend: 0, ctx_pend: 0,
                                                                  nounce: nounce + 1 } })

      # if the msg to be sent is not empty, just send the msg to telegra group.
      if tg_msg != nil
        Telegram::Bot::Client.run(@token) do |bot|
          bot.api.send_message(chat_id: @group_id, text: "#{tg_msg}")
        end
      end

      @logger.info("payment done, now the version in local db is #{nounce + 1}")
      return "done"
    when 9
      id = msg[:id]
      terminal_tx = CKB::Types::Transaction.from_h(msg[:terminal_tx])
      sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
      local_fee_cell = @coll_sessions.find({ id: id }).first[:settlement_fee_cell]
      local_change_output = JSON.parse(@coll_sessions.find({ id: msg[:id] }).first[:settlement_fee_change], symbolize_names: true)
      remote_pubkey = @coll_sessions.find({ id: id }).first[:remote_pubkey]
      local_stx_info = hash_to_info(JSON.parse(@coll_sessions.find({ id: msg[:id] }).first[:stx_info], symbolize_names: true))
      fund_tx = @coll_sessions.find({ id: id }).first[:fund_tx]
      fund_tx = CKB::Types::Transaction.from_h(fund_tx)
      local_fee_cell = local_fee_cell.map { |cell| JSON.parse(cell.to_json, symbolize_names: true) }
      input_fund = @tx_generator.convert_input(fund_tx, 0, 0)

      @logger.info("#{@key.pubkey} check msg 9: msg parsed.")

      for output in local_stx_info[:outputs].map(&:to_h)
        if !terminal_tx.outputs.map(&:to_h).include? output
          record_result({ "sender_step9_error_stx_inconsistent": true })
          msg_reply = generate_text_msg(msg[:id], "sry, the settlement outputs are inconsistent with my local one.")
          return false
        end
      end

      @logger.info("#{@key.pubkey} check msg 9: settlement is right.")

      terminal_tx = CKB::Types::Transaction.from_h(msg[:terminal_tx])
      remote_fee_cells = terminal_tx.inputs.map(&:to_h) - local_fee_cell - [input_fund.to_h]
      remote_fee_cells = remote_fee_cells.map { |cell| CKB::Types::Input.from_h(cell) }
      remote_change_output = terminal_tx.outputs.map(&:to_h) - [local_change_output] - local_stx_info[:outputs].map(&:to_h)

      remote_change_output = remote_change_output.map { |output| CKB::Types::Output.from_h(output) }
      # check cell is live.
      for cell in remote_fee_cells
        validation = @api.get_live_cell(cell.previous_output)
        if validation.status != "live"
          record_result({ "sender_step9_error_cell_dead": true })
          client.puts(generate_text_msg(msg[:id], "sry, the cells you offer are dead."))
          return false
        end
      end

      @logger.info("#{@key.pubkey} check msg 9: cell all live.")

      remote_change_capacity = remote_change_output.map(&:capacity).inject(0, &:+)
      remote_fee = get_total_capacity(remote_fee_cells) - remote_change_capacity

      if remote_fee < 0
        record_result({ "receiver_step9_error_fee_negative": remote_fee })
        client.puts(generate_text_msg(msg[:id], "sry, you fee is not enough as you claimed."))
        return false
      end
      # check container sufficient.
      if remote_change_capacity < 61 * 10 ** 8
        record_result({ "receiver_step9_error_change_container_insufficient": remote_change_capacity - 61 * 10 ** 8 })
        client.puts(generate_text_msg(msg[:id], "sry, the container of change is not enough."))
        return false
      end

      # check signature.
      verify_result = verify_fund_tx_sig(terminal_tx, remote_pubkey)
      if !verify_result
        record_result({ "receiver_step9_error_signature_invalid": true })
        client.puts(generate_text_msg(msg[:id], "The signatures are invalid."))
        return false
      end

      while true
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

      @logger.info("#{@key.pubkey} check msg 9: begin to constrct terminal transaction.")
      # add my signature and send it to blockchain.
      local_fee_cell = local_fee_cell.map { |cell| CKB::Types::Input.from_h(cell) }
      terminal_tx = @tx_generator.sign_tx(terminal_tx, local_fee_cell)
      terminal_tx.witnesses[0] = @tx_generator.generate_witness(id, terminal_tx.witnesses[0], terminal_tx.hash, sig_index)

      begin
        exist = @api.get_transaction(terminal_tx.hash)
        tx_hash = @api.send_transaction(terminal_tx) if exist == nil
        @logger.info("Send settlement tx (the good case.) with hash #{tx_hash}.")
      rescue Exception => e
        # puts e
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
          begin
            msg = client.gets
            if msg != nil
              msg = JSON.parse(msg, symbolize_names: true)
              ret = process_recv_message(client, msg)
            end

            break if ret == 100
          rescue => exception
            break if exception.class == Errno::ECONNRESET
          end
        end
      end
    }
  end

  def print_stx(stx, local_pubkey, remote_pubkey)
    for index in (0..stx[:outputs].length - 1)
      output = stx[:outputs][index]
      output_data = stx[:outputs_data][index]
      ckb = output.capacity - output.calculate_min_capacity(output_data)
      udt = decoder(stx[:outputs_data][index])
      if local_pubkey == output.lock.args
        puts " Local's ckb: #{ckb}, udt: #{udt}."
      elsif remote_pubkey == output.lock.args
        puts " Remote's ckb: #{ckb}, udt: #{udt}"
      end
    end
    return true
  end

  def send_establish_channel(remote_ip, remote_port, funding, fee_fund = 3000, timeout = "9223372036854775908", refund_lock_script = @lock)
    s = TCPSocket.open(remote_ip, remote_port)
    change_lock_script = refund_lock_script
    local_pubkey = CKB::Key.blake160(@key.pubkey)
    locks = [@lock]

    # check all amount are positive.
    for funding_amount in funding.values()
      if funding_amount < 0
        record_result({ "sender_gather_funding_error_negative": funding_amount })
        return false
      end
    end

    # check fee is positive.s
    if fee_fund < 0
      record_result({ "sender_gather_fee_error_negative": fee_fund })
      return false
    end

    # change all asset type to hashes.
    funding_type_script_version = convert_text_to_hash(funding)

    # prepare the msg components.
    local_cells = gather_inputs(funding_type_script_version, fee_fund, locks, change_lock_script,
                                refund_lock_script, @coll_cells)
    if local_cells.is_a? Numeric
      record_result({ "sender_gather_funding_error_insufficient": local_cells })
      return false
    end

    # get temp id.
    msg_digest = (local_cells.map(&:to_h)).to_json
    session_id = Digest::MD5.hexdigest(msg_digest)

    funding_type_script_version = funding_type_script_version.sort.reverse.to_h
    local_empty_stx = @tx_generator.generate_empty_settlement_info(funding_type_script_version, refund_lock_script)

    # conver it to hash.
    local_empty_stx_h = info_to_hash(Marshal.load(Marshal.dump(local_empty_stx)))
    refund_capacity = local_empty_stx[:outputs][0].capacity

    local_change = @tx_generator.construct_change_output(local_cells, funding_type_script_version, fee_fund, refund_capacity, change_lock_script)

    local_change_h = cell_to_hash(local_change)
    local_cells_h = local_cells.map(&:to_h)

    msg = { id: session_id, type: 1, pubkey: local_pubkey, cells: local_cells_h, fee_fund: fee_fund,
            timeout: timeout, asset: funding_type_script_version, change: local_change_h, stx_info: local_empty_stx_h }.to_json

    # send the msg.
    s.puts(msg)

    doc = { id: session_id, local_pubkey: local_pubkey, remote_pubkey: "", status: 2,
            nounce: 0, ctx_info: 0, stx_info: local_empty_stx_h.to_json, local_cells: local_cells_h,
            timeout: timeout.to_s, msg_cache: msg.to_json, local_asset: funding_type_script_version.to_json, fee_fund: fee_fund,
            stage: 0, settlement_time: 0, sig_index: 0, closing_time: 0, local_change: local_change_h.to_json,
            stx_pend: 0, ctx_pend: 0, remote_ip: remote_ip, remote_port: remote_port }
    return false if !insert_with_check(@coll_sessions, doc)
    @logger.info("#{@key.pubkey} send msg1.")

    begin
      timeout(5) do
        while (true)
          msg = s.gets
          if msg != nil
            msg = JSON.parse(msg, symbolize_names: true)
            ret = process_recv_message(s, msg)
          end
          if ret == "done"
            s.close()
            break
          end
        end
      end
    rescue Timeout::Error
      puts "Timed out!"
    rescue Errno::ECONNRESET
      puts "reset"
    end
  end

  def send_payments(remote_ip, remote_port, id, payment, tg_msg = nil)
    s = TCPSocket.open(remote_ip, remote_port)

    remote_pubkey = @coll_sessions.find({ id: id }).first[:remote_pubkey]
    local_pubkey = @coll_sessions.find({ id: id }).first[:local_pubkey]
    sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
    stage = @coll_sessions.find({ id: id }).first[:stage]

    stx_info = hash_to_info(JSON.parse(@coll_sessions.find({ id: id }).first[:stx_info], symbolize_names: true))
    ctx_info = hash_to_info(JSON.parse(@coll_sessions.find({ id: id }).first[:ctx_info], symbolize_names: true))

    @logger.info("#{local_pubkey} send_payments: prepare to send #{payment}")

    if stage != 1
      puts "the fund tx is not on chain, so the you can not make payment now..."
      return false
    end

    for payment_amount in payment.values()
      if payment_amount < 0
        record_result({ "sender_make_payments_error_negative": payment_amount })
        return false
      end
    end

    payment = convert_text_to_hash(payment)

    @logger.info("#{local_pubkey} is payer.")
    @logger.info("#{remote_pubkey} is payee.")

    # just read and update the latest stx, the new
    stx_info = @tx_generator.update_stx(payment, stx_info, local_pubkey, remote_pubkey)
    ctx_info = @tx_generator.update_ctx(ctx_info)

    if stx_info.is_a? Numeric
      record_result({ "sender_make_payments_error_insufficient": stx_info })
      return false
    end

    # sign the stx.
    msg_signed = generate_msg_from_info(stx_info, "settlement")

    # the msg ready.
    witness_new = Array.new()
    for witness in stx_info[:witnesses]
      witness_new << @tx_generator.generate_witness(id, witness, msg_signed, sig_index)
    end
    stx_info[:witnesses] = witness_new
    ctx_info_h = info_to_hash(ctx_info)
    stx_info_h = info_to_hash(stx_info)

    # send the msg.
    msg = { id: id, type: 6, ctx_info: ctx_info_h, stx_info: stx_info_h, tg_msg: tg_msg,
            payment: payment, msg_type: "payment" }.to_json
    s.puts(msg)

    # update the local database.
    @coll_sessions.find_one_and_update({ id: id }, { "$set" => { stx_pend: stx_info_h.to_json, ctx_pend: ctx_info_h.to_json,
                                                                status: 7, msg_cache: msg } })
    @logger.info("#{local_pubkey} sent payment")

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
    rescue => exception
      s.close()
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
    fee_cell = gather_fee_cell([@lock], total_fee, @coll_cells)
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
    rescue Exception => e
      puts e
    end

    return "done"
  end

  def make_exchange(remote_ip, remote_port, id, flag, quantity)
    s = TCPSocket.open(remote_ip, remote_port)

    remote_pubkey = @coll_sessions.find({ id: id }).first[:remote_pubkey]
    local_pubkey = @coll_sessions.find({ id: id }).first[:local_pubkey]
    sig_index = @coll_sessions.find({ id: id }).first[:sig_index]
    stage = @coll_sessions.find({ id: id }).first[:stage]

    stx_info = hash_to_info(JSON.parse(@coll_sessions.find({ id: id }).first[:stx_info], symbolize_names: true))
    ctx_info = hash_to_info(JSON.parse(@coll_sessions.find({ id: id }).first[:ctx_info], symbolize_names: true))

    @logger.info("#{local_pubkey} make_exchange: #{flag}")

    if stage != 1
      puts "the fund tx is not on chain, so the you can not make payment now..."
      return false
    end

    @logger.info("#{local_pubkey} is payer, #{remote_pubkey} is payee.")

    if flag == "ckb2udt"
      payment = { ckb: quantity * 10 ** 8, udt: -quantity }
    elsif flag == "udt2ckb"
      payment = { ckb: -quantity * 10 ** 8, udt: quantity }
    else
      puts "something went wrong."
    end

    payment = convert_text_to_hash(payment)

    # just read and update the latest stx, the new
    stx_info = @tx_generator.update_stx(payment, stx_info, local_pubkey, remote_pubkey)
    ctx_info = @tx_generator.update_ctx(ctx_info)

    if stx_info.is_a? Numeric or stx_info.is_a? String
      puts "Your balance is not enough, please check it."
      record_result({ "sender_make_payments_error_insufficient": stx_info })
      return false
    end

    # sign the stx.
    msg_signed = generate_msg_from_info(stx_info, "settlement")

    # the msg ready.
    witness_new = Array.new()
    for witness in stx_info[:witnesses]
      witness_new << @tx_generator.generate_witness(id, witness, msg_signed, sig_index)
    end
    stx_info[:witnesses] = witness_new
    ctx_info_h = info_to_hash(ctx_info)
    stx_info_h = info_to_hash(stx_info)

    # send the msg.
    msg = { id: id, type: 6, ctx_info: ctx_info_h, stx_info: stx_info_h,
            payment: payment, msg_type: "payment" }.to_json
    s.puts(msg)

    # update the local database.
    @coll_sessions.find_one_and_update({ id: id }, { "$set" => { stx_pend: stx_info_h.to_json, ctx_pend: ctx_info_h.to_json,
                                                                status: 7, msg_cache: msg } })
    @logger.info("#{local_pubkey} make exchange.")

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
    rescue => exception
      s.close()
    end
  end
end
