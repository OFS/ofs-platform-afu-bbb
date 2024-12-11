// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Break an incoming multiplexed stream into separate ports,
// one per virtual channel. The opposite of ofs_plat_prim_vchan_mux.
//
// The output port index is stored in mux_in.t.user.
//

`include "ofs_plat_if.vh"

module ofs_plat_prim_vchan_demux
  #(
    parameter NUM_DEMUX_PORTS = 2,

    // Start position in mux_in.t.user field of the outbound demux_out
    // port index.
    parameter PORT_IDX_START_BIT = 0
    )
   (
    ofs_plat_axi_stream_if.to_source mux_in,
    ofs_plat_axi_stream_if.to_sink demux_out[NUM_DEMUX_PORTS]
    );

    wire clk = mux_in.clk;
    wire reset_n = mux_in.reset_n;

    localparam M_IN_PAYLOAD_WIDTH = mux_in.T_PAYLOAD_WIDTH;
    localparam PORT_SEL_WIDTH = $clog2(NUM_DEMUX_PORTS);

    logic mux_in_sop;
    always_ff @(posedge clk)
    begin
        if (mux_in.tvalid && mux_in.tready)
            mux_in_sop <= mux_in.t.last;

        if (!reset_n)
            mux_in_sop <= 1'b1;
    end

    logic [NUM_DEMUX_PORTS-1 : 0] M_in_sel;
    logic [NUM_DEMUX_PORTS-1 : 0] M_in_valid;
    logic [NUM_DEMUX_PORTS-1 : 0] M_in_ready;

    // Declare mux_in to demux_out port mapping as "bit" so it always has
    // a value, even when invalid. Traffic will still be gated by valid/ready
    // bits.
    bit [PORT_SEL_WIDTH-1 : 0] port_sel;
    assign port_sel =
        (mux_in.t.user[PORT_IDX_START_BIT +: PORT_SEL_WIDTH] < NUM_DEMUX_PORTS) ?
            mux_in.t.user[PORT_IDX_START_BIT +: PORT_SEL_WIDTH] : '0;

    always_comb
    begin
        M_in_sel = '0;
        M_in_sel[port_sel] = 1'b1;
        M_in_valid = M_in_sel & {NUM_DEMUX_PORTS{mux_in.tvalid}};

        mux_in.tready = M_in_ready[port_sel];
    end

    for (genvar p = 0; p < NUM_DEMUX_PORTS; p = p + 1) begin : D_mux
        // mux_in -> demux_out[p]
        fim_pf_vf_nmux
          #(
            .WIDTH(M_IN_PAYLOAD_WIDTH),
            .N(1),
            .REG_OUT(0),
            .DEPTH(1)
            )
          mux
           (
            .clk,
            .rst_n(reset_n),

            .mux_in_data(mux_in.t),
            .mux_in_sop(mux_in_sop & M_in_valid[p]),
            .mux_in_eop(mux_in.t.last & M_in_valid[p]),
            .mux_in_valid(M_in_valid[p]),
            .mux_out_ready(demux_out[p].tready),

            .mux_in_ready(M_in_ready[p]),
            .mux_out_data(demux_out[p].t),
            .mux_out_valid(demux_out[p].tvalid),

            .out_q_err(),
            .out_q_perr()
            );
    end


    // ====================================================================
    //
    //  Validation
    //
    // ====================================================================

    // synthesis translate_off
    initial
    begin
        if (M_IN_PAYLOAD_WIDTH != demux_out[0].T_PAYLOAD_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: mux_in (%0d)/demux_out (%0d) payload width mismatch!",
                   M_IN_PAYLOAD_WIDTH, demux_out[0].T_PAYLOAD_WIDTH);
        end

        if (mux_in.TUSER_WIDTH != demux_out[0].TUSER_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: mux_in (%0d)/demux_out (%0d) user width mismatch!",
                   mux_in.TUSER_WIDTH, demux_out[0].TUSER_WIDTH);
        end

        if (mux_in.TUSER_WIDTH < PORT_IDX_START_BIT + PORT_SEL_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: mux_in user width (%0d) too small for [%0d:%0d] demux ports!",
                   mux_in.TUSER_WIDTH,
                   PORT_IDX_START_BIT + PORT_SEL_WIDTH - 1, PORT_IDX_START_BIT);
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_prim_vchan_demux
