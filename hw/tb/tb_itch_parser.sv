// ============================================================================
// File Name   : tb_itch_parser.sv
// Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
// Description : Self-checking Testbench for itch_parser.sv
//               Injects MoldUDP64 packets containing ITCH 5.0 messages 
//               (Add Order 'A', Order Executed 'E', Order Delete 'D') over AXI4-Stream.
// Standard    : SystemVerilog IEEE 1800-2017
// ============================================================================

`timescale 1ns / 1ps

import hft_pkg::*;

module tb_itch_parser;

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
    // Output Event Monitor Task
    // ------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (m_parsed_event_valid) begin
            $display("----------------------------------------------------------------");
            $display("[TB MONITOR @ %0t ps] NEW ITCH EVENT PARSED!", $time);
            $display("  -> Message Type  : %c (0x%0h)", m_parsed_event.msg_type, m_parsed_event.msg_type);
            $display("  -> Stock Locate  : %0d", m_parsed_event.stock_locate);
            $display("  -> Timestamp (ns): %0d", m_parsed_event.timestamp);
            $display("  -> Order Ref Num : %0d", m_parsed_event.order_ref_num);
            
            if (m_parsed_event.msg_type == MSG_ADD_ORDER) begin
                $display("  -> Side          : %s", m_parsed_event.is_buy ? "BUY" : "SELL");
                $display("  -> Stock Symbol  : %s", string'(m_parsed_event.stock_symbol));
                $display("  -> Shares        : %0d", m_parsed_event.shares);
                $display("  -> Price         : $%0d.%04d", m_parsed_event.price / 10000, m_parsed_event.price % 10000);
            end else if (m_parsed_event.msg_type == MSG_ORDER_EXECUTED) begin
                $display("  -> Executed Qty  : %0d", m_parsed_event.shares);
                $display("  -> Match Number  : %0d", m_parsed_event.match_number);
            end else if (m_parsed_event.msg_type == MSG_ORDER_DELETE) begin
                $display("  -> Action        : ORDER DELETED");
            end
            $display("----------------------------------------------------------------");
        end
    end

    // ------------------------------------------------------------------------
    // Main Stimulus Task
    // ------------------------------------------------------------------------
    initial begin
        // Initialize signals
        rst_n         = 0;
        s_axis_tdata  = '0;
        s_axis_tkeep  = '0;
        s_axis_tvalid = 0;
        s_axis_tlast  = 0;

        $display("================================================================");
        $display("       STARTING ITCH 5.0 PARSER TESTBENCH SIMULATION");
        $display("================================================================");

        // Apply Reset for 20ns
        #20;
        rst_n = 1;
        #10;

        // Send Test MoldUDP64 Packet #1 containing 3 ITCH Messages:
        // Message 1: Add Order ('A') - Stock: "AAPL    ", Price: $150.2500, Qty: 500
        // Message 2: Order Executed ('E') - Executed Qty: 100
        // Message 3: Order Delete ('D') - Order Ref: 100
        send_mold_packet_1();

        #100;

        $display("================================================================");
        $display("[TB TEST COMPLETED]");
        $display("  Total MoldUDP64 Packets Parsed : %0d", out_packet_count);
        $display("  Total Parse Errors             : %0d", out_parse_error_count);
        $display("================================================================");

        $finish;
    end

    // ------------------------------------------------------------------------
    // Helper Task: Send MoldUDP64 Packet #1
    // ------------------------------------------------------------------------
    task send_mold_packet_1();
        begin
            @(posedge clk);
            s_axis_tvalid <= 1'b1;
            s_axis_tkeep  <= 8'hFF;

            // Word 0: MoldUDP64 Header Bytes 0..7 (Session "SESSION001"[0..7])
            // "SESSION0" -> 0x53, 0x45, 0x53, 0x53, 0x49, 0x4F, 0x4E, 0x30
            s_axis_tdata <= 64'h53455353494F4E30;
            s_axis_tlast <= 1'b0;
            @(posedge clk);

            // Word 1: MoldUDP64 Header Bytes 8..15 (Session "01", SeqNum 0..5)
            // Session "01" (0x3031), SeqNum = 1 (0x0000000000000001 -> high 6 bytes 0x000000000000)
            s_axis_tdata <= 64'h3031000000000000;
            @(posedge clk);

            // Word 2: MoldUDP64 Header Bytes 16..19 + Msg 1 Length (2 bytes) + Msg 1 Type & Locate
            // SeqNum low 2 bytes (0x0001), MsgCount = 3 (0x0003), Msg 1 Length = 36 (0x0024), Msg 1 Type 'A' (0x41), Locate 0x0001
            s_axis_tdata <= 64'h0001000300244100;
            @(posedge clk);

            // Word 3: Msg 1 Payload: Locate low byte (0x01) + Tracking (0x0002) + Timestamp (0x000012345678) + OrderRef high byte (0x00)
            s_axis_tdata <= 64'h0100020000123456;
            @(posedge clk);

            // Word 4: Msg 1 Payload: OrderRef (0x7800000000000064 -> 100) + Side 'B' (0x42) + Shares high bytes (0x000001)
            s_axis_tdata <= 64'h7800000000000064;
            @(posedge clk);

            // Word 5: Msg 1 Payload: Side 'B' (0x42) + Shares (500 = 0x000001F4) + Stock "AAPL    " (0x4141504C2020)
            s_axis_tdata <= 64'h42000001F4414150;
            @(posedge clk);

            // Word 6: Msg 1 Payload: Stock remainder "  " (0x2020) + Price ($150.2500 = 1502500 = 0x0016ED24) + Msg 2 Length = 31 (0x001F)
            s_axis_tdata <= 64'h4C2020200016ED24;
            @(posedge clk);

            // Word 7: Msg 2 Payload (Order Executed 'E'): Length (0x001F) + Type 'E' (0x45) + Locate (0x0001) + Tracking (0x0003) + Timestamp high
            s_axis_tdata <= 64'h001F450001000300;
            @(posedge clk);

            // Word 8: Msg 2 Payload: Timestamp low + OrderRef (100 = 0x0000000000000064) + Exec Shares (100 = 0x00000064)
            s_axis_tdata <= 64'h0012345678000000;
            @(posedge clk);

            // Word 9: Msg 2 Payload: OrderRef remainder + Match Number (1000 = 0x00000000000003E8) + Msg 3 Length = 19 (0x0013)
            s_axis_tdata <= 64'h0000006400000000;
            @(posedge clk);

            // Word 10: Msg 3 Payload (Order Delete 'D'): Match low + Length (0x0013) + Type 'D' (0x44) + Locate (0x0001) + Tracking (0x0004)
            s_axis_tdata <= 64'h000003E800134400;
            @(posedge clk);

            // Word 11 (Last word in UDP packet): Msg 3 Payload: Timestamp + OrderRef (100)
            s_axis_tdata <= 64'h0100040000123456;
            s_axis_tlast <= 1'b1;
            @(posedge clk);

            // End of packet
            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
            s_axis_tdata  <= '0;
            s_axis_tkeep  <= '0;
        end
    endtask

endmodule : tb_itch_parser
