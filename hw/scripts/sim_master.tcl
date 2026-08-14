# ============================================================================
# Tcl Script : sim_master.tcl
# Project    : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
# Description: Automation script to compile all hardware modules and run XSIM
#              simulation for Master System Testbench (tb_hft_master_system.sv).
# Usage      : vivado -mode batch -source sim_master.tcl
# ============================================================================

# Close any open project in current Vivado session
catch {close_project}

# Create temporary simulation project targetting Kria KV260 (Zynq UltraScale+ XCZU5EV)
create_project -force sim_proj_master ./sim_proj_master -part xck26-sfvc784-2LV-c

# Set project target language to Verilog (Vivado automatically treats .sv as SystemVerilog)
set_property target_language Verilog [current_project]

# Add all RTL Source Files
add_files -norecurse ../src/common/hft_pkg.sv
add_files -norecurse ../src/itch_parser/itch_parser.sv
add_files -norecurse ../src/matching_engine/matching_engine.sv
add_files -norecurse ../src/ouch_formatter/ouch_formatter.sv
add_files -norecurse ../src/network/udp_ip_stack.sv
add_files -norecurse ../src/network/emio_eth_wrapper.sv
add_files -norecurse ../src/dma_intf/axi_dma_telemetry_intf.sv
add_files -norecurse ../src/hft_top.sv

# Add Master Testbench & Data Dump Memory File
add_files -norecurse ../tb/tb_hft_master_system.sv
add_files -norecurse ../tb/itch_data_dump.mem

# Set Simulation Top to Master System Testbench
set_property top tb_hft_master_system [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Launch Vivado Simulator (XSIM)
launch_simulation -mode behavioral

# Copy memory dump file to simulation run directory
file copy -force ../tb/itch_data_dump.mem ./sim_proj_master/sim_proj_master.sim/sim_1/behav/xsim/itch_data_dump.mem

# Run simulation for 2 microseconds
run 2000ns

puts "------------------------------------------------------------------------"
puts " MASTER SYSTEM END-TO-END SIMULATION COMPLETED SUCCESSFULLY!"
puts "------------------------------------------------------------------------"
