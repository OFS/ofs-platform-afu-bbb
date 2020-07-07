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
// Base mapping of an AXI stream of PCIe TLPs to memory mapped interfaces.
// No particular memory mapped interface is required. The ports here
// pass basic fields needed for any memory interface. It is up to the
// parent module to map to a particular protocol.
//

`include "ofs_plat_if.vh"


// Lots of streams are used to pass messages through the TLP processing
// modules instantiated here. They use a common idiom. Define a macro
// that instantiates a stream "instance_name" of "data_type" and assigns
// standard clock, reset and debug info.
`define AXI_STREAM_INSTANCE(instance_name, data_type) \
    ofs_plat_axi_stream_if \
      #( \
        .TDATA_TYPE(data_type), \
        .TUSER_TYPE(logic) /* Unused */ \
        ) \
      instance_name(); \
    assign instance_name.clk = clk; \
    assign instance_name.reset_n = reset_n; \
    assign instance_name.instance_number = to_fiu_tlp.instance_number

// Standard AFU line-width TX TLP stream instance
`define AXI_TX_TLP_STREAM_INSTANCE(instance_name) \
    ofs_plat_axi_stream_if \
      #( \
        .TDATA_TYPE(t_gen_tx_tlp_vec), \
        .TUSER_TYPE(t_gen_tx_tlp_user_vec) \
        ) \
      instance_name(); \
    assign instance_name.clk = clk; \
    assign instance_name.reset_n = reset_n; \
    assign instance_name.instance_number = to_fiu_tlp.instance_number


module ofs_plat_host_chan_@GROUP@_map_to_tlps
   (
    ofs_plat_host_chan_@GROUP@_axis_pcie_tlp_if to_fiu_tlp,

    // MMIO requests from host to AFU (t_gen_tx_mmio_afu_req)
    ofs_plat_axi_stream_if.to_slave host_mmio_req,
    // AFU MMIO responses to host (t_gen_tx_mmio_afu_rsp)
    ofs_plat_axi_stream_if.to_master host_mmio_rsp,

    // Read requests from AFU (t_gen_tx_afu_rd_req)
    ofs_plat_axi_stream_if.to_master afu_rd_req,
    // Read responses to AFU (t_gen_tx_afu_rd_rsp)
    ofs_plat_axi_stream_if.to_slave afu_rd_rsp,

    // Write requests from AFU (t_gen_tx_afu_wr_req)
    ofs_plat_axi_stream_if.to_master afu_wr_req,
    // Write responses to AFU once the packet is completely sent (t_gen_tx_afu_wr_rsp)
    ofs_plat_axi_stream_if.to_slave afu_wr_rsp
    );

    import ofs_plat_host_chan_@GROUP@_pcie_tlp_pkg::*;
    import ofs_plat_host_chan_@GROUP@_gen_tlps_pkg::*;

    logic clk;
    assign clk = to_fiu_tlp.clk;
    logic reset_n;
    assign reset_n = to_fiu_tlp.reset_n;

    assign to_fiu_tlp.afu_irq_rx_st.tready = 1'b1;


    // ====================================================================
    //
    //  Align the incoming RX stream in canonical form, making it far
    //  easier to map to wider lines.
    //
    //  Alignment guarantees the following properties of a beat's
    //  vector of TLPs:
    //    1. At most one SOP is set. That SOP will always be in slot 0.
    //    2. Entries beyond an EOP are empty. (A consequence of #1.)
    //    3. All entries up to an EOP or the end of the vector are valid.
    //
    // ====================================================================

    typedef t_ofs_plat_axis_pcie_tdata [1:0] t_axis_pcie_tdata_vec;
    typedef t_ofs_plat_axis_pcie_rx_tuser [1:0] t_axis_pcie_rx_tuser_vec;

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_axis_pcie_tdata_vec),
        .TUSER_TYPE(t_axis_pcie_rx_tuser_vec)
        )
      aligned_rx_st();

    assign aligned_rx_st.clk = clk;
    assign aligned_rx_st.reset_n = reset_n;
    assign aligned_rx_st.instance_number = to_fiu_tlp.instance_number;

    // synthesis translate_off
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_RX(ofs_plat_log_pkg::HOST_CHAN, aligned_rx_st)
    // synthesis translate_on

    ofs_plat_host_chan_align_axis_tlps
      #(
        .NUM_MASTER_TLP_CH(NUM_FIU_PCIE_TLP_CH),
        .NUM_SLAVE_TLP_CH(2),
        .TDATA_TYPE(t_ofs_plat_axis_pcie_tdata),
        .TUSER_TYPE(t_ofs_plat_axis_pcie_rx_tuser)
        )
      align_rx
       (
        .stream_master(to_fiu_tlp.afu_rx_st),
        .stream_slave(aligned_rx_st)
        );

    logic rx_cpl_handler_ready;
    assign aligned_rx_st.tready = rx_cpl_handler_ready && host_mmio_req.tready;


    // ====================================================================
    //
    //  Manage MMIO requests and responses.
    //
    // ====================================================================

    // PCIe message type
    ofs_fim_pcie_hdr_def::t_tlp_mem_req_hdr rx_mem_req_hdr, rx_mem_req_hdr_q;
    assign rx_mem_req_hdr = aligned_rx_st.t.data[0].hdr;

    assign host_mmio_req.tvalid =
        aligned_rx_st.tvalid && aligned_rx_st.tready &&
        aligned_rx_st.t.data[0].sop &&
        ofs_fim_pcie_hdr_def::func_is_mem_req(rx_mem_req_hdr.dw0.fmttype);

    // Incoming MMIO read request from host?
    logic rx_st_is_mmio_rd_req, rx_st_is_mmio_rd_req_q;
    assign rx_st_is_mmio_rd_req =
        aligned_rx_st.tvalid && aligned_rx_st.tready &&
        aligned_rx_st.t.data[0].sop &&
        ofs_fim_pcie_hdr_def::func_is_mrd_req(rx_mem_req_hdr.dw0.fmttype);

    always_comb
    begin
        host_mmio_req.t.data.tag = t_mmio_rd_tag'(rx_mem_req_hdr.tag);

        if (ofs_fim_pcie_hdr_def::func_is_addr32(rx_mem_req_hdr.dw0.fmttype))
        begin
            host_mmio_req.t.data.addr = { '0, rx_mem_req_hdr.addr };
        end
        else
        begin
            host_mmio_req.t.data.addr = { rx_mem_req_hdr.addr, rx_mem_req_hdr.lsb_addr };
        end

        host_mmio_req.t.data.byte_count = { 10'(rx_mem_req_hdr.dw0.length), 2'b0 };
        host_mmio_req.t.data.is_write = ofs_fim_pcie_hdr_def::func_is_mwr_req(rx_mem_req_hdr.dw0.fmttype);

        host_mmio_req.t.data.payload = { aligned_rx_st.t.data[1].payload,
                                         aligned_rx_st.t.data[0].payload };
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
    // rx_mmio_from_host.tready is always true.
    `AXI_STREAM_INSTANCE(rx_mmio_from_host, t_gen_tx_mmio_host_req);

    assign rx_mmio_from_host.tvalid = rx_st_is_mmio_rd_req_q;
    assign rx_mmio_from_host.t.data.tag = rx_mem_req_hdr_q.tag;
    assign rx_mmio_from_host.t.data.lower_addr =
               ofs_fim_pcie_hdr_def::func_is_addr32(rx_mem_req_hdr_q.dw0.fmttype) ?
                                         rx_mem_req_hdr_q.addr[6:0] :
                                         rx_mem_req_hdr_q.lsb_addr[6:0];
    assign rx_mmio_from_host.t.data.byte_count = rx_mem_req_hdr_q.dw0.length << 2;
    assign rx_mmio_from_host.t.data.requester_id = rx_mem_req_hdr_q.requester_id;

    // Output response stream (TX TLP vector with NUM_PCIE_TLP_CH channels)
    `AXI_TX_TLP_STREAM_INSTANCE(tx_mmio_tlps);

    ofs_plat_host_chan_@GROUP@_gen_mmio_tlps mmio_rsp_to_tlps
       (
        .clk,
        .reset_n,

        .rx_mmio(rx_mmio_from_host),
        .host_mmio_rsp,
        .tx_mmio(tx_mmio_tlps),

        .error()
        );

    // synthesis translate_off
    always_ff @(negedge clk)
    begin
        if (reset_n)
        begin
            assert(rx_mmio_from_host.tready) else
                $fatal(2, " ** ERROR ** %m: rx_mmio_from_host.tready expected always ready!");
        end
    end
    // synthesis translate_on


    // ====================================================================
    //
    //  Manage AFU read requests and host completion responses
    //
    // ====================================================================

    // Output read request stream to host (TX TLP vector with NUM_PCIE_TLP_CH channels)
    `AXI_TX_TLP_STREAM_INSTANCE(tx_rd_tlps);

    // Input read completion stream from host (TX TLP vector with NUM_PCIE_TLP_CH channels)
    `AXI_TX_TLP_STREAM_INSTANCE(rx_cpl_tlps);
    assign rx_cpl_tlps.tvalid = aligned_rx_st.tvalid && aligned_rx_st.tready;
    assign rx_cpl_handler_ready = rx_cpl_tlps.tready;
    assign rx_cpl_tlps.t.data = aligned_rx_st.t.data;
    assign rx_cpl_tlps.t.user = aligned_rx_st.t.user;

    // Tag streams from read to write pipeline for fences
    `AXI_STREAM_INSTANCE(wr_fence_req_tag, t_dma_rd_tag);
    `AXI_STREAM_INSTANCE(wr_fence_cpl_tag, t_dma_rd_tag);
    assign wr_fence_req_tag.tready = 1'b0;
    assign wr_fence_cpl_tag.tready = 1'b1;

    ofs_plat_host_chan_@GROUP@_gen_rd_tlps rd_req_to_tlps
       (
        .clk,
        .reset_n,

        // Read requests from AFU
        .afu_rd_req,

        // Output TLP request stream to host
        .tx_rd_tlps,

        // Input TLP response stream from host.
        .rx_cpl_tlps,

        // Read responses to AFU
        .afu_rd_rsp,

        // Tags for write fence requests (to write pipeline)
        .wr_fence_req_tag,
        // Tags of write fence responses (dataless completion TLP)
        .wr_fence_cpl_tag,

        .error()
        );


    // ====================================================================
    //
    //  Manage AFU write requests
    //
    // ====================================================================

    // Output write request stream to host (TX TLP vector with NUM_PCIE_TLP_CH channels)
    `AXI_TX_TLP_STREAM_INSTANCE(tx_wr_tlps);

    ofs_plat_host_chan_@GROUP@_gen_wr_tlps wr_req_to_tlps
       (
        .clk,
        .reset_n,

        // Write requests from host
        .afu_wr_req,

        // Output write request TLP stream
        .tx_wr_tlps,

        // Write responses to AFU (once the packet is completely sent)
        .afu_wr_rsp,

        .error()
        );


    // ====================================================================
    //
    //  TLP Tx arbitration
    //
    // ====================================================================

    always_comb
    begin
        to_fiu_tlp.afu_tx_st.tvalid = tx_mmio_tlps.tvalid || tx_rd_tlps.tvalid || tx_wr_tlps.tvalid;

        tx_mmio_tlps.tready = to_fiu_tlp.afu_tx_st.tready;
        tx_rd_tlps.tready = to_fiu_tlp.afu_tx_st.tready && !tx_mmio_tlps.tvalid;
        tx_wr_tlps.tready = to_fiu_tlp.afu_tx_st.tready && !tx_mmio_tlps.tvalid && !tx_rd_tlps.tvalid;

        if (tx_mmio_tlps.tvalid)
        begin
            to_fiu_tlp.afu_tx_st.t.data = tx_mmio_tlps.t.data;
            to_fiu_tlp.afu_tx_st.t.user = tx_mmio_tlps.t.user;
        end
        else if (tx_rd_tlps.tvalid)
        begin
            to_fiu_tlp.afu_tx_st.t.data = tx_rd_tlps.t.data;
            to_fiu_tlp.afu_tx_st.t.user = tx_rd_tlps.t.user;
        end
        else
        begin
            to_fiu_tlp.afu_tx_st.t.data = tx_wr_tlps.t.data;
            to_fiu_tlp.afu_tx_st.t.user = tx_wr_tlps.t.user;
        end
    end

endmodule // ofs_plat_host_chan_@GROUP@_map_to_tlps
