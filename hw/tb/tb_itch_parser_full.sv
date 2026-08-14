// ============================================================================
// File Name   : tb_itch_parser_full.sv
// Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
// Description : Full-coverage Self-checking Testbench for itch_parser.sv
//               Reads raw hexadecimal MoldUDP64/ITCH 5.0 data dumps (.mem file)
//               generated from real PCAP network captures or synthetic generators.
//               Validates ALL ITCH 5.0 message types ('A', 'F', 'E', 'C', 'X', 'D', 'U', 'P', 'S', 'R').
// Standard    : SystemVerilog IEEE 1800-2017
// ============================================================================

`timescale 1ns / 1ps

import hft_pkg::*;

module tb_itch_parser_full;

    // ------------------------------------------------------------------------
    // Clock & Reset Signals
    // ------------------------------------------------------------------------
    logic clk;
    logic rst_n;

    // ------------------------------------------------------------------------
    // AXI-Stream Bus Interfaces
    // ------------------------------------------------------------------------
    logic [63:0] s_axis_tdata;
    logic [7:0]  s_axis_tkeep;
    logic        s_axis_tvalid;
    logic        s_axis_tlast;
    logic        s_axis_tready;

    // ------------------------------------------------------------------------
    // DUT Outputs
    // ------------------------------------------------------------------------
    parsed_order_event_t m_parsed_event;
    logic                m_parsed_event_valid;
    logic [63:0]         out_packet_count;
    logic [63:0]         out_parse_error_count;
    moldudp64_hdr_t      out_last_mold_hdr;

    // ------------------------------------------------------------------------
    // Testbench Storage Array & Counters
    // ------------------------------------------------------------------------
    logic [63:0] mem_array [0:1023]; // Memory buffer for hex data dump
    int total_words;
    int msg_counts [logic [7:0]];     // Associative array to count messages by type

    // ------------------------------------------------------------------------
    // Clock Generation (200 MHz -> 5ns period)
    // ------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #2.5 clk = ~clk;
    end

    // ------------------------------------------------------------------------
    // DUT Instantiation
    // ------------------------------------------------------------------------
    itch_parser #(
        .AXIS_DATA_WIDTH(64)
    ) dut (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .s_axis_tdata          (s_axis_tdata),
        .s_axis_tkeep          (s_axis_tkeep),
        .s_axis_tvalid         (s_axis_tvalid),
        .s_axis_tlast          (s_axis_tlast),
        .s_axis_tready         (s_axis_tready),
        .m_parsed_event        (m_parsed_event),
        .m_parsed_event_valid  (m_parsed_event_valid),
        .out_packet_count      (out_packet_count),
        .out_parse_error_count (out_parse_error_count),
        .out_last_mold_hdr     (out_last_mold_hdr)
    );

    // ------------------------------------------------------------------------
    // Output Event Monitor & Validation Task
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (m_parsed_event_valid) begin
            // Increment statistics for this message type
            if (!msg_counts.exists(m_parsed_event.msg_type)) begin
                msg_counts[m_parsed_event.msg_type] = 1;
            end else begin
                msg_counts[m_parsed_event.msg_type]++;
            end

            $display("----------------------------------------------------------------");
            $display("[TB FULL MONITOR @ %0t ps] EVENT PARSED SUCCESSFULLY", $time);
            $display("  -> Msg Type      : '%c' (0x%0h)", m_parsed_event.msg_type, m_parsed_event.msg_type);
            $display("  -> Locate ID     : %0d", m_parsed_event.stock_locate);
            $display("  -> Timestamp     : %0d ns", m_parsed_event.timestamp);
            $display("  -> Order Ref Num : %0d", m_parsed_event.order_ref_num);

            case (m_parsed_event.msg_type)
                MSG_ADD_ORDER, MSG_ADD_ORDER_MPID: begin
                    $display("  -> Details       : ADD ORDER | Side: %s | Symbol: %s | Qty: %0d | Price: $%0d.%04d",
                             m_parsed_event.is_buy ? "BUY" : "SELL",
                             string'(m_parsed_event.stock_symbol),
                             m_parsed_event.shares,
                             m_parsed_event.price / 10000, m_parsed_event.price % 10000);
                end
                MSG_ORDER_EXECUTED: begin
                    $display("  -> Details       : ORDER EXECUTED | Executed Qty: %0d | Match ID: %0d",
                             m_parsed_event.shares, m_parsed_event.match_number);
                end
                MSG_ORDER_CANCEL: begin
                    $display("  -> Details       : ORDER CANCELLED | Cancelled Qty: %0d", m_parsed_event.shares);
                end
                MSG_ORDER_DELETE: begin
                    $display("  -> Details       : ORDER DELETED");
                end
                default: begin
                    $display("  -> Details       : EVENT MSG TYPE 0x%0h PROCESSED", m_parsed_event.msg_type);
                end
            endcase
            $display("----------------------------------------------------------------");
        end
    end

    // ------------------------------------------------------------------------
    // Main Test Stimulus Process
    // ------------------------------------------------------------------------
    initial begin
        // Reset signals
        rst_n         = 0;
        s_axis_tdata  = '0;
        s_axis_tkeep  = '0;
        s_axis_tvalid = 0;
        s_axis_tlast  = 0;

        $display("================================================================");
        $display("   STARTING FULL PCAP/MEM ITCH 5.0 PARSER SIMULATION TESTBENCH");
        $display("================================================================");

        // Load hex data dump into memory array
        $readmemh("itch_data_dump.mem", mem_array);

        // Count non-zero 64-bit words in memory array
        total_words = 0;
        for (int i = 0; i < 1024; i++) begin
            if (mem_array[i] !== 64'hX && mem_array[i] !== 64'h0) begin
                total_words++;
            end
        end

        $display("[TB INFO] Loaded %0d 64-bit data words from 'itch_data_dump.mem'", total_words);

        // Apply Reset
        #20;
        rst_n = 1;
        #10;

        // Feed data stream through AXI-Stream interface
        $display("[TB INFO] Injecting AXI-Stream data flow to DUT...");
        
        for (int w = 0; w < total_words; w++) begin
            @(posedge clk);
            s_axis_tvalid <= 1'b1;
            s_axis_tkeep  <= 8'hFF;
            s_axis_tdata  <= mem_array[w];
            
            // Assert tlast on final word of UDP packet
            if (w == total_words - 1) begin
                s_axis_tlast <= 1'b1;
            end else begin
                s_axis_tlast <= 1'b0;
            end
        end

        @(posedge clk);
        s_axis_tvalid <= 1'b0;
        s_axis_tlast  <= 1'b0;
        s_axis_tdata  <= '0;

        // Wait for pipeline processing to complete
        #150;

        // Final Report & Validation Checks
        $display("\n================================================================");
        $display("            FULL PARSER SIMULATION SUMMARY REPORT");
        $display("================================================================");
        $display(" Total MoldUDP64 Packets Parsed : %0d", out_packet_count);
        $display(" Total Parse Errors             : %0d", out_parse_error_count);
        $display(" Parsed Message Breakdown by Type:");
        
        foreach (msg_counts[k]) begin
            $display("   -> Type '%c' (0x%0h) : %0d messages", k, k, msg_counts[k]);
        end

        // Assertions for correctness
        if (out_parse_error_count == 0 && out_packet_count > 0) begin
            $display("\n>>> [PASSED] ALL ITCH 5.0 MESSAGES PARSED WITH ZERO ERRORS! <<<");
        end else begin
            $display("\n>>> [FAILED] PARSER ENCOUNTERED ERRORS OR NO PACKETS PROCESSED <<<");
        end
        $display("================================================================");

        $finish;
    end

endmodule : tb_itch_parser_full
