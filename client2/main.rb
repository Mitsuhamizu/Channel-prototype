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

Mongo::Logger.logger.level = Logger::FATAL


if ARGV[0] == "init"
  priv_key = ARGV[1]
  init = Init.new(priv_key)
elsif ARGV[0] == "start"
  # queue = Queue.new
  communicator = Communication.new(ARGV[1])
  while true
    # command = STDIN.gets.chomp
    command_file = File.open("command.txt", "r")
    command = command_file.gets.gsub("\n", "")
    command_split = command.split(" ")
    type = command_split[0]
    if type == "quit"
      break
    elsif type == "listen"
      # t_listen = Thread.new(communicator.listen(command_split[1], command_file))
      communicator.listen(command_split[1], command_file)
      command_file.close
    end
  end
end
