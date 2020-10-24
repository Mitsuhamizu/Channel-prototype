require_relative "../libs/initialization.rb"
require_relative "../libs/communication.rb"
require_relative "../libs/chain_monitor.rb"
require "mongo"
require "thor"
require "ckb"
Mongo::Logger.logger.level = Logger::FATAL

def pubkey_to_privkey(pubkey)
  @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
  @db = @client.database
  @coll_sessions = @db[pubkey + "_session_pool"]
  private_key = @coll_sessions.find({ id: 0 }).first[:privkey]
  return private_key
end

def hash_to_info(info_h)
  info_h[:outputs] = info_h[:outputs].map { |output| CKB::Types::Output.from_h(output) }
  return info_h
end

def decoder(data)
  result = CKB::Utils.hex_to_bin(data).unpack("Q<")[0]
  return result.to_i
end

def get_balance(pubkey)
  @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
  @db = @client.database
  @coll_sessions = @db[pubkey + "_session_pool"]

  balance = {}
  # iterate all record.
  view = @coll_sessions.find { }
  view.each do |doc|
    if doc[:id] != 0
      local_pubkey = doc[:local_pubkey]
      remote_pubkey = doc[:remote_pubkey]
      balance[doc[:id]] = {}
      stx = hash_to_info(JSON.parse(doc[:stx_info], symbolize_names: true))
      for index in (0..stx[:outputs].length - 1)
        output = stx[:outputs][index]
        output_data = stx[:outputs_data][index]
        ckb = output.capacity - output.calculate_min_capacity(output_data)
        udt = decoder(stx[:outputs_data][index])
        if local_pubkey == output.lock.args
          balance[doc[:id]][:local] = { ckb: ckb, udt: udt }
        elsif remote_pubkey == output.lock.args
          balance[doc[:id]][:remote] = { ckb: ckb, udt: udt }
        end
      end
      # puts doc[:nounce] - 1
      balance[doc[:id]][:payments] = doc[:nounce] - 1
    end
  end

  return balance
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
        --port <port> \
        --funding <fundings>",
       "Send the chanenl establishment request."
  option :pubkey, :required => true
  option :ip, :required => true
  option :port, :required => true
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

    communicator.send_establish_channel(options[:ip], options[:port], fundings)
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

  # --------------close the channel unilateral
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

  # --------------send the closing request about bilateral closing.
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

  # --------------list the channel.
  desc "list_channel --pubkey <public key>", "List channels"

  option :pubkey, :required => true

  def list_channel()
    puts "\n"
    balance = get_balance(options[:pubkey])
    for id in balance.keys()
      puts "channel #{id}, with #{balance[id][:payments]} payments."
      puts " local's ckb: #{balance[id][:local][:ckb]}, local's udt #{balance[id][:local][:udt]}."
      puts " remote's ckb: #{balance[id][:remote][:ckb]}, local's udt #{balance[id][:remote][:udt]}.\n\n"
    end
  end

  # --------------exchange the ckb and channel.
  desc "make_exchange_ckb_to_udt --pubkey <public key> --ip <ip> --port <port> --id <id> --quantity <quantity>", "use ckb for udt."
  option :pubkey, :required => true
  option :ip, :required => true
  option :port, :required => true
  option :id, :required => true
  option :quantity, :required => true

  def make_exchange_ckb_to_udt()
    private_key = pubkey_to_privkey(options[:pubkey])
    quantity = options[:quantity]
    communicator = Communication.new(private_key)

    communicator.make_exchange(options[:ip], options[:port], options[:id], "ckb2udt", quantity.to_i)
  end

  # --------------send_msg by payment channel.
  desc "send_tg_msg --pubkey <public key> --ip <ip> --port <port> --id <id>", "pay tg robot and he will send msg for you."

  option :pubkey, :required => true
  option :port, :required => true
  option :ip, :required => true
  option :id, :required => true

  def send_tg_msg()
    private_key = pubkey_to_privkey(options[:pubkey])

    puts "Tell me what you want to say."
    tg_msg = STDIN.gets.chomp
    tg_msg_len = tg_msg.length

    balance = get_balance(options[:pubkey])

    udt_required = tg_msg_len * 1
    udt_actual = balance[options[:id]][:local][:udt]

    if udt_actual < udt_actual
      puts "you do not have enough udt, please exchange it with ckb first."
    end

    # construct the payment.
    payment = { udt: udt_required }
    communicator = Communication.new(private_key)
    communicator.send_payments(options[:ip], options[:port], options[:id], payment, tg_msg)
  end
end

$VERBOSE = nil
GPCCLI.start(ARGV)
