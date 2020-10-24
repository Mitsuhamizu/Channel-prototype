require "rubygems"
require "bundler/setup"
require "minitest/autorun"
require "mongo"
require "json"
require "ckb"
require "logger"

def deploy_contract(wallet, data)
  code_hash = CKB::Blake2b.hexdigest(data)
  data_size = data.bytesize
  tx_hash = wallet.send_capacity(wallet.address, CKB::Utils.byte_to_shannon(data_size + 10000), CKB::Utils.bin_to_hex(data), fee: 10 ** 6)
  return [code_hash, tx_hash]
end

@api = CKB::API::new
@private_key = "0x85ce75a6b678c6930a4f0938588f0240784971bb03632f1a2f1b25102b7cf5f0"
@wallet_A = CKB::Wallet.from_hex(@api, @private_key)

@path_to_binary = __dir__ + "/../binary/"
gpc_data = File.read(@path_to_binary + "gpc")
gpc_code_hash, gpc_tx_hash = deploy_contract(gpc_data)
