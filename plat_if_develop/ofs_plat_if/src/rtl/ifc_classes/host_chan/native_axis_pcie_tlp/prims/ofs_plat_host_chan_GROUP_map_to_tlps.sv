// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT


//
// Base mapping of an AXI stream of PCIe TLPs to memory mapped interfaces.
// No particular memory mapped interface is required. The ports here
// pass basic fields needed for any memory interface. It is up to the
// parent module to map to a particular protocol.
//
// The PCIe TLP representation used in this and the read, write and MMIO
// mapping modules is a PIM-specific, platform-independent data structure.
// The mapping code thus works across multiple FIMs and platforms. The
// PIM's mapping is transformed to platform-specific mapping by FIM-specific
// gaskets.
//

`include "ofs_plat_if.vh"


// Lots of streams are used to pass messages through the TLP processing
// modules instantiated here. They use a common idiom. Define a macro
// that instantiates a stream "instance_name" of "data_type" and assigns
// standard clock, reset and debug info.
`define OFS_PLAT_AXI_STREAM_INSTANCE(instance_name, data_type) \
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
`define OFS_PLAT_AXI_TLP_STREAM_INSTANCE(instance_name) \
    ofs_plat_axi_stream_if \
      #( \
        .TDATA_TYPE(ofs_plat_host_chan_@group@_pcie_tlp_pkg::t_ofs_plat_axis_pcie_tdata_vec), \
        .TUSER_TYPE(ofs_plat_host_chan_@group@_pcie_tlp_pkg::t_ofs_plat_axis_pcie_tuser_vec) \
        ) \
      instance_name(); \
    assign instance_name.clk = clk; \
    assign instance_name.reset_n = reset_n; \
    assign instance_name.instance_number = to_fiu_tlp.instance_number


module ofs_plat_host_chan_@group@_map_to_tlps
   (
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu_tlp,
    // Allow Data Mover encoding?
    input  logic allow_dm_enc,

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
    import ofs_plat_pcie_tlp_@group@_hdr_pkg::*;

    logic clk;
    assign clk = to_fiu_tlp.clk;
    logic reset_n;
    assign reset_n = to_fiu_tlp.reset_n;

`ifdef OFS_PLAT_PARAM_HOST_CHAN_GASKET_PCIE_SS
    localparam FIM_HAS_SEPARATE_READ_STREAM = 1;
`else
    localparam FIM_HAS_SEPARATE_READ_STREAM = 0;
`endif

    `OFS_PLAT_AXI_TLP_STREAM_INSTANCE(from_fiu_mmio_req);
    `OFS_PLAT_AXI_TLP_STREAM_INSTANCE(from_fiu_rd_cpl);
    `OFS_PLAT_AXI_STREAM_INSTANCE(from_fiu_wr_cpl, t_gen_tx_wr_cpl);
    `OFS_PLAT_AXI_STREAM_INSTANCE(from_fiu_irq_cpl, t_ofs_plat_pcie_hdr_irq);

    // synthesis translate_off
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_RX(ofs_plat_log_pkg::HOST_CHAN, from_fiu_mmio_req)
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_RX(ofs_plat_log_pkg::HOST_CHAN, from_fiu_rd_cpl)
    // synthesis translate_on


    `OFS_PLAT_AXI_TLP_STREAM_INSTANCE(to_fiu_tx_st);
    `OFS_PLAT_AXI_TLP_STREAM_INSTANCE(to_fiu_tx_st_skid);

    // Read request stream to FIM, used only when the FIM provides a separate
    // port for read requests. Otherwise, tied off.
    `OFS_PLAT_AXI_TLP_STREAM_INSTANCE(to_fiu_tx_mrd_st);

    // synthesis translate_off
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_AXIS_PCIE_TLP_TX(ofs_plat_log_pkg::HOST_CHAN, to_fiu_tx_st)
    // synthesis translate_on

    // Outbound skid buffer for timing and to drop poisoned requests. The most common
    // poisoned request is a write fence with no previous write, which is both not
    // necessary and impossible to generate without an address.
    logic tx_st_skid_tvalid;
    ofs_plat_prim_ready_enable_skid
      #(
        .N_DATA_BITS(to_fiu_tx_st.T_PAYLOAD_WIDTH)
        )
      skid
       (
        .clk(to_fiu_tx_st.clk),
        .reset_n(to_fiu_tx_st.reset_n),

        .enable_from_src(to_fiu_tx_st.tvalid),
        .data_from_src(to_fiu_tx_st.t),
        .ready_to_src(to_fiu_tx_st.tready),

        .enable_to_dst(tx_st_skid_tvalid),
        .data_to_dst(to_fiu_tx_st_skid.t),
        .ready_from_dst(to_fiu_tx_st_skid.tready)
        );

    assign to_fiu_tx_st_skid.tvalid = tx_st_skid_tvalid &&
                                      !to_fiu_tx_st_skid.t.user[0].poison;


    // Map the FIM's TLP encoding to the PIM's encoding using the
    // platform-specific gasket.
    ofs_plat_host_chan_@group@_fim_gasket fim_gasket
       (
        .to_fiu_tlp,
        .allow_dm_enc,

        // TX (AFU -> host)
        .tx_from_pim(to_fiu_tx_st_skid),
        // TX MRd stream (AFU -> host)
        .tx_mrd_from_pim(to_fiu_tx_mrd_st),

        // MMIO requests (host -> AFU)
        .mmio_req_to_pim(from_fiu_mmio_req),
        // Read completions (host -> AFU)
        .rd_cpl_to_pim(from_fiu_rd_cpl),
        // Write completions
        .wr_cpl_to_pim(from_fiu_wr_cpl),
        // Interrupt responses (host -> AFU)
        .irq_cpl_to_pim(from_fiu_irq_cpl)
        );


    // ====================================================================
    //
    //  Manage MMIO requests and responses.
    //
    // ====================================================================

    // Output response stream (TX TLP vector with NUM_PCIE_TLP_CH channels)
    `OFS_PLAT_AXI_TLP_STREAM_INSTANCE(tx_mmio_tlps);

    ofs_plat_host_chan_@group@_gen_mmio_tlps mmio_to_tlps
       (
        .clk,
        .reset_n,

        .from_fiu_rx_st(from_fiu_mmio_req),
        .host_mmio_req,
        .host_mmio_rsp,
        .tx_mmio(tx_mmio_tlps),

        .error()
        );


    // ====================================================================
    //
    //  Manage AFU read requests and host completion responses
    //
    // ====================================================================

    // Output read request stream to host (TX TLP vector with NUM_PCIE_TLP_CH channels)
    `OFS_PLAT_AXI_TLP_STREAM_INSTANCE(tx_rd_tlps);

    // Atomic completion tags are allocated by sending a dummy read through the
    // read pipeline. Response tags are attached to the atomic write request
    // through this stream.
    `OFS_PLAT_AXI_STREAM_INSTANCE(atomic_cpl_tag, t_dma_rd_tag);

    // Write fence completions
    `OFS_PLAT_AXI_STREAM_INSTANCE(wr_fence_cpl, t_gen_tx_wr_cpl);

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
        .rx_cpl_tlps(from_fiu_rd_cpl),

        // Read responses to AFU
        .afu_rd_rsp,

        // Tags for atomic completions allocated by the read engine but
        // forwarded to the write engine.
        .atomic_cpl_tag,

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
    `OFS_PLAT_AXI_TLP_STREAM_INSTANCE(tx_wr_tlps);

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

        // Write commits from FIM gasket
        .wr_cpl(from_fiu_wr_cpl),

        // Tags for atomic completions allocated by the read engine but
        // forwarded to the write engine.
        .atomic_cpl_tag,

        // Tags of write fence responses (dataless completion TLP)
        .wr_fence_cpl,

        // Interrupt completions from the FIM
        .irq_cpl(from_fiu_irq_cpl),

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
    logic force_allow_wr;

    ofs_plat_prim_arb_rr
      #(
        .NUM_CLIENTS(3)
        )
      tx_arb
       (
        .clk,
        .reset_n,

        .ena(to_fiu_tx_st.tready && (arb_state == ARB_NONE)),
        .request(arb_req),
        .grant(arb_grant),
        .grantIdx()
        );

    assign arb_req[0] = tx_mmio_tlps.tvalid;
    // For FIMs with a separate read stream, no read arbitration is required
    assign arb_req[1] = (FIM_HAS_SEPARATE_READ_STREAM ? 1'b0 : tx_rd_tlps.tvalid && allow_rd_tlps);
    assign arb_req[2] = tx_wr_tlps.tvalid && allow_wr_tlps &&
                        // Block write traffic when reads are blocked due to TLP
                        // tag exhaustion. Writes lack back-pressure since they
                        // don't require tags. Allowing writes to proceed when
                        // reads are blocked causes a significant imbalance when
                        // read and write streams are both active. Without back-
                        // pressure on writes, the FIM pipeline fills with only
                        // write requests. The force_allow_wr flag avoids a
                        // deadlock when reads are blocked due to the write
                        // stream also being blocked.
                        (rd_cpld_tag_available || force_allow_wr);

    // Allow writes when there has been no write activity for a while, even
    // if reads are blocked.
    logic [4:0] non_wr_ctr;
    always_ff @(posedge clk)
    begin
        non_wr_ctr <= non_wr_ctr + 1;
        if (non_wr_ctr[4])
        begin
            force_allow_wr <= 1'b1;
        end

        // A write was granted this cycle, or in reset
        if (!reset_n || arb_grant_wr)
        begin
            force_allow_wr <= 1'b0;
            non_wr_ctr <= '0;
        end
    end

    assign arb_grant_mmio = arb_grant[0] ||
                            ((arb_state == ARB_LOCK_MMIO) && to_fiu_tx_st.tready && tx_mmio_tlps.tvalid);
    assign arb_grant_rd = arb_grant[1];
    assign arb_grant_wr = arb_grant[2] ||
                          ((arb_state == ARB_LOCK_WR) && to_fiu_tx_st.tready && tx_wr_tlps.tvalid);

    always_comb
    begin
        to_fiu_tx_st.tvalid = (arb_grant_mmio || arb_grant_rd || arb_grant_wr);

        tx_mmio_tlps.tready = arb_grant_mmio;
        tx_wr_tlps.tready = arb_grant_wr;
        // tx_rd_tlps.tready is set in a generate block below, only when
        // FIM_HAS_SEPARATE_READ_STREAM is false. Otherwise, the tx_rd_tlps
        // stream is forwarded without arbitration to the FIM.

        if (tx_mmio_tlps.tready)
        begin
            to_fiu_tx_st.t = tx_mmio_tlps.t;
        end
        else if ((FIM_HAS_SEPARATE_READ_STREAM == 0) && tx_rd_tlps.tready)
        begin
            to_fiu_tx_st.t = tx_rd_tlps.t;
        end
        else
        begin
            to_fiu_tx_st.t = tx_wr_tlps.t;
        end
    end

    // Compute whether EOP is present in this beat for various TX streams
    logic tx_mmio_tlps_eop;
    assign tx_mmio_tlps_eop = ofs_plat_pcie_func_is_eop(tx_mmio_tlps.t.user);
    logic tx_wr_tlps_eop;
    assign tx_wr_tlps_eop = ofs_plat_pcie_func_is_eop(tx_wr_tlps.t.user);

    // Track multi-beat messages and hold arbitration
    always_ff @(posedge clk)
    begin
        //
        // Ready signals in the local protocol here are true only when
        // arbitration is won.
        //
        if (tx_mmio_tlps.tready && !tx_mmio_tlps_eop)
        begin
            arb_state <= ARB_LOCK_MMIO;
        end
        else if (tx_wr_tlps.tready && !tx_wr_tlps_eop)
        begin
            arb_state <= ARB_LOCK_WR;
        end
        else if (to_fiu_tx_st.tvalid)
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


    generate
        if (FIM_HAS_SEPARATE_READ_STREAM)
        begin : mrd_st
            // Pass reads in a separate TLP stream, with arbitration handled by
            // the FIM.
            ofs_plat_axi_stream_if_connect conn_tx_mrd
               (
                .stream_source(tx_rd_tlps),
                .stream_sink(to_fiu_tx_mrd_st)
                );

            assign allow_rd_tlps = 1'b1;
            assign allow_wr_tlps = 1'b1;
        end
        else
        begin : shared_st
            // Read/write arbitration is handled in this module.
            assign to_fiu_tx_mrd_st.tvalid = 1'b0;
            assign to_fiu_tx_mrd_st.t = '0;

            assign tx_rd_tlps.tready = arb_grant_rd;

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
                .rd_burstcount(dwordLenToLineCount(tx_rd_tlps.t.user[0].hdr.length)),

                // Track only the SOP beat of writes
                .wr_valid(arb_grant_wr && (arb_state == ARB_NONE)),
                .wr_burstcount(dwordLenToLineCount(tx_wr_tlps.t.user[0].hdr.length)),

                .update_favoring((tx_rd_tlps.tvalid || tx_wr_tlps.tvalid) &&
                                 (arb_state == ARB_NONE)),

                .rd_enable_favoring(allow_rd_tlps),
                .wr_enable_favoring(allow_wr_tlps)
                );
        end
    endgenerate


    // synthesis translate_off
    always_ff @(negedge clk)
    begin
        if (reset_n)
        begin
            // Only one winner is allowed!
            assert(2'(arb_grant_mmio) + 2'(arb_grant_rd) + 2'(arb_grant_wr) <= 2'b1) else
                $fatal(2, " ** ERROR ** %m: Multiple arbitration winners!");

            // Check that TX addresses are encoded properly as 32 or 64 bits.
            if (to_fiu_tx_st.tvalid && !to_fiu_tx_st.t.user[0].poison &&
                ofs_plat_pcie_func_is_mem_req(to_fiu_tx_st.t.user[0].hdr.fmttype))
            begin
                if (ofs_plat_pcie_func_is_addr64(to_fiu_tx_st.t.user[0].hdr.fmttype))
                begin
                    assert(to_fiu_tx_st.t.user[0].hdr.u.mem_req.addr[63:32] != 32'b0) else
                        $fatal(2, " ** ERROR ** %m: TX memory request claims 64 bit address but it is 32!");
                end
                else
                begin
                    assert(to_fiu_tx_st.t.user[0].hdr.u.mem_req.addr[63:32] == 32'b0) else
                        $fatal(2, " ** ERROR ** %m: TX memory request claims 32 bit address but it is 64!");
                end
            end
        end
    end
    // synthesis translate_on

endmodule // ofs_plat_host_chan_@group@_map_to_tlps

`undef OFS_PLAT_AXI_STREAM_INSTANCE
`undef OFS_PLAT_AXI_TLP_STREAM_INSTANCE
