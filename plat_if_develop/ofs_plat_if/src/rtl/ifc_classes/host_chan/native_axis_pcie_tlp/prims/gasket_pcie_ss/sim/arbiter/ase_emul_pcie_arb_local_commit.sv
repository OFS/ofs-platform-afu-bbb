// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Description
//-----------------------------------------------------------------------------
//
// Monitor the sink->source stream. When a write request is detected, emit
// a completion without data on the commit stream.
//
// These locally generated commits are used along with the dual (A/B) PF/VF
// MUX tree. Commits are forwarded to AFUs so they can track the point at
// which the relative order of the A and B streams is guaranteed.
//
// The tag, length and metadata extension fields are looped back from
// each write request into the generated completion.
//
// Responses are also generated for DM encoded interrupt requests.
// Bit 0 of TC will always be set to one for a generated interrupt
// completion and 0 for a normal write completion. The interrupt vector_num
// is returned in metadata_l of the generated completion.
//
//-----------------------------------------------------------------------------

module ase_emul_pcie_arb_local_commit #(
   parameter TDATA_WIDTH = ofs_pcie_ss_cfg_pkg::TDATA_WIDTH,
   parameter TUSER_WIDTH = ofs_pcie_ss_cfg_pkg::TUSER_WIDTH,

   // Don't generate a commit when this TUSER bit is set. Ignored
   // when the parameter is zero.
`ifdef OFS_PCIE_SS_CFG_FLAG_TUSER_NO_STORE_COMMIT
   parameter TUSER_NO_STORE_COMMIT_MSG_BIT = ofs_pcie_ss_cfg_pkg::TUSER_NO_STORE_COMMIT_MSG_BIT
`else
   parameter TUSER_NO_STORE_COMMIT_MSG_BIT = 0
`endif
)(
   input  wire clk,
   input  wire rst_n,

   pcie_ss_axis_if.sink   sink,
   pcie_ss_axis_if.source source,
   pcie_ss_axis_if.source commit
);

   import pcie_ss_hdr_pkg::*;

   pcie_ss_axis_if commit_in(clk, rst_n);
   logic sink_sop;

   // Commit messages are only generated on tlast
   wire commit_in_ready = (commit_in.tready || !sink.tlast);

   // TX data, viewed as either PU or DM headers
   PCIe_ReqHdr_t   tx_req_dm_hdr;
   PCIe_PUReqHdr_t tx_req_pu_hdr;
   PCIe_IntrHdr_t  tx_req_dm_intr;
   assign tx_req_dm_hdr = PCIe_ReqHdr_t'(sink.tdata);
   assign tx_req_pu_hdr = PCIe_PUReqHdr_t'(sink.tdata);
   assign tx_req_dm_intr = PCIe_IntrHdr_t'(sink.tdata);

   // Suppress the commit for this message when specified tuser_vendor bit is 1.
   // Suppress nothing when the bit index is 0.
   wire tx_suppress_commit =
      TUSER_NO_STORE_COMMIT_MSG_BIT ? sink.tuser_vendor[TUSER_NO_STORE_COMMIT_MSG_BIT] : 1'b0;

   wire tx_is_dm = func_hdr_is_dm_mode(sink.tuser_vendor);
   wire tx_is_wr_req = func_is_mwr_req(tx_req_dm_hdr.fmt_type);
   wire tx_is_intr_req = tx_is_dm && func_is_interrupt_req(tx_req_dm_hdr.fmt_type);
   wire tx_needs_cpl = (tx_is_wr_req || tx_is_intr_req) && !tx_suppress_commit;

   // Forward incoming TX stream (sink) toward the FIM (source)
   assign sink.tready = source.tready && commit_in_ready;
   assign source.tvalid = sink.tvalid && commit_in_ready;
   assign source.tkeep = sink.tkeep;
   assign source.tlast = sink.tlast;
   assign source.tuser_vendor = sink.tuser_vendor;
   always_comb
   begin
      source.tdata = sink.tdata;
      if (sink_sop && tx_needs_cpl && !tx_is_dm)
      begin
         // The PCIe SS declares bytes 24-31 of PU encoded requests as reserved.
         // These correspond to the metadata fields of DM encoded requests. The
         // FIM allows AFUs to pass state even in PU encoded write requests and
         // will include the metadata values in the write ACK synthesized below.
         // Force the metadata bits to 0 in the header being forwarded to the
         // PCIe SS.
         source.tdata[24*8 +: 64] = '0;
      end
   end

   always_ff @(posedge clk)
   begin
      if (sink.tvalid && sink.tready)
         sink_sop <= sink.tlast;

      if (!rst_n)
         sink_sop <= 1'b1;
   end

   PCIe_CplHdr_t   rx_cmp_dm_hdr;
   PCIe_PUCplHdr_t rx_cmp_pu_hdr;
   PCIe_CplHdr_t   rx_cmp_dm_intr;

   // Generate local completion, mostly returning a copy of the input fields
   always_comb begin
      // Completion (without data) in DM mode, to match a DM write
      rx_cmp_dm_hdr = '0;
      rx_cmp_dm_hdr.fmt_type   = ReqHdr_FmtType_e'({ '0, PCIE_FMTTYPE_CPL });
      rx_cmp_dm_hdr.metadata_l = tx_req_dm_hdr.metadata_l;
      rx_cmp_dm_hdr.metadata_h = tx_req_dm_hdr.metadata_h;
      rx_cmp_dm_hdr.vf_active  = tx_req_dm_hdr.vf_active;
      rx_cmp_dm_hdr.vf_num     = tx_req_dm_hdr.vf_num;
      rx_cmp_dm_hdr.pf_num     = tx_req_dm_hdr.pf_num;
      rx_cmp_dm_hdr.length_h   = tx_req_dm_hdr.length_h;
      rx_cmp_dm_hdr.length_m   = tx_req_dm_hdr.length_m;
      rx_cmp_dm_hdr.length_l   = tx_req_dm_hdr.length_l;
      rx_cmp_dm_hdr.tag        = { tx_req_dm_hdr.tag_h, tx_req_dm_hdr.tag_m, tx_req_dm_hdr.tag_l };
      rx_cmp_dm_hdr.FC         = 1'b1;

      // Completion (without data) in PU mode, to match a PU write
      rx_cmp_pu_hdr = '0;
      rx_cmp_pu_hdr.fmt_type   = ReqHdr_FmtType_e'({ '0, PCIE_FMTTYPE_CPL });
      rx_cmp_pu_hdr.metadata_l = tx_req_pu_hdr.metadata_l;
      rx_cmp_pu_hdr.metadata_h = tx_req_pu_hdr.metadata_h;
      rx_cmp_pu_hdr.req_id     = tx_req_pu_hdr.req_id;
      rx_cmp_pu_hdr.vf_active  = tx_req_pu_hdr.vf_active;
      rx_cmp_pu_hdr.vf_num     = tx_req_pu_hdr.vf_num;
      rx_cmp_pu_hdr.pf_num     = tx_req_pu_hdr.pf_num;
      rx_cmp_pu_hdr.length     = tx_req_pu_hdr.length;
      rx_cmp_pu_hdr.byte_count = tx_req_pu_hdr.length << 2;
      rx_cmp_pu_hdr.tag_h      = tx_req_pu_hdr.tag_h;
      rx_cmp_pu_hdr.tag_m      = tx_req_pu_hdr.tag_m;
      rx_cmp_pu_hdr.tag_l      = tx_req_pu_hdr.tag_l;

      // Completion (without data) in DM mode, to match a DM interrupt request
      rx_cmp_dm_intr = '0;
      rx_cmp_dm_intr.fmt_type   = ReqHdr_FmtType_e'({ '0, PCIE_FMTTYPE_CPL });
      rx_cmp_dm_intr.metadata_l = { '0, tx_req_dm_intr.vector_num };
      rx_cmp_dm_intr.vf_active  = tx_req_dm_intr.vf_active;
      rx_cmp_dm_intr.vf_num     = tx_req_dm_intr.vf_num;
      rx_cmp_dm_intr.pf_num     = tx_req_dm_intr.pf_num;
      rx_cmp_dm_intr.FC         = 1'b1;
      rx_cmp_dm_intr.TC[0]      = 1'b1;  // TC[0] set to 1 indicates interrupt
   end

   // The completion header is derived from the first beat of a write request,
   // but returned to the AFU on the last write beat.
   PCIe_CplHdr_t rx_cmp_hdr, rx_cmp_hdr_reg;
   logic [$bits(commit_in.tuser_vendor)-1 : 0] rx_cmp_tuser_reg;
   logic rx_cmp_hdr_reg_valid;

   always_comb
   begin
      if (tx_is_wr_req)
         rx_cmp_hdr = { '0, (tx_is_dm ? rx_cmp_dm_hdr : rx_cmp_pu_hdr) };
      else
         rx_cmp_hdr = { '0, rx_cmp_dm_intr };
   end

   // Record commit header during the sink header beat
   always_ff @(posedge clk)
   begin
      if (sink.tvalid && sink.tready && sink_sop) begin
         rx_cmp_hdr_reg_valid <= tx_needs_cpl;
         rx_cmp_hdr_reg <= rx_cmp_hdr;
         rx_cmp_tuser_reg <= sink.tuser_vendor;
      end

      if (!rst_n) begin
         rx_cmp_hdr_reg_valid <= 1'b0;
      end
   end

   assign commit_in.tvalid = sink.tvalid && sink.tready && sink.tlast &&
                             (sink_sop ? tx_needs_cpl : rx_cmp_hdr_reg_valid);
   assign commit_in.tdata = { '0, (sink_sop ? rx_cmp_hdr : rx_cmp_hdr_reg) };
   assign commit_in.tuser_vendor = (sink_sop ? sink.tuser_vendor : rx_cmp_tuser_reg);
   assign commit_in.tkeep = { '0, {($bits(PCIe_CplHdr_t)/8){1'b1}} };
   assign commit_in.tlast = 1'b1;

   ase_emul_pcie_ss_axis_pipeline #(
      .TDATA_WIDTH(TDATA_WIDTH),
      .TUSER_WIDTH(TUSER_WIDTH),
      .MODE(1)
   ) commit_skid (
      .clk,
      .rst_n,
      .axis_s(commit_in),
      .axis_m(commit)
   );

endmodule // ase_emul_pcie_arb_local_commit
