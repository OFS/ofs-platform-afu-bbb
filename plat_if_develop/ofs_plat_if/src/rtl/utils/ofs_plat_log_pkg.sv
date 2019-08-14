//
// Copyright (c) 2018, Intel Corporation
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
// Manage logging to shared files. A collection of global file handles is
// maintained, allowing multiple modules to log to the same file.
//

package ofs_plat_log_pkg;

    typedef enum
    {
        NONE = 0,        // Don't log
        HOST_CHAN = 1,
        LOCAL_MEM = 2
    }
    t_log_class;

    // What is the name for an instance of the class?
    localparam string instance_name[3] = {
        "",
        "port",
        "bank"
        };

    int log_fds[3] = '{3{-1}};
    localparam string log_names[3] = {
        "",
        "log_ofs_plat_host_chan.tsv",
        "log_ofs_plat_local_mem.tsv"
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
