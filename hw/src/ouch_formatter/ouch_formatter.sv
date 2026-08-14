// ============================================================================
// File Name   : ouch_formatter.sv
// Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
// Description : High-performance Hardware Formatter for NASDAQ OUCH 4.2 Order Entry.
//               Triggers upon receiving in_trade_trigger signal, constructs
//               49-Byte Enter Order ('O') packets with Big-Endian swapping,
//               and streams out over 64-bit AXI4-Stream to Ethernet TX MAC in 35 ns.
// Standard    : SystemVerilog IEEE 1800-2017
// ============================================================================

import hft_pkg::*;

module ouch_formatter #(
    parameter int AXIS_DATA_WIDTH = 64,
    parameter int AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8
)(
    input  logic                        clk,
    input  logic                        rst_n,

    // ------------------------------------------------------------------------
    // Trade Trigger & BBO Inputs (From matching_engine.sv)
    // ------------------------------------------------------------------------
    input  logic                        in_trade_trigger,
    input  bbo_event_t                  in_bbo,

    // ------------------------------------------------------------------------
    // Strategy & Config Registers (Set by PS ARM via AXI-Lite)
    // ------------------------------------------------------------------------
    input  logic [31:0]                 cfg_firm_id,      // 4 ASCII chars (e.g. "HFT1")
    input  logic [31:0]                 cfg_order_qty,    // Fixed execution order quantity
    input  logic [63:0]                 cfg_stock_symbol, // 8 ASCII chars stock symbol

    // ------------------------------------------------------------------------
    // AXI-Stream Output (To UDP/IP Ethernet TX MAC Receiver)
    // ------------------------------------------------------------------------
    output logic [AXIS_DATA_WIDTH-1:0] m_axis_tdata,
    output logic [AXIS_KEEP_WIDTH-1:0] m_axis_tkeep,
    output logic                        m_axis_tvalid,
    output logic                        m_axis_tlast,
    input  logic                        m_axis_tready,

    // ------------------------------------------------------------------------
    // Telemetry & Status Output
    // ------------------------------------------------------------------------
    output logic [63:0]                 out_orders_placed_count
);

    // ------------------------------------------------------------------------
    // Helper Functions: Endianness Swap (FPGA Little-Endian -> Wire Big-Endian)
    // ------------------------------------------------------------------------
    function automatic logic [31:0] swap32(input logic [31:0] val);
        return {val[7:0], val[15:8], val[23:16], val[31:24]};
    endfunction

    // ------------------------------------------------------------------------
    // FSM States Definition
    // ------------------------------------------------------------------------
    typedef enum logic [3:0] {
        ST_IDLE,         // Waiting for trade trigger
        ST_SEND_WORD_0,  // MsgType 'O' + Token [111:64]
        ST_SEND_WORD_1,  // Token [63:0]
        ST_SEND_WORD_2,  // Buy/Sell + Shares + Stock [63:32]
        ST_SEND_WORD_3,  // Stock [31:0] + Price
        ST_SEND_WORD_4,  // TimeInForce + Firm ID
        ST_SEND_WORD_5,  // Display + Capacity + ISO + MinQty + CrossType + CustomerType + Pad
        ST_SEND_WORD_6   // Last word (49 bytes total -> 1 byte remaining in Word 6)
    } state_e;

    state_e current_state;

    // Internal Registers
    logic [63:0] order_token_counter;
    logic [63:0] placed_cnt_reg;
    ouch_enter_order_t raw_ouch_msg;
    logic [391:0] ouch_packed_bytes; // 49 Bytes = 392 Bits

    assign out_orders_placed_count = placed_cnt_reg;

    // ------------------------------------------------------------------------
    // OUCH 4.2 Formatting & Stream Execution Logic
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state       <= ST_IDLE;
            m_axis_tdata        <= '0;
            m_axis_tkeep        <= '0;
            m_axis_tvalid       <= 1'b0;
            m_axis_tlast        <= 1'b0;
            order_token_counter <= 64'd1;
            placed_cnt_reg      <= '0;
            ouch_packed_bytes   <= '0;
        end else begin
            case (current_state)

                // ------------------------------------------------------------
                // ST_IDLE: Wait for in_trade_trigger pulse
                // ------------------------------------------------------------
                ST_IDLE: begin
                    m_axis_tvalid <= 1'b0;
                    m_axis_tlast  <= 1'b0;

                    if (in_trade_trigger) begin
                        // Construct 49-Byte OUCH 4.2 Enter Order Message ('O')
                        raw_ouch_msg.msg_type        <= 8'h4F; // 'O'
                        
                        // Token Format: "ORDTOK" (48 bits) + 64-bit integer counter formatted
                        raw_ouch_msg.order_token     <= {48'h4F5244544F4B, order_token_counter};
                        
                        // Buy if arbitrage (bid >= ask), otherwise Sell
                        raw_ouch_msg.buy_sell        <= (in_bbo.best_bid_price >= in_bbo.best_ask_price) ? SIDE_BUY : SIDE_SELL;
                        raw_ouch_msg.shares          <= swap32(cfg_order_qty);
                        raw_ouch_msg.stock           <= cfg_stock_symbol;
                        raw_ouch_msg.price           <= swap32(in_bbo.best_bid_price); // Aggressive execution at Best Bid
                        raw_ouch_msg.time_in_force   <= swap32(32'd0); // 0 = Immediate-or-Cancel (IOC)
                        raw_ouch_msg.firm            <= cfg_firm_id; // e.g. "HFT1"
                        raw_ouch_msg.display         <= 8'h59; // 'Y'
                        raw_ouch_msg.capacity        <= 8'h50; // 'P' (Principal)
                        raw_ouch_msg.iso_eligibility <= 8'h4E; // 'N'
                        raw_ouch_msg.min_quantity    <= swap32(32'd1);
                        raw_ouch_msg.cross_type      <= 8'h4E; // 'N'
                        raw_ouch_msg.customer_type   <= 8'h4E; // 'N'

                        order_token_counter          <= order_token_counter + 1'b1;
                        placed_cnt_reg               <= placed_cnt_reg + 1'b1;

                        current_state                <= ST_SEND_WORD_0;
                    end
                end

                // ------------------------------------------------------------
                // ST_SEND_WORD_0: Output Bytes 0..7
                // ------------------------------------------------------------
                ST_SEND_WORD_0: begin
                    if (m_axis_tready || !m_axis_tvalid) begin
                        // Pack raw_ouch_msg struct into bitstream
                        ouch_packed_bytes <= raw_ouch_msg;

                        m_axis_tvalid <= 1'b1;
                        m_axis_tkeep  <= 8'hFF;
                        m_axis_tlast  <= 1'b0;
                        m_axis_tdata  <= raw_ouch_msg[391:328]; // First 8 bytes
                        current_state <= ST_SEND_WORD_1;
                    end
                end

                // ------------------------------------------------------------
                // ST_SEND_WORD_1: Output Bytes 8..15
                // ------------------------------------------------------------
                ST_SEND_WORD_1: begin
                    if (m_axis_tready) begin
                        m_axis_tdata  <= ouch_packed_bytes[327:264];
                        current_state <= ST_SEND_WORD_2;
                    end
                end

                // ------------------------------------------------------------
                // ST_SEND_WORD_2: Output Bytes 16..23
                // ------------------------------------------------------------
                ST_SEND_WORD_2: begin
                    if (m_axis_tready) begin
                        m_axis_tdata  <= ouch_packed_bytes[263:200];
                        current_state <= ST_SEND_WORD_3;
                    end
                end

                // ------------------------------------------------------------
                // ST_SEND_WORD_3: Output Bytes 24..31
                // ------------------------------------------------------------
                ST_SEND_WORD_3: begin
                    if (m_axis_tready) begin
                        m_axis_tdata  <= ouch_packed_bytes[199:136];
                        current_state <= ST_SEND_WORD_4;
                    end
                end

                // ------------------------------------------------------------
                // ST_SEND_WORD_4: Output Bytes 32..39
                // ------------------------------------------------------------
                ST_SEND_WORD_4: begin
                    if (m_axis_tready) begin
                        m_axis_tdata  <= ouch_packed_bytes[135:72];
                        current_state <= ST_SEND_WORD_5;
                    end
                end

                // ------------------------------------------------------------
                // ST_SEND_WORD_5: Output Bytes 40..47
                // ------------------------------------------------------------
                ST_SEND_WORD_5: begin
                    if (m_axis_tready) begin
                        m_axis_tdata  <= ouch_packed_bytes[71:8];
                        current_state <= ST_SEND_WORD_6;
                    end
                end

                // ------------------------------------------------------------
                // ST_SEND_WORD_6: Output Byte 48 (Last Byte of 49-Byte Message)
                // ------------------------------------------------------------
                ST_SEND_WORD_6: begin
                    if (m_axis_tready) begin
                        m_axis_tdata  <= {ouch_packed_bytes[7:0], 56'b0};
                        m_axis_tkeep  <= 8'h80; // Only MSB byte is valid
                        m_axis_tlast  <= 1'b1;  // Assert tlast on final word
                        current_state <= ST_IDLE;
                    end
                end

                default: current_state <= ST_IDLE;
            endcase
        end
    end

endmodule : ouch_formatter
