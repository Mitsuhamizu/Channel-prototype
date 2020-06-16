#!/usr/bin/ruby -w

require "socket"
require "json"
require "rubygems"
require "bundler/setup"
require "ckb"
require "./tx_generator.rb"

class Communication
  def initialize(private_key)
    @key = CKB::Key.new("0x" + private_key)
    @api = CKB::API::new
    @wallet = CKB::Wallet.from_hex(@api, @key.privkey)
    @tx_generator = Tx_generator.new(@key)
    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database
    @coll_session = @db[@key.pubkey + "_session_pool"]
  end

  def group_tx_input(tx)
    group = Hash.new()
    index = 0
    for input in tx.inputs
      validation = @api.get_live_cell(input.previous_output)
      lock_hash = validation.cell.output.lock.compute_hash
      if !group.keys.include?(lock_hash)
        group[lock_hash] = Array.new()
      end
      group[lock_hash] << index
      index += 1
    end
    return group
  end

  
  def sign_fund_tx(tx)
    input_group = group_tx_input(tx)

    for key in input_group.keys
      first_index = input_group[key][0]

      # include the first witness
      blake2b = CKB::Blake2b.new
      emptied_witness = tx.witnesses[first_index].dup
      emptied_witness.lock = "0x#{"0" * 130}"
      emptied_witness_data_binary = CKB::Utils.hex_to_bin(CKB::Serializers::WitnessArgsSerializer.from(emptied_witness).serialize)
      emptied_witness_data_size = emptied_witness_data_binary.bytesize
      blake2b.update(CKB::Utils.hex_to_bin(tx.hash))
      blake2b.update([emptied_witness_data_size].pack("Q<"))
      blake2b.update(emptied_witness_data_binary)

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
      message = blake2b.hexdigest
      tx.witnesses[first_index].lock = @key.sign_recoverable(message)
    end

    return tx
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

  def check_cells(cells, capacity)
    capacity_check = 0
    for cell in cells
      validation = @api.get_live_cell(cell.previous_output)
      capacity_check += validation.cell.output.capacity
      if validation.status != "live"
        return -1
      end
    end
    if capacity > capacity_check
      return -1
    end
    return capacity_check
  end

  def listen(src_port, command_file)
    puts "listen start"
    stage = 0
    server = TCPServer.open(src_port)
    loop {
      Thread.start(server.accept) do |client|

        #parse the msg
        msg = client.gets
        puts msg
        msg = JSON.parse(msg)
        cells = msg["cells"]
        puts msg
        puts cells
        cells = JSON.parse(cells)

        #check the cell is live'
        #!!!!! it needs a loop
        api = CKB::API::new
        out_point = CKB::Types::OutPoint.new(
          tx_hash: cells["tx_hash"],
          index: cells["index"].to_i,
        )
        validation = api.get_live_cell(out_point)
        if validation.status != "live"
          client.puts "sry, your cells are invalid"
          client.close
          Thread.kill
        end

        puts "Tell me whether you are willing to accept this request"

        #stage 0
        while true
          # response = STDIN.gets.chomp
          response = command_file.gets.gsub("\n", "")
          if response == "yes"
            stage += 1
            break
          elsif response == "no"
            puts "reject it "
            break
          else
            puts "your input is invalid"
          end
        end

        #stage 1

        while true
          puts "Please input the capacity you want to use for funding"
          capacity = command_file.gsub("\n", "")
          break
        end

        #find cells, if it is used for UDT, it may change.

        # Well, just assume give the cell.
        # give the reply info IP,PK,cells

        #stage2

        #check the ctx, stx is right, and the signatrue is valid.

        #send the IP, PK, ctx, stx.

        #stage 3

        #check the signature is valid

        #reply with the signed fund tx.
      end
    }
  end

  def send_establish_channel(trg_ip, trg_port, capacity, fee)

    #gather the input.
    s = TCPSocket.open(trg_ip, trg_port)
    input_cells = gather_inputs(capacity, fee)
    fund_cells = input_cells.inputs.map(&:to_h)

    #init the msg
    ip_address = Socket.ip_address_list.detect { |intf| intf.ipv4_private? }.ip_address
    session_id = (ip_address + fund_cells.to_json).hash
    fund_capacity = capacity
    msg = { id: session_id, type: 1, pbk: @key.pubkey, fund_cells: fund_cells, fund_capacity: fund_capacity, fee: fee }.to_json
    s.puts msg

    reply_1st = JSON.parse(s.gets, symbolize_names: true)

    # If the msg is error, just exit.
    if reply_1st[:type] == 0
      puts reply_1st[:text]
      return -1
    end

    #else, just parse the fund tx
    fund_tx = CKB::Types::Transaction.from_h(reply_1st[:fund_tx])
    puts (reply_1st[:fund_tx])
    tx_fund_file = File.new("./tx_fund_file.json", "w")
    tx_fund_file.syswrite(reply_1st[:fund_tx].to_json)
    tx_fund_file.close

    trg_fund_cells = fund_tx.inputs.map(&:to_h) - fund_cells
    trg_fund_cells = trg_fund_cells.map { |cell| CKB::Types::Input.from_h(cell) }

    #check the cpacity and the cells are alive.
    capacity_check = check_cells(trg_fund_cells, reply_1st[:capacity])
    if capacity_check == -1
      msg = generate_text_msg("sry, your capacity is not enough or your cells are not alive.")
      s.puts msg
      s.close
      return -1
    end

    #construct ctx and stx.

    # ctx = @tx_generator.generate_closing_tx(fund_tx)

    #check the ctx, stx is right, and the signature is valid, note that the signature of ctx is no-input-signature.

    #stage 3

    #send the fund tx

    fund_tx = sign_fund_tx(fund_tx)

    #check the reply is valid.

    reply = s.gets
    # reply = JSON.parse(reply, symbolize_names: true)
    # fund_tx = CKB::Types::Transaction.from_h(reply)ƒ
  end

  # def send(pbk, trg_ip, trg_port, capacity, fee)
  # end
end
