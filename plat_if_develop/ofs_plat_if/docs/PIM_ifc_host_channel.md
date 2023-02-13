# Host Channel Mapping

A host channel is any device interface that can read and write host memory or that can expose AFU-side CSRs accessible from a host. Most often, both capabilities are present. A PCIe device is a host channel, as is CXL. Each PCIe virtual or physical function is treated by the PIM as a separate channel.

The PIM provides shims to map any host channel into three AFU interfaces: AXI-MM, Avalon-MM and CCI-P. All three shims are present in the build environment. The chosen interface depends only on which shim an AFU instantiates. CCI-P is a legacy protocol from older OPAE systems and should not be used for new designs.

The general design pattern for both AXI-MM and Avalon-MM within an AFU is:

* Instantiate a host memory interface -- one of the [PIM's base interfaces](PIM_core_concepts.md#pim-base-systemverilog-interfaces).
* Instantiate a CSR \(MMIO\) interface -- another PIM base interface.
* Instantiate a shim that maps a host channel to the CSR and host memory interfaces.

The hello world tutorial example demonstrates the pattern for both [AXI-MM](https://github.com/OFS/examples-afu/blob/main/tutorial/afu_types/01_pim_ifc/hello_world/hw/rtl/axi/ofs_plat_afu.sv) and [Avalon-MM](https://github.com/OFS/examples-afu/blob/main/tutorial/afu_types/01_pim_ifc/hello_world/hw/rtl/avalon/ofs_plat_afu.sv).

The PIM's host channel shim implementations are in the source tree under [ifc_classes/host_chan](../src/rtl/ifc_classes/host_chan/). RTL sources there are templates. Only a subset will be chosen by the PIM's configuration scripts, based on the protocol of the native device.

## AXI-MM Host Channels

The PIM's AXI interfaces define the payload for each AXI bus inside a struct so that all fields can be copied in a single statement. This simplifies code inside the PIM and reduces opportunities for bugs. See the discussion in [PIM core concepts](PIM_core_concepts.md#pim-base-systemverilog-interfaces). Discussions of both AXI-MM and AXI-Lite below include links to the interface definitions and structs.

### Host memory AXI-MM

Define the host memory AXI-MM interface as follows:

```SystemVerilog
    ofs_plat_axi_mem_if
      #(
        `HOST_CHAN_AXI_MEM_PARAMS,
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
      host_mem();
```

The PIM provides the macro `HOST_CHAN_AXI_MEM_PARAMS, which sets ADDR_WIDTH and DATA_WIDTH to values appropriate for the native device in the memory interface. An AFU may set other [ofs_plat_axi_mem_if](../src/rtl/base_ifcs/axi/ofs_plat_axi_mem_if.sv) parameters to AFU-specific values:

* BURST_CNT_WIDTH may be any value. The PIM will map large AFU bursts into legal host channel sizes and handle device-specific alignment requirements. For example, the PIM permits AFU-generated bursts to cross 4KB boundaries. This would be illegal on PCIe, so the PIM breaks apart bursts at 4KB boundaries.
* Whatever the RID_WIDTH and WID_WIDTH, IDs passed in requests will be returned in responses. The PIM is incapable of implementing the AXI-MM standard that read requests sharing the same RID will reach the host and be serviced in request order because PCIe does not make this guarantee.
* USER_WIDTH may also be set by an AFU, but must leave space for the user bits defined by the PIM for fences and interrupts that are described below. The user field from a request is returned with a response. For writes, user bits from the address bus are returned.

The argument to LOG_CLASS enables message logging in simulation of all traffic on the interface, typically to a file named log_ofs_plat_host_chan.tsv.

### CSR \(MMIO\) AXI-Lite

Define the CSR AXI-Lite interface as follows:

```SystemVerilog
    ofs_plat_axi_mem_lite_if
      #(
        `HOST_CHAN_AXI_MMIO_PARAMS(64),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_to_afu();
```

The parameters are similar to those set above on the host memory AXI-MM interface. The "64" passed to the HOST_CHAN_AXI_MMIO_PARAMS sets the data bus width. OPAE expects to read feature IDs as 64 bit parameters. Because the CSR interface is acting as a sink, the other parameters to ofs_plat_axi_mem_lite_if should not be changed.

LOG_CLASS behaves the same as the host memory interface. In the suggested configuration, both host memory and CSR traffic are logged to the same file.

### Host memory shim

Finally, instantiate the shim that maps a host channel to the AXI-MM and AXI-Lite interfaces:

```SystemVerilog
    ofs_plat_host_chan_as_axi_mem_with_mmio primary_axi
       (
        .to_fiu(plat_ifc.host_chan.ports[0]),
        .host_mem_to_afu(host_mem),
        .mmio_to_afu(mmio64_to_afu),

        // These ports would be used if the PIM is told to cross to
        // a different clock. In this example, native pClk is used.
        .afu_clk(),
        .afu_reset_n()
        );
```

All host channel mapping shims have a common set of optional parameters:

* When non-zero, ADD_CLOCK_CROSSING includes a clock crossing from the native interface's default clock to a clock passed into the afu_clk/afu_reset_n pair of ports. When set, host_mem and mmio64_to_afu operate on afu_clk.
* SORT_READ_RESPONSES, when set, guarantees that read responses will arrive in request order. The PIM adds a reorder buffer when the native interface might return responses out of order. When the native interface is inherently ordered, the parameter has no effect.
* SORT_WRITE_RESPONSES is the equivalent setting for write requests and responses.
* ADD_TIMING_REG_STAGES adds the specified number of register stages at the border to the native interface.

### CSR \(MMIO\) AXI-Lite Protocol

AFUs must implement the AXI-Lite sink \(slave\) for MMIO read and write requests from the host. At the very least, the OPAE feature ID registers must be present.

The PIM's AXI-Lite interface includes request ID tags that must be returned along with read data. Because the tags are present, there is no response order requirement. An AFU may complete outstanding read requests in any order.

### Host memory protocol

#### Tags and ordering

AXI-MM permits duplicate tags on read and write requests. However, while the AXI-MM standard requires that requests with the same tag complete in order, PCIe does not for reads. The PIM can make no guarantee about the order in which reads are processed by the host. When SORT_READ_RESPONSES is set, the PIM guarantees that read responses arrive in request order. When responses are sorted, an AFU will see the same read response ordering and throughput whether all request IDs are identical or unique.

Write commits, returned on the AXI-MM B channel, guarantee that all read and writes generated after the commit will reach the host after the committed write.

#### Bursts

Only incrementing address mode is supported. Addresses must be aligned to the bus width. Lower address bits that index bytes within the data bus are ignored.

Burst length is limited only by the width of the burst count field, which is set by the BURST_CNT_WIDTH parameter to the [AXI-MM interface](../src/rtl/base_ifcs/axi/ofs_plat_axi_mem_if.sv). Bursts may cross any address boundary, including 4KB pages. The PIM will break apart large bursts as needed, depending on both alignment and size restrictions of the native interface.

#### Masked writes

AXI-MM defines strobe bits on the write data bus that mask write data, reducing the range of a write. The PIM imposes the following restrictions on the use of masked write data:

* Strobe bits may be zero only at the beginning or the end of a data range. No zero bits are permitted between ones.
* **Burst length when a zero mask bit is present must be 0 \(one line\).** This restriction comes from the difference in AXI-MM and PCIe TLP encoding. PCIe encodes the length of a burst in a header, in front of the payload. AXI-MM encodes the masked length at the end of the payload. The PIM would have to buffer entire payloads in order to compute the true PCIe transaction length. Masked data at the start of a burst requires a data shift when translated to PCIe. Allowing a multi-line burst with a starting mask would add significant complexity to the AXI to TLP translation.

#### Write fences

Write fences are encoded with a bit in the user field on the AXI-MM write address channel. The PIM defines AXI-MM host channel user bits in [ofs_plat_host_chan_axi_mem_pkg](../src/rtl/ifc_classes/host_chan/afu_ifcs/axi/ofs_plat_host_chan_axi_mem_pkg.sv). User bits in all AXI-MM channels below ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_WIDTH, which includes the write fence flag, are reserved by the PIM. AFUs may set the width of the user fields in ofs_plat_axi_mem_if to anything larger than HC_AXI_UFLAG_WIDTH. Note that the width may change in future PIM releases. AFU developers are encouraged to set AFU-specific flag offsets relative to HC_AXI_UFLAG_WIDTH.

A write fence is encoded as a normal write:

* Set ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_FENCE in the AW user field.
* Burst length must be 0.
* Generate a single data beat on the write data bus.
* Address and data are ignored.

A completion is returned on the B channel.

#### Interrupts

Interrupts are encoded with user bits, just like write fences. Interrupts are encoded as normal writes:

* Set ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_INTERRUPT in the AW user field.
* Store the interrupt vector in the AW address field. The available number of interface vectors is platform-dependent. The PIM provides a macro with the number of vectors available to each AFU: `OFS_PLAT_PARAM_HOST_CHAN_NUM_INTR_VECS.
* Burst length must be 0.
* Generate a single data beat on the write data bus. The payload is ignored.

A [PIM test for interrupts](../../../plat_if_tests/host_chan_intr/hw/rtl/axi/) serves as a simple example.

#### Atomic memory transactions

When the native interface supports them, the standard PCIe atomic transactions are supported. That is: 32 and 64 bit atomic ADD, SWAP and CAS. The PIM provides a macro, `OFS_PLAT_PARAM_HOST_CHAN_ATOMICS, that is defined when atomic transactions are supported on the native host memory channel.

Version 5 of the AMBA AXI protocol adds encoding for atomic transactions. The PIM follows the encoding in section E1.1 of the AMBA AXI and ACE Protocol Specification. The AWATOP encoding is defined in the PIM's base AXI-MM interface in [ofs_plat_axi_mem_pkg](../src/rtl/base_ifcs/axi/ofs_plat_axi_mem_pkg.sv). Localparams are included there for the AXI5 encoding of ATOMIC_ADD, ATOMIC_SWAP and ATOMIC_CAS.

Atomic requests may not cross data-bus aligned boundaries. As specified in the standard, a write commit is returned on the B channel when no future requests will bypass the atomic operation. Data is returned on the read response channel.

Atomic operations are encoded as write requests:
* Store the atomic operation in aw.atop.
* Burst length must be 0.
* Generate a single data beat on the write data bus. The byte offset, data strobe and position of data on the bus should all match and follow the AXI-MM standard. The AMBA AXI protocol defines the location of compare and swap data, which varies depending on the address offset within the data bus. In version 5 of the specification, CAS locations are detailed in E1.1.3.

The PIM test [host_chan_atomic](../../../plat_if_tests/host_chan_atomic/hw/rtl/axi/) generates all of the atomic operations and is currently the best example.

## Avalon-MM Host Channels

The PIM has two varieties of Avalon-MM channels: a split-bus [ofs_plat_avalon_mem_rdwr_if](../src/rtl/base_ifcs/avalon/ofs_plat_avalon_mem_if.sv) with completely separate channels for reads and writes and a standard Avalon-MM channel [ofs_plat_avalon_mem_if](../src/rtl/base_ifcs/avalon/ofs_plat_avalon_mem_if.sv) with a shared address bus. The split-bus version is used for the host memory interface since it more accurately reflects the behavior and throughput of most native host channels. The standard shared address bus is used for CSRs \(MMIO\).

### Host memory Avalon-MM Split Bus

Define the host memory Avalon-MM interface as follows:

```SystemVerilog
    ofs_plat_avalon_mem_rdwr_if
      #(
        `HOST_CHAN_AVALON_MEM_RDWR_PARAMS,
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
      host_mem();

```

The PIM provides the macro `HOST_CHAN_AVALON_MEM_RDWR_PARAMS, which sets ADDR_WIDTH and DATA_WIDTH to values appropriate for the native device in the memory interface. An AFU may set other [ofs_plat_avalon_mem_rdwr_if](../src/rtl/base_ifcs/avalon/ofs_plat_avalon_mem_if.sv) parameters to AFU-specific values:

* BURST_CNT_WIDTH may be any value. The PIM will map large AFU bursts into legal host channel sizes and handle device-specific alignment requirements. For example, the PIM permits AFU-generated bursts to cross 4KB boundaries. This would be illegal on PCIe, so the PIM breaks apart bursts at 4KB boundaries.
* USER_WIDTH may be set by an AFU, but must leave space for the user bits defined by the PIM for fences and interrupts that are described below. The user field from a request is returned with a response. For writes, user bits from the address bus are returned.

The argument to LOG_CLASS enables message logging in simulation of all traffic on the interface, typically to a file named log_ofs_plat_host_chan.tsv.

### CSR \(MMIO\) Avalon-MM

Define the CSR AXI-Lite interface as follows:

```SystemVerilog
    ofs_plat_avalon_mem_if
      #(
        `HOST_CHAN_AVALON_MMIO_PARAMS(64),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_to_afu();

```

The parameters are similar to those set above on the host memory Avalon-MM interface. The "64" passed to the HOST_CHAN_AVALON_MMIO_PARAMS sets the data bus width. OPAE expects to read feature IDs as 64 bit parameters. Because the CSR interface is acting as a sink, the other parameters to ofs_plat_avalon_mem_if should not be changed.

LOG_CLASS behaves the same as the host memory interface. In the suggested configuration, both host memory and CSR traffic are logged to the same file.

### Host memory shim

Finally, instantiate the shim that maps a host channel to the Avalon-MM interfaces:

```SystemVerilog
     ofs_plat_host_chan_as_avalon_mem_rdwr_with_mmio primary_avalon
       (
        .to_fiu(plat_ifc.host_chan.ports[0]),
        .host_mem_to_afu(host_mem),
        .mmio_to_afu(mmio64_to_afu),

        // These ports would be used if the PIM is told to cross to
        // a different clock. In this example, native pClk is used.
        .afu_clk(),
        .afu_reset_n()
        );
```

All host channel mapping shims have a common set of optional parameters:

* When non-zero, ADD_CLOCK_CROSSING includes a clock crossing from the native interface's default clock to a clock passed into the afu_clk/afu_reset_n pair of ports. When set, host_mem and mmio64_to_afu operate on afu_clk.
* ADD_TIMING_REG_STAGES adds the specified number of register stages at the border to the native interface.
* The Avalon-MM interfaces requires responses sorted in request order. Unlike the AXI-MM version of the shim, no parameters exist for requesting ordered responses. This shim will ensure proper response ordering.

### CSR \(MMIO\) Avalon-MM Protocol

AFUs must implement the Avalon-MM sink \(slave\) for MMIO read and write requests from the host. At the very least, the OPAE feature ID registers must be present.

CSR read responses must be returned to the PIM in request order.

### Host memory protocol

#### Read/write ordering

A write commit path is defined on the host memory split Avalon-MM bus in order to give AFUs control over the relative order of reads and writes. Write commits arrive in request order. All reads generated after a write commit are guaranteed to follow the write.

#### Bursts

Burst length is limited only by the width of the burst count field, which is set by the BURST_CNT_WIDTH parameter to the [Avalon-MM interface](../src/rtl/base_ifcs/avalon/ofs_plat_avalon_mem_rdwr_if.sv). Bursts may cross any address boundary, including 4KB pages. The PIM will break apart large bursts as needed, depending on both alignment and size restrictions of the native interface.

#### Masked writes

Avalon-MM defines byte enable bits on the write data bus that mask write data, reducing the range of a write. The PIM imposes the following restrictions on the use of masked write data:

* Enable bits may be zero only at the beginning or the end of a data range. No zero bits are permitted between ones.
* **Burst length when a zero mask bit is present must be 1 \(one line\).** This restriction comes from the difference in Avalon-MM and PCIe TLP encoding. PCIe encodes the length of a burst in a header, in front of the payload. Avalon-MM encodes the masked length at the end of the payload. The PIM would have to buffer entire payloads in order to compute the true PCIe transaction length. Masked data at the start of a burst requires a data shift when translated to PCIe. Allowing a multi-line burst with a starting mask would add significant complexity to the Avalon to TLP translation.

#### Write fences

Write fences are encoded with a bit in the wr_user field. The PIM defines Avalon-MM host channel user bits in [ofs_plat_host_chan_avalon_mem_pkg](../src/rtl/ifc_classes/host_chan/afu_ifcs/avalon/ofs_plat_host_chan_avalon_mem_pkg.sv). User bits in all Avalon-MM channels below ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_WIDTH, which includes the write fence flag, are reserved by the PIM. AFUs may set the width of the user fields in ofs_plat_avalon_mem_rdwr_if to anything larger than HC_AVALON_UFLAG_WIDTH. Note that the width may change in future PIM releases. AFU developers are encouraged to set AFU-specific flag offsets relative to HC_AVALON_UFLAG_WIDTH.

A write fence is encoded as a normal write:

* Set ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_FENCE in the wr_user user field.
* Burst length must be 1.
* Address and data are ignored.

A completion is returned as a write response.

#### Interrupts

Interrupts are encoded with user bits, just like write fences. Interrupts are encoded as normal writes:

* Set ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_INTERRUPT in the wr_user field.
* Store the interrupt vector in the wr_address field. The available number of interface vectors is platform-dependent. The PIM provides a macro with the number of vectors available to each AFU: `OFS_PLAT_PARAM_HOST_CHAN_NUM_INTR_VECS.
* Burst length must be 1.
* Data is ignored.

A completion is returned as a write response.

A [PIM test for interrupts](../../../plat_if_tests/host_chan_intr/hw/rtl/avalon/) serves as a simple example.

#### Atomic memory transactions

Atomic memory transactions are not supported on the Avalon bus. There is no encoding defined for them.
