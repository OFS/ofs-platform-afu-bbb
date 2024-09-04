// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Combine incoming per-channel streams into a single multiplexed
// stream. The opposite of ofs_plat_prim_vchan_demux.
//
// No virtual channel tags are added here. The streams must be
// tagged internally with the matching port index by whatever
// generates the stream data.
//

`include "ofs_plat_if.vh"

module ofs_plat_prim_vchan_mux
  #(
    parameter NUM_DEMUX_PORTS = 2
    )
   (
    ofs_plat_axi_stream_if.to_source demux_in[NUM_DEMUX_PORTS],
    ofs_plat_axi_stream_if.to_sink mux_out
    );

    wire clk = mux_out.clk;
    wire reset_n = mux_out.reset_n;

    localparam M_OUT_PAYLOAD_WIDTH = mux_out.T_PAYLOAD_WIDTH;

    logic [NUM_DEMUX_PORTS-1 : 0][M_OUT_PAYLOAD_WIDTH-1 : 0] D_in_data;
    logic [NUM_DEMUX_PORTS-1 : 0] D_in_sop;
    logic [NUM_DEMUX_PORTS-1 : 0] D_in_eop;
    logic [NUM_DEMUX_PORTS-1 : 0] D_in_valid;
    logic [NUM_DEMUX_PORTS-1 : 0] D_in_ready;

    for (genvar p = 0; p < NUM_DEMUX_PORTS; p = p + 1) begin
        assign D_in_data[p] = demux_in[p].t;
        assign D_in_eop[p] = demux_in[p].t.last;
        assign D_in_valid[p] = demux_in[p].tvalid;
        assign demux_in[p].tready = D_in_ready[p];

        always_ff @(posedge clk)
        begin
            if (demux_in[p].tvalid && demux_in[p].tready)
                D_in_sop[p] <= demux_in[p].t.last;

            if (!reset_n)
                D_in_sop[p] <= 1'b1;
        end
    end

    // demux_in -> mux_out
    fim_pf_vf_nmux
      #(
        .WIDTH(M_OUT_PAYLOAD_WIDTH),
        .N(NUM_DEMUX_PORTS),
        .REG_OUT(0),
        .DEPTH(1)
        )
      mux
       (
        .clk,
        .rst_n(reset_n),

        .mux_in_data(D_in_data),
        .mux_in_sop(D_in_sop & D_in_valid),
        .mux_in_eop(D_in_eop & D_in_valid),
        .mux_in_valid(D_in_valid),
        .mux_out_ready(mux_out.tready),

        .mux_in_ready(D_in_ready),
        .mux_out_data(mux_out.t),
        .mux_out_valid(mux_out.tvalid),

        .out_q_err(),
        .out_q_perr()
        );


    // ====================================================================
    //
    //  Validation
    //
    // ====================================================================

    // synthesis translate_off
    initial
    begin
        if (M_OUT_PAYLOAD_WIDTH != demux_in[0].T_PAYLOAD_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: mux_out (%0d)/demux_in (%0d) width mismatch!",
                   M_OUT_PAYLOAD_WIDTH, demux_in[0].T_PAYLOAD_WIDTH);
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_prim_vchan_mux
