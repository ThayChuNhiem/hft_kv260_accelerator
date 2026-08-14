# ============================================================================
# Tcl Script : build_project.tcl
# Project    : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
# Description: Automated Vivado Build & Bitstream Generation Script.
#              Executes full Synthesis, Place & Route, Bitstream (.bit) creation,
#              and Hardware Definition (.xsa/.hwh) export to sw/bitstream/.
# Target Part: xck26-sfvc784-2LV-c (Zynq UltraScale+ XCZU5EV)
# Usage      : vivado -mode batch -source build_project.tcl
# ============================================================================

# Step 1: Initialize Project Directory & Close Any Open Session
catch {close_project}
set proj_name "hft_kv260_build"
set proj_dir "./hft_kv260_build"
set output_dir "../../sw/bitstream"

file mkdir $output_dir

puts "========================================================================"
puts "   STARTING AUTOMATED VIVADO BITSTREAM BUILD FOR KRIA KV260"
puts "========================================================================"

create_project -force $proj_name $proj_dir -part xck26-sfvc784-2LV-c
set_property target_language Verilog [current_project]

# Step 2: Add SystemVerilog RTL Source Files
puts "[BUILD INFO] Adding RTL Source Files..."
add_files -norecurse ../src/common/hft_pkg.sv
add_files -norecurse ../src/itch_parser/itch_parser.sv
add_files -norecurse ../src/matching_engine/matching_engine.sv
add_files -norecurse ../src/ouch_formatter/ouch_formatter.sv
add_files -norecurse ../src/network/udp_ip_stack.sv
add_files -norecurse ../src/network/emio_eth_wrapper.sv
add_files -norecurse ../src/dma_intf/axi_dma_telemetry_intf.sv
add_files -norecurse ../src/hft_top.sv

# Step 3: Add Constraints File
puts "[BUILD INFO] Adding Constraints File..."
add_files -fileset constrs_1 -norecurse ../constraints/kria_kv260.xdc

# Set Top Module
set_property top hft_top [current_fileset]
update_compile_order -fileset sources_1

# Step 4: Run Logic Synthesis
puts "------------------------------------------------------------------------"
puts "[BUILD INFO] Running Logic Synthesis (synth_design)..."
puts "------------------------------------------------------------------------"
synth_design -top hft_top -part xck26-sfvc784-2LV-c -mode out_of_context

# Step 5: Run Implementation (Place & Route)
puts "------------------------------------------------------------------------"
puts "[BUILD INFO] Running Logic Optimization (opt_design)..."
opt_design

puts "[BUILD INFO] Running Placement (place_design)..."
place_design

puts "[BUILD INFO] Running Routing (route_design)..."
route_design

# Step 6: Generate Timing & Utilization Reports
puts "------------------------------------------------------------------------"
puts "[BUILD INFO] Generating Timing & Utilization Reports..."
report_timing_summary -file $output_dir/hft_kv260_timing_summary.rpt
report_utilization -file $output_dir/hft_kv260_utilization.rpt

# Step 7: Generate Bitstream (.bit) & Export Hardware XSA
puts "------------------------------------------------------------------------"
puts "[BUILD INFO] Generating Bitstream file: $output_dir/hft_kv260.bit"
write_bitstream -force $output_dir/hft_kv260.bit

puts "[BUILD INFO] Exporting Hardware Platform XSA: $output_dir/hft_kv260.xsa"
write_hw_platform -fixed -force -file $output_dir/hft_kv260.xsa

puts "========================================================================"
puts " 🎉 KRIA KV260 BITSTREAM BUILD COMPLETED SUCCESSFULLY!"
puts "    Bitstream File: $output_dir/hft_kv260.bit"
puts "    Hardware XSA  : $output_dir/hft_kv260.xsa"
puts "========================================================================"
