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
// Generate TLP writes for AFU write requests.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_@group@_gen_wr_tlps
   (
    input  logic clk,
    input  logic reset_n,

    // Write requests from AFU (t_gen_tx_afu_wr_req)
    ofs_plat_axi_stream_if.to_master afu_wr_req,

    // Output write request TLP stream
    ofs_plat_axi_stream_if.to_slave tx_wr_tlps,

    // Write responses to AFU once the packet is completely sent (t_gen_tx_afu_wr_rsp)
    ofs_plat_axi_stream_if.to_slave afu_wr_rsp,

    // Fence completions, processed first by the read response pipeline.
    // (t_dma_rd_tag)
    ofs_plat_axi_stream_if.to_master wr_fence_cpl,

    output logic error
    );

    import ofs_plat_host_chan_@group@_pcie_tlp_pkg::*;
    import ofs_plat_host_chan_@group@_gen_tlps_pkg::*;

    assign error = 1'b0;

    // Byte index in a line to dword index
    function automatic logic [$bits(t_tlp_payload_line_byte_idx)-3:0] dw_idx(
        t_tlp_payload_line_byte_idx b_idx
        );
        return b_idx[$bits(t_tlp_payload_line_byte_idx)-1 : 2];
    endfunction


    // ====================================================================
    //
    //  Store requests in a FIFO for timing.
    //
    // ====================================================================

    t_gen_tx_afu_wr_req wr_req;
    logic wr_req_deq;
    logic wr_req_notEmpty;
    logic wr_req_ready;

    // Canonicalize afu_wr_req
    t_gen_tx_afu_wr_req afu_wr_req_c;
    always_comb
    begin
        afu_wr_req_c = afu_wr_req.t.data;

        if (!afu_wr_req.t.data.enable_byte_range)
        begin
            afu_wr_req_c.byte_start_idx = 0;
        end
    end

    // Pre-compute some byte range handling details on the way in to the
    // skid buffer.
    typedef struct packed {
        t_tlp_payload_line_byte_idx dword_len;
        t_tlp_payload_line_byte_idx byte_end_idx;
    } t_byte_range_req;

    t_byte_range_req br_req_in, br_req;
    assign br_req_in.dword_len =
        (afu_wr_req.t.data.byte_start_idx[1:0] + afu_wr_req.t.data.byte_len + 3) >> 2;
    assign br_req_in.byte_end_idx =
        afu_wr_req.t.data.byte_len + afu_wr_req.t.data.byte_start_idx - 1;

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS($bits(t_byte_range_req) + $bits(t_gen_tx_afu_wr_req))
        )
      afu_req_fifo
       (
        .clk,
        .reset_n,

        .enq_data({ br_req_in, afu_wr_req_c }),
        .enq_en(afu_wr_req.tvalid && afu_wr_req.tready),
        .notFull(afu_wr_req.tready),

        .first({ br_req, wr_req }),
        .deq_en(wr_req_deq),
        .notEmpty(wr_req_notEmpty)
        );


    // ====================================================================
    //
    //  Maintain a UID space for tagging PCIe write fences.
    //
    // ====================================================================

    typedef logic [$clog2(MAX_OUTSTANDING_DMA_WR_FENCES)-1 : 0] t_wr_fence_tag;

    logic wr_rsp_notFull;
    logic req_tlp_tag_ready;
    t_wr_fence_tag req_tlp_tag;

    logic free_tlp_tag;
    t_wr_fence_tag free_tlp_tag_value;

    logic alloc_tlp_tag;
    assign alloc_tlp_tag = wr_req_deq && wr_req.sop && wr_req.is_fence;

    ofs_plat_prim_uid
      #(
        .N_ENTRIES(MAX_OUTSTANDING_DMA_WR_FENCES)
        )
      tags
       (
        .clk,
        .reset_n,

        // New tag needed when either the write fence tag stream is ready
        // (the stream holds a couple of entries) or a read request was
        // processed.
        .alloc(alloc_tlp_tag),
        .alloc_ready(req_tlp_tag_ready),
        .alloc_uid(req_tlp_tag),

        .free(free_tlp_tag),
        .free_uid(free_tlp_tag_value)
        );


    //
    // Track write addresses so a fence can use the most recent address.
    //
    logic [63:0] last_wr_addr;

    always_ff @(posedge clk)
    begin
        // Track last write address (used in next fence)
        if (wr_req_deq && wr_req.sop && !wr_req.is_fence)
        begin
            last_wr_addr <= wr_req.addr;
        end

        if (!reset_n)
        begin
            last_wr_addr <= '0;
        end
    end

    //
    // Register fence completion tags until forwarded to the AFU.
    //
    logic wr_fence_cpl_valid;
    t_wr_fence_tag wr_fence_cpl_tag;

    assign free_tlp_tag = wr_rsp_notFull && wr_fence_cpl_valid;
    assign free_tlp_tag_value = wr_fence_cpl_tag;

    assign wr_fence_cpl.tready = !wr_fence_cpl_valid;

    always_ff @(posedge clk)
    begin
        if (!wr_fence_cpl_valid)
        begin
            wr_fence_cpl_valid <= wr_fence_cpl.tvalid;
            wr_fence_cpl_tag <= wr_fence_cpl.t.data;
        end
        else
        begin
            // Fence completions get priority. As long as the outbound FIFO
            // has space the fence completion will be handled.
            wr_fence_cpl_valid <= !wr_rsp_notFull;
        end

        if (!reset_n)
        begin
            wr_fence_cpl_valid <= 1'b0;
        end
    end

    // Save the AFU tag associated with a write fence
    logic [AFU_TAG_WIDTH-1 : 0] wr_fence_afu_tag;

    ofs_plat_prim_lutram
      #(
        .N_ENTRIES(MAX_OUTSTANDING_DMA_WR_FENCES),
        .N_DATA_BITS(AFU_TAG_WIDTH)
        )
      fence_meta
       (
        .clk,
        .reset_n,

        .wen(alloc_tlp_tag),
        .waddr(req_tlp_tag),
        .wdata(wr_req.tag),

        .raddr(wr_fence_cpl_tag),
        .rdata(wr_fence_afu_tag)
        );


    // ====================================================================
    //
    //  Handle byte range requests (writing less than a full line).
    //  Shift counts, payload sizes and masks must be computed.
    //
    //  Logic here with the prefix "br_req" is valid only when
    //  wr_req.enable_byte_range is true. Logic with the prefix "wr_req"
    //  is always valid.
    //
    // ====================================================================

    //
    // Byte enable for the first DWORD. (PCIe address granularity is 32
    // bit words, with 4-bit enable masks on the first and last DWORDs.)
    //
    logic [3:0] br_req_hdr_first_be;
    logic [3:0] first_dword_mask;
    always_comb
    begin
        first_dword_mask = 4'hf;
        if (wr_req.byte_len < 4)
        begin
            // Only one DWORD in the payload. The mask may describe both
            // the start and the end positions.
            case (wr_req.byte_len[1:0])
              2'b01 : first_dword_mask = 4'h1;
              2'b10 : first_dword_mask = 4'h3;
              2'b11 : first_dword_mask = 4'h7;
              default : first_dword_mask = 4'h0;
            endcase
        end
        br_req_hdr_first_be = first_dword_mask << wr_req.byte_start_idx[1:0];
    end

    //
    // Byte enable for the last DWORD.
    //
    logic [3:0] br_req_hdr_last_be;

    always_comb
    begin
        br_req_hdr_last_be = 4'h0;

        // Check if first DW and last DW are the same DW in the CL. PCIe
        // requires that the last byte enable be 0 when the payload length
        // is 1 DWORD.
        if (dw_idx(wr_req.byte_start_idx) != dw_idx(br_req.byte_end_idx))
        begin
            case (br_req.byte_end_idx[1:0])
              2'b00 : br_req_hdr_last_be = 4'h1;
              2'b01 : br_req_hdr_last_be = 4'h3;
              2'b10 : br_req_hdr_last_be  = 4'h7;
              default : br_req_hdr_last_be = 4'hf;
            endcase
        end
    end

    logic wr_req_short_eop;
    assign wr_req_short_eop = wr_req.enable_byte_range && (br_req.dword_len <= 8);

    logic [63:0] wr_req_addr;
    always_comb
    begin
        wr_req_addr = wr_req.addr;
        wr_req_addr[$bits(t_tlp_payload_line_byte_idx)-1 : 2] = dw_idx(wr_req.byte_start_idx);
    end


    // ====================================================================
    //
    //  Map AFU write requests to TLPs
    //
    // ====================================================================

    assign wr_req_ready = wr_req_notEmpty && req_tlp_tag_ready && !wr_fence_cpl_valid;
    assign wr_req_deq = wr_req_ready && wr_rsp_notFull &&
                        (tx_wr_tlps.tready || !tx_wr_tlps.tvalid);
    assign tx_wr_tlps.t.user = '0;

    ofs_fim_pcie_hdr_def::t_tlp_mem_req_hdr tlp_mem_hdr;
    logic [AFU_TAG_WIDTH-1 : 0] wr_req_tag_q;
    t_tlp_payload_line_idx wr_req_last_line_idx_q;

    always_comb
    begin
        tlp_mem_hdr = '0;

        if (wr_req.is_fence)
        begin
            // Fence
`ifdef USE_PCIE_ADDR32
            tlp_mem_hdr.dw0.fmttype = ofs_fim_pcie_hdr_def::PCIE_FMTTYPE_MEM_READ32;
            tlp_mem_hdr.addr = last_wr_addr;
`else
            tlp_mem_hdr.dw0.fmttype = ofs_fim_pcie_hdr_def::PCIE_FMTTYPE_MEM_READ64;
            { tlp_mem_hdr.addr, tlp_mem_hdr.lsb_addr } = last_wr_addr;
`endif
            tlp_mem_hdr.dw0.length = 1;
            tlp_mem_hdr.tag = req_tlp_tag;
        end
        else
        begin
            // Normal write
`ifdef USE_PCIE_ADDR32
            tlp_mem_hdr.dw0.fmttype = ofs_fim_pcie_hdr_def::PCIE_FMTTYPE_MEM_WRITE32;
            tlp_mem_hdr.addr = = wr_req_addr;
`else
            tlp_mem_hdr.dw0.fmttype = ofs_fim_pcie_hdr_def::PCIE_FMTTYPE_MEM_WRITE64;
            { tlp_mem_hdr.addr, tlp_mem_hdr.lsb_addr } = wr_req_addr;
`endif
            tlp_mem_hdr.dw0.length =
                (wr_req.enable_byte_range ? br_req.dword_len :
                                            lineCountToDwordLen(wr_req.line_count));
            tlp_mem_hdr.last_be = (wr_req.enable_byte_range ? br_req_hdr_last_be : 4'b1111);
            tlp_mem_hdr.first_be = (wr_req.enable_byte_range ? br_req_hdr_first_be : 4'b1111);
        end
    end

    always_ff @(posedge clk)
    begin
        if (tx_wr_tlps.tready || !tx_wr_tlps.tvalid)
        begin
            if (wr_req_ready && wr_req.sop)
            begin
                wr_req_tag_q <= wr_req.tag;
                wr_req_last_line_idx_q <= t_tlp_payload_line_idx'(wr_req.line_count - 1);
            end
        end
    end

    // Shift the payload to the first DWORD used. The shift only happens when
    // a partial line is being written, using a byte range.
    logic [PAYLOAD_LINE_SIZE-1 : 0] wr_req_shifted_payload;
    ofs_plat_prim_rshift_words_comb
      #(
        .DATA_WIDTH(PAYLOAD_LINE_SIZE),
        .WORD_WIDTH(32)
        )
      pshift
       (
        .d_in(wr_req.payload),
        .rshift_cnt(dw_idx(wr_req.byte_start_idx)),
        .d_out(wr_req_shifted_payload)
        );

    always_ff @(posedge clk)
    begin
        if (tx_wr_tlps.tready || !tx_wr_tlps.tvalid)
        begin
            tx_wr_tlps.tvalid <= wr_req_ready && wr_rsp_notFull;

            tx_wr_tlps.t.data <= '0;

            tx_wr_tlps.t.data[0].valid <= wr_req_notEmpty;
            tx_wr_tlps.t.data[0].sop <= wr_req_notEmpty && wr_req.sop;
            // The request is one empty read if it's a fence or a short byte
            // range, otherwise write data spans multiple channels.
            tx_wr_tlps.t.data[0].eop <= wr_req_notEmpty && (wr_req.is_fence || wr_req_short_eop);

            tx_wr_tlps.t.data[1].valid <= wr_req_notEmpty && !wr_req.is_fence &&
                                          !wr_req_short_eop;
            tx_wr_tlps.t.data[1].eop <= wr_req_notEmpty && wr_req.eop && !wr_req.is_fence;

            tx_wr_tlps.t.data[0].hdr <= (wr_req.sop ? tlp_mem_hdr : '0);

            // It is always safe to use the shifted payload since byte_start_idx
            // is guaranteed by the canonicalization step above to be 0 when in
            // full-line mode. Using the value from the shifter avoids an extra MUX.
            { tx_wr_tlps.t.data[1].payload, tx_wr_tlps.t.data[0].payload } <=
                wr_req_shifted_payload;
        end

        if (!reset_n)
        begin
            tx_wr_tlps.tvalid <= 1'b0;
        end
    end


    // ====================================================================
    //
    //  Generate write response on final packet
    //
    // ====================================================================

    t_gen_tx_afu_wr_rsp wr_rsp;
    always_comb
    begin
        if (wr_fence_cpl_valid)
        begin
            wr_rsp.tag = wr_fence_afu_tag;
        end
        else
        begin
            wr_rsp.tag = (wr_req.sop ? wr_req.tag : wr_req_tag_q);
        end
        wr_rsp.line_idx = (wr_req.sop ? '0 : wr_req_last_line_idx_q);
        wr_rsp.is_fence = wr_fence_cpl_valid;
    end

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS($bits(t_gen_tx_afu_wr_rsp))
        )
      afu_rsp_fifo
       (
        .clk,
        .reset_n,

        .enq_data(wr_rsp),
        // Send a write response for the end of a normal write or when a
        // write fence completion arrives.
        .enq_en((wr_req_deq && wr_req.eop && !wr_req.is_fence) || free_tlp_tag),
        .notFull(wr_rsp_notFull),

        .first(afu_wr_rsp.t.data),
        .deq_en(afu_wr_rsp.tvalid && afu_wr_rsp.tready),
        .notEmpty(afu_wr_rsp.tvalid)
        );

endmodule // ofs_plat_host_chan_@group@_gen_wr_tlps
