require "json"
require "rubygems"
require "bundler/setup"
require "ckb"
require "mongo"
require "../libs/tx_generator.rb"
require "../libs/mongodb_operate.rb"
require "../libs/ckb_interaction.rb"
require "../libs/verification.rb"

# Mongo::Logger.logger.level = Logger::FATAL

class Minotor
  def initialize(private_key)
    @key = CKB::Key.new(private_key)
    @api = CKB::API::new
    @wallet = CKB::Wallet.from_hex(@api, @key.privkey)
    @tx_generator = Tx_generator.new(@key)

    # @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC_copy")
    # @db = @client.database
    # @db.drop()
    @cell_min_capacity = 61
    # copy_db("GPC", "GPC_copy")
    # @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
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

  def json_to_info(json)
    info_h = JSON.parse(json, symbolize_names: true)
    info = info_h
    info[:outputs] = info_h[:outputs].map { |output| CKB::Types::Output.from_h(output) }
    return info
  end

  def json_to_input(input_hash)
    out_point = CKB::Types::OutPoint.from_h(input_hash[:previous_output])
    closing_input = CKB::Types::Input.new(
      previous_output: out_point,
      since: input_hash[:since],
    )
    return closing_input
  end

  def reset_lock(lock)
    lock_args = @tx_generator.parse_lock_args(lock.args)
    nounce = lock_args[:nounce]
    lock_args = @tx_generator.generate_lock_args(lock_args[:id], 0, lock_args[:timeout],
                                                 0, lock_args[:pubkey_A], lock_args[:pubkey_B])
    lock.args = lock_args
    lock_ser = CKB::Serializers::ScriptSerializer.new(lock).serialize

    return { lock_ser: lock_ser, nounce: nounce }
  end

  def monitor_chain()
    while true
      current_height = @api.get_tip_block_number
      checked_height = @coll_sessions.find({ id: 0 }).first[:current_block_num]

      # check whether there are some related ctx or fund tx submitted to chain.
      for i in (checked_height + 1..current_height)
        puts i
        block = @api.get_block_by_number(i)
        for transaction in block.transactions
          view = @coll_sessions.find { }
          view.each do |doc|
            # we need to verify the status of the tx is commited...
            @coll_sessions.find_one_and_delete(id: doc[:id]) if transaction.hash == doc[:settlement_hash]
          end
          index = 0

          remote_input_nounce = nil

          script_hash_lib = {}

          # get the all inputs.
          for input in transaction.inputs
            if input.previous_output.tx_hash != "0x0000000000000000000000000000000000000000000000000000000000000000"
              previous_tx = @api.get_transaction(input.previous_output.tx_hash)
              previous_output_lock = previous_tx.transaction.outputs[input.previous_output.index].lock
              next if previous_output_lock.code_hash != @tx_generator.gpc_code_hash

              reset_result = reset_lock(previous_output_lock)
              if !script_hash_lib.keys.include? reset_result[:lock_ser]
                script_hash_lib[reset_result[:lock_ser]] = { input_nounce: reset_result[:nounce] }
              end
            end
          end

          for output in transaction.outputs
            remote_output_lock = output.lock
            next if remote_output_lock.code_hash != @tx_generator.gpc_code_hash
            reset_result = reset_lock(remote_output_lock)
            if !script_hash_lib.keys.include? reset_result[:lock_ser]
              script_hash_lib[reset_result[:lock_ser]] = { output_nounce: reset_result[:nounce] }
            else
              script_hash_lib[reset_result[:lock_ser]][:output_nounce] = reset_result[:nounce]
            end
          end
          next if script_hash_lib.length == 0
          view = @coll_sessions.find { }
          view.each do |doc|
            local_script = doc[:gpc_script]
            nounce_local = doc[:nounce]
            next if !script_hash_lib.keys.include? local_script

            remote = script_hash_lib[local_script]
            stx_pend = @coll_sessions.find({ id: doc[:id] }).first[:stx_pend]

            if (remote.include? :input_nounce) && (remote.include? :output_nounce)
              # closing

              if remote[:output_nounce] < nounce_local
                # remote cheat
                send_tx(doc, "closing")
              elsif remote[:output_nounce] == nounce_local
                # my or remote latest is accepted, so prepare to settle.
                timeout = doc[:timeout].to_i
                timeout = [timeout].pack("Q>")
                timeout[0] = [0].pack("C")
                timeout = timeout.unpack("Q>")[0]

                stx_input_h = @tx_generator.convert_input(transaction, index, doc[:timeout].to_i).to_h
                @coll_sessions.find_one_and_update({ id: doc[:id] }, { "$set" => { settlement_time: i + timeout, stx_input: stx_input_h, stage: 3 } })
              elsif stx_pend = 0 && remote[:output_nounce] - nounce_local == 1
                # remote one break his promise, so just prepare to send the pend stx.
                timeout = doc[:timeout].to_i
                timeout = [timeout].pack("Q>")
                timeout[0] = [0].pack("C")
                timeout = timeout.unpack("Q>")[0]

                stx_input_h = @tx_generator.convert_input(transaction, index, doc[:timeout].to_i).to_h
                @coll_sessions.find_one_and_update({ id: doc[:id] }, { "$set" => { settlement_time: i + timeout, stx_input: stx_input_h, stx: stx_pend, stage: 3 } })
              end
            elsif (remote.include? :input_nounce) && !(remote.include? :output_nounce)
              # settlement, may have attack....
              @coll_sessions.find_one_and_delete(id: doc[:id])
            elsif !(remote.include? :input_nounce) && (remote.include? :output_nounce)
              # fund
              ctx_input_h = @tx_generator.convert_input(transaction, index, 0).to_h
              @coll_sessions.find_one_and_update({ id: doc[:id] }, { "$set" => { ctx_input: ctx_input_h, stage: 1 } })
            end
          end
        end
      end

      view = @coll_sessions.find { }
      view.each do |doc|
        # well, if the ctx I sent can not be seen, just send it again.
        next if doc[:"id"] == 0
        send_tx(doc, "closing") if doc[:stage] == 2 && doc[:settlement_time] == 0
        # check whether there are available to be sent.
        if current_height >= doc[:settlement_time] && doc[:stage] == 3
          tx_hash = send_tx(doc, "settlement")
          @coll_sessions.find_one_and_update({ id: doc[:id] }, { "$set" => { settlement_hash: tx_hash } })
        end
      end

      @coll_sessions.find_one_and_update({ id: 0 }, { "$set" => { current_block_num: current_height } })
      # just update the checked block!
    end
  end

  # Need to construct corresponding txs.
  def send_tx(doc, type, fee = 10000)
    tx_info = type == "closing" ? json_to_info(doc[:ctx]) : json_to_info(doc[:stx])
    gpc_input = type == "closing" ? doc[:ctx_input] : doc[:stx_input]
    gpc_input = json_to_input(gpc_input)

    fee_cell = gather_inputs(@cell_min_capacity, fee).inputs
    input = [gpc_input] + fee_cell

    local_change_output = CKB::Types::Output.new(
      capacity: CKB::Utils.byte_to_shannon(@cell_min_capacity),
      lock: default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                                  args: CKB::Key.blake160(@key.pubkey), hash_type: CKB::ScriptHashType::TYPE),
      type: nil,
    )
    tx_info[:outputs] << local_change_output
    for nosense in fee_cell
      tx_info[:outputs_data] << "0x"
      tx_info[:witness] << CKB::Types::Witness.new
    end
    tx = @tx_generator.generate_no_input_tx(input, tx_info)

    tx = @tx_generator.sign_tx(tx)
    if !tx
      puts "the input of the tx is spent."
      return false
    end

    tx_hash = @api.send_transaction(tx)
    return tx_hash
  end
end
