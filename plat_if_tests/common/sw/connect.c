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

#include <assert.h>
#include <inttypes.h>
#include <uuid/uuid.h>

#include <opae/fpga.h>
#include "tests_common.h"

#define ON_ERR_GOTO(res, label, desc)        \
    {                                        \
        if ((res) != FPGA_OK) {              \
            print_err((desc), (res));        \
            goto label;                      \
        }                                    \
    }


//
// Print readable error message for fpga_results
//
static void
print_err(const char *s, fpga_result res)
{
    fprintf(stderr, "Error %s: %s\n", s, fpgaErrStr(res));
}


//
// Search for an accelerator matching the requested UUID and connect to it.
//
fpga_handle
connectToAccel(const char *accel_uuid, const t_target_bdf *bdf)
{
    fpga_properties filter = NULL;
    fpga_guid guid;
    fpga_token accel_token = NULL;
    uint32_t num_matches;
    fpga_handle accel_handle = NULL;
    fpga_result r;

    assert(NULL != bdf);

    // Don't print verbose messages in ASE by default
    setenv("ASE_LOG", "0", 0);

    // Set up a filter that will search for an accelerator
    fpgaGetProperties(NULL, &filter);
    fpgaPropertiesSetObjectType(filter, FPGA_ACCELERATOR);

    if (-1 != bdf->segment)
    {
        r = fpgaPropertiesSetSegment(filter, bdf->segment);
        ON_ERR_GOTO(r, out_destroy, "setting segment");
    }

    if (-1 != bdf->bus)
    {
        r = fpgaPropertiesSetBus(filter, bdf->bus);
        ON_ERR_GOTO(r, out_destroy, "setting bus");
    }

    if (-1 != bdf->device)
    {
        r = fpgaPropertiesSetDevice(filter, bdf->device);
        ON_ERR_GOTO(r, out_destroy, "setting device");
    }

    if (-1 != bdf->function)
    {
        r = fpgaPropertiesSetFunction(filter, bdf->function);
        ON_ERR_GOTO(r, out_destroy, "setting function");
    }

    if (-1 != bdf->socket)
    {
        r = fpgaPropertiesSetSocketID(filter, bdf->socket);
        ON_ERR_GOTO(r, out_destroy, "setting socket id");
    }

    // Add the desired UUID to the filter
    uuid_parse(accel_uuid, guid);
    fpgaPropertiesSetGUID(filter, guid);

    // Do the search across the available FPGA contexts
    num_matches = 1;
    fpgaEnumerate(&filter, 1, &accel_token, 1, &num_matches);

    if (num_matches < 1)
    {
        fprintf(stderr, "Accelerator %s not found!\n", accel_uuid);
        goto out_destroy;
    }

    // Open accelerator
    r = fpgaOpen(accel_token, &accel_handle, 0);
    assert(FPGA_OK == r);

  out_destroy:
    // Done with token
    if (accel_token)
        fpgaDestroyToken(&accel_token);

    fpgaDestroyProperties(&filter);

    return accel_handle;
}


void
initTargetBDF(t_target_bdf *target)
{
    target->segment = -1;
    target->bus = -1;
    target->device = -1;
    target->function = -1;
    target->socket = -1;
}


bool
probeForASE(const t_target_bdf *bdf)
{
    fpga_result r = FPGA_OK;
    uint16_t device_id = 0;
    fpga_properties filter = NULL;
    uint32_t num_matches = 1;
    fpga_token fme_token;

    // Connect to the FPGA management engine
    fpgaGetProperties(NULL, &filter);
    fpgaPropertiesSetObjectType(filter, FPGA_DEVICE);

    if (-1 != bdf->segment)
    {
        r = fpgaPropertiesSetSegment(filter, bdf->segment);
        ON_ERR_GOTO(r, out_destroy, "setting segment");
    }

    if (-1 != bdf->bus)
    {
        r = fpgaPropertiesSetBus(filter, bdf->bus);
        ON_ERR_GOTO(r, out_destroy, "setting bus");
    }

    if (-1 != bdf->device)
    {
        r = fpgaPropertiesSetDevice(filter, bdf->device);
        ON_ERR_GOTO(r, out_destroy, "setting device");
    }

    if (-1 != bdf->function)
    {
        r = fpgaPropertiesSetFunction(filter, bdf->function);
        ON_ERR_GOTO(r, out_destroy, "setting function");
    }

    if (-1 != bdf->socket)
    {
        r = fpgaPropertiesSetSocketID(filter, bdf->socket);
        ON_ERR_GOTO(r, out_destroy, "setting socket id");
    }

    // Connecting to one is sufficient to find ASE.
    fpgaEnumerate(&filter, 1, &fme_token, 1, &num_matches);
    if (0 != num_matches)
    {
        // Retrieve the device ID of the FME
        fpgaGetProperties(fme_token, &filter);
        r = fpgaPropertiesGetDeviceID(filter, &device_id);
        fpgaDestroyToken(&fme_token);
    }
    fpgaDestroyProperties(&filter);

    // ASE's device ID is 0xa5e
    return ((FPGA_OK == r) && (0xa5e == device_id));

  out_destroy:
    fpgaDestroyProperties(&filter);
    return false;
}
