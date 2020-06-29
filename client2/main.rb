#!/usr/bin/ruby -w
require "rubygems"
require "bundler/setup"
require "ckb"
require "socket"
require "../libs/initialization.rb"
require "json"
require "thread"
require "../libs/communication.rb"
require "mongo"

def read_command(command_file)
  command = command_file.gets.gsub("\n", "")
  return command
end

Mongo::Logger.logger.level = Logger::FATAL

if ARGV[0] == "init"
  private_key = ARGV[1]
  init = Init.new(private_key)
elsif ARGV[0] == "start"

  # init the communicator.
  pubkey = ARGV[1]
  @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
  @db = @client.database
  @coll_sessions = @db[pubkey + "_session_pool"]
  private_key = @coll_sessions.find({ id: 0 }).first[:privkey]
  communicator = Communication.new(private_key)

  while true
    # command = STDIN.gets.chomp
    command_file = File.open("command.txt", "r")
    type = read_command(command_file)
    port = read_command(command_file)
    if type == "quit"
      break
    elsif type == "listen"
      # t_listen = Thread.new(communicator.listen(command_split[1], command_file))
      communicator.listen(port, command_file)
      command_file.close
    end
  end
end
