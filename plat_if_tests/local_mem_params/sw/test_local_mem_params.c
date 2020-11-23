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
#include <string.h>

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
    uint32_t eng_type;
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
    "Avalon-MM",
    "AXI-MM",
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
    printf("    waitrequest: 0x%lx\n", 7 & (status >> 40));
    printf("    read burst requests: %ld\n", csrEngRead(s_csr_handle, e, 1));
    if (2 == s_eng_bufs[e].eng_type)
    {
        // AXI marks RLAST so counting burst responses is possible
        printf("    read burst responses: %ld\n", csrEngRead(s_csr_handle, e, 6));
    }
    printf("    read line responses: %ld\n", csrEngRead(s_csr_handle, e, 2));
    printf("    write line requests: %ld\n", csrEngRead(s_csr_handle, e, 3));
    if (2 == s_eng_bufs[e].eng_type)
    {
        printf("    write burst responses: %ld\n", csrEngRead(s_csr_handle, e, 4));
    }
}


static void
configEngRead(
    uint32_t e,
    bool enabled,
    uint32_t burst_size,
    uint32_t num_bursts,
    uint32_t start_addr
)
{
    assert(burst_size <= 0xffff);
    assert(num_bursts <= 0xffff);
    assert(start_addr <= 0xffff);

    csrEngWrite(s_csr_handle, e, 0,
                ((uint64_t)enabled << 48) |
                ((uint64_t)num_bursts << 32) |
                (start_addr << 16) |
                burst_size);
}


static void
configEngWrite(
    uint32_t e,
    bool enabled,
    bool write_zeros,
    uint32_t burst_size,
    uint32_t num_bursts,
    uint32_t start_addr,
    uint64_t data_seed
)
{
    assert(burst_size <= 0xffff);
    assert(num_bursts <= 0xffff);
    assert(start_addr <= 0xffff);

    csrEngWrite(s_csr_handle, e, 1,
                ((uint64_t)write_zeros << 49) |
                ((uint64_t)enabled << 48) |
                ((uint64_t)num_bursts << 32) |
                (start_addr << 16) |
                burst_size);

    // Write data seed
    csrEngWrite(s_csr_handle, e, 2, data_seed);
}


//
// Run engines (tests must be configured already with fixed numbers
// of bursts. Returns after all the engines are quiet.
//
static int
runEnginesTest(
    uint64_t emask
)
{
    assert(emask != 0);

    // Start your engines
    csrEnableEngines(s_csr_handle, emask);

    // Wait for engines to complete. Checking csrGetEnginesEnabled()
    // resolves a race between the request to start an engine
    // and the engine active flag going high. Execution is done when
    // the engine is enabled and the active flag goes low.
    struct timespec wait_time;
    // Poll less often in simulation
    wait_time.tv_sec = (s_is_ase ? 2 : 0);
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
            return 1;
        }

        nanosleep(&wait_time, NULL);
    }

    // Stop the engines
    csrDisableEngines(s_csr_handle, emask);
    return 0;
}


//
// Quick test that byte masks are wired properly.
//
static int
testByteMask(
    uint32_t num_engines
)
{
    int num_errors = 0;

    printf("Testing byte masking:\n");

    // Turn off all engines. We will use engine 0 for the test.
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        configEngWrite(e, false, false, 0, 0, 0, 0);
        configEngRead(e, false, 0, 0, 0);
    }

    // Write zeros to a chunk of memory
    configEngWrite(0, true, true, 4, 2, 0, 0);

    // Start the engines
    if (runEnginesTest(1))
    {
        testDumpEngineState(0);

        num_errors += 1;
        goto fail;
    }

    // Set byte masks (up to 128 masked bytes)
    uint64_t mask_low = 0xcc4350e951224e48;
    csrEngWrite(s_csr_handle, 0, 3, mask_low);
    uint64_t mask_high = 0x373b5905de904a9b;
    csrEngWrite(s_csr_handle, 0, 4, mask_high);

    // Write a random, masked pattern. In addition to generating new data each
    // cycle, the hardware rotates { mask_high, mask_low } one bit for each
    // line written.
    srand(1);
    configEngWrite(0, true, false, 4, 2, 0, rand());
    if (runEnginesTest(1))
    {
        testDumpEngineState(0);

        num_errors += 1;
        goto fail;
    }

    // Clear masks (set them to all ones)
    csrEngWrite(s_csr_handle, 0, 3, ~0LL);
    csrEngWrite(s_csr_handle, 0, 4, ~0LL);

    // Read the values back from local memory and confirm hashes
    configEngRead(0, true, 4, 2, 0);
    configEngWrite(0, false, false, 0, 0, 0, 0);
    if (runEnginesTest(1))
    {
        testDumpEngineState(0);

        num_errors += 1;
        goto fail;
    }

    // Hash computed in hardware
    uint64_t hw_hash = csrEngRead(s_csr_handle, 0, 5);

    // Compute the expected hash for the 8 lines written
    srand(1);
    uint64_t seed = rand();
    size_t byte_len = s_eng_bufs[0].data_byte_width;
    uint64_t *data = malloc(byte_len);
    uint8_t *masked_data = malloc(byte_len);
    uint64_t *hash_vec = malloc(byte_len);
    assert((data != NULL) && (masked_data != NULL) && (hash_vec != NULL));

    testDataGenReset(byte_len, seed, data);
    testDataChkReset(byte_len, hash_vec);

    for (int i = 0; i < 8; i += 1)
    {
        // Clear the masked bytes before hashing
        memcpy(masked_data, data, byte_len);
        for (int j = 0; j < byte_len; j += 1)
        {
            uint64_t mask = (j < 64) ? mask_low : mask_high;
            if (0 == (mask & ((uint64_t)1 << (j & 63))))
            {
                masked_data[j] = 0;
            }
        }

        // Hash using the masked data that has zeros where the mask prevented
        // a write.
        testDataChkNext(byte_len, hash_vec, (uint64_t*)masked_data);
        testDataGenNext(byte_len, seed, data);

        // Rotate the mask left once per line. The hardware did this when writing.
        uint64_t new_mask_low = (mask_low << 1) | (mask_high >> 63);
        mask_high = (mask_high << 1) | (mask_low >> 63);
        mask_low = new_mask_low;
    }

    // Reduce expected hash to a 64 bit value (same as hardware)
    uint64_t expected_hash = testDataChkReduce(byte_len, hash_vec);

    free(hash_vec);
    free(masked_data);
    free(data);

    printf("  Engine %d, addr 0x%x", 0, 0);
    if (hw_hash == expected_hash)
    {
        printf(" - PASS (0x%016lx)\n", hw_hash);
    }
    else
    {
        num_errors += 1;
        printf(" - FAIL\n");
        printf("    0x%016lx, expected 0x%016lx\n", hw_hash, expected_hash);
    }

    printf("\n");
  fail:
    return num_errors;
}


static int
testBankWiring(
    uint32_t num_engines
)
{
    int num_errors = 0;
    uint64_t all_eng_mask = ((uint64_t)1 << num_engines) - 1;

    printf("Testing bank wiring:\n");

    // Write unique patterns to all memory banks. We will later read
    // them back to prove that the banks are wired correctly.
    // Write to two address regions in each bank to confirm the
    // address logic.
    srand(1);
    for (uint32_t p = 0; p < 2; p += 1)
    {
        uint32_t start_addr = (p ? 0xa00 : 0);

        for (uint32_t e = 0; e < num_engines; e += 1)
        {
            configEngWrite(e, true, false, 2, 2, start_addr, rand());
            configEngRead(e, false, 0, 0, 0);
        }

        // Start the engines
        if (runEnginesTest(all_eng_mask))
        {
            for (uint32_t e = 0; e < num_engines; e += 1)
            {
                testDumpEngineState(e);
            }
            num_errors += 1;
            goto fail;
        }
    }

    // Read the values and confirm hashes
    srand(1);
    for (uint32_t p = 0; p < 2; p += 1)
    {
        uint32_t start_addr = (p ? 0xa00 : 0);

        for (uint32_t e = 0; e < num_engines; e += 1)
        {
            configEngRead(e, true, 2, 2, start_addr);
            configEngWrite(e, false, false, 0, 0, 0, 0);
        }

        // Start the engines
        if (runEnginesTest(all_eng_mask))
        {
            for (uint32_t e = 0; e < num_engines; e += 1)
            {
                testDumpEngineState(e);
            }
            num_errors += 1;
            goto fail;
        }

        // Check hashes
        for (uint32_t e = 0; e < num_engines; e += 1)
        {
            uint64_t expected_hash = testDataChkGen(s_eng_bufs[e].data_byte_width, rand(), 4);
            uint64_t hw_hash = csrEngRead(s_csr_handle, e, 5);

            printf("  Engine %d, addr 0x%x", e, start_addr);
            if (hw_hash == expected_hash)
            {
                printf(" - PASS (0x%016lx)\n", hw_hash);
            }
            else
            {
                num_errors += 1;
                printf(" - FAIL\n");
                printf("    0x%016lx, expected 0x%016lx\n", hw_hash, expected_hash);
            }
        }
    }

    printf("\n");
  fail:
    return num_errors;
}


static int
testSmallRegions(
    uint32_t e
)
{
    int num_errors = 0;
    size_t data_byte_width = s_eng_bufs[e].data_byte_width;

    // What is the maximum burst size for the engine? It is encoded in CSR 0.
    uint64_t max_burst_size = s_eng_bufs[e].max_burst_size;
    printf("Testing engine %d, maximum burst size %ld:\n", e, max_burst_size);

    srand(1 + e);

    uint64_t burst_size = 1;
    while (burst_size <= max_burst_size)
    {
        uint64_t num_bursts = 1;
        while (num_bursts < 20)
        {
            uint64_t seed = rand();
            uint64_t expected_hash, hw_hash;
            uint64_t err_bits;

            //
            // Test only writes (mode 1), only reads (mode 2) and
            // read+write (mode 3).
            //
            for (int mode = 1; mode <= 3; mode += 1)
            {
                char *mode_str = "R+W:  ";
                if (mode == 1)
                    mode_str = "Write:";
                else if (mode == 2)
                    mode_str = "Read: ";

                printf("  %s %2ld bursts of %2ld lines", mode_str,
                       num_bursts, burst_size);

                // Configure reads
                configEngRead(e, mode & 2, burst_size, num_bursts, 0);

                // Configure writes. Use address 0 for just a write and
                // address 0xf00 for simultaneous read+write.
                uint64_t wr_seed = rand();
                uint32_t wr_start_addr = ((mode == 3) ? 0xf00 : 0);
                configEngWrite(e, mode & 1, false, burst_size, num_bursts,
                               wr_start_addr, wr_seed);

                if (runEnginesTest((uint64_t)1 << e))
                {
                    testDumpEngineState(e);
                    num_errors += 1;
                    goto fail;
                }

                // Check errors
                err_bits = (csrEngRead(s_csr_handle, e, 0) >> 43) & 0xf;
                if (err_bits)
                {
                    if (err_bits & 8) printf(" - FAIL (write response ID error)\n");
                    if (err_bits & 4) printf(" - FAIL (read response ID error)\n");
                    if (err_bits & 2) printf(" - FAIL (write response user error)\n");
                    if (err_bits & 1) printf(" - FAIL (read response user error)\n");

                    num_errors += 1;
                    goto fail;
                }

                // Compute expected hash
                expected_hash = testDataChkGen(data_byte_width, seed, num_bursts * burst_size);

                hw_hash = csrEngRead(s_csr_handle, e, 5);
                if ((mode == 1) || (expected_hash == hw_hash))
                {
                    printf(" - PASS\n");
                }
                else
                {
                    num_errors += 1;
                    printf(" - FAIL\n");
                    printf("    0x%016lx, expected 0x%016lx\n", hw_hash, expected_hash);
                }

                // Update hash if a write was done
                if (mode & 1) seed = wr_seed;
            }


            //
            // Test the write from the final R+W, looking at start address 0xf00.
            //
            configEngRead(e, true, burst_size, num_bursts, 0xf00);
            configEngWrite(e, false, false, 0, 0, 0, 0);
            if (runEnginesTest((uint64_t)1 << e))
            {
                testDumpEngineState(e);
                num_errors += 1;
                goto fail;
            }

            expected_hash = testDataChkGen(data_byte_width, seed, num_bursts * burst_size);
            hw_hash = csrEngRead(s_csr_handle, e, 5);
            if (expected_hash != hw_hash)
            {
                printf("    R+W readback failed: 0x%016lx, expected 0x%016lx\n",
                       hw_hash, expected_hash);
                num_errors += 1;
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
    configEngRead(e, do_reads, burst_size, 0, 0);
    configEngWrite(e, do_writes, false, burst_size, 0, 0x2000, e);

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
        s_eng_bufs[e].eng_type = (r >> 35) & 7;
        printf("  Engine %d type: %s\n", e, engine_type[s_eng_bufs[e].eng_type]);
        printf("  Engine %d data byte width: %d\n", e, s_eng_bufs[e].data_byte_width);
        printf("  Engine %d max burst size: %d\n", e, s_eng_bufs[e].max_burst_size);
        printf("  Engine %d natural bursts: %d\n", e, s_eng_bufs[e].natural_bursts);
        printf("  Engine %d ordered read responses: %d\n", e, s_eng_bufs[e].ordered_read_responses);
    }
    printf("\n");
    
    if (testBankWiring(num_engines))
    {
        // Quit on error
        result = 1;
        goto done;
    }

    if (testByteMask(num_engines))
    {
        // Quit on error
        result = 1;
        goto done;
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
