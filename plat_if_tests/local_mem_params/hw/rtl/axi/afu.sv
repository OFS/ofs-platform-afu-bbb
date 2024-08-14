// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"

module afu
  #(
    parameter LM_AFU_USER_WIDTH = 4
    )
   (
    // Local memory group 0
    ofs_plat_axi_mem_if.to_sink local_mem_g0[local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS],

`ifdef OFS_PLAT_PARAM_LOCAL_MEM_G1_NUM_BANKS
    // Local memory group 1
    ofs_plat_axi_mem_if.to_sink local_mem_g1[local_mem_g1_cfg_pkg::LOCAL_MEM_NUM_BANKS],
`endif

`ifdef OFS_PLAT_PARAM_LOCAL_MEM_G2_NUM_BANKS
    // Local memory group 2
    ofs_plat_axi_mem_if.to_sink local_mem_g2[local_mem_g2_cfg_pkg::LOCAL_MEM_NUM_BANKS],
`endif

    // FPGA MMIO source
    ofs_plat_axi_mem_lite_if.to_source mmio64_if,

    // pClk is used to compute the frequency of the AFU's clk, since pClk
    // is a known frequency.
    input  logic pClk,

    // AFU Power State
    input  t_ofs_plat_power_state pwrState
    );

    logic clk;
    assign clk = mmio64_if.clk;

    logic reset_n = 1'b0;
    always @(posedge clk)
    begin
        reset_n <= mmio64_if.reset_n;
    end

    localparam NUM_ENGINES = local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS
`ifdef OFS_PLAT_PARAM_LOCAL_MEM_G1_NUM_BANKS
                             + local_mem_g1_cfg_pkg::LOCAL_MEM_NUM_BANKS
`endif
`ifdef OFS_PLAT_PARAM_LOCAL_MEM_G2_NUM_BANKS
                             + local_mem_g2_cfg_pkg::LOCAL_MEM_NUM_BANKS
`endif
                             ;

    engine_csr_if eng_csr_glob();
    engine_csr_if eng_csr[NUM_ENGINES]();


    // ====================================================================
    //
    //  Global CSRs (mostly to tell SW about the AFU configuration)
    //
    // ====================================================================

    // Test UUID. Multiple tests may share an AFU UUID and are differentiated
    // with test IDs.
    logic [127:0] test_id = 128'hf8c7e210_7050_4315_b70e_c6c8074fb2b5;

    always_comb
    begin
        eng_csr_glob.rd_data[0] = test_id[63:0];
        eng_csr_glob.rd_data[1] = test_id[127:64];

        for (int e = 2; e < eng_csr_glob.NUM_CSRS; e = e + 1)
        begin
            eng_csr_glob.rd_data[e] = 64'(0);
        end

        // This signal means nothing
        eng_csr_glob.status_active = 1'b0;
    end


    // ====================================================================
    //
    //  Engines (one per local memory port)
    //
    // ====================================================================

`ifdef TEST_PARAM_UNIQUE_REGIONS
    localparam UNIQUE_MEM_REGIONS = 1;
`else
    localparam UNIQUE_MEM_REGIONS = 0;
`endif

    generate
        for (genvar b = 0; b < local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS; b = b + 1)
        begin : mb
            local_mem_engine_axi
              #(
                .GROUP_ENGINE_NUMBER(b),
                .LM_AFU_USER_WIDTH(LM_AFU_USER_WIDTH),
                .NUM_UNIQUE_MEM_REGIONS(UNIQUE_MEM_REGIONS ? local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS : 1)
                )
              eng
               (
                .local_mem_if(local_mem_g0[b]),
                .csrs(eng_csr[b])
                );
        end

`ifdef OFS_PLAT_PARAM_LOCAL_MEM_G1_NUM_BANKS
        for (genvar b = 0; b < local_mem_g1_cfg_pkg::LOCAL_MEM_NUM_BANKS; b = b + 1)
        begin : mb_g1
            local_mem_engine_axi
              #(
                .GROUP_ENGINE_NUMBER(b),
                .LM_AFU_USER_WIDTH(LM_AFU_USER_WIDTH),
                .NUM_UNIQUE_MEM_REGIONS(UNIQUE_MEM_REGIONS ? local_mem_g1_cfg_pkg::LOCAL_MEM_NUM_BANKS : 1)
                )
              eng
               (
                .local_mem_if(local_mem_g1[b]),
                .csrs(eng_csr[b + local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS])
                );
        end
`endif

`ifdef OFS_PLAT_PARAM_LOCAL_MEM_G2_NUM_BANKS
        for (genvar b = 0; b < local_mem_g2_cfg_pkg::LOCAL_MEM_NUM_BANKS; b = b + 1)
        begin : mb_g2
            local_mem_engine_axi
              #(
                .GROUP_ENGINE_NUMBER(b),
                .LM_AFU_USER_WIDTH(LM_AFU_USER_WIDTH),
                .NUM_UNIQUE_MEM_REGIONS(UNIQUE_MEM_REGIONS ? local_mem_g2_cfg_pkg::LOCAL_MEM_NUM_BANKS : 1)
                )
              eng
               (
                .local_mem_if(local_mem_g2[b]),
                .csrs(eng_csr[b + local_mem_g1_cfg_pkg::LOCAL_MEM_NUM_BANKS +
                                  local_mem_cfg_pkg::LOCAL_MEM_NUM_BANKS])
                );
        end
`endif
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
