// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#include <stdlib.h>
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

// Do we know already whether this is a run on HW or simulation with ASE?
static bool ase_check_complete;
static bool is_ase_sim;

//
// Print readable error message for fpga_results
//
static void
print_err(const char *s, fpga_result res)
{
    fprintf(stderr, "Error %s: %s\n", s, fpgaErrStr(res));
}


fpga_handle
connectToAccel(const char *accel_uuid, const t_target_bdf *bdf)
{
    fpga_result r;
    fpga_handle accel_handle;
    uint32_t num_handles = 1;
    r = connectToMatchingAccels(accel_uuid, bdf, &num_handles, &accel_handle);
    assert(FPGA_OK == r);
    assert(num_handles == 1);

    return accel_handle;
}


//
// Search for all accelerators matching the requested properties and
// connect to them. The input value of *num_handles is the maximum
// number of connections allowed. (The size of accel_handles.) The
// output value of *num_handles is the actual number of connections.
//
fpga_result
connectToMatchingAccels(const char *accel_uuid,
                        const t_target_bdf *bdf,
                        uint32_t *num_handles,
                        fpga_handle *accel_handles)
{
    fpga_properties filter = NULL;
    fpga_guid guid;
    const uint32_t max_tokens = 16;
    fpga_token accel_tokens[max_tokens];
    uint32_t num_matches;
    fpga_result r;

    assert(NULL != bdf);
    assert(num_handles && *num_handles);
    assert(accel_handles);

    // Limit num_handles to max_tokens. We could be smarter and dynamically
    // allocate accel_tokens.
    if (*num_handles > max_tokens)
        *num_handles = max_tokens;

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
    r = fpgaEnumerate(&filter, 1, accel_tokens, *num_handles, &num_matches);
    if (*num_handles > num_matches)
        *num_handles = num_matches;

    if ((FPGA_OK != r) || (num_matches < 1))
    {
        fprintf(stderr, "Accelerator %s not found!\n", accel_uuid);
        goto out_destroy;
    }

    // Open accelerators
    uint32_t num_found = 0;
    for (uint32_t i = 0; i < *num_handles; i += 1)
    {
        r = fpgaOpen(accel_tokens[i], &accel_handles[num_found], 0);
        if (FPGA_OK == r)
        {
            num_found += 1;

            // While the token is available, check whether it is for HW
            // or for ASE simulation, recording it so probeForASE() below
            // doesn't have to run through the device list again.
            fpga_properties accel_props;
            uint16_t vendor_id, dev_id;
            fpgaGetProperties(accel_tokens[i], &accel_props);
            fpgaPropertiesGetVendorID(accel_props, &vendor_id);
            fpgaPropertiesGetDeviceID(accel_props, &dev_id);
            ase_check_complete = true;
            is_ase_sim = (vendor_id == 0x8086) && (dev_id == 0xa5e);
        }

        fpgaDestroyToken(&accel_tokens[i]);
    }
    *num_handles = num_found;
    if (0 != num_found) r = FPGA_OK;

  out_destroy:
    fpgaDestroyProperties(&filter);

    return r;
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

    if (ase_check_complete) return is_ase_sim;

    // Connect to the FPGA management engine
    fpgaGetProperties(NULL, &filter);
    fpgaPropertiesSetObjectType(filter, FPGA_DEVICE);

    // BDF is ignored when checking for ASE. Connecting to one is
    // sufficient to find ASE.
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
    is_ase_sim = (FPGA_OK == r) && (0xa5e == device_id);
    ase_check_complete = true;
    return is_ase_sim;

  out_destroy:
    fpgaDestroyProperties(&filter);
    return false;
}
