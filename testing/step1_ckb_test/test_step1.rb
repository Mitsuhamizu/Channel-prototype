require_relative "../miscellaneous/libs/gpctest.rb"
require_relative "../../message_sender_bot/message_sender_bot.rb"
require "minitest/autorun"
require "mongo"
require "bigdecimal"

# A is sender and B is listener

Mongo::Logger.logger.level = Logger::FATAL

class Making_payment_udt < Minitest::Test
  def establish_step1(file_name)
    begin
      @private_key_A = "0x63d86723e08f0f813a36ce6aa123bb2289d90680ae1e99d4de8cdb334553f24d"
      @private_key_B = "0xd00c06bfd800d27397002dca6fb0993d5ba6399b4238b2f29ee9deb97593d2bc"
      @path_to_file = __dir__ + "/../miscellaneous/files/"
      @logger = Logger.new(@path_to_file + "gpc.log")
      @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
      @db = @client.database

      data_raw = File.read(__dir__ + "/" + file_name)
      data_json = JSON.parse(data_raw, symbolize_names: true)

      msg_1 = data_json[:A][:msg_1]
      remote_ip = data_json[:A][:remote_ip]
      remote_port = data_json[:A][:remote_port]
      funding_B = data_json[:B][:amount]
      fee_B = data_json[:B][:fee]

      tests = Gpctest.new("test")
      tests.setup()
      commands = { sender_reply: "yes", recv_reply: "yes", recv_fund: funding_B,
                   recv_fund_fee: fee_B, sender_one_way_permission: "yes",
                   payment_reply: "yes", closing_reply: "yes" }
      tests.create_commands_file(commands)
      tests.init_client()
      @monitor_B, @listener_B = tests.start_listen_monitor_B()

      # Since we test step 1, we needs to act as A.
      sender = Sender_bot.new(@private_key_A)
      sender.send_msg(remote_ip, remote_port, msg_1.to_json)
      sleep(2)
    rescue => exception
      puts exception
    ensure
      tests.close_all_thread(0, @monitor_B, @db)
    end
  end

  def test_success()
    establish_step1("test_step1_success.json")
  end
end
