if (! exists("data_file")) exit error "Data file not specified!"
if (! exists("platform")) platform = "OFS FPGA"

# Cycle time in ns
afu_mhz = system("grep 'AFU MHz' " . data_file . " | sed -e 's/.*MHz: //'")
cycle_time = 1000.0 / afu_mhz
print sprintf("AFU cycle time: %f ns", cycle_time)
platform = platform . " (" . afu_mhz . " MHz)"

# The number of "# AFU ID" lines in the data file header indicates the number
# of accelerators (individual AFUs) used in the run. The base grouping of
# tables is all read, all write, all read+all write (3 tables). When two accelerators are
# present, one read+one write is added. When three are present, the three base
# tables are extended with one read+others write and one write+others read.
afu_cnt = system("grep -c '# AFU ID' " . data_file) + 0
set_size = 3
if (afu_cnt > 1) { set_size = 5 }
if (afu_cnt > 2) { set_size = 6 }

# Does data for 3 line requests exist?
mcl3_found = system("grep -c 'Burst size: 3' " . data_file) + 0
# Does data for 8 line requests exist?
mcl8_found = system("grep -c 'Burst size: 8' " . data_file) + 0

set term postscript color enhanced font "Helvetica" 17 butt dashed

set ylabel "Bandwidth (GB/s)" offset 1,0 font ",15"
set y2label "Latency (ns)" offset -1.75,0 font ",15"
set xlabel "Maximum Outstanding Lines" font ",15"
if (afu_cnt > 1) { set xlabel "Maximum Outstanding Lines per VF" font ",15" }

set mxtics 3
set boxwidth 0.8
set xtics out font ",12"

set ytics out nomirror font ",12"
set mytics 4
set y2tics out font ",12"

set yrange [0:]
set y2range [0:]
#set size square
set bmargin 0.5
set tmargin 0.5
set lmargin 3.0
set rmargin 6.25

set grid ytics mytics
set grid xtics

set key on inside bottom right width 2 samplen 4 spacing 1.5 font ",14"
set style fill pattern
set style data histograms

set style line 1 lc rgb "red" lw 3
set style line 2 lc rgb "red" lw 3 dashtype "-"
set style line 3 lc rgb "dark-goldenrod" lw 3
set style line 4 lc rgb "dark-goldenrod" lw 3 dashtype "-"
set style line 5 lc rgb "green" lw 3
set style line 6 lc rgb "green" lw 3 dashtype "-"
set style line 7 lc rgb "magenta" lw 3
set style line 8 lc rgb "magenta" lw 3 dashtype "-"
set style line 9 lc rgb "blue" lw 3
set style line 10 lc rgb "blue" lw 3 dashtype "-"

prefix = ""
if (afu_cnt > 1) { prefix = " All" }

set output "| ps2pdf - write_credit_vc.pdf"
set title platform . prefix . " WRITE Varying Offered Load" offset 0,1 font ",18"
set xrange [0:128]

if (mcl8_found) {
  plot data_file index (1             ) using ($6):($2) with lines smooth bezier ls 1 title "Bandwidth (MCL=1)", \
       data_file index (1             ) using ($6):($9) axes x1y2 with lines smooth bezier ls 2 title "Latency (MCL=1)", \
       data_file index (1 + set_size*1) using ($6):($2) with lines smooth bezier ls 3 title "Bandwidth (MCL=2)", \
       data_file index (1 + set_size*1) using ($6):($9) axes x1y2 with lines smooth bezier ls 4 title "Latency (MCL=2)", \
       data_file index (1 + set_size*2) using ($6):($2) with lines smooth bezier ls 5 title "Bandwidth (MCL=3)", \
       data_file index (1 + set_size*2) using ($6):($9) axes x1y2 with lines smooth bezier ls 6 title "Latency (MCL=3)", \
       data_file index (1 + set_size*3) using ($6):($2) with lines smooth bezier ls 7 title "Bandwidth (MCL=4)", \
       data_file index (1 + set_size*3) using ($6):($9) axes x1y2 with lines smooth bezier ls 8 title "Latency (MCL=4)", \
       data_file index (1 + set_size*7) using ($6):($2) with lines smooth bezier ls 9 title "Bandwidth (MCL=8)", \
       data_file index (1 + set_size*7) using ($6):($9) axes x1y2 with lines smooth bezier ls 10 title "Latency (MCL=8)"
}
if (!mcl8_found && mcl3_found) {
  plot data_file index (1             ) using ($6):($2) with lines smooth bezier ls 1 title "Bandwidth (MCL=1)", \
       data_file index (1             ) using ($6):($9) axes x1y2 with lines smooth bezier ls 2 title "Latency (MCL=1)", \
       data_file index (1 + set_size*1) using ($6):($2) with lines smooth bezier ls 3 title "Bandwidth (MCL=2)", \
       data_file index (1 + set_size*1) using ($6):($9) axes x1y2 with lines smooth bezier ls 4 title "Latency (MCL=2)", \
       data_file index (1 + set_size*2) using ($6):($2) with lines smooth bezier ls 5 title "Bandwidth (MCL=3)", \
       data_file index (1 + set_size*2) using ($6):($9) axes x1y2 with lines smooth bezier ls 6 title "Latency (MCL=3)", \
       data_file index (1 + set_size*3) using ($6):($2) with lines smooth bezier ls 7 title "Bandwidth (MCL=4)", \
       data_file index (1 + set_size*3) using ($6):($9) axes x1y2 with lines smooth bezier ls 8 title "Latency (MCL=4)"
}
if (!mcl8_found && !mcl3_found) {
  plot data_file index (1             ) using ($6):($2) with lines smooth bezier ls 1 title "Bandwidth (MCL=1)", \
       data_file index (1             ) using ($6):($9) axes x1y2 with lines smooth bezier ls 2 title "Latency (MCL=1)", \
       data_file index (1 + set_size*1) using ($6):($2) with lines smooth bezier ls 3 title "Bandwidth (MCL=2)", \
       data_file index (1 + set_size*1) using ($6):($9) axes x1y2 with lines smooth bezier ls 4 title "Latency (MCL=2)", \
       data_file index (1 + set_size*2) using ($6):($2) with lines smooth bezier ls 7 title "Bandwidth (MCL=4)", \
       data_file index (1 + set_size*2) using ($6):($9) axes x1y2 with lines smooth bezier ls 8 title "Latency (MCL=4)"
}

##
## Always plot these for the requested channel
##

set output "| ps2pdf - read_credit_vc.pdf"
set title platform . prefix . " READ Varying Offered Load" offset 0,1 font ",18"
set xrange [0:450]

if (mcl8_found) {
  plot data_file index (0             ) using ($3):($1) with lines smooth bezier ls 1 title "Bandwidth (MCL=1)", \
       data_file index (0             ) using ($3):($7) axes x1y2 with lines smooth bezier ls 2 title "Latency (MCL=1)", \
       data_file index (0 + set_size*1) using ($3):($1) with lines smooth bezier ls 3 title "Bandwidth (MCL=2)", \
       data_file index (0 + set_size*1) using ($3):($7) axes x1y2 with lines smooth bezier ls 4 title "Latency (MCL=2)", \
       data_file index (0 + set_size*2) using ($3):($1) with lines smooth bezier ls 5 title "Bandwidth (MCL=3)", \
       data_file index (0 + set_size*2) using ($3):($7) axes x1y2 with lines smooth bezier ls 6 title "Latency (MCL=3)", \
       data_file index (0 + set_size*3) using ($3):($1) with lines smooth bezier ls 7 title "Bandwidth (MCL=4)", \
       data_file index (0 + set_size*3) using ($3):($7) axes x1y2 with lines smooth bezier ls 8 title "Latency (MCL=4)", \
       data_file index (0 + set_size*7) using ($3):($1) with lines smooth bezier ls 9 title "Bandwidth (MCL=8)", \
       data_file index (0 + set_size*7) using ($3):($7) axes x1y2 with lines smooth bezier ls 10 title "Latency (MCL=8)"
}
if (!mcl8_found && mcl3_found) {
  plot data_file index (0             ) using ($3):($1) with lines smooth bezier ls 1 title "Bandwidth (MCL=1)", \
       data_file index (0             ) using ($3):($7) axes x1y2 with lines smooth bezier ls 2 title "Latency (MCL=1)", \
       data_file index (0 + set_size*1) using ($3):($1) with lines smooth bezier ls 3 title "Bandwidth (MCL=2)", \
       data_file index (0 + set_size*1) using ($3):($7) axes x1y2 with lines smooth bezier ls 4 title "Latency (MCL=2)", \
       data_file index (0 + set_size*2) using ($3):($1) with lines smooth bezier ls 5 title "Bandwidth (MCL=3)", \
       data_file index (0 + set_size*2) using ($3):($7) axes x1y2 with lines smooth bezier ls 6 title "Latency (MCL=3)", \
       data_file index (0 + set_size*3) using ($3):($1) with lines smooth bezier ls 7 title "Bandwidth (MCL=4)", \
       data_file index (0 + set_size*3) using ($3):($7) axes x1y2 with lines smooth bezier ls 8 title "Latency (MCL=4)"
}
if (!mcl8_found && !mcl3_found) {
  plot data_file index (0             ) using ($3):($1) with lines smooth bezier ls 1 title "Bandwidth (MCL=1)", \
       data_file index (0             ) using ($3):($7) axes x1y2 with lines smooth bezier ls 2 title "Latency (MCL=1)", \
       data_file index (0 + set_size*1) using ($3):($1) with lines smooth bezier ls 3 title "Bandwidth (MCL=2)", \
       data_file index (0 + set_size*1) using ($3):($7) axes x1y2 with lines smooth bezier ls 4 title "Latency (MCL=2)", \
       data_file index (0 + set_size*2) using ($3):($1) with lines smooth bezier ls 7 title "Bandwidth (MCL=4)", \
       data_file index (0 + set_size*2) using ($3):($7) axes x1y2 with lines smooth bezier ls 8 title "Latency (MCL=4)"
}
