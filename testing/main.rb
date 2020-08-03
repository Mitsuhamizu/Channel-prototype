require "./libs/gpctest.rb"
require "mongo"

Mongo::Logger.logger.level = Logger::FATAL
$VERBOSE = nil

tests = Gpctest.new("test")
tests.test1()
# tests.test2()
# tests.test3()
# tests.test4()
# tests.test5()
