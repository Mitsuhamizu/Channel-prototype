require_relative "type_script_info.rb"

def insert_with_check(coll, doc)
  view = coll.find({ id: doc[:id] })
  if view.count_documents() != 0
    puts "sry, there is an record already, please using reset msg."
    return false
  else
    coll.insert_one(doc)
    return true
  end
end

# gather fund amount.
# if decoder == nil and type_script_hash == ""
# it means the asset type is ckbyte.
def gather_fund_input(lock_hashes, amount_required, type_script_hash, decoder, coll_cells, from_block_number = 0)
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
        next if cell.output_data_len != 0 && type_script == nil
        cell_type_script_hash = type_script == nil ? "" : type_script.compute_hash
        next if cell_type_script_hash != type_script_hash
        current_input = CKB::Types::Input.new(
          previous_output: cell.out_point,
          since: 0,
        )
        view = coll_cells.find({ cell: current_input.to_h })
        next if view.count_documents() != 0
        amount_gathered += decoder == nil ?
          tx.outputs[cell.out_point.index].capacity :
          decoder.call(tx.outputs_data[cell.out_point.index])
        final_inputs << current_input
        doc = { cell: current_input.to_h, revival: (Time.new).to_i + 60 }
        coll_cells.insert_one(doc)
        break if amount_gathered >= amount_required
      end

      break if amount_gathered >= amount_required
      from_block_number = current_to + 1
    end
    break if amount_gathered >= amount_required
  end

  puts "here is available ckbyte."
  puts amount_gathered
  return amount_gathered < amount_required ? amount_gathered - amount_required : final_inputs
end

def gather_fee_cell(lock_hashes, fee, coll_cells, from_block_number = 0)
  return [] if fee == 0
  final_inputs = []
  capacity_gathered = 0
  capacity_required = fee
  current_height = @api.get_tip_block_number()

  for lock_hash in lock_hashes
    while from_block_number <= current_height
      current_to = [from_block_number + 100, current_height].min
      cells = @api.get_cells_by_lock_hash(lock_hash, from_block_number, current_to)
      for cell in cells
        # testinghahaha
        next if cell.output_data_len != 0
        next if cell.type != nil
        # add the input.
        current_input = CKB::Types::Input.new(
          previous_output: cell.out_point,
          since: 0,
        )
        # next if current_output_data != "0x" && type_script == nil
        view = coll_cells.find({ cell: current_input.to_h })
        next if view.count_documents() != 0
        capacity_gathered += cell.capacity
        final_inputs << current_input
        break if capacity_gathered >= capacity_required
      end

      break if capacity_gathered >= capacity_required
      from_block_number = current_to + 1
    end

    break if capacity_gathered >= capacity_required
  end

  return capacity_gathered < capacity_required ? capacity_gathered - capacity_required : final_inputs
end

def get_minimal_capacity(lock, type, output_data)
  output = CKB::Types::Output.new(
    capacity: 0,
    lock: lock,
    type: type,
  )
  return 0 if lock == nil
  return output.calculate_min_capacity(output_data)
end

def gather_inputs(funding_type_script_version, fee, lock_hashes, change_lock_script, refund_lock_script, coll_cells, from_block_number = 0)
  input_cells = []
  change_minimal_capacity = 0
  refund_minimal_capacity = 0
  for asset_type_hash in funding_type_script_version.keys()
    current_type = find_type(asset_type_hash)

    # gather fund inputs.
    fund_inputs = gather_fund_input(lock_hashes, funding_type_script_version[asset_type_hash], asset_type_hash, current_type[:decoder], coll_cells, from_block_number)
    return fund_inputs if fund_inputs.is_a? Numeric
    input_cells += fund_inputs
    output_data = current_type[:encoder] == nil ? "0x" : current_type[:encoder].call(0)
    current_change_minimal_capacity = get_minimal_capacity(change_lock_script, current_type[:type_script], output_data)
    current_refund_minimal_capacity = get_minimal_capacity(refund_lock_script, current_type[:type_script], output_data)
    change_minimal_capacity = [change_minimal_capacity, current_change_minimal_capacity].max
    refund_minimal_capacity = [refund_minimal_capacity, current_refund_minimal_capacity].max
  end

  fund_inputs_capacity = get_total_capacity(input_cells)

  @logger.info("gather_input: refund_minimal_capacity: #{refund_minimal_capacity}, change_minimal_capacity: #{change_minimal_capacity}")
  # change capacity
  required_capacity = funding_type_script_version.length() == 1 ?
    refund_minimal_capacity + change_minimal_capacity + fee :
    refund_minimal_capacity + change_minimal_capacity + fee + funding_type_script_version.values()[0]
  # check whether the fund cells' capacity is enought.
  # If yes, it is unnecessary to gather fee cells.

  diff_capacity = required_capacity - fund_inputs_capacity
  return input_cells if diff_capacity <= 0

  # gather fee cells.
  fee_inputs = gather_fee_cell(lock_hashes, diff_capacity, coll_cells, from_block_number)
  return fee_inputs if fee_inputs.is_a? Numeric
  input_cells += fee_inputs
  return input_cells
end

def get_total_capacity(cells)
  capacity_gathered = 0

  for cell in cells
    # check live.
    validation = @api.get_live_cell(cell.previous_output)
    return nil if validation.status != "live"

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
    return nil if validation.status != "live"

    # add amount
    tx = @api.get_transaction(cell.previous_output.tx_hash).transaction
    type_script = tx.outputs[cell.previous_output.index].type
    current_type_script_hash = type_script == nil ? "" : type_script.compute_hash
    next if current_type_script_hash != type_script_hash
    amount_gathered += decoder == nil ?
      tx.outputs[cell.previous_output.index].capacity :
      decoder.call(tx.outputs_data[cell.previous_output.index])
  end

  return amount_gathered
end

# def check_cells(cells, amount_required, fee_required, change, stx_info, type_script_hash, decoder)
def check_cells(cells, remote_asset, fee_required, remote_change, remote_stx_info)
  type_script_hash = remote_asset.values[0]
  type = find_type(type_script_hash)

  amount_gathered = get_total_amount(cells, type_script_hash, type[:decoder])
  # if it is ckb

  # if it is udt

  # check the ckbyte is enough to support this output.
  change_actual = change[:output].capacity
  change_min = change[:output].calculate_min_capacity(change[:output_data])
  stx_actual = stx_info[:outputs][0].capacity
  stx_min = stx_info[:outputs][0].calculate_min_capacity(stx_info[:outputs_data][0])

  return "error_change_container_insufficient", change_actual - change_min if change_actual < change_min
  return "error_settle_container_insufficient", stx_actual - stx_min if stx_actual < stx_min

    

  if type_script_hash != ""
    capacity_gathered = get_total_capacity(cells)

    # cell live
    return "error_cell_dead", true if !amount_gathered || !capacity_gathered
    # amount right
    refund_amount = decoder.call(stx_info[:outputs_data][0]) + decoder.call(change[:output_data])

    return "error_amount_claimed_inconsistent", amount_gathered - amount_required if amount_gathered != amount_required + decoder.call(change[:output_data])
    return "error_amount_refund_inconsistent", amount_gathered - refund_amount if amount_gathered != refund_amount

    # capacity right
    refund_capacity = change[:output].capacity + stx_info[:outputs][0].capacity
    return "error_capacity_inconsistent", capacity_gathered - (fee_required + refund_capacity) if capacity_gathered != fee_required + refund_capacity
    # true
    return "success", "0"
  else
    # cell live
    return "error_cell_dead", true if !amount_gathered

    # capacity right.
    refund_capacity = change[:output].capacity + stx_info[:outputs][0].capacity
    return "error_capacity_inconsistent", amount_gathered - (fee_required + refund_capacity) if amount_gathered != fee_required + refund_capacity

    # true
    return "success", "0"
  end
end
