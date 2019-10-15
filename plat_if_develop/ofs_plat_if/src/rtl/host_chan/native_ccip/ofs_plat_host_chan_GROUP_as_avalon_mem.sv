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
// Export a CCI-P native host_chan interface to an AFU as Avalon interfaces.
// There are three Avalon interfaces: host memory master, 64 bit wide MMIO
// (FPGA memory slave) and 512 bit wide write-only MMIO slave. MMIO is
// split in two because CCI-P only supports 512 bit writes, not reads.
//

`include "ofs_plat_if.vh"

module ofs_plat_host_chan_GROUP_as_avalon_mem
  #(
    // When non-zero, add a clock crossing to move the AFU CCI-P
    // interface to the clock/reset pair passed in afu_clk/afu_reset.
    parameter ADD_CLOCK_CROSSING = 0,

    // Add extra pipeline stages to the FIU side, typically for timing.
    // Note that these stages contribute to the latency of receiving
    // almost full and requests in these registers continue to flow
    // when almost full is asserted. Beware of adding too many stages
    // and losing requests on transitions to almost full.
    parameter ADD_TIMING_REG_STAGES = 0
    )
   (
    ofs_plat_host_ccip_if.to_fiu to_fiu,

    ofs_plat_avalon_mem_rdwr_if.to_master host_mem_to_afu,
    ofs_plat_avalon_mem_if.to_slave mmio64_to_afu,
    ofs_plat_avalon_mem_if.to_slave mmio512_wr_to_afu,

    // AFU CCI-P clock, used only when the ADD_CLOCK_CROSSING parameter
    // is non-zero.
    input  logic afu_clk,

    // Map pwrState to the target clock domain.
    input  t_ofs_plat_power_state fiu_pwrState,
    output t_ofs_plat_power_state afu_pwrState
    );

    //
    // Transform native CCI-P signals to the AFU's requested clock domain.
    //
    ofs_plat_host_ccip_if std_ccip_if();
    ofs_plat_host_chan_GROUP_as_ccip
     #(
       .ADD_CLOCK_CROSSING(ADD_CLOCK_CROSSING),
       .ADD_TIMING_REG_STAGES(ADD_TIMING_REG_STAGES)
       )
     afu_ccip
       (
        .to_fiu(to_fiu),
        .to_afu(std_ccip_if),
        .afu_clk,
        .fiu_pwrState,
        .afu_pwrState
        );

    //
    // Later stages depend on CCI-P write responses always being packed: a
    // single write response per multi-line write request. Make sure that
    // is true.
    //
    ofs_plat_host_ccip_if eop_ccip_if();
    ofs_plat_shim_ccip_detect_eop
      #(
        .MAX_ACTIVE_WR_REQS(ccip_GROUP_cfg_pkg::C1_MAX_BW_ACTIVE_LINES[0])
        )
      eop
       (
        .to_fiu(std_ccip_if),
        .to_afu(eop_ccip_if)
        );

    //
    // Sort write responses.
    //
    ofs_plat_host_ccip_if rob_wr_ccip_if();
    ofs_plat_shim_ccip_rob_wr
      #(
        .MAX_ACTIVE_WR_REQS(ccip_GROUP_cfg_pkg::C1_MAX_BW_ACTIVE_LINES[0])
        )
      rob_wr
       (
        .to_fiu(eop_ccip_if),
        .to_afu(rob_wr_ccip_if)
        );

    //
    // Sort read responses.
    //
    ofs_plat_host_ccip_if#(.LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)) sorted_ccip_if();
    ofs_plat_shim_ccip_rob_rd
      #(
        .MAX_ACTIVE_RD_REQS(ccip_GROUP_cfg_pkg::C0_MAX_BW_ACTIVE_LINES[0])
        )
      rob_rd
       (
        .to_fiu(rob_wr_ccip_if),
        .to_afu(sorted_ccip_if)
        );


    //
    // Now we can map to Avalon.
    //
    ofs_plat_host_chan_GROUP_map_avalon_host_mem av_host_mem
       (
        .clk(sorted_ccip_if.clk),
        .reset(sorted_ccip_if.reset),
        .sRx(sorted_ccip_if.sRx),
        .c0Tx(sorted_ccip_if.sTx.c0),
        .c1Tx(sorted_ccip_if.sTx.c1),
        .host_mem_to_afu
        );

    ofs_plat_host_chan_GROUP_map_avalon_mmio av_host_mmio
       (
        .clk(sorted_ccip_if.clk),
        .reset(sorted_ccip_if.reset),
        .sRx(sorted_ccip_if.sRx),
        .c2Tx(sorted_ccip_if.sTx.c2),
        .mmio64_to_afu,
        .mmio512_wr_to_afu
        );

endmodule // ofs_plat_host_chan_GROUP_as_avalon_mem


module ofs_plat_host_chan_GROUP_map_avalon_host_mem
   (
    input  logic clk,
    input  logic reset,
    input  t_if_ccip_Rx sRx,
    output t_if_ccip_c0_Tx c0Tx,
    output t_if_ccip_c1_Tx c1Tx,

    ofs_plat_avalon_mem_rdwr_if.to_master host_mem_to_afu
    );

    assign host_mem_to_afu.clk = clk;
    assign host_mem_to_afu.reset = reset;
    assign host_mem_to_afu.instance_number = 0;

    assign c0Tx = t_if_ccip_c0_Tx'(0);
    assign c1Tx = t_if_ccip_c1_Tx'(0);

    assign host_mem_to_afu.wr_waitrequest = 1'b0;
    assign host_mem_to_afu.wr_response = 2'b0;
    assign host_mem_to_afu.wr_writeresponsevalid = 2'b0;
    assign host_mem_to_afu.rd_waitrequest = 1'b0;
    assign host_mem_to_afu.rd_response = 2'b0;
    assign host_mem_to_afu.rd_readdatavalid = 2'b0;

endmodule // ofs_plat_host_chan_GROUP_map_avalon_host_mem


module ofs_plat_host_chan_GROUP_map_avalon_mmio
   (
    input  logic clk,
    input  logic reset,
    input  t_if_ccip_Rx sRx,
    output t_if_ccip_c2_Tx c2Tx,

    ofs_plat_avalon_mem_if.to_slave mmio64_to_afu,
    ofs_plat_avalon_mem_if.to_slave mmio512_wr_to_afu
    );

    // Cast c0 header into ReqMmioHdr
    t_ccip_c0_ReqMmioHdr mmio_in_hdr;
    assign mmio_in_hdr = t_ccip_c0_ReqMmioHdr'(sRx.c0.hdr);

    logic error;

    //
    // Send MMIO requests through a buffering FIFO in case the AFU's MMIO slave
    // asserts waitrequest. The FIU guarantees that no more than 64 requests will
    // be outstanding.
    //
    logic req_in_fifo_notFull;
    logic mmio_is_wr;
    t_ccip_clData mmio_wr_data;
    t_ccip_c0_ReqMmioHdr mmio_hdr;
    logic mmio_req_deq;
    logic mmio_req_notEmpty;

    ofs_plat_prim_fifo_bram
      #(
        // Simply push the whole data structure and wide data through the FIFO.
        // Quartus will remove the parts that wind up not being used.
        .N_DATA_BITS(1 + $bits(t_ccip_clData) + $bits(t_ccip_c0_ReqMmioHdr)),
        .N_ENTRIES(64)
        )
      req_in_fifo
       (
        .clk,
        .reset,
        .enq_data({ sRx.c0.mmioWrValid, sRx.c0.data, mmio_in_hdr }),
        .enq_en((sRx.c0.mmioRdValid || sRx.c0.mmioWrValid) && ! error),
        .notFull(req_in_fifo_notFull),
        .almostFull(),
        .first({ mmio_is_wr, mmio_wr_data, mmio_hdr }),
        .deq_en(mmio_req_deq),
        .notEmpty(mmio_req_notEmpty)
        );

    //
    // Save tid for MMIO read requests. It will be needed when generating the
    // response. Avalon slave responses will be returned in request order.
    //
    logic tid_in_fifo_notFull;
    t_ccip_tid mmio_tid;
    logic mmio_high32;

    ofs_plat_prim_fifo_bram
      #(
        .N_DATA_BITS(1 + $bits(t_ccip_tid)),
        .N_ENTRIES(64)
        )
      tid_in_fifo
       (
        .clk,
        .reset,
        // High bit indicates need to fetch 32 bit response from high half
        .enq_data({ (! mmio_in_hdr.length[0] && mmio_in_hdr.address[0]), mmio_in_hdr.tid }),
        .enq_en(sRx.c0.mmioRdValid && ! mmio_in_hdr.length[1] && ! error),
        .notFull(tid_in_fifo_notFull),
        .almostFull(),
        .first({ mmio_high32, mmio_tid }),
        .deq_en(mmio64_to_afu.readdatavalid),
        // Must not be empty
        .notEmpty()
        );

    //
    // Ingress FIFO overflow check
    //
    always_ff @(posedge clk)
    begin
        if (((sRx.c0.mmioRdValid || sRx.c0.mmioWrValid) && ! req_in_fifo_notFull) ||
            (sRx.c0.mmioRdValid && ! tid_in_fifo_notFull))
        begin
            error <= 1'b1;
        end

        if (reset)
        begin
            error <= 1'b0;
        end
    end

    //
    // Generate requests to the 64 bit slave.
    //
    assign mmio64_to_afu.write = mmio_req_notEmpty && ! mmio_hdr.length[1] && mmio_is_wr;
    assign mmio64_to_afu.read = mmio_req_notEmpty && ! mmio_hdr.length[1] && ! mmio_is_wr;
    assign mmio64_to_afu.burstcount = 1;
    assign mmio64_to_afu.writedata = mmio_wr_data[63:0];

    // Drop low address bit. CCI-P addresses 32 bit chunks and the Avalon interface
    // addresses 64 bit chunks. The low address bit will be reflected in byteenable.
    assign mmio64_to_afu.address = mmio_hdr.address[$bits(t_ccip_mmioAddr)-1 : 1];
    assign mmio64_to_afu.byteenable =
        (mmio_hdr.length[0] ? 8'b11111111 :
                              (mmio_hdr.address[0] ? 8'b11110000 : 8'b00001111));

    // Consume requests once they are accepted by the Avalon slave.
    assign mmio_req_deq = ! mmio64_to_afu.waitrequest && mmio_req_notEmpty;

    //
    // Forward read responses back to CCI-P.
    //
    always_ff @(posedge clk)
    begin
        c2Tx.mmioRdValid <= mmio64_to_afu.readdatavalid;
        c2Tx.hdr.tid <= mmio_tid;

        c2Tx.data <= mmio64_to_afu.readdata;
        if (mmio_high32)
        begin
            c2Tx.data[31:0] <= mmio64_to_afu.readdata[63:32];
        end

        if (reset)
        begin
            c2Tx.mmioRdValid <= 1'b0;
        end
    end

endmodule // ofs_plat_host_chan_GROUP_map_avalon_mmio
