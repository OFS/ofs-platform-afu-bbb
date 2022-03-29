#!/bin/bash
# script to setup common variables
set -e

# Get exact script path
COMMON_SCRIPT_PATH=`readlink -f ${BASH_SOURCE[0]}`
# Get directory of script path
COMMON_SCRIPT_DIR_PATH="$(dirname $COMMON_SCRIPT_PATH)"

usage() {
   echo "Usage: $0 -a <afu dir> -r <rtl simulation dir>" 1>&2
   echo "                       [-s <vcs|modelsim|questa>] [-p <platform>] [-v <variant>]" 1>&2
   echo "                       [-b <opae base dir>] [-i <opae install path>]" 1>&2
   echo "                       [-l <log dir>]" 1>&2
   exit 1
}

parse_args() {
   # Defaults
   v=""
   r=""
   b="${OPAE_BASEDIR}"
   i=""

   # By documented convention, OPAE_PLATFORM_ROOT points to the root of a release tree.
   # The platform's interface class is stored there.
   p="discrete"
   if [ "${OPAE_PLATFORM_ROOT}" != "" ]; then
      p=`cat "${OPAE_PLATFORM_ROOT}/hw/lib/fme-platform-class.txt"`
   fi

   if [ -x "$(command -v vcs)" ] ; then
      s="vcs"
   elif [ -x "$(command -v vsim)" ] ; then
      s="questa"
   else
      s=""
   fi

   local OPTIND
   while getopts ":a:r:s:b:p:v:f:i:l:" o; do
      case "${o}" in
         a)
            a=${OPTARG}
            ;;
         r)
            r=${OPTARG}
            ;;
         s)
            s=${OPTARG}            
            ;;
         b)
            b=${OPTARG}            
            ;;
         p)
            p=${OPTARG}
            ;;
         v)
            v=${OPTARG}
            ;;
         i)
            i=${OPTARG}
            ;;
         l)
            l=${OPTARG}
            ;;
      esac
   done
   shift $((OPTIND-1))

   afu=${a}
   rtl=${a}/hw/rtl
   app_base=${a}/sw
   variant=${v}
   platform=${p}
   rtl_sim_dir=${r}
   sim=${s}
   opae_base=${b}
   opae_install=${i}
   log_dir=${l}

   rtl_filelist="${rtl}/filelist.txt"
   if [ "${variant}" != "" ]; then
      if [ -f "${rtl}/filelist_${variant}.txt" ]; then
         rtl_filelist="${rtl}/filelist_${variant}.txt"
      elif [ -f "${rtl}/${variant}" ]; then
         rtl_filelist="${rtl}/${variant}"
      else
         echo "Unable to find sources for variant ${variant}"
         exit 1;
      fi
   fi

   # mandatory args
   if [ -z "${a}" ] || [ -z "${r}" ]; then
      usage;
   fi

   if [ -z "${log_dir}" ]; then
      log_dir="."
   fi

   if [ -z "$sim" ]; then
      echo "No RTL simulator detected or specified with -s."
      echo ""
      usage;
   elif [[ "$sim" != "vcs" ]] && [[ "$sim" != "questa" ]] && [[ "$sim" != "modelsim" ]] ; then
      echo "Supported simulators are vcs, modelsim and questa. You specified \"$sim\"."
      echo ""
      usage;
   fi

   echo "afu=$afu, rtl=$rtl, app_base=$app_base, sim=$sim, variant=$variant, platform=$platform"
   echo "rtl_sim_dir=$rtl_sim_dir"
}

menu_run_app() {
   parse_args "$@"
}

# Quiet pushd/popd
pushd () {
  command pushd "$@" > /dev/null
}
popd () {
  command popd "$@" > /dev/null
}

setup_sim_dir() {
   echo "Configuring ASE in ${rtl_sim_dir}"
   afu_sim_setup --source "${rtl_filelist}" --platform ${platform} --tool ${sim} --force \
                 --ase-mode 1 \
                 "${rtl_sim_dir}"

   pushd "$rtl_sim_dir"

   # Suppress some ModelSim warnings
   echo "MENT_VLOG_OPT += -suppress 3485,3584" >> ase_sources.mk
   echo "MENT_VSIM_OPT += -suppress 3485,3584" >> ase_sources.mk

   # add non-standard text macros (if any)
   # specify them using add_text_macros
   if [ "${add_macros}" != "" ]; then
      echo "SNPS_VLOGAN_OPT += $add_macros" >> ase_sources.mk
      echo "MENT_VLOG_OPT += $add_macros" >> ase_sources.mk
      echo "MENT_VSIM_OPT += $add_macros" >> ase_sources.mk
   fi

   popd
}

setup_quartus_home() {
   # use QUARTUS_HOME (from env)
   if [ -z "$QUARTUS_HOME" ] ; then      
      # env not found
      echo "Your environment did not set QUARTUS_HOME. Trying to detect QUARTUS_HOME.. "
      quartus_bin=`which quartus`
      quartus_bin_dir=`dirname $quartus_bin`
      export QUARTUS_HOME="$quartus_bin_dir/../"
      echo "Info: Auto-detected QUARTUS_HOME at $QUARTUS_HOME"   
   else
      echo "Detected QUARTUS_HOME at $QUARTUS_HOME"
   fi
}

# No longer required since afu_sim_setup handles this.  Kept for legacy code.
gen_qsys() {
   :
}

add_text_macros() {     
   add_macros=$1;
}

get_vcs_home() {
   # Use VCS_HOME (if available in env)      
   if [ -z "$VCS_HOME" ] ; then      
      # env not found
      echo "Your environment did not set VCS_HOME. Trying to detect VCS.. "
      vcs_bin=`which vcs`
      if [ -z "$vcs_bin" ] ; then          
         echo "Unable to find VCS. Please set the env variable VCS_HOME to your VCS install path"
         exit 1;
      else            
         vcs_bin_dir=`dirname $vcs_bin`
         export VCS_HOME="$vcs_bin_dir/../"      
         echo "Auto-detected VCS_HOME at $VCS_HOME"
      fi
   else
      echo "Detected VCS_HOME at $VCS_HOME"
   fi
}

get_mti_home() {
   if [ -z "$MTI_HOME" ] ; then
      # env not found
      echo "Your environment did not set MTI_HOME. Trying to detect Modelsim SE.. "
      vsim_bin=`which vsim`
      if [ -z "$vsim_bin" ] ; then
         echo "Unable to find Modelsim. Please set the env variable MTI_HOME to your Modelsim install path"
         exit 1;
      else
         vsim_bin_dir=`dirname $vsim_bin`
         export MTI_HOME="$vsim_bin_dir/../"   
         echo "Auto-detected MTI_HOME at $MTI_HOME"
      fi
   else
      echo "Detected MTI_HOME at $MTI_HOME"
   fi
}

setup_ase() {
   echo "Using ${sim} simulator"

   if [ "$sim" == "vcs" ] ; then
      get_vcs_home
   elif [ "$sim" == "modelsim" ] || [ "$sim" == "questa" ] ; then
      get_mti_home
   else
      echo "Unknown simulator"
      exit 1
   fi

   setup_quartus_home
}

build_sim() {
   setup_ase

   pushd $rtl_sim_dir
   # run ase make
   make
   popd
}

run_sim() {
   setup_ase

   pushd $rtl_sim_dir
   # build_sim must already have been called
   make sim
   popd
}

wait_for_sim_ready() {
   ASE_READY_FILE=$rtl_sim_dir/work/.ase_ready.pid
   while [ ! -f $ASE_READY_FILE ]
   do
      echo "Waiting for simulation to start..."
      sleep 5
   done
   echo "simulation is ready!"
}

setup_app_env() {
   # setup env variables
   export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:$app_base
   if [[ $opae_install ]]; then
      export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:$opae_install/lib64
   fi
   export ASE_WORKDIR=`readlink -m ${rtl_sim_dir}/work`
   echo "ASE workdir is $ASE_WORKDIR"

}

build_app() {
   set -x
   pushd $app_base
   # Build the software application
   #make clean
   if [[ $opae_install ]]; then
      # non-RPM flow
      echo "Non-RPM Flow"
      make prefix=$opae_install
   else
      # RPM flow
      echo "RPM Flow"
      make
   fi

   popd
}

exec_app() {
   pushd $app_base

   # Find the executable and run.  First look for an application with the suffix "_ase".
   app=$(find . -maxdepth 1 -type f -executable -name '*_ase')
   if [ "${app}" != "" ]; then
       # Run *_ase app if found
       "${app}"
   else
      # No "_ase".  Find any executable.
      app=$(find . -maxdepth 1 -type f -executable)
      if [ "${app}" != "" ]; then
         with_ase "${app}"
      fi
   fi

   popd
}

run_app() {
   setup_app_env
   wait_for_sim_ready
   build_app
   exec_app
}

kill_sim() {
   ase_workdir=$rtl_sim_dir/work/
   pid=`cat $ase_workdir/.ase_ready.pid | grep pid | cut -d "=" -s -f2-`
   echo "Killing pid = $pid"
   kill $pid
   while [ -f "$ase_workdir/.ase_ready.pid" ]; do
       sleep 1
   done
}

configure_ase_reg_mode() {
   rm -f $rtl_sim_dir/sim_afu/ase.cfg
   echo "ASE_MODE = 4" >> $rtl_sim_dir/sim_afu/ase.cfg
   find $ASE_WORKDIR -name ase.cfg -exec cp $rtl_sim_dir/sim_afu/ase.cfg {} \;
}
