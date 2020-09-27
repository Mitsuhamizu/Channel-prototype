# Testing

Tests in this dir are about the gather_input function in CKB and UDT. The two accounts used for testing are as follows

**A's info**

``` 
# issue for random generated private key: 63d86723e08f0f813a36ce6aa123bb2289d90680ae1e99d4de8cdb334553f24d
[[genesis.issued_cells]]
capacity = 5_198_735_037_00000000
lock.code_hash = "0x9bd7e06f3ecf4be0f2fcd2188b23f1b9fcc88e5d4b65a8637b17723bbda3cce8"
lock.args = "0x470dcdc5e44064909650113a274b3b36aecb6dc7"
lock.hash_type = "type"
```

**B's info**

``` 
# issue for random generated private key: d00c06bfd800d27397002dca6fb0993d5ba6399b4238b2f29ee9deb97593d2bc
[[genesis.issued_cells]]
capacity = 20_000_000_000_00000000
lock.code_hash = "0x9bd7e06f3ecf4be0f2fcd2188b23f1b9fcc88e5d4b65a8637b17723bbda3cce8"
lock.args = "0xc8328aabcd9b9e8e64fbc566c4385c3bdeb219d7"
lock.hash_type = "type"

```

# Setup

User A will deploy the [GPC](https://github.com/ZhichunLu-11/ckb-gpc-contract/blob/master/main.c) and [UDT](https://github.com/ZhichunLu-11/ckb-gpc-contract/blob/f39fd7774019d0333857f8e6861300a67fb1e266/c/simple_udt.c) contract and distribute 200 UDT cells with a denomination of 20 to itself and B. After initialization, the balances of A and B are

``` 
A
UDT: 200
CKB(asset): 519862318097990000 (shannon)
CKB(total): 519871637697990000 (shannon)

B
UDT: 200
CKB(asset): 2000000000000000000 (shannon)
CKB(total): 2000000134000000000 (shannon)
```

The *CKB asset* represents the number of CKByte that a user can use for trading, while the *CKB total* represents the user's total CKB including containers. This is because, CKB is a special asset, a cell representing UDT also contains CKB, and users can store some data in output_data. Therefore, we should not consider these CKByte that support UDT or data as CKByte assets.

You can find the detail of the setup work in [gpctest.rb](https://github.com/ZhichunLu-11/Channel-prototype/blob/master/testing/miscellaneous/libs/gpctest.rb#L97-L183). 

**Note:** You need to set the miner account in ckb.toml to any user except A and B before testing. This is because we need to ensure that during the operation period, the balance of A and B will not change due to mining rewards.

# Specification

I will describe the test according to the lifecycle of the channel.

## Happy paths

### Establishment

When establishing a channel, the interaction between the client and the user is simply the amount invested and whether or not the establishment is accepted. Here we assume the answer to the connection request is YES, so we only need to test the amount of investment the user wants to make.

The test file of happy path is [test_simulator_happy_path.rb](https://github.com/ZhichunLu-11/Channel-prototype/tree/master/testing/test_simulator_happy_path.rb). It contains following tests.

* Establishment: [gather_input_ckb_test](https://github.com/ZhichunLu-11/Channel-prototype/tree/master/testing/gather_input_ckb_test) and 
[gather_input_udt_test](https://github.com/ZhichunLu-11/Channel-prototype/tree/master/testing/gather_input_udt_test) tests correct behaviour of progra when the gathering amount of fee are negtive or insufficient in CKB and UDT situations.

* Making payments: Folder [making_payment_ckb](https://github.com/ZhichunLu-11/Channel-prototype/tree/master/testing/making_payment_ckb) and [making_payment_udt](https://github.com/ZhichunLu-11/Channel-prototype/tree/master/testing/making_payment_ckb) tests the correct behaviour of the program when the payment amount is insufficient or negative when the payment asset type is CKB and UDT, respectively.
* Closing channel: Folder [closing_channel_test](https://github.com/ZhichunLu-11/Channel-prototype/tree/master/testing/closing_channel_test) tests bilateral and unilateral close situation of GPC.

## Sad paths

### Establishment

There are three .rb file to test the sad paths, namely 
* [test_simulator_sad_path_closing.rb](https://github.com/ZhichunLu-11/Channel-prototype/tree/master/testing/test_simulator_sad_path_closing.rb): tests the first step 1-5.
* [test_simulator_sad_path_establishment.rb](https://github.com/ZhichunLu-11/Channel-prototype/tree/master/testing/test_simulator_sad_path_establishment.rb): tests step 6-8.
* [test_simulator_sad_path_closing.rb](https://github.com/ZhichunLu-11/Channel-prototype/tree/master/testing/test_simulator_sad_path_closing.rb) tests step 6 and step 9.

To simulate the misbehaviour, invalid signature for example. Firstly, I record every message in the normal case, I can make sure that every time the msg is valid since I will truncate to block 0 before every test begins.

Then, I adopt a [message robot](https://github.com/ZhichunLu-11/Channel-prototype/blob/master/message_sender_bot/message_sender_bot.rb) to simulate malicious users. In every json file for sad path, there is one field called *robot* to point out which one is robot and one filed called *modification* to illustrate which part of msg I will change.

# Usage

You can type rake in the terminal to let all test begins. 

``` 
rake
```
