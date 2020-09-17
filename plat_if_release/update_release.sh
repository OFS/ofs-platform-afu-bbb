#!/bin/bash
# Copyright(c) 2019, Intel Corporation
#
# Redistribution  and  use  in source  and  binary  forms,  with  or  without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of  source code  must retain the  above copyright notice,
#   this list of conditions and the following disclaimer.
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
# * Neither the name  of Intel Corporation  nor the names of its contributors
#   may be used to  endorse or promote  products derived  from this  software
#   without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,  BUT NOT LIMITED TO,  THE
# IMPLIED WARRANTIES OF  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT  SHALL THE COPYRIGHT OWNER  OR CONTRIBUTORS BE
# LIABLE  FOR  ANY  DIRECT,  INDIRECT,  INCIDENTAL,  SPECIAL,  EXEMPLARY,  OR
# CONSEQUENTIAL  DAMAGES  (INCLUDING,  BUT  NOT LIMITED  TO,  PROCUREMENT  OF
# SUBSTITUTE GOODS OR SERVICES;  LOSS OF USE,  DATA, OR PROFITS;  OR BUSINESS
# INTERRUPTION)  HOWEVER CAUSED  AND ON ANY THEORY  OF LIABILITY,  WHETHER IN
# CONTRACT,  STRICT LIABILITY,  OR TORT  (INCLUDING NEGLIGENCE  OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,  EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

##
## Given a path to a release tree:
##  - Identify the release by inspecting the existing files.
##  - Invoke the proper script to upgrade the release to support the OFS
##    platform interface.
##

SCRIPTNAME="$(basename -- "$0")"
SCRIPT_DIR="$(cd "$(dirname -- "$0")" 2>/dev/null && pwd -P)"

function usage {
    echo "Usage: ${SCRIPTNAME} <release dir>"
    exit 1
}

tgt_dir="$1"
if [ "$tgt_dir" == "" ]; then
    usage
fi

if [ ! -d "$tgt_dir" ]; then
    echo "${tgt_dir} does not exist!"
    exit 1
fi

#
# Look for a unique characteristic of a release in order to figure
# out which board it targets. Then invoke the proper updater.
#
if [ -f "${tgt_dir}"/hw/lib/platform/platform_db/s10_pac_dc_hssi.json ]; then

    echo "Updating D5005 (S10 SX PAC -- Darby Creek) FPGA release"
    "${SCRIPT_DIR}"/templates/ofs_plat_if_compat/d5005_ias/install.sh "$@"

elif [ -f "${tgt_dir}"/hw/lib/platform/platform_db/a10_gx_pac_hssi.json ]; then

    echo "Updating A10 GX PAC FPGA (Rush Creek) release"
    "${SCRIPT_DIR}"/templates/ofs_plat_if_compat/a10_gx_pac_ias/install.sh "$@"

elif [ -d "${tgt_dir}"/BBS_6.4.0/skx_pr_pkg ]; then

    echo "Updating SR-6.4.0 for Skylake integrated FPGA release"
    "${SCRIPT_DIR}"/templates/ofs_plat_if_compat/SR-6.4.0/install.sh "$@"

elif [ -d "${tgt_dir}"/Base/HW/bdw_503_pr_pkg ]; then

    echo "Updating SR-5.0.3 for Broadwell integrated FPGA release"
    "${SCRIPT_DIR}"/templates/ofs_plat_if_compat/SR-5.0.3-Release/install.sh "$@"

else

    echo "Unable to identify release at ${tgt_dir}"
    exit 1

fi

#
# "${tgt_dir}"/bin/run.sh is now "${tgt_dir}"/bin/afu_synth
#
if [ ! -e "${tgt_dir}"/bin/afu_synth ]; then
    (cd "${tgt_dir}"/bin; ln -s run.sh afu_synth)
fi
