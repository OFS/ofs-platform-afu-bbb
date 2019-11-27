//
// Copyright (c) 2019, Intel Corporation
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
// Test one or more local memory interfaces, varying address alignment and
// burst sizes.
//

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <assert.h>
#include <inttypes.h>
#include <uuid/uuid.h>
#include <time.h>

#include <opae/fpga.h>

// State from the AFU's JSON file, extracted using OPAE's afu_json_mgr script
#include "afu_json_info.h"
#include "test_local_mem_params.h"

#define MEMLINE_BYTES 64
#define CL(x) ((x) * MEMLINE_BYTES)
#define MB(x) ((x) * 1048576)

//
// Hold local memory details for one engine
//
typedef struct
{
    uint32_t data_byte_width;
    uint32_t max_burst_size;
    bool natural_bursts;
    bool ordered_read_responses;
}
t_engine_buf;

static fpga_handle s_accel_handle;
static t_csr_handle_p s_csr_handle;
static bool s_is_ase;
static t_engine_buf* s_eng_bufs;
static double s_afu_mhz;

static char *engine_type[] = 
{
    "CCI-P",
    "Avalon",
    NULL
};


static void
testDumpEngineState(
    uint32_t e
)
{
    printf("  Engine %d state:\n", e);

    uint64_t status = csrEngRead(s_csr_handle, e, 0);
    printf("    active: %ld\n", 1 & (status >> 34));
    printf("    running: %ld\n", 1 & (status >> 33));
    printf("    in reset: %ld\n", 1 & (status >> 32));
    printf("    waitrequest: %ld\n", 1 & (status >> 40));
    printf("    read burst requests: %ld\n", csrEngRead(s_csr_handle, e, 1));
    printf("    read line responses: %ld\n", csrEngRead(s_csr_handle, e, 2));
    printf("    write line requests: %ld\n", csrEngRead(s_csr_handle, e, 3));
}


static int
testSmallRegions(
    uint32_t e
)
{
    int num_errors = 0;

    // What is the maximum burst size for the engine? It is encoded in CSR 0.
    uint64_t max_burst_size = s_eng_bufs[e].max_burst_size;
    printf("Testing engine %d, maximum burst size %ld:\n", e, max_burst_size);

    uint64_t burst_size = 1;
    while (burst_size <= max_burst_size)
    {
        uint64_t num_bursts = 1;
        while (num_bursts < 20)
        {
            //
            // Test only writes (mode 1), only reads (mode 2) and
            // read+write (mode 3).
            //
            for (int mode = 1; mode <= 3; mode += 1)
            {
                char *mode_str = "R+W:  ";
                if (mode == 1)
                    mode_str = "Write:";
                if (mode == 2)
                {
                    mode_str = "Read: ";
                }

                printf("  %s %2ld bursts of %2ld lines", mode_str,
                       num_bursts, burst_size);

                // Configure engine burst details
                csrEngWrite(s_csr_handle, e, 0,
                            ((uint64_t)((mode & 2) ? 1 : 0) << 48) |
                            (num_bursts << 32) | burst_size);
                csrEngWrite(s_csr_handle, e, 1,
                            ((uint64_t)((mode & 1) ? 1 : 0) << 48) |
                            (num_bursts << 32) | burst_size);
                // Write data seed
                csrEngWrite(s_csr_handle, e, 2, e + 0xf00);

                // Start your engines
                csrEnableEngines(s_csr_handle, (uint64_t)1 << e);

                // Compute expected hash while the hardware is running
                uint64_t expected_hash =
                    testDataChkGen(64, e + 0xf00, num_bursts * burst_size);

                // Wait for engine to complete. Checking csrGetEnginesEnabled()
                // resolves a race between the request to start an engine
                // and the engine active flag going high. Execution is done when
                // the engine is enabled and the active flag goes low.
                struct timespec wait_time;
                // Poll less often in simulation
                wait_time.tv_sec = (s_is_ase ? 1 : 0);
                wait_time.tv_nsec = 1000000;
                int trips = 0;
                while (true)
                {
                    uint64_t eng_enabled = csrGetEnginesEnabled(s_csr_handle);
                    uint64_t eng_active = csrGetEnginesActive(s_csr_handle);

                    // Done once the engine has been enabled and it is
                    // no longer active.
                    if (eng_enabled && ! eng_active) break;

                    trips += 1;
                    if (trips == 10)
                    {
                        printf(" - HANG!\n\n");
                        printf("Aborting - enabled mask 0x%lx, active mask 0x%lx\n",
                               eng_enabled, eng_active);
                        testDumpEngineState(e);
                        num_errors += 1;
                        goto fail;
                    }

                    nanosleep(&wait_time, NULL);
                }

                // Stop the engine
                csrDisableEngines(s_csr_handle, (uint64_t)1 << e);

                uint64_t hw_hash = csrEngRead(s_csr_handle, e, 5);
                if ((mode == 1) || (expected_hash == hw_hash))
                {
                    printf(" - PASS\n");
                }
                else
                {
                    num_errors += 1;
                    printf(" - FAIL\n");
                    printf("  0x%016lx, expected 0x%016lx\n", hw_hash, expected_hash);
                }
            }

            num_bursts = (num_bursts * 2) + 1;
        }

        if (s_eng_bufs[e].natural_bursts)
        {
            // Natural burst sizes -- test powers of 2
            burst_size <<= 1;
        }
        else
        {
            // Test every burst size up to 4 and then sparsely after that
            if ((burst_size < 4) || (burst_size == max_burst_size))
                burst_size += 1;
            else
            {
                burst_size = burst_size * 3 + 1;
                if (burst_size > max_burst_size) burst_size = max_burst_size;
            }
        }
    }

  fail:
    return num_errors;
}


//
// Configure (but don't start) a continuous bandwidth test on one engine.
//
static int
configBandwidth(
    uint32_t e,
    uint32_t burst_size,
    bool do_reads,
    bool do_writes
)
{
    // Configure engine burst details. Set the number of bursts to 0,
    // indicating unlimited I/O until time expires.
    csrEngWrite(s_csr_handle, e, 0,
                ((uint64_t)do_reads << 48) | burst_size);
    csrEngWrite(s_csr_handle, e, 1,
                ((uint64_t)do_writes << 48) |
                (0x2000 << 16) |
                burst_size);

    // Write data seed (will be ignored)
    csrEngWrite(s_csr_handle, e, 2, e);

    return 0;
}


//
// Run a bandwidth test (configured already with configBandwidth) on the set
// of engines indicated by emask.
//
static int
runBandwidth(
    uint64_t emask
)
{
    assert(emask != 0);

    csrEnableEngines(s_csr_handle, emask);

    // Wait for them to start
    struct timespec wait_time;
    wait_time.tv_sec = (s_is_ase ? 1 : 0);
    wait_time.tv_nsec = 1000000;
    while (csrGetEnginesEnabled(s_csr_handle) == 0)
    {
        nanosleep(&wait_time, NULL);
    }

    // Let them run for a while
    sleep(s_is_ase ? 10 : 1);
    
    csrDisableEngines(s_csr_handle, emask);

    // Wait for them to stop
    while (csrGetEnginesActive(s_csr_handle))
    {
        nanosleep(&wait_time, NULL);
    }

    if (s_afu_mhz == 0)
    {
        s_afu_mhz = csrGetClockMHz(s_csr_handle);
        printf("  AFU clock is %.1f MHz\n", s_afu_mhz);
    }

    uint64_t cycles = csrGetClockCycles(s_csr_handle);

    // Loop through the engine mask, finding all enabled engines.
    uint32_t e = 0;
    uint64_t m = emask;
    while (m)
    {
        if (m & 1)
        {
            uint64_t read_lines = csrEngRead(s_csr_handle, e, 2);
            uint64_t write_lines = csrEngRead(s_csr_handle, e, 3);
            if (!read_lines && !write_lines)
            {
                printf("  FAIL: no memory traffic detected!\n");
                return 1;
            }

            double read_bw = s_eng_bufs[e].data_byte_width * read_lines *
                             s_afu_mhz / (1000.0 * cycles);
            double write_bw = s_eng_bufs[e].data_byte_width * write_lines *
                              s_afu_mhz / (1000.0 * cycles);

            if (! write_lines)
            {
                printf("  [eng %d] Read GB/s:  %f\n", e, read_bw);
            }
            else if (! read_lines)
            {
                printf("  [eng %d] Write GB/s: %f\n", e, write_bw);
            }
            else
            {
                printf("  [eng %d] R+W GB/s:   %f (read %f, write %f)\n",
                       e, read_bw + write_bw, read_bw, write_bw);
            }
        }

        e += 1;
        m >>= 1;
    }

    return 0;
}


int
testLocalMemParams(
    int argc,
    char *argv[],
    fpga_handle accel_handle,
    t_csr_handle_p csr_handle,
    bool is_ase)
{
    int result = 0;
    s_accel_handle = accel_handle;
    s_csr_handle = csr_handle;
    s_is_ase = is_ase;

    printf("Test ID: %016" PRIx64 " %016" PRIx64 "\n",
           csrEngGlobRead(csr_handle, 1),
           csrEngGlobRead(csr_handle, 0));

    uint32_t num_engines = csrGetNumEngines(csr_handle);
    printf("Engines: %d\n", num_engines);

    // Allocate memory buffers for each engine
    s_eng_bufs = malloc(num_engines * sizeof(t_engine_buf));
    assert(NULL != s_eng_bufs);
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        // Get the maximum burst size for the engine.
        uint64_t r = csrEngRead(s_csr_handle, e, 0);
        s_eng_bufs[e].data_byte_width = r >> 56;
        s_eng_bufs[e].max_burst_size = r & 0x7fff;
        s_eng_bufs[e].natural_bursts = (r >> 15) & 1;
        s_eng_bufs[e].ordered_read_responses = (r >> 39) & 1;
        printf("  Engine %d type: %s\n", e, engine_type[(r >> 35) & 1]);
        printf("  Engine %d data byte width: %d\n", e, s_eng_bufs[e].data_byte_width);
        printf("  Engine %d max burst size: %d\n", e, s_eng_bufs[e].max_burst_size);
        printf("  Engine %d natural bursts: %d\n", e, s_eng_bufs[e].natural_bursts);
        printf("  Engine %d ordered read responses: %d\n", e, s_eng_bufs[e].ordered_read_responses);
    }
    printf("\n");
    
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        if (testSmallRegions(e))
        {
            // Quit on error
            result = 1;
            goto done;
        }
    }

    // Test bandwidth of all engines in parallel. We assume that all engines
    // have the same max. burst size.
    uint64_t all_eng_mask = ((uint64_t)1 << num_engines) - 1;
    uint64_t burst_size = 1;
    while (burst_size <= s_eng_bufs[0].max_burst_size)
    {
        printf("\nTesting burst size %ld:\n", burst_size);

        // Read
        for (uint32_t e = 0; e < num_engines; e += 1)
        {
            configBandwidth(e, burst_size, true, false);
        }
        runBandwidth(all_eng_mask);

        // Write
        for (uint32_t e = 0; e < num_engines; e += 1)
        {
            configBandwidth(e, burst_size, false, true);
        }
        runBandwidth(all_eng_mask);

        // Read+Write
        for (uint32_t e = 0; e < num_engines; e += 1)
        {
            configBandwidth(e, burst_size, true, true);
        }
        runBandwidth(all_eng_mask);

        if (s_eng_bufs[0].natural_bursts || (burst_size >= 4))
        {
            // Natural burst sizes -- test powers of 2
            burst_size <<= 1;
        }
        else
        {
            burst_size += 1;
        }
    }

  done:
    free(s_eng_bufs);

    return result;
}
