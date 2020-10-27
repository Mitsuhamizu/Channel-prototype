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
def gather_fund_input(locks, amount_required, type_script_hash, decoder, coll_cells)
  @logger.info("gather_input: begin to gather funding.")
  return [] if amount_required == 0
  final_inputs = []
  amount_gathered = 0

  for lock in locks
    # iter the cells.
    search_key = { script: lock.to_h, script_type: "lock" }
    search_result = @rpc.get_cells(search_key, "asc", "0x64")

    # iter all cells
    while true
      last_cursor = search_result[:last_cursor]
      cells = search_result[:objects]

      for cell in cells

        # load type and check the type is same as required.
        type_script = CKB::Types::Script.from_h(cell[:output][:type])
        cell_type_script_hash = type_script == nil ? "" : type_script.compute_hash
        next if cell_type_script_hash != type_script_hash
        # If I fund ckb, I should make there is no data in the output.
        next if cell[:output_data] != "0x" && type_script == nil

        # construct the input.
        current_input = CKB::Types::Input.new(
          previous_output: CKB::Types::OutPoint.from_h(cell[:out_point]),
          since: 0,
        )

        # inquiry whether the cell is in the cell pool.
        # This is to ensure that the same cell can not be sent to two party at the same time.
        view = coll_cells.find({ cell: current_input.to_h })
        next if view.count_documents() != 0

        # add the amount to toal amount and add it to fund input.
        amount_gathered += decoder == nil ?
          cell[:output][:capacity].to_i(16) :
          decoder.call(cell[:output_data])
        final_inputs << current_input

        # add it to the cell pool.
        doc = { cell: current_input.to_h, revival: (Time.new).to_i + 60 }
        coll_cells.insert_one(doc)

        break if amount_gathered >= amount_required
      end

      break if amount_gathered >= amount_required
      break if last_cursor == "0x"
      search_result = @rpc.get_cells(search_key, "asc", "0x64", last_cursor)
    end

    break if amount_gathered >= amount_required
  end

  # puts "here is available ckbyte."
  # puts amount_gathered
  return amount_gathered < amount_required ? amount_gathered - amount_required : final_inputs
end

def gather_fee_cell(locks, fee, coll_cells)
  return [] if fee == 0
  final_inputs = []
  capacity_gathered = 0
  capacity_required = fee

  for lock in locks
    search_key = { script: lock.to_h, script_type: "lock" }
    search_result = @rpc.get_cells(search_key, "asc", "0x64")

    while true
      last_cursor = search_result[:last_cursor]
      cells = search_result[:objects]

      for cell in cells
        # make sure the cell is ckb-only.
        type_script = CKB::Types::Script.from_h(cell[:output][:type])
        next if cell[:output_data] != "0x" || type_script != nil

        # construct the input.
        current_input = CKB::Types::Input.new(
          previous_output: CKB::Types::OutPoint.from_h(cell[:out_point]),
          since: 0,
        )

        # inquiry whether the cell is in the cell pool.
        # This is to ensure that the same cell can not be sent to two party at the same time.
        view = coll_cells.find({ cell: current_input.to_h })
        next if view.count_documents() != 0

        # add the amount to toal amount and add it to fund input.
        capacity_gathered += cell[:output][:capacity].to_i(16)
        final_inputs << current_input

        # add it to the cell pool.
        doc = { cell: current_input.to_h, revival: (Time.new).to_i + 60 }
        coll_cells.insert_one(doc)

        break if capacity_gathered >= capacity_required
        break if last_cursor == "0x"
        search_result = @rpc.get_cells(search_key, "asc", "0x64", last_cursor)
      end

      break if capacity_gathered >= capacity_required
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

def gather_inputs(funding_type_script_version, fee, locks, change_lock_script, refund_lock_script, coll_cells)
  input_cells = []
  change_minimal_capacity = 0
  refund_minimal_capacity = 0
  for asset_type_hash in funding_type_script_version.keys()
    current_type = find_type(asset_type_hash)

    # gather fund inputs according to the type script.
    fund_inputs = gather_fund_input(locks, funding_type_script_version[asset_type_hash], asset_type_hash, current_type[:decoder], coll_cells)
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
  fee_inputs = gather_fee_cell(locks, diff_capacity, coll_cells)
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

def get_investment(output, output_data, decoder)
  return decoder == nil ? output.capacity : decoder.call(output_data)
end

def check_output(amount, output, output_data, decoder)
  if decoder == nil
    @logger.info("check_output: ckb, expect: #{amount}, actual: #{output.capacity - output.calculate_min_capacity(output_data)}")
    return amount - (output.capacity - output.calculate_min_capacity(output_data))
  else
    @logger.info("check_output: udt, expect: #{amount}, actual: #{decoder.call(output_data)}")
    return amount - decoder.call(output_data)
  end
end

def assemble_change(changes)
  @logger.info("#{@key.pubkey} assemble_change: begin.")
  output_assembled = CKB::Types::Output.new(
    capacity: 0,
    lock: nil,
    type: nil,
  )

  output_assembled.capacity = changes.map { |h| h[:output].capacity }.sum
  @logger.info("#{@key.pubkey} assemble_change: capacity assembled.")

  if changes.length == 1
    @logger.info("#{@key.pubkey} assemble_change: branch 1.")
    output_assembled.lock = changes[0][:output].lock
    output_assembled.type = changes[0][:output].type
    output_data_assembled = changes[0][:output_data]
  elsif changes.length == 2
    @logger.info("#{@key.pubkey} assemble_change: branch 2.")
    if changes[0][:output].type != nil
      asset_change_index = 0
    elsif changes[1][:output].type
      asset_change_index = 1
    else
      asset_change_index = -1
    end

    return "lock_inconsistent" if changes[0][:output].lock.to_h != changes[1][:output].lock.to_h
    return "type_collision" if changes[0][:output].type != nil && changes[1][:output].type != nil

    output_assembled.lock = changes[asset_change_index][:output].lock
    output_assembled.type = changes[asset_change_index][:output].type
    output_data_assembled = changes[asset_change_index][:output_data]
  else
    return "length_unknow"
  end

  return { output: output_assembled, output_data: output_data_assembled }
end

# def check_cells(cells, amount_required, fee_required, change, stx_info, type_script_hash, decoder)
def check_cells(cells, remote_asset, fee_required, changes, stx_info)
  @logger.info("#{@key.pubkey} check cells: amount begin.")

  for change in changes
    change_actual = change[:output].capacity
    change_min = change[:output].calculate_min_capacity(change[:output_data])
    return "error_change_container_insufficient", change_actual - change_min if change_actual < change_min
  end

  stx_actual = stx_info[:outputs][0].capacity
  stx_min = stx_info[:outputs][0].calculate_min_capacity(stx_info[:outputs_data][0])
  return "error_settle_container_insufficient", stx_actual - stx_min if stx_actual < stx_min

  change = assemble_change(changes)

  capacity_gathered = get_total_capacity(cells)
  return "error_cell_dead", true if !capacity_gathered
  # check stx is enough.
  for current_type_script_hash in remote_asset.keys()
    current_type = find_type(current_type_script_hash)
    current_decoder = current_type[:decoder]
    # I only import one stx, so the index is 0.
    check_output_result = check_output(remote_asset[current_type_script_hash], stx_info[:outputs][0], stx_info[:outputs_data][0], current_decoder)
    # check the amount he invests is right as he claims.
    return "error_amount_invest_inconsistent", check_output_result if check_output_result != 0
    # check change + settelement refund is equal to amount_total
    if current_type_script_hash != ""
      amount_required = remote_asset[current_type_script_hash]
      amount_gathered = get_total_amount(cells, current_type_script_hash, current_decoder)
      refund_amount = current_decoder.call(stx_info[:outputs_data][0]) + current_decoder.call(change[:output_data])
      return "error_amount_refund_inconsistent", amount_gathered - refund_amount if amount_gathered != refund_amount
    end
  end

  refund_capacity = change[:output].capacity + stx_info[:outputs][0].capacity

  return "error_capacity_inconsistent", capacity_gathered - (fee_required + refund_capacity) if capacity_gathered != fee_required + refund_capacity

  @logger.info("#{@key.pubkey} check cells: capacity end.")
  return "success", "0"
end
