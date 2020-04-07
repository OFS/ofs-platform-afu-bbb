//
// Copyright (c) 2019, Intel Corporation
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
// Export a platform host_chan interface to an AFU as CCI-P.
//
// The "as CCI-P" abstraction here allows an AFU to request the host connection
// using a particular interface. The platform may offer multiple interfaces
// to the same underlying PR wires, instantiating protocol conversion
// shims as needed.
//

//
// This version of ofs_plat_host_chan_as_ccip works only on platforms
// where the native interface is Avalon split read/write.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_xGROUPx_as_ccip
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset pair passed in afu_clk/afu_reset.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0,

    // These are present so the interface is consistent across native
    // interfaces. The Avalon native interface is already sorted, so
    // the parameters will be ignored.
    parameter SORT_READ_RESPONSES = 0,
    parameter SORT_WRITE_RESPONSES = 0
    )
   (
    ofs_plat_avalon_mem_rdwr_if.to_slave to_fiu,
    ofs_plat_host_ccip_if.to_afu to_afu,

    // AFU CCI-P clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk
    );

    import ofs_plat_ccip_if_funcs_pkg::*;

    //
    // Apply clock crossing and register stages to the FIU Avalon interface.
    //
    ofs_plat_avalon_mem_rdwr_if
      #(
        `OFS_PLAT_AVALON_MEM_RDWR_IF_REPLICATE_MEM_PARAMS(to_fiu),
        .BURST_CNT_WIDTH(3)
        )
      afu_avmm_if();

    //
    // Use the base native Avalon to Avalon mapper to instantiate clock crossing
    // and register stages, if requested.
    //
    ofs_plat_host_chan_xGROUPx_as_avalon_mem
      #(
        .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
        .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
        )
      avmm
       (
        .to_fiu,
        .host_mem_to_afu(afu_avmm_if),
        .afu_clk
        );

    wire clk;
    assign clk = afu_avmm_if.clk;
    assign to_afu.clk = clk;

    logic reset;
    assign reset = afu_avmm_if.reset;
    assign to_afu.reset = reset;


    //
    // CCI-P reads (c0)
    //
    localparam C0_TRACKER_DEPTH = ccip_xGROUPx_cfg_pkg::C0_MAX_BW_ACTIVE_LINES[0];

    t_if_ccip_c0_Tx afu_c0Tx;
    logic afu_c0Tx_notEmpty;
    logic afu_c0Tx_deq_en;
    logic afu_c0Tx_tracker_notFull;

    // Buffer AFU-generated requests to satisfy the CCI-P almostFull protocol
    ofs_plat_prim_fifo_lutram
      #(
        .N_DATA_BITS($bits(t_if_ccip_c0_Tx)),
        .N_ENTRIES(CCIP_TX_ALMOST_FULL_THRESHOLD + 4),
        .THRESHOLD(CCIP_TX_ALMOST_FULL_THRESHOLD),
        .REGISTER_OUTPUT(1)
        )
      fifo_c0_in
       (
        .clk,
        .reset,
        .enq_data(to_afu.sTx.c0),
        .enq_en(to_afu.sTx.c0.valid),
        .notFull(),
        .almostFull(to_afu.sRx.c0TxAlmFull),
        .first(afu_c0Tx),
        .deq_en(afu_c0Tx_deq_en),
        .notEmpty(afu_c0Tx_notEmpty)
        );

    // Map CCI-P read request to AVMM request
    assign afu_avmm_if.rd_read = afu_c0Tx_notEmpty && afu_c0Tx_tracker_notFull;
    assign afu_c0Tx_deq_en = afu_avmm_if.rd_read && ! afu_avmm_if.rd_waitrequest;

    always_comb
    begin
        afu_avmm_if.rd_address = afu_c0Tx.hdr.address;
        afu_avmm_if.rd_burstcount = 3'(afu_c0Tx.hdr.cl_len) + 3'b1;
        afu_avmm_if.rd_byteenable = ~'0;
        afu_avmm_if.rd_function = '0;
    end

    // Track read bursts in flight, required to fill in CCI-P details in responses
    logic afu_c0Rx_deq_en;
    t_ccip_clLen afu_c0Rx_cl_len;
    t_ccip_mdata afu_c0Rx_mdata;

    ofs_plat_prim_fifo_bram
      #(
        .N_DATA_BITS($bits(t_ccip_clLen) + $bits(t_ccip_mdata)),
        .N_ENTRIES(C0_TRACKER_DEPTH)
        )
      fifo_c0_track
       (
        .clk,
        .reset,
        .enq_data({ afu_c0Tx.hdr.cl_len, afu_c0Tx.hdr.mdata }),
        .enq_en(afu_c0Tx_deq_en),
        .notFull(afu_c0Tx_tracker_notFull),
        .almostFull(),
        .first({ afu_c0Rx_cl_len, afu_c0Rx_mdata }),
        .deq_en(afu_c0Rx_deq_en),
        .notEmpty()
        );

    // Read responses
    t_ccip_clNum afu_c0Rx_cl_num;

    // Pop the oldest tracker entry when all response flits for the packet
    // are processed.
    assign afu_c0Rx_deq_en = afu_avmm_if.rd_readdatavalid &&
                             (afu_c0Rx_cl_num == t_ccip_clNum'(afu_c0Rx_cl_len));

    // Map Avalon read responses back to AFU CCI-P responses
    always_ff @(posedge clk)
    begin
        to_afu.sRx.c0.rspValid <= afu_avmm_if.rd_readdatavalid;
        to_afu.sRx.c0.data <= afu_avmm_if.rd_readdata;

        to_afu.sRx.c0.hdr <= '0;
        to_afu.sRx.c0.hdr.cl_num <= afu_c0Rx_cl_num;
        to_afu.sRx.c0.hdr.mdata <= afu_c0Rx_mdata;

        // MMIO not supported
        to_afu.sRx.c0.mmioRdValid <= 1'b0;
        to_afu.sRx.c0.mmioWrValid <= 1'b0;

        if (afu_c0Rx_deq_en)
        begin
            // Finished the current packet
            afu_c0Rx_cl_num <= t_ccip_clNum'(0);
        end
        else if (afu_avmm_if.rd_readdatavalid)
        begin
            afu_c0Rx_cl_num <= afu_c0Rx_cl_num + t_ccip_clNum'(1);
        end

        if (reset)
        begin
            to_afu.sRx.c0.rspValid <= 1'b0;
            afu_c0Rx_cl_num <= t_ccip_clNum'(0);
        end
    end


    //
    // CCI-P writes (c1)
    //
    localparam C1_TRACKER_DEPTH = ccip_xGROUPx_cfg_pkg::C1_MAX_BW_ACTIVE_LINES[0];

    t_if_ccip_c1_Tx afu_c1Tx;
    logic afu_c1Tx_notEmpty;
    logic afu_c1Tx_deq_en;
    logic afu_c1Tx_tracker_notFull;
    t_ccip_clByteIdx afu_c1Tx_byte_end;

    // Buffer AFU-generated requests to satisfy the CCI-P almostFull protocol.
    // The sum of byte_start and byte_len is computed on entry to the FIFO
    // because it will be needed in a critical path later.
    ofs_plat_prim_fifo_lutram
      #(
        .N_DATA_BITS($bits(t_ccip_clByteIdx) + $bits(t_if_ccip_c1_Tx)),
        .N_ENTRIES(CCIP_TX_ALMOST_FULL_THRESHOLD + 4),
        .THRESHOLD(CCIP_TX_ALMOST_FULL_THRESHOLD),
        .REGISTER_OUTPUT(1)
        )
      fifo_c1_in
       (
        .clk,
        .reset,
        .enq_data({ to_afu.sTx.c1.hdr.byte_start + to_afu.sTx.c1.hdr.byte_len,
                    to_afu.sTx.c1 }),
        .enq_en(to_afu.sTx.c1.valid),
        .notFull(),
        .almostFull(to_afu.sRx.c1TxAlmFull),
        .first({ afu_c1Tx_byte_end, afu_c1Tx }),
        .deq_en(afu_c1Tx_deq_en),
        .notEmpty(afu_c1Tx_notEmpty)
        );

    // Convert CCI-P start/end byte mask to Avalon byteenable
    logic [CCIP_CLDATA_BYTE_WIDTH-1 : 0] afu_c1Tx_byteenable;

    ofs_plat_utils_ccip_gen_bmask c1_bmask
       (
        .byte_start(afu_c1Tx.hdr.byte_start),
        .byte_start_plus_len(afu_c1Tx_byte_end),
        .bmask(afu_c1Tx_byteenable)
        );

    // Map CCI-P write request to AVMM request
    assign afu_avmm_if.wr_write = afu_c1Tx_notEmpty && afu_c1Tx_tracker_notFull;
    assign afu_c1Tx_deq_en = afu_avmm_if.wr_write && ! afu_avmm_if.wr_waitrequest;

    always_comb
    begin
        afu_avmm_if.wr_writedata = afu_c1Tx.data;
        afu_avmm_if.wr_address = afu_c1Tx.hdr.address;
        afu_avmm_if.wr_burstcount = 3'(afu_c1Tx.hdr.cl_len) + 3'b1;
        afu_avmm_if.wr_byteenable = afu_c1Tx.hdr.mode ? afu_c1Tx_byteenable : ~'0;

        afu_avmm_if.wr_function = '0;
        if (afu_c1Tx.hdr.req_type == eREQ_WRFENCE)
        begin
            // Use AVMM special fence encoding
            afu_avmm_if.wr_address = '0;
            afu_avmm_if.wr_function = 1'b1;
        end
    end

    // Track in-flight state that will be needed to fill in CCI-P responses.
    logic afu_c1_track_enq_en;
    logic afu_c1Rx_deq_en;
    logic afu_c1Rx_isFence;
    t_ccip_clNum afu_c1Rx_cl_num;
    t_ccip_mdata afu_c1Rx_mdata;

    // Track write bursts, not individual flits
    assign afu_c1_track_enq_en =
        afu_c1Tx_deq_en &&
        (afu_c1Tx.hdr.sop || (afu_c1Tx.hdr.req_type == eREQ_WRFENCE));

    ofs_plat_prim_fifo_bram
      #(
        .N_DATA_BITS(1 + $bits(t_ccip_clNum) + $bits(t_ccip_mdata)),
        .N_ENTRIES(C1_TRACKER_DEPTH)
        )
      fifo_c1_track
       (
        .clk,
        .reset,
        .enq_data({ afu_c1Tx.hdr.req_type == eREQ_WRFENCE,
                    t_ccip_clNum'(afu_c1Tx.hdr.cl_len),
                    afu_c1Tx.hdr.mdata }),
        .enq_en(afu_c1_track_enq_en),
        .notFull(afu_c1Tx_tracker_notFull),
        .almostFull(),
        .first({ afu_c1Rx_isFence, afu_c1Rx_cl_num, afu_c1Rx_mdata }),
        .deq_en(afu_c1Rx_deq_en),
        .notEmpty()
        );

    // Write responses. AVMM gives a single response for a burst.
    assign afu_c1Rx_deq_en = afu_avmm_if.wr_writeresponsevalid;

    always_ff @(posedge clk)
    begin
        to_afu.sRx.c1.rspValid <= afu_avmm_if.wr_writeresponsevalid;

        to_afu.sRx.c1.hdr <= '0;
        to_afu.sRx.c1.hdr.format <= 1'b1;
        to_afu.sRx.c1.hdr.cl_num <= afu_c1Rx_cl_num;
        to_afu.sRx.c1.hdr.resp_type <= afu_c1Rx_isFence ? eRSP_WRFENCE : eRSP_WRLINE;
        to_afu.sRx.c1.hdr.mdata <= afu_c1Rx_mdata;

        if (reset)
        begin
            to_afu.sRx.c1.rspValid <= 1'b0;
        end
    end


    //
    // MMIO read response (c2)
    //

    // synthesis translate_off
    always_ff @(posedge clk)
    begin
        if (! reset && to_afu.sTx.c2.mmioRdValid)
            $fatal(2, "** ERROR ** %m: MMIO read not supported in native AVMM host channels!");
    end
    // synthesis translate_on

endmodule // ofs_plat_host_chan_xGROUPx_as_ccip
