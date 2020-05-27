//
// Copyright (c) 2019, Intel Corporation
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
// Map an AXI memory interface to an Avalon split-bus read/write interface.
// This primitive is simple:
//
//   - Flow control on responses to the master is NOT enforced! It is up
//     to the AXI master to provide enough buffering to accept all pending
//     responses.
//   - RLAST is not generated.
//   - The Avalon slave must accept bursts at least as large as the
//     AXI master can generate.
//   - The Avalon user width must hold the AXI ID and USER fields.
//   - Data width must match.
//   - AXI AWSIZE and ARSIZE must be the full bus width.
//   - Low bits of AXI addresses (those below the bus width) must be 0.
//

`include "ofs_plat_if.vh"

module ofs_plat_axi_mem_if_to_avalon_rdwr_if
  #(
    // Generate read response metadata internally by holding request ID and
    // user data in a FIFO? Also generates RLAST if non-zero.
    parameter GEN_RD_RESPONSE_METADATA = 0,

    parameter RD_RESPONSE_FIFO_DEPTH = 256
    )
   (
    ofs_plat_avalon_mem_rdwr_if.to_slave avmm_slave,
    ofs_plat_axi_mem_if.to_master axi_master
    );

    logic clk;
    assign clk = avmm_slave.clk;
    logic reset_n;
    assign reset_n = avmm_slave.reset_n;

    localparam ADDR_WIDTH = avmm_slave.ADDR_WIDTH;
    typedef logic [ADDR_WIDTH-1 : 0] t_addr;
    localparam AXI_ADDR_START_BIT = axi_master.ADDR_WIDTH - avmm_slave.ADDR_WIDTH;

    localparam DATA_WIDTH = avmm_slave.DATA_WIDTH;
    typedef logic [DATA_WIDTH-1 : 0] t_data;

    localparam BYTE_ENABLE_WIDTH = avmm_slave.DATA_N_BYTES;
    typedef logic [BYTE_ENABLE_WIDTH-1 : 0] t_byteenable;

    localparam BURST_CNT_WIDTH = avmm_slave.BURST_CNT_WIDTH;
    typedef logic [BURST_CNT_WIDTH-1 : 0] t_burst_cnt;


    // ====================================================================
    //
    //  Reads
    //
    // ====================================================================

    // Stop traffic on read error
    (* preserve *) logic rd_error;

    logic rd_meta_fifo_ready;

    always_comb
    begin
        // Read request
        axi_master.arready = !avmm_slave.rd_waitrequest && rd_meta_fifo_ready;
        avmm_slave.rd_read = axi_master.arvalid;
        avmm_slave.rd_address = axi_master.ar.addr[AXI_ADDR_START_BIT +: ADDR_WIDTH];
        avmm_slave.rd_burstcount = t_burst_cnt'(axi_master.ar.len) + 1;
        avmm_slave.rd_byteenable = ~t_byteenable'(0);
        avmm_slave.rd_function = '0;
        avmm_slave.rd_user = { axi_master.ar.user, axi_master.ar.id };

        // Read response
        axi_master.rvalid = avmm_slave.rd_readdatavalid && !rd_error;
        axi_master.r.data = avmm_slave.rd_readdata;
        axi_master.r.resp = avmm_slave.rd_response;
    end

    // Read response metadata. Either consume it from the slave or generate
    // it locally by saving request state and matching it with responses.
    generate
        if (GEN_RD_RESPONSE_METADATA == 0)
        begin : nrm
            assign rd_meeta_fifo_ready = 1'b1;
            assign { axi_master.r.user, axi_master.r.id } = avmm_slave.rd_readresponseuser;
            assign axi_master.r.last = 'x;
        end
        else
        begin : rm
            ofs_plat_axi_mem_if_to_avalon_rdwr_if_rd_meta
              #(
                .RD_RESPONSE_FIFO_DEPTH(RD_RESPONSE_FIFO_DEPTH),
                .BURST_CNT_WIDTH(axi_master.BURST_CNT_WIDTH),
                .RID_WIDTH(axi_master.RID_WIDTH),
                .USER_WIDTH(axi_master.USER_WIDTH)
                )
              rd_meta
               (
                .clk,
                .reset_n,

                .notFull(rd_meta_fifo_ready),
                .process_req(axi_master.arvalid && axi_master.arready),
                .req_len(axi_master.ar.len),
                .req_id(axi_master.ar.id),
                .req_user(axi_master.ar.user),

                .process_rsp(avmm_slave.rd_readdatavalid && axi_master.rready),
                .rsp_id(axi_master.r.id),
                .rsp_user(axi_master.r.user),
                .rsp_last(axi_master.r.last)
                );
        end
    endgenerate

    always_ff @(posedge clk)
    begin
        if (!axi_master.rready && axi_master.rvalid)
        begin
            rd_error <= 1'b1;
        end

        if (!reset_n)
        begin
            rd_error <= 1'b0;
        end
    end

    // synthesis translate_off
    always_ff @(negedge clk)
    begin
        if (reset_n && rd_error)
            $fatal(2, "** ERROR ** %m: Lost read response -- master must have its own read response buffering!");

        if (reset_n)
        begin
            assert(!axi_master.arvalid || (axi_master.ar.addr[AXI_ADDR_START_BIT-1 : 0] == '0)) else
                $fatal(2, "** ERROR ** %m: Low read address bits must be 0, addr %x", axi_master.ar.addr);
        end
    end
    // synthesis translate_on


    // ====================================================================
    //
    //  Writes
    //
    // ====================================================================

    // Stop traffic on write error
    (* preserve *) logic wr_error;

    // Pass write address and data streams through FIFOs since they must
    // be merged to form an Avalon request.
    localparam T_AW_WIDTH = axi_master.T_AW_WIDTH;
    localparam T_W_WIDTH = axi_master.T_W_WIDTH;

    // AXI interface used internally as a convenient way to recreate
    // the data structures.
    ofs_plat_axi_mem_if
      #(
        `OFS_PLAT_AXI_MEM_IF_REPLICATE_PARAMS(axi_master)
        )
      axi_reg();

    // Protocol components mostly not used -- just using as a container
    assign axi_reg.awready = 1'b0;
    assign axi_reg.wready = 1'b0;
    assign axi_reg.bvalid = 1'b0;
    assign axi_reg.bready = 1'b0;
    assign axi_reg.arvalid = 1'b0;
    assign axi_reg.arready = 1'b0;
    assign axi_reg.rvalid = 1'b0;
    assign axi_reg.rready = 1'b0;

    logic wr_is_sop;
    logic fwd_wr_req;
    assign fwd_wr_req = !avmm_slave.wr_waitrequest &&
                        (axi_reg.awvalid || !wr_is_sop) &&
                        axi_reg.wvalid;

    // Write address
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(T_AW_WIDTH)
        )
      aw_fifo
       (
        .clk,
        .reset_n,
        .enq_data(axi_master.aw),
        .enq_en(axi_master.awready && axi_master.awvalid),
        .notFull(axi_master.awready),
        .first(axi_reg.aw),
        .deq_en(fwd_wr_req && wr_is_sop),
        .notEmpty(axi_reg.awvalid)
        );

    // Write data
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(T_W_WIDTH)
        )
      w_fifo
       (
        .clk,
        .reset_n,
        .enq_data(axi_master.w),
        .enq_en(axi_master.wready && axi_master.wvalid),
        .notFull(axi_master.wready),
        .first(axi_reg.w),
        .deq_en(fwd_wr_req),
        .notEmpty(axi_reg.wvalid)
        );

    // Track write SOP in order to know when to consume a new address
    always_ff @(posedge clk)
    begin
        if (fwd_wr_req)
        begin
            wr_is_sop <= axi_reg.w.last;
        end

        if (!reset_n)
        begin
            wr_is_sop <= 1'b1;
        end
    end

    always_comb
    begin
        avmm_slave.wr_write = (axi_reg.awvalid || !wr_is_sop) && axi_reg.wvalid;
        avmm_slave.wr_writedata = axi_reg.w.data;
        avmm_slave.wr_byteenable = axi_reg.w.strb;
        avmm_slave.wr_function = '0;
        if (wr_is_sop)
        begin
            avmm_slave.wr_address = axi_reg.aw.addr[AXI_ADDR_START_BIT +: ADDR_WIDTH];
            avmm_slave.wr_burstcount = t_burst_cnt'(axi_reg.aw.len) + 1;
            avmm_slave.wr_user = { axi_reg.aw.user, axi_reg.aw.id };
        end
        else
        begin
            avmm_slave.wr_address = 'x;
            avmm_slave.wr_burstcount = 'x;
            avmm_slave.wr_user = 'x;
        end

        axi_master.bvalid = avmm_slave.wr_writeresponsevalid && !wr_error;
        axi_master.b.resp = avmm_slave.wr_response;
        { axi_master.b.user, axi_master.b.id } = avmm_slave.wr_writeresponseuser;
    end

    always_ff @(posedge clk)
    begin
        if (!axi_master.bready && axi_master.bvalid)
        begin
            wr_error <= 1'b1;
        end

        if (!reset_n)
        begin
            wr_error <= 1'b0;
        end
    end

    // synthesis translate_off
    always_ff @(negedge clk)
    begin
        if (reset_n && wr_error)
            $fatal(2, "** ERROR ** %m: Lost write response -- master must have its own write response buffering!");

        if (reset_n)
        begin
            assert(!axi_master.awvalid || (axi_master.aw.addr[AXI_ADDR_START_BIT-1 : 0] == '0)) else
                $fatal(2, "** ERROR ** %m: Low write address bits must be 0, addr %x", axi_master.aw.addr);
        end
    end
    // synthesis translate_on


    // ====================================================================
    //
    //  Validation
    //
    // ====================================================================

    // synthesis translate_off
    initial
    begin
        // After dropping AXI address bits that are byte offsets into the data width,
        // the address widths should match.
        if (AXI_ADDR_START_BIT != axi_master.ADDR_BYTE_IDX_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: Address width mismatch, Avalon %0d and AXI %0d bits!",
                   avmm_slave.ADDR_WIDTH, axi_master.ADDR_WIDTH);
        end
        if (avmm_slave.BURST_CNT_WIDTH <= axi_master.BURST_CNT_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: Avalon burst width (%0d) smaller than AXI (%0d)!",
                   avmm_slave.BURST_CNT_WIDTH, axi_master.BURST_CNT_WIDTH);
        end
        if (avmm_slave.USER_WIDTH < (axi_master.USER_WIDTH + axi_master.RID_WIDTH))
        begin
            $fatal(2, "** ERROR ** %m: Avalon user width (%0d) smaller than AXI user+rid (%0d, %0d)!",
                   avmm_slave.USER_WIDTH, axi_master.USER_WIDTH, axi_master.RID_WIDTH);
        end
        if (avmm_slave.USER_WIDTH < (axi_master.USER_WIDTH + axi_master.WID_WIDTH))
        begin
            $fatal(2, "** ERROR ** %m: Avalon user width (%0d) smaller than AXI user+wid (%0d, %0d)!",
                   avmm_slave.USER_WIDTH, axi_master.USER_WIDTH, axi_master.WID_WIDTH);
        end
        if (avmm_slave.DATA_WIDTH < axi_master.DATA_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: Avalon data width (%0d) smaller than AXI (%0d)!",
                   avmm_slave.DATA_WIDTH, axi_master.DATA_WIDTH);
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_avalon_mem_if_to_rdwr_if


//
// Track read metadata (RID, RUSER and RLAST) by storing them in a FIFO as
// requests arrive. Avalon returns responses in order, so we can match them
// with responses from the slave.
//
module ofs_plat_axi_mem_if_to_avalon_rdwr_if_rd_meta
  #(
    parameter RD_RESPONSE_FIFO_DEPTH = 256,
    parameter BURST_CNT_WIDTH = 8,
    parameter RID_WIDTH = 1,
    parameter USER_WIDTH = 1
    )
   (
    input  logic clk,
    input  logic reset_n,

    output logic notFull,
    input  logic process_req,
    input  logic [BURST_CNT_WIDTH-1 : 0] req_len,
    input  logic [RID_WIDTH-1 : 0] req_id,
    input  logic [USER_WIDTH-1 : 0] req_user,

    input  logic process_rsp,
    output logic [RID_WIDTH-1 : 0] rsp_id,
    output logic [USER_WIDTH-1 : 0] rsp_user,
    output logic rsp_last
    );

    logic [BURST_CNT_WIDTH-1 : 0] rsp_len;

    // Store request metadata as it arrives, then return it with ordered responses.
    ofs_plat_prim_fifo_lutram
      #(
        .N_DATA_BITS(BURST_CNT_WIDTH + RID_WIDTH + USER_WIDTH),
        .N_ENTRIES(RD_RESPONSE_FIFO_DEPTH),
        .REGISTER_OUTPUT(1)
        )
      meta_fifo
       (
        .clk,
        .reset_n,
        .enq_data({ req_len, req_id, req_user }),
        .enq_en(process_req),
        .notFull,
        .first({ rsp_len, rsp_id, rsp_user }),
        .deq_en(process_rsp && rsp_last),
        .notEmpty(),
        .almostFull()
        );

    // Track eop (last) on response stream.
    ofs_plat_prim_burstcount0_sop_tracker
      #(
        .BURST_CNT_WIDTH(BURST_CNT_WIDTH)
        )
      sop_tracker
       (
        .clk,
        .reset_n,
        .flit_valid(process_rsp),
        .burstcount(rsp_len),
        .sop(),
        .eop(rsp_last)
        );

endmodule // ofs_plat_axi_mem_if_to_avalon_rdwr_if_rd_meta
