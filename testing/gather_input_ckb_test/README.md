# Gather_input_ckb_test

Tests in this dir is about the gather_input function in CKB and UDT. The two accounts used for testing are as follows

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

User A will deploy the [GPC](https://github.com/ZhichunLu-11/ckb-gpc-contract/blob/master/main.c) and [UDT](https://github.com/ZhichunLu-11/ckb-gpc-contract/blob/f39fd7774019d0333857f8e6861300a67fb1e266/c/simple_udt.c) contract and distribute 200 UDT cells with a denomination of 20 to itself and B. After initialization, the balances of A and B are.

``` 
A
UDT: 200
CKB: 519862318097990000 (shannon)

B
UDT: 200
CKB: 2000000000000000000 (shannon)
```

Please note that you need to set the miner account in ckb.toml to any user except A and B before testing. This is because we need to ensure that during the operation period, the balance of A and B will not change due to mining rewards.

# Cases detail

A is the initiator of the channel establishment and B is the recipient. So I'll refer to them in the following as sender and receiver.

## case1
**Description:** The sender puts in money equal to the maximum he can afford.

**Expect:** *sender_gather_funding_success*
## case2
**Description:** The sender invested more than the maximum amount he can afford.

**Expect:** *sender_gather_funding_error_insufficient*
## case3
**Description:** The funds invested by the sender are negative.

**Expect:** *sender_gather_funding_error_negtive*
## case4
**Description:** The fee invested by the sender is negative.

**Expect:** *sender_gather_funding_error_negtive*
## case5
**Description:** The receiver puts in money equal to the maximum he can afford.

**Expect:** *receiver_gather_funding_success*
## case6
**Description:** The receiver invested more than the maximum amount he can afford.

**Expect:** *receiver_gather_funding_error_insufficient*
## case7
**Description:** The funds invested by the receiver are negative.

**Expect:** *receiver_gather_funding_error_negtive*
## case8
**Description:** The fee invested by the receiver is negative.

**Expect:** *receiver_gather_funding_error_negtive*