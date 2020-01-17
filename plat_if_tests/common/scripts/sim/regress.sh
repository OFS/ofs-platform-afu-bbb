#!/bin/bash
## Copyright(c) 2013-2017, Intel Corporation
##
## Redistribution  and  use  in source  and  binary  forms,  with  or  without
## modification, are permitted provided that the following conditions are met:
##
## * Redistributions of  source code  must retain the  above copyright notice,
##   this list of conditions and the following disclaimer.
## * Redistributions in binary form must reproduce the above copyright notice,
##   this list of conditions and the following disclaimer in the documentation
##   and/or other materials provided with the distribution.
## * Neither the name  of Intel Corporation  nor the names of its contributors
##   may be used to  endorse or promote  products derived  from this  software
##   without specific prior written permission.
##
## THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
## AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,  BUT NOT LIMITED TO,  THE
## IMPLIED WARRANTIES OF  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
## ARE DISCLAIMED.  IN NO EVENT  SHALL THE COPYRIGHT OWNER  OR CONTRIBUTORS BE
## LIABLE  FOR  ANY  DIRECT,  INDIRECT,  INCIDENTAL,  SPECIAL,  EXEMPLARY,  OR
## CONSEQUENTIAL  DAMAGES  (INCLUDING,  BUT  NOT LIMITED  TO,  PROCUREMENT  OF
## SUBSTITUTE GOODS OR SERVICES;  LOSS OF USE,  DATA, OR PROFITS;  OR BUSINESS
## INTERRUPTION)  HOWEVER CAUSED  AND ON ANY THEORY  OF LIABILITY,  WHETHER IN
## CONTRACT,  STRICT LIABILITY,  OR TORT  (INCLUDING NEGLIGENCE  OR OTHERWISE)
## ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,  EVEN IF ADVISED OF THE
## POSSIBILITY OF SUCH DAMAGE.

##
## Run regressions of a HW/SW pair by simulating the RTL and running the
## software.  The required scripts are assumed to be in a standard
## location relative to the RTL's top-level directory. (<RTL dir>/../sim)
##

set -e

# Get exact script path
SCRIPT_PATH=`readlink -f ${BASH_SOURCE[0]}`
# Get directory of script path
SCRIPT_DIR_PATH="$(dirname $SCRIPT_PATH)"

. ${SCRIPT_DIR_PATH}/sim_common.sh
parse_args "$@"

sim_args="-a $afu -s $sim -p $platform -r $rtl_sim_dir -m $mem_model"
test_name=`basename "${afu}"`
if [ "$variant" != "" ]; then
    sim_args="${sim_args} -v $variant"
    test_name="${test_name}__${variant/.txt/}"
fi

rm -rf "${rtl_sim_dir}"
# Construct and compile the ASE simulator instance
${SCRIPT_DIR_PATH}/setup_sim.sh ${sim_args}
# Run ASE in the background
run_sim 2>&1 | tee "${log_dir}/${test_name}.hw.log" &
# Run the connected software in the foreground
${SCRIPT_DIR_PATH}/run_app.sh "$@" 2>&1 | tee "${log_dir}/${test_name}.sw.log"
echo $? > "${log_dir}/${test_name}.sw.status"

# Done.  Force ASE to exit.
kill_sim
wait
