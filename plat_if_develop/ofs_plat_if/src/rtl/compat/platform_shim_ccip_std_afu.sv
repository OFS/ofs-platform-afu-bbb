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


// ========================================================================
//
// Compatibility module that maps the ofs_plat_if to the ccip_std_afu()
// interface configured by version 1 of the OPAE Platform Interface
// Manager.
//
// Perhaps unsurprisingly, the logic here looks very similar to a
// standard ofs_plat_afu() top-level module.
//
// ========================================================================

`include "platform_if.vh"

//
// If these macros are missing the compilation is not in compatibility
// mode and platform_shim_ccip_std_afu won't be used. Skip this module
// to avoid compilation failure.
//
`ifndef PLATFORM_PARAM_CCI_P_CLOCK
  `ifndef PLATFORM_PARAM_CCI_P_CLOCK_IS_DEFAULT
    `define DISABLE_PLATFORM_SHIM_CCIP_STD_AFU 1
  `endif
`endif


`ifndef DISABLE_PLATFORM_SHIM_CCIP_STD_AFU

//
// Start with a simple wrapper that extracts hssi ports with the
// name used in the v1 PIM. Some AFUs specify clocks using the hssi
// naming.
//
module platform_shim_ccip_std_afu
   (
    // All platform wires, wrapped in one interface.
    ofs_plat_if plat_ifc
    );

`ifdef AFU_TOP_REQUIRES_LOCAL_MEMORY_AVALON_MM
    // Avalon memory interface vector
    localparam NUM_LOCAL_MEM_BANKS = `AFU_TOP_REQUIRES_LOCAL_MEMORY_AVALON_MM;
`elsif AFU_TOP_REQUIRES_LOCAL_MEMORY_AVALON_MM_LEGACY_WIRES_2BANK
    // Ancient two port Avalon wire interface
    localparam NUM_LOCAL_MEM_BANKS = 2;
`else
    localparam NUM_LOCAL_MEM_BANKS = 0;
`endif

`ifdef AFU_TOP_REQUIRES_HSSI_RAW_PR
    localparam NUM_HSSI_RAW_PR_IFCS = `AFU_TOP_REQUIRES_HSSI_RAW_PR;
`else
    localparam NUM_HSSI_RAW_PR_IFCS = 0;
`endif

    platform_shim_ccip_std_afu_hssi
      #(
        .NUM_LOCAL_MEM_BANKS(NUM_LOCAL_MEM_BANKS),
        .NUM_HSSI_RAW_PR_IFCS(NUM_HSSI_RAW_PR_IFCS)
        )
      shim
       (
`ifdef AFU_TOP_REQUIRES_HSSI_RAW_PR
  `ifdef PLATFORM_PARAM_HSSI_RAW_PR_IS_VECTOR
        .hssi(plat_ifc.hssi.ports[0:NUM_HSSI_RAW_PR_IFCS-1]),
  `else
        // Legacy hssi interface on a platform with only one HSSI port
        .hssi(plat_ifc.hssi.ports[0]),
  `endif
`endif
        .plat_ifc(plat_ifc)
        );

endmodule // platform_shim_ccip_std_afu


//
// This module exists only to expose the HSSI ports with the port name
// "hssi" in order to make them available as possible sources of clocks
// from AFU JSON specifications. PIM v1 allowed this.
//
module platform_shim_ccip_std_afu_hssi
  #(
    parameter NUM_LOCAL_MEM_BANKS = 0,
    parameter NUM_HSSI_RAW_PR_IFCS = 0
    )
   (
`ifdef AFU_TOP_REQUIRES_HSSI_RAW_PR
  `ifdef PLATFORM_PARAM_HSSI_RAW_PR_IS_VECTOR
    pr_hssi_if.to_fiu hssi[NUM_HSSI_RAW_PR_IFCS],
  `else
    // Legacy hssi interface on a platform with only one HSSI port
    pr_hssi_if.to_fiu hssi,
  `endif
`endif

    // All platform wires, wrapped in one interface.
    ofs_plat_if plat_ifc
    );

    // ====================================================================
    //
    //  Get a CCI-P port from the platform.
    //
    // ====================================================================

    // Instance of a CCI-P interface. The interface wraps usual CCI-P
    // sRx and sTx structs as well as the associated clock and reset.
    ofs_plat_host_ccip_if ccip_to_afu();

    // These names may be in `PLATFORM_PARAM_CCI_P_CLOCK
    logic pClk;
    logic pClkDiv2;
    logic pClkDiv4;
    logic uClk_usr;
    logic uClk_usrDiv2;

    always_comb
    begin
        pClk = plat_ifc.clocks.pClk.clk;
        pClkDiv2 = plat_ifc.clocks.pClkDiv2.clk;
        pClkDiv4 = plat_ifc.clocks.pClkDiv4.clk;
        uClk_usr = plat_ifc.clocks.uClk_usr.clk;
        uClk_usrDiv2 = plat_ifc.clocks.uClk_usrDiv2.clk;
    end

    // Default reset associated with AFU clock
    logic afu_reset_n;
`ifdef PLATFORM_PARAM_CCI_P_CLOCK_IS_DEFAULT
    assign afu_reset_n = plat_ifc.clocks.pClk.reset_n;
`else
    ofs_plat_prim_clock_crossing_reset afu_reset_gen
       (
        .clk_src(plat_ifc.clocks.pClk.clk),
        .clk_dst(`PLATFORM_PARAM_CCI_P_CLOCK),
        .reset_in(plat_ifc.clocks.pClk.reset_n),
        .reset_out(afu_reset_n)
        );
`endif

    // Use the platform-provided module to map the primary host interface
    // to CCI-P. The "primary" interface is the port that includes the
    // main OPAE-managed MMIO connection.
    ofs_plat_host_chan_as_ccip
      #(
`ifndef PLATFORM_PARAM_CCI_P_CLOCK_IS_DEFAULT
        .ADD_CLOCK_CROSSING(1),
`endif
        // Request registered AFU-side signals so that we don't have to
        // register the CCI-P signals in the AFU.
`ifdef PLATFORM_PARAM_CCI_P_ADD_TIMING_REG_STAGES
        .ADD_TIMING_REG_STAGES(`PLATFORM_PARAM_CCI_P_ADD_TIMING_REG_STAGES)
`else
        .ADD_TIMING_REG_STAGES(0)
`endif
        )
      primary_ccip
       (
        .to_fiu(plat_ifc.host_chan.ports[0]),
        .to_afu(ccip_to_afu),

`ifdef PLATFORM_PARAM_CCI_P_CLOCK_IS_DEFAULT
         // Default clock
        .afu_clk(1'b0),
        .afu_reset_n
`else
         // Updated CCI-P clock requested
        .afu_clk(`PLATFORM_PARAM_CCI_P_CLOCK),
        .afu_reset_n
`endif
        );

    t_ofs_plat_power_state afu_pwrState;
    ofs_plat_prim_clock_crossing_reg
      #(
        .WIDTH($bits(t_ofs_plat_power_state))
        )
      map_pwrState
       (
        .clk_src(plat_ifc.clocks.pClk.clk),
        .clk_dst(ccip_to_afu.clk),
        .r_in(plat_ifc.pwrState),
        .r_out(afu_pwrState)
        );

    // ====================================================================
    //
    //  Get local memory from the platform.
    //
    // ====================================================================

`ifdef AFU_TOP_REQUIRES_LOCAL_MEMORY_AVALON_MM
    // Avalon memory interface vector
    `define PLATFORM_SHIM_MAP_LOCAL_MEM 1
`elsif AFU_TOP_REQUIRES_LOCAL_MEMORY_AVALON_MM_LEGACY_WIRES_2BANK
    // Ancient two port Avalon wire interface
    `define PLATFORM_SHIM_MAP_LOCAL_MEM 1
`endif

`ifdef PLATFORM_SHIM_MAP_LOCAL_MEM
    ofs_plat_avalon_mem_if
      #(
        `LOCAL_MEM_AVALON_MEM_PARAMS_DEFAULT
        )
      local_mem_to_afu[NUM_LOCAL_MEM_BANKS]();

    // The compatibility interface to local memory is slightly different,
    // named avalon_mem_if.
    logic local_mem_clk[NUM_LOCAL_MEM_BANKS];
    logic local_mem_reset[NUM_LOCAL_MEM_BANKS];
    avalon_mem_if
      #(
        .ENABLE_LOG(1)
        )
      local_mem_compat[NUM_LOCAL_MEM_BANKS](local_mem_clk, local_mem_reset);

    // One final compatibility effort: define the same clock naming that
    // was present in the OPAE SDK in case the user requested a clock derived
    // from memory in the AFU JSON.
    typedef struct packed
    {
        logic clk;
    } t_clk_struct;
    t_clk_struct local_mem[NUM_LOCAL_MEM_BANKS];

    // Map each bank individually
    genvar b;
    generate
        for (b = 0; b < NUM_LOCAL_MEM_BANKS; b = b + 1)
        begin : mb

            // Generate local memory reset in target clock domain if necessary
`ifndef PLATFORM_PARAM_LOCAL_MEMORY_CLOCK_IS_DEFAULT
            logic local_mem_reset_n;
            ofs_plat_prim_clock_crossing_reset local_mem_reset_gen
               (
                .clk_src(plat_ifc.local_mem.banks[b].clk),
                .clk_dst(`PLATFORM_PARAM_LOCAL_MEMORY_CLOCK),
                .reset_in(plat_ifc.local_mem.banks[b].reset_n),
                .reset_out(local_mem_reset_n)
                );
`endif

            ofs_plat_local_mem_as_avalon_mem
              #(
`ifndef PLATFORM_PARAM_LOCAL_MEMORY_CLOCK_IS_DEFAULT
                .ADD_CLOCK_CROSSING(1),
`endif
`ifdef PLATFORM_PARAM_LOCAL_MEMORY_ADD_TIMING_REG_STAGES
                .ADD_TIMING_REG_STAGES(`PLATFORM_PARAM_LOCAL_MEMORY_ADD_TIMING_REG_STAGES)
`else
                .ADD_TIMING_REG_STAGES(0)
`endif
                )
              shim
               (
`ifdef PLATFORM_PARAM_LOCAL_MEMORY_CLOCK_IS_DEFAULT
                // Not used -- local memory clocks unchanged
                .afu_clk(1'b0),
                .afu_reset_n(),
`else
                // Updated target for local memory clock
                .afu_clk(`PLATFORM_PARAM_LOCAL_MEMORY_CLOCK),
                .afu_reset_n(local_mem_reset_n),
`endif
                .to_fiu(plat_ifc.local_mem.banks[b]),
                .to_afu(local_mem_to_afu[b])
                );

            // Wire mapping to the compatibility interface
            always_comb
            begin
                local_mem[b].clk = plat_ifc.local_mem.banks[b].clk;

                local_mem_clk[b] = local_mem_to_afu[b].clk;
                // Compatibility uses active high reset
                local_mem_reset[b] = !local_mem_to_afu[b].reset_n;
                local_mem_compat[b].bank_number = b;

                local_mem_compat[b].waitrequest = local_mem_to_afu[b].waitrequest;
                local_mem_compat[b].readdata = local_mem_to_afu[b].readdata;
                local_mem_compat[b].readdatavalid = local_mem_to_afu[b].readdatavalid;

                local_mem_to_afu[b].address = local_mem_compat[b].address;
                local_mem_to_afu[b].write = local_mem_compat[b].write;
                local_mem_to_afu[b].read = local_mem_compat[b].read;
                local_mem_to_afu[b].burstcount = local_mem_compat[b].burstcount;
                local_mem_to_afu[b].writedata = local_mem_compat[b].writedata;
                local_mem_to_afu[b].byteenable = local_mem_compat[b].byteenable;
            end
        end
    endgenerate
`endif


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
`ifdef PLATFORM_SHIM_MAP_LOCAL_MEM
        // Mask of banks used
        .LOCAL_MEM_IN_USE_MASK((1 << NUM_LOCAL_MEM_BANKS) - 1),
`endif
`ifdef AFU_TOP_REQUIRES_HSSI_RAW_PR
        // Mask of ports used
        .HSSI_IN_USE_MASK((1 << NUM_HSSI_RAW_PR_IFCS) - 1),
`endif
        .HOST_CHAN_IN_USE_MASK(1)
        )
        tie_off(plat_ifc);


    // ====================================================================
    //
    //  Pass the constructed interfaces to the AFU.
    //
    // ====================================================================

    // Add a timing stage to reset
    logic afu_softReset_q = 1'b1;
    always @(posedge ccip_to_afu.clk)
    begin
        // Compatibility uses active high reset
        afu_softReset_q <= !ccip_to_afu.reset_n;
    end

    `AFU_TOP_MODULE_NAME
      #(
        `PLATFORM_ARG_LIST_BEGIN
`ifdef AFU_TOP_REQUIRES_LOCAL_MEMORY_AVALON_MM
        `PLATFORM_ARG_APPEND(.NUM_LOCAL_MEM_BANKS(NUM_LOCAL_MEM_BANKS))
`endif
`ifdef AFU_TOP_REQUIRES_HSSI_RAW_PR
  `ifdef PLATFORM_PARAM_HSSI_RAW_PR_IS_VECTOR
        `PLATFORM_ARG_APPEND(.NUM_HSSI_RAW_PR_IFCS(NUM_HSSI_RAW_PR_IFCS))
  `endif
`endif
        )
      `AFU_TOP_MODULE_NAME
       (
        // All the clocks are still passed in as usual.  It is the responsibility
        // of the AFU to pick the right clock for CCI-P traffic if CCI-P is now
        // running on something other than pClk.  Ideally, we would change the
        // name of pck_af2cp_sTx and pck_cp2af_sRx below to match the clock,
        // but that would get messy.
        .pClk(plat_ifc.clocks.pClk.clk),
        .pClkDiv2(plat_ifc.clocks.pClkDiv2.clk),
        .pClkDiv4(plat_ifc.clocks.pClkDiv4.clk),
        .uClk_usr(plat_ifc.clocks.uClk_usr.clk),
        .uClk_usrDiv2(plat_ifc.clocks.uClk_usrDiv2.clk),
        .pck_cp2af_softReset(afu_softReset_q),
`ifdef AFU_TOP_REQUIRES_POWER_2BIT
        .pck_cp2af_pwrState(afu_pwrState),
`endif
`ifdef AFU_TOP_REQUIRES_ERROR_1BIT
        .pck_cp2af_error(ccip_to_afu.error),
`endif

`ifdef AFU_TOP_REQUIRES_LOCAL_MEMORY_AVALON_MM
        // Local memory's clock is included in its interface.  If a clock crossing
        // was inserted, the included clock is updated to match.
        .local_mem(local_mem_compat),
`endif
`ifdef AFU_TOP_REQUIRES_LOCAL_MEMORY_AVALON_MM_LEGACY_WIRES_2BANK
        .DDR4a_USERCLK          (local_mem_compat[0].clk),
        .DDR4a_waitrequest      (local_mem_compat[0].waitrequest),
        .DDR4a_readdata         (local_mem_compat[0].readdata),
        .DDR4a_readdatavalid    (local_mem_compat[0].readdatavalid),
        .DDR4a_burstcount       (local_mem_compat[0].burstcount),
        .DDR4a_writedata        (local_mem_compat[0].writedata),
        .DDR4a_address          (local_mem_compat[0].address),
        .DDR4a_write            (local_mem_compat[0].write),
        .DDR4a_read             (local_mem_compat[0].read),
        .DDR4a_byteenable       (local_mem_compat[0].byteenable),

        .DDR4b_USERCLK          (local_mem_compat[1].clk),
        .DDR4b_waitrequest      (local_mem_compat[1].waitrequest),
        .DDR4b_readdata         (local_mem_compat[1].readdata),
        .DDR4b_readdatavalid    (local_mem_compat[1].readdatavalid),
        .DDR4b_burstcount       (local_mem_compat[1].burstcount),
        .DDR4b_writedata        (local_mem_compat[1].writedata),
        .DDR4b_address          (local_mem_compat[1].address),
        .DDR4b_byteenable       (local_mem_compat[1].byteenable),
        .DDR4b_write            (local_mem_compat[1].write),
        .DDR4b_read             (local_mem_compat[1].read),
`endif // AFU_TOP_REQUIRES_LOCAL_MEMORY_AVALON_MM_LEGACY_WIRES_2BANK

`ifdef AFU_TOP_REQUIRES_HSSI_RAW_PR
        .hssi(hssi),
`endif

        .pck_af2cp_sTx(ccip_to_afu.sTx),
        .pck_cp2af_sRx(ccip_to_afu.sRx)
        );

endmodule // platform_shim_ccip_std_afu_hssi

`endif //  `ifndef DISABLE_PLATFORM_SHIM_CCIP_STD_AFU
