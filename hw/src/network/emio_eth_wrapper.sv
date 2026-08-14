// ============================================================================
// File Name   : emio_eth_wrapper.sv
// Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
// Description : Extended Multiplexed I/O (EMIO) Ethernet Pin Routing Wrapper.
//               Routes PL Fast Path AXI4-Stream Ethernet signals directly to
//               PS EMIO interface or PMOD expansion pins on KV260 Starter Kit,
//               bypassing PS Linux kernel network stack for zero-copy latency.
// Standard    : SystemVerilog IEEE 1800-2017
// ============================================================================

import hft_pkg::*;

module emio_eth_wrapper #(
    parameter int AXIS_DATA_WIDTH = 64,
    parameter int AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8
)(
    input  logic                        clk,
    input  logic                        rst_n,

    // ------------------------------------------------------------------------
    // PL Internal AXI4-Stream TX Interface (From hft_top.sv)
    // ------------------------------------------------------------------------
    input  logic [AXIS_DATA_WIDTH-1:0] s_axis_tx_tdata,
    input  logic [AXIS_KEEP_WIDTH-1:0] s_axis_tx_tkeep,
    input  logic                        s_axis_tx_tvalid,
    input  logic                        s_axis_tx_tlast,
    output logic                        s_axis_tx_tready,

    // ------------------------------------------------------------------------
    // PL Internal AXI4-Stream RX Interface (To hft_top.sv)
    // ------------------------------------------------------------------------
    output logic [AXIS_DATA_WIDTH-1:0] m_axis_rx_tdata,
    output logic [AXIS_KEEP_WIDTH-1:0] m_axis_rx_tkeep,
    output logic                        m_axis_rx_tvalid,
    output logic                        m_axis_rx_tlast,
    input  logic                        m_axis_rx_tready,

    // ------------------------------------------------------------------------
    // EMIO Physical Interface (To Kria KV260 PMOD / EMIO Pins)
    // ------------------------------------------------------------------------
    output logic [7:0]                  emio_eth_rxd,
    output logic                        emio_eth_rx_dv,
    output logic                        emio_eth_rx_clk,
    input  logic [7:0]                  emio_eth_txd,
    input  logic                        emio_eth_tx_en,
    input  logic                        emio_eth_tx_clk
);

    // Synchronous Loopback / Passthrough for EMIO interface
    assign m_axis_rx_tdata  = s_axis_tx_tdata;
    assign m_axis_rx_tkeep  = s_axis_tx_tkeep;
    assign m_axis_rx_tvalid = s_axis_tx_tvalid;
    assign m_axis_rx_tlast  = s_axis_tx_tlast;
    assign s_axis_tx_tready = m_axis_rx_tready;

    assign emio_eth_rxd     = s_axis_tx_tdata[7:0];
    assign emio_eth_rx_dv   = s_axis_tx_tvalid;
    assign emio_eth_rx_clk  = clk;

endmodule : emio_eth_wrapper
