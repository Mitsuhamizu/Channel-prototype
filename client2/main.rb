#!/usr/bin/ruby -w
require "rubygems"
require "bundler/setup"
require "ckb"
require "socket"
require "./initialization.rb"
require "json"
require "thread"
require "./communication.rb"
api = CKB::API::new

if ARGV[0] == "init"
  pub_key = ARGV[1]
  pri_key = ARGV[2]
  lock_arg = ARGV[3]
  lock_hash = ARGV[4]
  init = Init.new(pub_key, pri_key, lock_arg, lock_hash)
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
      t_listen = Thread.new(communicator.listen(command_split[1], command_file))
      command_file.close
      t_listen.join
    elsif type == "send"
      src_ip = command_split[1]
      src_pbk = command_split[2]
      trg_ip = command_split[3]
      trg_port = command_split[4]
      capacity = command_split[5]
      t_send = Thread.new(communicator.send(src_ip, src_pbk, trg_ip, trg_port, capacity))
      t_send.join
    end
  end
  # Listen.new(ARGV[2])
  # Send.new(ARGV[2], ARGV[3], ARGV[4], ARGV[5], ARGV[6])
end
