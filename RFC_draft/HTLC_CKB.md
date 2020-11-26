This article explores the possibility of building HTLC contracts on CKB.

[toc]

# Basic HTLC

HTLC is, in a nutshell, a smart contract with two ways to unlock it.

1. The payer unlocks the cell after a certain block height.
2. The payee unlocks the cell with the preimage of a specific hash.

## Construction

We can do both of these by putting `Timelock` and `Hash` into the `lock.args` of the cell. So, we can get the data structure of HTLC cell as follows

``` 

lock.args:
    <Pubkey_payer> <Pubkey_payee> <Timeout> <Hash of preimage>
Witnesses
    <Flag> <Signature>
    <Flag> <Signature> <preimage>
```

`Flag` indicates which way the signer chose to unlock this cell. For payment, the payee add the preimage to the `witness`. For refunding, the contract will require `since` of refund transaction is equals to `Timelock` in the `args`.

However, you can easily find the flaw in this solution, it doesn't support micro-payments. This is because CKB cells must have at least 61 CKBytes.

# Fused HTLC

I had the [idea](https://talk.nervos.org/t/idea-about-the-composability-of-assets-in-ckb/4855) of fusing the cells together before, so the second version is to use `outputs_data` to fuse all the HTLCs together to solve the CKB minimum cell size limitation. So we can get the following data structure.

``` 

capacity: capacity
lock script: 
	code_hash: <HTLC>  
	hash_type: type 
	args: 
          <Pubkey_payer> <Pubkey_payee> 
          <Timeout1> <Hash of preimage1> 
          <Timeout2> <Hash of preimage2> 
          ...
type script: <Collector type>  
data:{
    <Payment type1> <Payment amount1> 
    <Payment type2> <Payment amount2> 
}

Witnesses
<Flag> <HTLC_index> <Signature>
<Flag> <HTLC_index> <Signature> <preimage>
```

In short, every HTLC payment is split into two parts. `lock.args` stores the information needed for unlocking, while `output_data` stores the type and amount of assets to be unlocked. At this point, the contract looks for the corresponding HTLC based on the `HTLC_index` provided by the user and checks if the unlock logic is correct. Nevertheless, this scheme has the state sharing problem, when both Alice and Bob try to unlock two different HTLCs, only one will succeed.

# Fused HTLC with state sharing

Inspired by [Hydra](https://eprint.iacr.org/2020/299.pdf), I have found that some blockchain applications with specific deadlines can share state. For example, voting. The principle is as follows.

1. All users first agree to create a `teller` UTXO.
2. Users make transactions on their UTXOs into a form that conforms to the voting specifications.
3. After the deadline, the user creates a transaction with all votes UTXOs and teller UTXO as inputs. The transaction will count how many valid votes will be entered in the UTXOs.

Similarly, we can apply it to the HTLC scenario. 

1. Two users will submit the fused HTLC cell between them.
2. The party that owns the Preimage adds the corresponding unlock information to its cells before this HTLC deadline.
3. After the HTLC fused cells expire (the latest deadline of HTLCs), the user submits the proof that he has submitted the preimage before the deadline to unlock the corresponding HTLC. Please note that the **proof cell** here does not need to be live. We only need to prove that this record existed in the chain before the deadline.

That's how it works. Next, I'd like give a example to illustrate it.

## Example

Suppose Alice wants to pay Bob 10 CKB, 15 UDT1 and 20 UDT2. Expiration times are 200, 250, and 300 blocks height, respectively. Also, let's assume that both UDT allow the special type script I mentioned in the [idea](https://talk.nervos.org/t/idea-about-the-composability-of-assets-in-ckb/4855) to create and destroy their UDTs. For the simplicity, I start with the settlement phase of GPC have completed, while the Fused HTLC cell is on the chain and alive. Also, I assume that the minimum CKB required for the current cell is 100 CKBytes.

### The structure of fused HTLCs cell

``` 
Current block height: 150

capacity: 110
lock script: 
	code_hash: <HTLC>  
	hash_type: type 
	args: <Alice's pubkey> <Bob's pubkey> 
          <200> <H1> 
          <250> <H2> 
          <300> <H3> 
type script: <Collector type>  
data:{
    <32 * "0">         <10> 
    <UDT1's type hash> <UDT1_ENCODER(15)> 
    <UDT2's type hash> <UDT2_ENCODER(20)> 
}
```
1. 32 * "0" represents this asset is CKB.
2. `<UDT1_ENCODER(15)>` means it follows the rules of the corresponding type script. For example, if a type script specifies that the first 8 bytes of `output_data` represent an amount. Then the `<UDT1_ENCODER(15)>` here needs to occupy 8 bytes.

### The structure of proof cell

After that, the user simply sends a transaction to modify the data in the `output_data` before the corresponding block height as follows.

``` 
Current block height: 190

capacity: 110
lock script: Bob's secp lock
type script: nil
data:{
    1 && p1
    2 && p2
    3 && p3
}
```


`1` is the indexer and `p1` is preimage of `h1`. Please note that here I have submitted all preimages at once for simplicity. In practice, you may not be able to gather them all at the same time. For example, you might receive p3 at 260 blocks, then you should submit p1 and p2 proofs before that to ensure the proof is valid. 

``` 
Current block height: 190

capacity: 110
lock script: Bob's secp lock
type script: nil
data:{
    1 && p1
    2 && p2
}


----------------------------


Current block height: 260

capacity: 110
lock script: Bob's secp lock
type script: nil
data:{
    3 && p3
}
```

At the same time, we call the corresponding transaction **T**, the block containing **T** are called **B**. After committing, the user can clear the data from the cell after the on-chain confirmation period. 



### The structure of payment transaction

When the block height reaches 200, the user can redeem his money by proving 

``` 
Current block height: 201

Inputs:
    HTLCs Cell:
        capacity: 110
        lock script: 
            code_hash: <HTLC>  
            hash_type: type 
            args: <Alice's pubkey> <Bob's pubkey> 
                <200> <H1> 
                <250> <H2> 
                <300> <H3> 
        type script: <Collector type>  
        data:{
            <32 * "0">         <10> 
            <UDT1's type hash> <UDT1_ENCODER(15)> 
            <UDT2's type hash> <UDT2_ENCODER(20)> 
        }
    Container cell:
        capacity: 500
        lock script: Bob's secp lock
        type script: nil
        data{
            "0x"
        }
Outputs:
    CKB cell:
        capacity: 71
        lock script: Bob's secp lock
        type script: nil
        data{
            "0x"
        }    
    UDT1 cell:
        capacity: 100
        lock script: Bob's secp lock
        type script: UDT1 type script
        data{
            <UDT1_ENCODER(15)> 
        }
    UDT2 cell:
        capacity: 100
        lock script: Bob's secp lock
        type script: UDT2 type script
        data{
            <UDT2_ENCODER(20)> 
        }
    change cell:
        capacity: 228
        lock script: Bob's secp lock
        type script: nil
        data{
            "0x"
        }
Witnesses
    <The proof transaction T> <Merkle proof that T is in B> <Signature>
    <Signature> 
```

Here, Bob proves the existence of the corresponding **proof transaction** in `witnesses`. At the same time, we put the hash corresponding to **B** in the `head_deps` so that the HTLC script can verify that the block height where **B** is generated satisfies the requirement. The refund transaction is similar to this one, except that Alice have to wait a little longer and without any proof. This means that if Bob fails to submit the appropriate proof, Alice can take all the left money.

# Discussion

# Pros and cons

Pros:

1. HTLCs can share a single container.
2. User can make proof concurrently (state sharing).

Cons

1. All funds can not be withdrawn until the latest HTLC expires.
2. To perform merle tree validation, the corresponding block **B** must be mature (after four epochs).
3. If there are multiple **proof transaction**, the size of payment transaction will be massive.
## How does payer get refunds?

The fused HTLC cells will have two marker deadlines.

1. Payee's payment date, which is equal to the latest HTLC cutoff date in the cells. This is to ensure that all proofs submitted after this date are invalid.

2. Payer's refund date, which needs to be slightly later than the first date. After that, payer can take all unlocked HTLCs.

This design ensures that payee gets all the money that belongs to him, and that payee is guaranteed a refund.

## What if there are bidirectional HTLCs?

There are two possible solutions to this.

1. Use two cells to separate them: Cell A holds only A -> B HTLCs and Cells B holds only B -> A HTLCs.
2. Adopt more complex payment mechanisms. I'm not thinking in this direction, but maybe settle A->B HTLCs first, then settle B->A.


## Future work

We can use the merkle tree to consolidate the corresponding HTLC entries so that the storage of the Fused HTLC cell will be O(1). Thus, we can also break the Concurrent_HTLCs due to the transaction size. However, it will result in a swollen **proof transaction**. 