#!/usr/local/bin/tclsh
package require cmdline

set parameters {
  {view.arg "nowavesdb"   "which static waves to view"}
  {run                    "run sim"}
}
set usage "-run : to run sims . -view <waves.db> to view static waves"
array set options [cmdline::getoptions ::argv $parameters $usage] 
parray options
set top $::env(TOP_MODULE)
#puts $top

# all functions
proc run_sim {top} {
  puts "run_sim called"
  set_param simulator.quitOnSimulationComplete 0
  log_wave -r / 
  run all
  quit  
}

proc view_sim {wdb} {
  puts "view_sim called"
  open_wave_database $wdb
  open_wave_config ../../prj/pckt_decoder_top_tb.wcfg
}

# main flow
if {$options(run)==1} {
  puts "Running xsim"
  run_sim $top
} elseif {$options(view) ne "nowavesdb"} {
  puts "Opening static database"
  view_sim $options(view)
} else {
  puts "Default option : Running xsim"
  run_sim $top
}


