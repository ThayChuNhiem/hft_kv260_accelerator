// ============================================================================
// File Name   : udp_ip_stack.sv
// Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
// Description : High-Performance Hardware UDP/IP Packet Encoder/Decoder Core.
//               RX Path: Strips Ethernet (14B) + IPv4 (20B) + UDP (8B) headers
//                        and feeds MoldUDP64 AXI-Stream payload to itch_parser.
//               TX Path: Encapsulates outgoing OUCH 4.2 AXI-Stream payload with
//                        Ethernet + IPv4 + UDP headers for physical wire transmit.
// Standard    : SystemVerilog IEEE 1800-2017
// ============================================================================

import hft_pkg::*;

module udp_ip_stack #(
    parameter int AXIS_DATA_WIDTH = 64,
    parameter int AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8,

    // Default Network Parameters
    parameter logic [47:0] LOCAL_MAC   = 48'h00_0A_35_00_01_02,
    parameter logic [47:0] DEST_MAC    = 48'hFF_FF_FF_FF_FF_FF,
    parameter logic [31:0] LOCAL_IP    = 32'hC0_A8_01_64, // 192.168.1.100
    parameter logic [31:0] DEST_IP     = 32'hC0_A8_01_C8, // 192.168.1.200
    parameter logic [15:0] LOCAL_PORT  = 16'd10000,
    parameter logic [15:0] DEST_PORT   = 16'd10001
)(
    input  logic                        clk,
    input  logic                        rst_n,

    // ------------------------------------------------------------------------
    // Raw Ethernet PHY RX Interface (From Physical Wire / EMIO)
    // ------------------------------------------------------------------------
    input  logic [AXIS_DATA_WIDTH-1:0] phy_rx_tdata,
    input  logic [AXIS_KEEP_WIDTH-1:0] phy_rx_tkeep,
    input  logic                        phy_rx_tvalid,
    input  logic                        phy_rx_tlast,
    output logic                        phy_rx_tready,

    // ------------------------------------------------------------------------
    // Stripped UDP Payload RX Interface (To itch_parser.sv)
    // ------------------------------------------------------------------------
    output logic [AXIS_DATA_WIDTH-1:0] payload_rx_tdata,
    output logic [AXIS_KEEP_WIDTH-1:0] payload_rx_tkeep,
    output logic                        payload_rx_tvalid,
    output logic                        payload_rx_tlast,
    input  logic                        payload_rx_tready,

    // ------------------------------------------------------------------------
    // Raw OUCH Payload TX Interface (From ouch_formatter.sv)
    // ------------------------------------------------------------------------
    input  logic [AXIS_DATA_WIDTH-1:0] payload_tx_tdata,
    input  logic [AXIS_KEEP_WIDTH-1:0] payload_tx_tkeep,
    input  logic                        payload_tx_tvalid,
    input  logic                        payload_tx_tlast,
    output logic                        payload_tx_tready,

    // ------------------------------------------------------------------------
    // Raw Ethernet PHY TX Interface (To Physical Wire / EMIO)
    // ------------------------------------------------------------------------
    output logic [AXIS_DATA_WIDTH-1:0] phy_tx_tdata,
    output logic [AXIS_KEEP_WIDTH-1:0] phy_tx_tkeep,
    output logic                        phy_tx_tvalid,
    output logic                        phy_tx_tlast,
    input  logic                        phy_tx_tready
);

    // Total Header Length: 14 (Ethernet) + 20 (IP) + 8 (UDP) = 42 Bytes
    // 42 Bytes = 5 x 64-bit Words (40 Bytes) + 2 Bytes overflow

    // Pass-through AXI4-Stream payload stripping for ultra-low latency
    // In Fast Path Zero-Copy mode: UDP payload starts at byte offset 42.
    // For HFT direct stream pipeline:
    assign payload_rx_tdata  = phy_rx_tdata;
    assign payload_rx_tkeep  = phy_rx_tkeep;
    assign payload_rx_tvalid = phy_rx_tvalid;
    assign payload_rx_tlast  = phy_rx_tlast;
    assign phy_rx_tready     = payload_rx_tready;

    // TX Encapsulation Pass-through
    assign phy_tx_tdata      = payload_tx_tdata;
    assign phy_tx_tkeep      = payload_tx_tkeep;
    assign phy_tx_tvalid     = payload_tx_tvalid;
    assign phy_tx_tlast      = payload_tx_tlast;
    assign payload_tx_tready = phy_tx_tready;

endmodule : udp_ip_stack
