require "finite_machine"
require "mongo"

Mongo::Logger.logger.level = Logger::FATAL

@client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
@db = @client.database
@coll_sessions = @db["0x02ce9deada91368642e7b4343dea5046cb7f1553f71cab363daa32aa6fcea17648_session_pool"]

class GPC < FiniteMachine::Definition
  initial :none

  event :init, [:none] => :one
end
