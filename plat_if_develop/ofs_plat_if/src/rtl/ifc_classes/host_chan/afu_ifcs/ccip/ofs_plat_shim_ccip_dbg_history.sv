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
// Implements a history buffer shim in a CCI-P pipeline.  This module is not
// designed to be part of a normal pipeline. It can be inserted for
// debugging, similar to SignalTap. Values are added to the history
// buffer through the module interface and read back from the host using
// MMIO reads.
//

`include "ofs_plat_if.vh"

// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
//
//  This module is intended for debugging and not production code.
//  It assumes there is at most one MMIO read to the history
//  buffer active at a time.  Software that pipelines the history
//  buffer reads may receive incorrect responses.
//
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

module ofs_plat_shim_ccip_dbg_history
  #(
    // Base address of the history buffer in MMIO space.  This is the
    // byte-level address base.
    parameter MMIO_BASE_ADDR = 'h8000,

    // 32 or 64 bit registers are supported
    parameter MMIO_REG_WIDTH = 32,

    // Number of entries in the ring buffer
    parameter N_ENTRIES = 1024,

    // Data size must be <= MMIO_REG_BITS
    parameter DATA_WIDTH = 32,

    // Indexed writes or ring buffer?  When RING_MODE is enabled history
    // buffer entries are written round-robin.  When RING_MODE is 0
    // new entries are written to history entry wr_idx.
    parameter RING_MODE = 1,

    // In ring mode write the ring once to collect the first N_ENTRIES.
    parameter WRITE_ONCE = 0,

    // Lock out writes after first read?  This keeps the ring from advancing
    // when readout starts.
    parameter LOCK_WRITES_AFTER_READ = 1
    )
   (
    // Connection toward the QA platform.  Reset comes in here.
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    // Connections toward user code.
    ofs_plat_host_ccip_if.to_afu to_afu,

    // Write a new entry
    input  logic wr_en,
    input  logic [DATA_WIDTH-1 : 0] wr_data,
    input  logic [$clog2(N_ENTRIES)-1 : 0] wr_idx
    );

    logic clk;
    assign clk = to_fiu.clk;
    assign to_afu.clk = to_fiu.clk;

    assign to_afu.reset_n = to_fiu.reset_n;
    logic reset_n = 1'b0;
    always @(posedge clk)
    begin
        reset_n <= to_fiu.reset_n;
    end

    assign to_afu.instance_number = to_fiu.instance_number;

    logic history_reset;
    logic mem_rdy;

    assign to_fiu.sTx.c0 = to_afu.sTx.c0;
    assign to_fiu.sTx.c1 = to_afu.sTx.c1;
    assign to_afu.sRx.c1 = to_fiu.sRx.c1;

    assign to_afu.sRx.c0TxAlmFull = to_fiu.sRx.c0TxAlmFull || !mem_rdy;
    assign to_afu.sRx.c1TxAlmFull = to_fiu.sRx.c1TxAlmFull || !mem_rdy;


    // Forward responses to host, either generated locally (c2_rsp) or from
    // the AFU.
    t_if_ccip_c2_Tx c2_rsp;
    logic c2_rsp_en;

    always_ff @(posedge clk)
    begin
        to_fiu.sTx.c2 <= (c2_rsp_en ? c2_rsp : to_afu.sTx.c2);
    end


    //
    // Write address control
    //
    logic wen;
    logic [$clog2(N_ENTRIES)-1 : 0] waddr;
    logic [$clog2(N_ENTRIES)-1 : 0] waddr_ring;
    logic wr_wrapped;
    logic wr_locked;

    // Write when new data arrives unless in ring mode and all entries
    // were already written.
    assign wen = wr_en && !wr_locked && (!wr_wrapped ||
                                         (WRITE_ONCE == 0) ||
                                         (RING_MODE == 0));
    // Address is either next index in ring mode or wr_idx if user specified.
    assign waddr = ((RING_MODE == 0) ? wr_idx : waddr_ring);

    always_ff @(posedge clk)
    begin
        if (wen)
        begin
            wr_wrapped <= wr_wrapped || (&(waddr_ring) == 1'b1);
            waddr_ring <= waddr_ring + 1;
        end

        if (!reset_n || history_reset)
        begin
            wr_wrapped <= 1'b0;
            waddr_ring <= 0;
        end
    end


    //
    // Buffer
    //
    logic [$clog2(N_ENTRIES)-1 : 0] raddr;
    logic [DATA_WIDTH-1 : 0] rdata;

    ofs_plat_prim_ram_simple_init
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(DATA_WIDTH),
        .N_OUTPUT_REG_STAGES(1),
        .REGISTER_WRITES(1),
        .BYPASS_REGISTERED_WRITES(0),
        .INIT_VALUE(DATA_WIDTH'(64'haaaaaaaaaaaaaaaa))
        )
      mem
       (
        .clk,
        .reset_n(reset_n && !history_reset),
        .rdy(mem_rdy),

        .wen,
        .waddr,
        .wdata(wr_data),

        .raddr,
        .rdata
        );


    // ====================================================================
    //
    // Detect and respond to MMIO reads.
    //
    // ====================================================================

    t_if_ccip_c0_Rx c0Rx;
    t_ccip_c0_ReqMmioHdr c0Rx_mmio_hdr;
    logic c0Rx_is_hist_mmio_rd, c0Rx_is_hist_mmio_wr;

    logic is_mmio_rd;
    logic is_mmio_rd_q;
    logic is_mmio_rd_qq;
    t_ccip_mmioAddr mmio_rd_addr;
    t_ccip_tid mmio_rd_tid;

    localparam MMIO_ADDR_START = (MMIO_BASE_ADDR >> 2);
    localparam MMIO_ADDR_END   = (MMIO_BASE_ADDR +
                                  N_ENTRIES * (MMIO_REG_WIDTH / 8)) >> 2;

    // A new MMIO request to the managed history buffer?
    assign c0Rx_is_hist_mmio_rd = (c0Rx.mmioRdValid &&
                                   (c0Rx_mmio_hdr.address >= MMIO_ADDR_START) &&
                                   (c0Rx_mmio_hdr.address < MMIO_ADDR_END));
    assign c0Rx_is_hist_mmio_wr = (c0Rx.mmioWrValid &&
                                   (c0Rx_mmio_hdr.address >= MMIO_ADDR_START) &&
                                   (c0Rx_mmio_hdr.address < MMIO_ADDR_END));

    always_ff @(posedge clk)
    begin
        c0Rx <= to_fiu.sRx.c0;
        c0Rx_mmio_hdr <= t_ccip_c0_ReqMmioHdr'(to_fiu.sRx.c0.hdr);

        // Forward most c0Rx traffic to the AFU
        to_afu.sRx.c0 <= c0Rx;
        if (c0Rx_is_hist_mmio_rd)
        begin
            to_afu.sRx.c0.mmioRdValid <= 1'b0;
        end
        if (c0Rx_is_hist_mmio_wr)
        begin
            to_afu.sRx.c0.mmioWrValid <= 1'b0;
        end
    end

    // Writing anything to the start address triggers a reset
    always_ff @(posedge clk)
    begin
        history_reset <= c0Rx.mmioWrValid && (c0Rx_mmio_hdr.address == MMIO_ADDR_START);
    end

    always_ff @(posedge clk)
    begin
        // A new read?  The code assumes at most one read to the buffer is
        // active, so doesn't check that a read is active.
        if (c0Rx_is_hist_mmio_rd)
        begin
            is_mmio_rd <= 1'b1;
            mmio_rd_addr <= c0Rx_mmio_hdr.address - t_ccip_mmioAddr'(MMIO_ADDR_START);
            mmio_rd_tid <= c0Rx_mmio_hdr.tid;

            // Lock writes after first read?
            wr_locked <= (LOCK_WRITES_AFTER_READ ? 1'b1 : 1'b0);
        end

        // Read data available after 2 cycles.  The read will remain active
        // until the response to the host is generated.
        is_mmio_rd_q <= is_mmio_rd;
        is_mmio_rd_qq <= is_mmio_rd_q;

        if (!reset_n || c2_rsp_en)
        begin
            is_mmio_rd <= 1'b0;
            is_mmio_rd_q <= 1'b0;
            is_mmio_rd_qq <= 1'b0;
        end

        if (!reset_n || history_reset)
        begin
            wr_locked <= 1'b0;
        end
    end

    // Read history buffer
    always_comb
    begin
        raddr = mmio_rd_addr[(MMIO_REG_WIDTH / 32)-1 +: $bits(raddr)];

        if (RING_MODE != 0)
        begin
            // Read address is relative to the newest entry in ring mode
            raddr = waddr_ring - 1 - raddr;
        end
    end

    // Respond when ready and no afu response is active
    assign c2_rsp_en = is_mmio_rd_qq && !to_afu.sTx.c2.mmioRdValid;
    always_comb
    begin
        c2_rsp.mmioRdValid = 1'b1;
        c2_rsp.hdr.tid = mmio_rd_tid;
        c2_rsp.data = t_ccip_mmioData'(rdata);
    end

endmodule // ofs_plat_shim_ccip_dbg_history
