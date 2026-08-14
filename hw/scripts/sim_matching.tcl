# ============================================================================
# Tcl Script : sim_matching.tcl
# Project    : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
# Description: Automation script to compile matching_engine.sv and run XSIM
#              simulation for tb_matching_engine.sv in Vivado.
# Usage      : vivado -mode batch -source sim_matching.tcl
# ============================================================================

# Close any open project in current Vivado session
catch {close_project}

# Create temporary simulation project targetting Kria KV260 (Zynq UltraScale+ XCZU5EV)
create_project -force sim_proj_matching ./sim_proj_matching -part xck26-sfvc784-2LV-c

# Set project target language to Verilog (Vivado automatically treats .sv as SystemVerilog)
set_property target_language Verilog [current_project]

# Add RTL and Testbench files
add_files -norecurse ../src/common/hft_pkg.sv
add_files -norecurse ../src/matching_engine/matching_engine.sv
add_files -norecurse ../tb/tb_matching_engine.sv

# Set Simulation Top to Matching Engine Testbench
set_property top tb_matching_engine [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Launch Vivado Simulator (XSIM)
launch_simulation -mode behavioral

# Run simulation for 1 microsecond
run 1000ns

puts "------------------------------------------------------------------------"
puts " MATCHING ENGINE SIMULATION COMPLETED SUCCESSFULLY!"
puts "------------------------------------------------------------------------"
