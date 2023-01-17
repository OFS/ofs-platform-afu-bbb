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
    //  Get an AXI host channel connection from the platform.
    //
    // ====================================================================

    //
    // Assume that all group 0 interfaces have their own MMIO as well.
    // They are likely either separate virtual or physical interfaces
    // to the host.
    //
    // Separate instances of the test harness will be instantiated on
    // each group 0 interface.
    //

    localparam NUM_PORTS_G0 = plat_ifc.host_chan.NUM_PORTS_;

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
        // 4 extra bits for requests (returned with responses).
        .USER_WIDTH(ofs_plat_host_chan_axi_mem_pkg::HC_AXI_UFLAG_MAX + 1 + 4),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        host_mem_to_afu[NUM_PORTS_G0]();

    // 64 bit read/write MMIO AFU sink
    ofs_plat_axi_mem_lite_if
      #(
        `HOST_CHAN_AXI_MMIO_PARAMS(64),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_to_afu[NUM_PORTS_G0]();

    // Map group 0 ports to host_mem_to_afu.
    genvar p;
    generate
        for (p = 0; p < NUM_PORTS_G0; p = p + 1)
        begin : hc_g0
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

    //
    // If there is a second group of host channel ports map them too.
    // We assume they do not have MMIO control. These ports will be
    // associated with the G0 engine 0 environment.
    //
`ifndef OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS

    localparam NUM_PORTS_G1 = 0;
    ofs_plat_axi_mem_if
      #(
        `HOST_CHAN_AXI_MEM_PARAMS,
        .BURST_CNT_WIDTH(3)
        )
        host_mem_g1_to_afu[1]();

`else

    localparam NUM_PORTS_G1 = plat_ifc.host_chan_g1.NUM_PORTS_;
    ofs_plat_axi_mem_if
      #(
        `HOST_CHAN_G1_AXI_MEM_PARAMS,
`ifdef TEST_PARAM_BURST_CNT_WIDTH
        .BURST_CNT_WIDTH(`TEST_PARAM_BURST_CNT_WIDTH),
`else
        .BURST_CNT_WIDTH(7),
`endif
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        host_mem_g1_to_afu[NUM_PORTS_G1]();

    generate
        for (p = 0; p < NUM_PORTS_G1; p = p + 1)
        begin : hc_g1
            ofs_plat_host_chan_g1_as_axi_mem
              #(
`ifdef TEST_PARAM_AFU_REG_STAGES
                .ADD_TIMING_REG_STAGES(`TEST_PARAM_AFU_REG_STAGES),
`endif
                .ADD_CLOCK_CROSSING(1)
                )
              axi
               (
                .to_fiu(plat_ifc.host_chan_g1.ports[p]),
                .host_mem_to_afu(host_mem_g1_to_afu[p]),

                .afu_clk(host_mem_to_afu[0].clk),
                .afu_reset_n(host_mem_to_afu[0].reset_n)
                );
        end
    endgenerate

`endif // OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS


    //
    // If there is a third group of host channel ports map them too.
    //
`ifndef OFS_PLAT_PARAM_HOST_CHAN_G2_NUM_PORTS

    localparam NUM_PORTS_G2 = 0;
    ofs_plat_axi_mem_if
      #(
        `HOST_CHAN_AXI_MEM_PARAMS,
        .BURST_CNT_WIDTH(3)
        )
        host_mem_g2_to_afu[1]();

`else

    localparam NUM_PORTS_G2 = plat_ifc.host_chan_g2.NUM_PORTS_;
    ofs_plat_axi_mem_if
      #(
        `HOST_CHAN_G2_AXI_MEM_PARAMS,
`ifdef TEST_PARAM_BURST_CNT_WIDTH
        .BURST_CNT_WIDTH(`TEST_PARAM_BURST_CNT_WIDTH),
`else
        .BURST_CNT_WIDTH(7),
`endif
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        host_mem_g2_to_afu[NUM_PORTS_G2]();

    generate
        for (p = 0; p < NUM_PORTS_G2; p = p + 1)
        begin : hc_g2
            ofs_plat_host_chan_g2_as_axi_mem
              #(
`ifdef TEST_PARAM_AFU_REG_STAGES
                .ADD_TIMING_REG_STAGES(`TEST_PARAM_AFU_REG_STAGES),
`endif
                .ADD_CLOCK_CROSSING(1)
                )
              axi
               (
                .to_fiu(plat_ifc.host_chan_g2.ports[p]),
                .host_mem_to_afu(host_mem_g2_to_afu[p]),

                .afu_clk(host_mem_to_afu[0].clk),
                .afu_reset_n(host_mem_to_afu[0].reset_n)
                );
        end
    endgenerate

`endif // OFS_PLAT_PARAM_HOST_CHAN_G2_NUM_PORTS


    // ====================================================================
    //
    //  Host channel event trackers, used for computing latency through
    //  the FIM.
    //
    // ====================================================================

    host_chan_events_if host_chan_events[NUM_PORTS_G0]();
    host_chan_events_if host_chan_g1_events[NUM_PORTS_G1 == 0 ? 1 : NUM_PORTS_G1]();
    host_chan_events_if host_chan_g2_events[NUM_PORTS_G2 == 0 ? 1 : NUM_PORTS_G2]();

    generate
        for (p = 0; p < NUM_PORTS_G0; p = p + 1)
        begin : ev_g0
          `ifdef OFS_PLAT_PARAM_HOST_CHAN_IS_NATIVE_AXIS_PCIE_TLP
            `ifdef OFS_PLAT_PARAM_HOST_CHAN_GASKET_PCIE_SS
              // Pick the proper RX channel for read completions
              logic en_rx;
              ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata rx_data;
              ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser rx_user;
              if (ofs_plat_host_chan_fim_gasket_pkg::CPL_CHAN == ofs_plat_host_chan_fim_gasket_pkg::PCIE_CHAN_A)
              begin
                  assign en_rx =plat_ifc.host_chan.ports[p].afu_rx_a_st.tready && plat_ifc.host_chan.ports[p].afu_rx_a_st.tvalid;
                  assign rx_data = plat_ifc.host_chan.ports[p].afu_rx_a_st.t.data;
                  assign rx_user = plat_ifc.host_chan.ports[p].afu_rx_a_st.t.user;
              end
              else
              begin
                  assign en_rx =plat_ifc.host_chan.ports[p].afu_rx_b_st.tready && plat_ifc.host_chan.ports[p].afu_rx_b_st.tvalid;
                  assign rx_data = plat_ifc.host_chan.ports[p].afu_rx_b_st.t.data;
                  assign rx_user = plat_ifc.host_chan.ports[p].afu_rx_b_st.t.user;
              end
            `endif

            host_chan_events_axi ev
               (
                .clk(plat_ifc.host_chan.ports[p].clk),
                .reset_n(plat_ifc.host_chan.ports[p].reset_n),

              `ifdef OFS_PLAT_PARAM_HOST_CHAN_GASKET_PCIE_SS
                .en_tx(plat_ifc.host_chan.ports[p].afu_tx_a_st.tready && plat_ifc.host_chan.ports[p].afu_tx_a_st.tvalid),
                .tx_data(plat_ifc.host_chan.ports[p].afu_tx_a_st.t.data),
                .tx_user(plat_ifc.host_chan.ports[p].afu_tx_a_st.t.user),

                .en_tx_b(plat_ifc.host_chan.ports[p].afu_tx_b_st.tready && plat_ifc.host_chan.ports[p].afu_tx_b_st.tvalid),
                .tx_b_data(plat_ifc.host_chan.ports[p].afu_tx_b_st.t.data),
                .tx_b_user(plat_ifc.host_chan.ports[p].afu_tx_b_st.t.user),

                .en_rx,
                .rx_data,
                .rx_user,
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

        // For now, groups 1 and 2 don't track events
        for (p = 0; p < NUM_PORTS_G1; p = p + 1)
        begin : ev_g1
          `ifdef OFS_PLAT_PARAM_HOST_CHAN_G1_IS_NATIVE_AXIS_PCIE_TLP
            `ifdef OFS_PLAT_PARAM_HOST_CHAN_GASKET_PCIE_SS
              // Pick the proper RX channel for read completions
              logic en_rx;
              ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata rx_data;
              ofs_plat_host_chan_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser rx_user;
              if (ofs_plat_host_chan_fim_gasket_pkg::CPL_CHAN == ofs_plat_host_chan_fim_gasket_pkg::PCIE_CHAN_A)
              begin
                  assign en_rx = plat_ifc.host_chan_g1.ports[p].afu_rx_a_st.tready && plat_ifc.host_chan_g1.ports[p].afu_rx_a_st.tvalid;
                  assign rx_data = plat_ifc.host_chan_g1.ports[p].afu_rx_a_st.t.data;
                  assign rx_user = plat_ifc.host_chan_g1.ports[p].afu_rx_a_st.t.user;
              end
              else
              begin
                  assign en_rx = plat_ifc.host_chan_g1.ports[p].afu_rx_b_st.tready && plat_ifc.host_chan_g1.ports[p].afu_rx_b_st.tvalid;
                  assign rx_data = plat_ifc.host_chan_g1.ports[p].afu_rx_b_st.t.data;
                  assign rx_user = plat_ifc.host_chan_g1.ports[p].afu_rx_b_st.t.user;
              end
            `endif

            host_chan_events_axi ev
               (
                .clk(plat_ifc.host_chan_g1.ports[p].clk),
                .reset_n(plat_ifc.host_chan_g1.ports[p].reset_n),

              `ifdef OFS_PLAT_PARAM_HOST_CHAN_GASKET_PCIE_SS
                .en_tx(plat_ifc.host_chan_g1.ports[p].afu_tx_a_st.tready && plat_ifc.host_chan_g1.ports[p].afu_tx_a_st.tvalid),
                .tx_data(plat_ifc.host_chan_g1.ports[p].afu_tx_a_st.t.data),
                .tx_user(plat_ifc.host_chan_g1.ports[p].afu_tx_a_st.t.user),

                .en_tx_b(plat_ifc.host_chan_g1.ports[p].afu_tx_b_st.tready && plat_ifc.host_chan_g1.ports[p].afu_tx_b_st.tvalid),
                .tx_b_data(plat_ifc.host_chan_g1.ports[p].afu_tx_b_st.t.data),
                .tx_b_user(plat_ifc.host_chan_g1.ports[p].afu_tx_b_st.t.user),

                .en_rx,
                .rx_data,
                .rx_user,
               `else
                .en_tx(plat_ifc.host_chan_g1.ports[p].afu_tx_st.tready && plat_ifc.host_chan_g1.ports[p].afu_tx_st.tvalid),
                .tx_data(plat_ifc.host_chan_g1.ports[p].afu_tx_st.t.data),
                .tx_user(plat_ifc.host_chan_g1.ports[p].afu_tx_st.t.user),

                .en_rx(plat_ifc.host_chan_g1.ports[p].afu_rx_st.tready && plat_ifc.host_chan_g1.ports[p].afu_rx_st.tvalid),
                .rx_data(plat_ifc.host_chan_g1.ports[p].afu_rx_st.t.data),
                .rx_user(plat_ifc.host_chan_g1.ports[p].afu_rx_st.t.user),
               `endif

                .events(host_chan_g1_events[p])
                );
          `elsif OFS_PLAT_PARAM_HOST_CHAN_G1_IS_NATIVE_CCIP
            host_chan_events_ccip ev
               (
                .clk(plat_ifc.host_chan_g1.ports[p].clk),
                .reset_n(plat_ifc.host_chan_g1.ports[p].reset_n),

                .sRx(plat_ifc.host_chan_g1.ports[p].sRx),
                .sTx(plat_ifc.host_chan_g1.ports[p].sTx),

                .events(host_chan_g1_events[p])
                );
          `elsif OFS_PLAT_PARAM_HOST_CHAN_G1_IS_NATIVE_AVALON
            host_chan_events_avalon#(.BURST_CNT_WIDTH(plat_ifc.host_chan_g1.ports[p].BURST_CNT_WIDTH)) ev
               (
                .clk(plat_ifc.host_chan_g1.ports[p].clk),
                .reset_n(plat_ifc.host_chan_g1.ports[p].reset_n),

                .en_tx_rd(plat_ifc.host_chan_g1.ports[p].read && !plat_ifc.host_chan_g1.ports[p].waitrequest),
                .tx_rd_cnt(plat_ifc.host_chan_g1.ports[p].burstcount),
                .en_rx_rd(plat_ifc.host_chan_g1.ports[p].readdatavalid),

                .events(host_chan_g1_events[p])
                );
          `else
            host_chan_events_none n(.events(host_chan_g1_events[p]));
          `endif
        end
        for (p = 0; p < NUM_PORTS_G2; p = p + 1)
        begin : ev_g2
            host_chan_events_none n(.events(host_chan_g2_events[p]));
        end
    endgenerate


    // ====================================================================
    //
    //  Map pwrState to the AFU clock domain
    //
    // ====================================================================

    t_ofs_plat_power_state afu_pwrState[NUM_PORTS_G0];

    generate
        for (p = 0; p < NUM_PORTS_G0; p = p + 1)
        begin : ps_g0
            ofs_plat_prim_clock_crossing_reg
              #(
                .WIDTH($bits(t_ofs_plat_power_state))
                )
              map_pwrState
               (
                .clk_src(plat_ifc.clocks.ports[p].pClk.clk),
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
`ifdef OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS
        // If host channel group 1 ports exist, they are all connected
        .HOST_CHAN_G1_IN_USE_MASK(-1),
`endif
`ifdef OFS_PLAT_PARAM_HOST_CHAN_G2_NUM_PORTS
        // If host channel group 2 ports exist, they are all connected
        .HOST_CHAN_G2_IN_USE_MASK(-1),
`endif
        // All host channel group 0 ports are connected
        .HOST_CHAN_IN_USE_MASK(-1)
        )
        tie_off(plat_ifc);


    // ====================================================================
    //
    //  Pass the constructed interfaces to the AFU.
    //
    // ====================================================================

    // Group 0, port 0 gets all the G1/G2 ports
    afu
     #(
       .NUM_PORTS_G1(NUM_PORTS_G1),
       .NUM_PORTS_G2(NUM_PORTS_G2)
       )
     afu_impl
      (
       .host_mem_if(host_mem_to_afu[0]),
       .host_mem_g1_if(host_mem_g1_to_afu),
       .host_mem_g2_if(host_mem_g2_to_afu),

       .host_chan_events_if(host_chan_events[0]),
       .host_chan_g1_events_if(host_chan_g1_events),
       .host_chan_g2_events_if(host_chan_g2_events),

       .mmio64_if(mmio64_to_afu[0]),
       .pClk(plat_ifc.clocks.pClk.clk),
       .pwrState(afu_pwrState[0])
       );

    // Any other group 0 ports get their own AFU instances
    generate
        for (p = 1; p < NUM_PORTS_G0; p = p + 1)
        begin : afu_g0
            ofs_plat_axi_mem_if
              #(
                `HOST_CHAN_AXI_MEM_PARAMS,
                .BURST_CNT_WIDTH(3)
                )
              dummy_host_mem_g1[1]();

            ofs_plat_axi_mem_if
              #(
                `HOST_CHAN_AXI_MEM_PARAMS,
                .BURST_CNT_WIDTH(3)
                )
              dummy_host_mem_g2[1]();

            host_chan_events_if dummy_host_chan_g1_events[1]();
            host_chan_events_if dummy_host_chan_g2_events[1]();

            afu
              #(
                .AFU_INSTANCE_ID(p),
                .NUM_PORTS_G1(0),
                .NUM_PORTS_G2(0)
                )
              afu_impl
               (
                .host_mem_if(host_mem_to_afu[p]),
                .host_mem_g1_if(dummy_host_mem_g1),
                .host_mem_g2_if(dummy_host_mem_g2),

                .host_chan_events_if(host_chan_events[p]),
                .host_chan_g1_events_if(dummy_host_chan_g1_events),
                .host_chan_g2_events_if(dummy_host_chan_g2_events),

                .mmio64_if(mmio64_to_afu[p]),
                .pClk(plat_ifc.clocks.pClk.clk),
                .pwrState(afu_pwrState[p])
                );
        end
    endgenerate

endmodule // ofs_plat_afu
