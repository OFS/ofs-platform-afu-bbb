//
// Copyright (c) 2021, Intel Corporation
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
// OFS EA-specific mapping of the EA FIM's TLP streams to the PIM's internal
// PCIe TLP representation.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_@group@_fim_gasket
   (
    // Interface to FIM
    ofs_plat_host_chan_@group@_axis_pcie_tlp_if to_fiu_tlp,

    // PIM encoding (FPGA->host)
    ofs_plat_axi_stream_if.to_source tx_from_pim,
    // PIM encoding (FPGA->host, optional separate MRd stream)
    ofs_plat_axi_stream_if.to_source tx_mrd_from_pim,

    // PIM encoding
    ofs_plat_axi_stream_if.to_sink rx_to_pim,

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


    // ====================================================================
    //
    //  AFU -> FIM TX stream translation from PIM to FIM encoding
    //
    // ====================================================================

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t),
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
        .stream_sink(to_fiu_tlp.afu_tx_a_st),
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
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t tx_mem_req_hdr;
    pcie_ss_hdr_pkg::PCIe_PUCplHdr_t tx_cpl_hdr;
    pcie_ss_hdr_pkg::PCIe_IntrHdr_t tx_irq_hdr;

    pcie_ss_hdr_pkg::ReqHdr_FmtType_e tx_fmttype;
    assign tx_fmttype = pcie_ss_hdr_pkg::ReqHdr_FmtType_e'(tx_from_pim.t.user[0].hdr.fmttype);

    // Memory request
    always_comb
    begin
        tx_mem_req_hdr = '0;
        tx_mem_req_hdr.fmt_type = tx_fmttype;
        tx_mem_req_hdr.length = tx_from_pim.t.user[0].hdr.length;
        tx_mem_req_hdr.req_id = { to_fiu_tlp.vf_num, to_fiu_tlp.vf_active, to_fiu_tlp.pf_num };
        tx_mem_req_hdr.TC = tx_from_pim.t.user[0].hdr.u.mem_req.tc;
        { tx_mem_req_hdr.tag_h, tx_mem_req_hdr.tag_m, tx_mem_req_hdr.tag_l } =
            { '0, tx_from_pim.t.user[0].hdr.u.mem_req.tag };
        tx_mem_req_hdr.last_dw_be = tx_from_pim.t.user[0].hdr.u.mem_req.last_be;
        tx_mem_req_hdr.first_dw_be = tx_from_pim.t.user[0].hdr.u.mem_req.first_be;
        if (pcie_ss_hdr_pkg::func_is_addr64(tx_fmttype))
        begin
            tx_mem_req_hdr.host_addr_h = tx_from_pim.t.user[0].hdr.u.mem_req.addr[63:32];
            tx_mem_req_hdr.host_addr_l = tx_from_pim.t.user[0].hdr.u.mem_req.addr[31:2];
        end
        else
        begin
            tx_mem_req_hdr.host_addr_h = tx_from_pim.t.user[0].hdr.u.mem_req.addr[31:0];
        end
        tx_mem_req_hdr.pf_num = to_fiu_tlp.pf_num;
        tx_mem_req_hdr.vf_num = to_fiu_tlp.vf_num;
        tx_mem_req_hdr.vf_active = to_fiu_tlp.vf_active;

        // Because there are two TX pipelines in the FIM, TX A for writes and TX B
        // for reads, the commit point of writes has not yet been reached. Pass
        // the AFU's completion tag to the FIM. It will be returned in a dataless
        // completion by the FIM once each write is committed to an ordered stream.
        if (pcie_ss_hdr_pkg::func_is_mem_req(tx_fmttype))
        begin
            tx_mem_req_hdr.metadata_l = { '0, tx_from_pim.t.user[0].afu_tag };
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
        else if (pcie_ss_hdr_pkg::func_is_mem_req(tx_fmttype))
        begin
            fim_enc_tx_hdr.t.data = tx_mem_req_hdr;
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
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t tx_mrd_req_hdr;

    pcie_ss_hdr_pkg::ReqHdr_FmtType_e tx_mrd_fmttype;
    assign tx_mrd_fmttype = pcie_ss_hdr_pkg::ReqHdr_FmtType_e'(tx_mrd_from_pim.t.user[0].hdr.fmttype);

    // Memory request
    always_comb
    begin
        tx_mrd_req_hdr = '0;
        tx_mrd_req_hdr.fmt_type = tx_mrd_fmttype;
        tx_mrd_req_hdr.length = tx_mrd_from_pim.t.user[0].hdr.length;
        tx_mrd_req_hdr.req_id = { to_fiu_tlp.vf_num, to_fiu_tlp.vf_active, to_fiu_tlp.pf_num };
        tx_mrd_req_hdr.TC = tx_mrd_from_pim.t.user[0].hdr.u.mem_req.tc;
        { tx_mrd_req_hdr.tag_h, tx_mrd_req_hdr.tag_m, tx_mrd_req_hdr.tag_l } =
            { '0, tx_mrd_from_pim.t.user[0].hdr.u.mem_req.tag };
        tx_mrd_req_hdr.last_dw_be = tx_mrd_from_pim.t.user[0].hdr.u.mem_req.last_be;
        tx_mrd_req_hdr.first_dw_be = tx_mrd_from_pim.t.user[0].hdr.u.mem_req.first_be;
        if (pcie_ss_hdr_pkg::func_is_addr64(tx_mrd_fmttype))
        begin
            tx_mrd_req_hdr.host_addr_h = tx_mrd_from_pim.t.user[0].hdr.u.mem_req.addr[63:32];
            tx_mrd_req_hdr.host_addr_l = tx_mrd_from_pim.t.user[0].hdr.u.mem_req.addr[31:2];
        end
        else
        begin
            tx_mrd_req_hdr.host_addr_h = tx_mrd_from_pim.t.user[0].hdr.u.mem_req.addr[31:0];
        end
        tx_mrd_req_hdr.pf_num = to_fiu_tlp.pf_num;
        tx_mrd_req_hdr.vf_num = to_fiu_tlp.vf_num;
        tx_mrd_req_hdr.vf_active = to_fiu_tlp.vf_active;
    end

    assign fim_enc_tx_mrd.tvalid = tx_mrd_from_pim.tvalid;

    always_comb
    begin
        fim_enc_tx_mrd.t = '0;
        fim_enc_tx_mrd.t.data = { '0, tx_mrd_req_hdr };
        fim_enc_tx_mrd.t.keep = { '0, {($bits(tx_mrd_req_hdr)/8){1'b1}} };
        fim_enc_tx_mrd.t.last = tx_mrd_from_pim.t.user[0].eop;
        fim_enc_tx_mrd.t.user[0].dm_mode = 1'b0;
        fim_enc_tx_mrd.t.user[0].sop = tx_mrd_from_pim.t.user[0].sop;
        fim_enc_tx_mrd.t.user[0].eop = tx_mrd_from_pim.t.user[0].eop;
    end

    ofs_plat_axi_stream_if_skid_sink_clk mrd_exit_skid
       (
        .stream_source(fim_enc_tx_mrd),
        .stream_sink(to_fiu_tlp.afu_tx_b_st)
        );


    // ====================================================================
    //
    //  FIM -> AFU RX stream translation from FIM to PIM encoding
    //
    // ====================================================================

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(pcie_ss_hdr_pkg::PCIe_PUReqHdr_t),
        .TUSER_TYPE(logic)    // pu mode (0) / dm mode (1)
        )
      fim_enc_rx_hdr();

    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_ofs_fim_axis_pcie_tdata),
        .TUSER_TYPE(logic)    // Not used
        )
      fim_enc_rx_data();

    assign fim_enc_rx_hdr.clk = to_fiu_tlp.clk;
    assign fim_enc_rx_hdr.reset_n = to_fiu_tlp.reset_n;
    assign fim_enc_rx_hdr.instance_number = to_fiu_tlp.instance_number;
    assign fim_enc_rx_data.clk = to_fiu_tlp.clk;
    assign fim_enc_rx_data.reset_n = to_fiu_tlp.reset_n;
    assign fim_enc_rx_data.instance_number = to_fiu_tlp.instance_number;

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
        .stream_source(to_fiu_tlp.afu_rx_a_st),
        .hdr_stream_sink(fim_enc_rx_hdr),
        .data_stream_sink(fim_enc_rx_data)
        );

    //
    // Track EOP/SOP of the incoming fim_enc_rx streams in order to handle
    // hdr and data messages in order.
    //
    logic fim_enc_rx_sop;

    always_ff @(posedge clk)
    begin
        if (fim_enc_rx_data.tready && fim_enc_rx_data.tvalid)
        begin
            fim_enc_rx_sop <= fim_enc_rx_data.t.last;
        end

        if (!reset_n)
        begin
            fim_enc_rx_sop <= 1'b1;
        end
    end

    //
    // Ready for next incoming message? If SOP, then both header and data must be
    // valid. (In order to simplify the control logic here, there is always a data
    // message, even if the header indicates no payload.)
    //
    assign fim_enc_rx_hdr.tready = rx_to_pim.tready && fim_enc_rx_sop && fim_enc_rx_data.tvalid;
    assign fim_enc_rx_data.tready = rx_to_pim.tready && (!fim_enc_rx_sop || fim_enc_rx_hdr.tvalid);

    // Data stream to PIM valid? Data must always be present and, if SOP, a header.
    assign rx_to_pim.tvalid = fim_enc_rx_data.tvalid && (!fim_enc_rx_sop || fim_enc_rx_hdr.tvalid);


    //
    // Header
    //

    // Next header, cast to a memory request
    pcie_ss_hdr_pkg::PCIe_PUReqHdr_t rx_mem_req_hdr;
    assign rx_mem_req_hdr = fim_enc_rx_hdr.t.data;

    // Next header, cast to a completion response
    pcie_ss_hdr_pkg::PCIe_PUCplHdr_t rx_cpl_hdr;
    assign rx_cpl_hdr = fim_enc_rx_hdr.t.data;

    // Format type of header (same position in any message)
    pcie_ss_hdr_pkg::ReqHdr_FmtType_e rx_fmttype;
    assign rx_fmttype = rx_cpl_hdr.fmt_type;

    logic rx_to_pim_invalid_cmd;

    always_comb
    begin
        rx_to_pim_invalid_cmd = 1'b0;
        rx_to_pim.t.user = '0;

        rx_to_pim.t.user[0].sop = fim_enc_rx_sop;
        rx_to_pim.t.user[0].eop = fim_enc_rx_data.t.last;

        if (fim_enc_rx_sop)
        begin
            rx_to_pim.t.user[0].hdr.fmttype = rx_fmttype;
            rx_to_pim.t.user[0].hdr.length = rx_cpl_hdr.length;

            if (pcie_ss_hdr_pkg::func_is_mem_req(rx_fmttype))
            begin
                rx_to_pim.t.user[0].hdr.u.mem_req.requester_id = rx_mem_req_hdr.req_id;
                rx_to_pim.t.user[0].hdr.u.mem_req.tc = rx_mem_req_hdr.TC;
                rx_to_pim.t.user[0].hdr.u.mem_req.tag =
                    { rx_mem_req_hdr.tag_h, rx_mem_req_hdr.tag_m, rx_mem_req_hdr.tag_l };
                rx_to_pim.t.user[0].hdr.u.mem_req.last_be = rx_mem_req_hdr.last_dw_be;
                rx_to_pim.t.user[0].hdr.u.mem_req.first_be = rx_mem_req_hdr.first_dw_be;
                rx_to_pim.t.user[0].hdr.u.mem_req.addr =
                    pcie_ss_hdr_pkg::func_is_addr64(rx_fmttype) ?
                        { rx_mem_req_hdr.host_addr_h, rx_mem_req_hdr.host_addr_l, 2'b0 } :
                        { '0, rx_mem_req_hdr.host_addr_h };
            end
            else if (pcie_ss_hdr_pkg::func_is_completion(rx_fmttype))
            begin
                rx_to_pim.t.user[0].hdr.u.cpl.requester_id = rx_cpl_hdr.req_id;
                rx_to_pim.t.user[0].hdr.u.mem_req.tc = rx_cpl_hdr.TC;
                rx_to_pim.t.user[0].hdr.u.cpl.tag =
                    { rx_cpl_hdr.tag_h, rx_cpl_hdr.tag_m, rx_cpl_hdr.tag_l };
                rx_to_pim.t.user[0].hdr.u.cpl.completer_id = rx_cpl_hdr.comp_id;
                rx_to_pim.t.user[0].hdr.u.cpl.byte_count = rx_cpl_hdr.byte_count;
                rx_to_pim.t.user[0].hdr.u.cpl.lower_addr = rx_cpl_hdr.low_addr;
            end
            else
            begin
                rx_to_pim_invalid_cmd = 1'b1;
            end
        end
    end

    // synthesis translate_off
    always_ff @(posedge rx_to_pim.clk)
    begin
        if (rx_to_pim.reset_n && rx_to_pim.tvalid && rx_to_pim.tready)
        begin
            if (rx_to_pim_invalid_cmd)
                $fatal(2, "Unexpected TLP RX header to PIM!");

            if (fim_enc_rx_sop && fim_enc_rx_hdr.t.user)
                $fatal(2, "Data Mover encoded TLP RX headers not supported by PIM!");
        end
    end
    // synthesis translate_on

    //
    // Payload (data only)
    //
    always_comb
    begin
        rx_to_pim.t.data[0] = fim_enc_rx_data.t.data.payload;
        rx_to_pim.t.keep = ~'0;

        // The PIM will only generate a short read for atomic requests. The
        // response will arrive in the low bits of the payload, but the PIM's
        // memory mapped interfaces expect the data shifted to the position
        // in the data bus corresponding to the request address. We can simply
        // replicate the data unconditionally.
        if (fim_enc_rx_sop && pcie_ss_hdr_pkg::func_is_completion(rx_fmttype))
        begin
            if (rx_cpl_hdr.length == 1)
            begin
                for (int i = 1; i < $bits(rx_to_pim.t.data[0]) / 32; i = i + 1)
                begin
                    rx_to_pim.t.data[0][i*32 +: 32] = fim_enc_rx_data.t.data.payload[31:0];
                end
            end
            else if (rx_cpl_hdr.length == 2)
            begin
                for (int i = 1; i < $bits(rx_to_pim.t.data[0]) / 64; i = i + 1)
                begin
                    rx_to_pim.t.data[0][i*64 +: 64] = fim_enc_rx_data.t.data.payload[63:0];
                end
            end
        end
    end


    // Write and interrupt completions arrive on RX B
    assign to_fiu_tlp.afu_rx_b_st.tready = wr_cpl_to_pim.tready && irq_cpl_to_pim.tready;

    //
    // Forward write completions generated by the FIM back to the AFU. Write completions
    // indicate the serialized commit point of writes on TX A relative to reads on TX B.
    //
    pcie_ss_hdr_pkg::PCIe_PUCplHdr_t rx_wr_cpl_pu_hdr;
    assign rx_wr_cpl_pu_hdr = to_fiu_tlp.afu_rx_b_st.t.data;

    assign wr_cpl_to_pim.tvalid = to_fiu_tlp.afu_rx_b_st.tvalid &&
                                  // TC[0] is 0 for write responses, 1 for interrupts
                                  !rx_wr_cpl_pu_hdr.TC[0];

    always_comb
    begin
        wr_cpl_to_pim.t = '0;
        wr_cpl_to_pim.t.data.tag =
            ofs_plat_host_chan_@group@_pcie_tlp_pkg::t_dma_afu_tag'(rx_wr_cpl_pu_hdr.metadata_l);
        wr_cpl_to_pim.t.data.line_count =
            ofs_plat_host_chan_@group@_pcie_tlp_pkg::dwordLenToLineCount(rx_wr_cpl_pu_hdr.length);
        wr_cpl_to_pim.t.last = 1'b1;
    end


    //
    // IRQ responses are out of band from the FIM
    //
    pcie_ss_hdr_pkg::PCIe_CplHdr_t rx_intr_cpl_dm_hdr;
    assign rx_intr_cpl_dm_hdr = to_fiu_tlp.afu_rx_b_st.t.data;

    assign irq_cpl_to_pim.tvalid = to_fiu_tlp.afu_rx_b_st.tvalid &&
                                   // TC[0] is 1 for interrupts
                                   rx_wr_cpl_pu_hdr.TC[0];

    always_comb
    begin
        irq_cpl_to_pim.t = '0;
        irq_cpl_to_pim.t.data.requester_id = { to_fiu_tlp.vf_num, to_fiu_tlp.vf_active, to_fiu_tlp.pf_num };
        irq_cpl_to_pim.t.data.irq_id = rx_intr_cpl_dm_hdr.metadata_l[$bits(t_ofs_plat_pcie_hdr_irq_id)-1 : 0];
    end

endmodule // ofs_plat_host_chan_@group@_fim_gasket
