require "./miscellaneous/libs/setup.rb"
require "minitest/autorun"
require "mongo"
require "bigdecimal"

Mongo::Logger.logger.level = Logger::FATAL

@path_to_file = __dir__ + "/miscellaneous/files/"
@logger = Logger.new(@path_to_file + "gpc.log")
@client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
@db = @client.database

tests = Gpctest.new("test")
tests.setup()