# ============================================================================
# File Name   : kria_kv260.xdc
# Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
# Target Board: AMD Xilinx Kria KV260 Vision AI Starter Kit
# Part        : xck26-sfvc784-2LV-c (Zynq UltraScale+ XCZU5EV)
# Description : Timing and IO Constraints File for HFT Accelerator Pipeline.
# ============================================================================

# ----------------------------------------------------------------------------
# TIMING CONSTRAINTS (200 MHz System Clock -> 5.000 ns Period)
# ----------------------------------------------------------------------------
create_clock -period 5.000 -name sys_clk_pin -waveform {0.000 2.500} [get_ports clk]

# Clock Uncertainty & Jitter Constraints
set_clock_uncertainty 0.100 [get_clocks sys_clk_pin]

# Input / Output Delay Constraints
set_input_delay -clock [get_clocks sys_clk_pin] -max 1.500 [get_ports {s_axis_rx_tvalid s_axis_rx_tlast s_axis_rx_tdata[*]}]
set_input_delay -clock [get_clocks sys_clk_pin] -min 0.200 [get_ports {s_axis_rx_tvalid s_axis_rx_tlast s_axis_rx_tdata[*]}]

set_output_delay -clock [get_clocks sys_clk_pin] -max 1.500 [get_ports {m_axis_tx_tvalid m_axis_tx_tlast m_axis_tx_tdata[*]}]
set_output_delay -clock [get_clocks sys_clk_pin] -min 0.200 [get_ports {m_axis_tx_tvalid m_axis_tx_tlast m_axis_tx_tdata[*]}]

# ----------------------------------------------------------------------------
# IO PIN ASSIGNMENTS & DRIVE STRENGTH (Kria KV260 Starter Kit SOM/Carrier)
# ----------------------------------------------------------------------------
set_property IOSTANDARD LVCMOS18 [get_ports clk]
set_property IOSTANDARD LVCMOS18 [get_ports rst_n]

# Disable Unused Pin Voltage Warnings for Synthesis
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]
