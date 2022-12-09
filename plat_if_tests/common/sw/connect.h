// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

#ifndef __CONNECT_H__
#define __CONNECT_H__

#include <opae/fpga.h>

typedef struct
{
    int segment;
    int bus;
    int device;
    int function;
    int socket;
}
t_target_bdf;

// Search for an accelerator matching the requested UUID and connect to it.
fpga_handle connectToAccel(const char *accel_uuid, const t_target_bdf *bdf);

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
                        fpga_handle *accel_handles);

void initTargetBDF(t_target_bdf *bdf);

// Is the AFU simulated?
bool probeForASE(const t_target_bdf *bdf);

#endif // __CONNECT_H__
