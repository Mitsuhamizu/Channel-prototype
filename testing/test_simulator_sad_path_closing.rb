require_relative "./miscellaneous/libs/gpctest.rb"
require_relative "../message_sender_bot/message_sender_bot.rb"
require "active_support"
require "minitest/autorun"
require "mongo"
require "bigdecimal"

# A is sender and B is listener
Mongo::Logger.logger.level = Logger::FATAL

class Test_sad_closing < Minitest::Test
  def simulation(file_name)
    begin
      @private_key_A = "0x63d86723e08f0f813a36ce6aa123bb2289d90680ae1e99d4de8cdb334553f24d"
      @private_key_B = "0xd00c06bfd800d27397002dca6fb0993d5ba6399b4238b2f29ee9deb97593d2bc"
      @path_to_file = __dir__ + "/miscellaneous/files/"
      @path_to_msg = __dir__ + "/msg_lib_closing/"
      @logger = Logger.new(@path_to_file + "gpc.log")
      @client = Mongo::Client.new(["127.0.0.1:27017"], :database => "GPC")
      @db = @client.database
      @db.drop()

      @logger.info("simulate sad closign: begin to load msg template.")
      data_raw = File.read(__dir__ + "/" + file_name)
      data_json = JSON.parse(data_raw, symbolize_names: true)
      msg_lib = {}
      # load msg template
      for number in [6, 9]
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

      tests = Gpctest.new("test")
      tests.setup()
      # init the client.
      tests.init_client()

      # get the asset information at the beginning.
      udt_A_begin, udt_B_begin = tests.get_account_balance_udt()
      ckb_A_begin, ckb_B_begin = tests.get_account_balance_ckb()

      # create the channel.
      channel_id, @monitor_A, @monitor_B = tests.create_channel(funding_amount_A, funding_amount_B, container_min, funding_fee_A, funding_fee_B, channel_establishment)

      # make payment.
      @logger.info("sad path closing: channel establishment finish.")
      if channel_establishment
        # make payments.
        ckb_transfer_A_to_B = 0
        ckb_transfer_B_to_A = 0
        udt_transfer_A_to_B = 0
        udt_transfer_B_to_A = 0

        # send payment.
        for payment in payments
          @logger.info("sad path closing: #{payment[:name]} begins.")
          sender = payment[:sender]
          receiver = payment[:receiver]
          amount = payment[:amount]
          success = payment[:success]
          payment_type = payment[:payment_type]

          if sender == "A" && receiver == "B"
            tests.make_payment_A_B(channel_id, payment_type, amount)
            if success
              if payment_type == "ckb"
                ckb_transfer_A_to_B += amount
              elsif payment_type == "udt"
                udt_transfer_A_to_B += amount
              end
            end
          elsif sender == "B" && receiver == "A"
            tests.make_payment_B_A(channel_id, payment_type, amount)
            if success
              if payment_type == "ckb"
                ckb_transfer_B_to_A += amount
              elsif payment_type == "udt"
                udt_transfer_B_to_A += amount
              end
            end
          else
            return false
          end
        end
      end

      @logger.info("sad path closing: all payment sent.")

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

      @logger.info("sad path closing: all modification done.")

      # spend the cells.
      tests.spend_cell("A", cells_spent_A)
      tests.spend_cell("B", cells_spent_B)
      # tell me who is robot.
      if robot == "A"
        @logger.info("sad path closing: branch A.")
        tests.kill_listener()

        bot = Sender_bot.new(@private_key_A)
        thread_listen = Thread.new { bot.listen(listen_port_A, [msg_lib[:"msg9"]]) }

        @logger.info("Robot A is ready.")

        # send establishment request.
        tests.closing_B_A(channel_id, settle_fee_B, settle_fee_A, closing_fee_unilateral, settle_fee_unilateral, closing_type)
        thread_listen.join
      elsif robot == "B"
        @logger.info("sad path closing: branch B.")

        # create bot and set msg to be replied.
        bot = Sender_bot.new(@private_key_B)
        bot.send_msg(ip_A, listen_port_A, [msg_lib[:"msg6"]])
      else
        puts "robot can only be A or B."
        return false
      end
    rescue => exception
      puts exception
    ensure
      # record current state in db.
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

  # step6
  def test_step6()
    path_to_step6 = "./step6_closing_test/"
    simulation(path_to_step6 + "test_step6_cell_dead.json")
    simulation(path_to_step6 + "test_step6_change_container_insufficient.json")
    simulation(path_to_step6 + "test_step6_fee_negative.json")
  end

  # step9
  def test_step9()
    path_to_step9 = "./step9_test/"
    simulation(path_to_step9 + "test_step9_cell_dead.json")
    simulation(path_to_step9 + "test_step9_stx_info_inconsistent.json")
    simulation(path_to_step9 + "test_step9_change_container_insufficient.json")
    simulation(path_to_step9 + "test_step9_fee_negative.json")
    simulation(path_to_step9 + "test_step9_signature_invalid.json")
  end
end
