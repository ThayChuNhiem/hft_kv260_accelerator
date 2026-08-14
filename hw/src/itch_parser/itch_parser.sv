// ============================================================================
// File Name   : itch_parser.sv
// Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
// Description : High-performance Hardware FSM for parsing NASDAQ ITCH 5.0 &
//               MoldUDP64 packets over 64-bit AXI Stream input.
//               Converts Big-Endian wire format to normalized Little-Endian
//               parsed_order_event_t output with sub-microsecond latency.
// Standard    : SystemVerilog IEEE 1800-2017
// ============================================================================

import hft_pkg::*;

module itch_parser #(
    parameter int AXIS_DATA_WIDTH = 64,
    parameter int AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8
)(
    input  logic                        clk,
    input  logic                        rst_n,

    // ------------------------------------------------------------------------
    // AXI-Stream Input (From UDP/IP Network Receiver)
    // ------------------------------------------------------------------------
    input  logic [AXIS_DATA_WIDTH-1:0] s_axis_tdata,
    input  logic [AXIS_KEEP_WIDTH-1:0] s_axis_tkeep,
    input  logic                        s_axis_tvalid,
    input  logic                        s_axis_tlast,
    output logic                        s_axis_tready,

    // ------------------------------------------------------------------------
    // Parsed Event Output (To Matching Engine / Strategy)
    // ------------------------------------------------------------------------
    output parsed_order_event_t         m_parsed_event,
    output logic                        m_parsed_event_valid,

    // ------------------------------------------------------------------------
    // Telemetry & Status Registers
    // ------------------------------------------------------------------------
    output logic [63:0]                 out_packet_count,
    output logic [63:0]                 out_parse_error_count,
    output moldudp64_hdr_t              out_last_mold_hdr
);

    // ------------------------------------------------------------------------
    // Helper Functions: Endianness Swap (Big-Endian Wire -> Little-Endian FPGA)
    // ------------------------------------------------------------------------
    function automatic logic [15:0] swap16(input logic [15:0] val);
        return {val[7:0], val[15:8]};
    endfunction

    function automatic logic [31:0] swap32(input logic [31:0] val);
        return {val[7:0], val[15:8], val[23:16], val[31:24]};
    endfunction

    function automatic logic [47:0] swap48(input logic [47:0] val);
        return {val[7:0], val[15:8], val[23:16], val[31:24], val[39:32], val[47:40]};
    endfunction

    function automatic logic [63:0] swap64(input logic [63:0] val);
        return {
            val[7:0],   val[15:8],  val[23:16], val[31:24],
            val[39:32], val[47:40], val[55:48], val[63:56]
        };
    endfunction

    // ------------------------------------------------------------------------
    // FSM States Definition
    // ------------------------------------------------------------------------
    typedef enum logic [3:0] {
        ST_IDLE,             // Waiting for UDP packet start
        ST_MOLD_HDR_0,       // MoldUDP64 Header Bytes 0..7 (Session 0..7)
        ST_MOLD_HDR_1,       // MoldUDP64 Header Bytes 8..15 (Session 8..9 + SeqNum 0..5)
        ST_MOLD_HDR_2,       // MoldUDP64 Header Bytes 16..19 (SeqNum 6..7 + MsgCount 0..1)
        ST_FETCH_MSG_LEN,    // Fetching ITCH 2-byte Length prefix
        ST_PARSE_MSG_BODY,   // Collecting bytes for current ITCH Message
        ST_DISCARD_REST      // Error or unhandled packet discard until tlast
    } state_e;

    state_e current_state;

    // ------------------------------------------------------------------------
    // Internal Registers & Shift Buffers
    // ------------------------------------------------------------------------
    logic [511:0] byte_buffer;        // 64-Byte sliding window buffer
    logic [7:0]   buffer_count;       // Number of valid bytes currently in buffer
    logic [15:0]  current_msg_len;    // Length of current ITCH message
    logic [15:0]  msg_bytes_received; // Bytes received for current message
    logic [15:0]  remaining_mold_msgs;// Remaining ITCH messages in MoldUDP64 packet

    moldudp64_hdr_t mold_hdr_reg;
    logic [63:0]    pkt_cnt_reg;
    logic [63:0]    err_cnt_reg;

    assign s_axis_tready          = 1'b1; // Always ready to receive network stream
    assign out_packet_count       = pkt_cnt_reg;
    assign out_parse_error_count  = err_cnt_reg;
    assign out_last_mold_hdr      = mold_hdr_reg;

    // ------------------------------------------------------------------------
    // FSM State Transition & Execution Logic
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state        <= ST_IDLE;
            m_parsed_event_valid <= 1'b0;
            m_parsed_event       <= '0;
            byte_buffer          <= '0;
            buffer_count         <= '0;
            current_msg_len      <= '0;
            msg_bytes_received   <= '0;
            remaining_mold_msgs  <= '0;
            pkt_cnt_reg          <= '0;
            err_cnt_reg          <= '0;
            mold_hdr_reg         <= '0;
        end else begin
            // Default pulse clear
            m_parsed_event_valid <= 1'b0;

            case (current_state)

                // ------------------------------------------------------------
                // ST_IDLE: Wait for start of new UDP Packet
                // ------------------------------------------------------------
                ST_IDLE: begin
                    buffer_count       <= '0;
                    msg_bytes_received <= '0;
                    if (s_axis_tvalid) begin
                        // Save first 8 bytes of MoldUDP64 header
                        mold_hdr_reg.session[79:16] <= s_axis_tdata;
                        current_state               <= ST_MOLD_HDR_1;
                    end
                end

                // ------------------------------------------------------------
                // ST_MOLD_HDR_1: Read session remainder + start of SeqNum
                // ------------------------------------------------------------
                ST_MOLD_HDR_1: begin
                    if (s_axis_tvalid) begin
                        if (s_axis_tlast) begin
                            // Premature packet truncation error
                            err_cnt_reg   <= err_cnt_reg + 1'b1;
                            current_state <= ST_IDLE;
                        end else begin
                            mold_hdr_reg.session[15:0]          <= s_axis_tdata[63:48];
                            mold_hdr_reg.sequence_number[63:16] <= s_axis_tdata[47:0];
                            current_state                       <= ST_MOLD_HDR_2;
                        end
                    end
                end

                // ------------------------------------------------------------
                // ST_MOLD_HDR_2: Read SeqNum remainder + Message Count
                // ------------------------------------------------------------
                ST_MOLD_HDR_2: begin
                    if (s_axis_tvalid) begin
                        if (s_axis_tlast) begin
                            // Premature packet truncation error
                            err_cnt_reg   <= err_cnt_reg + 1'b1;
                            current_state <= ST_IDLE;
                        end else begin
                            mold_hdr_reg.sequence_number[15:0] <= s_axis_tdata[63:48];
                            mold_hdr_reg.message_count         <= swap16(s_axis_tdata[47:32]);
                            remaining_mold_msgs                <= swap16(s_axis_tdata[47:32]);
                            pkt_cnt_reg                        <= pkt_cnt_reg + 1'b1;

                            // Next 2 bytes (s_axis_tdata[31:16]) contain first ITCH msg length
                            current_msg_len                    <= swap16(s_axis_tdata[31:16]);
                            
                            // Buffer remaining 2 bytes (s_axis_tdata[15:0])
                            byte_buffer[511:496]               <= s_axis_tdata[15:0];
                            buffer_count                       <= 8'd2;
                            msg_bytes_received                 <= 8'd2;

                            current_state                      <= ST_PARSE_MSG_BODY;
                        end
                    end
                end

                // ------------------------------------------------------------
                // ST_PARSE_MSG_BODY: Buffer bytes & parse ITCH message
                // ------------------------------------------------------------
                ST_PARSE_MSG_BODY: begin
                    if (s_axis_tvalid) begin
                        // Shift incoming 8 bytes into buffer
                        byte_buffer <= (byte_buffer >> 64) | ({s_axis_tdata, 448'b0});
                        buffer_count <= buffer_count + 8'd8;
                        msg_bytes_received <= msg_bytes_received + 8'd8;
                    end

                    // Check if full ITCH message payload is present in buffer
                    if (buffer_count >= current_msg_len) begin
                        // Extract Message Type (First byte of ITCH message)
                        case (byte_buffer[511:504])

                            // ------------------------------------------------
                            // Message Type 'A': Add Order (No MPID)
                            // ------------------------------------------------
                            MSG_ADD_ORDER: begin
                                itch_add_order_t raw_msg;
                                raw_msg = byte_buffer[511 : 512-(36*8)];

                                m_parsed_event_valid       <= 1'b1;
                                m_parsed_event.valid       <= 1'b1;
                                m_parsed_event.msg_type    <= MSG_ADD_ORDER;
                                m_parsed_event.stock_locate<= swap16(raw_msg.stock_locate);
                                m_parsed_event.timestamp   <= swap48(raw_msg.timestamp);
                                m_parsed_event.order_ref_num <= swap64(raw_msg.order_ref_num);
                                m_parsed_event.is_buy      <= (raw_msg.buy_sell == SIDE_BUY);
                                m_parsed_event.shares      <= swap32(raw_msg.shares);
                                m_parsed_event.stock_symbol<= raw_msg.stock; // 8 ASCII chars
                                m_parsed_event.price       <= swap32(raw_msg.price);
                                m_parsed_event.match_number<= '0;
                                m_parsed_event.new_order_ref_num <= '0;
                            end

                            // ------------------------------------------------
                            // Message Type 'E': Order Executed
                            // ------------------------------------------------
                            MSG_ORDER_EXECUTED: begin
                                itch_order_exec_t raw_msg;
                                raw_msg = byte_buffer[511 : 512-(31*8)];

                                m_parsed_event_valid       <= 1'b1;
                                m_parsed_event.valid       <= 1'b1;
                                m_parsed_event.msg_type    <= MSG_ORDER_EXECUTED;
                                m_parsed_event.stock_locate<= swap16(raw_msg.stock_locate);
                                m_parsed_event.timestamp   <= swap48(raw_msg.timestamp);
                                m_parsed_event.order_ref_num <= swap64(raw_msg.order_ref_num);
                                m_parsed_event.shares      <= swap32(raw_msg.executed_shares);
                                m_parsed_event.match_number<= swap64(raw_msg.match_number);
                                m_parsed_event.is_buy      <= 1'b0;
                                m_parsed_event.stock_symbol<= '0;
                                m_parsed_event.price       <= '0;
                                m_parsed_event.new_order_ref_num <= '0;
                            end

                            // ------------------------------------------------
                            // Message Type 'X': Order Cancel
                            // ------------------------------------------------
                            MSG_ORDER_CANCEL: begin
                                itch_order_cancel_t raw_msg;
                                raw_msg = byte_buffer[511 : 512-(23*8)];

                                m_parsed_event_valid       <= 1'b1;
                                m_parsed_event.valid       <= 1'b1;
                                m_parsed_event.msg_type    <= MSG_ORDER_CANCEL;
                                m_parsed_event.stock_locate<= swap16(raw_msg.stock_locate);
                                m_parsed_event.timestamp   <= swap48(raw_msg.timestamp);
                                m_parsed_event.order_ref_num <= swap64(raw_msg.order_ref_num);
                                m_parsed_event.shares      <= swap32(raw_msg.canceled_shares);
                                m_parsed_event.match_number<= '0;
                                m_parsed_event.is_buy      <= 1'b0;
                                m_parsed_event.stock_symbol<= '0;
                                m_parsed_event.price       <= '0;
                                m_parsed_event.new_order_ref_num <= '0;
                            end

                            // ------------------------------------------------
                            // Message Type 'D': Order Delete
                            // ------------------------------------------------
                            MSG_ORDER_DELETE: begin
                                itch_order_delete_t raw_msg;
                                raw_msg = byte_buffer[511 : 512-(19*8)];

                                m_parsed_event_valid       <= 1'b1;
                                m_parsed_event.valid       <= 1'b1;
                                m_parsed_event.msg_type    <= MSG_ORDER_DELETE;
                                m_parsed_event.stock_locate<= swap16(raw_msg.stock_locate);
                                m_parsed_event.timestamp   <= swap48(raw_msg.timestamp);
                                m_parsed_event.order_ref_num <= swap64(raw_msg.order_ref_num);
                                m_parsed_event.shares      <= '0;
                                m_parsed_event.match_number<= '0;
                                m_parsed_event.is_buy      <= 1'b0;
                                m_parsed_event.stock_symbol<= '0;
                                m_parsed_event.price       <= '0;
                                m_parsed_event.new_order_ref_num <= '0;
                            end

                            default: begin
                                // Unhandled message type or non-order message
                            end
                        endcase

                        // Deduct processed message bytes from buffer
                        buffer_count        <= buffer_count - current_msg_len;
                        remaining_mold_msgs <= remaining_mold_msgs - 1'b1;

                        if (remaining_mold_msgs <= 1) begin
                            current_state <= ST_IDLE;
                        end else begin
                            current_state <= ST_FETCH_MSG_LEN;
                        end
                    end

                    if (s_axis_tlast && s_axis_tvalid) begin
                        current_state <= ST_IDLE;
                    end
                end

                // ------------------------------------------------------------
                // ST_FETCH_MSG_LEN: Fetch 2-byte Length prefix for next Msg
                // ------------------------------------------------------------
                ST_FETCH_MSG_LEN: begin
                    if (buffer_count >= 2) begin
                        current_msg_len <= swap16(byte_buffer[511:496]);
                        buffer_count    <= buffer_count - 2;
                        current_state   <= ST_PARSE_MSG_BODY;
                    end else if (s_axis_tvalid) begin
                        byte_buffer  <= (byte_buffer >> 64) | ({s_axis_tdata, 448'b0});
                        buffer_count <= buffer_count + 8'd8;
                    end

                    if (s_axis_tlast && s_axis_tvalid) begin
                        current_state <= ST_IDLE;
                    end
                end

                // ------------------------------------------------------------
                // ST_DISCARD_REST: Skip to end of UDP packet on error
                // ------------------------------------------------------------
                ST_DISCARD_REST: begin
                    if (s_axis_tlast && s_axis_tvalid) begin
                        current_state <= ST_IDLE;
                    end
                end

                default: current_state <= ST_IDLE;
            endcase
        end
    end

endmodule : itch_parser
