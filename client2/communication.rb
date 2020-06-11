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

  def listen(src_port, command_file)
    puts "listen start"
    stage = 0
    server = TCPServer.open(src_port)
    loop {
      Thread.start(server.accept) do |client|
        #parse the msg
        msg = client.gets

        msg = JSON.parse(msg)
        trg_pbk = msg["pbk"]
        trg_cells = msg["cells"]
        trg_capacity = msg["capacity"]
        trg_fee = msg["fee"]

        #check the cell is live and the amount is right

        api = CKB::API::new

        capacity_check = 0
        for cell in trg_cells
          out_point = CKB::Types::OutPoint.new(
            tx_hash: cell["tx_hash"],
            index: cell["index"],
          )
          validation = api.get_live_cell(out_point)
          capacity_check += validation.cell.output.capacity
          if validation.status != "live"
            client.puts "sry, your cells are invalid"
            client.close
            Thread.kill
          end
        end

        if capacity_check < trg_capacity
          client.puts "sry, your cells are invalid"
          client.close
          Thread.kill
        end

        trg_change = capacity_check - trg_capacity

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
          #these code need to be more robust.
          puts "Please input the capacity you want to use for funding"
          capacity = command_file.gets.gsub("\n", "").to_i
          fee = command_file.gets.gsub("\n", "").to_i
          break
        end

        input_cells = gather_inputs(capacity, fee)
        src_change = input_cells.capacities - capacity

        gpc_capacity = trg_capacity + capacity
        #merge the fund cells

        #get the trg input and witness

        # input = CKB::Types::Input.new(
        #   previous_output: cell.out_point,
        #   since: 0
        # )
        fund_inputs = Array.new()
        for cell in trg_cells
          out_point = CKB::Types::OutPoint.new(
            tx_hash: cell["tx_hash"],
            index: cell["index"],
          )
          fund_inputs << CKB::Types::Input.new(
            previous_output: out_point,
            since: cell["since"],
          )
        end

        fund_inputs += input_cells.inputs

        fund_witnesses = Array.new()

        for iter in fund_inputs
          fund_witnesses << CKB::Types::Witness.new
        end
        # for cell in input_cells.inputs
        #   fund_cells << { index: cell.previous_output.index, tx_hash: cell.previous_output.tx_hash }
        # end

        # Let us create the tx
        @tx_generator.generate_fund_tx(fund_inputs, fund_witnesses, gpc_capacity, src_change, trg_change, trg_pbk)
        #find cells, if it is used for UDT, it may change.

        #stage2

        #check the ctx, stx is right, and the signatrue is valid.

        #send the IP, PK, ctx, stx.

        #stage 3

        #check the signature is valid

        #reply with the signed fund tx.
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

    msg = { type: 1, pbk: pbk, cells: fund_cells, capacity: capacity_input_cells }
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
