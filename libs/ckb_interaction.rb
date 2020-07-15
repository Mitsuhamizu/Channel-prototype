def gather_fund_input(lock_hashes, amount_required, type_script_hash, decoder, from_block_number)
  return [] if amount_required == 0
  final_inputs = []
  amount_gathered = 0
  current_height = @api.get_tip_block_number()

  for lock_hash in lock_hashes
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

    break if amount_gathered > amount_required
  end

  return amount_gathered < amount_required ? false : final_inputs
end

def gather_fee_cell(lock_hashes, fee, from_block_number)
  return [] if fee == 0

  final_inputs = []
  lock = CKB::Types::Script.generate_lock(CKB::Key.blake160(@key.pubkey), CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, CKB::ScriptHashType::TYPE)
  capacity_gathered = 0

  change_output = CKB::Types::Output.new(
    capacity: 0,
    lock: lock,
  )

  change_output_data = "0x"
  capacity_required = change_output.calculate_min_capacity(change_output_data) + fee
  current_height = @api.get_tip_block_number()

  for lock_hash in lock_hashes
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

    break if capacity_gathered > capacity_required
  end

  return capacity_gathered < capacity_required ? false : final_inputs
end

def gather_inputs(amount, fee, lock_hashes, type_script_hash = nil, decoder = nil, from_block_number = 0)

  # gather fund inputs.
  fund_inputs = gather_fund_input(lock_hashes, amount, type_script_hash, decoder, from_block_number)
  return false if !fund_inputs

  # gather fee cells.

  fee_inputs = gather_fee_cell(lock_hashes, fee, from_block_number)
  return false if !fee_inputs

  return fund_inputs + fee_inputs
end

def get_total_capacity(cells)
  capacity_gathered = 0

  for cell in cells
    # check live.
    validation = @api.get_live_cell(cell.previous_output)
    return false if validation.status != "live"

    # add amount
    tx = @api.get_transaction(cell.previous_output.tx_hash).transaction
    capacity_gathered += tx.outputs[cell.previous_output.index].capacity
  end

  return capacity_gathered
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
    # nil, just jump into
    current_type_script_hash = type_script == nil ? "" : type_script.compute_hash
    next if current_type_script_hash != type_script_hash && type_script_hash != ""
    amount_gathered += decoder == nil ?
      tx.outputs[cell.previous_output.index].capacity :
      decoder.call(tx.outputs_data[cell.previous_output.index])
  end

  return amount_gathered
end

def check_cells(cells, amount_required, fee_required, change, stx_info, type_script_hash, decoder)
  # def check_cells(cells, amount_required, fee_required, change, type_script_hash, decoder)
  # 2. the amount is enough, amount_gathered = amount_gpc + amount_change
  # 3. the capacity is enough.
  amount_gathered = get_total_amount(cells, type_script_hash, decoder)

  return false if change[:output].capacity < change[:output].calculate_min_capacity(change[:output_data])
  return false if stx_info[:outputs][0].capacity < stx_info[:outputs][0].calculate_min_capacity(stx_info[:outputs_data][0])

  if type_script_hash != ""
    capacity_gathered = get_total_amount(cells, "", nil)

    # cell live
    return false if !amount_gathered || !capacity_gathered

    # amount right
    return false if amount_gathered != decoder.call(stx_info[:outputs_data][0]) + decoder.call(change[:output_data])

    # capacity right
    return false if capacity_gathered != fee_required + change[:output].capacity + stx_info[:outputs][0].capacity

    # true
    return true
  else
    # cell live
    return false if !amount_gathered

    # capacity right.
    return false if amount_gathered != fee_required + amount_required + change[:output].capacity + stx_info[:outputs][0].capacity

    # true
    return true
  end
end
