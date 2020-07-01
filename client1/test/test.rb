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
privkey = "82dede298f916ced53bf5aa87cea8a7e44e8898eaedcff96606579f7bf84d99d"
@client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
@db = @client.database
# pubkey = CKB::Key.pubkey("0x" + privkey)
@key = CKB::Key.new("0x" + privkey)
pubkey = @key.pubkey
# pool_name = pubkey + "_session_pool"


coll_sessions = @db[pubkey + "_session_pool"]
test = coll_sessions.find({ id: 0 }).first
puts test[:id]
