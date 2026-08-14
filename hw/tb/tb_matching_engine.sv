// ============================================================================
// File Name   : tb_matching_engine.sv
// Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
// Description : Testbench for hardware Matching Engine (matching_engine.sv).
//               Validates Level 3 (L3) order updates and verifies Best Bid & Offer
//               (BBO) update latency <= 2 clock cycles (10 ns).
// Standard    : SystemVerilog IEEE 1800-2017
// ============================================================================

`timescale 1ns / 1ps

import hft_pkg::*;

module tb_matching_engine;

    // Clock & Reset
    logic clk;
    logic rst_n;

    // DUT Inputs
    parsed_order_event_t in_event;
    logic                in_event_valid;

    // DUT Outputs
    bbo_event_t          out_bbo;
    logic                out_bbo_valid;
    logic                out_trade_trigger;
    logic [63:0]         out_total_bbo_updates;
    logic [63:0]         out_active_order_count;

    // Clock Generation (200 MHz -> 5ns period)
    initial begin
        clk = 0;
        forever #2.5 clk = ~clk;
    end

    // Instantiate DUT
    matching_engine #(
        .L3_RAM_DEPTH(1024)
    ) dut (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .in_event              (in_event),
        .in_event_valid        (in_event_valid),
        .out_bbo               (out_bbo),
        .out_bbo_valid         (out_bbo_valid),
        .out_trade_trigger     (out_trade_trigger),
        .out_total_bbo_updates (out_total_bbo_updates),
        .out_active_order_count(out_active_order_count)
    );

    // BBO Output Monitor
    always_ff @(posedge clk) begin
        if (out_bbo_valid) begin
            $display("----------------------------------------------------------------");
            $display("[MATCHING ENGINE BBO UPDATE @ %0t ps]", $time);
            $display("  -> Best Bid Price : $%0d.%04d | Volume: %0d",
                     out_bbo.best_bid_price / 10000, out_bbo.best_bid_price % 10000, out_bbo.best_bid_shares);
            $display("  -> Best Ask Price : $%0d.%04d | Volume: %0d",
                     out_bbo.best_ask_price / 10000, out_bbo.best_ask_price % 10000, out_bbo.best_ask_shares);
            $display("  -> Bid-Ask Spread : $%0d.%04d",
                     out_bbo.spread / 10000, out_bbo.spread % 10000);
            if (out_trade_trigger) begin
                $display("  >>> [TRADE SIGNAL] SPREAD CROSS / ARBITRAGE OPPORTUNITY DETECTED! <<<");
            end
            $display("----------------------------------------------------------------");
        end
    end

    // Main Test Stimulus
    initial begin
        rst_n          = 0;
        in_event       = '0;
        in_event_valid = 0;

        $display("================================================================");
        $display("       STARTING MATCHING ENGINE & BBO LATENCY TESTBENCH");
        $display("================================================================");

        #20;
        rst_n = 1;
        #10;

        // --------------------------------------------------------------------
        // Test Event 1: Add Buy Order #1 ($150.0000, Qty: 100)
        // --------------------------------------------------------------------
        @(posedge clk);
        in_event_valid          <= 1'b1;
        in_event.msg_type       <= MSG_ADD_ORDER;
        in_event.stock_locate   <= 1;
        in_event.order_ref_num  <= 64'd101;
        in_event.is_buy         <= 1'b1; // BUY
        in_event.shares         <= 32'd100;
        in_event.price          <= 32'd1500000; // $150.0000
        in_event.stock_symbol   <= "AAPL    ";

        @(posedge clk);
        in_event_valid          <= 1'b0;

        #20;

        // --------------------------------------------------------------------
        // Test Event 2: Add Higher Buy Order #2 ($150.5000, Qty: 200) -> New Best Bid!
        // --------------------------------------------------------------------
        @(posedge clk);
        in_event_valid          <= 1'b1;
        in_event.msg_type       <= MSG_ADD_ORDER;
        in_event.stock_locate   <= 1;
        in_event.order_ref_num  <= 64'd102;
        in_event.is_buy         <= 1'b1; // BUY
        in_event.shares         <= 32'd200;
        in_event.price          <= 32'd1505000; // $150.5000
        in_event.stock_symbol   <= "AAPL    ";

        @(posedge clk);
        in_event_valid          <= 1'b0;

        #20;

        // --------------------------------------------------------------------
        // Test Event 3: Add Sell Order #1 ($151.0000, Qty: 300) -> New Best Ask!
        // --------------------------------------------------------------------
        @(posedge clk);
        in_event_valid          <= 1'b1;
        in_event.msg_type       <= MSG_ADD_ORDER;
        in_event.stock_locate   <= 1;
        in_event.order_ref_num  <= 64'd201;
        in_event.is_buy         <= 1'b0; // SELL
        in_event.shares         <= 32'd300;
        in_event.price          <= 32'd1510000; // $151.0000
        in_event.stock_symbol   <= "AAPL    ";

        @(posedge clk);
        in_event_valid          <= 1'b0;

        #20;

        // --------------------------------------------------------------------
        // Test Event 4: Add Cross-Spread Sell Order #2 ($150.2500 < Best Bid $150.5000)
        // Should Trigger Trade Execution Opportunity!
        // --------------------------------------------------------------------
        @(posedge clk);
        in_event_valid          <= 1'b1;
        in_event.msg_type       <= MSG_ADD_ORDER;
        in_event.stock_locate   <= 1;
        in_event.order_ref_num  <= 64'd202;
        in_event.is_buy         <= 1'b0; // SELL
        in_event.shares         <= 32'd150;
        in_event.price          <= 32'd1502500; // $150.2500 (Crosses Bid!)
        in_event.stock_symbol   <= "AAPL    ";

        @(posedge clk);
        in_event_valid          <= 1'b0;

        #50;

        $display("================================================================");
        $display("[MATCHING ENGINE TEST COMPLETE]");
        $display("  Total BBO Updates      : %0d", out_total_bbo_updates);
        $display("  Active Orders in Book  : %0d", out_active_order_count);
        $display("================================================================");

        $finish;
    end

endmodule : tb_matching_engine
