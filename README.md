# Channel-prototype

The code of contract is in the contract.

Client 1 is the sender.

```
cd client1

ruby main.rb init 0x82dede298f916ced53bf5aa87cea8a7e44e8898eaedcff96606579f7bf84d99d

ruby main.rb start 0x02ce9deada91368642e7b4343dea5046cb7f1553f71cab363daa32aa6fcea17648
```

Note that the command for main.rb is in the command.txt. In client1, the channel eatablishment command is in command copy.txt, and the command for making payments is in command copy 2.txt.

The meaning of command copy 1.txt are
"send" represents send channel establishment request.
"127.0.0.1" represents the remote ip, and "1000" is the port.
"200" is the amount of money I want to fund.
"10000" is the fee I want to pay (the fee of tx).
"9223372036854775908" is the lock time i.e, since, here, it is the 100 relative blocks.
Note that amount is in ckbyte and fee is in shannon.

The meaning of command copy 2.txt are
"pay" is pay command.
"127.0.0.1" and "1000" are the remote IP and port.
"1" is the amount I want to pay (making payments).

Client 2 is the listener.

```
cd client2
ruby main.rb init 0xd986d7bf901e50368cbe565f239c224934cd554805357338abcef177efadc08d
ruby main.rb start 0x039b64d0f58e2cc28d4579fac2ae571e118af0e4945928d699519aecb20ec9a793
```

The meaning of command in command.txt are

"listen" is listen command.
"1000" is the port of listening.
"yes" means I am willing to accept the channel establishment request.
"300" and "10000" is the amount of money I want to fund and the fee I want to pay. Amount is in ckbyte and fee is in shannon.

If you want to find the detail of communication detail, just check the communication.rb.