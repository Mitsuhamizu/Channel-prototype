require "rubygems"
require "bundler/setup"
require "ckb"


lock_hashes, type_script_hash = "", decoder = nil)

from_block_number = 0
current_height = @api.get_tip_block_number
amount_gathered = 0
for lock_hash in lock_hashes
  while from_block_number <= current_height
    current_to = [from_block_number + 100, current_height].min
    cells = @api.get_cells_by_lock_hash(lock_hash, from_block_number, current_to)
    for cell in cells
      validation = @api.get_live_cell(cell.out_point)
      return nil if validation.status != "live"

      tx = @api.get_transaction(cell.out_point.tx_hash).transaction
      type_script = tx.outputs[cell.out_point.index].type
      type_script_hash_current = type_script == nil ? "" : type_script.compute_hash
      @logger.info("#{cell.to_h}")
      next if type_script_hash_current != type_script_hash
      amount_gathered += decoder == nil ?
        tx.outputs[cell.out_point.index].capacity :
        decoder.call(tx.outputs_data[cell.out_point.index])
    end
    from_block_number = current_to + 1
  end
end