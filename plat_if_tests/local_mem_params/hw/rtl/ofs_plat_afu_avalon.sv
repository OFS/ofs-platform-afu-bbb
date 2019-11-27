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
// Export local memory as Avalon interfaces.
//

`include "ofs_plat_if.vh"

module ofs_plat_afu
   (
    // All platform wires, wrapped in one interface.
    ofs_plat_if plat_ifc
    );

    //
    // Drive the AFU with the clock from the first memory bank by default.
    // 
    logic afu_clk;
`ifdef TEST_PARAM_AFU_CLK
    assign afu_clk = `TEST_PARAM_AFU_CLK;
    localparam USE_DEFAULT_CLOCK = 0;
`else
    assign afu_clk = plat_ifc.local_mem.banks[0].clk;
    localparam USE_DEFAULT_CLOCK = 1;
`endif

    // ====================================================================
    //
    //  Get an Avalon host channel collection from the platform.
    //
    // ====================================================================

    // Host memory AFU master
    ofs_plat_avalon_mem_rdwr_if
      #(
        `HOST_CHAN_AVALON_MEM_PARAMS,
        .BURST_CNT_WIDTH(1)
        )
        host_mem_to_afu();

    // 64 bit read/write MMIO AFU slave
    ofs_plat_avalon_mem_if
      #(
        `HOST_CHAN_AVALON_MMIO_PARAMS(64),
        .LOG_CLASS(ofs_plat_log_pkg::HOST_CHAN)
        )
        mmio64_to_afu();

    ofs_plat_host_chan_as_avalon_mem_with_mmio
      #(
        .ADD_CLOCK_CROSSING(1),
        .ADD_TIMING_REG_STAGES(1)
        )
      primary_avalon
       (
        .to_fiu(plat_ifc.host_chan.ports[0]),
        .host_mem_to_afu,
        .mmio_to_afu(mmio64_to_afu),

        .afu_clk
        );

    // Not using host memory
    assign host_mem_to_afu.rd_read = 1'b0;
    assign host_mem_to_afu.wr_write = 1'b0;


    // ====================================================================
    //
    //  Map pwrState to the AFU clock domain
    //
    // ====================================================================

    t_ofs_plat_power_state afu_pwrState;

    ofs_plat_prim_clock_crossing_reg
      #(
        .WIDTH($bits(t_ofs_plat_power_state))
        )
      map_pwrState
       (
        .clk_src(plat_ifc.clocks.pClk),
        .clk_dst(host_mem_to_afu.clk),
        .r_in(plat_ifc.pwrState),
        .r_out(afu_pwrState)
        );


    // ====================================================================
    //
    //  Get local memory from the platform.
    //
    // ====================================================================

    ofs_plat_avalon_mem_if
      #(
        .LOG_CLASS(ofs_plat_log_pkg::LOCAL_MEM),
        `OFS_PLAT_LOCAL_MEM_AS_AVALON_IF_PARAMS
        )
      local_mem_to_afu[local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS]();

    // Map each bank individually
    genvar b;
    generate
        for (b = 0; b < local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS; b = b + 1)
        begin : mb
            ofs_plat_local_mem_as_avalon_mem
              #(
                // Add a clock crossing unless this is bank 0 and the AFU is
                // using the default (bank 0) clock as the primary clock.
                .ADD_CLOCK_CROSSING(((USE_DEFAULT_CLOCK == 1) && (b == 0)) ? 0 : 1),
                .ADD_TIMING_REG_STAGES(2)
                )
              shim
               (
                .tgt_mem_afu_clk(afu_clk),
                .to_fiu(plat_ifc.local_mem.banks[b]),
                .to_afu(local_mem_to_afu[b])
                );
        end
    endgenerate


    // ====================================================================
    //
    //  Tie off unused ports.
    //
    // ====================================================================

    ofs_plat_if_tie_off_unused
      #(
        // Masks are bit masks, with bit 0 corresponding to port/bank zero.
        // Set a bit in the mask when a port is IN USE by the design.
        // This way, the AFU does not need to know about every available
        // device. By default, devices are tied off.
        .HOST_CHAN_IN_USE_MASK(1),
        // All banks are used
        .LOCAL_MEM_IN_USE_MASK(-1)
        )
        tie_off(plat_ifc);


    // ====================================================================
    //
    //  Pass the constructed interfaces to the AFU.
    //
    // ====================================================================

    afu afu
      (
       .local_mem_g0(local_mem_to_afu),
       .mmio64_if(mmio64_to_afu),
       .pClk(plat_ifc.clocks.pClk),
       .pwrState(afu_pwrState)
       );

endmodule // ofs_plat_afu
