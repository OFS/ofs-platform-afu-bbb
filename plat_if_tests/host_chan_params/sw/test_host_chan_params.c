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

#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <assert.h>
#include <inttypes.h>
#include <uuid/uuid.h>
#include <time.h>
#include <immintrin.h>
#include <cpuid.h>
#include <numa.h>

#include <opae/fpga.h>

#ifdef FPGA_NEAR_MEM_MAP
#include <opae/fpga_near_mem_map.h>
#endif

// State from the AFU's JSON file, extracted using OPAE's afu_json_mgr script
#include "afu_json_info.h"
#include "test_host_chan_params.h"

#define CACHELINE_BYTES 64
#define CL(x) ((x) * CACHELINE_BYTES)
#define MB(x) ((x) * 1048576)

#define PROTECTION (PROT_READ | PROT_WRITE)

#ifndef MAP_HUGETLB
#define MAP_HUGETLB 0x40000
#endif
#ifndef MAP_HUGE_SHIFT
#define MAP_HUGE_SHIFT 26
#endif

#define MAP_1G_HUGEPAGE (0x1e << MAP_HUGE_SHIFT) /* 2 ^ 0x1e = 1G */

#define FLAGS_4K (MAP_PRIVATE | MAP_ANONYMOUS)
#define FLAGS_2M (FLAGS_4K | MAP_HUGETLB)
#define FLAGS_1G (FLAGS_2M | MAP_1G_HUGEPAGE)


// Engine's address mode
typedef enum
{
    ADDR_MODE_IOADDR = 0,
    ADDR_MODE_HOST_PHYSICAL = 1,
    ADDR_MODE_VIRTUAL = 3
}
t_fpga_addr_mode;

const char* addr_mode_str[] =
{
    "IOADDR",
    "Host physical",
    "reserved",
    "Virtual"
};


//
// Hold shared memory buffer details for one engine
//
typedef struct
{
    volatile uint64_t *rd_buf;
    uint64_t rd_buf_ioaddr;
    uint64_t rd_wsid;

    volatile uint64_t *wr_buf;
    uint64_t wr_buf_ioaddr;
    uint64_t wr_wsid;

    struct bitmask* numa_mem_mask;
    uint32_t max_burst_size;
    uint32_t group;
    uint32_t eng_type;
    t_fpga_addr_mode addr_mode;
    bool natural_bursts;
    bool ordered_read_responses;
    bool masked_writes;

    double fim_ifc_mhz;
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


//
// Taken from https://github.com/pmem/pmdk/blob/master/src/libpmem2/x86_64/flush.h.
// The clflushopt instruction was added for Skylake and isn't in <immintrin.h>
// _mm_clflushopt() in many of the compilers currently in use.
//
static inline void
asm_clflushopt(const void *addr)
{
    asm volatile(".byte 0x66; clflush %0" : "+m" \
        (*(volatile char *)(addr)));
}

//
// Flush a range of lines from the cache hierarchy in the entire coherence
// domain. (All cores all sockets)
//
static void
flushRange(void* start, size_t len)
{
    uint8_t* cl = start;
    uint8_t* end = start + len;

    // Does the CPU support clflushopt?
    static bool checked_clflushopt;
    static bool supports_clflushopt;

    if (! checked_clflushopt)
    {
        checked_clflushopt = true;
        supports_clflushopt = false;

        unsigned int eax, ebx, ecx, edx;
        if (__get_cpuid_max(0, 0) >= 7)
        {
            __cpuid_count(7, 0, eax, ebx, ecx, edx);
            // bit_CLFLUSHOPT is (1 << 23)
            supports_clflushopt = (((1 << 23) & ebx) != 0);
            printf("#  Processor supports clflushopt: %d\n", supports_clflushopt);
        }
    }
    if (! supports_clflushopt) return;

    while (cl < end)
    {
        asm_clflushopt(cl);
        cl += CACHELINE_BYTES;
    }

    _mm_sfence();
}


//
// Allocate a buffer in I/O memory, shared with the FPGA.
//
static void*
allocSharedBuffer(
    fpga_handle accel_handle,
    size_t size,
    t_fpga_addr_mode addr_mode,
    struct bitmask *numa_mem_mask,
    uint64_t *wsid,
    uint64_t *ioaddr)
{
    fpga_result r;
    void* buf;

    int flags;
    if (size >= MB(1024))
        flags = FLAGS_1G;
    else if (size >= 2 * MB(1))
        flags = FLAGS_2M;
    else
        flags = FLAGS_4K;

    // Preserve current NUMA configuration
    struct bitmask *numa_mems_preserve;
    numa_mems_preserve = numa_get_membind();

    // Limit NUMA to what the port requests (except in simulation)
    if (!s_is_ase) numa_set_membind(numa_mem_mask);

    // Allocate a buffer
    buf = mmap(NULL, size, (PROT_READ | PROT_WRITE), flags, -1, 0);
    assert(NULL != buf);

    // Pin the buffer
    r = fpgaPrepareBuffer(accel_handle, size, (void*)&buf, wsid, FPGA_BUF_PREALLOCATED);
    if (FPGA_OK != r) return NULL;

    // Restore NUMA configuration
    numa_set_membind(numa_mems_preserve);
    numa_bitmask_free(numa_mems_preserve);

    // Get the physical address of the buffer in the accelerator
    r = fpgaGetIOAddress(accel_handle, *wsid, ioaddr);
    assert(FPGA_OK == r);

    // Physical addresses? (ASE doesn't support this)
    if ((addr_mode == ADDR_MODE_HOST_PHYSICAL) && !s_is_ase)
    {
#ifdef FPGA_NEAR_MEM_MAP
        // Call libfpga_near_mem_map from BBB repository for address info.
        // FPGA_NEAR_MEM_MAP has been tested already in initEngine().
        fpga_near_mem_map_buf_info buf_info;
        r = fpgaNearMemGetPageAddrInfo((void*)buf, &buf_info);
        if (FPGA_OK != r)
        {
            fprintf(stderr,
                    "Physical translation from VA %p failed. Is the fpga_near_mem_map driver from\n"
                    "the OPAE intel-fpga-bbb repository installed properly?\n", buf);
            exit(1);
        }

        *ioaddr = buf_info.phys_addr - buf_info.phys_space_base;
#endif
    }

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


static void
engineErrorAndExit(
    uint32_t num_engines,
    uint64_t emask
)
{
    printf("\nEngine mask 0x%lx failure:\n", emask);
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        if (emask & ((uint64_t)1 << e))
        {
            printf("  Engine %d state:\n", e);

            printf("    Read burst requests: %ld\n", csrEngRead(s_csr_handle, e, 1));
            if (s_eng_bufs[e].eng_type == 2)
            {
                printf("    Read burst responses: %ld\n", csrEngRead(s_csr_handle, e, 6));
            }
            printf("    Read lines responses: %ld\n", csrEngRead(s_csr_handle, e, 2));

            printf("    Write burst requests: %ld\n", csrEngRead(s_csr_handle, e, 3));
            printf("    Write burst responses: %ld\n", csrEngRead(s_csr_handle, e, 4));
        }
    }

    exit(1);
}


static void
initEngine(
    uint32_t e,
    fpga_handle accel_handle,
    t_csr_handle_p csr_handle)
{
    // Get the maximum burst size for the engine.
    uint64_t r = csrEngRead(s_csr_handle, e, 0);
    s_eng_bufs[e].max_burst_size = r & 0x7fff;
    s_eng_bufs[e].natural_bursts = (r >> 15) & 1;
    s_eng_bufs[e].ordered_read_responses = (r >> 39) & 1;
    s_eng_bufs[e].masked_writes = (r >> 50) & 1;
    s_eng_bufs[e].addr_mode = (r >> 40) & 3;
    s_eng_bufs[e].group = (r >> 47) & 7;
    s_eng_bufs[e].eng_type = (r >> 35) & 7;
    uint32_t eng_num = (r >> 42) & 31;
    printf("#  Engine %d type: %s\n", e, engine_type[s_eng_bufs[e].eng_type]);
    printf("#  Engine %d max burst size: %d\n", e, s_eng_bufs[e].max_burst_size);
    printf("#  Engine %d natural bursts: %d\n", e, s_eng_bufs[e].natural_bursts);
    printf("#  Engine %d ordered read responses: %d\n", e, s_eng_bufs[e].ordered_read_responses);
    printf("#  Engine %d masked writes allowed: %d\n", e, s_eng_bufs[e].masked_writes);
    printf("#  Engine %d addressing mode: %s\n", e, addr_mode_str[s_eng_bufs[e].addr_mode]);
    printf("#  Engine %d group: %d\n", e, s_eng_bufs[e].group);

    if (eng_num != e)
    {
        fprintf(stderr, "  Engine %d internal numbering mismatch (%d)\n", e, eng_num);
        exit(1);
    }

    // 64 bit mask of valid NUMA nodes, according to the FPGA configuration
    struct bitmask* numa_mask;
    if ((s_eng_bufs[e].addr_mode == ADDR_MODE_HOST_PHYSICAL) && !s_is_ase)
    {
#ifndef FPGA_NEAR_MEM_MAP
        fprintf(stderr,
                "Port requires physical addresses. Please install the fpga_near_mem_map\n"
                "device driver from the OPAE intel-fpga-bbb repository, compile and install\n"
                "the intel-fpga-bbb software with -DBUILD_FPGA_NEAR_MEM_MAP=ON and compile\n"
                "this program with \"make FPGA_NEAR_MEM_MAP=1\".\n");
        exit(1);
#else
        // Call libfpga_near_mem_map from BBB repository for controller info.
        // At some point we will have to pass something other than 0 for the
        // controller number.
        uint64_t base_phys;
        numa_mask = numa_allocate_nodemask();
        r = fpgaNearMemGetCtrlInfo(0, &base_phys, numa_mask);
#endif
    }
    else
    {
        numa_mask = numa_get_membind();
    }
    s_eng_bufs[e].numa_mem_mask = numa_mask;

    // Separate 2MB read and write buffers
    s_eng_bufs[e].rd_buf = allocSharedBuffer(accel_handle, MB(2),
                                             s_eng_bufs[e].addr_mode,
                                             s_eng_bufs[e].numa_mem_mask,
                                             &s_eng_bufs[e].rd_wsid,
                                             &s_eng_bufs[e].rd_buf_ioaddr);
    assert(NULL != s_eng_bufs[e].rd_buf);
    printf("#  Engine %d read buffer: VA %p, DMA address %p\n", e,
           s_eng_bufs[e].rd_buf, (void*)s_eng_bufs[e].rd_buf_ioaddr);
    initReadBuf(s_eng_bufs[e].rd_buf, MB(2));
    flushRange((void*)s_eng_bufs[e].rd_buf, MB(2));

    s_eng_bufs[e].wr_buf = allocSharedBuffer(accel_handle, MB(2),
                                             s_eng_bufs[e].addr_mode,
                                             s_eng_bufs[e].numa_mem_mask,
                                             &s_eng_bufs[e].wr_wsid,
                                             &s_eng_bufs[e].wr_buf_ioaddr);
    assert(NULL != s_eng_bufs[e].wr_buf);
    printf("#  Engine %d write buffer: VA %p, DMA address %p\n", e,
           s_eng_bufs[e].wr_buf, (void*)s_eng_bufs[e].wr_buf_ioaddr);

    // Will be determined later
    s_eng_bufs[e].fim_ifc_mhz = 0;

    // Set the buffer size mask. The buffer is 2MB but the mask covers
    // only 1MB. This allows bursts to flow a bit beyond the mask
    // without concern for overflow.
    csrEngWrite(csr_handle, e, 4, (MB(1) / CL(1)) - 1);
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


// Checksum is used when hardware reads may arrive out of order.
static uint32_t
computeExpectedReadSum(
    uint16_t *buf,
    uint32_t num_bursts,
    uint32_t burst_size)
{
    uint32_t sum = 0;

    while (num_bursts--)
    {
        uint32_t num_lines = burst_size;
        while (num_lines--)
        {
            // Hash the low and high 16 bits of each line
            sum += ((buf[31] << 16) | buf[0]);
            buf += 32;
        }
    }

    return sum;
}


// Check a write buffer to confirm that the FPGA engine wrote the
// expected values.
static bool
testExpectedWrites(
    uint64_t *buf,
    uint64_t buf_ioaddr,
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
            // The low word is the IOADDR
            if (buf[0] != buf_ioaddr++) return false;
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
testMaskedWrite(
    uint32_t e
)
{
    int num_errors = 0;
    uint64_t emask = (uint64_t)1 << e;

    // No support for masked writes?
    if (! s_eng_bufs[e].masked_writes)
    {
        printf("  Engine %d does not support masked writes\n", e);
        return 0;
    }

    // No read
    csrEngWrite(s_csr_handle, e, 0, 0);
    // Configure write
    csrEngWrite(s_csr_handle, e, 1, s_eng_bufs[e].wr_buf_ioaddr / CL(1));

    // Write 1 line (1 burst of 1 line)
    csrEngWrite(s_csr_handle, e, 2, ((uint64_t)1 << 32) | 1);
    csrEngWrite(s_csr_handle, e, 3, ((uint64_t)1 << 32) | 1);

    uint64_t mask = 0x3fffffffffffffe;

    // Test a simple mask -- just prove that the mask reaches the FIM
    csrEngWrite(s_csr_handle, e, 5, mask);

    // Set the line to all ones to make it easier to observe the mask
    memset((void*)s_eng_bufs[e].wr_buf, ~0, CL(1));
    flushRange((void*)s_eng_bufs[e].wr_buf, CL(1));

    printf("  Write engine %d, mask 0x%016" PRIx64 " - ", e, mask);

    // Start engine
    csrEnableEngines(s_csr_handle, emask);

    // Wait for it to start
    struct timespec wait_time;
    wait_time.tv_sec = 0;
    wait_time.tv_nsec = 1000000;
    while ((csrGetEnginesEnabled(s_csr_handle) == 0) ||
           csrGetEnginesActive(s_csr_handle))
    {
        nanosleep(&wait_time, NULL);
    }

    csrDisableEngines(s_csr_handle, emask);

    uint64_t *buf = (uint64_t*)s_eng_bufs[e].wr_buf;

    // Test expected values (assuming mask of 0x3fffffffffffffe
    uint64_t buf_ioaddr = s_eng_bufs[e].wr_buf_ioaddr / CL(1);
    if (buf[0] != (buf_ioaddr | 0xff))
    {
        printf("FAIL (expected low 0x%016" PRIx64 ", found 0x%016" PRIx64 ")\n",
               buf_ioaddr | 0xff, buf[0]);
        num_errors += 1;
    }
    else if (buf[7] != 0xffffffffffffbeef)
    {
        printf("FAIL (expected high 0x%016" PRIx64 ", found 0x%016" PRIx64 ")\n",
               0xffffffffffffbeef, buf[7]);
        num_errors += 1;
    }
    else
    {
        printf("PASS\n");
    }

    // Clear the write mask
    csrEngWrite(s_csr_handle, e, 5, ~(uint64_t)0);

    return num_errors;
}


static int
testSmallRegions(
    uint32_t num_engines,
    uint64_t emask
)
{
    int num_errors = 0;

    // What is the maximum burst size for the engines? It is encoded in CSR 0.
    uint64_t max_burst_size = 1024;
    bool natural_bursts = false;
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        if (emask & ((uint64_t)1 << e))
        {
            if (max_burst_size > s_eng_bufs[e].max_burst_size)
                max_burst_size = s_eng_bufs[e].max_burst_size;

            natural_bursts |= s_eng_bufs[e].natural_bursts;
        }
    }

    printf("Testing emask 0x%lx, maximum burst size %ld:\n", emask, max_burst_size);

    uint64_t burst_size = 1;
    while (burst_size <= max_burst_size)
    {
        uint64_t num_bursts = 1;
        while (num_bursts < 100)
        {
            //
            // Test only reads (mode 1), only writes (mode 2) and
            // read+write (mode 3).
            //
            for (int mode = 1; mode <= 3; mode += 1)
            {
                for (uint32_t e = 0; e < num_engines; e += 1)
                {
                    if (emask & ((uint64_t)1 << e))
                    {
                        // Read buffer base address (0 disables reads)
                        if (mode & 1)
                            csrEngWrite(s_csr_handle, e, 0, s_eng_bufs[e].rd_buf_ioaddr / CL(1));
                        else
                            csrEngWrite(s_csr_handle, e, 0, 0);

                        // Write buffer base address (0 disables writes)
                        if (mode & 2)
                            csrEngWrite(s_csr_handle, e, 1, s_eng_bufs[e].wr_buf_ioaddr / CL(1));
                        else
                            csrEngWrite(s_csr_handle, e, 1, 0);

                        // Clear the write buffer
                        memset((void*)s_eng_bufs[e].wr_buf, 0, MB(2));
                        flushRange((void*)s_eng_bufs[e].wr_buf, MB(2));

                        // Configure engine burst details
                        csrEngWrite(s_csr_handle, e, 2,
                                    (num_bursts << 32) | burst_size);
                        csrEngWrite(s_csr_handle, e, 3,
                                    (num_bursts << 32) | burst_size);
                    }
                }

                char *mode_str = "R+W:  ";
                if (mode == 1)
                    mode_str = "Read: ";
                if (mode == 2)
                {
                    mode_str = "Write:";
                }

                printf("  %s %2ld bursts of %2ld lines", mode_str,
                       num_bursts, burst_size);

                // Start your engines
                csrEnableEngines(s_csr_handle, emask);

                // Wait for engine to complete. Checking csrGetEnginesEnabled()
                // resolves a race between the request to start an engine
                // and the engine active flag going high. Execution is done when
                // the engine is enabled and the active flag goes low.
                struct timespec wait_time;
                // Poll less often in simulation
                wait_time.tv_sec = 0;
                wait_time.tv_nsec = 1000000;
                uint64_t wait_nsec = 0;
                while ((csrGetEnginesEnabled(s_csr_handle) == 0) ||
                       csrGetEnginesActive(s_csr_handle))
                {
                    nanosleep(&wait_time, NULL);

                    wait_nsec += wait_time.tv_nsec + wait_time.tv_sec * (uint64_t)1000000000L;
                    if ((wait_nsec / (uint64_t)1000000000L) > (s_is_ase ? 20 : 5))
                    {
                        engineErrorAndExit(num_engines, emask);
                    }
                }

                // Stop the engine
                csrDisableEngines(s_csr_handle, emask);

                bool pass = true;
                for (uint32_t e = 0; e < num_engines; e += 1)
                {
                    if (emask & ((uint64_t)1 << e))
                    {
                        // Compute the expected hash and sum
                        uint32_t expected_hash = 0;
                        uint32_t expected_sum = 0;
                        if (mode & 1)
                        {
                            expected_hash = computeExpectedReadHash(
                                (uint16_t*)s_eng_bufs[e].rd_buf,
                                num_bursts, burst_size);

                            expected_sum = computeExpectedReadSum(
                                (uint16_t*)s_eng_bufs[e].rd_buf,
                                num_bursts, burst_size);
                        }

                        // Get the actual hash
                        uint32_t actual_hash = 0;
                        uint32_t actual_sum = 0;
                        if (mode & 1)
                        {
                            uint64_t check_val = csrEngRead(s_csr_handle, e, 5);
                            actual_hash = (uint32_t)check_val;
                            actual_sum = check_val >> 32;
                        }

                        // Test that writes arrived
                        bool writes_ok = true;
                        uint32_t write_error_line;
                        if (mode & 2)
                        {
                            flushRange((void*)s_eng_bufs[e].wr_buf, MB(2));

                            writes_ok = testExpectedWrites(
                                (uint64_t*)s_eng_bufs[e].wr_buf,
                                s_eng_bufs[e].wr_buf_ioaddr / CL(1),
                                num_bursts, burst_size, &write_error_line);
                        }

                        if (expected_sum != actual_sum)
                        {
                            pass = false;
                            num_errors += 1;
                            printf("\n - FAIL %d: read ERROR expected sum 0x%08x found 0x%08x\n",
                                   e, expected_sum, actual_sum);
                            engineErrorAndExit(num_engines, emask);
                        }
                        else if ((expected_hash != actual_hash) &&
                                 s_eng_bufs[e].ordered_read_responses)
                        {
                            pass = false;
                            num_errors += 1;
                            printf("\n - FAIL %d: read ERROR expected hash 0x%08x found 0x%08x\n",
                                   e, expected_hash, actual_hash);
                            engineErrorAndExit(num_engines, emask);
                        }
                        else if (! writes_ok)
                        {
                            pass = false;
                            num_errors += 1;
                            printf("\n - FAIL %d: write ERROR line index 0x%x\n", e, write_error_line);
                        }
                    }
                }

                if (pass) printf(" - PASS\n");
            }

            num_bursts = (num_bursts * 2) + 1;
        }

        if (natural_bursts)
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

    return num_errors;
}


//
// Configure (but don't start) a continuous bandwidth test on one engine.
//
static int
configBandwidth(
    uint32_t e,
    uint32_t burst_size,
    uint32_t mode,         // 1 - read, 2 - write, 3 - read+write
    uint32_t max_active    // Maximum outstanding requests at once (0 is unlimited)
)
{
    // Read buffer base address (0 disables reads)
    if (mode & 1)
        csrEngWrite(s_csr_handle, e, 0, s_eng_bufs[e].rd_buf_ioaddr / CL(1));
    else
        csrEngWrite(s_csr_handle, e, 0, 0);

    // Write buffer base address (0 disables writes)
    if (mode & 2)
        csrEngWrite(s_csr_handle, e, 1, s_eng_bufs[e].wr_buf_ioaddr / CL(1));
    else
        csrEngWrite(s_csr_handle, e, 1, 0);

    // Configure engine burst details
    csrEngWrite(s_csr_handle, e, 2, ((uint64_t)max_active << 48) | burst_size);
    csrEngWrite(s_csr_handle, e, 3, ((uint64_t)max_active << 48) | burst_size);

    return 0;
}


//
// Run a bandwidth test (configured already with configBandwidth) on the set
// of engines indicated by emask.
//
static int
runBandwidth(
    uint32_t num_engines,
    uint64_t emask
)
{
    assert(emask != 0);

    csrEnableEngines(s_csr_handle, emask);

    // Wait for them to start
    struct timespec wait_time;
    wait_time.tv_sec = 0;
    wait_time.tv_nsec = 1000000;
    while (csrGetEnginesEnabled(s_csr_handle) == 0)
    {
        nanosleep(&wait_time, NULL);
    }

    // Let them run for a while
    usleep(s_is_ase ? 10000000 : 100000);
    
    csrDisableEngines(s_csr_handle, emask);

    // Wait for them to stop
    while (csrGetEnginesActive(s_csr_handle))
    {
        nanosleep(&wait_time, NULL);
    }

    if (s_afu_mhz == 0)
    {
        s_afu_mhz = csrGetClockMHz(s_csr_handle);
    }
}


//
// Print bandwidth results after runBandwidth().
//
static int
printBandwidth(
    uint32_t num_engines,
    uint64_t emask
)
{
    assert(emask != 0);

    uint64_t cycles = csrGetClockCycles(s_csr_handle);
    uint64_t read_lines = 0;
    uint64_t write_lines = 0;
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        if (emask & ((uint64_t)1 << e))
        {
            read_lines += csrEngRead(s_csr_handle, e, 2);
            write_lines += csrEngRead(s_csr_handle, e, 3);
        }
    }

    if (!read_lines && !write_lines)
    {
        printf("  FAIL: no memory traffic detected!\n");
        return 1;
    }

    double read_bw = 64 * read_lines * s_afu_mhz / (1000.0 * cycles);
    double write_bw = 64 * write_lines * s_afu_mhz / (1000.0 * cycles);

    if (! write_lines)
    {
        printf("  Read GB/s:  %0.2f\n", read_bw);
    }
    else if (! read_lines)
    {
        printf("  Write GB/s: %0.2f\n", write_bw);
    }
    else
    {
        printf("  R+W GB/s:   %0.2f (read %0.2f, write %0.2f)\n",
               read_bw + write_bw, read_bw, write_bw);
    }

    return 0;
}


//
// Print bandwidth results after runBandwidth().
//
static int
printLatencyAndBandwidth(
    uint32_t num_engines,
    uint64_t emask,
    uint32_t max_active_reqs,
    bool print_header
)
{
    assert(emask != 0);

    uint64_t cycles = csrGetClockCycles(s_csr_handle);
    double afu_ns_per_cycle = 1000.0 / s_afu_mhz;

    uint64_t total_read_lines = 0;
    uint64_t total_write_lines = 0;
    double read_avg_lat = 0;
    double fim_read_avg_lat = 0;
    double write_avg_lat = 0;
    uint64_t max_reads_in_flight = 0;
    uint64_t fim_max_reads_in_flight = 0;

    // How many engines are being sampled in this test?
    uint32_t n_sampled_engines = 0;
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        if (emask & ((uint64_t)1 << e))
        {
            n_sampled_engines += 1;
        }
    }

    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        if (emask & ((uint64_t)1 << e))
        {
            // Is the engine's FIM frequency known yet?
            if (0 == s_eng_bufs[e].fim_ifc_mhz)
            {
                uint64_t fim_clk_cycles = csrEngRead(s_csr_handle, e, 14);
                uint64_t eng_clk_cycles = csrEngRead(s_csr_handle, e, 15);
                s_eng_bufs[e].fim_ifc_mhz = s_afu_mhz * fim_clk_cycles / eng_clk_cycles;
                printf("# FIM %d interface MHz: %0.1f\n", e, s_eng_bufs[e].fim_ifc_mhz);
            }
            double fim_ns_per_cycle = 1000.0 / s_eng_bufs[e].fim_ifc_mhz;

            // Count of lines read and written by the engine
            uint64_t read_lines = csrEngRead(s_csr_handle, e, 2);
            total_read_lines += read_lines;
            uint64_t write_lines = csrEngRead(s_csr_handle, e, 3);
            total_write_lines += write_lines;

            // Total active lines across all cycles, from the AFU
            uint64_t read_active_lines = csrEngRead(s_csr_handle, e, 8);
            uint64_t write_active_lines = csrEngRead(s_csr_handle, e, 9);

            // Compute average latency using Little's Law. Each sampled engine
            // is given equal weight.
            if (read_lines)
            {
                read_avg_lat += afu_ns_per_cycle * (read_active_lines / read_lines) / n_sampled_engines;
            }
            if (write_lines)
            {
                write_avg_lat += afu_ns_per_cycle * (write_active_lines / write_lines) / n_sampled_engines;
            }

            // Sample latency calculation for reads at the boundary to the FIM.
            // The separates the FIM latency from the PIM latency.
            uint64_t fim_reads = csrEngRead(s_csr_handle, e, 10);
            if (fim_reads >> 63)
            {
                fprintf(stderr, "ERROR: FIM read tracking request/response mismatch!\n");
                exit(1);
            }
            uint64_t fim_read_active = csrEngRead(s_csr_handle, e, 11);
            if (fim_reads)
            {
                fim_read_avg_lat += fim_ns_per_cycle * (fim_read_active / fim_reads) / n_sampled_engines;
            }

            max_reads_in_flight += csrEngRead(s_csr_handle, e, 12);
            uint64_t fim_max_reads = csrEngRead(s_csr_handle, e, 13);
            if (fim_max_reads >> 63)
            {
                // Unit is DWORDs, not lines. Reduce to lines.
                fim_max_reads &= 0x7fffffffffffffffL;
                fim_max_reads /= 16;
            }
            fim_max_reads_in_flight += fim_max_reads;
        }
    }

    if (!total_read_lines && !total_write_lines)
    {
        fprintf(stderr, "  FAIL: no memory traffic detected!\n");
        return 1;
    }

    double read_bw = 64 * total_read_lines * s_afu_mhz / (1000.0 * cycles);
    double write_bw = 64 * total_write_lines * s_afu_mhz / (1000.0 * cycles);

    if (print_header)
    {
        printf("Read GB/s, Write GB/s, Read Inflight Lines Limit, Read Max Measured Inflight Lines, "
               "FIM Read Max Measured Inflight Lines, Write Inflight Lines Limit, "
               "Read Avg Latency ns, FIM Read Avg Latency ns, Write Avg Latency ns\n");
    }

    printf("%0.2f %0.2f %d %ld %ld %d %0.0f %0.0f %0.0f\n",
           read_bw, write_bw,
           max_active_reqs, max_reads_in_flight, fim_max_reads_in_flight, max_active_reqs,
           read_avg_lat, fim_read_avg_lat, write_avg_lat);

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

    printf("# Test ID: %016" PRIx64 " %016" PRIx64 "\n",
           csrEngGlobRead(csr_handle, 1),
           csrEngGlobRead(csr_handle, 0));

    uint32_t num_engines = csrGetNumEngines(csr_handle);
    printf("# Engines: %d\n", num_engines);

    // Allocate memory buffers for each engine
    s_eng_bufs = malloc(num_engines * sizeof(t_engine_buf));
    assert(NULL != s_eng_bufs);
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        initEngine(e, accel_handle, csr_handle);
    }
    printf("\n");

    // Test each engine separately
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        if (testSmallRegions(num_engines, (uint64_t)1 << e))
        {
            // Quit on error
            result = 1;
            goto done;
        }
    }

    // Test all the engines at once
    if (num_engines > 1)
    {
        if (testSmallRegions(num_engines, ((uint64_t)1 << num_engines) - 1))
        {
            // Quit on error
            result = 1;
            goto done;
        }
    }

    // Masked writes
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        printf("\nTesting masked writes:\n");
        if (testMaskedWrite(e))
        {
            // Quit on error
            result = 1;
            goto done;
        }
    }

    // Bandwidth test each engine individually
    bool printed_afu_mhz = false;
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        uint64_t burst_size = 1;
        while (burst_size <= s_eng_bufs[e].max_burst_size)
        {
            printf("\nTesting engine %d, burst size %ld:\n", e, burst_size);

            for (int mode = 1; mode <= 3; mode += 1)
            {
                configBandwidth(e, burst_size, mode, 0);
                runBandwidth(num_engines, (uint64_t)1 << e);

                if (! printed_afu_mhz)
                {
                    printf("  AFU clock is %.1f MHz\n", s_afu_mhz);
                    printed_afu_mhz = true;
                }

                printBandwidth(num_engines, (uint64_t)1 << e);
            }

            if (s_eng_bufs[e].natural_bursts)
            {
                // Natural burst sizes -- test powers of 2
                burst_size <<= 1;
            }
            else
            {
                burst_size += 1;
                if ((burst_size < s_eng_bufs[e].max_burst_size) && (burst_size == 5))
                {
                    burst_size = s_eng_bufs[e].max_burst_size;
                }
            }
        }
    }

    // Bandwidth test all engines together
    if (num_engines > 1)
    {
        printf("\nTesting all engines, max burst size:\n");

        for (int mode = 1; mode <= 3; mode += 1)
        {
            for (uint32_t e = 0; e < num_engines; e += 1)
            {
                configBandwidth(e, s_eng_bufs[e].max_burst_size, mode, 0);
            }
            runBandwidth(num_engines, ((uint64_t)1 << num_engines) - 1);
            printBandwidth(num_engines, ((uint64_t)1 << num_engines) - 1);
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


int
testHostChanLatency(
    int argc,
    char *argv[],
    fpga_handle accel_handle,
    t_csr_handle_p csr_handle,
    bool is_ase,
    uint32_t engine_mask
)
{
    int result = 0;
    s_accel_handle = accel_handle;
    s_csr_handle = csr_handle;
    s_is_ase = is_ase;

    printf("# Test ID: %016" PRIx64 " %016" PRIx64 "\n",
           csrEngGlobRead(csr_handle, 1),
           csrEngGlobRead(csr_handle, 0));

    uint32_t num_engines = csrGetNumEngines(csr_handle);
    printf("# Engines: %d\n", num_engines);

    // Limit incoming engine mask to available engines
    engine_mask &= (1 << num_engines) - 1;
    if (0 == engine_mask)
    {
        fprintf(stderr, "No engines selected!\n");
        return 1;
    }

    // Allocate memory buffers for each engine
    s_eng_bufs = malloc(num_engines * sizeof(t_engine_buf));
    assert(NULL != s_eng_bufs);
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        initEngine(e, accel_handle, csr_handle);
    }

    // Bandwidth test each engine individually
    bool printed_afu_mhz = false;
    uint64_t burst_size = 1;
    while (burst_size <= 4)
    {
        for (int mode = 1; mode <= 3; mode += 1)
        {
            bool printed_header = false;
            for (uint32_t max_reqs = burst_size; max_reqs <= 512; max_reqs = (max_reqs + 4) & 0xfffffffc)
            {
                for (uint32_t e = 0; e < num_engines; e += 1)
                {
                    if (engine_mask & (1 << e))
                    {
                        configBandwidth(e, burst_size, mode, max_reqs);
                    }
                }

                runBandwidth(num_engines, engine_mask);

                if (! printed_afu_mhz)
                {
                    printf("# AFU MHz: %.1f\n", s_afu_mhz);
                    printed_afu_mhz = true;
                }

                if (! printed_header)
                {
                    printf("\n\n# Engine mask: %d\n", engine_mask);
                    printf("# Burst size: %ld\n", burst_size);
                    printf("# Mode: %s\n",
                           ((mode == 1) ? "read" : ((mode == 2) ? "write" : "read+write")));
                }

                printLatencyAndBandwidth(num_engines, engine_mask, max_reqs,
                                         ! printed_header);

                printed_header = true;
            }
        }

        // CCI-P requires naturally aligned sizes. Other protocols do not.
        if (s_eng_bufs[0].eng_type)
            burst_size += 1;
        else
            burst_size <<= 1;
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
