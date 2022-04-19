//
// Copyright (c) 2022, Intel Corporation
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
// Test atomic requests on host interfaces.
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
#include "test_host_chan_atomic.h"

#define CACHELINE_BYTES 64
#define CL(x) ((x) * CACHELINE_BYTES)
#define KB(x) ((x) * 1024)
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
    fpga_handle accel_handle;
    t_csr_handle_p csr_handle;
    uint32_t accel_eng_idx;

    volatile uint64_t *atomic_buf;
    uint64_t atomic_buf_ioaddr;
    uint64_t atomic_wsid;

    volatile uint64_t *rd_buf;
    uint64_t rd_buf_ioaddr;
    uint64_t rd_wsid;

    volatile uint64_t *wb_buf;
    uint64_t wb_buf_ioaddr;
    uint64_t wb_wsid;

    struct bitmask* numa_rd_mem_mask;
    struct bitmask* numa_wr_mem_mask;
    uint32_t data_bus_bytes;
    uint32_t group;
    uint32_t eng_type;
    t_fpga_addr_mode addr_mode;
    bool natural_bursts;
    bool ordered_read_responses;
    bool atomics_supported;
}
t_engine_buf;

static bool s_is_ase;
static t_engine_buf* s_eng_bufs;
static uint32_t s_num_engines;
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
    static bool checked_clflushopt = false;
    static bool supports_clflushopt = false;

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
// Prefetch a range into the local cache.
//
static void
prefetchRange(void* start, size_t len)
{
    uint8_t* cl = start;
    uint8_t* end = start + len;
    static volatile uint64_t sum = 0;

    while (cl < end)
    {
        sum += *cl;
        cl += CACHELINE_BYTES;
    }
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

    // The test engines treat a zero buffer IOVA as a hint to disable the engine.
    // If IOVA is zero, just leave it allocated as a placeholder and get another
    // buffer.
    if (0 == *ioaddr)
    {
        buf = allocSharedBuffer(accel_handle, size, addr_mode, numa_mem_mask,
                                wsid, ioaddr);
    }

    return buf;
}


//
// Initialize the buffer being consumed by the read engine. These accesses
// are not atomic and exist merely to inject extra traffic during the test
// in order to test a system that isn't idle. Entries are initialized with
// a known pattern and the AFU checks for the pattern.
//
static void
initReadBuf(
    volatile uint64_t *buf,
    size_t n_bytes,
    size_t data_bus_bytes)
{
    uint16_t cnt = 0;
    uint32_t offset = 0;

    // The FPGA-side read engine expects the low 16 bits of every response to
    // be an incrementing count and the next 16 bits in the inverse of the count.
    while (offset < n_bytes)
    {
        *(uint16_t*)((uint8_t*)buf + offset) = cnt;
        *(uint16_t*)((uint8_t*)buf + offset + 2) = ~cnt;

        offset += data_bus_bytes;
        cnt += 1;
    }
}


static void
engineErrorAndExit(
    uint32_t num_engines,
    uint64_t emask
)
{
    printf("\nEngine mask 0x%lx failure:\n", emask);
    for (uint32_t glob_e = 0; glob_e < num_engines; glob_e += 1)
    {
        t_csr_handle_p csr_handle = s_eng_bufs[glob_e].csr_handle;

        if (emask & ((uint64_t)1 << glob_e))
        {
            printf("  Engine %d state:\n", glob_e);

            uint32_t e = s_eng_bufs[glob_e].accel_eng_idx;
            printf("    Atomic requests: %ld\n", csrEngRead(csr_handle, e, 1));
            printf("    Atomic read responses: %ld\n", csrEngRead(csr_handle, e, 2));
            printf("    Read requests: %ld\n", csrEngRead(csr_handle, e, 3));
            printf("    Read responses: %ld\n", csrEngRead(csr_handle, e, 4));
            printf("    Writeback requests: %ld\n", csrEngRead(csr_handle, e, 5));
            printf("    Writeback responses: %ld\n", csrEngRead(csr_handle, e, 6));
        }
    }

    exit(1);
}


static void
initEngine(
    uint32_t e,
    fpga_handle accel_handle,
    t_csr_handle_p csr_handle,
    uint32_t accel_eng_idx)
{
    s_eng_bufs[e].accel_handle = accel_handle;
    s_eng_bufs[e].csr_handle = csr_handle;
    s_eng_bufs[e].accel_eng_idx = accel_eng_idx;

    // Get the maximum burst size for the engine.
    uint64_t r = csrEngRead(csr_handle, accel_eng_idx, 0);
    s_eng_bufs[e].data_bus_bytes = r & 0x7fff;
    s_eng_bufs[e].natural_bursts = (r >> 15) & 1;
    s_eng_bufs[e].ordered_read_responses = (r >> 39) & 1;
    s_eng_bufs[e].atomics_supported = (r >> 50) & 1;
    s_eng_bufs[e].addr_mode = (r >> 40) & 3;
    s_eng_bufs[e].group = (r >> 47) & 7;
    s_eng_bufs[e].eng_type = (r >> 35) & 7;
    uint32_t eng_num = (r >> 42) & 31;
    printf("#  Engine %d type: %s\n", e, engine_type[s_eng_bufs[e].eng_type]);
    printf("#  Engine %d data bus bytes: %d\n", e, s_eng_bufs[e].data_bus_bytes);
    printf("#  Engine %d natural bursts: %d\n", e, s_eng_bufs[e].natural_bursts);
    printf("#  Engine %d ordered read responses: %d\n", e, s_eng_bufs[e].ordered_read_responses);
    printf("#  Engine %d atomics supported: %d\n", e, s_eng_bufs[e].atomics_supported);
    printf("#  Engine %d addressing mode: %s\n", e, addr_mode_str[s_eng_bufs[e].addr_mode]);
    printf("#  Engine %d group: %d\n", e, s_eng_bufs[e].group);

    // 64 bit mask of valid NUMA nodes, according to the FPGA configuration
    struct bitmask* numa_rd_mask;
    struct bitmask* numa_wr_mask;
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
        numa_rd_mask = numa_allocate_nodemask();
        r = fpgaNearMemGetCtrlInfo(0, &base_phys, numa_rd_mask);
        numa_wr_mask = numa_rd_mask;
#endif
    }
    else
    {
        numa_rd_mask = numa_get_membind();
        numa_wr_mask = numa_get_membind();
    }
    s_eng_bufs[e].numa_rd_mem_mask = numa_rd_mask;
    s_eng_bufs[e].numa_wr_mem_mask = numa_wr_mask;

    // Separate atomic, read and write buffers
    s_eng_bufs[e].atomic_buf = allocSharedBuffer(accel_handle, KB(4),
                                                 s_eng_bufs[e].addr_mode,
                                                 s_eng_bufs[e].numa_wr_mem_mask,
                                                 &s_eng_bufs[e].atomic_wsid,
                                                 &s_eng_bufs[e].atomic_buf_ioaddr);
    assert(NULL != s_eng_bufs[e].atomic_buf);
    printf("#  Engine %d atomic buffer: VA %p, DMA address %p\n", e,
           s_eng_bufs[e].atomic_buf, (void*)s_eng_bufs[e].atomic_buf_ioaddr);
    // Flush to guarantee that the values reach RAM
    flushRange((void*)s_eng_bufs[e].atomic_buf, KB(4));
    // Read back to the local cache. Some engine types may benefit from reading
    // cached memory. This doesn't undo the flushRange() above, which was needed
    // only to guarantee that RAM and cache are consistent.
    prefetchRange((void*)s_eng_bufs[e].atomic_buf, KB(4));

    s_eng_bufs[e].rd_buf = allocSharedBuffer(accel_handle, KB(4),
                                             s_eng_bufs[e].addr_mode,
                                             s_eng_bufs[e].numa_rd_mem_mask,
                                             &s_eng_bufs[e].rd_wsid,
                                             &s_eng_bufs[e].rd_buf_ioaddr);
    assert(NULL != s_eng_bufs[e].rd_buf);
    printf("#  Engine %d read buffer: VA %p, DMA address %p\n", e,
           s_eng_bufs[e].rd_buf, (void*)s_eng_bufs[e].rd_buf_ioaddr);
    initReadBuf(s_eng_bufs[e].rd_buf, KB(4), s_eng_bufs[e].data_bus_bytes);
    // Flush to guarantee that the values reach RAM
    flushRange((void*)s_eng_bufs[e].rd_buf, KB(4));
    // Read back to the local cache. Some engine types may benefit from reading
    // cached memory. This doesn't undo the flushRange() above, which was needed
    // only to guarantee that RAM and cache are consistent.
    prefetchRange((void*)s_eng_bufs[e].rd_buf, KB(4));

    s_eng_bufs[e].wb_buf = allocSharedBuffer(accel_handle, KB(4),
                                             s_eng_bufs[e].addr_mode,
                                             s_eng_bufs[e].numa_wr_mem_mask,
                                             &s_eng_bufs[e].wb_wsid,
                                             &s_eng_bufs[e].wb_buf_ioaddr);
    assert(NULL != s_eng_bufs[e].wb_buf);
    printf("#  Engine %d write buffer: VA %p, DMA address %p\n", e,
           s_eng_bufs[e].wb_buf, (void*)s_eng_bufs[e].wb_buf_ioaddr);

    // Set the buffer size mask
    csrEngWrite(csr_handle, accel_eng_idx, 4, KB(4) - 1);
}


//
// Initial value of an entry in the atomic update buffer, by index. The same pattern
// is used for both 32 and 64 bit tests, varying data size of course.
//
static uint64_t
initAtomicBuf(
    int idx
)
{
    // The pattern of atomic operations rotates: FetchAdd, SWAP, CAS. On the FPGA,
    // the CAS compare value is the tag, which is (0x100 + idx) & 0x1ff. Here,
    // we set some of the initialized memory to match the compare value and some
    // does not.
    if ((idx % 3 == 2) && (idx & 1))
    {
        return (0x100 + idx) & 0x1ff;
    }
    else
    {
        return ~(uint64_t)0;
    }
}


//
// Compute the expected result of an atomic update.
//
static uint64_t
expectedAtomicUpd(
    int idx,
    uint64_t init_val
)
{
    // The data passed with atomic requests is a simple function of the index.
    uint64_t atomic_arg = (0x100 + idx) & 0x1ff;
    uint64_t expected;
    switch (idx % 3)
    {
      case 0:
        // FetchAdd
        expected = init_val + atomic_arg;
        break;
      case 1:
        // Swap
        expected = atomic_arg;
        break;
      default:
        // CAS
        expected = (idx & 1) ? 0x12345 : init_val;
    }

    return expected;
}


static int
testAtomicEngine(
    uint32_t e,
    uint32_t num_engines,
    bool mode_64bit,
    bool verbose
)
{
    int num_errors = 0;
    t_csr_handle_p csr_handle = s_eng_bufs[e].csr_handle;
    uint64_t emask = (uint64_t)1 << e;

    printf("Testing atomic engine %d, %d bit mode:\n", e, mode_64bit ? 64 : 32);
    memset((void*)s_eng_bufs[e].wb_buf, 0, KB(4));
    if (mode_64bit)
    {
        for (int i = 0; i < KB(4) / 8; i += 1)
        {
            ((int64_t*)s_eng_bufs[e].atomic_buf)[i] = initAtomicBuf(i);
        }
    }
    else
    {
        for (int i = 0; i < KB(4) / 4; i += 1)
        {
            ((int32_t*)s_eng_bufs[e].atomic_buf)[i] = initAtomicBuf(i);
        }
    }

    // Set up the buffers
    csrEngWrite(csr_handle, e, 0, s_eng_bufs[e].atomic_buf_ioaddr);
    csrEngWrite(csr_handle, e, 1, s_eng_bufs[e].wb_buf_ioaddr);
    csrEngWrite(csr_handle, e, 2, s_eng_bufs[e].rd_buf_ioaddr);

    // Configure the test
    const uint32_t num_atomic_writes = 251;
    uint64_t test_config = 0;
    test_config = test_config | (1 << 17);  // Write back atomic read responses to wb_buf
    test_config = test_config | ((uint64_t)mode_64bit << 16);  // 64 bit tests?

    test_config = test_config | (1 << 18);  // Generate unrelated read requests
    test_config = test_config | (30 << 8);  // Number of reads (extra traffic tests arbiters)

    test_config = test_config | num_atomic_writes;
    csrEngWrite(csr_handle, e, 3, test_config);

    // Start the engine
    csrEnableEngines(csr_handle, emask);
    
    // Wait for engine to complete. Checking csrGetEnginesEnabled()
    // resolves a race between the request to start an engine
    // and the engine active flag going high. Execution is done when
    // the engine is enabled and the active flag goes low.
    struct timespec wait_time;
    wait_time.tv_sec = (s_is_ase ? 2 : 0);
    wait_time.tv_nsec = 1000000;
    uint64_t wait_nsec = 0;
    while ((csrGetEnginesEnabled(csr_handle) == 0) ||
           csrGetEnginesActive(csr_handle))
    {
        nanosleep(&wait_time, NULL);

        wait_nsec += wait_time.tv_nsec + wait_time.tv_sec * (uint64_t)1000000000L;
        if ((wait_nsec / (uint64_t)1000000000L) > (s_is_ase ? 20 : 5))
        {
            engineErrorAndExit(num_engines, emask);
        }
    }

    // Stop the engine
    csrDisableEngines(csr_handle, emask);

    // Validate results
    for (int i = 0; i < num_atomic_writes; i += 1)
    {
        if (mode_64bit)
        {
            uint64_t init_val = initAtomicBuf(i);
            uint64_t expected_val = expectedAtomicUpd(i, init_val);

            if (verbose)
            {
                printf("  Updated atomic_buf[%3d] = 0x%016" PRIx64 ", initial 0x%016" PRIx64 "\n", i,
                       ((int64_t*)s_eng_bufs[e].atomic_buf)[i], init_val);
            }

            // Check the buffer that was updated with atomic requests
            if (((int64_t*)s_eng_bufs[e].atomic_buf)[i] != expected_val)
            {
                num_errors += 1;
                printf("  Error: atomic_buf[%3d] = 0x%016" PRIx64 ", expected 0x%016" PRIx64 "\n", i,
                       ((int64_t*)s_eng_bufs[e].atomic_buf)[i], expected_val);
            }

            // Check read responses from atomic updates that were written to wb_buf
            if (((int64_t*)s_eng_bufs[e].wb_buf)[i] != init_val)
            {
                num_errors += 1;
                printf("  Error: wb_buf[%3d] = 0x%016" PRIx64 ", expected 0x%016" PRIx64 "\n", i,
                       ((int64_t*)s_eng_bufs[e].wb_buf)[i], init_val);
            }
        }
        else
        {
            uint32_t init_val = initAtomicBuf(i);
            uint32_t expected_val = expectedAtomicUpd(i, init_val);

            if (verbose)
            {
                printf("  Updated atomic_buf[%3d] = 0x%08" PRIx32 ", initial 0x%08" PRIx32 "\n", i,
                       ((int32_t*)s_eng_bufs[e].atomic_buf)[i], init_val);
            }

            // Check the buffer that was updated with atomic requests
            if (((int32_t*)s_eng_bufs[e].atomic_buf)[i] != expected_val)
            {
                num_errors += 1;
                printf("  Error: atomic_buf[%3d] = 0x%08" PRIx32 ", expected 0x%08" PRIx32 "\n", i,
                       ((int32_t*)s_eng_bufs[e].atomic_buf)[i], expected_val);
            }

            // Check read responses from atomic updates that were written to wb_buf
            if (((int32_t*)s_eng_bufs[e].wb_buf)[i] != init_val)
            {
                num_errors += 1;
                printf("  Error: wb_buf[%3d] = 0x%08" PRIx32 ", expected 0x%08" PRIx32 "\n", i,
                       ((int32_t*)s_eng_bufs[e].wb_buf)[i], init_val);
            }
        }
    }

    // Portion of the buffers not touched by atomic updates should still have their
    // initial values.
    if (mode_64bit)
    {
        for (int i = num_atomic_writes; i < KB(4) / 8; i += 1)
        {
            if (((int64_t*)s_eng_bufs[e].atomic_buf)[i] != initAtomicBuf(i))
            {
                num_errors += 1;
                printf("  Error: atomic_buf[%3d] = 0x%016" PRIx64 ", expected 0\n", i,
                       ((int64_t*)s_eng_bufs[e].atomic_buf)[i]);
            }

            if (((int64_t*)s_eng_bufs[e].wb_buf)[i] != 0)
            {
                num_errors += 1;
                printf("  Error: wb_buf[%3d] = 0x%016" PRIx64 ", expected 0\n", i,
                       ((int64_t*)s_eng_bufs[e].wb_buf)[i]);
            }
        }
    }
    else
    {
        for (int i = num_atomic_writes; i < KB(4) / 4; i += 1)
        {
            if (((int32_t*)s_eng_bufs[e].atomic_buf)[i] != initAtomicBuf(i))
            {
                num_errors += 1;
                printf("  Error: atomic_buf[%3d] = 0x%08" PRIx32 ", expected 0\n", i,
                       ((int32_t*)s_eng_bufs[e].atomic_buf)[i]);
            }

            if (((int32_t*)s_eng_bufs[e].wb_buf)[i] != 0)
            {
                num_errors += 1;
                printf("  Error: wb_buf[%3d] = 0x%08" PRIx32 ", expected 0\n", i,
                       ((int32_t*)s_eng_bufs[e].wb_buf)[i]);
            }
        }
    }

    // Did the non-atomic reads return expected values? The AFU sets a single
    // error bit on failure.
    uint64_t r = csrEngRead(csr_handle, e, 0);
    bool read_error = (r >> 51) & 1;
    if (read_error)
    {
        printf("Non-atomic read stream error!\n");
        num_errors += 1;
    }

    if (num_errors)
        printf("FAIL\n");
    else
        printf("PASS\n");

    return num_errors;
}


int
testHostChanAtomic(
    int argc,
    char *argv[],
    fpga_handle accel_handle,
    t_csr_handle_p csr_handle,
    bool is_ase,
    bool verbose)
{
    int result = 0;
    s_is_ase = is_ase;

    printf("# Test ID: %016" PRIx64 " %016" PRIx64 " (%ld)\n",
           csrEngGlobRead(csr_handle, 1),
           csrEngGlobRead(csr_handle, 0),
           0xff & (csrEngGlobRead(csr_handle, 2) >> 24));

    uint32_t num_engines = csrGetNumEngines(csr_handle);
    printf("# Engines: %d\n", num_engines);

    // Allocate memory buffers for each engine
    s_eng_bufs = malloc(num_engines * sizeof(t_engine_buf));
    assert(NULL != s_eng_bufs);
    s_num_engines = num_engines;
    bool atomics_supported = false;
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        initEngine(e, accel_handle, csr_handle, e);
        atomics_supported |= s_eng_bufs[e].atomics_supported;
    }
    printf("\n");

    if (!atomics_supported)
    {
        printf(num_engines > 1 ?
               "Engines do not support atomics!\n" :
               "Engine does not support atomics!\n");
        result = 1;
        goto done;
    }

    // Test each engine separately
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        if (s_eng_bufs[e].atomics_supported)
        {
            // Test 32 bit and then 64 bit atomics
            if (testAtomicEngine(e, num_engines, false, verbose) ||
                testAtomicEngine(e, num_engines, true, verbose))
            {
                // Quit on error
                result = 1;
                goto done;
            }
        }
    }

    // Release buffers
  done:
    for (uint32_t e = 0; e < num_engines; e += 1)
    {
        fpgaReleaseBuffer(accel_handle, s_eng_bufs[e].atomic_wsid);
        fpgaReleaseBuffer(accel_handle, s_eng_bufs[e].rd_wsid);
        fpgaReleaseBuffer(accel_handle, s_eng_bufs[e].wb_wsid);
    }

    return result;
}
