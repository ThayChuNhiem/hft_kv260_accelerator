// ============================================================================
// File Name   : tb_dma_telemetry.sv
// Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
// Description : Testbench for AXI DMA Telemetry Logging Interface module.
// Standard    : SystemVerilog IEEE 1800-2017
// ============================================================================

`timescale 1ns / 1ps

import hft_pkg::*;

module tb_dma_telemetry;

    // Clock & Reset
    logic clk;
    logic rst_n;

    // Inputs
    logic               in_log_valid;
    hft_telemetry_log_t in_log_data;

    // AXI4-Stream Outputs
    logic [63:0] m_axis_dma_tdata;
    logic [7:0]  m_axis_dma_tkeep;
    logic        m_axis_dma_tvalid;
    logic        m_axis_dma_tlast;
    logic        m_axis_dma_tready;

    // Status Outputs
    logic [63:0] out_total_logs_sent;
    logic        out_fifo_full;
    logic        out_fifo_empty;

    // Clock Gen (200 MHz -> 5ns period)
    initial begin
        clk = 0;
        forever #2.5 clk = ~clk;
    end

    // Instantiate DUT
    axi_dma_telemetry_intf #(
        .AXIS_DATA_WIDTH(64)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .in_log_valid       (in_log_valid),
        .in_log_data        (in_log_data),
        .m_axis_dma_tdata   (m_axis_dma_tdata),
        .m_axis_dma_tkeep   (m_axis_dma_tkeep),
        .m_axis_dma_tvalid  (m_axis_dma_tvalid),
        .m_axis_dma_tlast   (m_axis_dma_tlast),
        .m_axis_dma_tready  (m_axis_dma_tready),
        .out_total_logs_sent(out_total_logs_sent),
        .out_fifo_full      (out_fifo_full),
        .out_fifo_empty     (out_fifo_empty)
    );

    // Stream Monitor
    always_ff @(posedge clk) begin
        if (m_axis_dma_tvalid && m_axis_dma_tready) begin
            $display("[AXI DMA TELEMETRY STREAM @ %0t ps] tdata: 0x%16h (tkeep: 0x%0h, tlast: %0b)",
                     $time, m_axis_dma_tdata, m_axis_dma_tkeep, m_axis_dma_tlast);
        end
    end

    // Test Process
    initial begin
        rst_n             = 0;
        in_log_valid      = 0;
        in_log_data       = '0;
        m_axis_dma_tready = 1'b1;

        $display("================================================================");
        $display("     STARTING AXI DMA TELEMETRY INTERFACE TESTBENCH");
        $display("================================================================");

        #20;
        rst_n = 1;
        #10;

        // Drive Telemetry Log Record
        @(posedge clk);
        in_log_valid                   <= 1'b1;
        in_log_data.hw_timestamp_cycles <= 64'h0000000000A1B2C3;
        in_log_data.itch_timestamp      <= 48'h112233445566;
        in_log_data.order_ref_num      <= 64'h9988776655443322;
        in_log_data.price              <= 32'd1505000;
        in_log_data.shares             <= 32'd500;
        in_log_data.stock_locate       <= 16'd1;
        in_log_data.action_code        <= 8'h01; // Order Executed Log

        @(posedge clk);
        in_log_valid                   <= 1'b0;

        #100;

        $display("================================================================");
        $display("[DMA TELEMETRY TEST COMPLETE] Total Logs Sent: %0d", out_total_logs_sent);
        $display("================================================================");

        $finish;
    end

endmodule : tb_dma_telemetry
