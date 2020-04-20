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
// Service multiple Avalon master interfaces with a single slave interface.
// The most common use of this module in the PIM is for testing: simulating
// platforms with multiple Avalon host channels on platforms with only a
// single host interface. Developers are free to use it for other purposes.
//

`include "ofs_plat_if.vh"

module ofs_plat_avalon_mem_rdwr_if_mux
  #(
    parameter NUM_MASTER_PORTS = 2,

    // Tracker depths govern the maximum number of bursts that may be in flight.
    parameter RD_TRACKER_DEPTH = 256,
    parameter WR_TRACKER_DEPTH = 128
    )
   (
    ofs_plat_avalon_mem_rdwr_if.to_slave mem_slave,
    ofs_plat_avalon_mem_rdwr_if.to_master_clk mem_master[NUM_MASTER_PORTS]
    );

    wire clk;
    assign clk = mem_slave.clk;

    logic reset_n = 1'b0;
    always @(posedge clk)
    begin
        reset_n <= mem_slave.reset_n;
    end

    // Avalon returns responses in order. The MUX will use FIFOs to route
    // responses to the proper master.
    typedef logic [$clog2(NUM_MASTER_PORTS)-1 : 0] t_port_idx;

    // All slave and master address, data and burst count sizes must match.
    localparam ADDR_WIDTH = mem_slave.ADDR_WIDTH_;
    localparam DATA_WIDTH = mem_slave.DATA_WIDTH_;
    localparam DATA_N_BYTES = mem_slave.DATA_N_BYTES;
    localparam BURST_CNT_WIDTH = mem_slave.BURST_CNT_WIDTH_;

    typedef logic [ADDR_WIDTH-1:0] t_addr;
    typedef logic [DATA_WIDTH-1:0] t_data;
    typedef logic [BURST_CNT_WIDTH-1:0] t_burstcount;
    typedef logic [DATA_N_BYTES-1:0] t_byteenable;

    genvar p;
    generate
        if (NUM_MASTER_PORTS < 2)
        begin : nm
            // No MUX required with only one master port
            ofs_plat_avalon_mem_rdwr_if_connect_slave_clk conn
               (
                .mem_slave,
                .mem_master(mem_master[0])
                );
        end
        else
        begin : m
            // Multiplex incoming requests into shared_if
            ofs_plat_avalon_mem_rdwr_if
              #(
                `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_PARAMS(mem_slave)
                )
                shared_if();

            ofs_plat_avalon_mem_rdwr_if_reg conn
               (
                .mem_slave,
                .mem_master(shared_if)
                );

            assign shared_if.clk = mem_slave.clk;
            assign shared_if.reset_n = mem_slave.reset_n;
            assign shared_if.instance_number = mem_slave.instance_number;

            // Fan out clock and reset_n to the master ports
            for (p = 0; p < NUM_MASTER_PORTS; p = p + 1)
            begin : ctrl
                assign mem_master[p].clk = mem_slave.clk;
                assign mem_master[p].reset_n = mem_slave.reset_n;
                assign mem_master[p].instance_number = mem_slave.instance_number + p;
            end

            // Wrap Avalon control signals in a struct for use in FIFOs
            typedef struct packed {
                t_addr address;
                t_burstcount burstcount;
                t_byteenable byteenable;
                logic func;
            } t_req;

            // ============================================================
            //
            // Reads
            //
            // ============================================================

            //
            // Push master read requests into a FIFO per port
            //

            t_req rd_req[NUM_MASTER_PORTS];
            logic [NUM_MASTER_PORTS-1 : 0] rd_req_deq_en;
            logic [NUM_MASTER_PORTS-1 : 0] rd_req_notEmpty;

            for (p = 0; p < NUM_MASTER_PORTS; p = p + 1)
            begin : rd_buf_req
                t_req rd_master_req;
                assign rd_master_req.address = mem_master[p].rd_address;
                assign rd_master_req.burstcount = mem_master[p].rd_burstcount;
                assign rd_master_req.byteenable = mem_master[p].rd_byteenable;
                assign rd_master_req.func = mem_master[p].rd_function;

                logic rd_req_in_notFull;
                assign mem_master[p].rd_waitrequest = ! rd_req_in_notFull;

                ofs_plat_prim_fifo2
                  #(
                    .N_DATA_BITS($bits(t_req))
                    )
                  rd_req_in
                   (
                    .clk,
                    .reset_n,
                    .enq_data(rd_master_req),
                    .enq_en(mem_master[p].rd_read && rd_req_in_notFull),
                    .notFull(rd_req_in_notFull),
                    .first(rd_req[p]),
                    .deq_en(rd_req_deq_en[p]),
                    .notEmpty(rd_req_notEmpty[p])
                    );
            end

            //
            // Round-robin arbitration to pick a request from among the
            // active masters.
            //
            t_port_idx rd_grantIdx;
            logic rd_tracker_notFull;

            ofs_plat_prim_arb_rr
              #(
                .NUM_CLIENTS(NUM_MASTER_PORTS)
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
                shared_if.rd_function = rd_req[rd_grantIdx].func;
            end

            // Track the port and burst length of winners in order to send
            // responses to the proper port.
            t_burstcount rd_rsp_burstcount;
            t_port_idx rd_rsp_port_idx;
            logic rd_tracker_deq_en;

            ofs_plat_prim_fifo_bram
              #(
                .N_DATA_BITS($bits(t_burstcount) + $bits(t_port_idx)),
                .N_ENTRIES(RD_TRACKER_DEPTH)
                )
              fifo_rd_track
               (
                .clk,
                .reset_n,
                .enq_data({ shared_if.rd_burstcount, rd_grantIdx }),
                .enq_en(shared_if.rd_read),
                .notFull(rd_tracker_notFull),
                .almostFull(),
                .first({ rd_rsp_burstcount, rd_rsp_port_idx }),
                .deq_en(rd_tracker_deq_en),
                .notEmpty()
                );

            //
            // Forward slave responses back to the proper master.
            //
            for (p = 0; p < NUM_MASTER_PORTS; p = p + 1)
            begin : rd_rsp
                always_ff @(posedge clk)
                begin
                    mem_master[p].rd_readdatavalid <= shared_if.rd_readdatavalid &&
                                                      (rd_rsp_port_idx == t_port_idx'(p));
                    mem_master[p].rd_readdata <= shared_if.rd_readdata;
                    mem_master[p].rd_response <= shared_if.rd_response;
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

            t_req wr_req[NUM_MASTER_PORTS];
            logic [NUM_MASTER_PORTS-1 : 0] wr_req_deq_en;
            logic [NUM_MASTER_PORTS-1 : 0] wr_req_notEmpty;
            t_data wr_writedata[NUM_MASTER_PORTS];

            for (p = 0; p < NUM_MASTER_PORTS; p = p + 1)
            begin : wr_buf_req
                t_req wr_master_req;
                assign wr_master_req.address = mem_master[p].wr_address;
                assign wr_master_req.burstcount = mem_master[p].wr_burstcount;
                assign wr_master_req.byteenable = mem_master[p].wr_byteenable;
                assign wr_master_req.func = mem_master[p].wr_function;

                logic wr_req_in_notFull;
                assign mem_master[p].wr_waitrequest = ! wr_req_in_notFull;

                ofs_plat_prim_fifo2
                  #(
                    .N_DATA_BITS($bits(t_data) + $bits(t_req))
                    )
                  wr_req_in
                   (
                    .clk,
                    .reset_n,
                    .enq_data({ mem_master[p].wr_writedata, wr_master_req }),
                    .enq_en(mem_master[p].wr_write && wr_req_in_notFull),
                    .notFull(wr_req_in_notFull),
                    .first({ wr_writedata[p], wr_req[p] }),
                    .deq_en(wr_req_deq_en[p]),
                    .notEmpty(wr_req_notEmpty[p])
                    );
            end

            //
            // Round-robin arbitration to pick a request from among the
            // active masters. Once a write burst starts, arbitration
            // stays with the port until the burst is complete.
            //
            logic [NUM_MASTER_PORTS-1 : 0] wr_grant_onehot;
            t_port_idx wr_grantIdx;
            logic wr_tracker_notFull;
            logic wr_sop;

            ofs_plat_prim_arb_rr
              #(
                .NUM_CLIENTS(NUM_MASTER_PORTS)
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
            logic [NUM_MASTER_PORTS-1 : 0] wr_grant_onehot_hold;
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
                          ~{NUM_MASTER_PORTS{shared_if.wr_waitrequest}});

            // Forward the winner
            always_comb
            begin
                shared_if.wr_address = wr_req[wr_winnerIdx].address;
                shared_if.wr_write = (|(wr_req_deq_en));
                shared_if.wr_burstcount = wr_req[wr_winnerIdx].burstcount;
                shared_if.wr_byteenable = wr_req[wr_winnerIdx].byteenable;
                shared_if.wr_function = wr_req[wr_winnerIdx].func;
                shared_if.wr_writedata = wr_writedata[wr_winnerIdx];
            end

            // Track the port of winners in order to send responses to the proper port.
            t_port_idx wr_rsp_port_idx;

            ofs_plat_prim_fifo_bram
              #(
                .N_DATA_BITS($bits(t_port_idx)),
                .N_ENTRIES(WR_TRACKER_DEPTH)
                )
              fifo_wr_track
               (
                .clk,
                .reset_n,
                .enq_data(wr_grantIdx),
                .enq_en(wr_sop && (|(wr_grant_onehot))),
                .notFull(wr_tracker_notFull),
                .almostFull(),
                .first(wr_rsp_port_idx),
                .deq_en(shared_if.wr_writeresponsevalid),
                .notEmpty()
                );

            //
            // Forward slave responses back to the proper master.
            //
            for (p = 0; p < NUM_MASTER_PORTS; p = p + 1)
            begin : wr_rsp
                always_ff @(posedge clk)
                begin
                    mem_master[p].wr_writeresponsevalid <=
                        shared_if.wr_writeresponsevalid && (wr_rsp_port_idx == t_port_idx'(p));
                    mem_master[p].wr_response <= shared_if.wr_response;
                end
            end
        end
    endgenerate

endmodule // ofs_plat_avalon_mem_rdwr_if_mux
