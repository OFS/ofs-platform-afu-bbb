#!/bin/bash
# Copyright(c) 2017, Intel Corporation
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
## Update the A10 GX PAC tree for use with the platform database.
##

SCRIPTNAME="$(basename -- "$0")"
SCRIPT_DIR="$(cd "$(dirname -- "$0")" 2>/dev/null && pwd -P)"

function usage {
    echo "Usage: ${SCRIPTNAME} <A10 GX PAC dir>"
    exit 1
}

function not_release {
    echo "Can't find ${tgt_dir}/${1}"
    echo "Target isn't the proper release tree"
    exit 1
}

tgt_dir="$1"
if [ "$tgt_dir" == "" ]; then
    usage
fi

# Does the target directory look like the release?
if [ ! -d "$tgt_dir" ]; then
    echo "${tgt_dir} does not exist!"
    exit 1
fi

# Find the OFS Platform Interface builder directory (it is a parent of this tree)
OFS_PLAT_SRC=`"${SCRIPT_DIR}"/../common/find_ofs_plat_dir.sh`
if [ "${OFS_PLAT_SRC}" == "" ]; then
    exit 1
fi

cd "$tgt_dir"
if [ ! -f hw/lib/platform/platform_db/a10_gx_pac_hssi.json ]; then
    not_release "hw/lib/platform/platform_db/a10_gx_pac_hssi.json"
fi

if [ ! -f hw/lib/build/afu_fit.qsf ]; then
    not_release "hw/lib/build/afu_fit.qsf"
fi

# Copy updated green_bs.sv
echo "Updating hw/lib/build/platform/green_bs.sv..."
if [ ! -f hw/lib/build/platform/green_bs.sv.orig ]; then
    mv -f hw/lib/build/platform/green_bs.sv hw/lib/build/platform/green_bs.sv.orig
fi
cp "${SCRIPT_DIR}/files/green_bs.sv" hw/lib/build/platform/

# Copy platform DB
echo "Updating hw/lib/platform/platform_db..."
cp -f "${SCRIPT_DIR}"/files/platform_db/*[^~] hw/lib/platform/platform_db/

# Generate ofs_plat_if tree
rm -rf hw/lib/build/platform/ofs_plat_if
"${OFS_PLAT_SRC}"/scripts/gen_ofs_plat_if -c "${OFS_PLAT_SRC}"/src/config/a10_gx_pac_ias.ini -t hw/lib/build/platform/ofs_plat_if -v

# Copy the HSSI interface file to ofs_plat_if. Also make it an .sv file instead
# if a .vh include file. First, rename it away from the original location in
# case the installer is run more than once.
if [ -f hw/lib/build/platform/pr_hssi_if.vh ]; then
    mv -f hw/lib/build/platform/pr_hssi_if.vh hw/lib/build/platform/pr_hssi_if.vh.orig
fi
grep -v PR_HSSI_IF_VH hw/lib/build/platform/pr_hssi_if.vh.orig > hw/lib/build/platform/ofs_plat_if/rtl/hssi/pr_hssi_if.sv
# Tie off file is specific to this platform
cp -f "${SCRIPT_DIR}"/files/ofs_plat_hssi_fiu_if_tie_off.sv hw/lib/build/platform/ofs_plat_if/rtl/hssi/

echo ""
echo "Update complete."
