require "json"
require "rubygems"
require "bundler/setup"
require "ckb"
require "mongo"
require "../libs/tx_generator.rb"
require "../libs/ckb_interaction.rb"
require "../libs/verification.rb"

class Minotor
  def initialize(private_key)
    @key = CKB::Key.new(private_key)
    @api = CKB::API::new
    @wallet = CKB::Wallet.from_hex(@api, @key.privkey)
    @tx_generator = Tx_generator.new(@key)

    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database
    @coll_sessions = @db[@key.pubkey + "_session_pool"]
    @coll_cells = @db[@key.pubkey + "_cell_pool"]

    @lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: CKB::Key.blake160(@key.pubkey), hash_type: CKB::ScriptHashType::TYPE)
    @lock_hash = @lock.compute_hash
  end

  def json_to_info(json)
    info_h = JSON.parse(json, symbolize_names: true)
    info_h[:outputs] = info_h[:outputs].map { |output| CKB::Types::Output.from_h(output) }
    return info_h
  end

  def json_to_input(input_hash)
    out_point = CKB::Types::OutPoint.from_h(input_hash[:previous_output])
    closing_input = CKB::Types::Input.new(
      previous_output: out_point,
      since: input_hash[:since],
    )
    return closing_input
  end

  # parse since to a number.
  def parse_since(since)
    since = [since.to_i].pack("Q>")
    since[0] = [0].pack("C")
    timeout = since.unpack("Q>")[0]
    return timeout
  end

  def monitor_pending_cells()
    while true
      view = @coll_sessions.find { }
      view.each do |doc|
        timeout = doc[:revival].to_i
        current_time = (Time.new).to_i
        @coll_cells.find_one_and_delete(id: doc[:id]) if current_time >= timeout
      end
      sleep(1)
    end
  end

  def monitor_chain()
    while true
      current_height = @api.get_tip_block_number
      checked_height = @coll_sessions.find({ id: 0 }).first[:current_block_num]

      # check whether there are some related ctx or fund tx submitted to chain.
      for i in (checked_height + 1..current_height)
        block = @api.get_block_by_number(i)
        for transaction in block.transactions
          index = 0
          id_lib = {}

          # travel inputs.
          for input in transaction.inputs

            # except cellbase.
            if input.previous_output.tx_hash != "0x0000000000000000000000000000000000000000000000000000000000000000"

              # load previous tx.
              previous_tx = @api.get_transaction(input.previous_output.tx_hash)
              previous_output_lock = previous_tx.transaction.outputs[input.previous_output.index].lock

              # record the nounce.
              next if previous_output_lock.code_hash != @tx_generator.gpc_code_hash || previous_output_lock.hash_type != @tx_generator.gpc_hash_type
              lock_args = @tx_generator.parse_lock_args(previous_output_lock.args)
              if !id_lib.keys.include? lock_args[:id]
                id_lib[lock_args[:id]] = { input_nounce: lock_args[:nounce] }
              end
            end
          end

          # travel outputs.
          for output in transaction.outputs
            remote_output_lock = output.lock
            next if remote_output_lock.code_hash != @tx_generator.gpc_code_hash || remote_output_lock.hash_type != @tx_generator.gpc_hash_type
            lock_args = @tx_generator.parse_lock_args(remote_output_lock.args)
            remote_nounce = if !id_lib.keys.include? lock_args[:id]
                id_lib[lock_args[:id]] = { output_nounce: lock_args[:nounce] }
              else
                id_lib[lock_args[:id]][:output_nounce] = lock_args[:nounce]
              end
          end

          # if there is no gpc tx, next.
          next if id_lib.length == 0

          # travel local docs.
          view = @coll_sessions.find { }
          view.each do |doc|
            nounce_local = doc[:nounce]
            next if !id_lib.keys.include? doc[:id]

            remote = id_lib[doc[:id]]
            stx_pend = @coll_sessions.find({ id: doc[:id] }).first[:stx_info_pend]

            if (remote.include? :input_nounce) && (remote.include? :output_nounce)

              # closing
              if remote[:output_nounce] < nounce_local
                # remote cheat
                ctx_input_h = @tx_generator.convert_input(transaction, index, 0).to_h
                @coll_sessions.find_one_and_update({ id: doc[:id] }, { "$set" => { ctx_input: ctx_input_h, stage: 2 } })
                send_tx(doc, "closing")
                puts "send closing tx about #{doc[:id]} at block number #{i}."
              elsif remote[:output_nounce] == nounce_local
                # my or remote latest ctx is accepted by chain, so prepare to settle.
                timeout = parse_since(doc[:timeout])
                stx_input_h = @tx_generator.convert_input(transaction, index, doc[:timeout].to_i).to_h
                @coll_sessions.find_one_and_update({ id: doc[:id] }, { "$set" => { settlement_time: i + timeout, stx_input: stx_input_h, stage: 3 } })
                puts "#{doc[:id]} is closing at block number #{i}."
              elsif stx_pend != 0 && remote[:output_nounce] - nounce_local == 1
                # remote party break his promise, so just prepare to send the pending stx.
                timeout = parse_since(doc[:timeout])
                stx_input_h = @tx_generator.convert_input(transaction, index, doc[:timeout].to_i).to_h
                @coll_sessions.find_one_and_update({ id: doc[:id] }, { "$set" => { settlement_time: i + timeout, stx_input: stx_input_h, stx: stx_pend, stage: 3 } })
              end
            elsif (remote.include? :input_nounce) && !(remote.include? :output_nounce)
              # this is the settlement tx.
              @coll_sessions.find_one_and_delete(id: doc[:id])
              puts "#{doc[:id]} is settled at block number #{i}."
            elsif !(remote.include? :input_nounce) && (remote.include? :output_nounce)
              # this is the fund tx.
              ctx_input_h = @tx_generator.convert_input(transaction, index, 0).to_h
              @coll_sessions.find_one_and_update({ id: doc[:id] }, { "$set" => { ctx_input: ctx_input_h, stage: 1 } })
              puts "#{doc[:id]}'s fund tx on chain at block number #{i}."
            end
          end
        end
      end

      # the below logic maybe confusing
      # I will rewrite it more clearly.
      view = @coll_sessions.find { }
      view.each do |doc|
        # well, if the ctx I sent can not be seen, just send it again.
        next if doc[:"id"] == 0
        if doc[:stage] == 2 && doc[:settlement_time] == 0 && doc[:closing_time] == 0
          send_tx(doc, "closing")
          puts "send closing tx about #{doc[:id]} at block number #{i}."
        end
        # check whether there are available to be sent.
        if current_height >= doc[:settlement_time] && doc[:stage] == 3
          tx_hash = send_tx(doc, "settlement")
          @coll_sessions.find_one_and_update({ id: doc[:id] }, { "$set" => { settlement_hash: tx_hash } }) if tx_hash
          puts "send settlement tx about #{doc[:id]} at block number #{i}."
        end

        # If remote party refuses the closing request, and the closing_time is passed.
        # Just submit the closing tx.
        if current_height >= doc[:closing_time] && doc[:stage] == 2 && doc[:closing_time] != 0
          send_tx(doc, "closing")
          puts "send closing tx about #{doc[:id]} at block number #{i}."
        end
      end

      @coll_sessions.find_one_and_update({ id: 0 }, { "$set" => { current_block_num: current_height } })
      # just update the checked block!

      # add and remove live cells pool.
      sleep(1)
    end
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

  def decoder(data)
    result = CKB::Utils.hex_to_bin(data).unpack("Q<")[0]
    return result.to_i
  end

  def encoder(data)
    return CKB::Utils.bin_to_hex([data].pack("Q<"))
  end

  # Need to construct corresponding txs.
  def send_tx(doc, type, fee = 2000)
    tx_info = type == "closing" ? json_to_info(doc[:ctx_info]) : json_to_info(doc[:stx_info])
    gpc_input = type == "closing" ? doc[:ctx_input] : doc[:stx_input]
    type_hash = doc[:type_hash]
    gpc_input = json_to_input(gpc_input)
    type_info = find_type(type_hash)
    input = [gpc_input]

    # the fee rules for settlement and closing is different.
    # closing need extra fee, so you need to pay it, which means you need one more input cells.
    # settlement does not.
    local_change_output = CKB::Types::Output.new(
      capacity: 0,
      lock: @lock,
      type: nil,
    )

    # require the change ckbyte is greater than the min capacity.
    fee = local_change_output.calculate_min_capacity("0x") + fee
    fee_cell = gather_fee_cell([@lock_hash], fee, @coll_cells, 0)
    return false if fee_cell == nil

    fee_cell_capacity = get_total_capacity(fee_cell)
    input += fee_cell

    local_change_output.capacity = fee_cell_capacity - fee
    tx_info[:outputs] << local_change_output
    for nosense in fee_cell
      tx_info[:outputs_data] << "0x"
      tx_info[:witnesses] << CKB::Types::Witness.new
    end

    # generate the tx.
    tx = @tx_generator.generate_no_input_tx(input, tx_info, type_info[:type_dep])
    tx = @tx_generator.sign_tx(tx, tx.inputs[1..])

    if !tx
      puts "the input of the tx is spent."
      return false
    end

    tx_hash = false
    exist = @api.get_transaction(tx.hash)

    begin
      tx_hash = @api.send_transaction(tx) if exist == nil
    rescue Exception => e
    end

    return tx_hash
  end
end
