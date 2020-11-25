This article explores the possibility of building HTLC contracts on CKB.

# Basic HTLC

HTLC is, in a nutshell, a smart contract with two ways to unlock it.

1. The payer unlocks the cell after a certain block height.
2. The payee unlocks the cell with the preimage of a specific hash.

## Construction

We can do both of these by putting `Timelock` and `Hash` into the `outputs_data` of the cell. So, we can get the data structure of HTLC cell as follows

``` 

Lock.args:
<Pubkey_payer> <Pubkey_payee> <Timeout> <Hash of preiamge>
Witness.lock 
<Flag> <Signature>
<Flag> <Signature> <preimage>
```

`Flag` indicates which way the signer chose to unlock this cell. For payment, the payee add the preimage to the `witness` . For refunding, the contract will require `since` of refund transaction is equals to `Timelock` in the `args` .

However, you can easily find the flaw in this solution, it doesn't support micro-payments. This is because CKB cells must have at least 61 CKBytes.

# Fused HTLC

I had the [idea](https://talk.nervos.org/t/idea-about-the-composability-of-assets-in-ckb/4855) of fusing the cells together before, so the second version is to use `outputs_data` to fuse all the HTLCs together to solve the CKB minimum cell size limitation. So we can get the following data structure.

``` 

Lock.args:
<Pubkey_payer1> <Pubkey_payee1> <Timeout1> <Hash of preiamge1> <Payment asset class1> <Payment amount1> 
<Pubkey_payer2> <Pubkey_payee2> <Timeout2> <Hash of preiamge2> <Payment asset class2> <Payment amount2> 
...
Witness.lock 
<Flag> <HTLC_index> <Signature>
<Flag> <HTLC_index> <Signature> <preimage>
```

In short, every HTLC payment is put into output_data. At this point, the contract looks for the corresponding HTLC based on the `HTLC_index` provided by the user and checks if the unlock logic is correct. Nevertheless, this scheme has the state sharing problem, when both Alice and Bob try to unlock two different HTLCs, only one will succeed.

# Fused HTLC with state sharing

Inspired by [Hydra](https://eprint.iacr.org/2020/299.pdf), I have found that some blockchain applications with specific deadlines are able to share state. For example, voting. The principle is as follows.

1. All users first agree to create a `teller` UTXO.
2. Users make transactions on their UTXOs into a form that conforms to the voting specifications.
3. After the deadline, the user creates a transaction with all votes UTXOs and teller UTXO as inputs. The transaction will count how many valid votes will be entered in the UTXOs.

Similarly, we can apply it to the HTLC scenario. 

1. Two users will submit the fused HTLC cell between them.
2. The party that owns the Preimage adds the corresponding unlock information to its cells.
3. After the HTLC fused cells expire (the latest deadline of HTLCs), the user submits the proof that he has submitted the preimage before the deadline to unlock the corresponding HTLC. Please note that the **proof cell** here does not need to be live. We only need to prove that this record existed in the chain before the deadline.

That's how it works. Next, I'd like to take a few questions and answers to explain its principles in more detail.

## How to ensure that payer will display Preimage before the deadline?

In fact, we can prove that this record existed in the chain before the block height by putting some merkle proof in the `witness` of the transaction that finally unlocks the HTLC. Specifically, we need to put in the transaction that created the **Proof cell** and its Merkle proof that it is created in a specific block, and then put the hash of the corresponding block into `header_dep`. The contract checks to see if the block is before the corresponding HTLC deadline. If the proof fails, he cannot take the money from the HTLC.

## How does payer get refunds?

The fused HTLC cells will have two marker deadlines.

1. Payee's payment date, which is equal to the latest HTLC cutoff date in the cells. This is to ensure that all proofs submitted after this date are invalid.

2. Payer's refund date, which needs to be slightly later than the first date. After that, payer can take all unlocked HTLCs.

This design ensures that payee gets all the money that belongs to him, and that payee is guaranteed a refund.

## What if there are bidirectional HTLCs?

There are two possible solutions to this.

1. Use two cells to separate them: Cell A holds only A -> B HTLCs and Cells B holds only B -> A HTLCs.
2. Adopt more complex payment mechanisms. I'm not thinking in this direction, but maybe settle A->B HTLCs first, then settle B->A.

## Does this proposal really reduce the CKBytes that need to be locked up?

The answer is yes.

1. HTLCs can share a single container.
2. Proof cells only need to be submitted before deadline. Then you can spend it.

Of course, he also has some drawbacks.

1. All funds can not be withdrawn until the latest HTLC expires.
2. To perform merle tree validation, the corresponding block must be mature (after four epochs).

But on the whole, I think the proposal works.

## How do I listen to the corresponding Proof cell？

I suggest requiring the locks in **proof cell** must equals to the payee's lock in Fused HTLCs cells. This way the user can get preimage information by listening to the cell corresponding to the lock.
