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
    logic softReset;


    //
    // Clocks
    //

    ofs_plat_std_clocks_gen_resets_from_active_high clocks
       (
        .pClk,
        .pClk_reset(softReset),
        .pClkDiv2,
        .pClkDiv4,
        .uClk_usr,
        .uClk_usrDiv2,
        .clocks(plat_ifc.clocks)
        );

    assign plat_ifc.softReset_n = plat_ifc.clocks.pClk_reset_n;


    //
    // CCI-P emulator (defined in the ASE core library)
    //

    // Construct the primary ASE CCI-P interface
    ofs_plat_host_ccip_if ccip_fiu();

    assign ccip_fiu.clk = pClk;
    assign ccip_fiu.reset_n = plat_ifc.softReset_n;
    assign ccip_fiu.instance_number = 0;

    ccip_emulator ccip_emulator
       (
        .pClk,
        .pClkDiv2,
        .pClkDiv4,
        .uClk_usr,
        .uClk_usrDiv2,
        // Output signals, mapped to the platform interface
        .pck_cp2af_softReset(softReset),
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
    // This code currently supports up to three groups of ports.
    localparam NUM_AFU_PORTS = `OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS
`ifdef OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS
  `ifdef OFS_PLAT_PARAM_HOST_CHAN_G1_IS_NATIVE_CCIP
                               + `OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS
  `elsif OFS_PLAT_PARAM_HOST_CHAN_G1_IS_NATIVE_AVALON
                               // Transform only 1 port to Avalon and multiplex
                               // it. This is much less resource intensive, since
                               // CCI-P to Avalon requires sorting responses.
                               + 1
  `else
        *** ERROR *** Unsupported native interface!
  `endif
`endif
`ifdef OFS_PLAT_PARAM_HOST_CHAN_G2_NUM_PORTS
  `ifdef OFS_PLAT_PARAM_HOST_CHAN_G2_IS_NATIVE_CCIP
                               + `OFS_PLAT_PARAM_HOST_CHAN_G2_NUM_PORTS
  `elsif OFS_PLAT_PARAM_HOST_CHAN_G2_IS_NATIVE_AVALON
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
        // ================================================================
        //
        //  Primary CCI-P port group (usually just 1 main port)
        //
        // ================================================================

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

        localparam CCIP_PORT_G1_START = `OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS;


        // ================================================================
        //
        //  Group 1 ports, either CCI-P or Avalon, emulated by multiplexing
        //  the primary CCI-P port.
        //
        // ================================================================

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
                .to_fiu(ccip_afu[p + CCIP_PORT_G1_START]),
                .to_afu(plat_ifc.host_chan_g1.ports[p])
                );
        end

        localparam CCIP_PORT_G2_START = CCIP_PORT_G1_START +
                                        `OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS;

  `elsif OFS_PLAT_PARAM_HOST_CHAN_G1_IS_NATIVE_AVALON

        // Emulate a group of Avalon memory mapped ports.

        ase_emulate_avalon_host_chan_group
          #(
            .INSTANCE_BASE(`OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS),
            .NUM_PORTS(`OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS),
            .ADDR_WIDTH(`OFS_PLAT_PARAM_HOST_CHAN_G1_ADDR_WIDTH),
            .DATA_WIDTH(`OFS_PLAT_PARAM_HOST_CHAN_G1_DATA_WIDTH),
            .BURST_CNT_WIDTH(`OFS_PLAT_PARAM_HOST_CHAN_G1_BURST_CNT_WIDTH),
            .USER_WIDTH(`OFS_PLAT_PARAM_HOST_CHAN_G1_USER_WIDTH != 0 ?
                          `OFS_PLAT_PARAM_HOST_CHAN_G1_USER_WIDTH : 1),
            .RD_TRACKER_DEPTH(`OFS_PLAT_PARAM_HOST_CHAN_G1_MAX_BW_ACTIVE_LINES_RD),
            .WR_TRACKER_DEPTH(`OFS_PLAT_PARAM_HOST_CHAN_G1_MAX_BW_ACTIVE_LINES_WR),
    `ifdef OFS_PLAT_PARAM_HOST_CHAN_G1_OUT_OF_ORDER
            .OUT_OF_ORDER(1)
    `else
            .OUT_OF_ORDER(0)
    `endif
            )
          hc_1
           (
            .to_fiu(ccip_afu[CCIP_PORT_G1_START]),
            .emul_ports(plat_ifc.host_chan_g1.ports)
            );

        localparam CCIP_PORT_G2_START = CCIP_PORT_G1_START + 1;

  `else
        *** ERROR *** Unsupported native interface!
  `endif
`endif


        // ================================================================
        //
        //  Group 2 ports, either CCI-P or Avalon, emulated by multiplexing
        //  the primary CCI-P port.
        //
        // ================================================================

`ifdef OFS_PLAT_PARAM_HOST_CHAN_G2_NUM_PORTS
  `ifdef OFS_PLAT_PARAM_HOST_CHAN_G2_IS_NATIVE_CCIP

        // Emulate a second group of CCI-P ports
        for (p = 0; p < `OFS_PLAT_PARAM_HOST_CHAN_G2_NUM_PORTS; p = p + 1)
        begin : hc_2
            ofs_plat_shim_ccip_reg
              #(
                .N_REG_STAGES(0)
                )
              ccip_conn
               (
                .to_fiu(ccip_afu[p + CCIP_PORT_G2_START]),
                .to_afu(plat_ifc.host_chan_g2.ports[p])
                );
        end

        localparam CCIP_PORT_G3_START = CCIP_PORT_G2_START +
                                        `OFS_PLAT_PARAM_HOST_CHAN_G2_NUM_PORTS;

  `elsif OFS_PLAT_PARAM_HOST_CHAN_G2_IS_NATIVE_AVALON

        // Emulate a group of Avalon memory mapped ports.

        ase_emulate_avalon_host_chan_group
          #(
            .INSTANCE_BASE(`OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS +
                           `OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS),
            .NUM_PORTS(`OFS_PLAT_PARAM_HOST_CHAN_G2_NUM_PORTS),
            .ADDR_WIDTH(`OFS_PLAT_PARAM_HOST_CHAN_G2_ADDR_WIDTH),
            .DATA_WIDTH(`OFS_PLAT_PARAM_HOST_CHAN_G2_DATA_WIDTH),
            .BURST_CNT_WIDTH(`OFS_PLAT_PARAM_HOST_CHAN_G2_BURST_CNT_WIDTH),
            .USER_WIDTH(`OFS_PLAT_PARAM_HOST_CHAN_G2_USER_WIDTH != 0 ?
                          `OFS_PLAT_PARAM_HOST_CHAN_G2_USER_WIDTH : 1),
            .RD_TRACKER_DEPTH(`OFS_PLAT_PARAM_HOST_CHAN_G2_MAX_BW_ACTIVE_LINES_RD),
            .WR_TRACKER_DEPTH(`OFS_PLAT_PARAM_HOST_CHAN_G2_MAX_BW_ACTIVE_LINES_WR),
    `ifdef OFS_PLAT_PARAM_HOST_CHAN_G2_OUT_OF_ORDER
            .OUT_OF_ORDER(1)
    `else
            .OUT_OF_ORDER(0)
    `endif
            )
          hc_2
           (
            .to_fiu(ccip_afu[CCIP_PORT_G2_START]),
            .emul_ports(plat_ifc.host_chan_g2.ports)
            );

        localparam CCIP_PORT_G3_START = CCIP_PORT_G2_START + 1;

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

    ase_sim_local_mem_ofs_avmm
      #(
        .NUM_BANKS(NUM_LOCAL_MEM_BANKS),
        .ADDR_WIDTH(local_mem_cfg_pkg::LOCAL_MEM_ADDR_WIDTH),
        .DATA_WIDTH(local_mem_cfg_pkg::LOCAL_MEM_FULL_BUS_WIDTH),
        .MASKED_SYMBOL_WIDTH(local_mem_cfg_pkg::LOCAL_MEM_MASKED_FULL_SYMBOL_WIDTH),
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
            assign plat_ifc.local_mem.banks[b].reset_n = plat_ifc.softReset_n;
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


//
// Emulate a group of Avalon host channels given a CCI-P port. The Avalon
// channels will be multiplexed on top of the single CCI-P port.
//
module ase_emulate_avalon_host_chan_group
  #(
    parameter INSTANCE_BASE = 0,
    parameter NUM_PORTS = 0,
    parameter ADDR_WIDTH = 0,
    parameter DATA_WIDTH = 0,
    parameter BURST_CNT_WIDTH = 0,
    parameter USER_WIDTH = 0,
    parameter RD_TRACKER_DEPTH = 0,
    parameter WR_TRACKER_DEPTH = 0,
    parameter OUT_OF_ORDER = 0
    )
   (
    ofs_plat_host_ccip_if.to_fiu to_fiu,
    ofs_plat_avalon_mem_if emul_ports[NUM_PORTS]
    );

    // Begin by transforming the CCI-P port to a single Avalon port.
    ofs_plat_avalon_mem_rdwr_if
      #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BURST_CNT_WIDTH(BURST_CNT_WIDTH)
        )
        avmm_shared_slave_if();

    ofs_plat_host_chan_as_avalon_mem_rdwr avmm_to_ccip
       (
        .to_fiu,
        .host_mem_to_afu(avmm_shared_slave_if),
        .afu_clk(),
        .afu_reset_n()
        );

    // Multiplex the single Avalon slave into the required number of ports
    ofs_plat_avalon_mem_rdwr_if
      #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .BURST_CNT_WIDTH(BURST_CNT_WIDTH),
        .USER_WIDTH(USER_WIDTH)
        )
        avmm_port_slave_if[NUM_PORTS]();

    // The MUX preservers the master's "user" extension fields, making it
    // possible to use algorithms that depend on user fields in responses
    // matching requests.
    ofs_plat_avalon_mem_rdwr_if_mux
      #(
        .NUM_MASTER_PORTS(NUM_PORTS),
        .RD_TRACKER_DEPTH(RD_TRACKER_DEPTH),
        .WR_TRACKER_DEPTH(WR_TRACKER_DEPTH)
        )
      avmm_mux
       (
        .mem_slave(avmm_shared_slave_if),
        .mem_master(avmm_port_slave_if)
        );

    // Convert split-bus read/write Avalon to standard Avalon
    genvar p;
    for (p = 0; p < NUM_PORTS; p = p + 1)
    begin : e
        // Emulate ports that return results out of order
        ofs_plat_avalon_mem_rdwr_if
          #(
            .ADDR_WIDTH(ADDR_WIDTH),
            .DATA_WIDTH(DATA_WIDTH),
            .BURST_CNT_WIDTH(BURST_CNT_WIDTH),
            .USER_WIDTH(USER_WIDTH)
            )
            avmm_ooo_if();

        ase_emul_ooo_avalon_mem_rdwr_if
          #(
            .OUT_OF_ORDER(OUT_OF_ORDER)
            )
          ooo_port
           (
            .mem_slave(avmm_port_slave_if[p]),
            .mem_master(avmm_ooo_if)
            );

        ofs_plat_avalon_mem_if_to_rdwr_if avmm_to_rdwr
           (
            .mem_slave(avmm_ooo_if),
            .mem_master(emul_ports[p])
            );

        assign emul_ports[p].clk = avmm_port_slave_if[p].clk;
        assign emul_ports[p].reset_n = avmm_port_slave_if[p].reset_n;
        assign emul_ports[p].instance_number = INSTANCE_BASE + p;
    end

endmodule // ase_emulate_avalon_host_chan_group
