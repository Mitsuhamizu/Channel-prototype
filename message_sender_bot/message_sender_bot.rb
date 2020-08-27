#!/usr/bin/ruby -w

require "socket"
require "json"
require "rubygems"
require "bundler/setup"
require "ckb"
require "digest/sha1"
require "mongo"
require "set"
require "timeout"
require_relative "tx_generator.rb"
require_relative "verification.rb"
$VERBOSE = nil

class Sender_bot
  def initialize(private_key)
    $VERBOSE = nil
    @key = CKB::Key.new(private_key)
    @api = CKB::API::new
    @tx_generator = Tx_generator.new(@key)
    @lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: CKB::Key.blake160(@key.pubkey), hash_type: CKB::ScriptHashType::TYPE)
    @lock_hash = @lock.compute_hash

    @logger = Logger.new(__dir__ + "/../testing/files/" + "gpc.log")
  end

  def listen(src_port)
    puts "listen start"
    server = TCPServer.open(src_port)
    loop {
      Thread.start(server.accept) do |client|

        #parse the msg
        while (1)
          msg = client.gets
          msg = JSON.parse(msg, symbolize_names: true) if msg != nil
          ret = process_recv_message(client, msg) if msg != nil
        end
      end
    }
  end

  def send_msg(msg)
    s = TCPSocket.open(remote_ip, remote_port)
    s.puts(msg)
  end
end
