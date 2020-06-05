#!/usr/bin/ruby -w
require 'rubygems'
require 'bundler/setup'
require 'ckb'
require 'socket'


api=CKB::API::new
puts api.get_tip_block_number

