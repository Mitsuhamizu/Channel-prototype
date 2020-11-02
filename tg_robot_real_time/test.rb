require "mongo"

Mongo::Logger.logger.level = Logger::FATAL

@client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
@db = @client.database
@group_id = -1001372639358
@msg_coll = @db[@group_id.to_s + "_msg_pool"]
text = "123"
view = @msg_coll.find({ text: text })
records = []
view.each do |doc|
  records << "'#{doc[:text]}' sent by #{doc[:sender]} in #{doc[:group]} at #{Time.at(doc[:date]).to_datetime}, the id of this msg is #{doc[:id]}."
end
puts records
