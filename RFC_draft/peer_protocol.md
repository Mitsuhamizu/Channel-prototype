
- ![#f03c15](https://via.placeholder.com/15/f03c15/000000?text=+) `#f03c15`


[#f03c15]
# Message format

1. `type` : a 2-byte big-endian field indicating the type of message
2. `payload` : a variable-length payload that comprises the remainder of the message and that conforms to a format matching the `type`
3. `extension` : an optional [TLV stream](#type-length-value-format)

# Gossiper

# Single-hop

### The `open_channel` Message

1. type: 32 (`open_channel`)
2. data:

   * [`chain_hash`:`chain_hash`]
   * [`32*byte`:`temporary_channel_id`]
   * [`u64`:`funding_satoshis`] <font color=yellow> multi-asset.</font>
   * [`u64`:`push_msat`] <font color=red> bilateral funding.</font>
   * [`u64`:`dust_limit_satoshis`] <font color=red> About the dust problem. In my option, this problem will not happen in CKB.</font>
   * [`u64`:`max_htlc_value_in_flight_msat`]
   * [`u64`:`channel_reserve_satoshis`] <font color=red> Only in RSMC. </font>
   * [`u64`:`htlc_minimum_msat`] 
   * [`u32`:`feerate_per_kw`] <font color=red> Not sure, it depends on the fee mechanism in CKB. </font>
   * [`u16`:`to_self_delay`] <font color=red> Only in RSMC. </font>
   * [`u16`:`max_accepted_htlcs`]
   * [`point`:`funding_pubkey`] 
   * [`point`:`revocation_basepoint`] <font color=red> Only in RSMC. </font>
   * [`point`:`payment_basepoint`] <font color=red> Not sure. </font>
   * [`point`:`delayed_payment_basepoint`] <font color=red> Only in RSMC. </font>
   * [`point`:`htlc_basepoint`] <font color=red> Not sure, is it necessary to use different key in HTLCs? </font>
   * [`point`:`first_per_commitment_point`] <font color=red> Only in RMSC. </font>
   * [`byte`:`channel_flags`] 
   * [`open_channel_tlvs`:`tlvs`]
   * [ `u16`:`challenge_period`] <font color=green> For GPC. </font>
   * [ `u16`:`fee`]<font color=green> For GPC, it depends on the fee mechanism in ckb.</font>
   * [ `input[]` : `funding_cells` ]<font color=green> For GPC. </font>
   * [ `output[]` : `change_outputs` ]<font color=green> For GPC. </font>
   * [ `output[]` : `settlement_output` ]<font color=green> For GPC. </font>

### The `accept_channel` Message

1. type: 33 (`accept_channel`)
2. data:

   * [ `32*byte` : `temporary_channel_id` ]
   * [ `u64` : `max_htlc_value_in_flight_ckbytes` ]
   * [ `u64` : `htlc_minimum_ckbyte` ] (Dust problem.)
   * [ `u32` : `minimum_depth` ]
   * [ `u16` : `to_self_delay` ]
   * [ `u16` : `max_accepted_htlcs` ]
   * [ `point` : `funding_pubkey` ]
   * [ `point` : `revocation_basepoint` ]
   * [ `point` : `payment_basepoint` ]
   * [ `point` : `delayed_payment_basepoint` ]
   * [ `point` : `htlc_basepoint` ]
   * [ `point` : `first_per_commitment_point` ]
   * [ `accept_channel_tlvs` : `tlvs` ]

# Multi-hop

# Watch tower
