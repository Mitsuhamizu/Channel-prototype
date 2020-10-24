require_relative "../libs/initialization.rb"
require_relative "../libs/communication.rb"
require_relative "../libs/chain_monitor.rb"
require "mongo"
require "thor"
Mongo::Logger.logger.level = Logger::FATAL

def pubkey_to_privkey(pubkey)
  @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
  @db = @client.database
  @coll_sessions = @db[pubkey + "_session_pool"]
  private_key = @coll_sessions.find({ id: 0 }).first[:privkey]
  return private_key
end

class GPCCLI < Thor
  desc "init <private-key>", "Init with the private key."
  # --------------init
  def init(private_key)
    if ARGV.length != 2
      puts "The arg number is not right."
      return false
    end
    Init.new(private_key)
  end

  # --------------listen
  desc "listen <pubkey> <port>", "Listen the port."

  def listen(pubkey, port = 1000)
    if ARGV.length != 3
      puts "The arg number is not right."
      return false
    end
    private_key = pubkey_to_privkey(pubkey)
    communicator = Communication.new(private_key)
    communicator.listen(port)
  end

  # --------------establishment
  desc "send_establishment_request --pubkey <public key> --ip <ip> \
        --port <port> --fee <fee in shannon> --since <since> \
        --funding <fundings>",
       "Send the chanenl establishment request."
  option :pubkey, :required => true
  option :ip, :required => true
  option :port, :required => true
  option :fee, :required => true
  option :since, :required => true
  option :funding, :required => true, :type => :hash

  def send_establishment_request()
    private_key = pubkey_to_privkey(options[:pubkey])
    communicator = Communication.new(private_key)
    fundings = options[:funding]

    fundings = fundings.map() { |key, value| [key.to_sym, value] }.to_h

    for asset_type in fundings.keys()
      fundings[asset_type] = asset_type == :ckb ? CKB::Utils.byte_to_shannon(BigDecimal(fundings[asset_type])) : BigDecimal(fundings[asset_type])
      fundings[asset_type] = fundings[asset_type].to_i
    end

    communicator.send_establish_channel(options[:ip], options[:port], fundings, options[:fee].to_i,
                                        options[:since])
  end

  # --------------make payments
  desc "make_payment --pubkey <public key> --ip <ip> --port <port> --id <id> --payment <payment>", "Make payments"

  option :pubkey, :required => true
  option :ip, :required => true
  option :port, :required => true
  option :id, :required => true
  option :payment, :required => true, :type => :hash

  def make_payment()
    @path_to_file = __dir__ + "/../../miscellaneous/files/"
    private_key = pubkey_to_privkey(options[:pubkey])
    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database
    @coll_sessions = @db[options[:pubkey] + "_session_pool"]

    payment = options[:payment]
    payment = payment.map() { |key, value| [key.to_sym, value] }.to_h

    for asset_type in payment.keys()
      payment[asset_type] = asset_type == :ckb ? CKB::Utils.byte_to_shannon(BigDecimal(payment[asset_type])) : BigDecimal(payment[asset_type])
      payment[asset_type] = payment[asset_type].to_i
    end

    communicator = Communication.new(private_key)
    communicator.send_payments(options[:ip], options[:port], options[:id], payment)
  end

  # --------------monitor
  desc "monitor <public key>", "Monitor the chain."

  def monitor(pubkey)
    private_key = pubkey_to_privkey(pubkey)
    monitor = Minotor.new(private_key)
    thread_monitor_chain = Thread.start { monitor.monitor_chain() }
    thread_monitor_cell = Thread.start { monitor.monitor_pending_cells() }
    thread_monitor_chain.join
    thread_monitor_cell.join
  end

  desc "closing_channel <pubkey> <id>", "closing the channel with id."

  def closing_channel(pubkey, id)
    private_key = pubkey_to_privkey(pubkey)
    monitor = Minotor.new(private_key)

    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database
    @coll_sessions = @db[pubkey + "_session_pool"]

    doc = @coll_sessions.find({ id: id }).first
    monitor.send_tx(doc, "closing")
  end

  desc "send_closing_request --pubkey <public key> --ip <ip> --port <port> --id <id> --fee ", "The good case, bilateral closing."

  option :pubkey, :required => true
  option :ip, :required => true
  option :port, :required => true
  option :id, :required => true
  option :fee

  def send_closing_request()
    private_key = pubkey_to_privkey(options[:pubkey])
    communicator = Communication.new(private_key)
    communicator.send_closing_request(options[:ip], options[:port], options[:id], options[:fee].to_i) if options[:fee]
    communicator.send_closing_request(options[:ip], options[:port], options[:id]) if !options[:fee]
  end

end

$VERBOSE = nil
GPCCLI.start(ARGV)
