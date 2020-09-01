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
require_relative "../libs/tx_generator.rb"
require_relative "../libs/verification.rb"
$VERBOSE = nil

class Sender_bot
  def initialize(private_key)
    $VERBOSE = nil
    @key = CKB::Key.new(private_key)
    @api = CKB::API::new
    @tx_generator = Tx_generator.new(@key)
    @lock = CKB::Types::Script.new(code_hash: CKB::SystemCodeHash::SECP256K1_BLAKE160_SIGHASH_ALL_TYPE_HASH, args: CKB::Key.blake160(@key.pubkey), hash_type: CKB::ScriptHashType::TYPE)
    @lock_hash = @lock.compute_hash
    @path_to_logger = __dir__ + "/../testing/miscellaneous/logger/"
    @logger = Logger.new(@path_to_logger + "gpc.log")
  end

  def listen(src_port, msg_array)
    puts "listen start"
    server = TCPServer.open(src_port)
    msg_counter = 0
    begin
      loop {
        Thread.start(server.accept) do |client|
          #parse the msg
          begin
            Thread.current.report_on_exception = false
            while (true)
              msg = client.gets
              if msg != nil
                msg = JSON.parse(msg, symbolize_names: true)
                if msg[:type] + 1 == msg_array[msg_counter][:type]
                  client.puts(msg_array[msg_counter].to_json)
                  msg_counter += 1
                end
              end

              if msg_counter >= msg_array.length()
                client.close()
                raise "close"
                break
              end
            end
          rescue => exception
            server.close()
            return true
            # rescue StandardError => error
            #   puts "branch 2"
            #   server.close()
            #   return true
          end
        end
      }
    rescue => exception
    end
  end

  def send_msg(remote_ip, remote_port, msg_array)
    s = TCPSocket.open(remote_ip, remote_port)
    s.puts(msg_array[0].to_json)
    msg_counter = 1
    begin
      timeout(5) do
        while (true)
          msg = s.gets
          if msg != nil
            msg = JSON.parse(s.gets, symbolize_names: true)
            if msg[:type] + 1 == msg_array[msg_counter][:type]
              client.puts(msg_array[msg_counter].to_json)
              msg_counter += 1
            end
            if msg_counter >= msg_array.length()
              puts "I close the session."
              s.close()
              break
            end
          end
        end
      end
    rescue Timeout::Error
      puts "Timed out!"
    end
    s.close()
  end
end
