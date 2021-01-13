# Optimized PCIe TLP Mapping

Mapping a memory interface to the PCIe TLP AXI-stream interface is surprisingly complicated. Simple arbitration of an AFU's host channel read and write request streams is legal, but bandwidth allocation is dramatically skewed in favor of write traffic. The cause:

* Read requests require completion tags, used to match out-of-order read responses to requests. Enough tags are made available so that the number of read requests in flight achieves maximum bus bandwidth. The number of tags is not enough to emit a read request every cycle. That would require a needlessly large tag space. As a consequence, the AFU must stop generating TLP read requests when tags are unavailable, forcing the AFU read request stream to block.
* Write requests have no tags. The only limit on the rate at which an AFU generates TLP write requests is the ready signal from the FIM.
* In the simple arbitration case, the TLP stream contains only write requests once read tags are exhausted. The AFU will pump write requests into the TLP stream until the FIM's PCIe request stream fills and the ready signal is deasserted. Each time that read requests are blocked, the FIM pipeline is filled with write requests, enabling far more write than read requests. The difference in read to write traffic is 1:4, or worse, on some hardware.

The memory interface to PCIe TLP mapper here adds logic for fair arbitration of read and write traffic by throttling write requests in order to avoid filling the request pipeline with only writes. Write requests are throttled. Unfortunately, optimal throttling depends on the traffic pattern. The amount of write traffic to allow depends on request sizes and the ratio of an AFU's read to write requests. There are too many variables to build a static arbiter.

The code here adds dynamic write throttling in [ofs\_plat\_host\_chan\_tlp\_learning\_weight.sv](ofs_plat_host_chan_tlp_learning_weight.sv). Read and write traffic is sampled over fixed-size intervals. Hill-climbing code adjusts the write throttling threshold at the end of each sampling interval. The hill-climbing is mostly simple and linear. At random intervals, larger threshold adjustments are made to avoid getting stuck in a local maximum.

The dynamic hill-climbing logic is able to achieve fair allocation for a variety of access patterns. Of course, patterns that are highly chaotic, with read and write ratios varying rapidly, remain challenging.
