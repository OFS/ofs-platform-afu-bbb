// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Export the host channel as Avalon interfaces.
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
    //  Get an Avalon host channel connection from the platform.
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

    localparam NUM_PORTS = plat_ifc.host_chan.NUM_PORTS;

    // Host memory AFU source
    ofs_plat_avalon_mem_rdwr_if
      #(
        `HOST_CHAN_AVALON_MEM_RDWR_PARAMS,
`ifdef TEST_PARAM_BURST_CNT_WIDTH
        .BURST_CNT_WIDTH(`TEST_PARAM_BURST_CNT_WIDTH),
`else
        .BURST_CNT_WIDTH(7),
`endif
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        host_mem_to_afu[NUM_PORTS]();

    // 64 bit read/write MMIO AFU sink
    ofs_plat_avalon_mem_if
      #(
        `HOST_CHAN_AVALON_MMIO_PARAMS(64),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_to_afu[NUM_PORTS]();

    // Map ports to host_mem_to_afu.
    genvar p;
    generate
        for (p = 0; p < NUM_PORTS; p = p + 1)
        begin : hc
            ofs_plat_host_chan_as_avalon_mem_rdwr_with_mmio
              #(
`ifdef TEST_PARAM_AFU_CLK
                .ADD_CLOCK_CROSSING(1),
`endif
`ifdef TEST_PARAM_AFU_REG_STAGES
                .ADD_TIMING_REG_STAGES(`TEST_PARAM_AFU_REG_STAGES)
`endif
                )
              primary_avalon
               (
                .to_fiu(plat_ifc.host_chan.ports[p]),
                .host_mem_to_afu(host_mem_to_afu[p]),
                .mmio_to_afu(mmio64_to_afu[p]),

`ifdef TEST_PARAM_AFU_CLK
                .afu_clk(plat_ifc.clocks.ports[p].`TEST_PARAM_AFU_CLK.clk),
                .afu_reset_n(plat_ifc.clocks.ports[p].`TEST_PARAM_AFU_CLK.reset_n)
`else
                .afu_clk(),
                .afu_reset_n()
`endif
                );
        end
    endgenerate


    // ====================================================================
    //
    //  Host channel event trackers, used for computing latency through
    //  the FIM.
    //
    // ====================================================================

    host_chan_events_if host_chan_events[NUM_PORTS]();

    generate
        for (p = 0; p < NUM_PORTS; p = p + 1)
        begin : ev
          `ifdef OFS_PLAT_PARAM_HOST_CHAN_IS_NATIVE_AXIS_PCIE_TLP
            `ifdef OFS_PLAT_PARAM_HOST_CHAN_GASKET_PCIE_SS
              // Pick the proper RX channel for read completions
              logic en_rx;
              logic [ofs_plat_host_chan_fim_gasket_pkg::TDATA_WIDTH-1 : 0] rx_data;
              logic rx_tlast;
              if (ofs_plat_host_chan_fim_gasket_pkg::CPL_CHAN == ofs_plat_host_chan_fim_gasket_pkg::PCIE_CHAN_A)
              begin
                  assign en_rx =plat_ifc.host_chan.ports[p].afu_rx_a_st.tready && plat_ifc.host_chan.ports[p].afu_rx_a_st.tvalid;
                  assign rx_data = plat_ifc.host_chan.ports[p].afu_rx_a_st.tdata;
                  assign rx_tlast = plat_ifc.host_chan.ports[p].afu_rx_a_st.tlast;
              end
              else
              begin
                  assign en_rx =plat_ifc.host_chan.ports[p].afu_rx_b_st.tready && plat_ifc.host_chan.ports[p].afu_rx_b_st.tvalid;
                  assign rx_data = plat_ifc.host_chan.ports[p].afu_rx_b_st.tdata;
                  assign rx_tlast = plat_ifc.host_chan.ports[p].afu_rx_b_st.tlast;
              end
            `endif

            host_chan_events_axi ev
               (
                .clk(plat_ifc.host_chan.ports[p].clk),
                .reset_n(plat_ifc.host_chan.ports[p].reset_n),

              `ifdef OFS_PLAT_PARAM_HOST_CHAN_GASKET_PCIE_SS
                .en_tx(plat_ifc.host_chan.ports[p].afu_tx_a_st.tready && plat_ifc.host_chan.ports[p].afu_tx_a_st.tvalid),
                .tx_data(plat_ifc.host_chan.ports[p].afu_tx_a_st.tdata),
                .tx_tlast(plat_ifc.host_chan.ports[p].afu_tx_a_st.tlast),

                .en_tx_b(plat_ifc.host_chan.ports[p].afu_tx_b_st.tready && plat_ifc.host_chan.ports[p].afu_tx_b_st.tvalid),
                .tx_b_data(plat_ifc.host_chan.ports[p].afu_tx_b_st.tdata),
                .tx_b_tlast(plat_ifc.host_chan.ports[p].afu_tx_b_st.tlast),

                .en_rx,
                .rx_data,
                .rx_tlast,
               `else
                .en_tx(plat_ifc.host_chan.ports[p].afu_tx_st.tready && plat_ifc.host_chan.ports[p].afu_tx_st.tvalid),
                .tx_data(plat_ifc.host_chan.ports[p].afu_tx_st.t.data),
                .tx_user(plat_ifc.host_chan.ports[p].afu_tx_st.t.user),

                .en_rx(plat_ifc.host_chan.ports[p].afu_rx_st.tready && plat_ifc.host_chan.ports[p].afu_rx_st.tvalid),
                .rx_data(plat_ifc.host_chan.ports[p].afu_rx_st.t.data),
                .rx_user(plat_ifc.host_chan.ports[p].afu_rx_st.t.user),
               `endif

                .events(host_chan_events[p])
                );
          `elsif OFS_PLAT_PARAM_HOST_CHAN_IS_NATIVE_CCIP
            host_chan_events_ccip ev
               (
                .clk(plat_ifc.host_chan.ports[p].clk),
                .reset_n(plat_ifc.host_chan.ports[p].reset_n),

                .sRx(plat_ifc.host_chan.ports[p].sRx),
                .sTx(plat_ifc.host_chan.ports[p].sTx),

                .events(host_chan_events[p])
                );
          `else
            host_chan_events_none n(.events(host_chan_events[p]));
          `endif
        end
    endgenerate


    // ====================================================================
    //
    //  Map pwrState to the AFU clock domain
    //
    // ====================================================================

    t_ofs_plat_power_state afu_pwrState[NUM_PORTS];

    generate
        for (p = 0; p < NUM_PORTS; p = p + 1)
        begin : ps
            ofs_plat_prim_clock_crossing_reg
              #(
                .WIDTH($bits(t_ofs_plat_power_state))
                )
              map_pwrState
               (
                .clk_src(plat_ifc.clocks.pClk.clk),
                .clk_dst(host_mem_to_afu[p].clk),
                .r_in(plat_ifc.pwrState),
                .r_out(afu_pwrState[p])
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
                .AFU_INSTANCE_ID(p)
                )
              afu_impl
               (
                .host_mem_if(host_mem_to_afu[p]),
                .host_chan_events_if(host_chan_events[p]),

                .mmio64_if(mmio64_to_afu[p]),
                .pClk(plat_ifc.clocks.pClk.clk),
                .pwrState(afu_pwrState[p])
                );
        end
    endgenerate

endmodule // ofs_plat_afu
