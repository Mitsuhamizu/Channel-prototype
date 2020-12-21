This post discusses the problem about locking time in multi-hop payments. First of all, many thanks to @janx, @doitian, @thewawar and @driftluo for their help and feedback on this problem.

# Introduction

HTLC is a contract between two parties (Alice and Bob, for example), which has the following logic. Alice offers 100 CKBytes and tells Bob, "if you can tell me the preimage of the hash value **H** before the block height 100, then you can take the money. Otherwise, the money will be refunded". HTLC is utilized by many blockchain applications, what I will discuss in this post is its role in multi-hop payments. You can find how it works [here](https://github.com/bitcoinbook/bitcoinbook/blob/develop/ch12.asciidoc).

# Problem statement

I know at this point the HTLC in your mind must look like this: Bob can take the money with preimage before the HTLC expires. Otherwise, the money belongs to Alice. However, the story is quite different in BTC. Let's think about how to implement this contract (script)? Suppose that the expiration time of HTLC is **E**, the hash value is **H** and the preimage is **P**. Then the unlocking condition of this cell (UTXO) should be

1. Bob shows **P** before **E**.
2. Alice refunds after **E**.

So, we need the following three functionalities in the contract.

1. Check **P**.
2. Prevent Alice from getting the refund *before* **E**.
3. Prevent Bob from submitting the preimage *after* **E**.

The first one can be achieved by any script language with *if* logic and *hash* function. The second one can be achieved by `since` in CKB or `nounce` in BTC, but how about the third one? The third functionality is a mechanism called `until`. AFAIK, there is no such mechanism in BTC, which means Bob can still unlock the funds through preimage after the expiration date.

Let's pause the discussion for a moment and talk about how multi-hop payments work in Lightning Network. We assume that Alice pays Carol through Bob, and the corresponding HTLC expiration block heights are **$E_{AB}$** and **$E_{BC}$**, respectively. Also, we assume that a transaction takes **$\Delta$** blocks from being broadcast to being on-chain and confirmed. We suppose the deadline of **$HTLC_{BC}$** is reached, and both Bob and Carol intend to unlock **$HTLC_{BC}$**. Note that the `until` mechanism is lacking in this setting, so Carol can unlock **$HTLC_{BC}$** by submitting the preimage after the deadline.

* At **$E_{BC}$**
* **action**: Bob submits refund transactions **$Tx^{refund}_{BC}$**.
* **action**: Carol shows **P** and trys to get the payments in **$Tx^{payment}_{BC}$**.

Unfortunately, Carol's transaction goes up first. But the good news is that Bob now knows the preimage, so he can use it to unlock **$HTLC_{AB}$**.

* At **$E_{BC}+\Delta$**
* **result of last step**: **$Tx^{payment}_{BC}$** wins.
* **action**: Bob knows **P** from blockchain and trys to get the payments in **$Tx^{payment}_{AB}$**.

**$Tx^{payment}_{AB}$** is on-chain.

* At **$E_{BC}+2\Delta$**
* **result of last step**: **$Tx^{payment}_{AB}$** wins.

At this point, we know that Bob will get paid until **$E_{BC}+2\Delta$** in the worst case. Therefore, we can get the following inequality

**$$E_{AB} \geq E_{BC}+2\Delta$$**

In brief, we stop Alice from initiating a refund before Bob can get the payment with preimage. And this can occur at every hop so that the expiration block height is incremental with the number of hops reversely (1st hop has the latest expiry time). If we consider the lock time in the last hop as **$2\Delta$** too, then the sum of multi-hop payment locking time in LN of length **$N$** is 

**$$L_{sum}=2\Delta+4\Delta+...+2N\Delta$$**

To make the problem easier to understand, I have omitted some details in the above description. What I want to convey is the complexity of **$L_{sum}$** is **$O(N^2)$** in multi-hop payment in Lightning Network. Then we will discuss how to **reduce it to **$O(N)$** on ckb in the remainder of the post.**

Fortunately, we can support [until mechanism](https://talk.nervos.org/t/htlc-in-ckb/5062) on CKB thanks to its powerful programmability. In a nutshell, users can add preimage to their own cell first, then use it as `cell_deps` in the HTLC unlocking transaction. Meanwhile, he should add the hash of block that generates the cell in `header_deps` . At this point, we ask the script to read the block header and verify the block height is before the deadline. From this, we can make actions valid only before a certain block height. 

Okay, now that we have the `until` mechanism, is the problem solved? The answer is no. Following the example above, but with the difference that we now have the `until` mechanism and an extra hop in the path, i.e. the scenario is Alice paying Dave (A->B->C->D). Here we assume that the expiration time **$E$** is the same for each hop. Then for Dave, if he wants to get this payment, he needs to submit the preimage before **$N-\Delta$** to ensure it will be on-chain before **$E$**. And Bob is asked to do the same because they have the same expiration date. However, Bob knows nothing about preimage at **$N-\Delta$**. There are two solutions to this problem

1. Make the act that Dave submitting the preimage able to affect every hops in the path.
2. Let all nodes on the path listen the public zone (blockchain, mempool for example).

[Sprites](https://arxiv.org/pdf/1702.05812.pdf) adopts the former, and I will discuss how it works in the next section.

# Sprites

Sprites is an Ether-based multi-hop payment solution that consist of two contracts **$contract_{htlc}$** and **$contract_{pm}$** (preimage manager). The former is an HTLC contract, but the difference is that it works by asking **$contract_{pm}$** to determine the outcome. The latter is a preimage manager, which provides two interfaces

1. **function submitPreimage(bytes32 x)**
2. **function revealedBefore(bytes32 h, uint T) returns(bool)**

**$submitPreimage$** allows the user to submit a preimage **$P$** and store it as dictionary {**$H$**: **$T$**}, where **$H$** is the hash of **$P$** and **$T$** is the block number containing the transaction. The logic of until is implied here, that is, if the user submits a preimage after the expiration date, the block height being recorded will not meet the requirements. **$revealedBefore$** provides a query interface to **$contract_{htlc}$**, returns true if the preimage of **$H$** was committed before **$T$**, false otherwise.

Now, let's go back to the payment scenarios. Likewise, Dave submits the preimage to **$contract_{pm}$** before **$E-\Delta$** and the transaction is on-chain before **$E$**. Now, Bob can initiate a dispute in **$contract_{htlc}^{AB}$** without knowing the preimage, because Dave's behaviour affects all HTLCs with preimage **$P$** through a globally shared **$contract_{pm}$**.

Now, you might think that global sharing is the key to achieving constant lock time, but I would like to give an example to illustrate the importance of `until`. Let's assume Sprite without the `until` mechanism. it's simple, we just need to remove the block num when submitting the preimage. In other words, the **$revealedBefore$** only looks for the existence of the corresponding hash without paying attention to when it was committed. Now let's still assume the scenario where Alice pays Carol. The expiration time **$E$** has now been reached. Alice and Bob both initiate disputed transactions **$Tx_{AB}$** and **$Tx_{BC}$**, Carol submits the preimage transaction **$Tx_{preimage}$**. At this point all three transactions can be accepted by the blockchain, a possible order is.

1. **$Tx_{AB}$**
2. **$Tx_{preimage}$**
3. **$Tx_{BC}$**

Since the preimage had not been submitted at the time, **$Tx_{AB}$** ended up with a refund, i.e., Alice got money. However, **$Tx_{BC}$** had succeeded because the preimage has been revealed (Carol got coins). At this point, Bob suffered a loss. Thus a pair of conscious nodes can use this to scam money. A good protocol should not have the possibility of rational nodes losing money. Therefore, the `until` mechanism is essential.

# Story in CKB

[Sprites](https://arxiv.org/pdf/1702.05812.pdf) relies on a globally shared contract, the simplest equivalence is **$cell_{pm}$**. However, there would be the state sharing problem. First, collisions occur when two users want to submit preimages with the same **$cell_{pm}$** as input. Secondly, when I want to unlock HTLC with **$cell_{pm}$** as a `cell_dep` , someone else may change it too.

So I'm thinking of another direction, having nodes on the path look for the [proof cell](https://talk.nervos.org/t/htlc-in-ckb/5062) on-chain and use it to unlock their HTLC. Specifically, if Dave submits a proof cell before **$E-\Delta$**, then all nodes can see it after **$E$**, then both Bob and Carol can utilize it to unlock the corresponding HTLCs. 

However, there are two concerns about this solution. First, the cell in `cell_deps` must be live. How can we ensure the proof cell is live when Bob and Carol want to use it? Second, after HTLC expires, one party can take the proof cell to get the payment, but the other party can initiate a refund. How to solve this conflict?

For the first concern, we use time lock. The lock script of proof cell is 

``` 
lock.args:
    <owner's pubkey> <htlc_expire_date> <grace_period> 
Witnesses
    <Signature>
```

First, we will require expiration date in HTLC cell must be consistent with `htlc_expire_date` field of the proof_cell. Second, we will require that the proof cell cannot be unlocked before `htlc_expire_date`+`grace_period`, where `grace_period` is utilized to allow other nodes on the same path to unlock their payments. At this point, we ensure that each node has enough time to use the proof cell to unlock their payment.

For the second problem, I prefer to call it **proof of absence**. That is, how do we go about proving on the blockchain that something didn't happen? A naive solution is that we first let one party give the **proof of attendance**. If it is not provided within this period, then **absence is proved**. In HTLC, we allow Bob to unlock **$HTLC_{AB}$** after **$E$** by providing proof cell in `cell_deps`. Then, we allow Alice to unlock **$HTLC_{AB}$** unconditionally after **$E+grace\_period$**. 

# Discussion

In a nutshell, this post discusses the locking time of multi-hop payments. Specifically, I elaborate on the problem, introducing the Ether-based Sprites and the proof cell on CKB. Next, I would like to discuss the pros and cons of these two solutions.

## Atomicity

As with many Layer 2 designs, I introduce grace period (challenge period) at the time of final settlement of HTLC in proof cell. Thus, the atomicity of multi-hop payments may be broken when the network has a traffic jam. But I've recently seen very interesting [discussions](https://ethresear.ch/t/extending-proof-deadlines-during-chain-congestion/84) about elastic challenge periods. In short, it means that the challenge period will be extended when the network is congested. This effectively mitigates the risk of losing funding due to network congestion.

There is no doubt that Sprites excels in atomicity. Neither party needs to worry about the other cheating because the outcome of the dispute is strongly dependent on **$contract_{pm}$**. In the meantime, the contract has irreversibility. The results of the HTLC are determined and can not be modified after the deadline.

If you want to improve the atomicity of the proof cell, I highly recommend that you think about the following two questions.

1. How to efficiently prove the non-existence of proof cell?
2. How to achieve the elastic challenge period on CKB?

## Capacity cost

As I discussed above, Sprites must have irreversibility. Then when we want to port Sprites to CKB, the capacity required by **$cell_{pm}$** will keep growing. You may ask, "Well, can we clean the **$cell_pm$** regularly?" From my perspective, the answer is no.

If you choose to clean up regularly, that's actually adding a challenge period. You are telling the user: "Please come and reference this contract before I clean it up or you won't find the record you need for dispute". So a simple thought, can I wait until all the HTLC disputes that require this preimage have been processed and then clean it up? Unfortunately, not all users are willing to settle disputes on-chain. Because it means they need to close the channel between them. So you will most likely not be able to collect a complete dispute record. On the contrary, proof cell is economical in terms of the cost it requires. All proof cells need to be locked only during the grace period, and users can spend them after that. 

Therefore, if you wish to implement Sprites in CKB, then I suggest you think about the following two questions.

1. How to solve the state sharing problem?
2. How do you address the continued growth in space occupation that Sprites bring?

If you have any idea about the above mentioned open challenges, don't hesitate to PM me. Also, any comments are welcome.