#!/usr/bin/ruby
require "rubygems"
require "bundler/setup"
require "ckb"
require "mongo"

class Init
  def initialize(privkey)
    client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    db = client.database
    pubkey = CKB::Key.pubkey(privkey)
    pool_name = pubkey + "_session_pool"
    coll_sessions = db[pool_name]
    doc = { id: 0, privkey: privkey, current_block_num: 0 }
    view = coll_sessions.find({ id: 0 })

    if view.count_documents() == 0
      coll_sessions.insert_one(doc)
    else
      puts "the initialization has been down."
    end
  end
end
