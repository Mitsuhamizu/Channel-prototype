# Channel-prototype

The code of contract is in the ckb-gpc-contract/main.c.

# Preparation

You needs to have two ckb account that have sufficient ckb in you local chain, and the mongodb.

# Send contract to chain.

```
cd client1/test
ruby send_contract.rb
```

Note that send_contract.rb will print two info, the first is the code hash, and the second is tx_hash. You should remember these info.

# Channel establishment.

## Initailization.

```
cd client1
ruby main.rb init <private key 1>
cd ../client2
ruby main.rb init <private key 2>
```

Afther these two step, you will have two collections in your local mongodb.

## Channel establishment.

First of all, you need to replace all @gpc_code_hash and @gpc_tx to your local ones. More specifically, in /libs/chain_monitor.rb, /libs/communication.rb and /libs/tx_generator.rb.



Client 2 is the listener.

```
cd client2

ruby main.rb start <public key2>
```

The meaning of command in command.txt are

"listen" is listen command.

"1000" is the port of listening.

"yes" means I am willing to accept the channel establishment request.

"300" and "10000" is the amount of money I want to fund and the fee I want to pay. Amount is in ckbyte and fee is in shannon.


Client 1 is the sender, and copy client1/channel_establishment.txt to client1/command.txt.

```
cd client1

ruby main.rb start <public 1>
```

The meaning of commands are

"send" represents send channel establishment request.

"127.0.0.1" represents the remote ip, and "1000" is the port.

"200" is the amount of money I want to fund.

"10000" is the fee I want to pay (the fee of tx).

"9223372036854775908" is the lock time i.e, since, here, it is the 100 relative blocks.


Then, you can see the database updated. Now they have the fund, closing and settlement tx, and the client 2 will send the fund tx to chain, you should run ckb to see if the tx is accepted.

## Update the status.

Then you should run 
```
cd client1

ruby minitor.rb

cd ../client2

ruby minitor.rb
```

Note that you should change the variable "private_key" in client1/monitor.rb and client2/monitor.rb to you local ones.

Then you can see the "stage" field of two records in mongodb changed to 1, which means the monitor find the fund tx on chain, so they can make payments now.

# Making payments.

First, you should copy client1/making_payments.txt to command.txt.

Then

```
cd client2

ruby main.rb start <public key2>

cd ../client2

ruby main.rb start <private key1>
```

The meaning of command are

"pay" is pay command.

"127.0.0.1" and "1000" are the remote IP and port.

"1" is the amount I want to pay (making payments).

Then, you can see the record is updated according to the payments.

# Send closing and settlement tx.

Previously, I adopted client1/test/generate_ctx.rb to send tx. But now, I merge the function into the libs/chain_monitor.rb. You need three args, the doc is the documents in mongodb, type is the type... "closing" or "settlement". And fee is the fee you want to pay. After sending the closing tx, you can just run monitor.rb. The program will detect and automatically send settlement tx.

If you want to find the detail of communication detail, just check the communication.rb.