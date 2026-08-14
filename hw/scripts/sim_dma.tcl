# ============================================================================
# Tcl Script : sim_dma.tcl
# Project    : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
# Description: Automation script to compile axi_dma_telemetry_intf.sv and run XSIM
#              simulation for tb_dma_telemetry.sv in Vivado.
# Usage      : vivado -mode batch -source sim_dma.tcl
# ============================================================================

# Close any open project in current Vivado session
catch {close_project}

# Create temporary simulation project targetting Kria KV260 (Zynq UltraScale+ XCZU5EV)
create_project -force sim_proj_dma ./sim_proj_dma -part xck26-sfvc784-2LV-c

# Set project target language to Verilog (Vivado automatically treats .sv as SystemVerilog)
set_property target_language Verilog [current_project]

# Add RTL and Testbench files
add_files -norecurse ../src/common/hft_pkg.sv
add_files -norecurse ../src/dma_intf/axi_dma_telemetry_intf.sv
add_files -norecurse ../tb/tb_dma_telemetry.sv

# Set Simulation Top to DMA Telemetry Testbench
set_property top tb_dma_telemetry [get_filesets sim_1]

# Update compile order
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# Launch Vivado Simulator (XSIM)
launch_simulation -mode behavioral

# Run simulation for 1 microsecond
run 1000ns

puts "------------------------------------------------------------------------"
puts " AXI DMA TELEMETRY LOGGING SIMULATION COMPLETED SUCCESSFULLY!"
puts "------------------------------------------------------------------------"
