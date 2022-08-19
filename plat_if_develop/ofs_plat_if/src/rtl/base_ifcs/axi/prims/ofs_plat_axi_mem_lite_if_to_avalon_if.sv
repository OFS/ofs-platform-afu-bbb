//
// Copyright (c) 2022, Intel Corporation
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
// Map an AXI lite interface to an either an Avalon split-bus read/write
// interface or a normal Avalon interface.
//
// This primitive is simple:
//
//   - Flow control on read responses to the source is enforced by allowing only
//     a single outstanding read request.
//   - There is no flow control on write responses.
//   - Low bits of AXI read addresses are mapped to Avalon rd_byteenable.
//   - Low bits of AXI write addresses are dropped, but the incoming strb
//     byte mask becomes wr_byteenable.
//

`include "ofs_plat_if.vh"

module ofs_plat_axi_mem_lite_if_to_avalon_rdwr_if
  #(
    // Generate read response metadata internally by holding request ID and
    // user data in a FIFO? Also generates RLAST if non-zero.
    parameter GEN_RD_RESPONSE_METADATA = 0,

    // Pass user fields back to source? If 0, user responses are set to 0.
    parameter PRESERVE_RESPONSE_USER = 1
    )
   (
    ofs_plat_avalon_mem_rdwr_if.to_sink avmm_sink,
    ofs_plat_axi_mem_lite_if.to_source axi_source
    );

    logic clk;
    assign clk = avmm_sink.clk;
    logic reset_n;
    assign reset_n = avmm_sink.reset_n;

    localparam ADDR_WIDTH = avmm_sink.ADDR_WIDTH;
    typedef logic [ADDR_WIDTH-1 : 0] t_addr;
    localparam AXI_ADDR_START_BIT = axi_source.ADDR_WIDTH - avmm_sink.ADDR_WIDTH;

    localparam DATA_WIDTH = avmm_sink.DATA_WIDTH;
    typedef logic [DATA_WIDTH-1 : 0] t_data;

    localparam BYTE_ENABLE_WIDTH = avmm_sink.DATA_N_BYTES;
    typedef logic [BYTE_ENABLE_WIDTH-1 : 0] t_byteenable;

    // AXI interface used internally as a convenient way to recreate
    // the data structures.
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(axi_source)
        )
      axi_reg();

    // ====================================================================
    //
    //  Reads
    //
    // ====================================================================

    // Pass read requests through a FIFO. This is done because the AW
    // pipeline has a FIFO and imposing the same delay on reads helps
    // keep them ordered. (Not well, but at least not worse.)
    localparam T_AR_WIDTH = axi_source.T_AR_WIDTH;

    // One read at a time to avoid dealing with flow control. We assume that
    // AXI lite is low bandwidth, such as a CSR bus.
    logic rd_not_busy;
    localparam METADATA_WIDTH = axi_source.USER_WIDTH + axi_source.RID_WIDTH;
    logic [METADATA_WIDTH-1 : 0] rd_preserved_metadata;

    wire fwd_rd_req = !avmm_sink.rd_waitrequest && axi_reg.arvalid && rd_not_busy;

    // Read address
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(T_AR_WIDTH)
        )
      ar_fifo
       (
        .clk,
        .reset_n,
        .enq_data(axi_source.ar),
        .enq_en(axi_source.arready && axi_source.arvalid),
        .notFull(axi_source.arready),
        .first(axi_reg.ar),
        .deq_en(fwd_rd_req),
        .notEmpty(axi_reg.arvalid)
        );

    always_comb
    begin
        // Read request
        avmm_sink.rd_read = axi_reg.arvalid && rd_not_busy;
        avmm_sink.rd_address = axi_reg.ar.addr[AXI_ADDR_START_BIT +: ADDR_WIDTH];
        avmm_sink.rd_burstcount = 1;
        // Map AXI size and low address bits to an Avalon byte mask
        avmm_sink.rd_byteenable =
            BYTE_ENABLE_WIDTH'(
                ofs_plat_axi_mem_pkg::beat_size_to_byte_mask(axi_reg.ar.size) <<
                axi_reg.ar.addr[AXI_ADDR_START_BIT-1 : 0]);
        avmm_sink.rd_user = { axi_reg.ar.user, axi_reg.ar.id };
    end

    always_ff @(posedge clk)
    begin
        if (axi_source.rvalid && axi_source.rready)
        begin
            // Pending read response complete. Allow the next read request.
            rd_not_busy <= 1'b1;
            axi_source.rvalid <= 1'b0;
        end
        else if (axi_reg.arvalid && axi_reg.arready)
        begin
            // New read request
            rd_not_busy <= 1'b0;
            rd_preserved_metadata <= { axi_reg.ar.user, axi_reg.ar.id };
        end

        // Read response. Register the response and wait for axi_source.rready.
        // With only one request allowed to be outstanding, no FIFO is needed.
        if (avmm_sink.rd_readdatavalid)
        begin
            axi_source.rvalid <= 1'b1;
            axi_source.r <= '0;
            axi_source.r.data <= avmm_sink.rd_readdata;
            axi_source.r.resp <= avmm_sink.rd_response;

            // Read response metadata. Either consume it from the sink or generate
            // it locally by saving request state and matching it with responses.
            if (GEN_RD_RESPONSE_METADATA == 0)
            begin
                { axi_source.r.user, axi_source.r.id } <= avmm_sink.rd_readresponseuser;
                if (PRESERVE_RESPONSE_USER == 0)
                begin
                    axi_source.r.user <= '0;
                end
            end
            else
            begin
                { axi_source.r.user, axi_source.r.id } <= rd_preserved_metadata;
            end
        end

        if (!reset_n)
        begin
            rd_not_busy <= 1'b1;
            axi_source.rvalid <= 1'b0;
        end
    end


    // ====================================================================
    //
    //  Writes
    //
    // ====================================================================

    // Pass write address and data streams through FIFOs since they must
    // be merged to form an Avalon request.
    localparam T_AW_WIDTH = axi_source.T_AW_WIDTH;
    localparam T_W_WIDTH = axi_source.T_W_WIDTH;
    localparam AVMM_USER_WIDTH = avmm_sink.USER_WIDTH;

    // Protocol components mostly not used -- just using as a container
    assign axi_reg.awready = 1'b0;
    assign axi_reg.wready = 1'b0;
    assign axi_reg.bvalid = 1'b0;
    assign axi_reg.bready = 1'b0;
    assign axi_reg.arready = 1'b0;
    assign axi_reg.rvalid = 1'b0;
    assign axi_reg.rready = 1'b0;

    wire fwd_wr_req = !avmm_sink.wr_waitrequest &&
                      axi_reg.awvalid && axi_reg.wvalid;

    // Write address
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS(T_AW_WIDTH)
        )
      aw_fifo
       (
        .clk,
        .reset_n,
        .enq_data(axi_source.aw),
        .enq_en(axi_source.awready && axi_source.awvalid),
        .notFull(axi_source.awready),
        .first(axi_reg.aw),
        .deq_en(fwd_wr_req),
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
        .enq_data(axi_source.w),
        .enq_en(axi_source.wready && axi_source.wvalid),
        .notFull(axi_source.wready),
        .first(axi_reg.w),
        .deq_en(fwd_wr_req),
        .notEmpty(axi_reg.wvalid)
        );

    always_comb
    begin
        avmm_sink.wr_write = axi_reg.awvalid && axi_reg.wvalid;
        avmm_sink.wr_writedata = axi_reg.w.data;
        avmm_sink.wr_byteenable = axi_reg.w.strb;
        avmm_sink.wr_address = axi_reg.aw.addr[AXI_ADDR_START_BIT +: ADDR_WIDTH];
        avmm_sink.wr_burstcount = 1;
        avmm_sink.wr_user = { axi_reg.aw.user, axi_reg.aw.id };

        // No flow control supported on write responses here. If needed, put
        // a FIFO outside this module.
        axi_source.bvalid = avmm_sink.wr_writeresponsevalid;
        axi_source.b.resp = avmm_sink.wr_response;

        { axi_source.b.user, axi_source.b.id } = avmm_sink.wr_writeresponseuser;
        if (PRESERVE_RESPONSE_USER == 0)
        begin
            axi_source.b.user = '0;
        end
    end


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
        if (AXI_ADDR_START_BIT != axi_source.ADDR_BYTE_IDX_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: Address width mismatch, Avalon %0d and AXI %0d bits!",
                   avmm_sink.ADDR_WIDTH, axi_source.ADDR_WIDTH);
        end
        if (avmm_sink.USER_WIDTH < (axi_source.USER_WIDTH + axi_source.RID_WIDTH))
        begin
            $fatal(2, "** ERROR ** %m: Avalon user width (%0d) smaller than AXI user+rid (%0d, %0d)!",
                   avmm_sink.USER_WIDTH, axi_source.USER_WIDTH, axi_source.RID_WIDTH);
        end
        if (avmm_sink.USER_WIDTH < (axi_source.USER_WIDTH + axi_source.WID_WIDTH))
        begin
            $fatal(2, "** ERROR ** %m: Avalon user width (%0d) smaller than AXI user+wid (%0d, %0d)!",
                   avmm_sink.USER_WIDTH, axi_source.USER_WIDTH, axi_source.WID_WIDTH);
        end
        if (avmm_sink.DATA_WIDTH < axi_source.DATA_WIDTH)
        begin
            $fatal(2, "** ERROR ** %m: Avalon data width (%0d) smaller than AXI (%0d)!",
                   avmm_sink.DATA_WIDTH, axi_source.DATA_WIDTH);
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_axi_mem_lite_if_to_avalon_rdwr_if


//
// Map AXI lite to normal Avalon. The Avalon read/write mapper above is used as
// an intermediate step.
//
module ofs_plat_axi_mem_lite_if_to_avalon_if
  #(
    // Generate read response metadata internally by holding request ID and
    // user data in a FIFO? Also generates RLAST if non-zero.
    parameter GEN_RD_RESPONSE_METADATA = 0,

    // Pass user fields back to source? If 0, user responses are set to 0.
    parameter PRESERVE_RESPONSE_USER = 1,

    // Generate a write response inside this module as write requests
    // commit? Some Avalon sinks may not generate write responses.
    // With LOCAL_WR_RESPONSE set, write responses are generated as
    // soon as write requests win arbitration.
    parameter LOCAL_WR_RESPONSE = 0
    )
   (
    ofs_plat_avalon_mem_if.to_sink avmm_sink,
    ofs_plat_axi_mem_lite_if.to_source axi_source
    );

    logic clk;
    assign clk = avmm_sink.clk;
    logic reset_n;
    assign reset_n = avmm_sink.reset_n;

    //
    // Map AXI lite to Avalon split read/write.
    //
    ofs_plat_avalon_mem_rdwr_if
      #(
        `OFS_PLAT_AVALON_MEM_IF_REPLICATE_PARAMS(avmm_sink)
        )
        avmm_rdwr();

    assign avmm_rdwr.instance_number = avmm_sink.instance_number;
    assign avmm_rdwr.clk = clk;
    assign avmm_rdwr.reset_n = reset_n;

    ofs_plat_axi_mem_lite_if_to_avalon_rdwr_if
      #(
        .GEN_RD_RESPONSE_METADATA(GEN_RD_RESPONSE_METADATA),
        .PRESERVE_RESPONSE_USER(PRESERVE_RESPONSE_USER)
        )
      map_avmm_rdwr
       (
        .axi_source(axi_source),
        .avmm_sink(avmm_rdwr)
        );

    //
    // Now map the split Avalon interface to standard Avalon.
    //
    ofs_plat_avalon_mem_rdwr_if_to_mem_if
      #(
        .LOCAL_WR_RESPONSE(LOCAL_WR_RESPONSE)
        )
      map_avmm
       (
        .mem_source(avmm_rdwr),
        .mem_sink(avmm_sink)
        );

endmodule // ofs_plat_axi_mem_lite_if_to_avalon_if
