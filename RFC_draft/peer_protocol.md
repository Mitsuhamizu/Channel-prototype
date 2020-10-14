Message format

1. `type` : a 2-byte big-endian field indicating the type of message
2. `payload` : a variable-length payload that comprises the remainder of
   the message and that conforms to a format matching the `type`
3. `extension` : an optional [TLV stream](#type-length-value-format)

The messages are grouped logically into five groups, ordered by the most significant bit that is set:

  - Setup & Control (types `0`-`31`): messages related to connection setup, control, supported features, and error reporting (described below)
  - Channel (types `32`-`127`): messages used to setup and tear down micropayment channels (described in [BOLT #2](02-peer-protocol.md))
  - Commitment (types `128`-`255`): messages related to updating the current commitment transaction, which includes adding, revoking, and settling HTLCs as well as updating fees and exchanging signatures (described in [BOLT #2](02-peer-protocol.md))
  - Routing (types `256`-`511`): messages containing node and channel announcements, as well as any active route exploration (described in [BOLT #7](07-routing-gossip.md))
  - Custom (types `32768`-`65535`): experimental and application-specific messages

  