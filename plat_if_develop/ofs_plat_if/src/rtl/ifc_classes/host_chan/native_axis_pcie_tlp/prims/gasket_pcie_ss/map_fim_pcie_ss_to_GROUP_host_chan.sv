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
// Map the PCIe SS AXI-S interface exposed by the FIM to the PIM's representation.
// The payload is the same in both. The PIM adds extra decoration to encode
// SOP flags within the user field and uses a consistent AXI-S interface
// declaration across all PIM-managed devices.
//
// There are two streams per port: A and B. TX B is used for read requests. TX A
// is used for all others. The two ports do not have a defined relative order.
// RX A has standard host to FPGA traffic. RX B has Cpl messages (without data),
// synthesized by the FIM in response to TX A write requests at the commit point
// where TX A and B are ordered.
//

`include "ofs_plat_if.vh"

//
// Primary wrapper for mapping a collection of four FIM TLP streams into a
// logical PIM port. There are two streams in each direction, with the "B"
// ports intended for transmitting reads that may flow around writes.
//
module map_fim_pcie_ss_to_pim_@group@_host_chan
  #(
    // Instance number is just used for debugging as a tag
    parameter INSTANCE_NUMBER = 0,

    // PCIe PF/VF details
    parameter pcie_ss_hdr_pkg::ReqHdr_pf_num_t PF_NUM,
    parameter pcie_ss_hdr_pkg::ReqHdr_vf_num_t VF_NUM,
    parameter VF_ACTIVE
    )
   (
    // All streams are expected to share the same clock and reset
    input  logic clk,
    // Force 'x to 0
    input  bit   reset_n,

    // FIM interfaces
    pcie_ss_axis_if.source pcie_ss_tx_a_st,
    pcie_ss_axis_if.source pcie_ss_tx_b_st,
    pcie_ss_axis_if.sink pcie_ss_rx_a_st,
    pcie_ss_axis_if.sink pcie_ss_rx_b_st,

    // PIM wrapper for the FIM interfaces
    ofs_plat_host_chan_axis_pcie_tlp_if port
    );

    assign port.clk = clk;
    assign port.reset_n = reset_n;

    assign port.instance_number = INSTANCE_NUMBER;
    assign port.pf_num = PF_NUM;
    assign port.vf_num = VF_NUM;
    assign port.vf_active = VF_ACTIVE;

    map_fim_pcie_ss_to_host_chan map
       (
        .pcie_ss_tx_a_st,
        .pcie_ss_tx_b_st,
        .pcie_ss_rx_a_st,
        .pcie_ss_rx_b_st,

        .pim_tx_a_st(port.afu_tx_a_st),
        .pim_tx_b_st(port.afu_tx_b_st),
        .pim_rx_a_st(port.afu_rx_a_st),
        .pim_rx_b_st(port.afu_rx_b_st)
        );

endmodule // map_fim_pcie_ss_to_pim_@group@_host_chan


//
// Mapping of individual FIM to PIM ports. Older code outside the PIM may
// also use this interface, so it is preserved here instead of being merged
// into the module above.
//
module map_fim_pcie_ss_to_@group@_host_chan
   (
    // FIM interfaces
    pcie_ss_axis_if.source pcie_ss_tx_a_st,
    pcie_ss_axis_if.source pcie_ss_tx_b_st,
    pcie_ss_axis_if.sink pcie_ss_rx_a_st,
    pcie_ss_axis_if.sink pcie_ss_rx_b_st,

    // PIM interfaces
    ofs_plat_axi_stream_if.to_source pim_tx_a_st,
    ofs_plat_axi_stream_if.to_source pim_tx_b_st,
    ofs_plat_axi_stream_if.to_sink pim_rx_a_st,
    ofs_plat_axi_stream_if.to_sink pim_rx_b_st
    );

    localparam FIM_PCIE_SEG_WIDTH = ofs_pcie_ss_cfg_pkg::TDATA_WIDTH /
                                    ofs_pcie_ss_cfg_pkg::NUM_OF_SEG;
    // Segment width in bytes (useful for indexing tkeep as valid bits)
    localparam FIM_PCIE_SEG_BYTES = FIM_PCIE_SEG_WIDTH / 8;

    wire clk = pim_tx_a_st.clk;
    wire reset_n = pim_tx_a_st.reset_n;

    logic pcie_ss_rx_a_is_sop;

    //
    // TX (AFU -> host)
    //
    assign pim_tx_a_st.tready = pcie_ss_tx_a_st.tready;
    assign pcie_ss_tx_a_st.tvalid = pim_tx_a_st.tvalid;

    always_comb
    begin
        pcie_ss_tx_a_st.tlast = pim_tx_a_st.t.last;
        pcie_ss_tx_a_st.tdata = pim_tx_a_st.t.data;
        // Map byte->dword keep bits, dropping 3/4 of them, to save space.
        // Masks are always at the dword level.
        for (int w = 0; w < ofs_pcie_ss_cfg_pkg::TDATA_WIDTH/32; w = w + 1)
        begin
            pcie_ss_tx_a_st.tkeep[w*4 +: 4] = {4{pim_tx_a_st.t.keep[w*4]}};
        end

        // Bit 0 of tuser_vendor indicates PU (0) or DM (1) format. The PIM's
        // user data is broken down into PCIe SS segments. For now, we assume
        // that only segment 0 has a header.
        pcie_ss_tx_a_st.tuser_vendor = '0;
        pcie_ss_tx_a_st.tuser_vendor[0] = pim_tx_a_st.t.user[0].dm_mode;
    end

    //
    // TX B (AFU -> host). TX B is a second transmit port. The PIM uses the B
    // port for reads and the primary port for writes and other traffic. This
    // may improve aggregate throughput in multi-VF designs.
    //
    assign pim_tx_b_st.tready = pcie_ss_tx_b_st.tready;
    assign pcie_ss_tx_b_st.tvalid = pim_tx_b_st.tvalid;

    always_comb
    begin
        pcie_ss_tx_b_st.tlast = pim_tx_b_st.t.last;
        pcie_ss_tx_b_st.tdata = pim_tx_b_st.t.data;
        // Map byte->dword keep bits, dropping 3/4 of them, to save space.
        // Masks are always at the dword level.
        for (int w = 0; w < ofs_pcie_ss_cfg_pkg::TDATA_WIDTH/32; w = w + 1)
        begin
            pcie_ss_tx_b_st.tkeep[w*4 +: 4] = {4{pim_tx_b_st.t.keep[w*4]}};
        end

        // Bit 0 of tuser_vendor indicates PU (0) or DM (1) format. The PIM's
        // user data is broken down into PCIe SS segments. For now, we assume
        // that only segment 0 has a header.
        pcie_ss_tx_b_st.tuser_vendor = '0;
        pcie_ss_tx_b_st.tuser_vendor[0] = pim_tx_b_st.t.user[0].dm_mode;
    end

    //
    // RX A (host -> AFU)
    //
    assign pcie_ss_rx_a_st.tready = pim_rx_a_st.tready;
    assign pim_rx_a_st.tvalid = pcie_ss_rx_a_st.tvalid;

    always_comb
    begin
        pim_rx_a_st.t = '0;
        pim_rx_a_st.t.last = pcie_ss_rx_a_st.tlast;
        pim_rx_a_st.t.data = pcie_ss_rx_a_st.tdata;
        pim_rx_a_st.t.keep = pcie_ss_rx_a_st.tkeep;

        // The PIM's user field has sop/eop tracking built in. For now, we
        // assume that only PCIe SS segment 0 has a header.
        pim_rx_a_st.t.user = '0;
        pim_rx_a_st.t.user[0].dm_mode = pcie_ss_rx_a_st.tuser_vendor[0];
        pim_rx_a_st.t.user[0].sop = pcie_ss_rx_a_is_sop;

        // Mark at most one EOP. Find the highest segment with a payload and
        // set its EOP bit, using tlast. tlast is currently the only header
        // indicator in the FIM's PCIe SS configuration.
        for (int s = ofs_pcie_ss_cfg_pkg::NUM_OF_SEG - 1; s >= 0; s = s - 1)
        begin
            if (pcie_ss_rx_a_st.tkeep[s * FIM_PCIE_SEG_BYTES])
            begin
                pim_rx_a_st.t.user[0].eop = pcie_ss_rx_a_st.tlast;
                break;
            end
        end
    end

    always_ff @(posedge clk)
    begin
        // Is the next RX packet a new SOP?
        if (pcie_ss_rx_a_st.tready && pcie_ss_rx_a_st.tvalid)
        begin
            pcie_ss_rx_a_is_sop <= pcie_ss_rx_a_st.tlast;
        end

        if (!reset_n)
        begin
            pcie_ss_rx_a_is_sop <= 1'b1;
        end
    end

    //
    // RX B (post TX A/B arbitration locally generated write completions -> AFU)
    //
    assign pcie_ss_rx_b_st.tready = pim_rx_b_st.tready;
    assign pim_rx_b_st.tvalid = pcie_ss_rx_b_st.tvalid;

    always_comb
    begin
        pim_rx_b_st.t = '0;
        pim_rx_b_st.t.last = pcie_ss_rx_b_st.tlast;
        pim_rx_b_st.t.data = pcie_ss_rx_b_st.tdata;
        pim_rx_b_st.t.keep = pcie_ss_rx_b_st.tkeep;

        // In RX B, only segment 0 will have a valid header. Since it has no payload,
        // SOP and EOP are the same value.
        pim_rx_b_st.t.user = '0;
        pim_rx_b_st.t.user[0].dm_mode = pcie_ss_rx_b_st.tuser_vendor[0];
        pim_rx_b_st.t.user[0].sop = pcie_ss_rx_b_st.tlast;
        pim_rx_b_st.t.user[0].eop = pcie_ss_rx_b_st.tlast;
    end

endmodule // map_fim_pcie_ss_to_@group@_host_chan
