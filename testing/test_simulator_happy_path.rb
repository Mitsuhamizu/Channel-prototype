require_relative "./miscellaneous/libs/gpctest.rb"
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
    payments = data_json[:payments]
    channel_establishment = data_json[:channel_establishment]

    # init the ckb environment.
    tests = Gpctest.new("test")
    tests.setup()
    tests.init_client()

    # get the asset information at the beginning.
    udt_A_begin, udt_B_begin = tests.get_account_balance_udt()
    ckb_A_begin, ckb_B_begin = tests.get_account_balance_ckb()

    begin
      # create channel.
      channel_id, @monitor_A, @monitor_B = tests.create_channel(funding_amount_A, funding_amount_B, container_min, funding_fee_A, funding_fee_B, channel_establishment)

      # If the channel establishment fails, we need not try to make payment and assert the balance.
      if channel_establishment

        # make payments.
        ckb_transfer_A_to_B = 0
        ckb_transfer_B_to_A = 0
        udt_transfer_A_to_B = 0
        udt_transfer_B_to_A = 0

        # send payment.
        for payment in payments
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

        # calculate the expected balance.
        ckb_A_B = ckb_transfer_A_to_B - ckb_transfer_B_to_A
        udt_A_B = udt_transfer_A_to_B - udt_transfer_B_to_A

        # B send the close request to A.
        tests.closing_B_A(channel_id, settle_fee_B, settle_fee_A, closing_fee_unilateral, settle_fee_unilateral, closing_type)

        ckb_A_after_closing, ckb_B_after_closing = tests.get_account_balance_ckb()
        udt_A_after_closing, udt_B_after_closing = tests.get_account_balance_udt()

        # assert udt
        assert_equal(udt_A_B, udt_A_begin - udt_A_after_closing, "A'udt after payment is wrong.")
        assert_equal(-udt_A_B, udt_B_begin - udt_B_after_closing, "B'udt after payment is wrong.")

        # assert ckb

        if closing_type == "bilateral"
          assert_equal(ckb_A_B * 10 ** 8 + funding_fee_A + settle_fee_A, ckb_A_begin - ckb_A_after_closing, "A'ckb after payment is wrong.")
          assert_equal(-ckb_A_B * 10 ** 8 + funding_fee_B + settle_fee_B, ckb_B_begin - ckb_B_after_closing, "B'ckb after payment is wrong.")
        elsif closing_type == "unilateral"
          # case1: B closing, A settle.
          # case2: B closing, B settle.
          assert(((ckb_A_B * 10 ** 8 + funding_fee_A + settle_fee_unilateral == ckb_A_begin - ckb_A_after_closing) &&
                  (-ckb_A_B * 10 ** 8 + funding_fee_B + closing_fee_unilateral == ckb_B_begin - ckb_B_after_closing)) ||
                 ((ckb_A_B * 10 ** 8 + funding_fee_A == ckb_A_begin - ckb_A_after_closing) &&
                  (-ckb_A_B * 10 ** 8 + funding_fee_B + closing_fee_unilateral + settle_fee_unilateral == ckb_B_begin - ckb_B_after_closing)), "balance after payments wrong.")
        end
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

  ## happy path

  # # closing_channel_test
  # def test_closing_channel()
  #   path_to_closing_channel_test = "./closing_channel_test/"
  #   simulation(path_to_closing_channel_test + "closing_unilateral.json")
  #   simulation(path_to_closing_channel_test + "closing_bilateral.json")
  # end

  # # gather_input_ckb
  # def test_gather_input_ckb()
  #   path_to_gather_input_ckb = "./gather_input_ckb_test/"
  #   simulation(path_to_gather_input_ckb + "Receiver_fee_negtive.json") 
  #   simulation(path_to_gather_input_ckb + "Receiver_funding_negtive.json")
  #   simulation(path_to_gather_input_ckb + "Receiver_gather_insufficient.json")
  #   simulation(path_to_gather_input_ckb + "Sender_fee_negtive.json")
  #   simulation(path_to_gather_input_ckb + "Sender_funding_negtive.json")
  #   simulation(path_to_gather_input_ckb + "Sender_gather_insufficient.json")
  # end

  # # gather_input_udt
  # # reconsider it.
  # def test_gather_input_udt()
  #   path_to_gather_input_udt = "./gather_input_udt_test/"
  #   simulation(path_to_gather_input_udt + "Receiver_gather_insufficient_1_stage.json")
  #   simulation(path_to_gather_input_udt + "Receiver_gather_insufficient_2_stage.json")
  #   simulation(path_to_gather_input_udt + "Receiver_gather_success_1_stage.json")
  #   simulation(path_to_gather_input_udt + "Receiver_gather_success_2_stage.json")
  #   simulation(path_to_gather_input_udt + "Sender_gather_insufficient_1_stage.json")
  #   simulation(path_to_gather_input_udt + "Sender_gather_insufficient_2_stage.json")
  #   simulation(path_to_gather_input_udt + "Sender_gather_success_1_stage.json")
  #   simulation(path_to_gather_input_udt + "Sender_gather_success_2_stage.json")
  # end

  # # making_payment_ckb
  # def test_makeing_payment_ckb()
  #   path_to_making_payment_ckb = "./making_payment_ckb_test/"
  #   simulation(path_to_making_payment_ckb + "making_payment_success.json")
  #   simulation(path_to_making_payment_ckb + "making_payment_negtive.json")
  #   simulation(path_to_making_payment_ckb + "making_payment_insufficient.json")
  # end

  # # making_payment_udt
  # def test_makeing_payment_udt()
  #   path_to_making_payment_udt = "./making_payment_udt_test/"
  #   simulation(path_to_making_payment_udt + "making_payment_success.json")
  # end
end
