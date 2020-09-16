require_relative "./miscellaneous/libs/gpctest.rb"
require_relative "../message_sender_bot/message_sender_bot.rb"
require "active_support"
require "minitest/autorun"
require "mongo"
require "bigdecimal"

# A is sender and B is listener
Mongo::Logger.logger.level = Logger::FATAL

class Test_sad < Minitest::Test
  def simulation(file_name)
    begin
      @private_key_A = "0x63d86723e08f0f813a36ce6aa123bb2289d90680ae1e99d4de8cdb334553f24d"
      @private_key_B = "0xd00c06bfd800d27397002dca6fb0993d5ba6399b4238b2f29ee9deb97593d2bc"
      @path_to_file = __dir__ + "/miscellaneous/files/"
      @path_to_msg = __dir__ + "/msg_lib/"
      @logger = Logger.new(@path_to_file + "gpc.log")
      @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
      @db = @client.database
      @db.drop()

      data_raw = File.read(__dir__ + "/" + file_name)
      data_json = JSON.parse(data_raw, symbolize_names: true)
      msg_lib = {}

      # load msg template
      for number in (1..9)
        file_name = @path_to_msg + number.to_s + ".json"
        data_raw = File.read(file_name)
        msg_lib[("msg" + number.to_s).to_sym] = JSON.parse(data_raw, symbolize_names: true)
      end

      # load data
      funding_fee_A = data_json[:A][:funding_fee].to_i
      funding_fee_B = data_json[:B][:funding_fee].to_i
      settle_fee_A = data_json[:A][:settle_fee].to_i
      settle_fee_B = data_json[:B][:settle_fee].to_i
      container_min = data_json[:container_min].to_i

      funding_amount_A = data_json[:A][:funding_amount].map { |key, value| key == :ckb ? [key, BigDecimal(value.to_i) / 10 ** 8] : [key, value.to_i] }.to_h
      funding_amount_B = data_json[:B][:funding_amount].map { |key, value| key == :ckb ? [key, BigDecimal(value.to_i) / 10 ** 8] : [key, value.to_i] }.to_h

      cells_spent_A = data_json[:A][:spent_cell] == nil ? nil : data_json[:A][:spent_cell].map { |cell| CKB::Types::OutPoint.from_h(cell) }
      cells_spent_B = data_json[:B][:spent_cell] == nil ? nil : data_json[:B][:spent_cell].map { |cell| CKB::Types::OutPoint.from_h(cell) }

      ip_A = data_json[:A][:ip]
      ip_B = data_json[:B][:ip]
      listen_port_A = data_json[:A][:port]
      listen_port_B = data_json[:B][:port]

      expect = JSON.parse(data_json[:expect_info], symbolize_names: true) if data_json[:expect_info] != nil
      settle_fee_unilateral = data_json[:settle_fee_unilateral].to_i
      closing_fee_unilateral = data_json[:closing_fee_unilateral].to_i
      closing_type = data_json[:closing_type]
      payments = data_json[:payments]
      robot = data_json[:robot]
      channel_establishment = data_json[:channel_establishment]
      modifications = data_json[:modifications]

      # init the ckb environment.
      tests = Gpctest.new("test")
      tests.setup()

      # init the client.
      tests.init_client()

      # get the asset information at the beginning.
      udt_A_begin, udt_B_begin = tests.get_account_balance_udt()
      ckb_A_begin, ckb_B_begin = tests.get_account_balance_ckb()

      # spend the cells.
      tests.spend_cell("A", cells_spent_A)
      tests.spend_cell("B", cells_spent_B)

      # process modification, i.e., modify the msg_lib.
      for modification in modifications
        keys = modification[:key]
        value = modification[:value_to]
        msg_layered_lib = []
        msg_layered = msg_lib
        for key in keys
          if key.is_a? Numeric
            msg_layered = msg_layered[key]
          elsif key.is_a? String
            msg_layered = msg_layered[key.to_s.to_sym]
          end
          msg_layered_lib.append(msg_layered)
        end
        msg_layered_lib[-1] = value
        # reverse
        for index in (1..keys.length() - 1).reverse_each
          key = keys[index]
          if key.is_a? Numeric
            msg_layered_lib[index - 1][key] = msg_layered_lib[index]
          elsif key.is_a? String
            msg_layered_lib[index - 1][key.to_s.to_sym] = msg_layered_lib[index]
          end
        end
        msg_lib[keys[0].to_s.to_sym] = msg_layered_lib[0]
      end

      # tell me who is robot.
      if robot == "A"
        @logger.info("sad path: branch A.")
        @monitor_B, @listener_B = tests.start_listen_monitor_B()

        # create bot and set msg to be sent.
        bot = Sender_bot.new(@private_key_A)
        bot.send_msg(ip_B, listen_port_B, [msg_lib[:"msg1"], msg_lib[:"msg3"], msg_lib[:"msg5"]])
      elsif robot == "B"
        @logger.info("sad path: branch B.")

        # create bot and set msg to be replied.
        bot = Sender_bot.new(@private_key_B)
        thread_listen = Thread.new { bot.listen(listen_port_B, [msg_lib[:"msg2"], msg_lib[:"msg4"]]) }
        # thread_listen = Thread.new { bot.listen(listen_port_B, [msg_lib[:"msg2"]]) }

        # send establishment request.
        tests.send_establishment_request_A(funding_amount_A, funding_fee_A)
        thread_listen.join
      else
        puts "robot can only be A or B."
        return false
      end
    rescue => exception
      puts exception
    ensure
      if robot == "A"
        tests.close_all_thread(0, @monitor_B, @db)
      elsif robot == "B"
        tests.close_all_thread(0, 0, @db)
      end
      
      if expect != nil
        for expect_iter in expect
          result_json = tests.load_json_file(@path_to_file + "result.json").to_json
          assert_match(expect_iter.to_json[1..-2], result_json, "#{expect_iter[1..-2]}")
        end
      end
    end
  end

  ### sad path
  ## step1
  # def test_step1()
  #   path_to_step1 = "./step1_test/"
  #   # simulation(path_to_step1 + "test_step1_amount_negtive.json")
  #   # simulation(path_to_step1 + "test_step1_fee_negtive.json")
  #   # simulation(path_to_step1 + "test_step1_change_container_insufficient.json")
  #   # simulation(path_to_step1 + "test_step1_settle_container_insufficient.json")
  #   # simulation(path_to_step1 + "test_step1_cell_dead.json")
  #   # simulation(path_to_step1 + "test_step1_capacity_inconsistent.json")
  # end

  ## step2
  # def test_step2()
  #   path_to_step2 = "./step2_test/"
  #   # simulation(path_to_step2 + "test_step2_gpc_output_modified.json")
  #   # simulation(path_to_step2 + "test_step2_gpc_output_data_modified.json")
  #   # simulation(path_to_step2 + "test_step2_local_change_output_modified.json")
  #   # simulation(path_to_step2 + "test_step2_local_change_output_data_modified.json")
  #   # simulation(path_to_step2 + "test_step2_capacity_inconsistent.json")
  # end

  ## step3
  # def test_step3()
    # path_to_step3 = "./step3_test/"
    # simulation(path_to_step3 + "test_step3_gpc_arg_modified.json")
    # simulation(path_to_step3 + "test_step3_signature_invalid.json")
  # end

  ## step4
  # def test_step4()
  #   path_to_step4 = "./step4_test/"
  #   simulation(path_to_step4 + "test_step4_local_data_modified.json")
  #   simulation(path_to_step4 + "test_step4_signature_invalid.json")
  #   simulation(path_to_step4 + "test_step4_signature_inconsistent.json")
  # end

  ## step5
  # def test_step5()
  #   path_to_step5 = "./step5_test/"
  #   simulation(path_to_step5 + "test_step5_fund_tx_modified.json")
  #   simulation(path_to_step5 + "test_step5_signature_invalid.json")
  # end

  ## step6_closing
  ## step6_payment
  ## step7
  ## step8
  ## step9
end
