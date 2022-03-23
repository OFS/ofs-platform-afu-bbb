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
#include <poll.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <assert.h>
#include <inttypes.h>
#include <time.h>
#include <pthread.h>

#include <opae/fpga.h>

// State from the AFU's JSON file, extracted using OPAE's afu_json_mgr script
#include "afu_json_info.h"
#include "test_host_chan_intr.h"


static fpga_handle s_accel_handle;
static t_csr_handle_p s_csr_handle;
static bool s_is_ase;

static fpga_event_handle *ehandles;


//
// Thread created by pthread -- one per interrupt vector.
//
static void* intr_wait_thread(void *args)
{
    fpga_result result;

    // Interrupt ID
    uint32_t id = (uintptr_t)args;

    struct pollfd pfd;
    result = fpgaGetOSObjectFromEventHandle(ehandles[id], &pfd.fd);
    assert(FPGA_OK == result);

    // Wait until the HW signals an interrupt (up to 30 seconds)
    pfd.events = POLLIN;
    int poll_res = poll(&pfd, 1, 30 * 1000);

    if (poll_res < 0)
    {
        fprintf(stderr, "Poll %d error: errno = %s\n", id, strerror(errno));
        pthread_exit((void*)1);
    } 
    else if (poll_res == 0)
    {
        fprintf(stderr, "Poll %d error: timeout \n", id);
        pthread_exit((void*)1);
    }
    else
    {
        uint64_t count;
        ssize_t bytes_read = read(pfd.fd, &count, sizeof(count));          
        if (bytes_read <= 0)
        {
            fprintf(stderr, "%d read error: %s\n", id,
                    (bytes_read < 0 ? strerror(errno) : "zero bytes read"));
            pthread_exit((void*)1);
        }

        // Count should be 1
        if (count != 1)
        {
            fprintf(stderr, "%d count error: %ld\n", id, count);
            pthread_exit((void*)1);
        }

        printf("Received ID %d\n", id);
    }

    // Success
    pthread_exit(NULL);
}


int
testHostChanIntr(
    int argc,
    char *argv[],
    fpga_handle accel_handle,
    t_csr_handle_p csr_handle,
    bool is_ase)
{
    fpga_result result = 0;
    int error_count = 0;
    s_accel_handle = accel_handle;
    s_csr_handle = csr_handle;
    s_is_ase = is_ase;

    printf("Test ID: %016" PRIx64 " %016" PRIx64 "\n",
           csrEngGlobRead(csr_handle, 1),
           csrEngGlobRead(csr_handle, 0));

    uint32_t num_engines = csrGetNumEngines(csr_handle);
    printf("Engines: %d\n", num_engines);

    // Ask the HW how many interrupt IDs are available
    uint32_t num_intr_ids = (uint8_t)(csrEngGlobRead(csr_handle, 2) >> 8);
    printf("Number of interrupt IDs: %d\n", num_intr_ids);

    ehandles = malloc(sizeof(fpga_event_handle) * num_intr_ids);
    assert(NULL != ehandles);

    pthread_t *threads = malloc(sizeof(pthread_t) * num_intr_ids);
    assert(NULL != threads);

    // Create a thread for each vector
    for (uint32_t id = 0; id < num_intr_ids; id += 1)
    {
        // Allocate a handle
        result = fpgaCreateEventHandle(&ehandles[id]);
        assert(FPGA_OK == result);

        // Register user interrupt with event handle
        result = fpgaRegisterEvent(s_accel_handle, FPGA_EVENT_INTERRUPT,
                                   ehandles[id], id);
        assert(FPGA_OK == result);

        pthread_create(&threads[id], NULL, &intr_wait_thread, (void*)(uintptr_t)id);
    }

    // Generate an interrupt for each vector
    printf("Triggering interrupts...\n");
    csrEngGlobWrite(csr_handle, 0, num_intr_ids-1);

    // Wait for threads to terminate
    for (uint32_t id = 0; id < num_intr_ids; id += 1)
    {
        void *retval;
        pthread_join(threads[id], &retval);

        if (NULL != retval)
        {
            error_count += 1;
            printf("ID %d: failed!\n", id);
        }
        else
        {
            printf("ID %d: pass\n", id);
        }

        result = fpgaUnregisterEvent(s_accel_handle, FPGA_EVENT_INTERRUPT,
                                     ehandles[id]);
        assert(FPGA_OK == result);
    }

    free(threads);

    // How many interrupt responses did the hardware get?
    uint64_t r;
    uint8_t num_resp;
    int cnt = 0;
    while (cnt < 10)
    {
        r = csrEngGlobRead(csr_handle, 3);
        num_resp = r;

        // Wait for interrupt responses to complete
        if (num_resp == num_intr_ids) break;
        cnt += 1;
        sleep(1);
    }

    uint16_t resp_mask = (r >> 8);

    if (num_resp != num_intr_ids)
    {
        printf("Error: expected %d responses, received %d\n", num_intr_ids, num_resp);
        error_count += 1;
    }
    if (resp_mask != ((1 << num_intr_ids) - 1))
    {
        printf("Error: not all %d interrupts fired, mask 0x%x\n", num_intr_ids, resp_mask);
        error_count += 1;
    }

    return error_count;
}
