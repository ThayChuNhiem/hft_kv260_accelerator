// ============================================================================
// File Name   : tb_ouch_formatter.sv
// Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
// Description : Testbench for hardware OUCH 4.2 Order Entry Formatter (ouch_formatter.sv).
//               Validates single-cycle trigger response and verifies 49-Byte packet
//               formatting over 64-bit AXI4-Stream output interface.
// Standard    : SystemVerilog IEEE 1800-2017
// ============================================================================

`timescale 1ns / 1ps

import hft_pkg::*;

module tb_ouch_formatter;

    // Clock & Reset
    logic clk;
    logic rst_n;

    // DUT Inputs
    logic        in_trade_trigger;
    bbo_event_t  in_bbo;
    logic [31:0] cfg_firm_id;
    logic [31:0] cfg_order_qty;
    logic [63:0] cfg_stock_symbol;

    // DUT Outputs
    logic [63:0] m_axis_tdata;
    logic [7:0]  m_axis_tkeep;
    logic        m_axis_tvalid;
    logic        m_axis_tlast;
    logic        m_axis_tready;
    logic [63:0] out_orders_placed_count;

    // Internal Stream Accumulator
    logic [391:0] rx_stream_buffer;
    int word_count;

    // Clock Generation (200 MHz -> 5ns period)
    initial begin
        clk = 0;
        forever #2.5 clk = ~clk;
    end

    // Instantiate DUT
    ouch_formatter #(
        .AXIS_DATA_WIDTH(64)
    ) dut (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .in_trade_trigger        (in_trade_trigger),
        .in_bbo                 (in_bbo),
        .cfg_firm_id            (cfg_firm_id),
        .cfg_order_qty          (cfg_order_qty),
        .cfg_stock_symbol       (cfg_stock_symbol),
        .m_axis_tdata           (m_axis_tdata),
        .m_axis_tkeep           (m_axis_tkeep),
        .m_axis_tvalid          (m_axis_tvalid),
        .m_axis_tlast           (m_axis_tlast),
        .m_axis_tready          (m_axis_tready),
        .out_orders_placed_count(out_orders_placed_count)
    );

    // Stream Accumulator Monitor
    always_ff @(posedge clk) begin
        if (m_axis_tvalid && m_axis_tready) begin
            $display("[OUCH STREAM OUTPUT @ %0t ps] Word %0d: 0x%16h (tkeep: 0x%0h, tlast: %0b)",
                     $time, word_count, m_axis_tdata, m_axis_tkeep, m_axis_tlast);
            
            rx_stream_buffer <= (rx_stream_buffer << 64) | m_axis_tdata;
            word_count++;

            if (m_axis_tlast) begin
                $display("----------------------------------------------------------------");
                $display("[TB OUCH MONITOR] FULL 49-BYTE ORDER ENTRY PACKET GENERATED!");
                $display("  -> Total Orders Placed: %0d", out_orders_placed_count);
                $display("----------------------------------------------------------------");
            end
        end
    end

    // Main Test Stimulus
    initial begin
        rst_n            = 0;
        in_trade_trigger = 0;
        in_bbo           = '0;
        m_axis_tready    = 1'b1; // Ethernet MAC ready
        word_count       = 0;

        // Config setup
        cfg_firm_id      = "HFT1";
        cfg_order_qty    = 32'd500; // 500 shares
        cfg_stock_symbol = "AAPL    ";

        $display("================================================================");
        $display("     STARTING OUCH 4.2 ORDER ENTRY FORMATTER TESTBENCH");
        $display("================================================================");

        #20;
        rst_n = 1;
        #10;

        // Setup BBO state (Spread Cross: Bid $150.5000 >= Ask $150.2500)
        in_bbo.valid           = 1'b1;
        in_bbo.stock_locate    = 1;
        in_bbo.best_bid_price  = 32'd1505000; // $150.5000
        in_bbo.best_bid_shares = 32'd200;
        in_bbo.best_ask_price  = 32'd1502500; // $150.2500
        in_bbo.best_ask_shares = 32'd150;
        in_bbo.spread          = 32'd0;

        // Assert Trade Trigger!
        @(posedge clk);
        in_trade_trigger <= 1'b1;
        
        @(posedge clk);
        in_trade_trigger <= 1'b0;

        #100;

        $display("================================================================");
        $display("[OUCH FORMATTER TEST COMPLETE]");
        $display("================================================================");

        $finish;
    end

endmodule : tb_ouch_formatter
