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

`define RESET_FROM_CLK(clk) clk``_reset_n

module ofs_plat_afu
   (
    // All platform wires, wrapped in one interface.
    ofs_plat_if plat_ifc
    );

    // ====================================================================
    //
    //  Get an Avalon host channel collection from the platform.
    //
    // ====================================================================

    // Host memory AFU master
    ofs_plat_avalon_mem_rdwr_if
      #(
        `HOST_CHAN_AVALON_MEM_RDWR_PARAMS,
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

    ofs_plat_host_chan_as_avalon_mem_rdwr_with_mmio
      #(
        .ADD_CLOCK_CROSSING(1),
        .ADD_TIMING_REG_STAGES(1)
        )
      primary_avalon
       (
        .to_fiu(plat_ifc.host_chan.ports[0]),
        .host_mem_to_afu,
        .mmio_to_afu(mmio64_to_afu),

`ifdef TEST_PARAM_AFU_CLK
        .afu_clk(`TEST_PARAM_AFU_CLK),
        .afu_reset_n(`RESET_FROM_CLK(`TEST_PARAM_AFU_CLK))
`else
        .afu_clk(plat_ifc.clocks.uClk_usr),
        .afu_reset_n(plat_ifc.clocks.uClk_usr_reset_n)
`endif
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

`ifdef TEST_PARAM_BURST_CNT_WIDTH_DELTA
    localparam LM_BURST_CNT_WIDTH = local_mem_cfg_pkg::LOCAL_MEM_BURST_CNT_WIDTH +
                                    `TEST_PARAM_BURST_CNT_WIDTH_DELTA;
`else
    localparam LM_BURST_CNT_WIDTH = local_mem_cfg_pkg::LOCAL_MEM_BURST_CNT_WIDTH;
`endif

    ofs_plat_avalon_mem_if
      #(
        .LOG_CLASS(ofs_plat_log_pkg::LOCAL_MEM),
`ifndef TEST_FULL_LOCAL_MEM_BUS
        `LOCAL_MEM_AVALON_MEM_PARAMS,
`else
        `LOCAL_MEM_AVALON_MEM_PARAMS_FULL_BUS,
`endif
        .BURST_CNT_WIDTH(LM_BURST_CNT_WIDTH)
        )
      local_mem_to_afu[local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS]();

`ifdef TEST_PARAM_AFU_CLK_MGMT
    // AFU manages clock crossing
    localparam AUTO_CLOCK_CROSSING = 0;
`else
    // PIM manages clock crossing
    localparam AUTO_CLOCK_CROSSING = 1;
`endif

    // Map each bank individually
    genvar b;
    generate
        for (b = 0; b < local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS; b = b + 1)
        begin : mb
            if (AUTO_CLOCK_CROSSING)
            begin
                // Handle the clock crossing in the OFS module.
                ofs_plat_local_mem_as_avalon_mem
                  #(
                    .ADD_CLOCK_CROSSING(1),
                    // Vary the number of register stages for testing.
                    .ADD_TIMING_REG_STAGES(b)
                    )
                  shim
                   (
                    .afu_clk(host_mem_to_afu.clk),
                    .afu_reset_n(host_mem_to_afu.reset_n),
                    .to_fiu(plat_ifc.local_mem.banks[b]),
                    .to_afu(local_mem_to_afu[b])
                    );
            end
            else
            begin
                // Don't use the OFS-provided clock crossing. We still
                // need a clock crossing, but the test here confirms that
                // ofs_plat_local_mem_as_avalon_mem() does the right thing
                // when not crossing.
                ofs_plat_avalon_mem_if
                  #(
                    `LOCAL_MEM_AVALON_MEM_PARAMS,
                    .BURST_CNT_WIDTH(LM_BURST_CNT_WIDTH)
                    )
                  local_mem_if();

                ofs_plat_local_mem_as_avalon_mem
                  #(
                    .ADD_CLOCK_CROSSING(0),
                    // Vary the number of register stages for testing.
                    .ADD_TIMING_REG_STAGES(b)
                    )
                  shim
                   (
                    .afu_clk(host_mem_to_afu.clk),
                    .afu_reset_n(host_mem_to_afu.reset_n),
                    .to_fiu(plat_ifc.local_mem.banks[b]),
                    .to_afu(local_mem_if)
                    );

                //
                // The rest of the code here consumes the PIM-generated Avalon
                // interface. It adds a clock crossing and some buffering. The
                // test uses the PIM modules because they are available, though
                // AFU designers are free to use non-PIM equivalent modules.
                //

                // Manage the clock crossing
                ofs_plat_avalon_mem_if
                  #(
                    `LOCAL_MEM_AVALON_MEM_PARAMS,
                    .BURST_CNT_WIDTH(LM_BURST_CNT_WIDTH)
                    )
                  local_mem_cross_if();

                assign local_mem_cross_if.clk = host_mem_to_afu.clk;
                assign local_mem_cross_if.instance_number = local_mem_if.instance_number;

                // Synchronize a reset with the target clock
                ofs_plat_prim_clock_crossing_reset
                  reset_cc
                   (
                    .clk_src(local_mem_if.clk),
                    .clk_dst(local_mem_cross_if.clk),
                    .reset_in(local_mem_if.reset_n),
                    .reset_out(local_mem_cross_if.reset_n)
                    );

                // Clock crossing
                ofs_plat_avalon_mem_if_async_shim
                  mem_async_shim
                   (
                    .mem_slave(local_mem_if),
                    .mem_master(local_mem_cross_if)
                    );

                // Add register stages for timing
                ofs_plat_avalon_mem_if_reg_slave_clk
                  #(
                    .N_REG_STAGES(2)
                    )
                  mem_pipe
                   (
                    .mem_slave(local_mem_cross_if),
                    .mem_master(local_mem_to_afu[b])
                    );
            end
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
