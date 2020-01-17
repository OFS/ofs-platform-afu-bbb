#!/bin/bash

for group in host_chan_mmio host_chan_params; do
    echo ${group}
    tests=`cd ${group}/hw/rtl; echo test_*.txt`
    for t in ${tests}; do
        echo $t
        ./common/scripts/sim/regress.sh -v ${t} -a ${group} -r /tmp/build_sim.$$ -l logs
        rm -rf /tmp/build_sim.$$
    done
done
