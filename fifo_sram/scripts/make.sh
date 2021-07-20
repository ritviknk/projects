#!/bin/bash -f
# ****************************************************************************
# Vivado (TM) v2019.1 (64-bit)
#
# Filename    : compile.sh
# Simulator   : Xilinx Vivado Simulator
# Description : Script for compiling the simulation design source files
#
# SW Build 2552052 on Fri May 24 14:47:09 MDT 2019
#
# Copyright 1986-2019 Xilinx, Inc. All Rights Reserved.
#
# usage: compile.sh
#
# ****************************************************************************
XILINX_VIVADO=/home/ritvik/projects/hdl/install/Vivado/2019.1

#rm -rf compile.log .compile.sh.swp elab.log .runsim.tcl.swp sim*.log webtalk* xelab.pb .Xil/ xsim.dir/ xsim*.jou xvlog.log xvlog.pb vivado*.jou vivado*.log logs/*

#gui - interactive debug
#view - view waves

gui=0
view=1
clean=0
elab=1
batch=1
while getopts "bcgvne" opt; do
  case ${opt} in 
    g ) 
      gui=1
      view=0
      batch=0
      ;;
    v )
      view=1
      gui=0
      batch=0
      ;;
    c )
      clean=1
      ;;
    e )
      elab=1
      ;;
    b )
      gui=0
      batch=1
      ;;
    n )
      gui=0
      view=0
      elab=0
      batch=0
      ;;
    \?  ) 
      gui=0
      view=0
      elab=0
      batch=0
      ;;
  esac
done
shift $((OPTIND -1))

#echo $gui
#echo $batch
#echo $view
#echo $clean
#echo $elab

if [ $clean -eq 1 ] 
then
  echo "cleaning"
  rm -rf compile.log .compile.sh.swp elab.log .runsim.tcl.swp sim*.log webtalk* xelab.pb .Xil/ xsim.dir/ xsim*.jou xvlog.log xvlog.pb vivado*.jou vivado*.log
fi 

# variables
designtop="fifo_sram"
top_module="${designtop}_tb"

rundir="rundir"
log_path="../logs"
prj="../../prj"
vlib="defaultlib"
xvlog_opts="--incr --relax -sv "
xelab_opts="--relax --incr --debug typical -mt auto"
xsim_opts="-onfinish stop "
simtclfile="${prj}/runsim.tcl"

comm_list_file="${prj}/common_pkg.list"
rtl_list_file="${prj}/${designtop}.list "
tb_list_file="${prj}/${top_module}.list "
compile_log="-log ${log_path}/compile.log"
top="${vlib}.${top_module}"
sim_libs="-L ${vlib} -L unisims_ver -L unimacro_ver -L secureip"
elab_log="-log ${log_path}/elab.log"
snpsht_name="${vlib}.${top_module}"
snpsht="--snapshot ${snpsht_name}" 
sim_log="-log ${log_path}/sim.log"
waves_log="${log_path}/${top_module}.wdb"
cfgfile="${prj}/${top_module}.wcfg"
export TOP_MODULE=$top_module

pushd $rundir
echo "Running compile, elab and sim from $PWD"
if [ $elab -eq 1 ]
then
  set -Eeuo pipefail
  echo "xvlog start"
  xvlog $xvlog_opts -f $comm_list_file -f $rtl_list_file -f $tb_list_file -work $vlib $compile_log
  echo "xvlog complete "
  
  echo "xelab top TB"
  xelab $top $xelab_opts $sim_libs $elab_log $snpsht
  
  echo "xelab complete "
fi

# if batch mode run
if [ $batch -eq 1 ]
then
  echo "running xsim command batch"
  xsim $snpsht_name -tclbatch $simtclfile $sim_log $xsim_opts -wdb $waves_log
fi
# if static debug
if [ $view -eq 1 ]
then
  echo "running vivado open waves"
  vivado -source $simtclfile -tclargs -view $waves_log
  #-cfg $cfgfile
fi
# if gui run and interactive debug
if [ $gui -eq 1 ] 
then
  echo "running xsim command gui"
  xsim $snpsht_name -gui $sim_log $xsim_opts -wdb $waves_log
fi

popd
