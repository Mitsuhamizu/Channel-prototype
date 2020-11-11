require "mongo"
Mongo::Logger.logger.level = Logger::FATAL
@client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
@db = @client.database
@db.drop()

@path_to_cli = __dir__ + "/GPC.rb"
@private_key_A = "0x63d86723e08f0f813a36ce6aa123bb2289d90680ae1e99d4de8cdb334553f24d"
@private_key_B = "0x85ce75a6b678c6930a4f0938588f0240784971bb03632f1a2f1b25102b7cf5f0"
system ("ruby " + @path_to_cli + " init #{@private_key_A}")
system ("ruby " + @path_to_cli + " init #{@private_key_B}")
