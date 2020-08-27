require "rubygems"
require "bundler/setup"
require "ckb"
require "json"
require "mongo"
Mongo::Logger.logger.level = Logger::FATAL

@api = CKB::API.new

private_key = "0xd986d7bf901e50368cbe565f239c224934cd554805357338abcef177efadc08d"
@key = CKB::Key.new(private_key)
@wallet = CKB::Wallet.from_hex(@api, @key.privkey)

tx = @wallet.generate_tx(@wallet.address, CKB::Utils.byte_to_shannon(100), fee: 5000)
# puts @wallet.get_balance
previous_tx_hash = tx.inputs[0].previous_output.tx_hash
previous_tx = @api.get_transaction(previous_tx_hash)
previous_block = @api.get_block(previous_tx.tx_status.block_hash)
previous_block_height = previous_block.header.number

current_height = @api.get_tip_block_number()

# height_diff = current_height - previous_block_height + 100
height_diff = 100

since_test = [height_diff].pack("Q>")
since_test[0] = [128].pack("C")
since_test = since_test.unpack("Q>")[0]

puts since_test
# tx.inputs[0].since = since_test

# tx = tx.sign(@wallet.key)

# @api.send_transaction(tx)
