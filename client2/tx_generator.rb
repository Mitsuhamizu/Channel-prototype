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
      cell_deps: [],
      inputs: fund_inputs,
      outputs: outputs,
      outputs_data: outputs_data,
      witnesses: fund_witnesses,
    )
    
    #need GPC lock, but now, just uses the default one.

  end

  # def generate_closing_tx()
  # end

  # def geenrate_settlement_tx()
  # end

  # def generate_terminal_tx()
  # end
end
