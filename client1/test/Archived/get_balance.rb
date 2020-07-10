require "rubygems"
require "bundler/setup"
require "ckb"
require "json"

@api = CKB::API.new

def group_tx_input(tx)
  group = Hash.new()
  index = 0
  for input in tx.inputs
    validation = @api.get_live_cell(input.previous_output)
    lock_hash = validation.cell.output.lock.compute_hash
    if !group.keys.include?(lock_hash)
      group[lock_hash] = Array.new()
    end
    group[lock_hash] << index
    index += 1
  end
  return group
end

def sign_fund_tx(tx)
  input_group = group_tx_input(tx)

  for key in input_group.keys
    first_index = input_group[key][0]

    # include the first witness
    blake2b = CKB::Blake2b.new
    emptied_witness = tx.witnesses[first_index].dup
    emptied_witness.lock = "0x#{"0" * 130}"
    emptied_witness_data_binary = CKB::Utils.hex_to_bin(CKB::Serializers::WitnessArgsSerializer.from(emptied_witness).serialize)
    emptied_witness_data_size = emptied_witness_data_binary.bytesize
    blake2b.update(CKB::Utils.hex_to_bin(tx.hash))
    blake2b.update([emptied_witness_data_size].pack("Q<"))
    blake2b.update(emptied_witness_data_binary)

    #include the witness in the same group
    for index in input_group[key][1..]
      witness = tx.witnesses[index]
      data_binary = case witness
        when CKB::Types::Witness
          CKB::Utils.hex_to_bin(CKB::Serializers::WitnessArgsSerializer.from(witness).serialize)
        else
          CKB::Utils.hex_to_bin(witness)
        end
      data_size = data_binary.bytesize
      blake2b.update([data_size].pack("Q<"))
      blake2b.update(data_binary)
    end
    # include other witness
    witnesses_len = tx.witnesses.length()
    input_len = tx.inputs.length()
    witness_no_input_index = (input_len..witnesses_len - 1).to_a
    for index in witness_no_input_index
      witness = tx.witnesses[index]
      data_binary = case witness
        when CKB::Types::Witness
          CKB::Utils.hex_to_bin(CKB::Serializers::WitnessArgsSerializer.from(witness).serialize)
        else
          CKB::Utils.hex_to_bin(witness)
        end
      data_size = data_binary.bytesize
      blake2b.update([data_size].pack("Q<"))
      blake2b.update(data_binary)
    end
    message = blake2b.hexdigest
    witnesses[first_index].lock = key.sign_recoverable(message)
  end
end

tx_fund_file = File.new("./tx_fund_file.json", "r")
tx_fund = tx_fund_file.sysread(50000)
tx_fund_file.close

tx_fund = JSON.parse(tx_fund, symbolize_names: true)
tx_fund = CKB::Types::Transaction.from_h(tx_fund)
tx_fund = sign_fund_tx(tx_fund)

# puts tx_fund

# wallet = CKB::Wallet.from_hex(api, CKB::Key.random_private_key) # 新钱包
# wallet2 = CKB::Wallet.from_hex(api, CKB::Key.random_private_key) # 新钱包

# miner.send_capacity(wallet.address, 10000*(10**8), fee: 1000) # 转账

# data = File.read("carrot")

# data.bytesize # 此处字节长度是 7765，字符串的长度，以字节为单位

# carrot_tx_hash = wallet.send_capacity(wallet.address, CKB::Utils.byte_to_shannon(8000), CKB::Utils.bin_to_hex(data), fee: 10**6)
