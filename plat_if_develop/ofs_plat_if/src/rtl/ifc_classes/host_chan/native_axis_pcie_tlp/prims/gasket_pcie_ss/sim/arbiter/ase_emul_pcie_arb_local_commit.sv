// Copyright 2020 Intel Corporation.
//
// THIS SOFTWARE MAY CONTAIN PREPRODUCTION CODE AND IS PROVIDED BY THE
// COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED
// WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
// MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
// DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
// BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
// WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE
// OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
// EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
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
//-----------------------------------------------------------------------------

module ase_emul_pcie_arb_local_commit #(
   parameter TDATA_WIDTH = ofs_pcie_ss_cfg_pkg::TDATA_WIDTH,
   parameter TUSER_WIDTH = ofs_pcie_ss_cfg_pkg::TUSER_WIDTH
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

   assign sink.tready = source.tready && commit_in.tready;
   assign source.tvalid = sink.tvalid && commit_in.tready;
   assign source.tdata = sink.tdata;
   assign source.tkeep = sink.tkeep;
   assign source.tlast = sink.tlast;
   assign source.tuser_vendor = sink.tuser_vendor;

   // TX data, viewed as either PU or DM headers
   PCIe_ReqHdr_t   tx_req_dm_hdr;
   PCIe_PUReqHdr_t tx_req_pu_hdr;
   assign tx_req_dm_hdr = PCIe_ReqHdr_t'(sink.tdata);
   assign tx_req_pu_hdr = PCIe_PUReqHdr_t'(sink.tdata);

   // Valid/ready bits are checked separately
   logic tx_is_dm;
   assign tx_is_dm = func_hdr_is_dm_mode(sink.tuser_vendor);
   logic tx_is_wr_req;
   assign tx_is_wr_req = sink_sop && func_is_mwr_req(tx_req_pu_hdr.fmt_type);

   PCIe_CplHdr_t   rx_cmp_dm_hdr;
   PCIe_PUCplHdr_t rx_cmp_pu_hdr;
   logic rx_pending, rx_ready;

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
   end

   always_ff @(posedge clk)
   begin
      // commit skid is known to be ready if the logic here sets it valid
      if (commit_in.tvalid) begin
         rx_pending <= 1'b0;
         rx_ready <= 1'b0;
      end

      if (sink.tvalid && sink.tready) begin
         sink_sop <= sink.tlast;

         if (tx_is_wr_req) begin
            rx_pending <= 1'b1;
            commit_in.tdata <= { '0, (tx_is_dm ? rx_cmp_dm_hdr : rx_cmp_pu_hdr) };
            commit_in.tuser_vendor <= sink.tuser_vendor;
         end
         if (sink.tlast && (tx_is_wr_req || rx_pending)) begin
            rx_ready <= 1'b1;
         end
      end

      if (!rst_n) begin
         rx_pending <= 1'b0;
         rx_ready <= 1'b0;
         sink_sop <= 1'b1;
      end
   end

   assign commit_in.tvalid = rx_pending && rx_ready;
   assign commit_in.tkeep = { '0, {($bits(PCIe_CplHdr_t)/8){1'b1}} };
   assign commit_in.tlast = 1'b1;

   ase_emul_pcie_ss_axis_pipeline #(
      .TDATA_WIDTH(TDATA_WIDTH),
      .TUSER_WIDTH(TUSER_WIDTH)
   ) commit_skid (
      .clk,
      .rst_n,
      .axis_s(commit_in),
      .axis_m(commit)
   );

endmodule // pcie_arb_local_commit
