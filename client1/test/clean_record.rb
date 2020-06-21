require "rubygems"
require "bundler/setup"
require "ckb"
require "mongo"

client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
db = client.database
coll_session1 = db["0x039b64d0f58e2cc28d4579fac2ae571e118af0e4945928d699519aecb20ec9a793_session_pool"]
coll_session2 = db["0x02ce9deada91368642e7b4343dea5046cb7f1553f71cab363daa32aa6fcea17648_session_pool"]

coll_session1.delete_many({ gpc_scirpt_hash: "0x349b6952f741b6ed130a606670446e83b02e997f752a75e3d88c15eca43fffd7" })
coll_session2.delete_many({ gpc_scirpt_hash: "0x349b6952f741b6ed130a606670446e83b02e997f752a75e3d88c15eca43fffd7" })