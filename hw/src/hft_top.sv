// ============================================================================
// File Name   : hft_top.sv
// Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
// Description : Top-Level Integrated Hardware Pipeline Wrapper for HFT Fast Path.
//               Pipeline: Network In (AXI-Stream) -> ITCH Parser -> Matching Engine
//                         -> OUCH Formatter -> Network Out (AXI-Stream).
//               Achieves end-to-end sub-microsecond Tick-to-Trade execution latency.
// Standard    : SystemVerilog IEEE 1800-2017
// ============================================================================

import hft_pkg::*;

module hft_top #(
    parameter int AXIS_DATA_WIDTH = 64,
    parameter int AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8,
    parameter int L3_RAM_DEPTH    = 1024
)(
    input  logic                        clk,
    input  logic                        rst_n,

    // ------------------------------------------------------------------------
    // Network RX AXI4-Stream Input (From Ethernet MAC RX / UDP Parser)
    // ------------------------------------------------------------------------
    input  logic [AXIS_DATA_WIDTH-1:0] s_axis_rx_tdata,
    input  logic [AXIS_KEEP_WIDTH-1:0] s_axis_rx_tkeep,
    input  logic                        s_axis_rx_tvalid,
    input  logic                        s_axis_rx_tlast,
    output logic                        s_axis_rx_tready,

    // ------------------------------------------------------------------------
    // Network TX AXI4-Stream Output (To Ethernet MAC TX / OUCH Out)
    // ------------------------------------------------------------------------
    output logic [AXIS_DATA_WIDTH-1:0] m_axis_tx_tdata,
    output logic [AXIS_KEEP_WIDTH-1:0] m_axis_tx_tkeep,
    output logic                        m_axis_tx_tvalid,
    output logic                        m_axis_tx_tlast,
    input  logic                        m_axis_tx_tready,

    // ------------------------------------------------------------------------
    // Strategy & Config Registers (Set by ARM PS via AXI-Lite)
    // ------------------------------------------------------------------------
    input  logic [31:0]                 cfg_firm_id,      // e.g. "HFT1"
    input  logic [31:0]                 cfg_order_qty,    // Fixed execution order qty
    input  logic [63:0]                 cfg_stock_symbol, // e.g. "AAPL    "

    // ------------------------------------------------------------------------
    // System Status & Telemetry Registers (To AXI DMA / Control Plane)
    // ------------------------------------------------------------------------
    output bbo_event_t                  out_top_bbo,
    output logic [63:0]                 out_parsed_packet_count,
    output logic [63:0]                 out_bbo_update_count,
    output logic [63:0]                 out_orders_placed_count
);

    // Internal Interconnect Wires
    parsed_order_event_t parsed_event;
    logic                parsed_event_valid;
    
    bbo_event_t          bbo_event;
    logic                bbo_event_valid;
    logic                trade_trigger;

    assign out_top_bbo = bbo_event;

    // ------------------------------------------------------------------------
    // MODULE 1: NASDAQ ITCH 5.0 FSM PARSER
    // ------------------------------------------------------------------------
    itch_parser #(
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH)
    ) u_itch_parser (
        .clk                  (clk),
        .rst_n                (rst_n),
        .s_axis_tdata         (s_axis_rx_tdata),
        .s_axis_tkeep         (s_axis_rx_tkeep),
        .s_axis_tvalid        (s_axis_rx_tvalid),
        .s_axis_tlast         (s_axis_rx_tlast),
        .s_axis_tready        (s_axis_rx_tready),
        .m_parsed_event       (parsed_event),
        .m_parsed_event_valid (parsed_event_valid),
        .out_packet_count     (out_parsed_packet_count),
        .out_parse_error_count(),
        .out_last_mold_hdr    ()
    );

    // ------------------------------------------------------------------------
    // MODULE 2: LIMIT ORDER BOOK (LOB) & MATCHING ENGINE
    // ------------------------------------------------------------------------
    matching_engine #(
        .L3_RAM_DEPTH(L3_RAM_DEPTH)
    ) u_matching_engine (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .in_event              (parsed_event),
        .in_event_valid        (parsed_event_valid),
        .out_bbo               (bbo_event),
        .out_bbo_valid         (bbo_event_valid),
        .out_trade_trigger     (trade_trigger),
        .out_total_bbo_updates (out_bbo_update_count),
        .out_active_order_count()
    );

    // ------------------------------------------------------------------------
    // MODULE 3: NASDAQ OUCH 4.2 ORDER ENTRY FORMATTER
    // ------------------------------------------------------------------------
    ouch_formatter #(
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH)
    ) u_ouch_formatter (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .in_trade_trigger        (trade_trigger),
        .in_bbo                 (bbo_event),
        .cfg_firm_id            (cfg_firm_id),
        .cfg_order_qty          (cfg_order_qty),
        .cfg_stock_symbol       (cfg_stock_symbol),
        .m_axis_tdata           (m_axis_tx_tdata),
        .m_axis_tkeep           (m_axis_tx_tkeep),
        .m_axis_tvalid          (m_axis_tx_tvalid),
        .m_axis_tlast           (m_axis_tx_tlast),
        .m_axis_tready          (m_axis_tx_tready),
        .out_orders_placed_count(out_orders_placed_count)
    );

endmodule : hft_top
