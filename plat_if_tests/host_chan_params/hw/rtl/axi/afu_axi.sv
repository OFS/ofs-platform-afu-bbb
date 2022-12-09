// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

module afu
  #(
    parameter AFU_INSTANCE_ID = 0,
    parameter NUM_PORTS_G1 = 0,
    parameter NUM_PORTS_G2 = 0
    )
   (
    // Host memory (AXI)
    ofs_plat_axi_mem_if.to_sink host_mem_if,
    // Zero length is illegal -- force minimum size 1 dummy entry
    ofs_plat_axi_mem_if.to_sink host_mem_g1_if[NUM_PORTS_G1 > 0 ? NUM_PORTS_G1 : 1],
    ofs_plat_axi_mem_if.to_sink host_mem_g2_if[NUM_PORTS_G2 > 0 ? NUM_PORTS_G2 : 1],

    // Events, used for tracking latency through the FIM
    host_chan_events_if.engine host_chan_events_if,
    host_chan_events_if.engine host_chan_g1_events_if[NUM_PORTS_G1 > 0 ? NUM_PORTS_G1 : 1],
    host_chan_events_if.engine host_chan_g2_events_if[NUM_PORTS_G2 > 0 ? NUM_PORTS_G2 : 1],

    // FPGA MMIO source (AXI)
    ofs_plat_axi_mem_lite_if.to_source mmio64_if,

    // pClk is used to compute the frequency of the AFU's clk, since pClk
    // is a known frequency.
    input  logic pClk,

    // AFU Power State
    input  t_ofs_plat_power_state pwrState
    );

    localparam NUM_PORTS_G0 = 1;
    localparam NUM_ENGINES = NUM_PORTS_G0 + NUM_PORTS_G1 + NUM_PORTS_G2;

    engine_csr_if eng_csr_glob();
    engine_csr_if eng_csr[NUM_ENGINES]();


    // ====================================================================
    //
    //  Global CSRs (mostly to tell SW about the AFU configuration)
    //
    // ====================================================================

    // Test UUID. Multiple tests may share an AFU UUID and are differentiated
    // with test IDs.
    logic [127:0] test_id = 128'h548ab951_2fc7_4b7c_9f5e_0d990a3ae963;

    always_comb
    begin
        eng_csr_glob.rd_data[0] = test_id[63:0];
        eng_csr_glob.rd_data[1] = test_id[127:64];
        eng_csr_glob.rd_data[2] = { 32'd0,
                                    8'(AFU_INSTANCE_ID),
                                    8'(NUM_PORTS_G2),
                                    8'(NUM_PORTS_G1),
                                    8'(NUM_PORTS_G0) };

        for (int e = 3; e < eng_csr_glob.NUM_CSRS; e = e + 1)
        begin
            eng_csr_glob.rd_data[e] = 64'(0);
        end

        // This signal means nothing
        eng_csr_glob.status_active = 1'b0;
    end


    // ====================================================================
    //
    //  Engines (one per host memory port)
    //
    // ====================================================================

    genvar p;
    generate
        // Group 0 engine
        host_mem_rdwr_engine_axi
          #(
`ifdef OFS_PLAT_PARAM_HOST_CHAN_ADDRESS_SPACE
            .ADDRESS_SPACE(`OFS_PLAT_PARAM_HOST_CHAN_ADDRESS_SPACE),
`endif
            .ENGINE_NUMBER(0),
            .ENGINE_GROUP(0)
            )
          eng
           (
            .host_mem_if(host_mem_if),
            .host_chan_events_if(host_chan_events_if),
            .csrs(eng_csr[0])
            );

        // Group 1 engines follow group 0
        for (p = 0; p < NUM_PORTS_G1; p = p + 1)
        begin : g1
            host_mem_rdwr_engine_axi
              #(
`ifdef OFS_PLAT_PARAM_HOST_CHAN_G1_IS_NATIVE_AXI
                // Simple AXI ports don't support write fences
                .WRITE_FENCE_SUPPORTED(0),
`endif
`ifdef OFS_PLAT_PARAM_HOST_CHAN_G1_ADDRESS_SPACE
                .ADDRESS_SPACE(`OFS_PLAT_PARAM_HOST_CHAN_G1_ADDRESS_SPACE),
`endif
                .ENGINE_NUMBER(NUM_PORTS_G0 + p),
                .ENGINE_GROUP(1)
                )
              eng
               (
                .host_mem_if(host_mem_g1_if[p]),
                .host_chan_events_if(host_chan_g1_events_if[p]),
                .csrs(eng_csr[NUM_PORTS_G0 + p])
                );
        end

        // Group 2 engines follow group 1
        for (p = 0; p < NUM_PORTS_G2; p = p + 1)
        begin : g2
            host_mem_rdwr_engine_axi
              #(
`ifdef OFS_PLAT_PARAM_HOST_CHAN_G2_IS_NATIVE_AXI
                // Simple AXI ports don't support write fences
                .WRITE_FENCE_SUPPORTED(0),
`endif
`ifdef OFS_PLAT_PARAM_HOST_CHAN_G2_ADDRESS_SPACE
                .ADDRESS_SPACE(`OFS_PLAT_PARAM_HOST_CHAN_G2_ADDRESS_SPACE),
`endif
                .ENGINE_NUMBER(NUM_PORTS_G0 + NUM_PORTS_G1 + p),
                .ENGINE_GROUP(2)
                )
              eng
               (
                .host_mem_if(host_mem_g2_if[p]),
                .host_chan_events_if(host_chan_g2_events_if[p]),
                .csrs(eng_csr[NUM_PORTS_G0 + NUM_PORTS_G1 + p])
                );
        end
    endgenerate


    // ====================================================================
    //
    //  Instantiate control via CSRs
    //
    // ====================================================================

    csr_mgr_axi
      #(
        .NUM_ENGINES(NUM_ENGINES)
        )
      csr_mgr
       (
        .mmio_if(mmio64_if),
        .pClk,

        .eng_csr_glob,
        .eng_csr
        );

endmodule // afu
