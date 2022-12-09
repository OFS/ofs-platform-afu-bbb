// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

//
// Emulate a group of Avalon host channels given a CCI-P port. The Avalon
// channels will be multiplexed on top of the single CCI-P port.
//
module ase_emul_host_chan_avalon_on_ccip
  #(
    parameter INSTANCE_BASE = 0,
    parameter NUM_PORTS = 0,
    parameter ADDR_WIDTH = 0,
    parameter DATA_WIDTH = 0,
    parameter BURST_CNT_WIDTH = 0,
    parameter USER_WIDTH = 0,
    parameter RD_TRACKER_DEPTH = 0,
    parameter WR_TRACKER_DEPTH = 0,
    parameter OUT_OF_ORDER = 0
    )
   (
    ofs_plat_host_ccip_if.to_fiu to_fiu,
    ofs_plat_avalon_mem_if emul_ports[NUM_PORTS]
    );

    // Begin by transforming the CCI-P port to a single Avalon port.
    ofs_plat_avalon_mem_rdwr_if
      #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BURST_CNT_WIDTH(BURST_CNT_WIDTH),
        .USER_WIDTH(USER_WIDTH + ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_MAX + 1)
        )
        avmm_shared_sink_if();

    ofs_plat_host_chan_as_avalon_mem_rdwr avmm_to_ccip
       (
        .to_fiu,
        .host_mem_to_afu(avmm_shared_sink_if),
        .afu_clk(),
        .afu_reset_n()
        );

    // Multiplex the single Avalon sink into the required number of ports
    ofs_plat_avalon_mem_rdwr_if
      #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BURST_CNT_WIDTH(BURST_CNT_WIDTH),
        .USER_WIDTH(USER_WIDTH)
        )
        avmm_port_sink_if[NUM_PORTS]();

    // The MUX preservers the source's "user" extension fields, making it
    // possible to use algorithms that depend on user fields in responses
    // matching requests.
    ofs_plat_avalon_mem_rdwr_if_mux
      #(
        .NUM_SOURCE_PORTS(NUM_PORTS),
        .RD_TRACKER_DEPTH(RD_TRACKER_DEPTH),
        .WR_TRACKER_DEPTH(WR_TRACKER_DEPTH),
        .SINK_USER_SHIFT(ofs_plat_host_chan_avalon_mem_pkg::HC_AVALON_UFLAG_MAX + 1)
        )
      avmm_mux
       (
        .mem_sink(avmm_shared_sink_if),
        .mem_source(avmm_port_sink_if)
        );

    // Convert split-bus read/write Avalon to standard Avalon
    genvar p;
    for (p = 0; p < NUM_PORTS; p = p + 1)
    begin : e
        // Emulate ports that return results out of order
        ofs_plat_avalon_mem_rdwr_if
          #(
            .ADDR_WIDTH(ADDR_WIDTH),
            .DATA_WIDTH(DATA_WIDTH),
            .BURST_CNT_WIDTH(BURST_CNT_WIDTH),
            .USER_WIDTH(USER_WIDTH)
            )
            avmm_ooo_if();

        ase_emul_ooo_avalon_mem_rdwr_if
          #(
            .OUT_OF_ORDER(OUT_OF_ORDER)
            )
          ooo_port
           (
            .mem_sink(avmm_port_sink_if[p]),
            .mem_source(avmm_ooo_if)
            );

        ofs_plat_avalon_mem_if_to_rdwr_if avmm_to_rdwr
           (
            .mem_sink(avmm_ooo_if),
            .mem_source(emul_ports[p])
            );

        assign emul_ports[p].clk = avmm_port_sink_if[p].clk;
        assign emul_ports[p].reset_n = avmm_port_sink_if[p].reset_n;
        assign emul_ports[p].instance_number = INSTANCE_BASE + p;
    end

endmodule // ase_emul_host_chan_avalon_on_ccip
