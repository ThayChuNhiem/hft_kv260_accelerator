# ============================================================================
# Tcl Script : sim_top.tcl
# Project    : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
# Description: Automation script to compile hft_top.sv and run XSIM simulation
#              for full end-to-end pipeline in Vivado.
# Usage      : vivado -mode batch -source sim_top.tcl
# ============================================================================

# Close any open project in current Vivado session
catch {close_project}

# Create temporary simulation project targetting Kria KV260 (Zynq UltraScale+ XCZU5EV)
create_project -force sim_proj_top ./sim_proj_top -part xck26-sfvc784-2LV-c

# Set project target language to Verilog (Vivado automatically treats .sv as SystemVerilog)
set_property target_language Verilog [current_project]

# Add RTL and Testbench files
add_files -norecurse ../src/common/hft_pkg.sv
add_files -norecurse ../src/itch_parser/itch_parser.sv
add_files -norecurse ../src/matching_engine/matching_engine.sv
add_files -norecurse ../src/ouch_formatter/ouch_formatter.sv
add_files -norecurse ../src/hft_top.sv
add_files -norecurse ../tb/tb_hft_top.sv
add_files -norecurse ../tb/itch_data_dump.mem

# Set Simulation Top to Full System Top Testbench
set_property top tb_hft_top [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Launch Vivado Simulator (XSIM)
launch_simulation -mode behavioral

# Copy memory dump file to simulation run directory
file copy -force ../tb/itch_data_dump.mem ./sim_proj_top/sim_proj_top.sim/sim_1/behav/xsim/itch_data_dump.mem

# Run simulation for 2 microseconds
run 2000ns

puts "------------------------------------------------------------------------"
puts " FULL END-TO-END PIPELINE SIMULATION COMPLETED SUCCESSFULLY!"
puts "------------------------------------------------------------------------"
