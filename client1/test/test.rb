#!/usr/bin/ruby
require "rubygems"
require "bundler/setup"
require "ckb"
require "mongo"

# person.name      # => "John Smith"
# person.age       # => 70
# person.address   # => nil

# cell_array = Array.new()
# cell_array << cells
# cell_array << cells
# cells = cell_array.to_json
# puts cells

# cells = JSON.parse(str)
# puts cells
# a="123"
# c=a.delete!("\n")
# puts c.class
privkey = "d986d7bf901e50368cbe565f239c224934cd554805357338abcef177efadc08d"
client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
db = client.database
pubkey = CKB::Key.pubkey("0x" + privkey)
pool_name = pubkey + "_session_pool"
coll_sessions = db[pool_name]
test = coll_sessions.find({ id: 0 }).first
puts test[:ctx]
puts "11"
# coll_sessions.find_one_and_update({ id: 0 }, { "$set" => { version: { type: 1 } } }, :return_document => :after)
# coll_sessions.find_one_and_update({ id: 0 }, { "$unset" => { test_filed: "" } }, :return_document => :after)
