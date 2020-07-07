require "thor"

class GPCCLI < Thor
  desc "init <private-key>", "Init with the private key."

  def init(private_key)
    if ARGV.length != 2
      puts "The arg number is not right."
      return false
    end
    puts "111"
  end

  desc "listen <port>", "Listen the port."

  def listen(port = 1000)
    if ARGV.length != 2
      puts "The arg number is not right."
      return false
    end
  end

  desc "send_establishment_request --pubkey <public key> --ip <ip> --port <port> --amount <amount> --fee <fee> --since <since>", "Send the chanenl establishment request."
  option :pubkey
  option :ip
  option :port
  option :amount
  option :fee
  option :since

  def send_establishment_request()
    if ARGV.length != 15
      puts "The arg number is not right."
      return false
    end
  end

  desc "make_payment --pubkey <public key> --ip <ip> --port <port> --id <id> --amount <amount> ", "Make payments"

  def make_payment()
    if ARGV.length != 11
      puts "The arg number is not right."
      return false
    end
  end

  desc "monitor <public key>", "Monitor the chain."

  def monitor(port = 1000)
    if ARGV.length != 2
      puts "The arg number is not right."
      return false
    end
  end
end

GPCCLI.start(ARGV)
