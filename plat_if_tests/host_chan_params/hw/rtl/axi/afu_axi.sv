// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

module afu
  #(
    parameter AFU_INSTANCE_ID = 0
    )
   (
    // Host memory (AXI)
    ofs_plat_axi_mem_if.to_sink host_mem_if,

    // Events, used for tracking latency through the FIM
    host_chan_events_if.engine host_chan_events_if,

    // FPGA MMIO source (AXI)
    ofs_plat_axi_mem_lite_if.to_source mmio64_if,

    // pClk is used to compute the frequency of the AFU's clk, since pClk
    // is a known frequency.
    input  logic pClk,

    // AFU Power State
    input  t_ofs_plat_power_state pwrState
    );

    localparam NUM_ENGINES = 1;

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
                                    16'(0),
                                    8'(NUM_ENGINES) };

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
    endgenerate


    // ====================================================================
    //
    //  Instantiate control via CSRs
    //
    // ====================================================================

    csr_mgr_axi
      #(
        .INSTANCE_ID(AFU_INSTANCE_ID),
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
