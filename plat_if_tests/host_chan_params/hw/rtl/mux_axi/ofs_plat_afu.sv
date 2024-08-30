// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Export the host channel as AXI-MM interfaces.
//

`default_nettype none

`include "ofs_plat_if.vh"

module ofs_plat_afu
   (
    // All platform wires, wrapped in one interface.
    ofs_plat_if plat_ifc
    );

    // ====================================================================
    //
    //  Get an AXI-MM multiplexed channel for each host channel.
    //  If the underlying host channel is multiplexed, e.g. with SR-IOV
    //  PF/VF tags, it will remain multiplexed in the AXI-MM interface.
    //
    // ====================================================================

    //
    // Assume that all interfaces have their own MMIO as well.
    // They are likely either separate virtual or physical interfaces
    // to the host.
    //
    // Separate instances of the test harness will be instantiated on
    // each interface.
    //

    localparam NUM_MUX_PORTS = `OFS_PLAT_PARAM_HOST_CHAN_NUM_MULTIPLEXED_PORTS;

    // Host memory AFU source
    ofs_plat_axi_mem_if
      #(
        `HOST_CHAN_AXI_MEM_PARAMS,
`ifdef TEST_PARAM_BURST_CNT_WIDTH
        .BURST_CNT_WIDTH(`TEST_PARAM_BURST_CNT_WIDTH),
`else
        .BURST_CNT_WIDTH(7),
`endif
        // Write fence and interrupt are signaled with AWUSER flags. Add
        // 4 extra bits for requests (returned with responses). Also leave
        // space in the user field for a virtual channel index.
        .USER_WIDTH(ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_WITH_VCHAN_WIDTH + 4),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        host_mem_to_afu[NUM_MUX_PORTS]();

    // 64 bit read/write MMIO AFU sink
    ofs_plat_axi_mem_lite_if
      #(
        `HOST_CHAN_AXI_MMIO_PARAMS(64),
        .USER_WIDTH(ofs_plat_host_chan_axi_mem_pkg::HC_AXI_MMIO_UFLAG_WITH_VCHAN_WIDTH),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_to_afu[NUM_MUX_PORTS]();

    // Map ports to host_mem_to_afu.
    generate
        for (genvar m = 0; m < NUM_MUX_PORTS; m = m + 1)
        begin : hc
            ofs_plat_host_chan_as_axi_mem_with_mmio
              #(
`ifdef TEST_PARAM_AFU_CLK
                .ADD_CLOCK_CROSSING(1),
`endif
`ifdef TEST_PARAM_AFU_REG_STAGES
                .ADD_TIMING_REG_STAGES(`TEST_PARAM_AFU_REG_STAGES)
`endif
                )
              primary_axi
               (
                .to_fiu(plat_ifc.host_chan.ports[m]),
                .host_mem_to_afu(host_mem_to_afu[m]),
                .mmio_to_afu(mmio64_to_afu[m]),

`ifdef TEST_PARAM_AFU_CLK
                .afu_clk(plat_ifc.clocks.ports[m].`TEST_PARAM_AFU_CLK.clk),
                .afu_reset_n(plat_ifc.clocks.ports[m].`TEST_PARAM_AFU_CLK.reset_n)
`else
                .afu_clk(),
                .afu_reset_n()
`endif
                );

        end
    endgenerate


    // ====================================================================
    //
    //  Map pwrState to the AFU clock domain
    //
    // ====================================================================

    t_ofs_plat_power_state afu_pwrState[NUM_MUX_PORTS];

    generate
        for (genvar m = 0; m < NUM_MUX_PORTS; m = m + 1)
        begin : ps
            ofs_plat_prim_clock_crossing_reg
              #(
                .WIDTH($bits(t_ofs_plat_power_state))
                )
              map_pwrState
               (
                .clk_src(plat_ifc.clocks.ports[m].pClk.clk),
                .clk_dst(host_mem_to_afu[m].clk),
                .r_in(plat_ifc.pwrState),
                .r_out(afu_pwrState[m])
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

    localparam NUM_CHAN = `OFS_PLAT_PARAM_HOST_CHAN_NUM_CHAN_PER_MULTIPLEXED_PORT;

    generate
        for (genvar m = 0; m < NUM_MUX_PORTS; m = m + 1)
        begin : demux
            //
            // Demultiplex each multiplexed AXI-MM interface into separate
            // AXI-MM interfaces, one per AFU.
            //

            // Per-AFU MMIO interfaces
            ofs_plat_axi_mem_lite_if
              #(
                `HOST_CHAN_AXI_MMIO_PARAMS(64),
                .USER_WIDTH(ofs_plat_host_chan_axi_mem_pkg::HC_AXI_MMIO_UFLAG_WITH_VCHAN_WIDTH),
                .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
                )
              mmio64_ports[NUM_CHAN]();

            // Demultiplex MMIO. Incoming requests are tagged with virtual channel IDs.
            ofs_plat_host_chan_axi_mem_lite_if_vchan_mux
              #(
                .NUM_AFU_PORTS(NUM_CHAN)
                )
              mmio64_mux
               (
                .host_mmio(mmio64_to_afu[m]),
                .afu_mmio(mmio64_ports)
                );

            // Per-AFU host memory interfaces
            ofs_plat_axi_mem_if
              #(
                `HOST_CHAN_AXI_MEM_PARAMS,
`ifdef TEST_PARAM_BURST_CNT_WIDTH
                .BURST_CNT_WIDTH(`TEST_PARAM_BURST_CNT_WIDTH),
`else
                .BURST_CNT_WIDTH(7),
`endif
                .USER_WIDTH(ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_WITH_VCHAN_WIDTH + 4),
                .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
                )
              host_mem_ports[NUM_CHAN]();

            // Host memory demultiplexer. Virtual channel numbers are dense,
            // corresponding directly to the port index.
            ofs_plat_host_chan_axi_mem_if_vchan_mux
              #(
                .NUM_AFU_PORTS(NUM_CHAN)
                )
              host_mem_mux
               (
                .host_mem(host_mem_to_afu[m]),
                .afu_mem(host_mem_ports)
                );

            // Per-AFU event counters
            host_chan_events_if host_chan_events[NUM_CHAN]();

            for (genvar p = 0; p < NUM_CHAN; p = p + 1) begin
                assign mmio64_ports[p].clk = host_mem_to_afu[m].clk;
`ifdef TEST_PARAM_AFU_CLK
                assign mmio64_ports[p].reset_n = plat_ifc.clocks.demux_ports[m][p].`TEST_PARAM_AFU_CLK.reset_n;
`else
                assign mmio64_ports[p].reset_n = plat_ifc.clocks.demux_ports[m][p].pClk.reset_n;
`endif
                assign mmio64_ports[p].instance_number = p;

                assign host_mem_ports[p].clk = host_mem_to_afu[m].clk;
`ifdef TEST_PARAM_AFU_CLK
                assign host_mem_ports[p].reset_n = plat_ifc.clocks.demux_ports[m][p].`TEST_PARAM_AFU_CLK.reset_n;
`else
                assign host_mem_ports[p].reset_n = plat_ifc.clocks.demux_ports[m][p].pClk.reset_n;
`endif
                assign host_mem_ports[p].instance_number = p;


                // Track reads for a specific AFU. Because the PIM AXI-MM mapper
                // is shared we can't track the other side of the PIM. Watch
                // the AFU's AXI-MM read traffic.
                host_chan_events_generic
                  #(
                    .BURST_CNT_WIDTH(host_mem_ports[0].BURST_CNT_WIDTH + 1)
                    )
                  ev
                   (
                    .clk(plat_ifc.clocks.demux_ports[m][p].pClk.clk),
                    .reset_n(plat_ifc.clocks.demux_ports[m][p].pClk.reset_n),

                    .rd_clk(host_mem_ports[p].clk),
                    .en_tx_rd(host_mem_ports[p].arvalid && host_mem_ports[p].arready),
                    .tx_rd_cnt({ 1'b0, host_mem_ports[p].ar.len } + 1'b1),
                    .en_rx_rd(host_mem_ports[p].rvalid && host_mem_ports[p].rready),

                    .events(host_chan_events[p])
                    );


                // One AFU per demultiplexed port
                afu
                  #(
                    .AFU_INSTANCE_ID(p),
                    .VCHAN_NUMBER(p)
                    )
                  afu_impl
                   (
                    .host_mem_if(host_mem_ports[p]),
                    .host_chan_events_if(host_chan_events[p]),

                    .mmio64_if(mmio64_ports[p]),
                    .pClk(plat_ifc.clocks.pClk.clk),
                    .pwrState(afu_pwrState[m])
                    );
            end
        end // block: afu
    endgenerate

endmodule // ofs_plat_afu
