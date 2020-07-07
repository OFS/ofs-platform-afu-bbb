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

module ofs_plat_host_chan_@GROUP@_gen_wr_tlps
   (
    input  logic clk,
    input  logic reset_n,

    // Write requests from AFU (t_gen_tx_afu_wr_req)
    ofs_plat_axi_stream_if.to_master afu_wr_req,

    // Output write request TLP stream
    ofs_plat_axi_stream_if.to_slave tx_wr_tlps,

    // Write responses to AFU once the packet is completely sent (t_gen_tx_afu_wr_rsp)
    ofs_plat_axi_stream_if.to_slave afu_wr_rsp,

    output logic error
    );

    import ofs_plat_host_chan_@GROUP@_pcie_tlp_pkg::*;
    import ofs_plat_host_chan_@GROUP@_gen_tlps_pkg::*;

    assign error = 1'b0;

    //
    // Store requests in a FIFO before arbitration.
    //
    t_gen_tx_afu_wr_req wr_req;
    logic wr_req_deq;
    logic wr_req_notEmpty;

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS($bits(t_gen_tx_afu_wr_req))
        )
      afu_req_fifo
       (
        .clk,
        .reset_n,

        .enq_data(afu_wr_req.t.data),
        .enq_en(afu_wr_req.tvalid && afu_wr_req.tready),
        .notFull(afu_wr_req.tready),

        .first(wr_req),
        .deq_en(wr_req_deq),
        .notEmpty(wr_req_notEmpty)
        );


    //
    // Map AFU write requests to TLPs
    //
    logic wr_rsp_notFull;
    assign wr_req_deq = wr_req_notEmpty && wr_rsp_notFull &&
                        (tx_wr_tlps.tready || !tx_wr_tlps.tvalid);
    assign tx_wr_tlps.t.user = '0;

    ofs_fim_pcie_hdr_def::t_tlp_mem_req_hdr tlp_mem_hdr, tlp_mem_hdr_q;
    logic [AFU_TAG_WIDTH-1 : 0] wr_req_tag_q;

    always_comb
    begin
        tlp_mem_hdr = '0;
`ifdef USE_PCIE_ADDR32
        tlp_mem_hdr.dw0.fmttype = ofs_fim_pcie_hdr_def::PCIE_FMTTYPE_MEM_WRITE32;
        tlp_mem_hdr.addr = wr_req.addr;
`else
        tlp_mem_hdr.dw0.fmttype = ofs_fim_pcie_hdr_def::PCIE_FMTTYPE_MEM_WRITE64;
        { tlp_mem_hdr.addr, tlp_mem_hdr.lsb_addr } = wr_req.addr;
`endif
        tlp_mem_hdr.dw0.length = lineCountToDwordLen(wr_req.line_count);
        tlp_mem_hdr.last_be = 4'b1111;
        tlp_mem_hdr.first_be = 4'b1111;
    end

    always_ff @(posedge clk)
    begin
        if (tx_wr_tlps.tready || !tx_wr_tlps.tvalid)
        begin
            if (wr_req_notEmpty && wr_req.sop)
            begin
                tlp_mem_hdr_q <= tlp_mem_hdr;
                wr_req_tag_q <= wr_req.tag;
            end
        end
    end

    always_ff @(posedge clk)
    begin
        if (tx_wr_tlps.tready || !tx_wr_tlps.tvalid)
        begin
            tx_wr_tlps.tvalid <= wr_req_notEmpty && wr_rsp_notFull && !wr_req.is_fence;

            tx_wr_tlps.t.data <= '0;

            tx_wr_tlps.t.data[0].valid <= wr_req_notEmpty;
            tx_wr_tlps.t.data[0].sop <= wr_req_notEmpty && wr_req.sop;
            tx_wr_tlps.t.data[1].valid <= wr_req_notEmpty;
            tx_wr_tlps.t.data[1].eop <= wr_req_notEmpty && wr_req.eop;

            tx_wr_tlps.t.data[0].hdr <= (wr_req.sop ? tlp_mem_hdr : tlp_mem_hdr_q);
            tx_wr_tlps.t.data[1].hdr <= (wr_req.sop ? tlp_mem_hdr : tlp_mem_hdr_q);

            { tx_wr_tlps.t.data[1].payload, tx_wr_tlps.t.data[0].payload } <= wr_req.payload;
        end

        if (!reset_n)
        begin
            tx_wr_tlps.tvalid <= 1'b0;
        end
    end


    //
    // Generate write response on final packet
    //
    t_gen_tx_afu_wr_rsp wr_rsp;
    assign wr_rsp.tag = (wr_req.sop ? wr_req.tag : wr_req_tag_q);
    assign wr_rsp.line_idx = '0;
    assign wr_rsp.is_fence = wr_req.is_fence && wr_req.sop;

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS($bits(t_gen_tx_afu_wr_rsp))
        )
      afu_rsp_fifo
       (
        .clk,
        .reset_n,

        .enq_data(wr_rsp),
        .enq_en(wr_req_deq && wr_req.eop),
        .notFull(wr_rsp_notFull),

        .first(afu_wr_rsp.t.data),
        .deq_en(afu_wr_rsp.tvalid && afu_wr_rsp.tready),
        .notEmpty(afu_wr_rsp.tvalid)
        );

endmodule // ofs_plat_host_chan_@GROUP@_gen_wr_tlps
