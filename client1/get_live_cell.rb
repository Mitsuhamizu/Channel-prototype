#!/usr/bin/ruby -w
require "rubygems"
require "bundler/setup"
require "ckb"

api = CKB::API::new

pub_key = ""
pri_key = ""
lock_hash = ""

lock_hash = "0xa8518131344d1cd10c3b43838e5eb9f733c98b5aa63f18af7b220759f35844aa"
# lock_hash = "0x5e1e5fcfd10989b14f31436dd5fb875eb0d2940bd17e2e65cb76688608fa51b4"
# lock_hash = "0x32e555f3ff8e135cece1351a6a2971518392c1e30375c1e006ad0ce8eac07947"

api.index_lock_hash(lock_hash)

cell1 = api.get_live_cells_by_lock_hash(lock_hash, "0x0", "0x32")
puts cell1
cell2 = api.get_live_cells_by_lock_hash(lock_hash, "0x0", "0x51")
puts cell2
