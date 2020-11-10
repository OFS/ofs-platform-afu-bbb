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
// Emulate a primary CCI-P port and optionally some other host channel groups.
//

`include "ofs_plat_if.vh"

module ase_emul_host_chan_native_ccip
   (
    input  wire t_ofs_plat_std_clocks clocks,
    ofs_plat_host_ccip_if.to_afu host_chan_ports[`OFS_PLAT_PARAM_HOST_CHAN_NUM_PORTS],

`ifdef OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS
  `ifdef OFS_PLAT_PARAM_HOST_CHAN_G1_IS_NATIVE_CCIP
    ofs_plat_host_ccip_if.to_afu host_chan_g1_ports[`OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS],
  `elsif OFS_PLAT_PARAM_HOST_CHAN_G1_IS_NATIVE_AVALON
    ofs_plat_avalon_mem_if.to_source host_chan_g1_ports[`OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS],
  `else
        *** ERROR *** Unsupported native interface!
  `endif
`endif

`ifdef OFS_PLAT_PARAM_HOST_CHAN_G2_NUM_PORTS
  `ifdef OFS_PLAT_PARAM_HOST_CHAN_G2_IS_NATIVE_CCIP
    ofs_plat_host_ccip_if.to_afu host_chan_g2_ports[`OFS_PLAT_PARAM_HOST_CHAN_G2_NUM_PORTS],
  `elsif OFS_PLAT_PARAM_HOST_CHAN_G2_IS_NATIVE_AVALON
    ofs_plat_avalon_mem_if.to_source host_chan_g2_ports[`OFS_PLAT_PARAM_HOST_CHAN_G2_NUM_PORTS],
  `else
        *** ERROR *** Unsupported native interface!
  `endif
`endif

    output logic softReset,
    output t_ofs_plat_power_state pwrState
    );

    //
    // CCI-P emulator (defined in the ASE core library)
    //

    // Construct the primary ASE CCI-P interface
    ofs_plat_host_ccip_if ccip_fiu();

    assign ccip_fiu.clk = clocks.pClk.clk;
    assign ccip_fiu.reset_n = !softReset;
    assign ccip_fiu.instance_number = 0;

    ccip_emulator ccip_emulator
       (
        .pClk(clocks.pClk.clk),
        .pClkDiv2(clocks.pClkDiv2.clk),
        .pClkDiv4(clocks.pClkDiv4.clk),
        .uClk_usr(clocks.uClk_usr.clk),
        .uClk_usrDiv2(clocks.uClk_usrDiv2.clk),
        // Output signals, mapped to the platform interface
        .pck_cp2af_softReset(softReset),
        .pck_cp2af_pwrState(pwrState),
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
                .to_afu(host_chan_ports[p])
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
                .to_afu(host_chan_g1_ports[p])
                );
        end

        localparam CCIP_PORT_G2_START = CCIP_PORT_G1_START +
                                        `OFS_PLAT_PARAM_HOST_CHAN_G1_NUM_PORTS;

  `elsif OFS_PLAT_PARAM_HOST_CHAN_G1_IS_NATIVE_AVALON

        // Emulate a group of Avalon memory mapped ports.

        ase_emul_host_chan_avalon_on_ccip
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
            .emul_ports(host_chan_g1_ports)
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
                .to_afu(host_chan_g2_ports[p])
                );
        end

        localparam CCIP_PORT_G3_START = CCIP_PORT_G2_START +
                                        `OFS_PLAT_PARAM_HOST_CHAN_G2_NUM_PORTS;

  `elsif OFS_PLAT_PARAM_HOST_CHAN_G2_IS_NATIVE_AVALON

        // Emulate a group of Avalon memory mapped ports.

        ase_emul_host_chan_avalon_on_ccip
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
            .emul_ports(host_chan_g2_ports)
            );

        localparam CCIP_PORT_G3_START = CCIP_PORT_G2_START + 1;

  `else
        *** ERROR *** Unsupported native interface!
  `endif
`endif
    endgenerate

endmodule // ase_emul_host_chan_native_ccip
