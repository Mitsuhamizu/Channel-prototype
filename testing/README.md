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
The *CKB asset* represents the number of CKByte that a user can use for trading, while the *CKB total* represents the user's total CKB including containers. This is because, CKB is a special asset, a cell representing UDT also contains CKB, and users can store some data in output_data. Therefore, we should not consider these CKByte that support UDT or data as CKByte assets. For B, the 134000000000 additional CKBytes represent containers for 10 UDT cells. For A, the extra 9319600000000 CKBytes represents containers for 10 UDT cells, GPC and UDT contracts.

You can find the detail of the setup work in [gpctest.rb](https://github.com/ZhichunLu-11/Channel-prototype/blob/master/testing/libs/gpctest.rb#L97-L183). 

**Note:** You need to set the miner account in ckb.toml to any user except A and B before testing. This is because we need to ensure that during the operation period, the balance of A and B will not change due to mining rewards.