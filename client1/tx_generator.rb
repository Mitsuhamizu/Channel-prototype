#!/usr/bin/ruby -w

require "rubygems"
require "bundler/setup"
require "ckb"

class Tx_generator
  def initialize(key)
    @key = key
  end

  def generate_fund_tx(capacity, target_address, cells_of_opposite)
    parsed_address = AddressParser.new(target_address).parse
    lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: CKB::Key.blake160(@key.pubkey), hash_type: CKB::ScriptHashType::TYPE)
  end

  def generate_closing_tx()
  end

  def geenrate_settlement_tx()
  end

  def generate_terminal_tx()
  end
end
