# Gather_input_udt_test

In the UDT test, each case is divided into 1_stages and 2_stages, which is related to our gather_input scheme. The scheme has two stage

1. Collection of assets.
2. Check if the capacity of the collected cells is enough for the container and the fee, if not, then collect fee cells. Otherwise, just return the inputs from step 1.

To cover all the paths, so I've tested all the cases here in two stages. You may wonder why I didn't have two-stage test in CKB. On the one hand, I think the CKB and UDT tests on this are duplicative, so I only need to choose one version for the two-stage test. On the other hand, the UDT version is much easier to do this test with. For example, I want to simulate the following scenario.

**The user collects enough cells in the first stage to fund, but not enough to pay container and fee, so the second phase of collection is initiated at this point.**

Since there is only one cell in the CKB asset owned by the user in the CKB, I need to slice it and then experiment with it. But in the UDT version things are easy, I just need to set the amount to 20. At this point I've only collected 1 cell, and it has a capacity of 134 ckbytes, which is clearly not enough to pay for container and fee.