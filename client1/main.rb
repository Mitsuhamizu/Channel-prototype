#!/usr/bin/ruby -w
require "rubygems"
require "bundler/setup"
require "ckb"
require "socket"
require "../libs/initialization.rb"
# require_relative "./libs/initialization.rb"
require "json"
require "thread"
require "../libs/communication.rb"
api = CKB::API::new

if ARGV[0] == "init"
  priv_key = ARGV[1]
  init = Init.new(priv_key)
elsif ARGV[0] == "start"
  communicator = Communication.new(ARGV[1])
  while true
    command_file = File.open("command.txt", "r")
    command = command_file.gets.gsub("\n", "")
    command_split = command.split(" ")
    type = command_split[0]
    if type == "quit"
      break
    elsif type == "send"
      remote_ip = command_split[1]
      remote_port = command_split[2]
      capacity = command_split[3].to_i
      fee = command_split[4].to_i
      # t_send = Thread.new(communicator.send(src_ip, src_pbk, trg_ip, trg_port, capacity, fee))
      communicator.send_establish_channel(remote_ip, remote_port, capacity, fee, command_file)
      # t_send.join
      return 0
    end
  end
end
