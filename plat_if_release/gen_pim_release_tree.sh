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
## Generate an initial platform-specific release tree using a .ini file
## and the PIM configuration scripts. The generated tree is structured
## for use with afu_sim_setup and afu_synth_setup.
##

SCRIPTNAME="$(basename -- "$0")"
SCRIPT_DIR="$(cd "$(dirname -- "$0")" 2>/dev/null && pwd -P)"

function usage {
    echo "Usage: ${SCRIPTNAME}" 1>&2
    echo "            [-u fim-uuid]" 1>&2
    echo "            [-c platform-class-name]" 1>&2
    echo "            [-t template-source-path]" 1>&2
    echo "            [-q] [-v]" 1>&2
    echo "            [-f]" 1>&2
    echo "            <platform .ini file> <release dir>" 1>&2
    echo "" 1>&2
    echo "  -u     Set the FIM's UUID (stored in hw/lib/fme-ifc-id.txt)." 1>&2
    echo "  -c     Set the platform class name (hw/lib/fme-platform-class.txt)." 1>&2
    echo "         The default class name is derived from the .ini file name if" 1>&2
    echo "         set explicitly." 1>&2
    echo "  -t     Specify a template source. The default is relative to this script:" 1>&2
    echo "         <script path>/templates/release_tree_template." 1>&2
    echo "  -q/-v  Quite/verbose." 1>&2
    echo "  -f     Overwrite release directory if it exists." 1>&2
    echo "" 1>&2
    echo "  Given a platform description .ini file, generate a release tree template" 1>&2
    echo "  and platform-specific PIM." 1>&2
    exit 1
}

parse_args() {
    # Defaults
    FIM_UUID="00000000-0000-0000-0000-000000000000"
    PLAT_CLASS=""
    TEMPLATE_PATH="${SCRIPT_DIR}/templates/release_tree_template"
    VERBOSITY=""
    FORCE=0

    local OPTIND
    while getopts ":u:c:t:qvf" opt; do
      case "${opt}" in
        u)
            FIM_UUID=${OPTARG}
            ;;
        c)
            PLAT_CLASS=${OPTARG}
            ;;
        t)
            TEMPLATE_PATH=${OPTARG}
            ;;
        q)
            VERBOSITY="-q"
            ;;
        v)
            VERBOSITY="-v"
            ;;
        f)
            FORCE=1
            ;;
        \?)
            echo "Invalid Option: -$OPTARG" 1>&2
            echo "" 1>&2
            usage
            ;;
        :)
            usage
            ;;
      esac
    done
    shift $((OPTIND-1))

    INI_FILE="${1}"
    TGT_DIR="${2}"

    if [[ "${INI_FILE}" == "" ]] || [[ "${TGT_DIR}" == "" ]]; then
        usage
    fi

    if [[ "${PLAT_CLASS}" == "" ]]; then
        PLAT_CLASS=$(basename "${INI_FILE}")
        PLAT_CLASS="${PLAT_CLASS%.*}"
    fi
}

parse_args "$@"

# Find the OFS scripts relative to to this script's path
OFS_SCRIPTS_DIR="${SCRIPT_DIR}/../plat_if_develop/ofs_plat_if/scripts"
if [ ! -d "${OFS_SCRIPTS_DIR}" ]; then
    echo "Failed to find OFS scripts in ${OFS_SCRIPTS_DIR}" 2>&1
    exit 1
fi
if [ ! -f "${OFS_SCRIPTS_DIR}/gen_ofs_plat_if" ]; then
    echo "Failed to find OFS scripts in ${OFS_SCRIPTS_DIR}" 2>&1
    exit 1
fi

if [ -e "${TGT_DIR}" ]; then
    if [[ ${FORCE} == 0 ]]; then
        echo "Error: target directory exists. Specify \"-f\" to replace it." 2>&1
        exit 1
    fi

    rm -rf "${TGT_DIR}"
fi

if [ "${TEMPLATE_PATH}" == "" ]; then
    echo "Template directory path is empty!" 2>&1
    exit 1
fi

if [ ! -d "${TEMPLATE_PATH}" ]; then
    echo "Template not found: ${TEMPLATE_PATH}" 2>&1
    exit 1
fi

# Copy template
cp -r "${TEMPLATE_PATH}" "${TGT_DIR}/"

# Set the interface and class IDs
echo "${FIM_UUID}" > "${TGT_DIR}/hw/lib/fme-ifc-id.txt"
echo "${PLAT_CLASS}" > "${TGT_DIR}/hw/lib/fme-platform-class.txt"

# Generate the legacy PIM database
"${OFS_SCRIPTS_DIR}"/gen_ofs_plat_json ${VERBOSITY} -c "${INI_FILE}" "${TGT_DIR}/hw/lib/platform/platform_db/${PLAT_CLASS}.json"
cp "${INI_FILE}" "${TGT_DIR}/hw/lib/platform/platform_db/"

# Generate the OFS PIM
"${OFS_SCRIPTS_DIR}"/gen_ofs_plat_if ${VERBOSITY} -c "${INI_FILE}" -t "${TGT_DIR}/hw/lib/build/platform/ofs_plat_if"
