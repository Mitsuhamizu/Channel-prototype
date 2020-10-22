require "./miscellaneous/libs/gpctest.rb"
require "minitest/autorun"
require "mongo"
require "bigdecimal"

Mongo::Logger.logger.level = Logger::FATAL

class Test_happy < Minitest::Test
  def simulation(file_name)
    @path_to_file = __dir__ + "/miscellaneous/files/"
    @logger = Logger.new(@path_to_file + "gpc.log")
    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database

    data_raw = File.read(__dir__ + "/" + file_name)
    data_json = JSON.parse(data_raw, symbolize_names: true)

    # load data
    funding_fee_A = data_json[:A][:funding_fee].to_i
    funding_fee_B = data_json[:B][:funding_fee].to_i
    settle_fee_A = data_json[:A][:settle_fee].to_i
    settle_fee_B = data_json[:B][:settle_fee].to_i
    container_min = data_json[:container_min].to_i

    funding_amount_A = data_json[:A][:funding_amount].map { |key, value| key == :ckb ? [key, BigDecimal(value.to_i) / 10 ** 8] : [key, value.to_i] }.to_h
    funding_amount_B = data_json[:B][:funding_amount].map { |key, value| key == :ckb ? [key, BigDecimal(value.to_i) / 10 ** 8] : [key, value.to_i] }.to_h

    expect = JSON.parse(data_json[:expect_info], symbolize_names: true) if data_json[:expect_info] != nil
    settle_fee_unilateral = data_json[:settle_fee_unilateral].to_i
    closing_fee_unilateral = data_json[:closing_fee_unilateral].to_i
    closing_type = data_json[:closing_type]
    tg_msg_lib = data_json[:tg_msg]
    channel_establishment = data_json[:channel_establishment]

    # init the ckb environment.
    tests = Gpctest.new("test")
    tests.setup()
    tests.init_client()

    begin
      # create channel.
      channel_id, @monitor_A, @monitor_B = tests.create_channel(funding_amount_A, funding_amount_B, container_min, funding_fee_A, funding_fee_B, channel_establishment)

      # If the channel establishment fails, we need not try to make payment and assert the balance.
      if channel_establishment

        # send tg msg.
        for tg_msg in tg_msg_lib
          sender = tg_msg[:sender]
          receiver = tg_msg[:receiver]
          payment_type = tg_msg[:payment_type]
          user_name = tg_msg[:user_name]
          muted_id = tg_msg[:muted_id]
          muted_time = tg_msg[:time]

          # store the payment type, msg and the user_name.
          file = File.new(@path_to_file + "tg_msg.json", "w")
          file.syswrite(tg_msg.to_json)

          if sender == "A" && receiver == "B"
            tests.send_tg_msg_A_B(channel_id, payment_type)
          else
            return false
          end
          sleep(3)
        end

        # B send the close request to A.
        tests.closing_B_A(channel_id, settle_fee_B, settle_fee_A, closing_fee_unilateral, settle_fee_unilateral, closing_type)
      end
    rescue Exception => e
      puts e
    ensure
      tests.record_info_in_db()
      tests.close_all_thread(@monitor_A, @monitor_B, @db)
      if expect != nil
        for expect_iter in expect
          result_json = tests.load_json_file(@path_to_file + "result.json").to_json
          assert_match(expect_iter.to_json[1..-2], result_json, "#{expect_iter[1..-2]}")
        end
      end
    end
  end

  # test tg robot.
  def test_tg_msg()
    path_to_tg_robot = "./tg_robot_test/"
    simulation(path_to_tg_robot + "tg_robot.json")
  end
end
