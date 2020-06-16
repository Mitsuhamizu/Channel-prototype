#!/usr/bin/ruby
require "rubygems"
require "bundler/setup"
require "ckb"
require "mongo"

class Init
  def initialize(prk)

    #link the mongodb
    client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    db = client.database
    pool_name = pbk + "_session_pool"
    coll_sessions = db[pool_name]
    doc = { id: 0, src_prvate_key: prk, trg_public_key: "0x0", status: "init" }
    coll_sessions.insert_one(doc)
    # db.command(:eval => 'db.createCollection(pbk + "session_pool")')

    # #init the wallet
    # api = CKB::API.new
    # wallet = CKB::Wallet.from_hex(api, "0x" + prk)
    # cells = wallet.get_unspent_cells
    # cell_group = Array.new()
    # for cell in cells
    #   h = { :"capacity" => cell.capacity, :"index" => cell.out_point.index, :"tx_hash" => cell.out_point.tx_hash }
    #   cell_group << h
    # end
    # doc = { pbk: pbk, prk: prk, lock_arg: lock_arg, lock_hash: lock_hash, cells: cell_group }
    # # insert the record
    # view = coll_info.find({ pbk: pbk })
    # if view.count_documents() == 0
    #   result = coll_info.insert_one(doc)
    # end
  end
end