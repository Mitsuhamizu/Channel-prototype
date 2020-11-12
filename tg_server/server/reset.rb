require "mongo"
Mongo::Logger.logger.level = Logger::FATAL
@client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
@db = @client.database
@coll_sessions = @db["0x03babbec0930eb604d89520055f45d7e33e0f6c34e52a97e665c7fe52896044602_session_pool"]
@coll_sessions.find_one_and_delete(id: "0459ff7946cf14a7db26d9f6f4095896")
