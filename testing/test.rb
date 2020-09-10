require "rubygems"
require "bundler/setup"
require "ckb"
require "json"
require "mongo"
Mongo::Logger.logger.level = Logger::FATAL

@api = CKB::API.new

private_key = "0x63d86723e08f0f813a36ce6aa123bb2289d90680ae1e99d4de8cdb334553f24d"
@key = CKB::Key.new(private_key)
@wallet = CKB::Wallet.from_hex(@api, @key.privkey)

tx = @wallet.generate_tx(@wallet.address, CKB::Utils.byte_to_shannon(100), fee: 5000)
tx.cell_deps << tx.cell_deps[0]
tx = tx.sign(@wallet.key)
@api.send_transaction(tx)