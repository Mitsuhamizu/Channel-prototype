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

  # The capacity is only the capcity of GPC, we should add the fee to it is the total_capacity.
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

def get_total_capacity(cells)
  total_capacity = 0
  for cell in cells
    validation = @api.get_live_cell(cell.previous_output)
    total_capacity += validation.cell.output.capacity
    return -1 if validation.status != "live"
  end
  return total_capacity
end

def check_cells(cells, capacity)
  capacity_check = get_total_capacity(cells)
  if capacity > capacity_check || capacity_check == -1
    return -1
  end
  return capacity_check
end
