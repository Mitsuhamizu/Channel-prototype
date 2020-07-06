require "mongo"

client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
db = client.database
coll_session1 = db["0x039b64d0f58e2cc28d4579fac2ae571e118af0e4945928d699519aecb20ec9a793_session_pool"]
coll_session2 = db["0x02ce9deada91368642e7b4343dea5046cb7f1553f71cab363daa32aa6fcea17648_session_pool"]

script_hash = "0x7e0000001000000030000000310000006d44e8e6ebc76927a48b581a0fb84576f784053ae9b53b8c2a20deafca5c4b7b0049000000bb15840434d6730640c5842d247c83110064000000000000800000000000000000c6a8ae902ac272ea0ec6378f7ab8648f76979ce296a11bf182b0e952f6fcc685b43ae50e13951b78"
coll_session1.delete_many({ gpc_script: script_hash })
coll_session2.delete_many({ gpc_script: script_hash })