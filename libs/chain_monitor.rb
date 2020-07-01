require "json"
require "rubygems"
require "bundler/setup"
require "ckb"
require "mongo"
require "../libs/tx_generator.rb"
require "../libs/mongodb_operate.rb"
require "../libs/ckb_interaction.rb"
require "../libs/verification.rb"

Mongo::Logger.logger.level = Logger::FATAL

class Minotor
  def initialize(private_key)
    @key = CKB::Key.new(private_key)
    @api = CKB::API::new
    @wallet = CKB::Wallet.from_hex(@api, @key.privkey)
    @tx_generator = Tx_generator.new(@key)
    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database
    @coll_sessions = @db[@key.pubkey + "_session_pool"]
    @gpc_code_hash = "0x6d44e8e6ebc76927a48b581a0fb84576f784053ae9b53b8c2a20deafca5c4b7b"
    @gpc_tx = "0xeda5b9d9c6d5db2d4ed894fd5419b4dbbfefdf364783593dbf62a719f650e020"
  end

  def monitor_chain()
    while true
      current_height = @api.get_tip_block_number
      checked_height = @coll_sessions.find({ id: 0 }).first[:current_block_num]

      view = @coll_sessions.find { }
      view.each do |doc|
        # well, if the ctx I sent can not be seen, just send it again.
        send_ctx(doc[:id]) if doc[:stage] > 1 && doc[:settlement_time] == 0
        # check whether there are available to be sent.
        send_stx(doc[:id]) if current_height > doc[:settlement_time] && doc[:settlement_time] != 0
      end

      # check whether there are some related ctx or fund tx submitted to chain.
      for i in (checked_height..current_height)
        puts i
        block = @api.get_block_by_number(i)
        for transaction in block.transactions
          index = 0
          for output in transaction.outputs
            remote_lock = output.lock

            next if remote_lock.code_hash != @gpc_code_hash

            # get remote args.
            remote_lock_args = @tx_generator::parse_lock_args(remote_lock.args)
            nounce_on_chain = remote_lock_args[:nounce]
            lock_args = @tx_generator.generate_lock_args(remote_lock_args[:id], 0, remote_lock_args[:timeout],
                                                         0, remote_lock_args[:pubkey_A], remote_lock_args[:pubkey_B])
            remote_lock.args = lock_args
            remote_script = CKB::Serializers::ScriptSerializer.new(remote_lock).serialize

            view = @coll_sessions.find { }
            view.each do |doc|
              local_script = doc[:gpc_script]
              nounce_local = doc[:nounce]
              next if local_script != remote_script

              if nounce_on_chain == 0 && nounce_local == 1
                # it is the fund tx...
                @coll_sessions.find_one_and_update({ id: doc[:id] }, { "$set" => { stage: doc[:stage] + 1 } })
                ctx_input_h = @tx_generator.convert_input(transaction, index, 0).to_h
                @coll_sessions.find_one_and_update({ id: doc[:id] }, { "$set" => { ctx_input: ctx_input_h } })
              elsif nounce_on_chain < nounce_local
                @coll_sessions.find_one_and_update({ id: doc[:id] }, { "$set" => { stage: doc[:stage] + 1 } })
                ctx_input_h = @tx_generator.convert_input(transaction, index, 0).to_h
                @coll_sessions.find_one_and_update({ id: doc[:id] }, { "$set" => { ctx_input: ctx_input_h } })
                send_ctx()
              elsif nounce_on_chain == nounce_local
                @coll_sessions.find_one_and_update({ id: doc[:id] }, { "$set" => { settlement_time: i + doc[:timeout] } })
                stx_input_h = @tx_generator.convert_input(transaction, index, 0).to_h
                @coll_sessions.find_one_and_update({ id: doc[:id] }, { "$set" => { stx_input: stx_input_h } })
              elsif nounce_on_chain > nounce_local
                puts "well, there is something wrong."
              end

              index += 1
            end
          end
        end
      end

      # just update the checked block!
    end
  end

  # Need to construct corresponding txs.

  def send_ctx(id, fee = 10000)
    gpc_input = @coll_sessions.find({ id: id }).first[:ctx_input]

    # find the fee cells.

    # get the inputs.

    # construct the corresponding data...
  end

  def send_ctx(id, fee = 10000)

    # get related input.
    gpc_input = @coll_sessions.find({ id: id }).first[:stx_input]

    # get the closing information.
    ctx_info_json = @coll_sessions.find({ id: id }).first[:ctx]
    ctx_info = json_to_info(ctx_info_json)

    # get the fee cell.
    capa = 61
    fee_cell = gather_inputs(capa, fee)

    # construct the change output.
    local_change_output = CKB::Types::Output.new(
      capacity: capa,
      lock: local_default_lock,
      type: nil,
    )

    # inputs done!
    closing_input = [closing_input, fee_cell.inputs[0]]

    # prepare the output, output_data and witness.

    # the output is very simple, just add the change to it.

    # the output also, just set it to 0x

    # the witness.., well I need to construct it.

    # find the fee cells.

    # get the inputs.

    # construct the corresponding data...
  end
end
