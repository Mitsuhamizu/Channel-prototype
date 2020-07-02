#!/usr/bin/ruby
require "rubygems"
require "bundler/setup"
require "ckb"
require "mongo"

# person.name      # => "John Smith"
# person.age       # => 70
# person.address   # => nil

# cell_array = Array.new()
# cell_array << cells
# cell_array << cells
# cells = cell_array.to_json
# puts cells

# cells = JSON.parse(str)
# puts cells
# a="123"
# c=a.delete!("\n")
# puts c.class
Mongo::Logger.logger.level = Logger::FATAL
#
@client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
@db = @client.database
for coll_name in @db.collection_names
    puts "fuck ni 你麻痹"
    puts test
end
@coll_sessions = @db["0x02ce9deada91368642e7b4343dea5046cb7f1553f71cab363daa32aa6fcea17648_session_pool"]
@coll_sessions.find_one_and_update({ id: 0 }, { "$set" => { stx: 0 } })
