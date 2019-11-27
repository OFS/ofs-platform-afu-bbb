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
