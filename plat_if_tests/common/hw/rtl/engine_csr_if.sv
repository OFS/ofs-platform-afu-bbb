// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Interface wrapping CSRs for an engine
//

interface engine_csr_if
  #(
    parameter NUM_CSRS = 16,
    parameter CSR_DATA_WIDTH = 64
    );

    typedef logic [$clog2(NUM_CSRS)-1 : 0] t_csr_idx;
    typedef logic [CSR_DATA_WIDTH-1 : 0] t_csr_value;

    // Engine control: CSR manager to engine.
    // At most one state flag will be set in a given cycle. The state_reset flag
    // will always be raised before state_run is enabled. Engines should clear
    // counters on state_reset and run as long as state_run is enabled.
    logic state_reset;
    logic state_run;

    // Engine status: engine to CSR manager.
    // The active flag indicates requests are in flight. It may be set even when
    // state_run is off. A standard run ends with the controller clearing
    // state_run and waiting for status_active to go low.
    logic status_active;

    // Writes to engine CSRs set wr_req for one cycle.
    logic wr_req;
    t_csr_idx wr_idx;
    t_csr_value wr_data;

    // Read registers are sampled continuously. There is no explicit request.
    t_csr_value rd_data[NUM_CSRS];

    modport csr_mgr
       (
        output state_reset,
        output state_run,
        input  status_active,

        output wr_req,
        output wr_idx,
        output wr_data,

        input  rd_data
        );

    modport engine
       (
        input  state_reset,
        input  state_run,
        output status_active,

        input  wr_req,
        input  wr_idx,
        input  wr_data,

        output rd_data
        );

endinterface // engine_csr_if
