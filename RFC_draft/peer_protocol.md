# Message format

1. `type` : a 2-byte big-endian field indicating the type of message
2. `payload` : a variable-length payload that comprises the remainder of the message and that conforms to a format matching the `type`
3. `extension` : an optional [TLV stream](#type-length-value-format)

# Gossiper

## The `announcement_signatures` Message

1. type: 259 (`announcement_signatures`)
2. data:
    - [`channel_id`:`channel_id`]
    - [`short_channel_id`:`short_channel_id`]
    - [`signature`:`node_signature`]
    - [`signature`:`bitcoin_signature`] 

## The `channel_announcement` Message

1. type: 256 (`channel_announcement`)
2. data:
    - [`signature`:`node_signature_1`]
    - [`signature`:`node_signature_2`]
    - [`signature`:`bitcoin_signature_1`]
    - [`signature`:`bitcoin_signature_2`]
    - [`u16`:`len`]
    - [`len*byte`:`features`]
    - [`chain_hash`:`chain_hash`]
    - [`short_channel_id`:`short_channel_id`]
    - [`point`:`node_id_1`]
    - [`point`:`node_id_2`]
    - [`point`:`bitcoin_key_1`]
    - [`point`:`bitcoin_key_2`]

## The `node_announcement` Message

1. type: 257 (`node_announcement`)
2. data:

   * [ `signature` : `signature` ]
   * [ `u16` : `flen` ]
   * [ `flen*byte` : `features` ]
   * [ `u32` : `timestamp` ]
   * [ `point` : `node_id` ]
   * [ `3*byte` : `rgb_color` ]
   * [ `32*byte` : `alias` ]
   * [ `u16` : `addrlen` ]
   * [ `addrlen*byte` : `addresses` ]
   

## The `channel_update` Message

1. type: 258 (`channel_update`)
2. data:
    - [`signature`:`signature`]
    - [`chain_hash`:`chain_hash`]
    - [`short_channel_id`:`short_channel_id`]
    - [`u32`:`timestamp`]
    - [`byte`:`message_flags`]
    - [`byte`:`channel_flags`]
    - [`u16`:`cltv_expiry_delta`]
    - [`u64`:`htlc_minimum_msat`]
    - [`u32`:`fee_base_msat`]
    - [`u32`:`fee_proportional_millionths`]
    - [`u64`:`htlc_maximum_msat`] (option_channel_htlc_max)

# Single-hop

## Establishment

### The `open_channel` Message

1. type: 32 (`open_channel`)
2. data:

   * [ `chain_hash` : `chain_hash` ]
   * [ `32*byte` : `temporary_channel_id` ]
   * [ `u64` : `funding_satoshis` ] <font color=yellow> multi-asset.</font>
   * [ `u64` : `push_msat` ] <font color=red> bilateral funding.</font>
   * [ `u64` : `dust_limit_satoshis` ] <font color=red> About the dust problem. In my option, this problem will not happen in CKB.</font>
   * [ `u64` : `max_htlc_value_in_flight_msat` ]
   * [ `u64` : `channel_reserve_satoshis` ] <font color=red> Only in RSMC. </font>
   * [ `u64` : `htlc_minimum_msat` ] 
   * [ `u32` : `feerate_per_kw` ] <font color=red> Not sure, it depends on the fee mechanism in CKB. </font>
   * [ `u16` : `to_self_delay` ] <font color=red> Only in RSMC. </font>
   * [ `u16` : `max_accepted_htlcs` ]
   * [ `point` : `funding_pubkey` ] 
   * [ `point` : `revocation_basepoint` ] <font color=red> Only in RSMC. </font>
   * [ `point` : `payment_basepoint` ] <font color=red> Not sure. </font>
   * [ `point` : `delayed_payment_basepoint` ] <font color=red> Only in RSMC. </font>
   * [ `point` : `htlc_basepoint` ] <font color=red> Not sure, is it necessary to use different key in HTLCs? </font>
   * [ `point` : `first_per_commitment_point` ] <font color=red> Only in RMSC. </font>
   * [ `byte` : `channel_flags` ] 
   * [ `open_channel_tlvs` : `tlvs` ]
   * [ `u16` : `challenge_period` ] <font color=green> For GPC. </font>
   * [ `u16` : `fee` ] <font color=green> For GPC, it depends on the fee mechanism in ckb.</font>
   * [ `input[]` : `funding_cells` ] <font color=green> For GPC. </font>
   * [ `output[]` : `change_outputs` ] <font color=green> For GPC. </font>

   * [ `output[]` : `settlement_output` ] <font color=green> For GPC. </font>
   * [ `output_data[]` : `settlement_output_data` ] <font color=green> For GPC. </font>
   * [ `witness[]` : `settlement_witness` ] <font color=green> For GPC. </font>

### The `accept_channel` Message

1. type: 33 (`accept_channel`)
2. data:

   * [ `32*byte` : `temporary_channel_id` ] <font color=yellow> Here we have the right id.</font>
   * [ `u64` : `max_htlc_value_in_flight_ckbytes` ]
   * [ `u32` : `minimum_depth` ]
   * [ `u16` : `max_accepted_htlcs` ]
   * [ `point` : `funding_pubkey` ]
   * [ `accept_channel_tlvs` : `tlvs` ]
   * [ `hash` : `funding` ] <font color=green> multi-asset.</font>
   * [ `tx` : `funding_tx` ] <font color=green> For GPC. </font>
   * [ `output[]` : `settlement_output` ] <font color=green> For GPC. </font>
   * [ `output_data[]` : `settlement_output_data` ] <font color=green> For GPC. </font>
   * [ `witness[]` : `settlement_witnesses` ] <font color=green> For GPC. </font>
   * [ `u16` : `fee` ] <font color=green> For GPC, it depends on the fee mechanism in ckb.</font>
   * [ `point` : `funding_pubkey` ] <font color=green> For GPC. </font>

### The `commitment_exchange` Message

1. type: 34 (`commitment_exchange`)
2. data:

   * [ `32*byte` : `channel_id` ] 
   * [ `output[]` : `closing_outputs` ] 
   * [ `output_data[]` : `closing_outputs_data` ] 
   * [ `witness[]` : `closing_witness` ] 
   * [ `output[]` : `settlement_outputs` ] 
   * [ `output_data[]` : `settlement_outputs_data` ] 
   * [ `witness[]` : `settlement_witness` ] 

### The `funding_signed` Message

1. type: 35 (`funding_signed`)
2. data:

   * [ `32*byte` : `channel_id` ] 
   * [ `tx` : `funding tx` ] 

## make_payment

### Committing Updates So Far: `settlement_signed`

1. type: 132 (`settlement_signed`)
2. data:

   * [ `channel_id` : `channel_id` ]
   * [ `signature` : `signature` ] <font color=yellow> the settlement transaction and signatures. </font>
   * [ `u16` : `num_htlcs` ] <font color=red> Can be removed, we do not need signature about htlc in GPC. </font>
   * [ `num_htlcs*signature` : `htlc_signature` ] <font color=red> Can be removed, we do not need signature about htlc in GPC. </font>
   * [ `output[]` : `settlement_outputs` ] 
   * [ `output_data[]` : `settlement_outputs_data` ] 
   * [ `witness[]` : `settlement_witness` ] 

### Completing the Transition to the Updated State: `closing_signed`

1. type: 133 (`closing_signed`)
2. data:

   * [ `channel_id` : `channel_id` ]
   * [ `outputs[]` : `closing_output` ]
   * [ `output_data[]` : `closing_output_data` ]
   * [ `witness[]` : `closing_witneses` ]

## closing_channel

### Closing initialization: `shutdown`

1. type: 38 (`shutdown`)
2. data:

   * [ `channel_id` : `channel_id` ]
   * [ `u16` : `len` ] 
   * [ `len*byte` : `scriptpubkey` ]

### Closing Negotiation: `closing_signed`

1. type: 39 (`closing_signed`)
2. data:

   * [ `channel_id` : `channel_id` ]
   * [ `u64` : `fee_satoshis` ] <font color=red> Both user needs to pay the fee. </font>
   * [ `u64` : `local_fee` ] <font color=green> local fee. </font>
   * [ `u64` : `remote_fee` ] <font color=green> remote fee. </font>
   * [ `tx` : `settlement_tx` ]
   

# Multi-hop

### Adding an HTLC: `update_add_htlc`

1. type: 128 (`update_add_htlc`)
2. data:

   * [ `channel_id` : `channel_id` ]
   * [ `u64` : `id` ]
   * [ `u64` : `amount_msat` ]
   * [ `sha256` : `payment_hash` ]
   * [ `u32` : `cltv_expiry` ]
   * [ `1366*byte` : `onion_routing_packet` ]

### Removing an HTLC: `update_fulfill_htlc` , `update_fail_htlc` , and `update_fail_malformed_htlc`

1. type: 130 (`update_fulfill_htlc`)
2. data:

   * [ `channel_id` : `channel_id` ] 
   * [ `u64` : `id` ] Monotonically Incremental HTLC Sequences.
   * [ `32*byte` : `payment_preimage` ]

1. type: 131 (`update_fail_htlc`)
2. data:

   * [ `channel_id` : `channel_id` ]
   * [ `u64` : `id` ]
   * [ `u16` : `len` ]
   * [ `len*byte` : `reason` ]

1. type: 135 (`update_fail_malformed_htlc`)
2. data:

   * [ `channel_id` : `channel_id` ]
   * [ `u64` : `id` ]
   * [ `sha256` : `sha256_of_onion` ]
   * [ `u16` : `failure_code` ]

### Committing Updates So Far: `settlement_signed`

1. type: 132 (`settlement_signed`)
2. data:

   * [ `channel_id` : `channel_id` ]
   * [ `signature` : `signature` ] <font color=yellow> the settlement transaction and signatures. </font>
   * [ `u16` : `num_htlcs` ] <font color=red> Can be removed, we do not need signature about htlc in GPC. </font>
   * [ `num_htlcs*signature` : `htlc_signature` ] <font color=red> Can be removed, we do not need signature about htlc in GPC. </font>
   * [ `output[]` : `settlement_outputs` ] 
   * [ `output_data[]` : `settlement_outputs_data` ] 
   * [ `witness[]` : `settlement_witness` ] 

### Completing the Transition to the Updated State: `closing_signed`

1. type: 133 (`closing_signed`)
2. data:

   * [ `channel_id` : `channel_id` ]
   * [ `outputs[]` : `closing_output` ]
   * [ `output_data[]` : `closing_output_data` ]
   * [ `witness[]` : `closing_witneses` ]

### CLTV

cltv_expiry_delta: 3R+2G+2S
min_final_cltv_expiry: 2R+G+S
`R` : reorganization depth, 2 in btc.
`G` : Grace period, 2 in LN.
`S` : blocks between transaction broadcast and the transaction being included in a block. 12 in LN.

# Watch tower

#### TODO

1. About fee mechanism and how to negotiate the funding fee.
2. Should we use multiple pubkey?
3. HTLC dust? (any-one-can-pay)
4. retransmission mechanism
5. About one-shot GPC.
6. About the mempool replacement.
