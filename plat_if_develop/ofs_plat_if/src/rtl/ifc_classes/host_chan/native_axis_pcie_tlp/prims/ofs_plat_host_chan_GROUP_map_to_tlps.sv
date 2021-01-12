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


module ofs_plat_host_chan_@group@_map_to_tlps
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu_tlp,

    // MMIO requests from host to AFU (t_gen_tx_mmio_afu_req)
    ofs_plat_axi_stream_if.to_sink host_mmio_req,
    // AFU MMIO responses to host (t_gen_tx_mmio_afu_rsp)
    ofs_plat_axi_stream_if.to_source host_mmio_rsp,

    // Read requests from AFU (t_gen_tx_afu_rd_req)
    ofs_plat_axi_stream_if.to_source afu_rd_req,
    // Read responses to AFU (t_gen_tx_afu_rd_rsp)
    ofs_plat_axi_stream_if.to_sink afu_rd_rsp,

    // Write requests from AFU (t_gen_tx_afu_wr_req)
    ofs_plat_axi_stream_if.to_source afu_wr_req,
    // Write responses to AFU once the packet is completely sent (t_gen_tx_afu_wr_rsp)
    ofs_plat_axi_stream_if.to_sink afu_wr_rsp
    );

    import ofs_plat_host_chan_@group@_pcie_tlp_pkg::*;
    import ofs_plat_host_chan_@group@_gen_tlps_pkg::*;

    logic clk;
    assign clk = to_fiu_tlp.clk;
    logic reset_n;
    assign reset_n = to_fiu_tlp.reset_n;


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

    typedef t_ofs_plat_axis_pcie_tdata [NUM_PIM_PCIE_TLP_CH-1 : 0] t_axis_pcie_tdata_vec;
    typedef t_ofs_plat_axis_pcie_rx_tuser [NUM_PIM_PCIE_TLP_CH-1 : 0] t_axis_pcie_rx_tuser_vec;

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

    ofs_plat_host_chan_align_axis_rx_tlps
      #(
        .NUM_SOURCE_TLP_CH(NUM_FIU_PCIE_TLP_CH),
        .NUM_SINK_TLP_CH(NUM_PIM_PCIE_TLP_CH),
        .TDATA_TYPE(t_ofs_plat_axis_pcie_tdata),
        .TUSER_TYPE(t_ofs_plat_axis_pcie_rx_tuser)
        )
      align_rx
       (
        .stream_source(to_fiu_tlp.afu_rx_st),
        .stream_sink(aligned_rx_st)
        );

    logic rx_cpl_handler_ready;
    assign aligned_rx_st.tready = rx_cpl_handler_ready && host_mmio_req.tready;


    // ====================================================================
    //
    //  Map the PIM-aligned outgoing TX stream to the FIU's width. This
    //  is simpler than the incoming RX stream, since the FIU is reasonably
    //  flexible. The TX alignment only handles mapping to narrower (fewer
    //  channels, e.g. PCIe x8) or wider streams. A wider stream would,
    //  of course, waste the available bandwidth and merely fill it with
    //  invalids.
    //
    // ====================================================================

    typedef t_ofs_plat_axis_pcie_tx_tuser [NUM_PIM_PCIE_TLP_CH-1 : 0] t_axis_pcie_tx_tuser_vec;

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_axis_pcie_tdata_vec),
        .TUSER_TYPE(t_axis_pcie_tx_tuser_vec)
        )
      aligned_tx_st();

    assign aligned_tx_st.clk = clk;
    assign aligned_tx_st.reset_n = reset_n;
    assign aligned_tx_st.instance_number = to_fiu_tlp.instance_number;

    // synthesis translate_off
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_TX(ofs_plat_log_pkg::HOST_CHAN, aligned_tx_st)
    // synthesis translate_on

    ofs_plat_host_chan_align_axis_tx_tlps
      #(
        .NUM_SOURCE_TLP_CH(NUM_PIM_PCIE_TLP_CH),
        .NUM_SINK_TLP_CH(NUM_FIU_PCIE_TLP_CH),
        .TDATA_TYPE(t_ofs_plat_axis_pcie_tdata),
        .TUSER_TYPE(t_ofs_plat_axis_pcie_tx_tuser)
        )
      align_tx
       (
        .stream_source(aligned_tx_st),
        .stream_sink(to_fiu_tlp.afu_tx_st)
        );


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

    ofs_plat_host_chan_@group@_gen_mmio_tlps mmio_rsp_to_tlps
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

    // Write fence completions
    `AXI_STREAM_INSTANCE(wr_fence_cpl, t_dma_rd_tag);

    logic rd_cpld_tag_available;

    ofs_plat_host_chan_@group@_gen_rd_tlps rd_req_to_tlps
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

        // Tags of write fence responses (dataless completion TLP)
        .wr_fence_cpl,

        .tlp_cpld_tag_available(rd_cpld_tag_available),
        .error()
        );


    // ====================================================================
    //
    //  Manage AFU write requests
    //
    // ====================================================================

    // Output write request stream to host (TX TLP vector with NUM_PCIE_TLP_CH channels)
    `AXI_TX_TLP_STREAM_INSTANCE(tx_wr_tlps);

    ofs_plat_host_chan_@group@_gen_wr_tlps wr_req_to_tlps
       (
        .clk,
        .reset_n,

        // Write requests from host
        .afu_wr_req,

        // Output write request TLP stream
        .tx_wr_tlps,

        // Write responses to AFU (once the packet is completely sent)
        .afu_wr_rsp,

        // Tags of write fence responses (dataless completion TLP)
        .wr_fence_cpl,

        // Interrupt completions from the FIU
        .irq_cpl(to_fiu_tlp.afu_irq_rx_st),

        .error()
        );


    // ====================================================================
    //
    //  TLP Tx arbitration
    //
    // ====================================================================

    typedef enum logic [1:0] {
        ARB_NONE,
        ARB_LOCK_MMIO,
        ARB_LOCK_WR
    } t_arb_state;

    t_arb_state arb_state;
    logic [2:0] arb_req;
    logic [2:0] arb_grant;

    logic arb_grant_mmio, arb_grant_rd, arb_grant_wr;
    logic allow_rd_tlps, allow_wr_tlps;
    logic history_fewer_rds;

    ofs_plat_prim_arb_rr
      #(
        .NUM_CLIENTS(3)
        )
      tx_arb
       (
        .clk,
        .reset_n,

        .ena(aligned_tx_st.tready && (arb_state == ARB_NONE)),
        .request(arb_req),
        .grant(arb_grant),
        .grantIdx()
        );

    assign arb_req[0] = tx_mmio_tlps.tvalid;
    assign arb_req[1] = tx_rd_tlps.tvalid && allow_rd_tlps;
    assign arb_req[2] = tx_wr_tlps.tvalid && allow_wr_tlps &&
                        // Block write traffic when reads are blocked due to TLP
                        // tag exhaustion. Writes lack back-pressure since they
                        // don't require tags. Allowing writes to proceed when
                        // reads are blocked causes a significant imbalance when
                        // read and write streams are both active. Without back-
                        // pressure on writes, the FIM pipeline fills with only
                        // write requests.
                        rd_cpld_tag_available;

    assign arb_grant_mmio = arb_grant[0] ||
                            ((arb_state == ARB_LOCK_MMIO) && aligned_tx_st.tready);
    assign arb_grant_rd = arb_grant[1];
    assign arb_grant_wr = arb_grant[2] ||
                          ((arb_state == ARB_LOCK_WR) && aligned_tx_st.tready);

    always_comb
    begin
        aligned_tx_st.tvalid = (arb_grant_mmio || arb_grant_rd || arb_grant_wr);

        tx_mmio_tlps.tready = arb_grant_mmio;
        tx_rd_tlps.tready = arb_grant_rd;
        tx_wr_tlps.tready = arb_grant_wr;

        if (tx_mmio_tlps.tready)
        begin
            aligned_tx_st.t.data = tx_mmio_tlps.t.data;
            aligned_tx_st.t.user = tx_mmio_tlps.t.user;
        end
        else if (tx_rd_tlps.tready)
        begin
            aligned_tx_st.t.data = tx_rd_tlps.t.data;
            aligned_tx_st.t.user = tx_rd_tlps.t.user;
        end
        else
        begin
            aligned_tx_st.t.data = tx_wr_tlps.t.data;
            aligned_tx_st.t.user = tx_wr_tlps.t.user;
        end
    end

    // Track multi-beat messages and hold arbitration
    always_ff @(posedge clk)
    begin
        //
        // Ready signals in the local protocol here are true only when
        // arbitration is won.
        //
        if (tx_mmio_tlps.tready &&
            !tx_mmio_tlps.t.data[0].eop &&
            !tx_mmio_tlps.t.data[1].eop)
        begin
            arb_state <= ARB_LOCK_MMIO;
        end
        else if (tx_wr_tlps.tready &&
                 !tx_wr_tlps.t.data[0].eop &&
                 !tx_wr_tlps.t.data[1].eop)
        begin
            arb_state <= ARB_LOCK_WR;
        end
        else if (aligned_tx_st.tvalid)
        begin
            arb_state <= ARB_NONE;
        end

        if (!reset_n)
        begin
            arb_state <= ARB_NONE;
        end
    end


    //
    // Fair arbitration is quite complicated, mostly as a result of the
    // relatively deep FIM pipeline. When reads are blocked, writes gain
    // an unfair advantage by filling the FIM pipline. The reverse is
    // also true.
    //
    // The arbitration below tracks read and write DWORDs in flight
    // in order to skew arbitration toward whichever is starved.
    //

    ofs_fim_pcie_hdr_def::t_tlp_mem_req_hdr tx_rd_tlps_mem_hdr;
    assign tx_rd_tlps_mem_hdr = tx_rd_tlps.t.data[0].hdr;
    ofs_fim_pcie_hdr_def::t_tlp_mem_req_hdr tx_wr_tlps_mem_hdr;
    assign tx_wr_tlps_mem_hdr = tx_wr_tlps.t.data[0].hdr;


    //
    // Learning algorithms for picking the probability of applying channel
    // favoring. If you apply it every cycle, performance will be suboptimal.
    // The learning algorithm measures bandwidth over intervals and adjusts
    // the weights to maximize total bandwidth.
    //
    // Weights for reads and writes are computed separately.
    //
    ofs_plat_host_chan_tlp_learning_weight
      #(
        .BURST_CNT_WIDTH($bits(t_tlp_payload_line_count)),
        .RD_TRAFFIC_CNT_SHIFT(1),
        // Giving writes slightly less weight than reads seems to result in
        // better decisions.
        .WR_TRAFFIC_CNT_SHIFT(2)
        )
      fairness_weight
       (
        .clk,
        .reset_n,

        .rd_valid(arb_grant_rd),
        .rd_burstcount(dwordLenToLineCount(tx_rd_tlps_mem_hdr.dw0.length)),

        // Track only the SOP beat of writes
        .wr_valid(arb_grant_wr && (arb_state == ARB_NONE)),
        .wr_burstcount(dwordLenToLineCount(tx_wr_tlps_mem_hdr.dw0.length)),

        .update_favoring((tx_rd_tlps.tvalid || tx_wr_tlps.tvalid) &&
                         (arb_state == ARB_NONE)),

        .rd_enable_favoring(allow_rd_tlps),
        .wr_enable_favoring(allow_wr_tlps)
        );


    // synthesis translate_off
    always_ff @(negedge clk)
    begin
        if (reset_n)
        begin
            // Only one winner is allowed!
            assert(2'(arb_grant_mmio) + 2'(arb_grant_rd) + 2'(arb_grant_wr) <= 2'b1) else
                $fatal(2, " ** ERROR ** %m: Multiple arbitration winners!");
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_host_chan_@group@_map_to_tlps
