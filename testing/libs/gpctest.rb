require "rubygems"
require "bundler/setup"
require "minitest/autorun"
require "ckb"

# udt_code: https://github.com/ZhichunLu-11/ckb-gpc-contract/blob/f39fd7774019d0333857f8e6861300a67fb1e266/c/simple_udt.c
# note that I change the byte of amount in UDT to 8.

# gpc_code https://github.com/ZhichunLu-11/ckb-gpc-contract/blob/f39fd7774019d0333857f8e6861300a67fb1e266/main.c
# here I setup the environment for testing.
# 1. deploy the gpc contract.
# 2. deploy the udt contract.
# 3. create and disseminate UDT to two account.

class Gpctest < Minitest::Test
  def initialize(name)
    super(name)
    @privkey = "0xd00c06bfd800d27397002dca6fb0993d5ba6399b4238b2f29ee9deb97593d2bc"
    @api = CKB::API::new
    @rpc = CKB::RPC.new
    @wallet = CKB::Wallet.from_hex(@api, @privkey)
  end

  def generate_blocks(rpc, num)
    for i in 0..num
      rpc.generate_block
    end
    return true
  end

  def deploy_contract(data)
    code_hash = CKB::Blake2b.hexdigest(data)
    data_size = data.bytesize
    tx_hash = @wallet.send_capacity(@wallet.address, CKB::Utils.byte_to_shannon(data_size + 10000), CKB::Utils.bin_to_hex(data), fee: 10 ** 6)
    return [code_hash, tx_hash]
  end

  def setup
    # back to 0 block.
    @rpc.truncate("0x823b2ff5785b12da8b1363cac9a5cbe566d8b715a4311441b119c39a0367488c")
    local_height = @api.get_tip_block_number
    generate_blocks(@rpc, 5)
    # back to the first block.

    # send gpc to the chain.
    gpc_data = File.read("./binary/gpc")
    gpc_code_hash, gpc_tx_hash = deploy_contract(gpc_data)
    generate_blocks(@rpc, 5)

    # send udt to the chain.
    udt_data = File.read("./binary/simple_udt")
    udt_code_hash, udt_tx_hash = deploy_contract(udt_data)

    # check the tx onchain.
    tx_checked = [gpc_tx_hash, udt_tx_hash]
    while true
      generate_blocks(@rpc, 5)
      remote_height = @api.get_tip_block_number
      for i in (local_height + 1..remote_height)
        block = @api.get_block_by_number(i)
        for transaction in block.transactions
          if tx_checked.include? transaction.hash
            tx_checked.delete(transaction.hash)
          end
        end
      end
      break if tx_checked == []
    end

    # disseminate udt.

    # these two lock belong to the testing accounts in dev-chain.
    # you can find the detail in dev.toml, line 71-78
    default_lock_1 = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                            args: "0xc8328aabcd9b9e8e64fbc566c4385c3bdeb219d7", hash_type: CKB::ScriptHashType::TYPE)
    default_lock_2 = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH,
                                            args: "0x470dcdc5e44064909650113a274b3b36aecb6dc7", hash_type: CKB::ScriptHashType::TYPE)

    udt_dep = CKB::Types::CellDep.new(out_point: CKB::Types::OutPoint.new(tx_hash: udt_tx_hash, index: 0))

    # send UDT randomly for ten times.
    for iter in 0..10
      tx = @wallet.generate_tx(@wallet.address, CKB::Utils.byte_to_shannon(2000), fee: 1000)
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

      # split the output
      outputs = tx.outputs
      first_output = outputs[0]
      first_output.capacity /= 2
      first_output.type = type_script
      second_output = first_output.dup

      first_output.lock = default_lock_1
      second_output.lock = default_lock_2

      tx.outputs.delete_at(0)
      tx.outputs.insert(0, first_output)
      tx.outputs.insert(0, second_output)

      # generate UDT amount.
      tx.outputs_data[0] = CKB::Utils.bin_to_hex([rand(0..100)].pack("Q<"))
      tx.outputs_data[1] = CKB::Utils.bin_to_hex([rand(0..100)].pack("Q<"))
      tx.outputs_data << "0x"

      signed_tx = tx.sign(@wallet.key)
      root_udt_tx_hash = @api.send_transaction(signed_tx)
      generate_blocks(@rpc, 5)
    end

    # record these info to json.
    script_info = { gpc_code_hash: gpc_code_hash, gpc_tx_hash: gpc_tx_hash,
                    udt_code_hash: udt_code_hash, udt_tx_hash: udt_tx_hash,
                    type_script: type_script.to_h.to_json }
    file = File.new("./files/contract_info.json", "w")
    file.syswrite(script_info.to_json)
    file.close()
  end

  # get amount of asset by type and lock_hashes.
  def get_balance(lock_hashes, type_script_hash = "", decoder = nil)
    from_block_number = 0
    current_height = @api.get_tip_block_number
    amount_gathered = 0
    for lock_hash in lock_hashes
      while from_block_number <= current_height
        current_to = [from_block_number + 100, current_height].min
        cells = @api.get_cells_by_lock_hash(lock_hash, from_block_number, current_to)
        for cell in cells
          tx = @api.get_transaction(cell.out_point.tx_hash).transaction
          type_script = tx.outputs[cell.out_point.index].type
          type_script_hash_current = type_script == nil ? "" : type_script.compute_hash
          next if type_script_hash_current != type_script_hash
          amount_gathered += decoder == nil ?
            tx.outputs[cell.out_point.index].capacity :
            decoder.call(tx.outputs_data[cell.out_point.index])
        end
        from_block_number = current_to + 1
      end
    end

    return amount_gathered
  end
end
