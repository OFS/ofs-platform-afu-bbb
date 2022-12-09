// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Simple dual port, dual clock Block RAM.
//

`include "ofs_plat_if.vh"

module ofs_plat_prim_ram_simple_dc
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,

    // Number of extra stages of output register buffering to add
    parameter N_OUTPUT_REG_STAGES = 0,

    // Register writes for a cycle?
    parameter REGISTER_WRITES = 0
    )
   (
    // Separate write and read clocks
    input  logic wclk,
    input  logic rclk,

    input  logic wen,
    input  logic [$clog2(N_ENTRIES)-1 : 0] waddr,
    input  logic [N_DATA_BITS-1 : 0] wdata,

    input  logic [$clog2(N_ENTRIES)-1 : 0] raddr,
    output logic [N_DATA_BITS-1 : 0] rdata
    );

    logic [N_DATA_BITS-1 : 0] c_rdata;

    ofs_plat_prim_ram_simple_dc_base
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS),
        .REGISTER_READS(N_OUTPUT_REG_STAGES),
        .REGISTER_WRITES(REGISTER_WRITES)
        )
      ram
       (
        .wclk,
        .rclk,
        .waddr,
        .wen,
        .wdata,
        .raddr,
        .rdata(c_rdata)
        );

    //
    // Optional extra registered read responses
    //
    genvar s;
    generate
        if (N_OUTPUT_REG_STAGES <= 1)
        begin : nr
            // 0 or 1 stages handled in base primitive
            assign rdata = c_rdata;
        end
        else
        begin : r
            logic [N_DATA_BITS-1 : 0] mem_rd[2 : N_OUTPUT_REG_STAGES];
            assign rdata = mem_rd[N_OUTPUT_REG_STAGES];

            always_ff @(posedge rclk)
            begin
                mem_rd[2] <= c_rdata;
            end

            for (s = 2; s < N_OUTPUT_REG_STAGES; s = s + 1)
            begin : shft
                always_ff @(posedge rclk)
                begin
                    mem_rd[s+1] <= mem_rd[s];
                end
            end
        end
    endgenerate

endmodule // ofs_plat_prim_ram_simple_dc


//
// Simple dual port, dual clock RAM initialized with a constant on reset.
//
module ofs_plat_prim_ram_simple_dc_init
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,
    // Number of extra stages of output register buffering to add
    parameter N_OUTPUT_REG_STAGES = 0,
    parameter REGISTER_WRITES = 0,

    parameter INIT_VALUE = 0
    )
   (
    // Separate write and read clocks
    input  logic wclk,
    input  logic rclk,

    // Reset (in the write domain for initialization)
    input  logic wreset,

    // Goes high after initialization complete and stays high.
    // Separate signals for each clock domain.
    output logic wrdy,
    output logic rrdy,

    input  logic wen,
    input  logic [$clog2(N_ENTRIES)-1 : 0] waddr,
    input  logic [N_DATA_BITS-1 : 0] wdata,

    input  logic [$clog2(N_ENTRIES)-1 : 0] raddr,
    output logic [N_DATA_BITS-1 : 0] rdata
    );

    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_addr;

    t_addr waddr_local;
    logic wen_local;
    logic [N_DATA_BITS-1 : 0] wdata_local;

    ofs_plat_prim_ram_simple_dc
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS),
        .N_OUTPUT_REG_STAGES(N_OUTPUT_REG_STAGES),
        .REGISTER_WRITES(REGISTER_WRITES)
        )
      ram
       (
        .wclk,
        .rclk,
        .waddr(waddr_local),
        .wen(wen_local),
        .wdata(wdata_local),
        .raddr,
        .rdata
        );

    //
    // Initialization loop
    //

    t_addr waddr_init;

    assign waddr_local = wrdy ? waddr : waddr_init;
    assign wen_local = wrdy ? wen : 1'b1;
    assign wdata_local = wrdy ? wdata : (N_DATA_BITS'(INIT_VALUE));

    initial
    begin
        wrdy = 1'b0;
        waddr_init = t_addr'(0);
    end

    always @(posedge wclk)
    begin
        if (wreset)
        begin
            wrdy <= 1'b0;
            waddr_init <= t_addr'(0);
        end
        else
        begin
            wrdy <= wrdy || (waddr_init == t_addr'(N_ENTRIES-1));
            waddr_init <= waddr_init + t_addr'(1'(~wrdy));
        end
    end

    // Ready signal in the read domain.
    ofs_plat_prim_clock_crossing_reg rdy_cross
       (
        .clk_src(wclk),
        .clk_dst(rclk),
        .r_in(wrdy),
        .r_out(rrdy)
        );

endmodule // ofs_plat_prim_ram_simple_dc_init


//
// Base implementation configured by the primary modules above.
//
module ofs_plat_prim_ram_simple_dc_base
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,

    // Register reads if non-zero
    parameter REGISTER_READS = 0,

    // Register writes for a cycle?
    parameter REGISTER_WRITES = 0
    )
   (
    input  logic wclk,
    input  logic rclk,

    input  logic wen,
    input  logic [$clog2(N_ENTRIES)-1 : 0] waddr,
    input  logic [N_DATA_BITS-1 : 0] wdata,

    input  logic [$clog2(N_ENTRIES)-1 : 0] raddr,
    output logic [N_DATA_BITS-1 : 0] rdata
    );

    // If the output data is registered then request a register stage in
    // the megafunction, giving it an opportunity to optimize the location.
    //
    localparam OUTDATA_REGISTERED = (REGISTER_READS == 0) ? "UNREGISTERED" :
                                                            "CLOCK1";

    logic c_wen;
    logic [$clog2(N_ENTRIES)-1 : 0] c_waddr;
    logic [N_DATA_BITS-1 : 0] c_wdata;

    altsyncram
      #(
`ifdef PLATFORM_INTENDED_DEVICE_FAMILY
        .intended_device_family(`PLATFORM_INTENDED_DEVICE_FAMILY),
`endif
        .operation_mode("DUAL_PORT"),
        .width_a(N_DATA_BITS),
        .widthad_a($clog2(N_ENTRIES)),
        .numwords_a(N_ENTRIES),
        .width_b(N_DATA_BITS),
        .widthad_b($clog2(N_ENTRIES)),
        .numwords_b(N_ENTRIES),
        .rdcontrol_reg_b("CLOCK1"),
        .address_reg_b("CLOCK1"),
        .outdata_reg_b(OUTDATA_REGISTERED),
        .read_during_write_mode_mixed_ports("DONT_CARE")
        )
      data
       (
        .clock0(wclk),
        .clock1(rclk),

        .wren_a(c_wen),
        .address_a(c_waddr),
        .data_a(c_wdata),
        .rden_a(1'b0),

        .address_b(raddr),
        .q_b(rdata),
        .wren_b(1'b0),

        // Legally unconnected ports -- get rid of lint errors
        .rden_b(),
        .data_b(),
        .clocken0(),
        .clocken1(),
        .clocken2(),
        .clocken3(),
        .aclr0(),
        .aclr1(),
        .byteena_a(),
        .byteena_b(),
        .addressstall_a(),
        .addressstall_b(),
        .q_a(),
        .eccstatus()
        );

    //
    // Handle optionally registered writes.
    //
    generate
        if (REGISTER_WRITES == 0)
        begin : nwr
            // No write buffering
            assign c_wen = wen;
            assign c_waddr = waddr;
            assign c_wdata = wdata;
        end
        else
        begin : wr
            // Register writes
            always_ff @(posedge wclk)
            begin
                c_wen <= wen;
                c_waddr <= waddr;
                c_wdata <= wdata;
            end
        end
    endgenerate

endmodule // ofs_plat_prim_ram_simple_dc_base
