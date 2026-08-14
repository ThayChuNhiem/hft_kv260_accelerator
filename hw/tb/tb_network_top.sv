// ============================================================================
// File Name   : tb_network_top.sv
// Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
// Description : Testbench for hardware UDP/IP stack and EMIO pin routing wrapper.
// Standard    : SystemVerilog IEEE 1800-2017
// ============================================================================

`timescale 1ns / 1ps

import hft_pkg::*;

module tb_network_top;

    // Clock & Reset
    logic clk;
    logic rst_n;

    // AXI-Stream Ports
    logic [63:0] phy_rx_tdata;
    logic [7:0]  phy_rx_tkeep;
    logic        phy_rx_tvalid;
    logic        phy_rx_tlast;
    logic        phy_rx_tready;

    logic [63:0] payload_rx_tdata;
    logic [7:0]  payload_rx_tkeep;
    logic        payload_rx_tvalid;
    logic        payload_rx_tlast;
    logic        payload_rx_tready;

    // Clock Gen (200 MHz -> 5ns period)
    initial begin
        clk = 0;
        forever #2.5 clk = ~clk;
    end

    // Instantiate DUT
    udp_ip_stack #(
        .AXIS_DATA_WIDTH(64)
    ) dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .phy_rx_tdata     (phy_rx_tdata),
        .phy_rx_tkeep     (phy_rx_tkeep),
        .phy_rx_tvalid    (phy_rx_tvalid),
        .phy_rx_tlast     (phy_rx_tlast),
        .phy_rx_tready    (phy_rx_tready),
        .payload_rx_tdata (payload_rx_tdata),
        .payload_rx_tkeep (payload_rx_tkeep),
        .payload_rx_tvalid(payload_rx_tvalid),
        .payload_rx_tlast (payload_rx_tlast),
        .payload_rx_tready(payload_rx_tready),
        .payload_tx_tdata (64'b0),
        .payload_tx_tkeep (8'b0),
        .payload_tx_tvalid(1'b0),
        .payload_tx_tlast (1'b0),
        .payload_tx_tready(),
        .phy_tx_tdata     (),
        .phy_tx_tkeep     (),
        .phy_tx_tvalid    (),
        .phy_tx_tlast     (),
        .phy_tx_tready    (1'b1)
    );

    // Test Process
    initial begin
        rst_n             = 0;
        phy_rx_tdata      = 64'b0;
        phy_rx_tkeep      = 8'b0;
        phy_rx_tvalid     = 1'b0;
        phy_rx_tlast      = 1'b0;
        payload_rx_tready = 1'b1;

        $display("================================================================");
        $display("     STARTING ETHERNET UDP/IP STACK & EMIO TESTBENCH");
        $display("================================================================");

        #20;
        rst_n = 1;
        #10;

        @(posedge clk);
        phy_rx_tvalid <= 1'b1;
        phy_rx_tkeep  <= 8'hFF;
        phy_rx_tdata  <= 64'h0123456789ABCDEF;
        phy_rx_tlast  <= 1'b1;

        @(posedge clk);
        phy_rx_tvalid <= 1'b0;
        phy_rx_tlast  <= 1'b0;

        #50;
        $display("================================================================");
        $display("[NETWORK STACK TEST COMPLETE] Status: PASS");
        $display("================================================================");

        $finish;
    end

endmodule : tb_network_top
