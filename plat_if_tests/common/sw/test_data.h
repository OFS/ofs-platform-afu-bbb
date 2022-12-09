// Copyright (C) 2022 Intel Corporation
// SPDX-License-Identifier: MIT

//
// Write test data generator and read check hash functions.
//

#ifndef __TEST_DATA_H__
#define __TEST_DATA_H__

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

// ========================================================================
//
//  Test data generator. The HW and SW versions of this code generate
//  the same sequence for a given seed.
//
// ========================================================================

//
// Reset the generator's data vector to the initial value. A 64 bit seed
// is XORed into every 64 bit word, allowing the caller to vary the
// generated values.
//
void testDataGenReset(size_t byte_len, uint64_t seed, uint64_t *data);

//
// Generate the next data vector (presumably following a write)
//
void testDataGenNext(size_t byte_len, uint64_t seed, uint64_t *data);


// ========================================================================
//
//  Test data checker. A collection of hashes are constructed as
//  new read data is added. A final function reduces the hashes to a
//  single 64 bit value. Separate hashes are maintained as reads
//  arrive so the hardware can hash an entire vector in parallel.
//
// ========================================================================

//
// Initialize the hash buckets. The vector of buckets should be the
// same byte length as the data itself.
//
void testDataChkReset(size_t byte_len, void *hash_vec);

//
// Update hashes with new data.
//
void testDataChkNext(size_t byte_len, void *hash_vec, uint64_t *data);

//
// Reduce hashes to a single 64 bit value.
//
uint64_t testDataChkReduce(size_t byte_len, void *hash_vec);

//
// Convenience function to generate a reduced hash for num_data_values
// and a seed. This tends to be useful when synthesizing check data
// to compare with the hardware. It drives testDataGen functions to
// synthesize data and testDataChk functions to compute the associated
// hash.
//
uint64_t testDataChkGen(size_t byte_len, uint64_t seed,
                        int num_data_values);


#ifdef __cplusplus
}
#endif

#endif // __TEST_DATA_H__
