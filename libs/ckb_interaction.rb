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
      next if cell.type != nil
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

def get_total_amount(cells, type_script_hash, decoder)
  amount_gathered = 0
  # check amount.
  for cell in cells
    # check live.
    validation = @api.get_live_cell(cell.previous_output)
    return false if validation.status != "live"

    # add amount
    tx = @api.get_transaction(cell.previous_output.tx_hash).transaction
    type_script = tx.outputs[cell.previous_output.index].type
    next if decoder != nil &&
            (type_script == nil ||
             type_script.compute_hash != type_script_hash)
    amount_gathered += decoder == nil ?
      tx.outputs[cell.previous_output.index].capacity :
      decoder.call(tx.outputs_data[cell.previous_output.index])
  end

  return amount_gathered
end

# def get_fee_cell(cells)
#   amount_gathered
#   for cell in cells
#     # check live.
#     validation = @api.get_live_cell(cell.previous_output)
#     return false if validation.status != "live"

#     # add amount
#     tx = @api.get_transaction(cell.previous_output.tx_hash).transaction
#     type_script = tx.outputs[cell.previous_output.index].type

#     amount_gathered += decoder == nil ?
#       tx.outputs[cell.previous_output.index].capacity :
#       decoder.call(tx.outputs_data[cell.previous_output.index])
#   end
# end

def check_cells(cells, type_script_hash, amount_required, decoder)
  amount_gathered = get_total_amount(cells, type_script_hash, decoder)
  return amount_gathered && amount_gathered > amount_required ? amount_gathered : false
  # check_fee
end

def construct_change_output(output, output_data, amount, decoder)
  cell_change = cell
  if decoder
  else
  end
end
