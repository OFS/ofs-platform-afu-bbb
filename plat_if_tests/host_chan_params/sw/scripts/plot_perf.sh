#!/bin/sh

##
##

set -e

usage() {
  echo "Usage: plot_perf <data file> <output pdf> [Platform name]"
  exit 1
}

data_file="${1}"
if [ "${data_file}" == "" ]; then
  usage
fi

out_pdf="${2}"
if [ "${out_pdf}" == "" ]; then
  usage
fi

platform="OFS FPGA"
if [ -n "${3}" ]; then
  platform="${3}"
fi

rm -f read_*.pdf write_*.pdf rw_*.pdf

gnuplot -e "platform='${platform}'; data_file='${data_file}'" scripts/plot_bw_lat.gp
gnuplot -e "platform='${platform}'; data_file='${data_file}'" scripts/plot_bw_lat_rw.gp

# Crop whitespace
for fn in read_*.pdf write_*.pdf rw_*.pdf
do
  pdfcrop --margins 10 ${fn} crop_${fn} >/dev/null
  mv -f crop_${fn} ${fn}
done

# Merge into a single PDF
gs -dBATCH -dNOPAUSE -q -sDEVICE=pdfwrite -dPDFSETTINGS=/prepress -sOutputFile="${out_pdf}" read_*.pdf write_*.pdf rw_*.pdf
rm read_*.pdf write_*.pdf rw_*.pdf
