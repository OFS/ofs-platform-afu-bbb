// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Manage logging to shared files. A collection of global file handles is
// maintained, allowing multiple modules to log to the same file.
//

package ofs_plat_log_pkg;

    typedef enum
    {
        NONE = 0,        // Don't log
        HOST_CHAN = 1,
        LOCAL_MEM = 2,
        HSSI = 3,
        OTHER = 4
    }
    t_log_class;

    // What is the name for an instance of the class?
    localparam string instance_name[5] = {
        "",
        "port",    // HOST_CHAN
        "bank",    // LOCAL_MEM
        "chan",    // HSSI
        "port"     // OTHER
        };

    int log_fds[5] = '{5{-1}};
    localparam string log_names[5] = {
        "",
        "log_ofs_plat_host_chan.tsv",
        "log_ofs_plat_local_mem.tsv",
        "log_ofs_plat_hssi.tsv",
        "log_ofs_plat_other.tsv"
        };

    // Get the file descriptor for a group
    function automatic int get_fd(t_log_class g);
        if (g == NONE) return -1;

        // Open the file if necessary
        if (log_fds[g] == -1)
        begin
            log_fds[g] = $fopen(log_names[g], "w");
        end

        return log_fds[g];
    endfunction

endpackage // ofs_plat_log_pkg
