// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// OFS EA-specific mapping of the EA FIM's TLP streams to the PIM's internal
// PCIe TLP representation.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_@group@_fim_gasket
   (
    // Interface to FIM
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu_tlp,
    // Allow Data Mover encoding? (Not used in EA)
    input  logic allow_dm_enc,

    // PIM encoding
    ofs_plat_axi_stream_if.to_source tx_from_pim,
    // PIM encoding (FPGA->host, optional separate MRd stream). Not used in
    // EA -- just set tready.
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

    import ofs_plat_pcie_tlp_@group@_hdr_pkg::*;

    logic clk;
    assign clk = to_fiu_tlp.clk;
    logic reset_n;
    assign reset_n = to_fiu_tlp.reset_n;


    //
    // Build a vector of FIM encoded packets that equals the width of the PIM's
    // PCIe encoding.
    //
    localparam NUM_FIM_MAP_CH = ofs_plat_host_chan_@group@_pcie_tlp_pkg::PAYLOAD_LINE_SIZE /
                                ofs_fim_if_pkg::AXIS_PCIE_PW;
    typedef ofs_fim_if_pkg::t_axis_pcie_tdata [NUM_FIM_MAP_CH-1 : 0] t_fim_map_pcie_tdata_vec;
    typedef ofs_fim_if_pkg::t_axis_pcie_tx_tuser [NUM_FIM_MAP_CH-1 : 0] t_fim_map_pcie_tx_tuser_vec;
    typedef ofs_fim_if_pkg::t_axis_pcie_rx_tuser [NUM_FIM_MAP_CH-1 : 0] t_fim_map_pcie_rx_tuser_vec;


    // ====================================================================
    //
    //  AFU -> FIM TX stream translation from PIM to FIM encoding
    //
    // ====================================================================

    // Not used. Reads are sent on EA in the tx_from_pim stream.
    assign tx_mrd_from_pim.tready = 1'b1;

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_fim_map_pcie_tdata_vec),
        .TUSER_TYPE(t_fim_map_pcie_tx_tuser_vec)
        )
      fim_enc_tx();

    assign fim_enc_tx.clk = to_fiu_tlp.clk;
    assign fim_enc_tx.reset_n = to_fiu_tlp.reset_n;
    assign fim_enc_tx.instance_number = to_fiu_tlp.instance_number;

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

    ofs_plat_host_chan_align_axis_tx_tlps
      #(
        .NUM_SOURCE_TLP_CH(NUM_FIM_MAP_CH),
        .NUM_SINK_TLP_CH(ofs_fim_if_pkg::FIM_PCIE_TLP_CH),
        .TDATA_TYPE(ofs_fim_if_pkg::t_axis_pcie_tdata),
        .TUSER_TYPE(ofs_fim_if_pkg::t_axis_pcie_tx_tuser)
        )
      align_tx
       (
        .stream_source(fim_enc_tx),
        .stream_sink(to_fiu_tlp.afu_tx_st)
        );


    assign tx_from_pim.tready = fim_enc_tx.tready && wr_cpl_to_pim.tready;
    assign fim_enc_tx.tvalid = tx_from_pim.tvalid && tx_from_pim.tready;

    // Construct headers for all message types. Only one will actually be
    // used, depending on fmttype.
    ofs_fim_pcie_hdr_def::t_tlp_mem_req_hdr tx_mem_req_hdr;
    ofs_fim_pcie_hdr_def::t_tlp_cpl_hdr tx_cpl_hdr;
    ofs_fim_if_pkg::t_axis_irq_tdata tx_irq_hdr;

    t_ofs_plat_pcie_hdr_fmttype tx_fmttype;
    assign tx_fmttype = tx_from_pim.t.user[0].hdr.fmttype;

    // Memory request
    always_comb
    begin
        tx_mem_req_hdr = '0;
        tx_mem_req_hdr.dw0.fmttype = tx_fmttype;
        tx_mem_req_hdr.dw0.length = tx_from_pim.t.user[0].hdr.length;
        tx_mem_req_hdr.requester_id = tx_from_pim.t.user[0].hdr.u.mem_req.requester_id;
        tx_mem_req_hdr.tag = tx_from_pim.t.user[0].hdr.u.mem_req.tag;
        tx_mem_req_hdr.last_be = tx_from_pim.t.user[0].hdr.u.mem_req.last_be;
        tx_mem_req_hdr.first_be = tx_from_pim.t.user[0].hdr.u.mem_req.first_be;
        if (ofs_plat_pcie_func_is_addr64(tx_fmttype))
        begin
            tx_mem_req_hdr.addr = tx_from_pim.t.user[0].hdr.u.mem_req.addr[63:32];
            tx_mem_req_hdr.lsb_addr = tx_from_pim.t.user[0].hdr.u.mem_req.addr[31:0];
        end
        else
        begin
            tx_mem_req_hdr.addr = tx_from_pim.t.user[0].hdr.u.mem_req.addr[31:0];
        end
    end

    // Completion
    always_comb
    begin
        tx_cpl_hdr = '0;
        tx_cpl_hdr.dw0.fmttype = tx_fmttype;
        tx_cpl_hdr.dw0.length = tx_from_pim.t.user[0].hdr.length;
        tx_cpl_hdr.requester_id = tx_from_pim.t.user[0].hdr.u.cpl.requester_id;
        tx_cpl_hdr.tag = tx_from_pim.t.user[0].hdr.u.cpl.tag;
        tx_cpl_hdr.completer_id = tx_from_pim.t.user[0].hdr.u.cpl.completer_id;
        tx_cpl_hdr.byte_count = tx_from_pim.t.user[0].hdr.u.cpl.byte_count;
        tx_cpl_hdr.lower_addr = tx_from_pim.t.user[0].hdr.u.cpl.lower_addr;
    end

    // Interrupt request
    always_comb
    begin
        tx_irq_hdr = '0;
        tx_irq_hdr.rid = tx_from_pim.t.user[0].hdr.u.irq.requester_id;
        tx_irq_hdr.irq_id = tx_from_pim.t.user[0].hdr.u.irq.irq_id;
    end

    logic tx_from_pim_invalid_cmd;

    // Map TX header and data
    always_comb
    begin
        tx_from_pim_invalid_cmd = 1'b0;
        fim_enc_tx.t = '0;

        fim_enc_tx.t.data[0].valid = tx_from_pim.tvalid;
        // The PIM normally generates data aligned to the full width of fim_enc_tx.
        // t.data[1] is valid for multi-cycle data (sop is false) since PIM-generated
        // multi-cycle data is always the width of this bus. t.data[1] is also valid
        // in the sop cycle when the data doesn't fit in t.data[0].
        fim_enc_tx.t.data[1].valid =
            tx_from_pim.tvalid &&
            (!tx_from_pim.t.user[0].sop ||
             (ofs_plat_pcie_func_has_data(tx_fmttype) &&
              (tx_from_pim.t.user[0].hdr.length > (ofs_fim_if_pkg::AXIS_PCIE_PW / 32))));

        fim_enc_tx.t.data[0].sop = tx_from_pim.t.user[0].sop;

        fim_enc_tx.t.data[0].eop =
            tx_from_pim.t.user[0].eop &&
            tx_from_pim.t.user[0].sop &&
            (!ofs_plat_pcie_func_has_data(tx_fmttype) ||
             (tx_from_pim.t.user[0].hdr.length <= (ofs_fim_if_pkg::AXIS_PCIE_PW / 32)));

        // t.data[1].eop calculation is similar to t.data[1].valid above.
        fim_enc_tx.t.data[1].eop =
            tx_from_pim.t.user[0].eop &&
            (!tx_from_pim.t.user[0].sop ||
             (ofs_plat_pcie_func_has_data(tx_fmttype) &&
              (tx_from_pim.t.user[0].hdr.length > (ofs_fim_if_pkg::AXIS_PCIE_PW / 32))));

        // Map PIM-formatted data to FIM-formatted data
        for (int i = 0; i < NUM_FIM_MAP_CH; i = i + 1)
        begin
            fim_enc_tx.t.data[i].payload =
                tx_from_pim.t.data[0][i * ofs_fim_if_pkg::AXIS_PCIE_PW +: ofs_fim_if_pkg::AXIS_PCIE_PW];
        end

        if (tx_from_pim.t.user[0].hdr.is_irq)
        begin
            fim_enc_tx.t.data[0].hdr = tx_irq_hdr;
            fim_enc_tx.t.user[0].afu_irq = 1'b1;
        end
        else if (ofs_plat_pcie_func_is_mem_req(tx_fmttype))
        begin
            fim_enc_tx.t.data[0].hdr = tx_mem_req_hdr;
        end
        else if (ofs_plat_pcie_func_is_completion(tx_fmttype))
        begin
            fim_enc_tx.t.data[0].hdr = tx_cpl_hdr;
        end
        else
        begin
            tx_from_pim_invalid_cmd = tx_from_pim.tvalid && tx_from_pim.t.user[0].sop;
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
    //  FIM -> AFU RX stream translation from FIM to PIM encoding
    //
    // ====================================================================

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_fim_map_pcie_tdata_vec),
        .TUSER_TYPE(t_fim_map_pcie_rx_tuser_vec)
        )
      fim_enc_rx();

    assign fim_enc_rx.clk = to_fiu_tlp.clk;
    assign fim_enc_rx.reset_n = to_fiu_tlp.reset_n;
    assign fim_enc_rx.instance_number = to_fiu_tlp.instance_number;

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

    ofs_plat_host_chan_align_axis_rx_tlps
      #(
        .NUM_SOURCE_TLP_CH(ofs_fim_if_pkg::FIM_PCIE_TLP_CH),
        .NUM_SINK_TLP_CH(NUM_FIM_MAP_CH),
        .TDATA_TYPE(ofs_fim_if_pkg::t_axis_pcie_tdata),
        .TUSER_TYPE(ofs_fim_if_pkg::t_axis_pcie_rx_tuser)
        )
      align_rx
       (
        .stream_source(to_fiu_tlp.afu_rx_st),
        .stream_sink(fim_enc_rx)
        );

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

    // FIM to PIM encoding translation. At this point, all SOP entries are
    // guaranteed to be in slot 0.
    assign fim_enc_rx.tready = mmio_req_to_pim.tready && rd_cpl_to_pim.tready;

    // Map multi-channel FIM to single-channel PIM data encoding
    always_comb
    begin
        for (int i = 0; i < NUM_FIM_MAP_CH; i = i + 1)
        begin
            mmio_req_to_pim.t.data[0][i * ofs_fim_if_pkg::AXIS_PCIE_PW +: ofs_fim_if_pkg::AXIS_PCIE_PW] =
                fim_enc_rx.t.data[i].payload;

            rd_cpl_to_pim.t.data[0][i * ofs_fim_if_pkg::AXIS_PCIE_PW +: ofs_fim_if_pkg::AXIS_PCIE_PW] =
                fim_enc_rx.t.data[i].payload;
        end
    end

    // Map the incoming FIM RX header to message-specific types. The FIM doesn't
    // have a union type. The fmttype will be used to figure out which of these
    // is relevant for a given message.
    ofs_fim_pcie_hdr_def::t_tlp_mem_req_hdr rx_mem_req_hdr;
    assign rx_mem_req_hdr = fim_enc_rx.t.data[0].hdr;
    ofs_fim_pcie_hdr_def::t_tlp_cpl_hdr rx_cpl_hdr;
    assign rx_cpl_hdr = fim_enc_rx.t.data[0].hdr;

    ofs_fim_pcie_hdr_def::t_tlp_hdr_dw0 rx_dw0;
    assign rx_dw0 = rx_mem_req_hdr.dw0;
    t_ofs_plat_pcie_hdr_fmttype rx_fmttype;
    assign rx_fmttype = t_ofs_plat_pcie_hdr_fmttype'(rx_dw0.fmttype);

    // MMIO request?
    assign mmio_req_to_pim.tvalid =
             fim_enc_rx.tvalid && rd_cpl_to_pim.tready &&
             (!mmio_req_sop ||
              (fim_enc_rx.t.data[0].sop && ofs_plat_pcie_func_is_mem_req(rx_fmttype)));

    // Read completion?
    assign rd_cpl_to_pim.tvalid =
             fim_enc_rx.tvalid && mmio_req_to_pim.tready &&
             (!rd_cpl_sop ||
              (fim_enc_rx.t.data[0].sop && ofs_plat_pcie_func_is_completion(rx_fmttype)));

    always_comb
    begin
        mmio_req_to_pim.t.keep = ~'0;
        mmio_req_to_pim.t.user = '0;

        // SOP guaranteed in FIM slot 0 after alignment above
        mmio_req_to_pim.t.user[0].sop = fim_enc_rx.t.data[0].sop;

        // Merge EOP into a single bit for PIM encoding
        mmio_req_to_pim.t.user[0].eop = fim_enc_rx.t.data[0].eop;
        for (int i = 1; i < NUM_FIM_MAP_CH; i = i + 1)
        begin
            mmio_req_to_pim.t.user[0].eop = mmio_req_to_pim.t.user[0].eop || fim_enc_rx.t.data[i].eop;
        end

        mmio_req_to_pim.t.user[0].hdr.fmttype = rx_fmttype;
        mmio_req_to_pim.t.user[0].hdr.length = rx_dw0.length;
        mmio_req_to_pim.t.user[0].hdr.u.mem_req.requester_id = rx_mem_req_hdr.requester_id;
        mmio_req_to_pim.t.user[0].hdr.u.mem_req.tag = rx_mem_req_hdr.tag;
        mmio_req_to_pim.t.user[0].hdr.u.mem_req.last_be = rx_mem_req_hdr.last_be;
        mmio_req_to_pim.t.user[0].hdr.u.mem_req.first_be = rx_mem_req_hdr.first_be;
        mmio_req_to_pim.t.user[0].hdr.u.mem_req.addr =
            ofs_plat_pcie_func_is_addr64(rx_fmttype) ?
               { rx_mem_req_hdr.addr, rx_mem_req_hdr.lsb_addr } :
               { '0, rx_mem_req_hdr.addr };
    end

    always_comb
    begin
        rd_cpl_to_pim.t.keep = ~'0;
        rd_cpl_to_pim.t.user = '0;

        // SOP guaranteed in FIM slot 0 after alignment above
        rd_cpl_to_pim.t.user[0].sop = fim_enc_rx.t.data[0].sop;

        // Merge EOP into a single bit for PIM encoding
        rd_cpl_to_pim.t.user[0].eop = fim_enc_rx.t.data[0].eop;
        for (int i = 1; i < NUM_FIM_MAP_CH; i = i + 1)
        begin
            rd_cpl_to_pim.t.user[0].eop = rd_cpl_to_pim.t.user[0].eop || fim_enc_rx.t.data[i].eop;
        end

        rd_cpl_to_pim.t.user[0].hdr.fmttype = rx_fmttype;
        rd_cpl_to_pim.t.user[0].hdr.length = rx_dw0.length;
        rd_cpl_to_pim.t.user[0].hdr.u.cpl.requester_id = rx_cpl_hdr.requester_id;
        rd_cpl_to_pim.t.user[0].hdr.u.cpl.tag = rx_cpl_hdr.tag;
        rd_cpl_to_pim.t.user[0].hdr.u.cpl.completer_id = rx_cpl_hdr.completer_id;
        rd_cpl_to_pim.t.user[0].hdr.u.cpl.byte_count = rx_cpl_hdr.byte_count;
        rd_cpl_to_pim.t.user[0].hdr.u.cpl.lower_addr = rx_cpl_hdr.lower_addr;
        // The PIM only generates dword aligned reads, so the check for
        // the last packet is easy.
        rd_cpl_to_pim.t.user[0].hdr.u.cpl.fc = (rx_cpl_hdr.byte_count[11:2] == rx_dw0.length);
    end

    // synthesis translate_off
    // Unexpected RX traffic?
    wire rx_to_pim_invalid_cmd = fim_enc_rx.t.data[0].sop &&
                                 !ofs_plat_pcie_func_is_completion(rx_fmttype);

    always_ff @(posedge rd_cpl_to_pim.clk)
    begin
        if (rd_cpl_to_pim.reset_n && rd_cpl_to_pim.tvalid && rd_cpl_to_pim.tready)
        begin
            if (rx_to_pim_invalid_cmd)
                $fatal(2, "Unexpected TLP RX header to PIM!");
        end
    end
    // synthesis translate_on

    //
    // Write completions. The OFS EA FIM has only one TX stream, so writes are
    // committed to TLP order already. Generate the write completion here as
    // writes are passed to the FIM.
    //
    // Completion is sent on the EOP cycle.
    //
    logic wr_cpl_pending;
    ofs_plat_host_chan_@group@_gen_tlps_pkg::t_gen_tx_wr_cpl wr_cpl_q;

    // Short payload, fitting in a single beat?
    logic wr_cpl_from_sop_eop;
    assign wr_cpl_from_sop_eop = tx_from_pim.t.user[0].sop && tx_from_pim.t.user[0].eop &&
                                 ofs_plat_pcie_func_is_mwr_req(tx_fmttype);

    assign wr_cpl_to_pim.tvalid = tx_from_pim.tvalid && tx_from_pim.tready &&
                                  ((wr_cpl_pending && tx_from_pim.t.user[0].eop) ||
                                   wr_cpl_from_sop_eop);

    always_comb
    begin
        wr_cpl_to_pim.t = '0;
        if (wr_cpl_from_sop_eop)
        begin
            wr_cpl_to_pim.t.data.tag = tx_from_pim.t.user[0].afu_tag;
            wr_cpl_to_pim.t.data.line_count =
                ofs_plat_host_chan_@group@_pcie_tlp_pkg::dwordLenToLineCount(tx_from_pim.t.user[0].hdr.length);
        end
        else
        begin
            wr_cpl_to_pim.t.data = wr_cpl_q;
        end

        wr_cpl_to_pim.t.last = 1'b1;
    end

    // Record write completion, which will be sent on EOP
    always_ff @(posedge clk)
    begin
        if (wr_cpl_to_pim.tvalid)
        begin
            wr_cpl_pending <= 1'b0;
        end

        // New write header and it isn't also EOP?
        if (tx_from_pim.tvalid && tx_from_pim.tready &&
            tx_from_pim.t.user[0].sop && !tx_from_pim.t.user[0].eop &&
            ofs_plat_pcie_func_is_mwr_req(tx_fmttype))
        begin
            wr_cpl_pending <= 1'b1;
            wr_cpl_q.tag <= tx_from_pim.t.user[0].afu_tag;
            wr_cpl_q.line_count <=
                ofs_plat_host_chan_@group@_pcie_tlp_pkg::dwordLenToLineCount(tx_from_pim.t.user[0].hdr.length);
        end

        if (!reset_n)
        begin
            wr_cpl_pending <= 1'b0;
        end
    end


    //
    // IRQ responses are out of band from the FIM
    //
    assign to_fiu_tlp.afu_irq_rx_st.tready = irq_cpl_to_pim.tready;
    assign irq_cpl_to_pim.tvalid = to_fiu_tlp.afu_irq_rx_st.tvalid;

    always_comb
    begin
        irq_cpl_to_pim.t = '0;
        irq_cpl_to_pim.t.data.requester_id = to_fiu_tlp.afu_irq_rx_st.t.data.rid;
        irq_cpl_to_pim.t.data.irq_id = to_fiu_tlp.afu_irq_rx_st.t.data.irq_id;
    end

endmodule // ofs_plat_host_chan_@group@_fim_gasket
