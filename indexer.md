This article indexes some of the information currently available about the CKB channel.

# Current docs

[Outline](https://hackmd.io/crQnHgBJQcK4sG3984bWSA) (In progress)

[Initial Design of GPC](https://talk.nervos.org/t/a-generic-payment-channel-construction-and-its-composability/4697) (done)

[Implementation](https://github.com/ZhichunLu-11/Channel-prototype) (done but lacking "one-shot" mechanism.)

[Discussion about container about HTLC](https://talk.nervos.org/t/a-discussion-on-container-capacity-of-multi-hop-payment-in-payment-channel-network/5062) (In progress)

[Discussion about lock time about HTLC](https://talk.nervos.org/t/a-discussion-on-lock-time-of-multi-hop-payment-in-payment-channel-network/5124) (In progress)

[GPC demo](https://github.com/ZhichunLu-11/channel_demo_tg_msg_sender) (done)

[Engineering Design](https://hackmd.io/sDg38T-nRYemk5zaUhGFNQ) (In progress)

# TO-DO list

* Find a good HTLC design.
* Routing algorithm.
    * [lnd's routing alg](https://www.youtube.com/watch?v=p8toOF-imk4&ab_channel=JoostJager) with reliability.
* Watch tower
    * Introduction about watchtower in LND.
        * [video](https://www.youtube.com/watch?v=2tyr05tLF4g&ab_channel=Bolt-A-Thon)
        * [text](http://diyhpl.us/wiki/transcripts/boltathon/2019-04-06-conner-fromknecht-watchtowers/)
    * discussion from Lightning lab co-founder.
        * [text](https://diyhpl.us/wiki/transcripts/blockchain-protocol-analysis-security-engineering/2018/hardening-lightning/)
    * eltoo watchtower
        * [text](https://lists.linuxfoundation.org/pipermail/lightning-dev/2018-May/001264.html)
    * [pisa](https://eprint.iacr.org/2018/582.pdf)
    