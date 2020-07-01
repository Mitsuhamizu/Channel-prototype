require "../libs/chain_monitor.rb"
require "../libs/tx_generator.rb"
Mongo::Logger.logger.level = Logger::FATAL

private_key = "0x82dede298f916ced53bf5aa87cea8a7e44e8898eaedcff96606579f7bf84d99d"

monitor = Minotor.new(private_key)

monitor.monitor_chain()
