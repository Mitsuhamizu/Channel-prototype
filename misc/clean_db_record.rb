require "mongo"

client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
db = client.database
coll_session1 = db["0x039b64d0f58e2cc28d4579fac2ae571e118af0e4945928d699519aecb20ec9a793_session_pool"]
coll_session2 = db["0x02ce9deada91368642e7b4343dea5046cb7f1553f71cab363daa32aa6fcea17648_session_pool"]

script_hash = "0x6e000000100000003000000031000000f3bdd1340f8db1fa67c3e87dad9ee9fe39b3cecc5afcfb380805245184bbc36f00390000000064000000000000000000000000000000c6a8ae902ac272ea0ec6378f7ab8648f76979ce296a11bf182b0e952f6fcc685b43ae50e13951b78"
coll_session1.delete_many({ gpc_script: script_hash })
coll_session2.delete_many({ gpc_script: script_hash })
