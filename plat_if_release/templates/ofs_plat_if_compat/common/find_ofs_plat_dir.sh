#!/bin/bash

##
## Find the OFS Platform Interface builder root directory.
##

find_parent_dir() {
    local dir="${1}"
    while [[ -n "${dir}" ]]; do
        [[ -e "${dir}/${2}" ]] && {
            echo "${dir}"
            return
        }
        dir="${dir%/*}"
    done
    [[ -e /"$1" ]] && echo /
}

#get exact script path
SCRIPT_PATH=`readlink -f ${BASH_SOURCE[0]}`
#get director of script path
SCRIPT_DIR_PATH="$(dirname $SCRIPT_PATH)"

seek_dir="plat_if_develop"
found_path=`find_parent_dir "${SCRIPT_DIR_PATH}" ${seek_dir}`
if [ ! -d "${found_path}/${seek_dir}" ]; then
    echo >&2 "Failed to find parent directory named ${seek_dir}"
    exit 1
fi

builder_dir="${found_path}/${seek_dir}/ofs_plat_if"
if [ ! -d "${builder_dir}" ]; then
    echo >&2 "Failed to find ofs_plat_if in directory ${found_path}/${seek_dir}"
    exit 1
fi

echo "${builder_dir}"
