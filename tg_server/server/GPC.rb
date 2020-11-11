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

def load_config()
  data_raw = File.read("config.json")
  data_json = JSON.parse(data_raw, symbolize_names: true)
  return data_json
end

def load_pubkey(options)
  pubkey = nil
  config = load_config()
  if options[:pubkey] != nil
    pubkey = options[:pubkey]
  elsif config[:pubkey] != nil
    pubkey = config[:pubkey]
  end

  if pubkey == nil
    puts "Please check the config.json."
  end

  return pubkey
end

def load_id(options)
  id = nil
  config = load_config()
  if options[:id] != nil
    id = options[:id]
  elsif config[:id] != nil
    id = config[:id]
  end

  if id == nil
    puts "Please init the config.json or provide the id with --id."
  end

  return id
end

def load_ip_port(options, pubkey, id)
  @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
  @db = @client.database
  @coll_sessions = @db[pubkey + "_session_pool"]

  ip_info = nil

  if id == ""
    puts "please set the channel id firstly."
    return false
  end
  view = @coll_sessions.find { }
  view.each do |doc|
    if doc[:id] == id
      ip_info = { ip: doc[:remote_ip], port: doc[:remote_port] }
    end
  end

  if options[:ip] != nil && options[:port] != nil
    ip_info = { ip: options[:ip], port: options[:port] }
  end

  if ip_info == nil
    puts "Please init the config.json or provide the ip and port with --ip and --port."
  end

  return ip_info
end

def load_pubkey_id(options)
  pubkey = load_pubkey(options)
  id = load_id(options)

  if pubkey == nil
    return false
  end

  if id == nil
    return false
  end

  return { pubkey: pubkey, id: id }
end

def load_pubkey_id_ip(options)
  # load pubkey and id
  channel_info = load_pubkey_id(options)
  return false if !channel_info

  # load ip info
  ip_info = load_ip_port(options, channel_info[:pubkey], channel_info[:id])
  return false if !ip_info

  result = channel_info.merge(ip_info)
  return result
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
      balance[doc[:id]][:stage] = doc[:stage]
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

    # add the pubkey to the config.json
    data_hash = {}
    if File.file?("config.json")
      data_raw = File.read("config.json")
      data_hash = JSON.parse(data_raw, symbolize_names: true)
    end
    pubkey = { pubkey: CKB::Key.pubkey(private_key) }
    data_hash = data_hash.merge(pubkey)
    data_json = data_hash.to_json
    file = File.new("config.json", "w")
    file.syswrite(data_json)
  end

  # --------------establishment
  desc "send_establishment_request [--pubkey public key] [--ip ip] \
        [--port port] \
        <--funding fundings>",
       "Send the chanenl establishment request."
  option :pubkey
  option :ip
  option :port
  option :funding, :required => true, :type => :hash

  def send_establishment_request()
    pubkey = load_pubkey(options)
    if pubkey == nil
      puts "Please init the config.json or provide the pubkey with --pubkey."
      return false
    end

    private_key = pubkey_to_privkey(pubkey)
    communicator = Communication.new(private_key)
    fundings = options[:funding]

    fundings = fundings.map() { |key, value| [key.to_sym, value] }.to_h

    for asset_type in fundings.keys()
      fundings[asset_type] = asset_type == :ckb ? CKB::Utils.byte_to_shannon(BigDecimal(fundings[asset_type])) : BigDecimal(fundings[asset_type])
      fundings[asset_type] = fundings[asset_type].to_i
    end

    config = load_config()
    communicator.send_establish_channel(config[:robot_ip], config[:robot_port], fundings)
  end

  # --------------listen
  desc "listen --pubkey <pubkey> --port <port>", "Listen the port."

  option :pubkey, :required => true
  option :port, :required => true

  def listen()
    pubkey = options[:pubkey]
    port = options[:port]
    private_key = pubkey_to_privkey(pubkey)
    communicator = Communication.new(private_key)
    communicator.listen(port)
  end

  # --------------monitor
  desc "monitor [--pubkey public key]", "Monitor the chain."

  option :pubkey

  def monitor()
    pubkey = load_pubkey(options)
    if pubkey == nil
      puts "Please init the config.json or provide the pubkey with --pubkey."
      return false
    end

    private_key = pubkey_to_privkey(pubkey)
    monitor = Minotor.new(private_key)
    thread_monitor_chain = Thread.start { monitor.monitor_chain() }
    thread_monitor_cell = Thread.start { monitor.monitor_pending_cells() }
    thread_monitor_msg = Thread.start { monitor.monitor_tg_group() }
    thread_monitor_pinned_msg = Thread.start { monitor.monitor_pinned_msg() }
    thread_monitor_chain.join
    thread_monitor_cell.join
    thread_monitor_msg.join
    thread_monitor_pinned_msg.join
  end

  # --------------close the channel unilateral
  desc "close_channel [--pubkey pubkey] [--id channel id]", "close the channel with id."
  option :pubkey
  option :id

  def close_channel()
    # load pubkey and id.
    channel_info = load_pubkey_id(options)
    return false if !channel_info
    pubkey = channel_info[:pubkey]
    id = channel_info[:id]

    private_key = pubkey_to_privkey(pubkey)
    monitor = Minotor.new(private_key)

    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database
    @coll_sessions = @db[pubkey + "_session_pool"]

    doc = @coll_sessions.find({ id: id }).first
    monitor.send_tx(doc, "closing")
  end

  # --------------send the closing request about bilateral closing.
  desc "send_closing_request [--pubkey public key] [--ip ip] [--port port] [--id id] [--fee fee] ", "The good case, bilateral closing."

  option :pubkey
  option :ip
  option :port
  option :id
  option :fee

  def send_closing_request()
    info = load_pubkey_id_ip(options)
    return false if !info

    private_key = pubkey_to_privkey(info[:pubkey])
    communicator = Communication.new(private_key)
    communicator.send_closing_request(info[:ip], info[:port], info[:id], options[:fee].to_i) if options[:fee]
    communicator.send_closing_request(info[:ip], info[:port], info[:id]) if !options[:fee]
  end

  # --------------list the channel.
  desc "list_channel [--pubkey public key]", "List channels"

  option :pubkey

  def list_channel()
    pubkey = load_pubkey(options)
    return false if !pubkey

    balance = get_balance(pubkey)
    for id in balance.keys()
      puts "channel #{id}, with #{balance[id][:payments]} payments and stage is #{balance[id][:stage]}"
      puts " local's ckb: #{balance[id][:local][:ckb] / 10 ** 8} ckbytes, local's udt #{balance[id][:local][:udt]}."
      puts " remote's ckb: #{balance[id][:remote][:ckb] / 10 ** 8} ckbytes, remote's udt #{balance[id][:remote][:udt]}.\n\n"
    end
  end

  # --------------exchange the ckb and channel.
  desc "make_exchange_ckb_to_udt [--pubkey public key] [--ip ip] [--port port] [--id id] <--quantity quantity>", "use ckb for udt."
  option :pubkey
  option :ip
  option :port
  option :id
  option :quantity, :required => true

  def make_exchange_ckb_to_udt()
    info = load_pubkey_id_ip(options)
    return false if !info

    private_key = pubkey_to_privkey(info[:pubkey])
    quantity = options[:quantity]
    communicator = Communication.new(private_key)
    communicator.make_exchange(info[:ip], info[:port], info[:id], "ckb2udt", quantity.to_i)
  end

  # --------------exchange the udt and channel.
  desc "make_exchange_ckb_to_udt [--pubkey public key] [--ip ip] [--port port] [--id id] <--quantity quantity>", "use udt for ckb."

  option :pubkey
  option :ip
  option :port
  option :id
  option :quantity, :required => true

  def make_exchange_udt_to_ckb()
    info = load_pubkey_id_ip(options)
    return false if !info

    private_key = pubkey_to_privkey(info[:pubkey])
    quantity = options[:quantity]
    communicator = Communication.new(private_key)

    communicator.make_exchange(info[:ip], info[:port], info[:id], "udt2ckb", quantity.to_i)
  end

  # --------------send_msg by payment channel.
  desc "send_tg_msg --pubkey <public key> --ip <ip> --port <port> --id <id>", "pay tg robot and he will send msg for you."

  option :pubkey
  option :port
  option :ip
  option :id

  def send_tg_msg()
    info = load_pubkey_id_ip(options)
    return false if !info

    private_key = pubkey_to_privkey(info[:pubkey])

    puts "Tell me what you want to say."
    tg_msg = STDIN.gets.chomp
    tg_msg_len = tg_msg.length

    balance = get_balance(info[:pubkey])

    udt_required = tg_msg_len * 1
    udt_actual = balance[info[:id]][:local][:udt]

    if udt_actual < udt_required
      puts "you do not have enough udt, please exchange it with ckb first."
    end

    # construct the payment.
    payment = { udt: udt_required }
    communicator = Communication.new(private_key)
    communicator.send_payments(info[:ip], info[:port], info[:id], payment, tg_msg)
  end

  # --------------send_msg by payment channel.
  desc "use_pubkey --pubkey <public key>", "denote the pubkey you want to use."

  option :pubkey, :required => true

  def use_pubkey()
    data_hash = {}
    if File.file?("config.json")
      data_raw = File.read("config.json")
      data_hash = JSON.parse(data_raw, symbolize_names: true)
    end
    pubkey = { pubkey: options[:pubkey] }
    data_hash = data_hash.merge(pubkey)
    data_json = data_hash.to_json
    file = File.new("config.json", "w")
    file.syswrite(data_json)
  end

  desc "use_channel <--id channel id>", "denote the pubkey you want to use."

  option :id, :required => true

  def use_channel()
    data_hash = {}
    if File.file?("config.json")
      data_raw = File.read("config.json")
      data_hash = JSON.parse(data_raw, symbolize_names: true)
    end
    id = { id: options[:id] }
    data_hash = data_hash.merge(id)
    data_json = data_hash.to_json
    file = File.new("config.json", "w")
    file.syswrite(data_json)
  end
end

$VERBOSE = nil
GPCCLI.start(ARGV)
