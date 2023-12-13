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

    localparam NUM_PORTS = plat_ifc.host_chan.NUM_PORTS_;

`ifndef OFS_PLAT_PARAM_HOST_CHAN_LINKX2_NUM_PORTS
    // No link x 2 support. Generate AFUs with only standard width.
    localparam NUM_STD_PORTS = NUM_PORTS;
    localparam NUM_2X_PORTS = 0;
`else
    // Generate one link x 2 AFU and the rest standard width.
    localparam NUM_STD_PORTS = NUM_PORTS - 1;
    localparam NUM_2X_PORTS = 1;
`endif

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
        host_mem_to_afu[NUM_STD_PORTS]();

    // 64 bit read/write MMIO AFU sink
    ofs_plat_avalon_mem_if
      #(
        `HOST_CHAN_AVALON_MMIO_PARAMS(64),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_to_afu[NUM_STD_PORTS]();

    // Map ports to host_mem_to_afu.
    genvar p;
    generate
        for (p = 0; p < NUM_STD_PORTS; p = p + 1)
        begin : hc
            localparam ifc_port = p + NUM_2X_PORTS;

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
                .to_fiu(plat_ifc.host_chan.ports[ifc_port]),
                .host_mem_to_afu(host_mem_to_afu[p]),
                .mmio_to_afu(mmio64_to_afu[p]),

`ifdef TEST_PARAM_AFU_CLK
                .afu_clk(plat_ifc.clocks.ports[ifc_port].`TEST_PARAM_AFU_CLK.clk),
                .afu_reset_n(plat_ifc.clocks.ports[ifc_port].`TEST_PARAM_AFU_CLK.reset_n)
`else
                .afu_clk(),
                .afu_reset_n()
`endif
                );
        end
    endgenerate


    // ====================================================================
    //
    // Map FIM ports to link x 2
    //
    // ====================================================================

`ifdef OFS_PLAT_PARAM_HOST_CHAN_LINKX2_NUM_PORTS

    // FIM host channels, mapped to a double width data bus
    ofs_plat_host_chan_linkx2_fiu_if
      #(
        .ENABLE_LOG(1),
        .NUM_PORTS(NUM_2X_PORTS)
        )
        host_chan_linkx2();

    ofs_plat_avalon_mem_rdwr_if
      #(
        `HOST_CHAN_LINKX2_AVALON_MEM_RDWR_PARAMS,
`ifdef TEST_PARAM_BURST_CNT_WIDTH
        .BURST_CNT_WIDTH(`TEST_PARAM_BURST_CNT_WIDTH),
`else
        .BURST_CNT_WIDTH(7),
`endif
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        host_mem_2x_to_afu[NUM_2X_PORTS]();

    // 64 bit read/write MMIO AFU sink
    ofs_plat_avalon_mem_if
      #(
        `HOST_CHAN_LINKX2_AVALON_MMIO_PARAMS(64),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_2x_to_afu[NUM_2X_PORTS]();

    // Map ports to host_mem_2x_to_afu.
    generate
        for (p = 0; p < NUM_2X_PORTS; p = p + 1)
        begin : hc_2x
            localparam ifc_port = p;

            // Map a host channel to double width. This double width
            // host-native stream (e.g. PCIe TLP) will be the input to
            // the PIM on the FIM side.
            ofs_plat_host_chan_linkx2_from_host_chan map_linkx2
               (
                .to_fiu0(plat_ifc.host_chan.ports[ifc_port]),
                .to_afu(host_chan_linkx2.ports[p])
                );

            // Connect a PIM instance to the double width native stream.
            ofs_plat_host_chan_linkx2_as_avalon_mem_rdwr_with_mmio
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
                .to_fiu(host_chan_linkx2.ports[ifc_port]),
                .host_mem_to_afu(host_mem_2x_to_afu[p]),
                .mmio_to_afu(mmio64_2x_to_afu[p]),

`ifdef TEST_PARAM_AFU_CLK
                .afu_clk(plat_ifc.clocks.ports[ifc_port].`TEST_PARAM_AFU_CLK.clk),
                .afu_reset_n(plat_ifc.clocks.ports[ifc_port].`TEST_PARAM_AFU_CLK.reset_n)
`else
                .afu_clk(),
                .afu_reset_n()
`endif
                );
        end
    endgenerate

`endif //  `ifdef OFS_PLAT_PARAM_HOST_CHAN_LINKX2_NUM_PORTS


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
                // All the AFU clocks are the same
                .clk_dst(host_mem_to_afu[0].clk),
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
        //
        // Normal width AFU instances
        //
        for (p = 0; p < NUM_STD_PORTS; p = p + 1)
        begin : afu
            localparam ifc_port = p + NUM_2X_PORTS;

            afu
              #(
                .AFU_INSTANCE_ID(ifc_port)
                )
              afu_impl
               (
                .host_mem_if(host_mem_to_afu[p]),
                .host_chan_events_if(host_chan_events[ifc_port]),

                .mmio64_if(mmio64_to_afu[p]),
                .pClk(plat_ifc.clocks.pClk.clk),
                .pwrState(afu_pwrState[ifc_port])
                );
        end

`ifdef OFS_PLAT_PARAM_HOST_CHAN_LINKX2_NUM_PORTS
        //
        // Double width AFU instances. afu() gets the bus width from the
        // configuration of host_mem_if.
        //
        for (p = 0; p < NUM_2X_PORTS; p = p + 1)
        begin : afu_2x
            afu
              #(
                .AFU_INSTANCE_ID(p)
                )
              afu_impl
               (
                .host_mem_if(host_mem_2x_to_afu[p]),
                .host_chan_events_if(host_chan_events[p]),

                .mmio64_if(mmio64_2x_to_afu[p]),
                .pClk(plat_ifc.clocks.pClk.clk),
                .pwrState(afu_pwrState[p])
                );
        end
`endif
    endgenerate

endmodule // ofs_plat_afu
