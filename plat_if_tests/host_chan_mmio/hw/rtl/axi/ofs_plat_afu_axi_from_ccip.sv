// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Export the host channel as AXI interfaces.
//

`include "ofs_plat_if.vh"

module ofs_plat_afu
   (
    // All platform wires, wrapped in one interface.
    ofs_plat_if plat_ifc
    );

    // ====================================================================
    //
    //  Get a CCI-P port from the platform.
    //
    // ====================================================================

    // Instance of a CCI-P interface. The interface wraps usual CCI-P
    // sRx and sTx structs as well as the associated clock and reset.
    ofs_plat_host_ccip_if ccip_to_afu();

    // Use the platform-provided module to map the primary host interface
    // to CCI-P. The "primary" interface is the port that includes the
    // main OPAE-managed MMIO connection.
    ofs_plat_host_chan_as_ccip
      #(
        .ADD_TIMING_REG_STAGES(2)
        )
      primary_ccip
       (
        .to_fiu(plat_ifc.host_chan.ports[0]),
        .to_afu(ccip_to_afu),

        // Use default clock
        .afu_clk(),
        .afu_reset_n()
        );


    // Split CCI-P into a pair of CCI-P interfaces: one for host memory
    // and the other for MMIO.
    ofs_plat_host_ccip_if#(.LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)) host_mem_to_afu();
    ofs_plat_host_ccip_if ccip_to_mmio();

    ofs_plat_shim_ccip_split_mmio ccip_split
       (
        .to_fiu(ccip_to_afu),
        .host_mem(host_mem_to_afu),
        .mmio(ccip_to_mmio)
        );


    //
    // Map the the CCI-P MMIO interface to a 64 bit AXI interface.
    //
    ofs_plat_axi_mem_lite_if
      #(
        `HOST_CHAN_AXI_MMIO_PARAMS(64),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_to_afu();

    ofs_plat_map_ccip_as_axi_mmio
      #(
        .MAX_OUTSTANDING_MMIO_RD_REQS(ccip_cfg_pkg::MAX_OUTSTANDING_MMIO_RD_REQS)
        )
      axi_host_mmio64
       (
        .to_fiu(ccip_to_mmio),
        .mmio_to_afu(mmio64_to_afu),

        // Not used (no clock crossing)
        .afu_clk(),
        .afu_reset_n()
        );


    //
    // Map the the CCI-P MMIO interface to a 512 bit write-only AXI
    // interface.
    //
    ofs_plat_axi_mem_lite_if
      #(
        `HOST_CHAN_AXI_MMIO_PARAMS(512),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio512_wr_to_afu();

    ofs_plat_map_ccip_as_axi_mmio_wo
      #(
        .MAX_OUTSTANDING_MMIO_RD_REQS(ccip_cfg_pkg::MAX_OUTSTANDING_MMIO_RD_REQS)
        )
      axi_host_mmio512
       (
        .to_fiu(ccip_to_mmio),
        .mmio_to_afu(mmio512_wr_to_afu),

        // Not used (no clock crossing)
        .afu_clk(),
        .afu_reset_n()
        );


    // ====================================================================
    //
    //  Tie off unused ports.
    //
    // ====================================================================

    ofs_plat_if_tie_off_unused
      #(
        // Masks are bit masks, with bit 0 corresponding to port/bank zero.
        // Set a bit in the mask when a port is IN USE by the design.
        // This way, the AFU does not need to know about every available
        // device. By default, devices are tied off.
        .HOST_CHAN_IN_USE_MASK(1)
        )
        tie_off(plat_ifc);


    // ====================================================================
    //
    //  Pass the constructed interfaces to the AFU.
    //
    // ====================================================================

    afu afu
      (
       .mmio64_if(mmio64_to_afu),
       .mmio512_if(mmio512_wr_to_afu)
       );

    // Tie off host memory -- not used by this test
    assign host_mem_to_afu.sTx = '0;

endmodule // ofs_plat_afu
