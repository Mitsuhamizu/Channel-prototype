#!/usr/bin/ruby -w

require "../libs/initialization.rb"
require "../libs/communication.rb"
require "mongo"

def read_command(command_file)
  command = command_file.gets.gsub("\n", "")
  return command
end

if ARGV[0] == "init"
  # init the database.
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

  # read the parameter.
  while true
    command_file = File.open("command.txt", "r")
    type = read_command(command_file)
    if type == "quit"
      break
    elsif type == "send"
      remote_ip = read_command(command_file)
      remote_port = read_command(command_file)
      capacity = read_command(command_file).to_i
      fee = read_command(command_file).to_i
      timeout = read_command(command_file).to_i
      communicator.send_establish_channel(remote_ip, remote_port, capacity, fee, timeout, command_file)
      return 0
    end
  end
end
