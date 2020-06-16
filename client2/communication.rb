#!/usr/bin/ruby -w

require "socket"
require "json"
require "rubygems"
require "bundler/setup"
require "ckb"
require "./tx_generator.rb"
require "mongo"

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

  def recv_establish_channel(client, msg, command_file)
    id = msg[:id]
    #TO-DO
    #check the id!!!!!!!!
    # sock_domain, remote_port, remote_hostname, remote_ip = client.peeraddr
    # id_check

    #check the id is brand new, i.e., there is no same id in the database.
    view = @coll_session.find("id" => id)
    if view.count != 0
      return -1
    end

    # parse the msg
    trg_pbk = msg[:pbk]
    trg_capacity = msg[:fund_capacity]
    trg_fee = msg[:fee]
    trg_cells = msg[:fund_cells].map { |cell| CKB::Types::Input.from_h(cell) }
    # trg_cells = Array.new()
    # for cell in msg[:fund_cells]
    #   trg_cells << CKB::Types::Input.from_h(cell)
    # end

    # check the cell is live and the capacity is enough.
    capacity_check = check_cells(trg_cells, trg_capacity)
    if capacity_check == -1
      msg = generate_text_msg("sry, your capacity is not enough or your cells are not alive.")
      client.puts msg
      client.close
      return -1
    end
    trg_change = capacity_check - trg_capacity

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
      capacity = command_file.gets.gsub("\n", "").to_i
      fee = command_file.gets.gsub("\n", "").to_i
      break
    end

    #gather the fund input.
    input_cells = gather_inputs(capacity, fee)
    src_change = input_cells.capacities - capacity

    gpc_capacity = trg_capacity + capacity

    #merge the fund cells and the witness.
    fund_inputs = trg_cells + input_cells.inputs

    fund_witnesses = Array.new()
    for iter in fund_inputs
      fund_witnesses << CKB::Types::Witness.new
    end

    # Let us create the tx.
    fund_tx = @tx_generator.generate_fund_tx(fund_inputs, fund_witnesses, gpc_capacity, src_change, trg_change, trg_pbk)
    fund_tx.witnesses[0].lock = "" #empty the signature, the default tx_generator in CKB has signed the tx.
    msg = { id: id, type: 1, fund_tx: fund_tx.to_h, capacity: capacity }.to_json
    client.puts(msg)

    # puts tx_send

    #find cells, if it is used for UDT, it may change.

    #stage2

    #check the ctx, stx is right, and the signatrue is valid.

    #send the IP, PK, ctx, stx.

    #stage 3

    #check the signature is valid

    #reply with the signed fund tx.

    client.close
  end

  def listen(src_port, command_file)
    puts "listen start"
    api = CKB::API::new
    stage = 0
    server = TCPServer.open(src_port)
    loop {
      Thread.start(server.accept) do |client|
        #parse the msg
        msg = client.gets

        msg = JSON.parse(msg, symbolize_names: true)
        msg_type = msg[:type]

        case msg_type
        when 1
          recv_establish_channel(client, msg, command_file)
          # else
          #   make_payment()
        end
      end
    }
  end

  def send(pbk, trg_ip, trg_port, capacity, fee)
    s = TCPSocket.open(trg_ip, trg_port)
    input_cells = gather_inputs(capacity, fee)
    fund_cells = Array.new()
    for cell in input_cells.inputs
      fund_cells << { index: cell.previous_output.index, tx_hash: cell.previous_output.tx_hash }
    end
    capacity_input_cells = input_cells.capacities

    #stage 0 prepare
    #get cells with the capcity

    msg = { id: id, type: 1, pbk: pbk, cells: fund_cells, capacity: capacity_input_cells }
    msg = msg.to_json
    s.puts msg

    # check the cell is live and the capacity is right. (If not the whole capcaity? I am not sure.)

    #stage 2

    #send Ip, PK, ctx, stx.
    # generator = Tx_generator.new()

    #check the ctx, stx is right, and the signature is valid, note that the signature of ctx is no-input-signature.

    #stage 3

    #send the fund tx

    #check the reply is valid.

    # reply = s.gets
    # puts reply
  end
end
