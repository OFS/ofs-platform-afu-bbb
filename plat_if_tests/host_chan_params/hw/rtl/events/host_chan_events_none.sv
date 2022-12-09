// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Host channel event tracker tie-off.
//

module host_chan_events_none
   (
    host_chan_events_if.monitor events
    );

    assign events.notEmpty = 1'b0;
    assign events.eng_clk_cycle_count = '0;
    assign events.fim_clk_cycle_count = '0;
    assign events.num_rd_reqs = '0;
    assign events.active_rd_req_sum = '0;

endmodule // host_chan_events_none
