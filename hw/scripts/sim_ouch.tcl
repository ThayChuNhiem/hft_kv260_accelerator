# ============================================================================
# Tcl Script : sim_ouch.tcl
# Project    : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
# Description: Automation script to compile ouch_formatter.sv and run XSIM
#              simulation for tb_ouch_formatter.sv in Vivado.
# Usage      : vivado -mode batch -source sim_ouch.tcl
# ============================================================================

# Close any open project in current Vivado session
catch {close_project}

# Create temporary simulation project targetting Kria KV260 (Zynq UltraScale+ XCZU5EV)
create_project -force sim_proj_ouch ./sim_proj_ouch -part xck26-sfvc784-2LV-c

# Set project target language to Verilog (Vivado automatically treats .sv as SystemVerilog)
set_property target_language Verilog [current_project]

# Add RTL and Testbench files
add_files -norecurse ../src/common/hft_pkg.sv
add_files -norecurse ../src/ouch_formatter/ouch_formatter.sv
add_files -norecurse ../tb/tb_ouch_formatter.sv

# Set Simulation Top to OUCH Formatter Testbench
set_property top tb_ouch_formatter [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Launch Vivado Simulator (XSIM)
launch_simulation -mode behavioral

# Run simulation for 1 microsecond
run 1000ns

puts "------------------------------------------------------------------------"
puts " OUCH FORMATTER SIMULATION COMPLETED SUCCESSFULLY!"
puts "------------------------------------------------------------------------"
