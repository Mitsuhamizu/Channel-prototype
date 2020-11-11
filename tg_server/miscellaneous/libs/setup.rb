require "rubygems"
require "bundler/setup"
require "minitest/autorun"
require "mongo"
require "json"
require "ckb"
require "logger"

# udt_code: https://github.com/ZhichunLu-11/ckb-gpc-contract/blob/f39fd7774019d0333857f8e6861300a67fb1e266/c/simple_udt.c
# note that I change the byte of amount in UDT from 16 to 8.

# gpc_code https://github.com/ZhichunLu-11/ckb-gpc-contract/blob/f39fd7774019d0333857f8e6861300a67fb1e266/main.c

# The two account are test account in ckb-dev.

# # issue for random generated private key: d00c06bfd800d27397002dca6fb0993d5ba6399b4238b2f29ee9deb97593d2bc
# [[genesis.issued_cells]]
# capacity = 20_000_000_000_00000000
# lock.code_hash = "0x9bd7e06f3ecf4be0f2fcd2188b23f1b9fcc88e5d4b65a8637b17723bbda3cce8"
# lock.args = "0xc8328aabcd9b9e8e64fbc566c4385c3bdeb219d7"
# lock.hash_type = "type"

# # issue for random generated private key: 63d86723e08f0f813a36ce6aa123bb2289d90680ae1e99d4de8cdb334553f24d
# [[genesis.issued_cells]]
# capacity = 5_198_735_037_00000000
# lock.code_hash = "0x9bd7e06f3ecf4be0f2fcd2188b23f1b9fcc88e5d4b65a8637b17723bbda3cce8"
# lock.args = "0x470dcdc5e44064909650113a274b3b36aecb6dc7"
# lock.hash_type = "type"

# note that A is users and B is robot.
# A send establishment request to B and then the channel established.

$VERBOSE = nil

class Gpctest < Minitest::Test
  def initialize(name)
    super(name)

    @path_to_binary = __dir__ + "/../binary/"
    @path_to_file = __dir__ + "/../files/"
    @path_to_user = __dir__ + "/../../User/GPC"
    @path_to_robot = __dir__ + "/../../Robot/GPC"

    @api = CKB::API::new
    @rpc = CKB::RPC.new

    @secp_args_A = "0x470dcdc5e44064909650113a274b3b36aecb6dc7"
    @private_key_A = "0x63d86723e08f0f813a36ce6aa123bb2289d90680ae1e99d4de8cdb334553f24d"
    @pubkey_A = "0x038d3cfceea4f9c2e76c5c4f5e99aec74c26d6ac894648b5700a0b71f91f9b5c2a"
    @ip_A = "127.0.0.1"

    @secp_args_B = "0xc8328aabcd9b9e8e64fbc566c4385c3bdeb219d7"
    @private_key_B = "0xd00c06bfd800d27397002dca6fb0993d5ba6399b4238b2f29ee9deb97593d2bc"
    @pubkey_B = "0x03fe6c6d09d1a0f70255cddf25c5ed57d41b5c08822ae710dc10f8c88290e0acdf"
    @ip_B = "127.0.0.1"

    @default_lock_A = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                             args: @secp_args_A, hash_type: CKB::ScriptHashType::TYPE)
    @default_lock_B = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                             args: @secp_args_B, hash_type: CKB::ScriptHashType::TYPE)

    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database
    @coll_session_A = @db[@pubkey_A + "_session_pool"]
    @coll_session_B = @db[@pubkey_B + "_session_pool"]

    @listen_port_A = 1000
    @listen_port_B = 2000

    @wallet_A = CKB::Wallet.from_hex(@api, "0x85ce75a6b678c6930a4f0938588f0240784971bb03632f1a2f1b25102b7cf5f0")
    @wallet_B = CKB::Wallet.from_hex(@api, @private_key_B)
    @logger = Logger.new(@path_to_file + "gpc.log")
  end

  def deploy_contract(data)
    code_hash = CKB::Blake2b.hexdigest(data)
    data_size = data.bytesize
    puts "prepare to send it."
    puts data_size
    tx_hash = @wallet_A.send_capacity(@wallet_A.address, CKB::Utils.byte_to_shannon(data_size + 1000), CKB::Utils.bin_to_hex(data), fee: 10 ** 6)
    puts tx_hash
    return [code_hash, tx_hash]
  end

  def spend_cell(party, inputs)
    return false if inputs == nil
    outputs = []
    outputs_data = []
    witnesses = []

    tx = CKB::Types::Transaction.new(
      version: 0,
      cell_deps: [],
      inputs: [],
      outputs: nil,
      outputs_data: nil,
      witnesses: nil,
    )

    for input in inputs
      previous_tx = @api.get_transaction(input.tx_hash).transaction
      previous_output = previous_tx.outputs[input.index]

      # construct output
      output = CKB::Types::Output.new(
        capacity: previous_output.capacity - 3000,
        lock: previous_output.lock,
        type: previous_output.type,
      )
      # add output, output_data and witness

      outputs << output
      outputs_data << previous_tx.outputs_data[input.index]
      witnesses << CKB::Types::Witness.new

      tx.inputs << CKB::Types::Input.new(
        previous_output: input,
        since: 0,
      )
    end
    tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_code_out_point, dep_type: "code")
    tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_data_out_point, dep_type: "code")
    tx.cell_deps << load_type_dep()

    tx.outputs = outputs
    tx.outputs_data = outputs_data
    tx.witnesses = witnesses

    tx.hash = tx.compute_hash

    # sign the tx
    if party == "A"
      signed_tx = tx.sign(@wallet_A.key)
    elsif party == "B"
      signed_tx = tx.sign(@wallet_B.key)
    end

    @api.send_transaction(signed_tx)
  end

  # here I setup the environment for testing.
  # 1. deploy the gpc contract.
  # 2. deploy the udt contract.
  # 3. create and disseminate UDT to two account.
  def setup
    # back to 0 block.
    # @rpc.truncate("0x823b2ff5785b12da8b1363cac9a5cbe566d8b715a4311441b119c39a0367488c")
    local_height = @api.get_tip_block_number
    # generate 5 blocks to enable the initial cells can be spent.

    # send gpc contract to the chain.
    # gpc_data = File.read(@path_to_binary + "gpc")
    # gpc_code_hash, gpc_tx_hash = deploy_contract(gpc_data)

    # puts "gpc sent"
    # sleep(10)
    # send udt contract to the chain.
    udt_data = File.read(@path_to_binary + "simple_udt")
    # udt_code_hash, udt_tx_hash = deploy_contract(udt_data)
    udt_code_hash = CKB::Blake2b.hexdigest(udt_data)
    puts "udt sent"
    # ensure the tx onchain.
    # tx_checked = [gpc_tx_hash, udt_tx_hash]
    # while true
    #   remote_height = @api.get_tip_block_number
    #   for i in (local_height + 1..remote_height)
    #     block = @api.get_block_by_number(i)
    #     for transaction in block.transactions
    #       if tx_checked.include? transaction.hash
    #         tx_checked.delete(transaction.hash)
    #       end
    #     end
    #   end
    #   break if tx_checked == []
    # end
    udt_tx_hash = "0x63bb08c125c028c556789a1d6e095c89577ecb4d133d5e642c225bdbdc70ab29"
    # disseminate udt.
    udt_dep = CKB::Types::CellDep.new(out_point: CKB::Types::OutPoint.new(tx_hash: udt_tx_hash, index: 0))

    tx = @wallet_A.generate_tx(@wallet_A.address, CKB::Utils.byte_to_shannon(2000), fee: 1000)
    tx.cell_deps.push(udt_dep.dup)
    # generate the udt type script.
    # set the args as the input lock to represent his is the owner, for more deteil, you can
    # have a look at the simple_udt.c.

    for input in tx.inputs
      cell = @api.get_live_cell(input.previous_output)
      next if cell.status != "live"
      input_lock = cell.cell.output.lock
      input_lock_ser = input_lock.compute_hash
      type_script = CKB::Types::Script.new(code_hash: udt_code_hash,
                                           args: input_lock_ser, hash_type: CKB::ScriptHashType::DATA)
    end

    # generate UDT amount.
    tx.outputs[0].type = type_script
    tx.outputs_data[0] = CKB::Utils.bin_to_hex([10000000].pack("Q<"))

    signed_tx = tx.sign(@wallet_A.key)
    # root_udt_tx_hash = @api.send_transaction(signed_tx)
    # puts root_udt_tx_hash

    # system("rm #{@path_to_file}result.json")
    # # system("rm #{@path_to_file}gpc.log")
    # # record these info to json. So the gpc client can read them.
    # script_info = { gpc_code_hash: gpc_code_hash, gpc_tx_hash: gpc_tx_hash,
    #                 udt_code_hash: udt_code_hash, udt_tx_hash: udt_tx_hash,
    #                 type_script: type_script.to_h.to_json }
    # file = File.new(@path_to_file + "contract_info.json", "w")
    # file.syswrite(script_info.to_json)
    # file.close()

    puts "done!"
  end
end
