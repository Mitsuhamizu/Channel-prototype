require "../libs/chain_monitor.rb"
require "../libs/tx_generator.rb"
Mongo::Logger.logger.level = Logger::FATAL

# just copy the collection

private_key = "0xd986d7bf901e50368cbe565f239c224934cd554805357338abcef177efadc08d"

monitor = Minotor.new(private_key)

monitor.monitor_chain()