require_relative "../miscellaneous/libs/gpctest.rb"
require_relative "../../message_sender_bot/message_sender_bot.rb"
require "minitest/autorun"
require "mongo"
require "bigdecimal"

# A is sender and B is listener

Mongo::Logger.logger.level = Logger::FATAL

class Step2 < Minitest::Test
  def establish_step2(file_name)
    begin
      @private_key_A = "0x63d86723e08f0f813a36ce6aa123bb2289d90680ae1e99d4de8cdb334553f24d"
      @private_key_B = "0xd00c06bfd800d27397002dca6fb0993d5ba6399b4238b2f29ee9deb97593d2bc"
      @path_to_file = __dir__ + "/../miscellaneous/files/"
      @logger = Logger.new(@path_to_file + "gpc.log")
      
      @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
      @db = @client.database
      @db.drop()

      data_raw = File.read(__dir__ + "/" + file_name)
      data_json = JSON.parse(data_raw, symbolize_names: true)
      since = "9223372036854775908"

      funding_A = data_json[:A][:amount_fund]
      fee_A = data_json[:A][:fee_fund]
      cells_spent_A = data_json[:A][:spent_cell] == nil ? nil : data_json[:A][:spent_cell].map { |cell| CKB::Types::OutPoint.from_h(cell) }

      msg_2 = data_json[:B][:msg_2]
      ip_B = data_json[:B][:ip]
      listen_port_B = data_json[:B][:port]
      cells_spent_B = data_json[:B][:spent_cell] == nil ? nil : data_json[:B][:spent_cell].map { |cell| CKB::Types::OutPoint.from_h(cell) }

      expect = JSON.parse(data_json[:expect_info], symbolize_names: true) if data_json[:expect_info] != nil

      tests = Gpctest.new("test")
      tests.setup()
      commands = { sender_reply: "yes", recv_reply: "yes", sender_one_way_permission: "yes",
                   payment_reply: "yes", closing_reply: "yes" }
      tests.create_commands_file(commands)
      tests.init_client()

      # spend cells.
      tests.spend_cell("A", cells_spent_A, "ckb")
      tests.spend_cell("B", cells_spent_B, "ckb")

      bot = Sender_bot.new(@private_key_B)
      thread_listen = Thread.new { bot.listen(listen_port_B, [msg_2]) }
      sleep(2)

      tests.send_establishment_request_A(funding_A, fee_A, since, "ckb")

      if expect != nil
        for expect_iter in expect
          result_json = tests.load_json_file(@path_to_file + "result.json").to_json
          assert_match(expect_iter.to_json[1..-2], result_json, "#{expect_iter[1..-2]}")
        end
      end
    rescue => exception
      puts exception
    ensure
      tests.close_all_thread(0, 0, @db)
    end
  end

  def test_success()
    establish_step2("test_step2_success.json")
  end

  def test_gpc_output_modified()
    establish_step2("test_step2_gpc_output_modified.json")
  end

  def test_gpc_output_data_modified()
    establish_step2("test_step2_gpc_output_data_modified.json")
  end

  def test_change_output_modified()
    establish_step2("test_step2_local_change_output_modified.json")
  end

  def test_change_output_data_modified()
    establish_step2("test_step2_local_change_output_data_modified.json")
  end

  def test_capacity_inconsistent()
    establish_step2("test_step2_capacity_inconsistent.json")
  end
end
