# ============================================================================
# Tcl Script : sim_parser.tcl
# Project    : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
# Description: Automation script to create temporary Vivado project, compile
#              SystemVerilog files, copy memory dump, and launch XSIM simulation.
# Usage      : vivado -mode batch -source sim_parser.tcl
# ============================================================================

# Close any open project in current Vivado session
catch {close_project}

# Create temporary simulation project targetting Kria KV260 (Zynq UltraScale+ XCZU5EV)
create_project -force sim_proj ./sim_proj -part xck26-sfvc784-2LV-c

# Set project target language to Verilog (Vivado automatically treats .sv as SystemVerilog)
set_property target_language Verilog [current_project]

# Add RTL and Testbench files
add_files -norecurse ../src/common/hft_pkg.sv
add_files -norecurse ../src/itch_parser/itch_parser.sv
add_files -norecurse ../tb/tb_itch_parser.sv
add_files -norecurse ../tb/tb_itch_parser_full.sv
add_files -norecurse ../tb/itch_data_dump.mem

# Set Simulation Top to full PCAP Testbench
set_property top tb_itch_parser_full [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Launch Vivado Simulator (XSIM)
launch_simulation -mode behavioral

# Ensure memory dump file is present in xsim working directory
file copy -force ../tb/itch_data_dump.mem ./sim_proj/sim_proj.sim/sim_1/behav/xsim/itch_data_dump.mem

# Run simulation for 2 microseconds
run 2000ns

puts "------------------------------------------------------------------------"
puts " SIMULATION COMPLETED SUCCESSFULLY!"
puts "------------------------------------------------------------------------"
