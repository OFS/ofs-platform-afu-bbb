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
// Test one or more host memory interfaces, varying address alignment and
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
#include "csr_mgr.h"
#include "hash32.h"
#include "utils.h"

#define CACHELINE_BYTES 64
#define CL(x) ((x) * CACHELINE_BYTES)
#define MB(x) ((x) * 1048576)

//
// Hold shared memory buffer details for one engine
//
typedef struct
{
    volatile uint64_t *rd_buf;
    uint64_t rd_buf_iova;
    uint64_t rd_wsid;

    volatile uint64_t *wr_buf;
    uint64_t wr_buf_iova;
    uint64_t wr_wsid;

    uint32_t max_burst_size;
}
t_engine_buf;

static fpga_handle s_accel_handle;
static t_csr_handle_p s_csr_handle;
static bool s_is_ase;
static t_engine_buf* s_eng_bufs;
static double s_afu_mhz;


//
// Allocate a buffer in I/O memory, shared with the FPGA.
//
static void*
allocSharedBuffer(
    fpga_handle accel_handle,
    size_t size,
    uint64_t *wsid,
    uint64_t *iova)
{
    fpga_result r;
    void* buf;

    r = fpgaPrepareBuffer(accel_handle, size, (void*)&buf, wsid, 0);
    if (FPGA_OK != r) return NULL;

    // Get the physical address of the buffer in the accelerator
    r = fpgaGetIOAddress(accel_handle, *wsid, iova);
    assert(FPGA_OK == r);

    return buf;
}


static void
initReadBuf(
    volatile uint64_t *buf,
    size_t n_bytes)
{
    uint64_t cnt = 1;

    // The data in the read buffers doesn't really matter as long as there are
    // unique values in each line. Reads will be checked with a hash (CRC).
    while (n_bytes -= sizeof(uint64_t))
    {
        *buf++ = cnt++;
    }
}


// The same hash is implemented in the read path in the hardware.
static uint32_t
computeExpectedReadHash(
    uint16_t *buf,
    uint32_t num_bursts,
    uint32_t burst_size)
{
    uint32_t hash = HASH32_DEFAULT_INIT;

    while (num_bursts--)
    {
        uint32_t num_lines = burst_size;
        while (num_lines--)
        {
            // Hash the low and high 16 bits of each line
            hash = hash32(hash, ((buf[31]) << 16) | buf[0]);
            buf += 32;
        }
    }

    return hash;
}


// Check a write buffer to confirm that the FPGA engine wrote the
// expected values.
static bool
testExpectedWrites(
    uint64_t *buf,
    uint64_t buf_iova,
    uint32_t num_bursts,
    uint32_t burst_size,
    uint32_t *line_index)
{
    *line_index = 0;

    while (num_bursts--)
    {
        uint32_t num_lines = burst_size;
        while (num_lines--)
        {
            // The low word is the IOVA
            if (buf[0] != buf_iova++) return false;
            // The high word is 0xdeadbeef
            if (buf[7] != 0xdeadbeef) return false;

            *line_index += 1;
            buf += 8;
        }
    }

    // Confirm that the next line is 0. This is the first line not
    // written by the FPGA.
    if (buf[0] != 0) return false;
    if (buf[7] != 0) return false;

    return true;
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
            // Test only reads (mode 1), only writes (mode 2) and
            // read+write (mode 3).
            //
            for (int mode = 1; mode <= 3; mode += 1)
            {
                // Read buffer base address (0 disables reads)
                if (mode & 1)
                    csrEngWrite(s_csr_handle, e, 0, s_eng_bufs[e].rd_buf_iova / CL(1));
                else
                    csrEngWrite(s_csr_handle, e, 0, 0);

                // Write buffer base address (0 disables writes)
                if (mode & 2)
                    csrEngWrite(s_csr_handle, e, 1, s_eng_bufs[e].wr_buf_iova / CL(1));
                else
                    csrEngWrite(s_csr_handle, e, 1, 0);

                char *mode_str = "R+W:  ";
                if (mode == 1)
                    mode_str = "Read: ";
                if (mode == 2)
                {
                    mode_str = "Write:";
                    // Clear the write buffer
                    memset((void*)s_eng_bufs[e].wr_buf, 0, MB(2));
                }

                printf("  %s %2ld bursts of %2ld lines", mode_str,
                       num_bursts, burst_size);

                // Configure engine burst details
                csrEngWrite(s_csr_handle, e, 2,
                            (num_bursts << 32) | burst_size);
                csrEngWrite(s_csr_handle, e, 3,
                            (num_bursts << 32) | burst_size);

                // Start your engines
                csrEnableEngines(s_csr_handle, (uint64_t)1 << e);

                // Compute the expected hash while the engine runs
                uint32_t expected_hash = 0;
                if (mode & 1)
                {
                    expected_hash = computeExpectedReadHash(
                        (uint16_t*)s_eng_bufs[e].rd_buf,
                        num_bursts, burst_size);
                }

                // Wait for engine to complete. Checking csrGetEnginesEnabled()
                // resolves a race between the request to start an engine
                // and the engine active flag going high. Execution is done when
                // the engine is enabled and the active flag goes low.
                struct timespec wait_time;
                // Poll less often in simulation
                wait_time.tv_sec = (s_is_ase ? 1 : 0);
                wait_time.tv_nsec = 1000000;
                while ((csrGetEnginesEnabled(s_csr_handle) == 0) ||
                       csrGetEnginesActive(s_csr_handle))
                {
                    nanosleep(&wait_time, NULL);
                }

                // Stop the engine
                csrDisableEngines(s_csr_handle, (uint64_t)1 << e);

                // Get the actual hash
                uint32_t actual_hash = 0;
                if (mode & 1)
                {
                    actual_hash = csrEngRead(s_csr_handle, e, 5);
                }

                // Test that writes arrived
                bool writes_ok = true;
                uint32_t write_error_line;
                if (mode & 2)
                {
                    writes_ok = testExpectedWrites(
                        (uint64_t*)s_eng_bufs[e].wr_buf,
                        s_eng_bufs[e].wr_buf_iova / CL(1),
                        num_bursts, burst_size, &write_error_line);
                }

                if (expected_hash != actual_hash)
                {
                    num_errors += 1;
                    printf("\n    Read ERROR expected hash 0x%08x found 0x%08x\n",
                           expected_hash, actual_hash);
                }
                else if (! writes_ok)
                {
                    num_errors += 1;
                    printf("\n    Write ERROR line index 0x%x\n", write_error_line);
                }
                else
                {
                    printf(" - PASS\n");
                }
            }

            num_bursts = (num_bursts * 2) + 1;
        }

        // Test every burst size up to 4 and then sparsely after that
        if ((burst_size < 4) || (burst_size == max_burst_size))
            burst_size += 1;
        else
        {
            burst_size = burst_size * 3 + 1;
            if (burst_size > max_burst_size) burst_size = max_burst_size;
        }
    }

    return num_errors;
}


//
// Configure (but don't start) a continuous bandwidth test on one engine.
//
static int
configBandwidth(
    uint32_t e,
    uint32_t burst_size,
    uint32_t mode            // 1 - read, 2 - write, 3 - read+write
)
{
    // Read buffer base address (0 disables reads)
    if (mode & 1)
        csrEngWrite(s_csr_handle, e, 0, s_eng_bufs[e].rd_buf_iova / CL(1));
    else
        csrEngWrite(s_csr_handle, e, 0, 0);

    // Write buffer base address (0 disables writes)
    if (mode & 2)
        csrEngWrite(s_csr_handle, e, 1, s_eng_bufs[e].wr_buf_iova / CL(1));
    else
        csrEngWrite(s_csr_handle, e, 1, 0);

    // Configure engine burst details
    csrEngWrite(s_csr_handle, e, 2, burst_size);
    csrEngWrite(s_csr_handle, e, 3, burst_size);

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
    uint64_t read_lines = csrEngRead(s_csr_handle, 0, 2);
    uint64_t write_lines = csrEngRead(s_csr_handle, 0, 3);
    if (!read_lines && !write_lines)
    {
        printf("ERROR: No memory traffic detected!\n");
        return 1;
    }

    double read_bw = 64 * read_lines * s_afu_mhz / (1000.0 * cycles);
    double write_bw = 64 * write_lines * s_afu_mhz / (1000.0 * cycles);

    if (! write_lines)
    {
        printf("  Read GB/s:  %f\n", read_bw);
    }
    else if (! read_lines)
    {
        printf("  Write GB/s: %f\n", write_bw);
    }
    else
    {
        printf("  R+W GB/s:   %f (read %f, write %f)\n",
               read_bw + write_bw, write_bw, write_bw);
    }

    return 0;
}


int
testHostChanParams(
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
        // Separate 2MB read and write buffers
        s_eng_bufs[e].rd_buf = allocSharedBuffer(accel_handle, MB(2),
                                                 &s_eng_bufs[e].rd_wsid,
                                                 &s_eng_bufs[e].rd_buf_iova);
        assert(NULL != s_eng_bufs[e].rd_buf);
        initReadBuf(s_eng_bufs[e].rd_buf, MB(2));

        s_eng_bufs[e].wr_buf = allocSharedBuffer(accel_handle, MB(2),
                                                 &s_eng_bufs[e].wr_wsid,
                                                 &s_eng_bufs[e].wr_buf_iova);
        assert(NULL != s_eng_bufs[e].wr_buf);

        // Set the buffer size mask. The buffer is 2MB but the mask covers
        // only 1MB. This allows bursts to flow a bit beyond the mask
        // without concern for overflow.
        csrEngWrite(csr_handle, e, 4, (MB(1) / CL(1)) - 1);

        // Get the maximum burst size for the engine.
        s_eng_bufs[e].max_burst_size = csrEngRead(s_csr_handle, e, 0) & 0xff;
    }
    
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        if (testSmallRegions(e))
        {
            // Quit on error
            result = 1;
            goto done;
        }
    }

    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        uint64_t burst_size = 1;
        while (burst_size <= s_eng_bufs[e].max_burst_size)
        {
            printf("\nTesting engine %d, burst size %ld:\n", e, burst_size);

            for (int mode = 1; mode <= 3; mode += 1)
            {
                configBandwidth(e, burst_size, mode);
                runBandwidth((uint64_t)1 << e);
            }

            burst_size += 1;
            if (burst_size == 5) burst_size = s_eng_bufs[e].max_burst_size;
        }
    }

    // Release buffers
  done:
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        fpgaReleaseBuffer(accel_handle, s_eng_bufs[e].rd_wsid);
        fpgaReleaseBuffer(accel_handle, s_eng_bufs[e].wr_wsid);
    }

    return result;
}
