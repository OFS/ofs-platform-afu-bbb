//
// Copyright (c) 2022, Intel Corporation
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
// Connect the PIM's MMIO traffic to an AXI-Lite interface provided by the FIM.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_@group@_gen_mmio_axi_lite
   (
    input  logic clk,
    input  logic reset_n,

    // AXI-Lite interface from host
    ofs_plat_axi_mem_lite_if.to_source fiu_mmio_if,

    // MMIO requests from host to AFU (t_gen_tx_mmio_afu_req)
    ofs_plat_axi_stream_if.to_sink host_mmio_req,

    // AFU responses (t_gen_tx_mmio_afu_rsp)
    ofs_plat_axi_stream_if.to_source host_mmio_rsp,

    output logic error
    );

    import ofs_plat_host_chan_@group@_gen_tlps_pkg::*;

    wire csr_clk = fiu_mmio_if.clk;
    wire csr_reset_n = fiu_mmio_if.reset_n;

    //
    // Add a skid buffer, both for timing and because the skid buffer uses
    // FIFOs internally that have ready signals that are independent of
    // incoming valids. This simplifies arbitration.
    //
    ofs_plat_axi_mem_lite_if
      #(
        `OFS_PLAT_AXI_MEM_LITE_IF_REPLICATE_PARAMS(fiu_mmio_if)
        )
      axi_mmio_if();

    assign axi_mmio_if.clk = csr_clk;
    assign axi_mmio_if.reset_n = csr_reset_n;
    assign axi_mmio_if.instance_number = fiu_mmio_if.instance_number;

    ofs_plat_axi_mem_lite_if_skid skid
       (
        .mem_source(fiu_mmio_if),
        .mem_sink(axi_mmio_if)
        );


    // MMIO requests to the AFU in the csr_clk domain
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_gen_tx_mmio_afu_req),
        .TUSER_TYPE(logic)
        )
      host_to_afu_req();

    assign host_to_afu_req.clk = csr_clk;
    assign host_to_afu_req.reset_n = csr_reset_n;
    assign host_to_afu_req.instance_number = fiu_mmio_if.instance_number;


    //
    // Arbitration. The host request stream accepts only a read or a write
    // in a cycle, not both.
    //

    wire pending_rd_req = axi_mmio_if.arvalid;
    // Writes send the commit on B immediately. There is no response to the host
    // anyway, so delaying the B response has no semantic value.
    wire pending_wr_req = axi_mmio_if.awvalid && axi_mmio_if.wvalid && axi_mmio_if.bready;
    logic arb_grant_wr, arb_grant_rd;

    ofs_plat_prim_arb_rr
      #(
        .NUM_CLIENTS(2)
        )
      arb
       (
        .clk(csr_clk),
        .reset_n(csr_reset_n),
        .ena(host_to_afu_req.tready),
        .request({ pending_wr_req, pending_rd_req }),
        .grant({ arb_grant_wr, arb_grant_rd }),
        .grantIdx()
        );

    assign host_to_afu_req.tvalid = arb_grant_wr || arb_grant_rd;
    assign axi_mmio_if.awready = arb_grant_wr;
    assign axi_mmio_if.wready = arb_grant_wr;
    assign axi_mmio_if.arready = arb_grant_rd;

    assign axi_mmio_if.bvalid = arb_grant_wr;
    assign axi_mmio_if.b = '0;

    always_comb
    begin
        host_to_afu_req.t = '0;
        host_to_afu_req.t.data.is_write = arb_grant_wr;

        if (arb_grant_rd)
        begin
            // The PCIe SS keeps reads simple. They are always assumed to be the
            // full bus width and the address is aligned to a bus boundary.
            host_to_afu_req.t.data.addr = axi_mmio_if.ar.addr;
            host_to_afu_req.t.data.byte_count = 8;
        end
        else
        begin
            // The PCIe SS signals a 32 bit write with both strb and by setting
            // addr[2]. The PIM expects data to always start at payload[0], since
            // that matches TLP encoding.
            host_to_afu_req.t.data.addr = axi_mmio_if.aw.addr;
            host_to_afu_req.t.data.byte_count =
                (axi_mmio_if.w.strb[0] && axi_mmio_if.w.strb[4]) ? 8 : 4;

            host_to_afu_req.t.data.payload = { '0, axi_mmio_if.w.data };
            if (!axi_mmio_if.w.strb[0])
                host_to_afu_req.t.data.payload[31:0] = axi_mmio_if.w.data[63:32];
        end
    end

    //
    // Cross requests to the primary clock
    //
    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(0),
        .ADD_TIMING_READY_STAGES(0),
        .READY_FROM_ALMOST_FULL(0),
        .N_ENTRIES(4),
        .DATA_WIDTH($bits(host_mmio_req.t))
        )
      from_csr_clk
       (
        .clk_in(csr_clk),
        .reset_n_in(csr_reset_n),
        .ready_in(host_to_afu_req.tready),
        .valid_in(host_to_afu_req.tvalid),
        .data_in(host_to_afu_req.t),

        .clk_out(clk),
        .reset_n_out(reset_n),
        .ready_out(host_mmio_req.tready),
        .valid_out(host_mmio_req.tvalid),
        .data_out(host_mmio_req.t)
        );


    //
    // Read responses
    //

    // Cross back to the CSR clock
    ofs_plat_axi_stream_if
      #(
        .TDATA_TYPE(t_gen_tx_mmio_afu_rsp),
        .TUSER_TYPE(logic)
        )
      afu_to_host_rsp();

    assign afu_to_host_rsp.clk = csr_clk;
    assign afu_to_host_rsp.reset_n = csr_reset_n;
    assign afu_to_host_rsp.instance_number = fiu_mmio_if.instance_number;

    ofs_plat_axi_mem_if_async_shim_channel
      #(
        .ADD_TIMING_REG_STAGES(0),
        .ADD_TIMING_READY_STAGES(0),
        .READY_FROM_ALMOST_FULL(0),
        .N_ENTRIES(4),
        .DATA_WIDTH($bits(host_mmio_rsp.t))
        )
      to_csr_clk
       (
        .clk_in(clk),
        .reset_n_in(reset_n),
        .ready_in(host_mmio_rsp.tready),
        .valid_in(host_mmio_rsp.tvalid),
        .data_in(host_mmio_rsp.t),

        .clk_out(csr_clk),
        .reset_n_out(csr_reset_n),
        .ready_out(afu_to_host_rsp.tready),
        .valid_out(afu_to_host_rsp.tvalid),
        .data_out(afu_to_host_rsp.t)
        );

    assign afu_to_host_rsp.tready = axi_mmio_if.rready;
    assign axi_mmio_if.rvalid = afu_to_host_rsp.tvalid;
    always_comb
    begin
        axi_mmio_if.r = '0;
        axi_mmio_if.r.data = { '0, afu_to_host_rsp.t.data.payload };
    end

endmodule // ofs_plat_host_chan_@group@_gen_mmio_axi_lite
