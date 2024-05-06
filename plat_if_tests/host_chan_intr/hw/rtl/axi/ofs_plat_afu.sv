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
    //  Get an AXI host channel connection from the platform.
    //
    // ====================================================================

    localparam NUM_PORTS = plat_ifc.host_chan.NUM_PORTS;

    // Host memory AFU source
    ofs_plat_axi_mem_if
      #(
        `HOST_CHAN_AXI_MEM_PARAMS,
        .BURST_CNT_WIDTH(7),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        host_mem_to_afu[NUM_PORTS]();

    // 64 bit read/write MMIO AFU sink
    ofs_plat_axi_mem_lite_if
      #(
        `HOST_CHAN_AXI_MMIO_PARAMS(64),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_to_afu[NUM_PORTS]();

    // Map FIU interface to AXI host memory and MMIO
    genvar p;
    generate
        for (p = 0; p < NUM_PORTS; p = p + 1)
        begin : hc
            ofs_plat_host_chan_as_axi_mem_with_mmio
              #(
                .ADD_TIMING_REG_STAGES(2)
                )
              primary_axi
               (
                .to_fiu(plat_ifc.host_chan.ports[p]),
                .host_mem_to_afu(host_mem_to_afu[p]),
                .mmio_to_afu(mmio64_to_afu[p]),

                .afu_clk(),
                .afu_reset_n()
                );
        end
    endgenerate


    // ====================================================================
    //
    //  Tie off unused ports.
    //
    // ====================================================================

    ofs_plat_if_tie_off_unused
      #(
        // All host channel ports are connected
        .HOST_CHAN_IN_USE_MASK(-1)
        )
        tie_off(plat_ifc);


    // ====================================================================
    //
    //  Pass the constructed interfaces to the AFU.
    //
    // ====================================================================

    generate
        for (p = 0; p < NUM_PORTS; p = p + 1)
        begin : afu
            afu
              #(
                .NUM_INTR_IDS(`OFS_PLAT_PARAM_HOST_CHAN_NUM_INTR_VECS)
                )
              afu
               (
                .host_mem_if(host_mem_to_afu[p]),
                .mmio64_if(mmio64_to_afu[p]),
                .pClk(plat_ifc.clocks.pClk.clk)
                );
        end
    endgenerate

endmodule // ofs_plat_afu
