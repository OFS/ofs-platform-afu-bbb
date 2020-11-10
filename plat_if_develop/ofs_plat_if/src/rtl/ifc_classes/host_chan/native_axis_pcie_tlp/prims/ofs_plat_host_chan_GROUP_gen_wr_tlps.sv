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
    ofs_plat_axi_stream_if.to_source afu_wr_req,

    // Output write request TLP stream
    ofs_plat_axi_stream_if.to_sink tx_wr_tlps,

    // Write responses to AFU once the packet is completely sent (t_gen_tx_afu_wr_rsp)
    ofs_plat_axi_stream_if.to_sink afu_wr_rsp,

    // Fence completions, processed first by the read response pipeline.
    // (t_dma_rd_tag)
    ofs_plat_axi_stream_if.to_source wr_fence_cpl,

    // Interrupt completions from the FIU (t_ofs_plat_axis_pcie_irq_data)
    ofs_plat_axi_stream_if.to_source irq_cpl,

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

    // Pre-compute OR of high address bits, needed for choosing either
    // MWr32 or MWr64. PCIe doesn't allow MWr64 when the address fits
    // in 32 bits.
    logic wr_req_is_addr64;
    logic afu_wr_req_is_addr64;
    assign afu_wr_req_is_addr64 = |(afu_wr_req.t.data.addr[63:32]);

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
        .N_DATA_BITS(1 + $bits(t_byte_range_req) + $bits(t_gen_tx_afu_wr_req))
        )
      afu_req_fifo
       (
        .clk,
        .reset_n,

        .enq_data({ afu_wr_req_is_addr64, br_req_in, afu_wr_req_c }),
        .enq_en(afu_wr_req.tvalid && afu_wr_req.tready),
        .notFull(afu_wr_req.tready),

        .first({ wr_req_is_addr64, br_req, wr_req }),
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

    logic free_wr_fence_tlp_tag;
    t_wr_fence_tag wr_fence_cpl_tag;

    //
    // Track write addresses so a fence can use the most recent address.
    //
    logic last_wr_addr_valid;
    logic last_wr_is_addr64;
    logic [63:0] last_wr_addr;

    always_ff @(posedge clk)
    begin
        // Track last write address (used in next fence)
        if (wr_req_deq && wr_req.sop && !wr_req.is_fence && !wr_req.is_interrupt)
        begin
            last_wr_addr <= wr_req.addr;
            last_wr_is_addr64 <= wr_req_is_addr64;
            last_wr_addr_valid <= 1'b1;
        end

        if (!reset_n)
        begin
            last_wr_addr_valid <= 1'b0;
        end
    end

    logic alloc_tlp_tag;
    assign alloc_tlp_tag = wr_req_deq && wr_req.sop &&
                           wr_req.is_fence && last_wr_addr_valid;

    // AFU asked for a fence but there hasn't been a write. No address to
    // use and no point in a fence!
    logic wr_req_is_invalid_fence;
    assign wr_req_is_invalid_fence = wr_req.is_fence && !last_wr_addr_valid;

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

        .free(free_wr_fence_tlp_tag),
        .free_uid(wr_fence_cpl_tag)
        );


    //
    // Register fence completion tags until forwarded to the AFU.
    //
    logic wr_fence_cpl_valid;
    assign free_wr_fence_tlp_tag = wr_rsp_notFull && wr_fence_cpl_valid;
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

    logic std_wr_rsp_notFull;

    assign wr_req_ready = wr_req_notEmpty && req_tlp_tag_ready;
    assign wr_req_deq = wr_req_ready && std_wr_rsp_notFull &&
                        (tx_wr_tlps.tready || !tx_wr_tlps.tvalid);

    ofs_fim_pcie_hdr_def::t_tlp_mem_req_hdr tlp_mem_hdr;
    logic [AFU_TAG_WIDTH-1 : 0] wr_req_tag_q;
    t_tlp_payload_line_idx wr_req_last_line_idx_q;
    t_ofs_plat_axis_pcie_irq_data irq_hdr;

    always_comb
    begin
        tlp_mem_hdr = '0;

        if (wr_req.is_fence)
        begin
            // Fence
            if (last_wr_is_addr64)
            begin
                tlp_mem_hdr.dw0.fmttype = ofs_fim_pcie_hdr_def::PCIE_FMTTYPE_MEM_READ64;
                { tlp_mem_hdr.addr, tlp_mem_hdr.lsb_addr } = last_wr_addr;
            end
            else
            begin
                tlp_mem_hdr.dw0.fmttype = ofs_fim_pcie_hdr_def::PCIE_FMTTYPE_MEM_READ32;
                tlp_mem_hdr.addr = last_wr_addr;
            end

            tlp_mem_hdr.dw0.length = 1;
            tlp_mem_hdr.tag = req_tlp_tag;
        end
        else if (wr_req.is_interrupt)
        begin
            // Interrupt ID is passed in from the AFU using the tag
            irq_hdr = '0;
            irq_hdr.irq_id = wr_req.tag[$bits(irq_hdr.irq_id)-1 : 0];
            // Pass irq_hdr instead of normal TLP header. The afu_irq user bit will
            // be set to indicate the interrupt header.
            tlp_mem_hdr = { '0, irq_hdr };
        end
        else
        begin
            // Normal write
            if (wr_req_is_addr64)
            begin
                tlp_mem_hdr.dw0.fmttype = ofs_fim_pcie_hdr_def::PCIE_FMTTYPE_MEM_WRITE64;
                { tlp_mem_hdr.addr, tlp_mem_hdr.lsb_addr } = wr_req_addr;
            end
            else
            begin
                tlp_mem_hdr.dw0.fmttype = ofs_fim_pcie_hdr_def::PCIE_FMTTYPE_MEM_WRITE32;
                tlp_mem_hdr.addr = wr_req_addr;
            end

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

    logic [1:0] tx_wr_is_eop;
    assign tx_wr_is_eop[0] = wr_req_notEmpty &&
                             (wr_req.is_fence || wr_req.is_interrupt || wr_req_short_eop);
    assign tx_wr_is_eop[1] = wr_req_notEmpty &&
                             wr_req.eop && !wr_req.is_fence && !wr_req.is_interrupt;

    always_ff @(posedge clk)
    begin
        if (tx_wr_tlps.tready || !tx_wr_tlps.tvalid)
        begin
            tx_wr_tlps.tvalid <= wr_req_ready && std_wr_rsp_notFull;

            tx_wr_tlps.t.data <= '0;
            tx_wr_tlps.t.last <= |(tx_wr_is_eop);

            tx_wr_tlps.t.data[0].valid <= wr_req_notEmpty && !wr_req_is_invalid_fence;
            tx_wr_tlps.t.data[0].sop <= wr_req_notEmpty && wr_req.sop;
            // The request is one empty read if it's a fence or a short byte
            // range, otherwise write data spans multiple channels.
            tx_wr_tlps.t.data[0].eop <= tx_wr_is_eop[0];

            tx_wr_tlps.t.data[1].valid <=
                wr_req_notEmpty && !wr_req.is_fence && !wr_req.is_interrupt &&
                !wr_req_short_eop;
            tx_wr_tlps.t.data[1].eop <= tx_wr_is_eop[1];

            tx_wr_tlps.t.data[0].hdr <= (wr_req.sop ? tlp_mem_hdr : '0);

            // It is always safe to use the shifted payload since byte_start_idx
            // is guaranteed by the canonicalization step above to be 0 when in
            // full-line mode. Using the value from the shifter avoids an extra MUX.
            { tx_wr_tlps.t.data[1].payload, tx_wr_tlps.t.data[0].payload } <=
                wr_req_shifted_payload;

            // Request meta-data
            tx_wr_tlps.t.user <= '0;
            tx_wr_tlps.t.user[0].afu_irq <= wr_req.is_interrupt;
        end

        if (!reset_n)
        begin
            tx_wr_tlps.tvalid <= 1'b0;
        end
    end

    // Write response queue. The output will be merged with fence and interrupt
    // responses before being routed back to the AFU.
    logic std_wr_rsp_valid;
    logic std_wr_rsp_deq;
    t_tlp_payload_line_idx std_wr_rsp_line_idx;
    logic [AFU_TAG_WIDTH-1 : 0] std_wr_rsp_tag;
    logic std_wr_rsp_is_fence;

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS($bits(t_tlp_payload_line_idx) + AFU_TAG_WIDTH + 1)
        )
      std_wr_rsp_fifo
       (
        .clk,
        .reset_n,

        .enq_data(wr_req.sop ? { '0, wr_req.tag, wr_req.is_fence } :
                               { wr_req_last_line_idx_q, wr_req_tag_q, 1'b0 }),
        // Send a write response for the end of a normal write or a
        // fence with no available address.
        .enq_en(wr_req_deq && wr_req.eop && !wr_req.is_interrupt &&
                !(wr_req.is_fence && last_wr_addr_valid)),
        .notFull(std_wr_rsp_notFull),

        .first({ std_wr_rsp_line_idx, std_wr_rsp_tag, std_wr_rsp_is_fence }),
        .deq_en(std_wr_rsp_deq),
        .notEmpty(std_wr_rsp_valid)
        );


    // ====================================================================
    //
    //  Register incoming interrupt completion. Don't bother pipelining
    //  interrupt completions. They are very infrequent.
    //
    // ====================================================================

    logic irq_cpl_reg_valid;
    assign irq_cpl.tready = !irq_cpl_reg_valid;

    t_ofs_plat_axis_pcie_irq_data irq_cpl_reg;

    always_ff @(posedge clk)
    begin
        if (!irq_cpl_reg_valid)
        begin
            // IRQ completion register not occupied. Take any new completion.
            irq_cpl_reg_valid <= irq_cpl.tvalid;
            irq_cpl_reg <= irq_cpl.t.data;
        end
        else if (wr_rsp_notFull && !wr_fence_cpl_valid)
        begin
            // Can forward a registered completion this cycle. (Fences get
            // priority.)
            irq_cpl_reg_valid <= 1'b0;
        end

        if (!reset_n)
        begin
            irq_cpl_reg_valid <= 1'b0;
        end
    end


    // ====================================================================
    //
    //  Generate write response for:
    //   - Final packet of a normal write
    //   - Write fence completion
    //   - Interrupt completion
    //
    // ====================================================================

    t_gen_tx_afu_wr_rsp wr_rsp;
    always_comb
    begin
        if (wr_fence_cpl_valid)
        begin
            wr_rsp.is_fence = 1'b1;
            wr_rsp.is_interrupt = 1'b0;
            wr_rsp.tag = wr_fence_afu_tag;
            wr_rsp.line_idx = 0;
            std_wr_rsp_deq = 1'b0;
        end
        else if (irq_cpl_reg_valid)
        begin
            wr_rsp.is_fence = 1'b0;
            wr_rsp.is_interrupt = 1'b1;
            wr_rsp.tag = { '0, irq_cpl_reg.irq_id };
            wr_rsp.line_idx = 0;
            std_wr_rsp_deq = 1'b0;
        end
        else
        begin
            wr_rsp.is_fence = std_wr_rsp_is_fence;
            wr_rsp.is_interrupt = 1'b0;
            wr_rsp.tag = std_wr_rsp_tag;
            wr_rsp.line_idx = std_wr_rsp_line_idx;
            std_wr_rsp_deq = std_wr_rsp_valid && wr_rsp_notFull;
        end
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
        // Send a write response for the end of a normal write, when a
        // write fence completion arrives, or when an interrupt completes.
        .enq_en(wr_rsp_notFull && (std_wr_rsp_valid || wr_fence_cpl_valid || irq_cpl_reg_valid)),
        .notFull(wr_rsp_notFull),

        .first(afu_wr_rsp.t.data),
        .deq_en(afu_wr_rsp.tvalid && afu_wr_rsp.tready),
        .notEmpty(afu_wr_rsp.tvalid)
        );

endmodule // ofs_plat_host_chan_@group@_gen_wr_tlps
