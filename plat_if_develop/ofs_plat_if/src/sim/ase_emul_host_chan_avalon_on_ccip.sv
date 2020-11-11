//
// Copyright (c) 2020, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

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
