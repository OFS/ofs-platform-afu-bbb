// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Export the host channel as CCI-P for host memory and Avalon for MMIO.
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
    //  Get a CCI-P port from the platform.
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

    // Instance of a CCI-P interface. The interface wraps usual CCI-P
    // sRx and sTx structs as well as the associated clock and reset.
    ofs_plat_host_ccip_if ccip_to_afu[NUM_PORTS]();

    // CCI-P interfaces will be split into a pair of CCI-P interfaces: one for
    // host memory and the other for MMIO.
    ofs_plat_host_ccip_if#(.LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)) host_mem_to_afu[NUM_PORTS]();
    ofs_plat_host_ccip_if ccip_to_mmio[NUM_PORTS]();

    // And the the CCI-P MMIO interface will be mapped to a 64 bit Avalon interface,
    // since that's what the AFU expects.
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
            ofs_plat_host_chan_as_ccip
              #(
`ifdef TEST_PARAM_AFU_CLK
                .ADD_CLOCK_CROSSING(1),
`endif
`ifdef TEST_PARAM_SORT_RD_RESP
                .SORT_READ_RESPONSES(1),
`endif
`ifdef TEST_PARAM_SORT_WR_RESP
                .SORT_WRITE_RESPONSES(1),
`endif
`ifdef TEST_PARAM_AFU_REG_STAGES
                .ADD_TIMING_REG_STAGES(`TEST_PARAM_AFU_REG_STAGES)
`endif
                )
              primary_ccip
               (
                .to_fiu(plat_ifc.host_chan.ports[p]),
                .to_afu(ccip_to_afu[p]),

`ifdef TEST_PARAM_AFU_CLK
                .afu_clk(plat_ifc.clocks.ports[p].`TEST_PARAM_AFU_CLK.clk),
                .afu_reset_n(plat_ifc.clocks.ports[p].`TEST_PARAM_AFU_CLK.reset_n)
`else
                .afu_clk(),
                .afu_reset_n()
`endif
                );


            // Split DMA and MMIO interfaces
            ofs_plat_shim_ccip_split_mmio ccip_split
               (
                .to_fiu(ccip_to_afu[p]),
                .host_mem(host_mem_to_afu[p]),
                .mmio(ccip_to_mmio[p])
                );


            // Map MMIO to Avalon
            ofs_plat_map_ccip_as_avalon_mmio
              #(
                .MAX_OUTSTANDING_MMIO_RD_REQS(ccip_cfg_pkg::MAX_OUTSTANDING_MMIO_RD_REQS)
                )
              av_host_mmio
               (
                .to_fiu(ccip_to_mmio[p]),
                .mmio_to_afu(mmio64_to_afu[p]),

                // Not used (no clock crossing)
                .afu_clk(),
                .afu_reset_n()
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
