require_relative "../libs/gpctest.rb"
require "minitest/autorun"
require "mongo"
require "bigdecimal"

Mongo::Logger.logger.level = Logger::FATAL

class Gather_input_udt < Minitest::Test
  def gather_input(file_name)
    @logger = Logger.new(__dir__ + "/../files/" + "gpc.log")
    @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
    @db = @client.database

    data_raw = File.read(__dir__ + "/" + file_name)
    data_json = JSON.parse(data_raw, symbolize_names: true)

    container_min = data_json[:container_min].to_i
    funding_fee_A = data_json[:funding_fee_A].to_i
    funding_fee_B = data_json[:funding_fee_B].to_i
    funding_amount_A = data_json[:funding_amount_A].to_i
    funding_amount_B = data_json[:funding_amount_B].to_i

    # # prepare the test
    tests = Gpctest.new("test")
    tests.setup()

    investment_A = funding_amount_A
    investment_B = funding_amount_B
    expect = data_json[:expect_info]
    @monitor_A, @monitor_B = tests.check_investment_fee(investment_A, investment_B, funding_fee_A, funding_fee_B, expect, "udt")

    if flag == "ckb"
      system("ruby " + __dir__ + "/../../client1/GPC" + " send_establishment_request --pubkey #{@pubkey_A} --ip #{@ip_B} --port #{@listen_port_B} --amount #{funding_A} --fee #{fee_A} --since #{since}")
    elsif flag == "udt"
      system("ruby " + __dir__ + "/../../client1/GPC" + " send_establishment_request --pubkey #{@pubkey_A} --ip #{@ip_B} --port #{@listen_port_B} --amount #{funding_A} --fee #{fee_A} --since #{since} --type_script_hash #{type_script_hash}")
    end

    result_json = tests.load_json_file(@path_to_file + "/result.json").to_json
    assert_match(expect[1..-2], result_json, "#{expect}")

    tests.close_all_thread(@monitor_A, @monitor_B, @db)
  end

  # receiver

  def test_receiver_gather_insufficient_1_stage()
    gather_input("Receiver_gather_insufficient_1_stage.json")
  end

  def test_receiver_gather_insufficient_2_stage()
    gather_input("Receiver_gather_insufficient_2_stage.json")
  end

  def test_receiver_gather_success_1_stage()
    gather_input("Receiver_gather_success_1_stage.json")
  end

  def test_receiver_gather_success_2_stage()
    gather_input("Receiver_gather_success_2_stage.json")
  end

  # sender

  def test_sender_gather_insufficient_1_stage()
    gather_input("Sender_gather_insufficient_1_stage.json")
  end

  def test_sender_gather_insufficient_2_stage()
    gather_input("Sender_gather_insufficient_2_stage.json")
  end

  def test_sender_gather_success_1_stage()
    gather_input("Sender_gather_success_1_stage.json")
  end

  def test_sender_gather_success_2_stage()
    gather_input("Sender_gather_success_2_stage.json")
  end
end
