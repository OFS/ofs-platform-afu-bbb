// Copyright (C) 2024 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Break a multiplexed bi-directional stream into separate ports.
// This is the equivalent of the FIM's PF/VF MUX, but operating on
// virtual channel IDs.
//
// In the mux -> demux direction the output port index is stored
// in mux_in.t.user.
//

`include "ofs_plat_if.vh"

module ofs_plat_prim_vchan_mux
  #(
    parameter NUM_DEMUX_PORTS = 2
    )
   (
    ofs_plat_axi_stream_if.to_source mux_in,
    ofs_plat_axi_stream_if.to_sink demux_out[NUM_DEMUX_PORTS],

    ofs_plat_axi_stream_if.to_source demux_in[NUM_DEMUX_PORTS],
    ofs_plat_axi_stream_if.to_sink mux_out
    );

    wire clk = mux_in.clk;
    wire reset_n = mux_in.reset_n;

    localparam M_IN_DATA_WIDTH = mux_in.TDATA_WIDTH;
    localparam M_OUT_DATA_WIDTH = mux_out.TDATA_WIDTH;

    logic mux_in_sop;
    always_ff @(posedge clk)
    begin
        if (mux_in.tvalid && mux_in.tready)
            mux_in_sop <= mux_in.t.last;

        if (!reset_n)
            mux_in_sop <= 1'b1;
    end

    logic [M_OUT_DATA_WIDTH-1 : 0] M_out_data;
    logic [NUM_DEMUX_PORTS-1 : 0] M_in_sel;
    logic [NUM_DEMUX_PORTS-1 : 0] M_in_valid;
    logic [NUM_DEMUX_PORTS-1 : 0] M_in_ready;

    // Declare mux_in to demux_out port mapping as "bit" so it always has
    // a value, even when invalid. Traffic will still be gated by valid/ready
    // bits.
    bit [$clog2(NUM_DEMUX_PORTS)-1 : 0] port_sel;
    assign port_sel = (mux_in.t.user < NUM_DEMUX_PORTS) ? mux_in.t.user : '0;

    always_comb
    begin
        mux_out.t = '0;
        mux_out.t.data = M_out_data;

        M_in_sel = '0;
        M_in_sel[port_sel] = 1'b1;
        M_in_valid = M_in_sel & {NUM_DEMUX_PORTS{mux_in.tvalid}};

        mux_in.tready = M_in_ready[port_sel];
    end

    logic [NUM_DEMUX_PORTS-1 : 0][M_OUT_DATA_WIDTH-1 : 0] D_in_data;
    logic [NUM_DEMUX_PORTS-1 : 0] D_in_sop;
    logic [NUM_DEMUX_PORTS-1 : 0] D_in_eop;
    logic [NUM_DEMUX_PORTS-1 : 0] D_in_valid;
    logic [NUM_DEMUX_PORTS-1 : 0] D_in_ready;

    logic [NUM_DEMUX_PORTS-1 : 0][M_IN_DATA_WIDTH-1 : 0] D_out_data;

    for (genvar p = 0; p < NUM_DEMUX_PORTS; p = p + 1) begin
        assign D_in_data[p] = demux_in[p].t.data;
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

        always_comb
        begin
            demux_out[p].t = '0;
            demux_out[p].t.data = D_out_data[p];
        end
    end

    // demux_in -> mux_out
    fim_pf_vf_nmux
      #(
        .WIDTH(M_OUT_DATA_WIDTH),
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
        .mux_out_data(M_out_data),
        .mux_out_valid(mux_out.tvalid),

        .out_q_err(),
        .out_q_perr()
        );

    for (genvar p = 0; p < NUM_DEMUX_PORTS; p = p + 1) begin : D_mux
        // mux_in -> demux_out[p]
        fim_pf_vf_nmux
          #(
            .WIDTH(M_IN_DATA_WIDTH),
            .N(1),
            .REG_OUT(0),
            .DEPTH(1)
            )
          mux
           (
            .clk,
            .rst_n(reset_n),

            .mux_in_data(mux_in.t.data),
            .mux_in_sop(mux_in_sop & M_in_valid[p]),
            .mux_in_eop(mux_in.t.last & M_in_valid[p]),
            .mux_in_valid(M_in_valid[p]),
            .mux_out_ready(demux_out[p].tready),

            .mux_in_ready(M_in_ready[p]),
            .mux_out_data(D_out_data[p]),
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
        if (M_IN_DATA_WIDTH != demux_out[0].TDATA_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: mux_in (%0d)/demux_out (%0d) width mismatch!",
                   M_IN_DATA_WIDTH, demux_out[0].TDATA_WIDTH);
        end

        if (M_OUT_DATA_WIDTH != demux_in[0].TDATA_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: mux_out (%0d)/demux_in (%0d) width mismatch!",
                   M_OUT_DATA_WIDTH, demux_in[0].TDATA_WIDTH);
        end

        if (mux_in.TUSER_WIDTH < $clog2(NUM_DEMUX_PORTS))
        begin
            $fatal(2, "** ERROR ** %m: mux_in port selector (%0d) too small for %0d demux ports!",
                   mux_in.TUSER_WIDTH, NUM_DEMUX_PORTS);
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_prim_vchan_mux
