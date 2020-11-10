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

//
// Service multiple Avalon source interfaces with a single sink interface.
// The most common use of this module in the PIM is for testing: simulating
// platforms with multiple Avalon host channels on platforms with only a
// single host interface. Developers are free to use it for other purposes.
//

`include "ofs_plat_if.vh"

module ofs_plat_avalon_mem_rdwr_if_mux
  #(
    parameter NUM_SOURCE_PORTS = 2,

    // Tracker depths govern the maximum number of bursts that may be in flight.
    parameter RD_TRACKER_DEPTH = 256,
    parameter WR_TRACKER_DEPTH = 128,

    // Shift in this many zero bits at the low end of sink user fields.
    // This simplifies protocol transformations after the MUX.
    parameter SINK_USER_SHIFT = 0
    )
   (
    ofs_plat_avalon_mem_rdwr_if.to_sink mem_sink,
    ofs_plat_avalon_mem_rdwr_if.to_source_clk mem_source[NUM_SOURCE_PORTS]
    );

    wire clk;
    assign clk = mem_sink.clk;

    logic reset_n = 1'b0;
    always @(posedge clk)
    begin
        reset_n <= mem_sink.reset_n;
    end

    // Avalon returns responses in order. The MUX will use FIFOs to route
    // responses to the proper source.
    typedef logic [$clog2(NUM_SOURCE_PORTS)-1 : 0] t_port_idx;

    // All sink and source address, data and burst count sizes must match.
    localparam ADDR_WIDTH = mem_sink.ADDR_WIDTH_;
    localparam DATA_WIDTH = mem_sink.DATA_WIDTH_;
    localparam DATA_N_BYTES = mem_sink.DATA_N_BYTES;
    localparam BURST_CNT_WIDTH = mem_sink.BURST_CNT_WIDTH_;

    // Preserve source's user, rd_user and wr_user fields. We assume that
    // all source ports have the same width.
    localparam USER_WIDTH = mem_source[0].USER_WIDTH_;

    typedef logic [ADDR_WIDTH-1:0] t_addr;
    typedef logic [DATA_WIDTH-1:0] t_data;
    typedef logic [BURST_CNT_WIDTH-1:0] t_burstcount;
    typedef logic [DATA_N_BYTES-1:0] t_byteenable;
    typedef logic [USER_WIDTH-1:0] t_user;

    genvar p;
    generate
        // Multiplex incoming requests into shared_if
        ofs_plat_avalon_mem_rdwr_if
          #(
            `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS(mem_sink)
            )
            shared_if();

        ofs_plat_avalon_mem_rdwr_if_reg conn
           (
            .mem_sink,
            .mem_source(shared_if)
            );

        assign shared_if.clk = mem_sink.clk;
        assign shared_if.reset_n = mem_sink.reset_n;
        assign shared_if.instance_number = mem_sink.instance_number;

        // Fan out clock and reset_n to the source ports
        for (p = 0; p < NUM_SOURCE_PORTS; p = p + 1)
        begin : ctrl
            assign mem_source[p].clk = mem_sink.clk;
            assign mem_source[p].reset_n = mem_sink.reset_n;
            assign mem_source[p].instance_number = mem_sink.instance_number + p;
        end

        // Wrap Avalon control signals in a struct for use in FIFOs
        typedef struct packed {
            t_addr address;
            t_burstcount burstcount;
            t_byteenable byteenable;
            t_user user;
        } t_req;

        // ============================================================
        //
        // Reads
        //
        // ============================================================

        //
        // Push source read requests into a FIFO per port
        //

        t_req rd_req[NUM_SOURCE_PORTS];
        logic [NUM_SOURCE_PORTS-1 : 0] rd_req_deq_en;
        logic [NUM_SOURCE_PORTS-1 : 0] rd_req_notEmpty;

        for (p = 0; p < NUM_SOURCE_PORTS; p = p + 1)
        begin : rd_buf_req
            t_req rd_source_req;
            assign rd_source_req.address = mem_source[p].rd_address;
            assign rd_source_req.burstcount = mem_source[p].rd_burstcount;
            assign rd_source_req.byteenable = mem_source[p].rd_byteenable;
            assign rd_source_req.user = mem_source[p].rd_user;

            logic rd_req_in_notFull;
            assign mem_source[p].rd_waitrequest = ! rd_req_in_notFull;

            ofs_plat_prim_fifo2
              #(
                .N_DATA_BITS($bits(t_req))
                )
              rd_req_in
               (
                .clk,
                .reset_n,
                .enq_data(rd_source_req),
                .enq_en(mem_source[p].rd_read && rd_req_in_notFull),
                .notFull(rd_req_in_notFull),
                .first(rd_req[p]),
                .deq_en(rd_req_deq_en[p]),
                .notEmpty(rd_req_notEmpty[p])
                );
        end

        //
        // Round-robin arbitration to pick a request from among the
        // active sources.
        //
        t_port_idx rd_grantIdx;
        logic rd_tracker_notFull;

        ofs_plat_prim_arb_rr
          #(
            .NUM_CLIENTS(NUM_SOURCE_PORTS)
            )
          rd_arb
           (
            .clk,
            .reset_n,
            .ena(! shared_if.rd_waitrequest && rd_tracker_notFull),
            .request(rd_req_notEmpty),
            .grant(rd_req_deq_en),
            .grantIdx(rd_grantIdx)
            );

        // Forward the winner
        always_comb
        begin
            shared_if.rd_address = rd_req[rd_grantIdx].address;
            shared_if.rd_read = (|(rd_req_deq_en));
            shared_if.rd_burstcount = rd_req[rd_grantIdx].burstcount;
            shared_if.rd_byteenable = rd_req[rd_grantIdx].byteenable;
            shared_if.rd_user = '0;
            shared_if.rd_user[SINK_USER_SHIFT +: USER_WIDTH] = rd_req[rd_grantIdx].user;
        end

        // Track the port and burst length of winners in order to send
        // responses to the proper port.
        t_burstcount rd_rsp_burstcount;
        t_port_idx rd_rsp_port_idx;
        t_user rd_rsp_user;
        logic rd_tracker_deq_en;

        ofs_plat_prim_fifo_bram
          #(
            .N_DATA_BITS($bits(t_user) + $bits(t_burstcount) + $bits(t_port_idx)),
            .N_ENTRIES(RD_TRACKER_DEPTH)
            )
          fifo_rd_track
           (
            .clk,
            .reset_n,
            .enq_data({ rd_req[rd_grantIdx].user,
                        shared_if.rd_burstcount,
                        rd_grantIdx }),
            .enq_en(shared_if.rd_read),
            .notFull(rd_tracker_notFull),
            .almostFull(),
            .first({ rd_rsp_user,
                     rd_rsp_burstcount,
                     rd_rsp_port_idx }),
            .deq_en(rd_tracker_deq_en),
            .notEmpty()
            );

        //
        // Forward sink responses back to the proper source.
        //
        for (p = 0; p < NUM_SOURCE_PORTS; p = p + 1)
        begin : rd_rsp
            always_ff @(posedge clk)
            begin
                mem_source[p].rd_readdatavalid <= shared_if.rd_readdatavalid &&
                                                  (rd_rsp_port_idx == t_port_idx'(p));
                mem_source[p].rd_readdata <= shared_if.rd_readdata;
                mem_source[p].rd_response <= shared_if.rd_response;
                mem_source[p].rd_readresponseuser <= rd_rsp_user;
            end
        end

        // Pop tracker FIFO at the end of each burst
        t_burstcount rd_track_flit_num;
        assign rd_tracker_deq_en = shared_if.rd_readdatavalid &&
                                   (rd_track_flit_num == rd_rsp_burstcount);

        always_ff @(posedge clk)
        begin
            if (!reset_n || rd_tracker_deq_en)
            begin
                rd_track_flit_num <= t_burstcount'(1);
            end
            else if (shared_if.rd_readdatavalid)
            begin
                rd_track_flit_num <= rd_track_flit_num + t_burstcount'(1);
            end
        end


        // ============================================================
        //
        // Writes
        //
        // ============================================================

        t_req wr_req[NUM_SOURCE_PORTS];
        logic [NUM_SOURCE_PORTS-1 : 0] wr_req_deq_en;
        logic [NUM_SOURCE_PORTS-1 : 0] wr_req_notEmpty;
        t_data wr_writedata[NUM_SOURCE_PORTS];

        for (p = 0; p < NUM_SOURCE_PORTS; p = p + 1)
        begin : wr_buf_req
            t_req wr_source_req;
            assign wr_source_req.address = mem_source[p].wr_address;
            assign wr_source_req.burstcount = mem_source[p].wr_burstcount;
            assign wr_source_req.byteenable = mem_source[p].wr_byteenable;
            assign wr_source_req.user = mem_source[p].wr_user;

            logic wr_req_in_notFull;
            assign mem_source[p].wr_waitrequest = ! wr_req_in_notFull;

            ofs_plat_prim_fifo2
              #(
                .N_DATA_BITS($bits(t_data) + $bits(t_req))
                )
              wr_req_in
               (
                .clk,
                .reset_n,
                .enq_data({ mem_source[p].wr_writedata, wr_source_req }),
                .enq_en(mem_source[p].wr_write && wr_req_in_notFull),
                .notFull(wr_req_in_notFull),
                .first({ wr_writedata[p], wr_req[p] }),
                .deq_en(wr_req_deq_en[p]),
                .notEmpty(wr_req_notEmpty[p])
                );
        end

        //
        // Round-robin arbitration to pick a request from among the
        // active sources. Once a write burst starts, arbitration
        // stays with the port until the burst is complete.
        //
        logic [NUM_SOURCE_PORTS-1 : 0] wr_grant_onehot;
        t_port_idx wr_grantIdx;
        logic wr_tracker_notFull;
        logic wr_sop;

        ofs_plat_prim_arb_rr
          #(
            .NUM_CLIENTS(NUM_SOURCE_PORTS)
            )
          wr_arb
           (
            .clk,
            .reset_n,
            .ena(! shared_if.wr_waitrequest && wr_tracker_notFull && wr_sop),
            .request(wr_req_notEmpty),
            .grant(wr_grant_onehot/*wr_req_deq_en*/),
            .grantIdx(wr_grantIdx)
            );

        // Track SOP, used for arbitration
        ofs_plat_prim_burstcount1_sop_tracker
          #(
            .BURST_CNT_WIDTH(BURST_CNT_WIDTH)
            )
          sop
           (
            .clk,
            .reset_n,
            .flit_valid(shared_if.wr_write && ! shared_if.wr_waitrequest),
            .burstcount(shared_if.wr_burstcount),
            .sop(wr_sop),
            .eop()
            );

        // Lock the winner at SOP
        logic [NUM_SOURCE_PORTS-1 : 0] wr_grant_onehot_hold;
        t_port_idx wr_grantIdx_hold;

        always_ff @(posedge clk)
        begin
            if (wr_sop)
            begin
                wr_grant_onehot_hold <= wr_grant_onehot;
                wr_grantIdx_hold <= wr_grantIdx;
            end
        end

        // Pick the port, either a new arbitration winner or the remainder
        // of a burst.
        t_port_idx wr_winnerIdx;
        assign wr_winnerIdx = wr_sop ? wr_grantIdx : wr_grantIdx_hold;

        // Consume an incoming FIFO either:
        //  - On SOP, based on arbitration winner (already factors in waitrequest)
        //  - On remaining flits in a burst when there is data in the FIFO and
        //    waitrequest isn't asserted.
        assign wr_req_deq_en =
            wr_sop ? wr_grant_onehot :
                     (wr_grant_onehot_hold & wr_req_notEmpty &
                      ~{NUM_SOURCE_PORTS{shared_if.wr_waitrequest}});

        // Forward the winner
        always_comb
        begin
            shared_if.wr_address = wr_req[wr_winnerIdx].address;
            shared_if.wr_write = (|(wr_req_deq_en));
            shared_if.wr_burstcount = wr_req[wr_winnerIdx].burstcount;
            shared_if.wr_byteenable = wr_req[wr_winnerIdx].byteenable;
            shared_if.wr_user = '0;
            shared_if.wr_user[SINK_USER_SHIFT +: USER_WIDTH] = wr_req[wr_winnerIdx].user;
            shared_if.wr_writedata = wr_writedata[wr_winnerIdx];
        end

        // Track the port of winners in order to send responses to the proper port.
        t_port_idx wr_rsp_port_idx;
        t_user wr_rsp_user;

        ofs_plat_prim_fifo_bram
          #(
            .N_DATA_BITS($bits(t_user) + $bits(t_port_idx)),
            .N_ENTRIES(WR_TRACKER_DEPTH)
            )
          fifo_wr_track
           (
            .clk,
            .reset_n,
            .enq_data({ wr_req[wr_winnerIdx].user, wr_grantIdx }),
            .enq_en(wr_sop && (|(wr_grant_onehot))),
            .notFull(wr_tracker_notFull),
            .almostFull(),
            .first({ wr_rsp_user, wr_rsp_port_idx }),
            .deq_en(shared_if.wr_writeresponsevalid),
            .notEmpty()
            );

        //
        // Forward sink responses back to the proper source.
        //
        for (p = 0; p < NUM_SOURCE_PORTS; p = p + 1)
        begin : wr_rsp
            always_ff @(posedge clk)
            begin
                mem_source[p].wr_writeresponsevalid <=
                    shared_if.wr_writeresponsevalid && (wr_rsp_port_idx == t_port_idx'(p));
                mem_source[p].wr_response <= shared_if.wr_response;
                mem_source[p].wr_writeresponseuser <= wr_rsp_user;
            end
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_rdwr_if_mux
