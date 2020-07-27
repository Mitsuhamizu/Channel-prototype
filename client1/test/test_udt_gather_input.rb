require "rubygems"
require "bundler/setup"
require "ckb"
require "json"

@api = CKB::API.new

# prikey = "0xd986d7bf901e50368cbe565f239c224934cd554805357338abcef177efadc08d"
prikey = "0x82dede298f916ced53bf5aa87cea8a7e44e8898eaedcff96606579f7bf84d99d"
@key = CKB::Key.new(prikey)
@wallet = CKB::Wallet.from_hex(@api, @key.privkey)

def gather_fund_input(lock_hash, amount_required, type_script_hash, decoder, from_block_number)
  final_inputs = []
  amount_gathered = 0
  current_height = @api.get_tip_block_number()

  while from_block_number <= current_height
    current_to = [from_block_number + 100, current_height].min
    cells = @api.get_cells_by_lock_hash(lock_hash, from_block_number, current_to)
    for cell in cells
      tx = @api.get_transaction(cell.out_point.tx_hash).transaction
      type_script = tx.outputs[cell.out_point.index].type
      next if decoder != nil &&
              (type_script == nil ||
               type_script.compute_hash != type_script_hash)
      amount_gathered += decoder == nil ?
        tx.outputs[cell.out_point.index].capacity :
        decoder.call(tx.outputs_data[cell.out_point.index])

      # add the input.
      final_inputs << CKB::Types::Input.new(
        previous_output: cell.out_point,
        since: 0,
      )

      break if amount_gathered > amount_required
    end

    break if amount_gathered > amount_required
    from_block_number = current_to + 1
  end
  return amount_gathered < amount_required ? false : final_inputs
end

def gather_fee_cell(lock_hash, fee, from_block_number)
  final_inputs = []
  lock = CKB::Types::Script.generate_lock(CKB::Key.blake160(@key.pubkey), CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, CKB::ScriptHashType::TYPE)
  current_height = @api.get_tip_block_number()
  capacity_gathered = 0

  change_output = CKB::Types::Output.new(
    capacity: 0,
    lock: lock,
  )
  change_output_data = "0x"
  capacity_required = change_output.calculate_min_capacity(change_output_data)

  while from_block_number <= current_height
    current_to = [from_block_number + 100, current_height].min
    cells = @api.get_cells_by_lock_hash(lock_hash, from_block_number, current_to)
    for cell in cells
      capacity_gathered += cell.capacity
      # add the input.
      final_inputs << CKB::Types::Input.new(
        previous_output: cell.out_point,
        since: 0,
      )

      break if capacity_gathered > capacity_required
    end

    break if capacity_gathered > capacity_required
    from_block_number = current_to + 1
  end

  return capacity_gathered < capacity_required ? false : final_inputs
end

def gather_inputs(amount, fee, type_script_hash = nil, decoder = nil, from_block_number = 0)

  # gather fund inputs.
  lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: CKB::Key.blake160(@key.pubkey), hash_type: CKB::ScriptHashType::TYPE)
  lock_hash = lock.compute_hash

  fund_inputs = gather_fund_input(lock_hash, amount, type_script_hash, decoder, from_block_number)
  return false if !fund_inputs

  # gather fee cells.

  fee_inputs = gather_fee_cell(lock_hash, fee, from_block_number)
  return false if !fee_inputs

  return fund_inputs + fee_inputs
end

# decoder = Proc.new do |data|
#   result = CKB::Utils.hex_to_bin(data).unpack("Q<")
#   return result
# end

def decoder(data)
  result = CKB::Utils.hex_to_bin(data).unpack("Q<")[0]
  return result.to_i
end

udt_tx_hash = "0xb0e1ade40b8a12edaf9ae4521dac6594da3d7527666fcc687a5f421856a7e45e"
udt_code_hash = "0x2a02e8725266f4f9740c315ac7facbcc5d1674b3893bd04d482aefbb4bdfdd8a"
type_script = CKB::Types::Script.new(code_hash: udt_code_hash, args: "0x32e555f3ff8e135cece1351a6a2971518392c1e30375c1e006ad0ce8eac07947", hash_type: CKB::ScriptHashType::DATA)
type_script_hash = type_script.compute_hash
inputs = gather_inputs(201, 10000, type_script_hash, method(:decoder))
# puts type_script_hash

puts inputs
