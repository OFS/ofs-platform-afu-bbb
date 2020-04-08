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
// Platform-specific device simulation. ASE's core library provides clocks
// and this module instantiates device models and constructs an OFS
// platform interface that wraps the simulated devices.
//

`include "ofs_plat_if.vh"

module ase_top_ofs_plat
   (
    input  logic pClk,
    input  logic pClkDiv2,
    input  logic pClkDiv4,
    input  logic uClk_usr,
    input  logic uClk_usrDiv2
    );

    // Construct the simulated platform interface wrapper which will be passed
    // to the AFU.
    ofs_plat_if#(.ENABLE_LOG(1)) plat_ifc();


    //
    // Clocks
    //

    assign plat_ifc.clocks.pClk = pClk;
    assign plat_ifc.clocks.pClkDiv2 = pClkDiv2;
    assign plat_ifc.clocks.pClkDiv4 = pClkDiv4;
    assign plat_ifc.clocks.uClk_usr = uClk_usr;
    assign plat_ifc.clocks.uClk_usrDiv2 = uClk_usrDiv2;


    //
    // CCI-P emulator (defined in the ASE core library)
    //

    // Construct the primary ASE CCI-P interface
    ofs_plat_host_ccip_if ccip_fiu();

    assign ccip_fiu.clk = pClk;
    assign ccip_fiu.reset = plat_ifc.softReset;
    assign ccip_fiu.instance_number = 0;

    ccip_emulator ccip_emulator
       (
        .pClk,
        .pClkDiv2,
        .pClkDiv4,
        .uClk_usr,
        .uClk_usrDiv2,
        // Output signals, mapped to the platform interface
        .pck_cp2af_softReset(plat_ifc.softReset),
        .pck_cp2af_pwrState(plat_ifc.pwrState),
        .pck_cp2af_error(ccip_fiu.error),
        .pck_af2cp_sTx(ccip_fiu.sTx),
        .pck_cp2af_sRx(ccip_fiu.sRx)
        );

    // Map the ASE CCI-P interface to the number of CCI-P interfaces
    // we must emulate for the simulated platform. ASE's core library
    // can only instantiate a single ccip_emulator, so we must multiplex
    // it if more than one interface is needed.
    //
    // This code currently supports up to two groups of ports.
    localparam NUM_AFU_PORTS = `OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS
`ifdef OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS
  `ifdef OFS_PLAT_PARAM_HOST_CHAN_G1_IS_NATIVE_CCIP
                               + `OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS
  `elsif OFS_PLAT_PARAM_HOST_CHAN_G1_IS_NATIVE_AVALON_RDWR
                               // Transform only 1 port to Avalon and multiplex
                               // it. This is much less resource intensive, since
                               // CCI-P to Avalon requires sorting responses.
                               + 1
  `else
        *** ERROR *** Unsupported native interface!
  `endif
`endif
                               ;

    ofs_plat_host_ccip_if ccip_afu[NUM_AFU_PORTS]();

    ofs_plat_shim_ccip_mux
      #(
        .NUM_AFU_PORTS(NUM_AFU_PORTS)
        )
      ccip_mux
       (
        .to_fiu(ccip_fiu),
        .to_afu(ccip_afu)
        );

    genvar p;
    generate
        // First group of CCI-P ports
        for (p = 0; p < `OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS; p = p + 1)
        begin : hc_0
            ofs_plat_shim_ccip_reg
              #(
                .N_REG_STAGES(0)
                )
              ccip_conn
               (
                .to_fiu(ccip_afu[p]),
                .to_afu(plat_ifc.host_chan.ports[p])
                );
        end

`ifdef OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS
  `ifdef OFS_PLAT_PARAM_HOST_CHAN_G1_IS_NATIVE_CCIP
        // Emulate a second group of CCI-P ports
        for (p = 0; p < `OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS; p = p + 1)
        begin : hc_1
            ofs_plat_shim_ccip_reg
              #(
                .N_REG_STAGES(0)
                )
              ccip_conn
               (
                .to_fiu(ccip_afu[p + `OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS]),
                .to_afu(plat_ifc.host_chan_g1.ports[p])
                );
        end
  `elsif OFS_PLAT_PARAM_HOST_CHAN_G1_IS_NATIVE_AVALON_RDWR
        // Emulate a secondary group of Avalon split read/write ports.

        // Begin by transforming the CCI-P port to a single Avalon port.
        ofs_plat_avalon_mem_rdwr_if
          #(
            .ADDR_WIDTH(`OFS_PLAT_PARAM_HOST_CHAN_G1_ADDR_WIDTH),
            .DATA_WIDTH(`OFS_PLAT_PARAM_HOST_CHAN_G1_DATA_WIDTH),
            .BURST_CNT_WIDTH(`OFS_PLAT_PARAM_HOST_CHAN_G1_BURST_CNT_WIDTH)
            )
            avmm_shared_slave_if();

        ofs_plat_host_chan_as_avalon_mem
          ccip_to_avmm
           (
            .to_fiu(ccip_afu[`OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS]),
            .host_mem_to_afu(avmm_shared_slave_if),
            .afu_clk()
            );

        // Multiplex the single Avalon slave into the platform's ports
        ofs_plat_avalon_mem_rdwr_if_mux
          #(
            .NUM_MASTER_PORTS(`OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS),
            .RD_TRACKER_DEPTH(`OFS_PLAT_PARAM_HOST_CHAN_G1_MAX_BW_ACTIVE_LINES_RD),
            .WR_TRACKER_DEPTH(`OFS_PLAT_PARAM_HOST_CHAN_G1_MAX_BW_ACTIVE_LINES_WR)
            )
          avmm_mux
           (
            .mem_slave(avmm_shared_slave_if),
            .mem_master(plat_ifc.host_chan_g1.ports)
            );
  `else
        *** ERROR *** Unsupported native interface!
  `endif
`endif
    endgenerate


    //
    // Local memory (model provided by the ASE core library)
    //
`ifdef OFS_PLAT_PARAM_LOCAL_MEM_NUM_BANKS

    localparam NUM_LOCAL_MEM_BANKS = plat_ifc.local_mem.NUM_BANKS;
    logic mem_banks_clk[NUM_LOCAL_MEM_BANKS];

    ase_sim_local_mem_avmm
      #(
        .NUM_BANKS(NUM_LOCAL_MEM_BANKS),
        .ADDR_WIDTH(local_mem_cfg_pkg::LOCAL_MEM_ADDR_WIDTH),
        .DATA_WIDTH(local_mem_cfg_pkg::LOCAL_MEM_DATA_WIDTH),
        .BURST_CNT_WIDTH(local_mem_cfg_pkg::LOCAL_MEM_BURST_CNT_WIDTH)
        )
      local_mem_model
       (
        .local_mem(plat_ifc.local_mem.banks),
        .clks(mem_banks_clk)
        );

    genvar b;
    generate
        for (b = 0; b < NUM_LOCAL_MEM_BANKS; b = b + 1)
        begin : b_reset
            assign plat_ifc.local_mem.banks[b].clk = mem_banks_clk[b];
            assign plat_ifc.local_mem.banks[b].reset = plat_ifc.softReset;
            assign plat_ifc.local_mem.banks[b].instance_number = b;

            assign plat_ifc.local_mem.banks[b].response = '0;

            // Write response not implemented
            assign plat_ifc.local_mem.banks[b].writeresponsevalid = 1'b0;
            assign plat_ifc.local_mem.banks[b].writeresponse = '0;
        end
    endgenerate
`endif


    //
    // Instantiate the AFU
    //
    `PLATFORM_SHIM_MODULE_NAME `PLATFORM_SHIM_MODULE_NAME
       (
        .plat_ifc
        );

endmodule // ase_top_ofs_plat
