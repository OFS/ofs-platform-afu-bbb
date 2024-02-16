// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// OFS EA-specific mapping of the EA FIM's TLP streams to the PIM's internal
// PCIe TLP representation.
//

//
// The implementation here handles multiple RX message configurations, where
// read completions and write commits may be on either RX-A or RX-B. The
// configuration is static, making the RTL complex but the generated logic
// remains efficient.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_@group@_fim_gasket
   (
    // Interface to FIM
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu_tlp,
    // Allow Data Mover encoding?
    input  logic allow_dm_enc,

    // PIM encoding (FPGA->host)
    ofs_plat_axi_stream_if.to_source tx_from_pim,
    // PIM encoding (FPGA->host, optional separate MRd stream)
    ofs_plat_axi_stream_if.to_source tx_mrd_from_pim,

    // MMIO requests (host -> AFU)
    ofs_plat_axi_stream_if.to_sink mmio_req_to_pim,

    // Read completions (host -> AFU)
    ofs_plat_axi_stream_if.to_sink rd_cpl_to_pim,

    // Write completions (t_gen_tx_wr_cpl)
    ofs_plat_axi_stream_if.to_sink wr_cpl_to_pim,

    // PIM encoding interrupt completions (t_ofs_plat_pcie_hdr_irq)
    ofs_plat_axi_stream_if.to_sink irq_cpl_to_pim
    );

    import ofs_plat_pcie_tlp_hdr_pkg::*;
    import ofs_plat_host_chan_@group@_fim_gasket_pkg::*;

    logic clk;
    assign clk = to_fiu_tlp.clk;
    logic reset_n;
    assign reset_n = to_fiu_tlp.reset_n;

    // Delay the allow_dm_enc flag for timing
    logic [7:0] allow_dm_enc_reg;
    wire allow_dm_enc_q = allow_dm_enc_reg[7];
    always_ff @(posedge clk)
    begin
        allow_dm_enc_reg <= { allow_dm_enc_reg[6:0], allow_dm_enc };
    end


    // ====================================================================
    //
    //  Map FIM interfaces to the PIM's representation of the same messages
    //
    // ====================================================================

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser)
        )
      fim_tx_a_st();

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser)
        )
      fim_tx_b_st();

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser)
        )
      fim_rx_a_st();

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(ofs_plat_host_chan_@group@_fim_gasket_pkg::t_ofs_fim_axis_pcie_tuser)
        )
      fim_rx_b_st();

    assign fim_tx_a_st.clk = to_fiu_tlp.clk;
    assign fim_tx_a_st.reset_n = to_fiu_tlp.reset_n;
    assign fim_tx_a_st.instance_number = to_fiu_tlp.instance_number;

    assign fim_tx_b_st.clk = to_fiu_tlp.clk;
    assign fim_tx_b_st.reset_n = to_fiu_tlp.reset_n;
    assign fim_tx_b_st.instance_number = to_fiu_tlp.instance_number;

    assign fim_rx_a_st.clk = to_fiu_tlp.clk;
    assign fim_rx_a_st.reset_n = to_fiu_tlp.reset_n;
    assign fim_rx_a_st.instance_number = to_fiu_tlp.instance_number;

    assign fim_rx_b_st.clk = to_fiu_tlp.clk;
    assign fim_rx_b_st.reset_n = to_fiu_tlp.reset_n;
    assign fim_rx_b_st.instance_number = to_fiu_tlp.instance_number;

    map_fim_pcie_ss_to_@group@_pim_axi_stream fim_to_pim
       (
        .pcie_ss_tx_a_st(to_fiu_tlp.afu_tx_a_st),
        .pcie_ss_tx_b_st(to_fiu_tlp.afu_tx_b_st),
        .pcie_ss_rx_a_st(to_fiu_tlp.afu_rx_a_st),
        .pcie_ss_rx_b_st(to_fiu_tlp.afu_rx_b_st),

        .pim_tx_a_st(fim_tx_a_st),
        .pim_tx_b_st(fim_tx_b_st),
        .pim_rx_a_st(fim_rx_a_st),
        .pim_rx_b_st(fim_rx_b_st)
        );

    // synthesis translate_off
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_FIM_GASKET_PCIE_TLP(ofs_plat_log_pkg::HOST_CHAN, "tx_a_st", fim_tx_a_st)
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_FIM_GASKET_PCIE_TLP(ofs_plat_log_pkg::HOST_CHAN, "tx_b_st", fim_tx_b_st)
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_FIM_GASKET_PCIE_TLP(ofs_plat_log_pkg::HOST_CHAN, "rx_a_st", fim_rx_a_st)
    `LOG_OFS_PLAT_HOST_CHAN_@GROUP@_FIM_GASKET_PCIE_TLP(ofs_plat_log_pkg::HOST_CHAN, "rx_b_st", fim_rx_b_st)
    // synthesis translate_on


    // ====================================================================
    //
    //  AFU -> FIM TX stream translation from PIM to FIM encoding
    //
    // ====================================================================

    ofs_plat_axi_stream_if
      #(
        // The type of the stream doesn't matter as long as it is the
        // size of a PCIe SS header. All headers are the same size.
        .TDATA_TYPE(pcie_ss_hdr_pkg::PCIe_ReqHdr_t),
        .TUSER_TYPE(logic)    // pu mode (0) / dm mode (1)
        )
      fim_enc_tx_hdr();

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(logic)    // Not used
        )
      fim_enc_tx_data();

    assign fim_enc_tx_hdr.clk = to_fiu_tlp.clk;
    assign fim_enc_tx_hdr.reset_n = to_fiu_tlp.reset_n;
    assign fim_enc_tx_hdr.instance_number = to_fiu_tlp.instance_number;
    assign fim_enc_tx_data.clk = to_fiu_tlp.clk;
    assign fim_enc_tx_data.reset_n = to_fiu_tlp.reset_n;
    assign fim_enc_tx_data.instance_number = to_fiu_tlp.instance_number;

    //
    //  Map the PIM-aligned outgoing TX stream to the FIU's in band
    //  TLP header encoding.
    //
    ofs_plat_host_chan_@group@_align_tx_tlps
      align_tx
       (
        .stream_sink(fim_tx_a_st),
        .hdr_stream_source(fim_enc_tx_hdr),
        .data_stream_source(fim_enc_tx_data)
        );

    assign tx_from_pim.tready = fim_enc_tx_hdr.tready && fim_enc_tx_data.tready;
    assign fim_enc_tx_data.tvalid = tx_from_pim.tvalid && tx_from_pim.tready;
    assign fim_enc_tx_hdr.tvalid = fim_enc_tx_data.tvalid && tx_from_pim.t.user[0].sop;


    always_comb
    begin
        fim_enc_tx_data.t = '0;
        fim_enc_tx_data.t.data = tx_from_pim.t.data[0];
        fim_enc_tx_data.t.last = tx_from_pim.t.user[0].eop;
        fim_enc_tx_data.t.keep = tx_from_pim.t.keep;
    end

    // Construct headers for all message types. Only one will actually be
    // used, depending on fmttype.
    pcie_ss_hdr_pkg::PCIe_ReqHdr_t tx_mem_req_dm_hdr;
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t tx_mem_req_pu_hdr;
    pcie_ss_hdr_pkg::PCIe_PUCplHdr_t tx_cpl_hdr;
    pcie_ss_hdr_pkg::PCIe_IntrHdr_t tx_irq_hdr;

    pcie_ss_hdr_pkg::ReqHdr_FmtType_e tx_fmttype;
    assign tx_fmttype = pcie_ss_hdr_pkg::ReqHdr_FmtType_e'(tx_from_pim.t.user[0].hdr.fmttype);

    // Use DM encoding for most write requests. Short writes not aligned to dwords
    // use PU encoding since DM would require a data shift.
    wire tx_req_hdr_use_dm =
        ofs_plat_host_chan_@group@_fim_gasket_pkg::ALLOW_DM_ENCODING &&
        allow_dm_enc_q &&
        ((tx_fmttype == pcie_ss_hdr_pkg::M_WR) || (tx_fmttype == pcie_ss_hdr_pkg::DM_WR)) &&
        &(tx_from_pim.t.user[0].hdr.u.mem_req.last_be) &&
        &(tx_from_pim.t.user[0].hdr.u.mem_req.first_be);

    // Memory request - DM encoding
    always_comb
    begin
        tx_mem_req_dm_hdr = '0;

        if (tx_fmttype == pcie_ss_hdr_pkg::M_WR)
            tx_mem_req_dm_hdr.fmt_type = pcie_ss_hdr_pkg::DM_WR;
        else if (tx_fmttype == pcie_ss_hdr_pkg::M_RD)
            tx_mem_req_dm_hdr.fmt_type = pcie_ss_hdr_pkg::DM_RD;
        else
            tx_mem_req_dm_hdr.fmt_type = tx_fmttype;

        { tx_mem_req_dm_hdr.length_h, tx_mem_req_dm_hdr.length_m, tx_mem_req_dm_hdr.length_l } =
            { '0, tx_from_pim.t.user[0].hdr.length, 2'b0 };
        tx_mem_req_dm_hdr.TC = tx_from_pim.t.user[0].hdr.u.mem_req.tc;
        { tx_mem_req_dm_hdr.tag_h, tx_mem_req_dm_hdr.tag_m, tx_mem_req_dm_hdr.tag_l } =
            { '0, tx_from_pim.t.user[0].hdr.u.mem_req.tag };

        { tx_mem_req_dm_hdr.host_addr_h, tx_mem_req_dm_hdr.host_addr_m, tx_mem_req_dm_hdr.host_addr_l } =
            tx_from_pim.t.user[0].hdr.u.mem_req.addr;

        tx_mem_req_dm_hdr.pf_num = to_fiu_tlp.pf_num;
        tx_mem_req_dm_hdr.vf_num = to_fiu_tlp.vf_num;
        tx_mem_req_dm_hdr.vf_active = to_fiu_tlp.vf_active;

        // Because there are two TX pipelines in the FIM, TX A for writes and TX B
        // for reads, the commit point of writes has not yet been reached. Pass
        // the AFU's completion tag to the FIM. It will be returned in a dataless
        // completion by the FIM once each write is committed to an ordered stream.
        if (pcie_ss_hdr_pkg::func_is_mem_req(tx_fmttype))
        begin
            tx_mem_req_dm_hdr.metadata_l = { '0, tx_from_pim.t.user[0].afu_tag };
        end
    end

    // Memory request - PU encoding
    always_comb
    begin
        tx_mem_req_pu_hdr = '0;
        tx_mem_req_pu_hdr.fmt_type = tx_fmttype;
        tx_mem_req_pu_hdr.length = tx_from_pim.t.user[0].hdr.length;
        tx_mem_req_pu_hdr.req_id = { to_fiu_tlp.vf_num, to_fiu_tlp.vf_active, to_fiu_tlp.pf_num };
        tx_mem_req_pu_hdr.TC = tx_from_pim.t.user[0].hdr.u.mem_req.tc;
        { tx_mem_req_pu_hdr.tag_h, tx_mem_req_pu_hdr.tag_m, tx_mem_req_pu_hdr.tag_l } =
            { '0, tx_from_pim.t.user[0].hdr.u.mem_req.tag };
        tx_mem_req_pu_hdr.last_dw_be = tx_from_pim.t.user[0].hdr.u.mem_req.last_be;
        tx_mem_req_pu_hdr.first_dw_be = tx_from_pim.t.user[0].hdr.u.mem_req.first_be;
        if (pcie_ss_hdr_pkg::func_is_addr64(tx_fmttype))
        begin
            tx_mem_req_pu_hdr.host_addr_h = tx_from_pim.t.user[0].hdr.u.mem_req.addr[63:32];
            tx_mem_req_pu_hdr.host_addr_l = tx_from_pim.t.user[0].hdr.u.mem_req.addr[31:2];
        end
        else
        begin
            tx_mem_req_pu_hdr.host_addr_h = tx_from_pim.t.user[0].hdr.u.mem_req.addr[31:0];
        end
        tx_mem_req_pu_hdr.pf_num = to_fiu_tlp.pf_num;
        tx_mem_req_pu_hdr.vf_num = to_fiu_tlp.vf_num;
        tx_mem_req_pu_hdr.vf_active = to_fiu_tlp.vf_active;

        // Because there are two TX pipelines in the FIM, TX A for writes and TX B
        // for reads, the commit point of writes has not yet been reached. Pass
        // the AFU's completion tag to the FIM. It will be returned in a dataless
        // completion by the FIM once each write is committed to an ordered stream.
        if (pcie_ss_hdr_pkg::func_is_mem_req(tx_fmttype))
        begin
            tx_mem_req_pu_hdr.metadata_l = { '0, tx_from_pim.t.user[0].afu_tag };
        end
    end

    // Completion
    always_comb
    begin
        tx_cpl_hdr = '0;
        tx_cpl_hdr.fmt_type = tx_fmttype;
        tx_cpl_hdr.length = tx_from_pim.t.user[0].hdr.length;
        tx_cpl_hdr.req_id = tx_from_pim.t.user[0].hdr.u.cpl.requester_id;
        tx_cpl_hdr.TC = tx_from_pim.t.user[0].hdr.u.cpl.tc;
        { tx_cpl_hdr.tag_h, tx_cpl_hdr.tag_m, tx_cpl_hdr.tag_l } =
            { '0, tx_from_pim.t.user[0].hdr.u.cpl.tag };
        tx_cpl_hdr.byte_count = tx_from_pim.t.user[0].hdr.u.cpl.byte_count;
        tx_cpl_hdr.low_addr = tx_from_pim.t.user[0].hdr.u.cpl.lower_addr;
        tx_cpl_hdr.comp_id = { to_fiu_tlp.vf_num, to_fiu_tlp.vf_active, to_fiu_tlp.pf_num };
        tx_cpl_hdr.pf_num = to_fiu_tlp.pf_num;
        tx_cpl_hdr.vf_num = to_fiu_tlp.vf_num;
        tx_cpl_hdr.vf_active = to_fiu_tlp.vf_active;
    end

    // Interrupt request
    always_comb
    begin
        tx_irq_hdr = '0;
        tx_irq_hdr.fmt_type = pcie_ss_hdr_pkg::DM_INTR;
        tx_irq_hdr.vector_num = { '0, tx_from_pim.t.user[0].hdr.u.irq.irq_id };
        tx_irq_hdr.pf_num = to_fiu_tlp.pf_num;
        tx_irq_hdr.vf_num = to_fiu_tlp.vf_num;
        tx_irq_hdr.vf_active = to_fiu_tlp.vf_active;
    end

    logic tx_from_pim_invalid_cmd;

    // Map TX header and data
    always_comb
    begin
        tx_from_pim_invalid_cmd = 1'b0;
        fim_enc_tx_hdr.t = '0;

        if (tx_from_pim.t.user[0].hdr.is_irq)
        begin
            fim_enc_tx_hdr.t.data = tx_irq_hdr;
            fim_enc_tx_hdr.t.user = 1'b1;	// Interrupt uses Data Mover encoding
        end
        else if (tx_req_hdr_use_dm)
        begin
            fim_enc_tx_hdr.t.data = tx_mem_req_dm_hdr;
            fim_enc_tx_hdr.t.user = 1'b1;
        end
        else if (pcie_ss_hdr_pkg::func_is_mem_req(tx_fmttype))
        begin
            // Any memory request that isn't a write is PU encoded. These are
            // atomic updates and fences.
            fim_enc_tx_hdr.t.data = tx_mem_req_pu_hdr;
        end
        else if (pcie_ss_hdr_pkg::func_is_completion(tx_fmttype))
        begin
            fim_enc_tx_hdr.t.data = tx_cpl_hdr;
        end
        else
        begin
            tx_from_pim_invalid_cmd = fim_enc_tx_hdr.tvalid;
        end
    end

    // synthesis translate_off
    always_ff @(posedge tx_from_pim.clk)
    begin
        if (tx_from_pim.reset_n && tx_from_pim_invalid_cmd)
            $fatal(2, "Unexpected TLP TX header to PIM!");
    end
    // synthesis translate_on


    // ====================================================================
    //
    //  AFU -> FIM TX MRd stream translation from PIM to FIM encoding
    //
    // ====================================================================

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(t_ofs_fim_axis_pcie_tuser)
        )
      fim_enc_tx_mrd();

    assign tx_mrd_from_pim.tready = fim_enc_tx_mrd.tready;

    // Construct a read request header
    pcie_ss_hdr_pkg::PCIe_ReqHdr_t tx_mrd_req_dm_hdr;
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t tx_mrd_req_pu_hdr;

    pcie_ss_hdr_pkg::ReqHdr_FmtType_e tx_mrd_fmttype;
    assign tx_mrd_fmttype = pcie_ss_hdr_pkg::ReqHdr_FmtType_e'(tx_mrd_from_pim.t.user[0].hdr.fmttype);

    // Use DM encoding for most read requests. Short reads not aligned to dwords
    // use PU encoding since DM would require a data shift.
    wire tx_mrd_req_hdr_use_dm =
        ofs_plat_host_chan_@group@_fim_gasket_pkg::ALLOW_DM_ENCODING &&
        allow_dm_enc_q &&
        ((tx_mrd_fmttype == pcie_ss_hdr_pkg::M_RD) || (tx_mrd_fmttype == pcie_ss_hdr_pkg::DM_RD)) &&
        &(tx_mrd_from_pim.t.user[0].hdr.u.mem_req.last_be) &&
        &(tx_mrd_from_pim.t.user[0].hdr.u.mem_req.first_be);

    // Memory request - DM encoding
    always_comb
    begin
        tx_mrd_req_dm_hdr = '0;

        if (tx_mrd_fmttype == pcie_ss_hdr_pkg::M_WR)
            tx_mrd_req_dm_hdr.fmt_type = pcie_ss_hdr_pkg::DM_WR;
        else if (tx_mrd_fmttype == pcie_ss_hdr_pkg::M_RD)
            tx_mrd_req_dm_hdr.fmt_type = pcie_ss_hdr_pkg::DM_RD;
        else
            tx_mrd_req_dm_hdr.fmt_type = tx_mrd_fmttype;

        { tx_mrd_req_dm_hdr.length_h, tx_mrd_req_dm_hdr.length_m, tx_mrd_req_dm_hdr.length_l } =
            { '0, tx_mrd_from_pim.t.user[0].hdr.length, 2'b0 };
        tx_mrd_req_dm_hdr.TC = tx_mrd_from_pim.t.user[0].hdr.u.mem_req.tc;
        { tx_mrd_req_dm_hdr.tag_h, tx_mrd_req_dm_hdr.tag_m, tx_mrd_req_dm_hdr.tag_l } =
            { '0, tx_mrd_from_pim.t.user[0].hdr.u.mem_req.tag };

        { tx_mrd_req_dm_hdr.host_addr_h, tx_mrd_req_dm_hdr.host_addr_m, tx_mrd_req_dm_hdr.host_addr_l } =
            tx_mrd_from_pim.t.user[0].hdr.u.mem_req.addr;

        tx_mrd_req_dm_hdr.pf_num = to_fiu_tlp.pf_num;
        tx_mrd_req_dm_hdr.vf_num = to_fiu_tlp.vf_num;
        tx_mrd_req_dm_hdr.vf_active = to_fiu_tlp.vf_active;
    end

    // Memory request - PU encoding
    always_comb
    begin
        tx_mrd_req_pu_hdr = '0;
        tx_mrd_req_pu_hdr.fmt_type = tx_mrd_fmttype;
        tx_mrd_req_pu_hdr.length = tx_mrd_from_pim.t.user[0].hdr.length;
        tx_mrd_req_pu_hdr.req_id = { to_fiu_tlp.vf_num, to_fiu_tlp.vf_active, to_fiu_tlp.pf_num };
        tx_mrd_req_pu_hdr.TC = tx_mrd_from_pim.t.user[0].hdr.u.mem_req.tc;
        { tx_mrd_req_pu_hdr.tag_h, tx_mrd_req_pu_hdr.tag_m, tx_mrd_req_pu_hdr.tag_l } =
            { '0, tx_mrd_from_pim.t.user[0].hdr.u.mem_req.tag };
        tx_mrd_req_pu_hdr.last_dw_be = tx_mrd_from_pim.t.user[0].hdr.u.mem_req.last_be;
        tx_mrd_req_pu_hdr.first_dw_be = tx_mrd_from_pim.t.user[0].hdr.u.mem_req.first_be;
        if (pcie_ss_hdr_pkg::func_is_addr64(tx_mrd_fmttype))
        begin
            tx_mrd_req_pu_hdr.host_addr_h = tx_mrd_from_pim.t.user[0].hdr.u.mem_req.addr[63:32];
            tx_mrd_req_pu_hdr.host_addr_l = tx_mrd_from_pim.t.user[0].hdr.u.mem_req.addr[31:2];
        end
        else
        begin
            tx_mrd_req_pu_hdr.host_addr_h = tx_mrd_from_pim.t.user[0].hdr.u.mem_req.addr[31:0];
        end
        tx_mrd_req_pu_hdr.pf_num = to_fiu_tlp.pf_num;
        tx_mrd_req_pu_hdr.vf_num = to_fiu_tlp.vf_num;
        tx_mrd_req_pu_hdr.vf_active = to_fiu_tlp.vf_active;
    end

    assign fim_enc_tx_mrd.tvalid = tx_mrd_from_pim.tvalid;

    always_comb
    begin
        fim_enc_tx_mrd.t = '0;
        fim_enc_tx_mrd.t.data = { '0, (tx_mrd_req_hdr_use_dm ? tx_mrd_req_dm_hdr : tx_mrd_req_pu_hdr) };
        fim_enc_tx_mrd.t.keep = { '0, {($bits(tx_mrd_req_dm_hdr)/8){1'b1}} };
        fim_enc_tx_mrd.t.last = tx_mrd_from_pim.t.user[0].eop;
        fim_enc_tx_mrd.t.user[0].dm_mode = tx_mrd_req_hdr_use_dm;
        fim_enc_tx_mrd.t.user[0].sop = tx_mrd_from_pim.t.user[0].sop;
        fim_enc_tx_mrd.t.user[0].eop = tx_mrd_from_pim.t.user[0].eop;
    end

    ofs_plat_axi_stream_if_skid_sink_clk mrd_exit_skid
       (
        .stream_source(fim_enc_tx_mrd),
        .stream_sink(fim_tx_b_st)
        );


    // ====================================================================
    //
    //  FIM -> AFU RX stream translation from FIM to PIM encoding
    //
    // ====================================================================

    //
    // It is not supported to send both write commits and read completions to
    // the RX-B channel. The configuration comes from
    // ofs_plat_host_chan_@group@_fim_gasket_pkg.
    //
    initial
    begin
        assert ((CPL_CHAN != PCIE_CHAN_B) ||
                (WR_COMMIT_CHAN != PCIE_CHAN_B)) else
          $fatal(2, "Illegal FIM configuration: both CPL_CHAN and WR_COMMIT_CHAN are RX-B!");
    end

    //
    // Map RX-A to separate header and data streams. The PIM expects out-of-band
    // headers.
    //
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t),
        .TUSER_TYPE(logic)    // pu mode (0) / dm mode (1)
        )
      fim_enc_rx_a_hdr();

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(logic)    // Not used
        )
      fim_enc_rx_a_data();

    assign fim_enc_rx_a_hdr.clk = to_fiu_tlp.clk;
    assign fim_enc_rx_a_hdr.reset_n = to_fiu_tlp.reset_n;
    assign fim_enc_rx_a_hdr.instance_number = to_fiu_tlp.instance_number;
    assign fim_enc_rx_a_data.clk = to_fiu_tlp.clk;
    assign fim_enc_rx_a_data.reset_n = to_fiu_tlp.reset_n;
    assign fim_enc_rx_a_data.instance_number = to_fiu_tlp.instance_number;

    //
    //  Align the incoming RX stream in canonical form, making it far
    //  easier to map to wider lines.
    //
    //  The sink streams guarantee:
    //   1. At most one header per cycle in hdr_stream_sink.
    //   2. Data aligned to the bus width in data_stream_sink.
    //
    ofs_plat_host_chan_@group@_align_rx_tlps
      align_rx_a
       (
        .stream_source(fim_rx_a_st),
        .hdr_stream_sink(fim_enc_rx_a_hdr),
        .data_stream_sink(fim_enc_rx_a_data)
        );


    //
    // RX-B handling is more complicated because its mapping depends on
    // whether read completions are on RX-B or whether write commits are
    // on RX-B. (It will always be one or the other, or neither.)
    // When read completions are on RX-B, separate headers and data
    // just like RX-A.
    //
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t),
        .TUSER_TYPE(logic)    // pu mode (0) / dm mode (1)
        )
      fim_enc_rx_b_hdr();

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(logic)    // Not used
        )
      fim_enc_rx_b_data();

    assign fim_enc_rx_b_hdr.clk = to_fiu_tlp.clk;
    assign fim_enc_rx_b_hdr.reset_n = to_fiu_tlp.reset_n;
    assign fim_enc_rx_b_hdr.instance_number = to_fiu_tlp.instance_number;
    assign fim_enc_rx_b_data.clk = to_fiu_tlp.clk;
    assign fim_enc_rx_b_data.reset_n = to_fiu_tlp.reset_n;
    assign fim_enc_rx_b_data.instance_number = to_fiu_tlp.instance_number;

    // afu_rx_b_st will be used only when read completions are on RX-A.
    // In this case, at most write commits are on RX-B and there is no
    // data.
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(t_ofs_fim_axis_pcie_tuser)
        )
      afu_rx_b_st();

    generate
        if (CPL_CHAN == PCIE_CHAN_A)
        begin : b_skid
            // Read completions are on RX-A. This means at most write
            // completions are on RX-B, which do not need split streams.
            // Use simple logic for RX-B with just a skid buffer for
            // timing.
            ofs_plat_axi_stream_if_skid_source_clk entry_b_skid
               (
                .stream_source(fim_rx_b_st),
                .stream_sink(afu_rx_b_st)
                );

            // Tie off the unused fim_enc_rx_b streams.
            assign fim_enc_rx_b_hdr.tvalid = 1'b0;
            assign fim_enc_rx_b_hdr.tready = 1'b0;
            assign fim_enc_rx_b_data.tvalid = 1'b0;
            assign fim_enc_rx_b_data.tready = 1'b0;
        end
        else
        begin : b_align
            // Read completions are on RX-B. Split header and data
            // streams are required.
            ofs_plat_host_chan_@group@_align_rx_tlps
              align_rx_b
               (
                .stream_source(fim_rx_b_st),
                .hdr_stream_sink(fim_enc_rx_b_hdr),
                .data_stream_sink(fim_enc_rx_b_data)
                );

            // Tie off the unused afu_rx_b_st.
            assign afu_rx_b_st.tvalid = 1'b0;
        end
    endgenerate


    //
    // Track EOP/SOP of the incoming fim_enc_rx streams in order to handle
    // hdr and data messages in order.
    //
    logic fim_enc_rx_a_sop;
    always_ff @(posedge clk)
    begin
        if (fim_enc_rx_a_data.tready && fim_enc_rx_a_data.tvalid)
            fim_enc_rx_a_sop <= fim_enc_rx_a_data.t.last;

        if (!reset_n)
            fim_enc_rx_a_sop <= 1'b1;
    end

    logic fim_enc_rx_b_sop;
    always_ff @(posedge clk)
    begin
        if (fim_enc_rx_b_data.tready && fim_enc_rx_b_data.tvalid)
            fim_enc_rx_b_sop <= fim_enc_rx_b_data.t.last;

        if (!reset_n)
            fim_enc_rx_b_sop <= 1'b1;
    end


    // SOP of the MMIO and read completion streams to the PIM are tracked in
    // order to route pure data beats.
    logic mmio_req_sop;
    always_ff @(posedge clk)
    begin
        if (mmio_req_to_pim.tready && mmio_req_to_pim.tvalid)
            mmio_req_sop <= mmio_req_to_pim.t.user[0].eop;

        if (!reset_n)
            mmio_req_sop <= 1'b1;
    end

    logic rd_cpl_sop;
    always_ff @(posedge clk)
    begin
        if (rd_cpl_to_pim.tready && rd_cpl_to_pim.tvalid)
            rd_cpl_sop <= rd_cpl_to_pim.t.user[0].eop;

        if (!reset_n)
            rd_cpl_sop <= 1'b1;
    end

    //
    // Ready for next incoming message? If SOP, then both header and data must be
    // valid. (In order to simplify the control logic here, there is always a data
    // message, even if the header indicates no payload.)
    //
    wire fim_enc_rx_a_all_tready =
             mmio_req_to_pim.tready &&
             (CPL_CHAN == PCIE_CHAN_A ? rd_cpl_to_pim.tready : 1'b1) &&
             (WR_COMMIT_CHAN == PCIE_CHAN_A ? wr_cpl_to_pim.tready : 1'b1) &&
             (WR_COMMIT_CHAN == PCIE_CHAN_A ? irq_cpl_to_pim.tready : 1'b1);

    assign fim_enc_rx_a_hdr.tready =
             fim_enc_rx_a_sop && fim_enc_rx_a_data.tvalid && fim_enc_rx_a_all_tready;
    assign fim_enc_rx_a_data.tready =
             fim_enc_rx_a_all_tready &&
             (!fim_enc_rx_a_sop || fim_enc_rx_a_hdr.tvalid);

    // Format type of header (same position in any message)
    pcie_ss_hdr_pkg::ReqHdr_FmtType_e rx_a_fmttype;
    assign rx_a_fmttype = fim_enc_rx_a_hdr.t.data.fmt_type;


    //
    // MMIO requests (always on RX-A)
    //
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t rx_mem_req_pu_hdr;
    assign rx_mem_req_pu_hdr = fim_enc_rx_a_hdr.t.data;

    assign mmio_req_to_pim.tvalid =
             fim_enc_rx_a_data.tvalid && fim_enc_rx_a_all_tready &&
             (!mmio_req_sop ||
              (fim_enc_rx_a_sop && fim_enc_rx_a_hdr.tvalid && pcie_ss_hdr_pkg::func_is_mem_req(rx_a_fmttype)));

    // MMIO request header
    always_comb
    begin
        mmio_req_to_pim.t.user = '0;

        mmio_req_to_pim.t.user[0].sop = fim_enc_rx_a_sop;
        mmio_req_to_pim.t.user[0].eop = fim_enc_rx_a_data.t.last;
        mmio_req_to_pim.t.last = fim_enc_rx_a_data.t.last;

        if (fim_enc_rx_a_sop)
        begin
            mmio_req_to_pim.t.user[0].hdr.fmttype = rx_a_fmttype;
            mmio_req_to_pim.t.user[0].hdr.length = rx_mem_req_pu_hdr.length;
            mmio_req_to_pim.t.user[0].hdr.u.mem_req.requester_id = rx_mem_req_pu_hdr.req_id;
            mmio_req_to_pim.t.user[0].hdr.u.mem_req.tc = rx_mem_req_pu_hdr.TC;
            mmio_req_to_pim.t.user[0].hdr.u.mem_req.tag =
                { rx_mem_req_pu_hdr.tag_h, rx_mem_req_pu_hdr.tag_m, rx_mem_req_pu_hdr.tag_l };
            mmio_req_to_pim.t.user[0].hdr.u.mem_req.last_be = rx_mem_req_pu_hdr.last_dw_be;
            mmio_req_to_pim.t.user[0].hdr.u.mem_req.first_be = rx_mem_req_pu_hdr.first_dw_be;
            mmio_req_to_pim.t.user[0].hdr.u.mem_req.addr =
                pcie_ss_hdr_pkg::func_is_addr64(rx_a_fmttype) ?
                    { rx_mem_req_pu_hdr.host_addr_h, rx_mem_req_pu_hdr.host_addr_l, 2'b0 } :
                    { '0, rx_mem_req_pu_hdr.host_addr_h };
        end
    end

    // MMIO request payload
    always_comb
    begin
        mmio_req_to_pim.t.data[0] = fim_enc_rx_a_data.t.data.payload;
        mmio_req_to_pim.t.keep = ~'0;
    end


    // Read completion header, cast to a both DM and PU
    pcie_ss_hdr_pkg::PCIe_CplHdr_t rd_cpl_dm_hdr;
    pcie_ss_hdr_pkg::PCIe_PUCplHdr_t rd_cpl_pu_hdr;
    logic rd_cpl_dm_mode;
    // Next completion payload
    t_ofs_fim_axis_pcie_tdata rd_cpl_data;
    logic rd_cpl_eop;

    // Get completion header and data from the proper channel. The condition
    // is static.
    generate
        if (CPL_CHAN == PCIE_CHAN_A)
        begin : rd_cpl_a
            // Read completions are on RX-A.
            assign rd_cpl_dm_hdr = fim_enc_rx_a_hdr.t.data;
            assign rd_cpl_pu_hdr = fim_enc_rx_a_hdr.t.data;
            assign rd_cpl_dm_mode = fim_enc_rx_a_hdr.t.user;
            assign rd_cpl_data = fim_enc_rx_a_data.t.data.payload;
            assign rd_cpl_eop = fim_enc_rx_a_data.t.last;

            // There are other message classes also on RX-A. Forward only
            // completions with data to rd_cpl_to_pim.
            assign rd_cpl_to_pim.tvalid =
                     fim_enc_rx_a_data.tvalid && fim_enc_rx_a_all_tready &&
                     (!rd_cpl_sop ||
                      (fim_enc_rx_a_sop && fim_enc_rx_a_hdr.tvalid &&
                       pcie_ss_hdr_pkg::func_is_completion(rx_a_fmttype) &&
                       pcie_ss_hdr_pkg::func_has_data(rx_a_fmttype)));

        end
        else
        begin : rd_cpl_b
            // Read completions are the only traffic on RX-B.
            assign rd_cpl_dm_hdr = fim_enc_rx_b_hdr.t.data;
            assign rd_cpl_pu_hdr = fim_enc_rx_b_hdr.t.data;
            assign rd_cpl_dm_mode = fim_enc_rx_b_hdr.t.user;
            assign rd_cpl_data = fim_enc_rx_b_data.t.data.payload;
            assign rd_cpl_eop = fim_enc_rx_b_data.t.last;

            assign fim_enc_rx_b_hdr.tready =
                     fim_enc_rx_b_sop && fim_enc_rx_b_data.tvalid && rd_cpl_to_pim.tready;
            assign fim_enc_rx_b_data.tready =
                     rd_cpl_to_pim.tready &&
                     (!fim_enc_rx_b_sop || fim_enc_rx_b_hdr.tvalid);

            assign rd_cpl_to_pim.tvalid =
                     fim_enc_rx_b_data.tvalid &&
                     (!rd_cpl_sop || (fim_enc_rx_b_sop && fim_enc_rx_b_hdr.tvalid));
        end
    endgenerate

    // Read completion headers: FIM to PIM mapping
    always_comb
    begin
        rd_cpl_to_pim.t.user = '0;

        rd_cpl_to_pim.t.user[0].sop = rd_cpl_sop;
        rd_cpl_to_pim.t.user[0].eop = rd_cpl_eop;
        rd_cpl_to_pim.t.last = rd_cpl_eop;

        if (rd_cpl_sop)
        begin
            if (rd_cpl_dm_mode)
            begin
                // DM encoded
                rd_cpl_to_pim.t.user[0].hdr.fmttype = rd_cpl_dm_hdr.fmt_type;
                rd_cpl_to_pim.t.user[0].hdr.length = { '0, rd_cpl_dm_hdr.length_h, rd_cpl_dm_hdr.length_m };
                rd_cpl_to_pim.t.user[0].hdr.u.mem_req.tc = rd_cpl_dm_hdr.TC;
                rd_cpl_to_pim.t.user[0].hdr.u.cpl.tag = rd_cpl_dm_hdr.tag;
                { rd_cpl_to_pim.t.user[0].hdr.u.cpl.lower_addr_h, rd_cpl_to_pim.t.user[0].hdr.u.cpl.lower_addr } =
                    { '0, rd_cpl_dm_hdr.low_addr_h, rd_cpl_dm_hdr.low_addr_l };
                rd_cpl_to_pim.t.user[0].hdr.u.cpl.fc = rd_cpl_dm_hdr.FC;
                rd_cpl_to_pim.t.user[0].hdr.u.cpl.dm_encoded = 1'b1;
            end
            else
            begin
                // PU encoded
                rd_cpl_to_pim.t.user[0].hdr.fmttype = rd_cpl_pu_hdr.fmt_type;
                rd_cpl_to_pim.t.user[0].hdr.length = rd_cpl_pu_hdr.length;
                rd_cpl_to_pim.t.user[0].hdr.u.cpl.requester_id = rd_cpl_pu_hdr.req_id;
                rd_cpl_to_pim.t.user[0].hdr.u.mem_req.tc = rd_cpl_pu_hdr.TC;
                rd_cpl_to_pim.t.user[0].hdr.u.cpl.tag =
                    { rd_cpl_pu_hdr.tag_h, rd_cpl_pu_hdr.tag_m, rd_cpl_pu_hdr.tag_l };
                rd_cpl_to_pim.t.user[0].hdr.u.cpl.completer_id = rd_cpl_pu_hdr.comp_id;
                rd_cpl_to_pim.t.user[0].hdr.u.cpl.byte_count = rd_cpl_pu_hdr.byte_count;
                rd_cpl_to_pim.t.user[0].hdr.u.cpl.lower_addr = rd_cpl_pu_hdr.low_addr;
                // The PIM only generates dword aligned reads, so the check for
                // the last packet is easy.
                rd_cpl_to_pim.t.user[0].hdr.u.cpl.fc = (rd_cpl_pu_hdr.byte_count[11:2] == rd_cpl_pu_hdr.length);
            end
        end
    end

    // Read completion data
    always_comb
    begin
        rd_cpl_to_pim.t.data[0] = rd_cpl_data;
        rd_cpl_to_pim.t.keep = ~'0;

        // The PIM will only generate a short read for atomic requests. The
        // response will arrive in the low bits of the payload, but the PIM's
        // memory mapped interfaces expect the data shifted to the position
        // in the data bus corresponding to the request address. We can simply
        // replicate the data unconditionally.
        if (rd_cpl_sop && !rd_cpl_dm_mode)
        begin
            if (rd_cpl_pu_hdr.length == 1)
            begin
                for (int i = 1; i < $bits(rd_cpl_to_pim.t.data[0]) / 32; i = i + 1)
                begin
                    rd_cpl_to_pim.t.data[0][i*32 +: 32] = rd_cpl_data[31:0];
                end
            end
            else if (rd_cpl_pu_hdr.length == 2)
            begin
                for (int i = 1; i < $bits(rd_cpl_to_pim.t.data[0]) / 64; i = i + 1)
                begin
                    rd_cpl_to_pim.t.data[0][i*64 +: 64] = rd_cpl_data[63:0];
                end
            end
        end
    end


    // synthesis translate_off

    //
    // Check a few properties of the read completion stream.
    //

    wire [13:0] rd_cpl_dm_hdr_length =
        { rd_cpl_dm_hdr.length_h, rd_cpl_dm_hdr.length_m, rd_cpl_dm_hdr.length_l };

    // Unexpected RX traffic?
    wire rx_to_pim_invalid_cmd =
           rd_cpl_sop &&
           (!pcie_ss_hdr_pkg::func_is_completion(rd_cpl_dm_hdr.fmt_type) ||
            !pcie_ss_hdr_pkg::func_has_data(rd_cpl_dm_hdr.fmt_type));

    always_ff @(posedge rd_cpl_to_pim.clk)
    begin
        if (rd_cpl_to_pim.reset_n && rd_cpl_to_pim.tvalid && rd_cpl_to_pim.tready)
        begin
            if (rx_to_pim_invalid_cmd)
                $fatal(2, "Unexpected TLP RX header to PIM!");

            if (rd_cpl_sop && rd_cpl_dm_mode &&
                pcie_ss_hdr_pkg::func_is_completion(rd_cpl_dm_hdr.fmt_type) &&
                (rd_cpl_dm_hdr_length <= 8))
            begin
                $fatal(2, "Data Mover encoded TLP RX headers for short reads not supported by PIM!");
            end
        end
    end
    // synthesis translate_on


    //
    // Forward write commits generated by the FIM back to the AFU. Write completions
    // indicate the serialized commit point of writes on TX A relative to reads on TX B.
    //

    // DM and PU fields needed in the write completion are in the same place. Either
    // header type will work.
    pcie_ss_hdr_pkg::PCIe_PUCplHdr_t rx_wr_cpl_pu_hdr;
    generate
        if (WR_COMMIT_CHAN == PCIE_CHAN_A)
        begin : wr_cpl_a
            // Write commits on RX-A
            assign afu_rx_b_st.tready = 1'b1;

            assign rx_wr_cpl_pu_hdr = fim_enc_rx_a_hdr.t.data;
            assign wr_cpl_to_pim.tvalid = fim_enc_rx_a_data.tvalid &&
                                          fim_enc_rx_a_all_tready &&
                                          fim_enc_rx_a_sop &&
                                          fim_enc_rx_a_hdr.tvalid &&
                                          pcie_ss_hdr_pkg::func_is_completion(rx_a_fmttype) &&
                                          !pcie_ss_hdr_pkg::func_has_data(rx_a_fmttype) &&
                                          // TC[0] is 0 for write responses, 1 for interrupts
                                          !rx_wr_cpl_pu_hdr.TC[0];
        end
        else
        begin : wr_cpl_b
            // Write commits on RX-B
            assign afu_rx_b_st.tready = wr_cpl_to_pim.tready && irq_cpl_to_pim.tready;

            assign rx_wr_cpl_pu_hdr = afu_rx_b_st.t.data;
            assign wr_cpl_to_pim.tvalid = afu_rx_b_st.tvalid &&
                                          // TC[0] is 0 for write responses, 1 for interrupts
                                          !rx_wr_cpl_pu_hdr.TC[0];
        end
    endgenerate

    always_comb
    begin
        wr_cpl_to_pim.t = '0;
        wr_cpl_to_pim.t.data.tag =
            ofs_plat_host_chan_@group@_pcie_tlp_pkg::t_dma_afu_tag'(rx_wr_cpl_pu_hdr.metadata_l);
        wr_cpl_to_pim.t.data.line_count =
            ofs_plat_host_chan_@group@_pcie_tlp_pkg::dwordLenToLineCount(rx_wr_cpl_pu_hdr.length);
        wr_cpl_to_pim.t.last = 1'b1;
    end


    // Local commits for IRQ requests. This isn't the IRQ response from the host.
    // It is just like a write commit, indicating that the request is now ordered
    // relative to all other requests.
    pcie_ss_hdr_pkg::PCIe_CplHdr_t rx_intr_cpl_dm_hdr;
    generate
        if (WR_COMMIT_CHAN == PCIE_CHAN_A)
        begin : irq_cpl_a
            // IRQ local commits on RX-A
            assign rx_intr_cpl_dm_hdr = fim_enc_rx_a_hdr.t.data;
            assign irq_cpl_to_pim.tvalid = fim_enc_rx_a_data.tvalid &&
                                           fim_enc_rx_a_all_tready &&
                                           fim_enc_rx_a_sop &&
                                           fim_enc_rx_a_hdr.tvalid &&
                                           pcie_ss_hdr_pkg::func_is_completion(rx_a_fmttype) &&
                                           !pcie_ss_hdr_pkg::func_has_data(rx_a_fmttype) &&
                                           // TC[0] is 1 for interrupts
                                           rx_intr_cpl_dm_hdr.TC[0];
        end
        else
        begin : irq_cpl_b
            // IRQ local commits on RX-B
            assign rx_intr_cpl_dm_hdr = afu_rx_b_st.t.data;
            assign irq_cpl_to_pim.tvalid = afu_rx_b_st.tvalid &&
                                           // TC[0] is 1 for interrupts
                                           rx_intr_cpl_dm_hdr.TC[0];
        end
    endgenerate

    always_comb
    begin
        irq_cpl_to_pim.t = '0;
        irq_cpl_to_pim.t.data.requester_id = { to_fiu_tlp.vf_num, to_fiu_tlp.vf_active, to_fiu_tlp.pf_num };
        irq_cpl_to_pim.t.data.irq_id = rx_intr_cpl_dm_hdr.metadata_l[$bits(t_ofs_plat_pcie_hdr_irq_id)-1 : 0];
    end

endmodule // ofs_plat_host_chan_@group@_fim_gasket
