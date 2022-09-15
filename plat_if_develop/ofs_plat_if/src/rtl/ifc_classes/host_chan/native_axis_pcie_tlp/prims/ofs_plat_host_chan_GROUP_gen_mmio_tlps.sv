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
// Generate TLP requests for MMIO read responses. The incoming TX stream
// is protocol-independent and can be used by any AFU memory sink.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_@group@_gen_mmio_tlps
   (
    input  logic clk,
    input  logic reset_n,

    // Input RX TLP stream from host
    ofs_plat_axi_stream_if.to_source from_fiu_rx_st,

    // MMIO requests from host to AFU (t_gen_tx_mmio_afu_req)
    ofs_plat_axi_stream_if.to_sink host_mmio_req,

    // AFU responses (t_gen_tx_mmio_afu_rsp)
    ofs_plat_axi_stream_if.to_source host_mmio_rsp,

    // Output response stream (TX TLP vector with NUM_PCIE_TLP_CH channels)
    ofs_plat_axi_stream_if.to_sink tx_mmio,

    output logic error
    );

    import ofs_plat_host_chan_@group@_pcie_tlp_pkg::*;
    import ofs_plat_host_chan_@group@_gen_tlps_pkg::*;
    import ofs_plat_pcie_tlp_hdr_pkg::*;

    assign error = 1'b0;

    //
    // Translation incoming TLP requests to requests for the AFU on host_mmio_req
    //
    ofs_plat_pcie_tlp_hdr_pkg::t_ofs_plat_pcie_hdr rx_mem_req_hdr, rx_mem_req_hdr_q;
    assign rx_mem_req_hdr = from_fiu_rx_st.t.user[0].hdr;

    assign from_fiu_rx_st.tready = host_mmio_req.tready;
    assign host_mmio_req.tvalid =
        from_fiu_rx_st.tvalid &&
        !from_fiu_rx_st.t.user[0].poison &&
        from_fiu_rx_st.t.user[0].sop &&
        ofs_plat_pcie_func_is_mem_req(rx_mem_req_hdr.fmttype);

    // Incoming MMIO read request from host?
    logic rx_st_is_mmio_rd_req, rx_st_is_mmio_rd_req_q;
    assign rx_st_is_mmio_rd_req =
        from_fiu_rx_st.tvalid &&
        !from_fiu_rx_st.t.user[0].poison &&
        from_fiu_rx_st.t.user[0].sop &&
        ofs_plat_pcie_func_is_mrd_req(rx_mem_req_hdr.fmttype);

    always_comb
    begin
        host_mmio_req.t.data.tag = t_mmio_rd_tag'(rx_mem_req_hdr.u.mem_req.tag);
        host_mmio_req.t.data.addr = rx_mem_req_hdr.u.mem_req.addr;
        host_mmio_req.t.data.byte_count = { rx_mem_req_hdr.length, 2'b0 };
        host_mmio_req.t.data.is_write = ofs_plat_pcie_func_is_mwr_req(rx_mem_req_hdr.fmttype);

        host_mmio_req.t.data.payload = from_fiu_rx_st.t.data;
    end

    always_ff @(posedge clk)
    begin
        rx_mem_req_hdr_q <= rx_mem_req_hdr;
        rx_st_is_mmio_rd_req_q <= rx_st_is_mmio_rd_req;
    end

    // Internal tracking of read requests from the host that arrive as a
    // TLP stream. This is extra metadata that isn't forwarded to the AFU,
    // indexed by the original tag, that will be needed in order to generate
    // the TLP completion.
    //

    logic rx_mmio_valid;
    t_gen_tx_mmio_host_req rx_mmio;

    assign rx_mmio_valid = rx_st_is_mmio_rd_req_q;
    assign rx_mmio.tag = rx_mem_req_hdr_q.u.mem_req.tag;
    assign rx_mmio.lower_addr = rx_mem_req_hdr_q.u.mem_req.addr[6:0];
    assign rx_mmio.byte_count = { rx_mem_req_hdr_q.length, 2'b0 };
    assign rx_mmio.requester_id = rx_mem_req_hdr_q.u.mem_req.requester_id;
    assign rx_mmio.tc = rx_mem_req_hdr_q.u.mem_req.tc;

    logic rx_mmio_valid_q;
    t_gen_tx_mmio_host_req rx_mmio_q;

    always_ff @(posedge clk)
    begin
        rx_mmio_valid_q <= rx_mmio_valid;
        rx_mmio_q <= rx_mmio;
    end

    // Meta-data for an AFU response (original request details)
    t_gen_tx_mmio_host_req host_mmio_rsp_meta;

    ofs_plat_prim_ram_simple
      #(
        .N_ENTRIES(MAX_OUTSTANDING_MMIO_RD_REQS),
        .N_DATA_BITS($bits(t_gen_tx_mmio_host_req)),
        .N_OUTPUT_REG_STAGES(1)
        )
      active_reads
       (
        .clk,

        .raddr(host_mmio_rsp.t.data.tag),
        .rdata(host_mmio_rsp_meta),

        .waddr(rx_mmio_q.tag),
        .wen(rx_mmio_valid_q),
        .wdata(rx_mmio_q)
        );

    // Response metadata is available from the RAM 2 cycles after the read.
    logic rsp_meta_rd_q, rsp_meta_rd_qq;
    always_ff @(posedge clk)
    begin
        rsp_meta_rd_q <= host_mmio_rsp.tvalid && host_mmio_rsp.tready;
        rsp_meta_rd_qq <= rsp_meta_rd_q;
    end

    //
    // Read responses from AFU. Combine the data from the AFU with the size
    // recorded with the original read request.
    //
    t_gen_tx_mmio_afu_rsp mmio_rsp;
    t_gen_tx_mmio_host_req mmio_rsp_meta;
    logic mmio_rsp_deq;
    logic mmio_rsp_notEmpty;

    //
    // The response and its associated metadata are available at different times
    // due to the latency of the active_reads RAM above. Maintain two FIFOs.
    // Once afu_rsp_fifo_meta is not empty it is guaranteed that afu_rsp_fifo
    // is also not empty. Also, afu_rsp_fifo will always fill before the metadata
    // FIFO.
    //
    // The pair of FIFOs here can't produce a result every cycle, but that's
    // unimportant given the bandwidth of MMIO traffic.
    //
    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS($bits(t_gen_tx_mmio_afu_rsp))
        )
      afu_rsp_fifo
       (
        .clk,
        .reset_n,

        .enq_data(host_mmio_rsp.t.data),
        .enq_en(host_mmio_rsp.tvalid && host_mmio_rsp.tready),
        .notFull(host_mmio_rsp.tready),

        .first(mmio_rsp),
        .deq_en(mmio_rsp_deq),
        .notEmpty()
        );

    ofs_plat_prim_fifo2
      #(
        .N_DATA_BITS($bits(t_gen_tx_mmio_host_req))
        )
      afu_rsp_fifo_meta
       (
        .clk,
        .reset_n,

        .enq_data(host_mmio_rsp_meta),
        .enq_en(rsp_meta_rd_qq),
        .notFull(),

        .first(mmio_rsp_meta),
        .deq_en(mmio_rsp_deq),
        .notEmpty(mmio_rsp_notEmpty)
        );


    //
    // Map AFU responses to TLPs
    //
    assign mmio_rsp_deq = mmio_rsp_notEmpty &&
                          (tx_mmio.tready || !tx_mmio.tvalid);

    t_ofs_plat_pcie_hdr mmio_cpl_hdr;
    always_comb
    begin
        mmio_cpl_hdr = '0;
        mmio_cpl_hdr.fmttype = OFS_PLAT_PCIE_FMTTYPE_CPLD;
        mmio_cpl_hdr.length = mmio_rsp_meta.byte_count >> 2;
        mmio_cpl_hdr.u.cpl.byte_count = mmio_rsp_meta.byte_count;
        mmio_cpl_hdr.u.cpl.requester_id = mmio_rsp_meta.requester_id;
        mmio_cpl_hdr.u.cpl.tc = mmio_rsp_meta.tc;
        mmio_cpl_hdr.u.cpl.lower_addr = mmio_rsp_meta.lower_addr;
        mmio_cpl_hdr.u.cpl.tag = mmio_rsp.tag;
    end

    always_ff @(posedge clk)
    begin
        if (tx_mmio.tready || !tx_mmio.tvalid)
        begin
            tx_mmio.tvalid <= mmio_rsp_notEmpty;

            tx_mmio.t.data <= { '0, mmio_rsp.payload };
            tx_mmio.t.keep <= { '0,
                                (mmio_rsp_meta.byte_count[3] ? 4'b1111 : 4'b0000),
                                4'b1111 };
            tx_mmio.t.last <= 1'b1;

            tx_mmio.t.user <= '0;
            tx_mmio.t.user[0].hdr <= mmio_cpl_hdr;
            tx_mmio.t.user[0].sop <= mmio_rsp_notEmpty;
            tx_mmio.t.user[0].eop <= mmio_rsp_notEmpty;
        end

        if (!reset_n)
        begin
            tx_mmio.tvalid <= 1'b0;
        end
    end


    // synthesis translate_off

    logic [MAX_OUTSTANDING_MMIO_RD_REQS-1:0] tag_is_active;

    always_ff @(posedge clk)
    begin
        if (rx_mmio_valid)
        begin
            tag_is_active[rx_mmio.tag] <= 1'b1;
            assert (tag_is_active[rx_mmio.tag] == 1'b0) else
                $fatal(2, "** ERROR ** %m: Duplicate MMIO read tag 0x%x", rx_mmio.tag);
        end

        if (host_mmio_rsp.tvalid && host_mmio_rsp.tready)
        begin
            tag_is_active[host_mmio_rsp.t.data.tag] <= 1'b0;
            assert (tag_is_active[host_mmio_rsp.t.data.tag] == 1'b1) else
                $fatal(2, "** ERROR ** %m: Response for inactive MMIO read tag 0x%x", host_mmio_rsp.t.data.tag);
        end

        if (!reset_n)
        begin
            tag_is_active <= '0;
        end
    end

    // synthesis translate_on

endmodule // ofs_plat_host_chan_@group@_gen_mmio_tlps
