#!/usr/bin/ruby -w

require "rubygems"
require "bundler/setup"
require "ckb"

class Tx_generator
  def initialize(key)
    @key = key
  end

  def generate_fund_tx(fund_inputs, fund_witnesses, gpc_capacity, src_change, trg_change, trg_pbk)
    src_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: CKB::Key.blake160(@key.pubkey), hash_type: CKB::ScriptHashType::TYPE)
    trg_default_lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: CKB::Key.blake160("0x" + trg_pbk), hash_type: CKB::ScriptHashType::TYPE)
    use_dep_group = true

    gpc_output = CKB::Types::Output.new(
      capacity: gpc_capacity,
      lock: trg_default_lock, #It should be GPC, but now, just use the trg_default_lock
    )

    gpc_output_data = "0x"
    # init the change output
    trg_change_output = CKB::Types::Output.new(
      capacity: trg_change,
      lock: trg_default_lock,
    )
    trg_change_output_data = "0x"
    src_change_output = CKB::Types::Output.new(
      capacity: src_change,
      lock: src_default_lock,
    )
    src_change_output_data = "0x"

    outputs = [gpc_output, src_change_output, trg_change_output]
    outputs_data = [gpc_output_data, src_change_output_data, trg_change_output_data]
    #output
    #outputs data

    tx = CKB::Types::Transaction.new(
      version: 0,
      cell_deps: [], #it should be the GPC lock script cell.
      inputs: fund_inputs,
      outputs: outputs,
      outputs_data: outputs_data,
      witnesses: fund_witnesses,
    )

    if use_dep_group
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_group_out_point, dep_type: "dep_group")
    else
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_code_out_point, dep_type: "code")
      tx.cell_deps << CKB::Types::CellDep.new(out_point: @api.secp_data_out_point, dep_type: "code")
    end
    #just sign the tx
    tx = tx.sign(@key)

    return tx
  end

  def generate_closing_tx(tx_fund)
    # gpc_code_hash = "0x9bd7e06f3ecf4be0f2fcd2188b23f1b9fcc88e5d4b65a8637b17723bbda3cce8"

    # #gather the GPC
    # gpc_outputs = Array.new()
    # for output in tx_fund.outputs
    #   if output.lock.code_hash == gpc_code_hash
    #     puts "this is the GPC output."
    #     gpc_outputs << output
    #   end
    # end

    # for output in gpc_outputs
    #   gpc_output = CKB::Types::Output.new(
    #     capacity: gpc_capacity,
    #     lock: trg_default_lock, #It should be GPC, but now, just use the trg_default_lock
    #   )
    # end
    # well, just assume that the first cell in the output is GPC output.
    gpc_out_point = CKB::Types::OutPoint.new(
      tx_hash: tx_fund.hash,
      index: 0,
    )
    gpc_input = CKB::Types::Input.new(
      previous_output: out_point,
      since: 0,
    )

    


  end

  def generate_settlement_tx()
  end

  def generate_terminal_tx()
  end
end
