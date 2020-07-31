require "./libs/gpctest.rb"
require "mongo"

Mongo::Logger.logger.level = Logger::FATAL
$VERBOSE = nil

tests = Gpctest.new("test")
tests.test1()
