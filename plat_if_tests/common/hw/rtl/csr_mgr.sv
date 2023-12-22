// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

`include "ofs_plat_if.vh"
`include "afu_json_info.vh"

`define SAFE_IDX(idx) (idx < NUM_ENGINES) ? idx : 0

//
// The CSR manager implements an MMIO master as the primary MMIO space.
//
// The CSR address space (in 64 bit words):
//
//   0x000 - OPAE AFU DFH (device feature header)
//   0x001 - OPAE AFU_ID_L (AFU ID low half)
//   0x002 - OPAE AFU_ID_H (AFU ID high half)
//
//   0x01? - CSR manager control space. The register interpretations are
//           described below.
//
//   0x02? - Global engine CSR space (16 read/write registers). The register
//           interpretations are determined by the AFU.
//
//   0x1?? - Individual engine CSR spaces (16 read/write registers
//           per engine). The low 4 bits are the register index within
//           an engine. Bits 7:4 are the engine index. The register
//           interpretations are determined by the engines.
//

//
// CSR manager control space (0x01?):
//
//  Writes:
//    0x010: Enable engines. Register value is a bit vector, one bit per
//           engine. Each bit enables a specific engine. The enable sequence
//           sets state_reset in each selected engine and then holds
//           state_run.
//
//    0x011: Disable engines. Clear state_run in the selected engines.
//
//  Reads:
//    0x010: Configuration details:
//             [63:16] undefined
//             [23: 8] pClk frequency (MHz)
//             [ 7: 0] number of engines
//    0x011: Engine run flags, one bit per engine.
//    0x012: Engine active flags, one bit per engine. An engine may be active
//           even if not running while outstanding requests are in flight.
//    0x013: Engine execution cycles in clk domain (primary AFU clock).
//    0x014: Engine execution cycles in pClk domain.
//

module csr_mgr
  #(
    parameter INSTANCE_ID = 0,
    parameter NUM_ENGINES = 1,
    parameter DFH_MMIO_NEXT_ADDR = 0,
    parameter MMIO_ADDR_WIDTH = 16,
    parameter MMIO_DATA_WIDTH = 64,
    parameter MMIO_TID_WIDTH = 9
    )
   (
    input  logic clk,
    input  logic reset_n,
    // Passing in pClk allows us to compute the frequency of clk given a
    // known pClk frequency.
    input  logic pClk,

    // CSR read and write commands from the host
    input  logic wr_write,
    input  logic [MMIO_ADDR_WIDTH-1 : 0] wr_address,
    input  logic [MMIO_DATA_WIDTH-1 : 0] wr_writedata,

    input  logic rd_read,
    input  logic [MMIO_ADDR_WIDTH-1 : 0] rd_address,
    input  logic [MMIO_TID_WIDTH-1 : 0] rd_tid_in,
    output logic rd_readdatavalid,
    output logic [MMIO_DATA_WIDTH-1 : 0] rd_readdata,
    output logic [MMIO_TID_WIDTH-1 : 0] rd_tid_out,

    // Global engine interface (write only)
    engine_csr_if.csr_mgr eng_csr_glob,

    // Individual engine CSRs
    engine_csr_if.csr_mgr eng_csr[NUM_ENGINES]
    );

    typedef logic [$clog2(NUM_ENGINES)-1 : 0] t_engine_idx;
    typedef logic [MMIO_ADDR_WIDTH-1 : 0] t_mmio_addr;
    typedef logic [MMIO_DATA_WIDTH-1 : 0] t_mmio_value;
    typedef logic [MMIO_TID_WIDTH-1 : 0] t_mmio_tid;

    // Engine CSRs are decoded in pipelined stages, selecting using 2 bits
    // each stage.
    localparam MAX_NUM_ENGINES = 64;
    localparam NUM_ENG_DECODE_STAGES = 2 + $clog2(MAX_NUM_ENGINES) / 2;

    // The CSR manager uses only a subset of the MMIO space
    typedef logic [11:0] t_csr_idx;


    // The AFU ID is a unique ID for a given program.  Here we generated
    // one with the "uuidgen" program and stored it in the AFU's JSON file.
    // ASE and synthesis setup scripts automatically invoke afu_json_mgr
    // to extract the UUID into afu_json_info.vh.
    logic [127:0] afu_id = `AFU_ACCEL_UUID;

    typedef enum logic [1:0] {
        STATE_READY = 2'h0,
        STATE_HOLD_RESET = 2'h1,
        STATE_ENG_START = 2'h2
    } t_state;

    t_state state;

    logic [47:0] num_pClk_cycles, num_clk_cycles;


    // ====================================================================
    //
    // CSR read
    //
    // ====================================================================

    // In the first cycle of a read each engine's array of CSRs is reduced
    // to a single register. This splits the multiplexing into two cycles.
    logic read_req[NUM_ENG_DECODE_STAGES];
    t_csr_idx read_idx[NUM_ENG_DECODE_STAGES];
    t_mmio_tid read_tid[NUM_ENG_DECODE_STAGES];

    // Engine states
    logic [NUM_ENGINES-1 : 0] state_reset, state_run, status_active;

    // Pass read request through the CSR decoder pipeline
    always_ff @(posedge clk)
    begin
        read_req[NUM_ENG_DECODE_STAGES-1] <= rd_read;
        read_idx[NUM_ENG_DECODE_STAGES-1] <= t_csr_idx'(rd_address);
        read_tid[NUM_ENG_DECODE_STAGES-1] <= rd_tid_in;

        for (int i = 0; i < NUM_ENG_DECODE_STAGES-1; i = i + 1)
        begin
            read_req[i] <= read_req[i+1];
            read_idx[i] <= read_idx[i+1];
            read_tid[i] <= read_tid[i+1];
        end

        if (!reset_n)
        begin
            read_req[NUM_ENG_DECODE_STAGES-1] <= 1'b0;
        end
    end


    // Pipeline of individual engine status_active, just for timing
    logic [NUM_ENGINES-1 : 0] status_active_p0, status_active_p1;

    generate
        for (genvar e = 0; e < NUM_ENGINES; e = e + 1)
        begin : sa
            // Map individual engine status_active to a register
            always_ff @(posedge clk)
            begin
                status_active_p1[e] <= eng_csr[e].status_active;
            end
        end

        // Extra stages for timing
        always_ff @(posedge clk)
        begin
            status_active_p0 <= status_active_p1;
            status_active <= status_active_p0;
        end
    endgenerate


    //
    // Reduce individual engine CSRs to a single register over multiple
    // pipeline stages.
    //

    // Reduction tree stage storage
    t_mmio_value eng_csr_data_s3[64];
    t_mmio_value eng_csr_data_s2[16];
    t_mmio_value eng_csr_data_s1[4];
    t_mmio_value eng_csr_data;

    generate
        // First stage, pick from the 16 registers in each engine.
        for (genvar e = 0; e < NUM_ENGINES; e = e + 1)
        begin : es3
            always_ff @(posedge clk)
            begin
                eng_csr_data_s3[e] <= eng_csr[e].rd_data[read_idx[4][3:0]];
            end
        end
        for (genvar e = NUM_ENGINES; e < 64; e = e + 1)
        begin : es3z
            assign eng_csr_data_s3[e] = '0;
        end

        // 4:1 reduction in each stage, using increasing pairs of read_idx
        // index bits.

        // 64 -> 16
        for (genvar i = 0; i < 16; i = i + 1)
        begin : es2
            always_ff @(posedge clk)
            begin
                eng_csr_data_s2[i] <= eng_csr_data_s3[{i, read_idx[3][5:4]}];
            end
        end

        // 16 -> 4
        for (genvar i = 0; i < 4; i = i + 1)
        begin : es1
            always_ff @(posedge clk)
            begin
                eng_csr_data_s1[i] <= eng_csr_data_s2[{i, read_idx[2][7:6]}];
            end
        end

        // 4 -> 1
        always_ff @(posedge clk)
        begin : es0
            eng_csr_data <= eng_csr_data_s1[read_idx[1][9:8]];
        end
    endgenerate


    // Reduce the global CSR read vector to the selected entry
    t_mmio_value eng_csr_glob_data;

    always_ff @(posedge clk)
    begin
        eng_csr_glob_data <= eng_csr_glob.rd_data[read_idx[1][3:0]];
    end


    // Reduce the mandatory feature header CSRs (read address 12'h00?)
    t_mmio_value dfh_afu_id;

    always_ff @(posedge clk)
    begin
        case (read_idx[1][3:0])
            4'h0: // AFU DFH (device feature header)
                begin
                    // Here we define a trivial feature list.  In this
                    // example, our AFU is the only entry in this list.
                    dfh_afu_id <= 64'b0;
                    // Feature type is AFU
                    dfh_afu_id[63:60] <= 4'h1;
                    // End of list (last entry in list)?
                    dfh_afu_id[40] <= (DFH_MMIO_NEXT_ADDR == 0);
                    // Next feature
                    dfh_afu_id[39:16] <= 24'(DFH_MMIO_NEXT_ADDR);
                end

            // AFU_ID_L
            4'h1: dfh_afu_id <= afu_id[63:0];
            // AFU_ID_H
            4'h2: dfh_afu_id <= afu_id[127:64];
            default: dfh_afu_id <= 64'b0;
        endcase
    end


    // Reduce CSR manager control space (read address 12'h01?)
    t_mmio_value csr_mgr_ctrl;

    always_ff @(posedge clk)
    begin
        case (read_idx[1][3:0])
            4'h0: // Configuration details
                begin
                    csr_mgr_ctrl <= 64'b0;
                    // pClk frequency (MHz)
                    csr_mgr_ctrl[23:8] <= 16'(`OFS_PLAT_PARAM_CLOCKS_PCLK_FREQ);
                    // Number of engines
                    csr_mgr_ctrl[7:0] <= 8'(NUM_ENGINES);
                end
            4'h1: csr_mgr_ctrl <= 64'(state_run);
            4'h2: csr_mgr_ctrl <= 64'(status_active);
            4'h3: csr_mgr_ctrl <= 64'(num_clk_cycles);
            4'h4: csr_mgr_ctrl <= 64'(num_pClk_cycles);
            default: csr_mgr_ctrl <= 64'b0;
        endcase
    end


    // Second cycle selects from among the already reduced groups
    always_ff @(posedge clk)
    begin
        rd_readdatavalid <= read_req[0];
        rd_tid_out <= read_tid[0];

        casez (read_idx[0])
            // AFU DFH (device feature header) and AFU ID
            12'h00?: rd_readdata <= dfh_afu_id;

            // CSR manager control space
            12'h01?: rd_readdata <= csr_mgr_ctrl;

            // 16 registers in the global CSR space at 'h2?. The value
            // is sampled as soon as the read request arrives.
            12'h02?: rd_readdata <= eng_csr_glob_data;

            // Individual engines have 16 registers each, reduced
            // to a single register in a pipeline above.
            12'b01??????????: rd_readdata <= eng_csr_data;

            default: rd_readdata <= 64'h0;
        endcase // casez (read_idx[0])
    end


    // ====================================================================
    //
    // CSR write
    //
    // ====================================================================

    // Use explicit fanout with a two cycle CSR write

    //
    // Global engine CSRs (0x02?)
    //
    logic eng_csr_glob_wr_write;
    t_mmio_addr eng_csr_glob_wr_address;
    t_mmio_value eng_csr_glob_wr_writedata;

    always_ff @(posedge clk)
    begin
        eng_csr_glob_wr_write <= wr_write;
        eng_csr_glob_wr_address <= wr_address;
        eng_csr_glob_wr_writedata <= wr_writedata;

        eng_csr_glob.wr_req <= (eng_csr_glob_wr_write && (eng_csr_glob_wr_address[11:4] == 8'h02));
        eng_csr_glob.wr_idx <= eng_csr_glob_wr_address[3:0];
        eng_csr_glob.wr_data <= eng_csr_glob_wr_writedata;
    end


    //
    // Individual engine CSRs (12'b01??????????)
    //
    logic eng_csr_wr_write;
    t_mmio_addr eng_csr_wr_address;
    t_mmio_value eng_csr_wr_writedata;

    always_ff @(posedge clk)
    begin
        eng_csr_wr_write <= wr_write;
        eng_csr_wr_address <= wr_address;
        eng_csr_wr_writedata <= wr_writedata;
    end

    generate
        for (genvar e = 0; e < NUM_ENGINES; e = e + 1)
        begin : w_eng
            // Add pipeline stages for timing
            struct {
                logic wr_req;
                t_csr_idx wr_idx;
                logic [63:0] wr_data;
                logic state_reset;
                logic state_run;
            } e_wr_pipe[2];

            always_ff @(posedge clk)
            begin
                e_wr_pipe[1].wr_req <= (eng_csr_wr_write &&
                                        (eng_csr_wr_address[11:10] == 2'b01) &&
                                        (eng_csr_wr_address[9:4] == 6'(e)));
                e_wr_pipe[1].wr_idx <= t_csr_idx'(eng_csr_wr_address);
                e_wr_pipe[1].wr_data <= eng_csr_wr_writedata;
                e_wr_pipe[1].state_reset <= state_reset[e];
                e_wr_pipe[1].state_run <= state_run[e];

                e_wr_pipe[0] <= e_wr_pipe[1];

                eng_csr[e].wr_req <= e_wr_pipe[0].wr_req;
                eng_csr[e].wr_idx <= e_wr_pipe[0].wr_idx[3:0];
                eng_csr[e].wr_data <= e_wr_pipe[0].wr_data;
                eng_csr[e].state_reset <= e_wr_pipe[0].state_reset;
                eng_csr[e].state_run <= e_wr_pipe[0].state_run;
            end
        end
    endgenerate


    //
    // Keep track of whether some engine is currently running
    //
    logic some_engine_is_enabled, some_engine_is_active;

    always_ff @(posedge clk)
    begin
        some_engine_is_enabled <= |state_run;
        some_engine_is_active <= |status_active;
    end


    //
    // Commands to engines
    //
    logic cmd_wr_write;
    t_mmio_addr cmd_wr_address;
    t_mmio_value cmd_wr_writedata;

    always_ff @(posedge clk)
    begin
        cmd_wr_write <= wr_write;
        cmd_wr_address <= wr_address;
        cmd_wr_writedata <= wr_writedata;
    end

    logic is_cmd;
    assign is_cmd = (state == STATE_READY) &&
                    cmd_wr_write && (cmd_wr_address[11:4] == 8'h01);
    logic is_eng_enable_cmd;
    assign is_eng_enable_cmd = is_cmd && (cmd_wr_address[3:0] == 4'h0);
    logic is_eng_disable_cmd;
    assign is_eng_disable_cmd = is_cmd && (cmd_wr_address[3:0] == 4'h1);

    generate
        for (genvar e = 0; e < NUM_ENGINES; e = e + 1)
        begin : cmd_eng
            always_ff @(posedge clk)
            begin
                if (state == STATE_ENG_START)
                begin
                    // Engines that were commanded to be in reset can now run
                    state_run[e] <= state_reset[e] || state_run[e];
                    state_reset[e] <= 1'b0;
                end
                else if (cmd_wr_writedata[e] && is_eng_enable_cmd)
                begin
                    state_reset[e] <= 1'b1;
                    $display("%t: Starting engine %0d (instance %0d)", $time, e, INSTANCE_ID);
                end
                else if (cmd_wr_writedata[e] && is_eng_disable_cmd)
                begin
                    state_run[e] <= 1'b0;
                    $display("%t: Stopping engine %0d (instance %0d)", $time, e, INSTANCE_ID);
                end

                if (!reset_n)
                begin
                    state_reset[e] <= 1'b0;
                    state_run[e] <= 1'b0;
                end
            end
        end
    endgenerate

    logic cycle_counter_reset_n;
    logic cycle_counter_enable;
    assign cycle_counter_enable = some_engine_is_active;
    logic [3:0] eng_reset_hold_cnt;

    always_ff @(posedge clk)
    begin
        case (state)
          STATE_READY:
            begin
                if (is_eng_enable_cmd)
                begin
                    state <= STATE_HOLD_RESET;
                    eng_reset_hold_cnt <= 4'b1;

                    // If no engines are running yet then reset the cycle counters
                    if (! some_engine_is_enabled)
                    begin
                        cycle_counter_reset_n <= 1'b0;
                    end
                end
            end
          STATE_HOLD_RESET:
            begin
                // Hold reset for clock crossing counters
                eng_reset_hold_cnt <= eng_reset_hold_cnt + 4'b1;
                if (eng_reset_hold_cnt == 4'b0)
                begin
                    state <= STATE_ENG_START;
                    cycle_counter_reset_n <= 1'b1;
                end
            end
          STATE_ENG_START:
            begin
                state <= STATE_READY;
            end
        endcase // case (state)
            
        if (!reset_n)
        begin
            state <= STATE_READY;
            cycle_counter_reset_n <= 1'b0;
        end
    end

    //
    // Cycle counters. These run when any engine is active and are reset as
    // engines transition from no engines running to at least one engine running.
    //
    clock_counter#(.COUNTER_WIDTH($bits(num_pClk_cycles)))
      count_pClk_cycles
       (
        .clk,
        .count_clk(pClk),
        .sync_reset_n(cycle_counter_reset_n),
        .enable(cycle_counter_enable),
        .count(num_pClk_cycles)
        );

    clock_counter#(.COUNTER_WIDTH($bits(num_clk_cycles)))
      count_clk_cycles
       (
        .clk,
        .count_clk(clk),
        .sync_reset_n(cycle_counter_reset_n),
        .enable(cycle_counter_enable),
        .count(num_clk_cycles)
        );

endmodule // csr_mgr
