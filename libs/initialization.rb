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
    doc = { id: 0, privkey: privkey, status: 0, version: 0, ctx: 0, stx: 0, gpc_scirpt_hash: 0, current_block_num: 0 }
    view = coll_sessions.find({ privkey: privkey })
    if view.count_documents() == 0
      coll_sessions.insert_one(doc)
    else
      puts "the initialization has been down."
    end
  end
end
