# Channel-prototype

The code of contract is in the ckb-gpc-contract/main.c.

# Preparation

You needs to have two ckb account that have sufficient ckb in you local chain, and the mongodb.

# Send contract to chain.

```
cd client1/test
ruby send_contract.rb
```

Note that send_contract.rb will print two info, the first is the code hash, and the second is tx_hash. You should remember these info, and change the @gpc_tx and @gpc_code_hash to your local version.

Now I just merge the component into the command line GPC. You can find it in both client1 and client2.


See the command in GPC by 

```
./GPC
```

Please init in the first use

```
GPC init <private-key>
```

Every client should run 
```
GPC monitor <public key>
GPC listen <pubkey> <port>
```

Then you can make payments by other command.

Note that some commands require continuous user interaction, please enter the corresponding content in your command line.