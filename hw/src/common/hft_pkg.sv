// ============================================================================
// File Name   : hft_pkg.sv
// Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
// Description : SystemVerilog package containing NASDAQ ITCH 5.0 protocol
//               struct definitions (packed big-endian format), enums, and 
//               normalized internal data structures for Order Book & Matching.
// Standard    : SystemVerilog IEEE 1800-2017
// ============================================================================

package hft_pkg;

    // ------------------------------------------------------------------------
    // CONSTANTS & ENUMS
    // ------------------------------------------------------------------------
    localparam int MAC_ADDR_WIDTH   = 48;
    localparam int IP_ADDR_WIDTH    = 32;
    localparam int PORT_WIDTH       = 16;
    localparam int TIMESTAMP_WIDTH  = 48; // ITCH 48-bit nanoseconds timestamp
    localparam int STOCK_SYM_WIDTH  = 64; // 8 ASCII characters
    localparam int MPID_WIDTH       = 32; // 4 ASCII characters

    // ITCH 5.0 Message Type Codes (ASCII)
    typedef enum logic [7:0] {
        MSG_SYSTEM_EVENT    = 8'h53, // 'S' - System Event
        MSG_STOCK_DIRECTORY = 8'h52, // 'R' - Stock Directory
        MSG_STOCK_TRADING   = 8'h48, // 'H' - Stock Trading Action
        MSG_ADD_ORDER       = 8'h41, // 'A' - Add Order (No MPID)
        MSG_ADD_ORDER_MPID  = 8'h46, // 'F' - Add Order (With MPID)
        MSG_ORDER_EXECUTED  = 8'h45, // 'E' - Order Executed
        MSG_ORDER_EXEC_PRICE= 8'h43, // 'C' - Order Executed With Price
        MSG_ORDER_CANCEL    = 8'h58, // 'X' - Order Cancel
        MSG_ORDER_DELETE    = 8'h44, // 'D' - Order Delete
        MSG_ORDER_REPLACE   = 8'h55, // 'U' - Order Replace
        MSG_TRADE_NON_CROSS = 8'h50, // 'P' - Trade (Non-Cross)
        MSG_CROSS_TRADE     = 8'h51, // 'Q' - Cross Trade
        MSG_NOII            = 8'h49  // 'I' - Net Order Imbalance Indicator
    } itch_msg_type_e;

    // Buy / Sell Side Indicators (ASCII)
    typedef enum logic [7:0] {
        SIDE_BUY  = 8'h42, // 'B'
        SIDE_SELL = 8'h53  // 'S'
    } side_e;

    // System Event Codes (ASCII)
    typedef enum logic [7:0] {
        EVENT_START_MESSAGES = 8'h4F, // 'O' - Start of Messages
        EVENT_START_SYSTEM   = 8'h53, // 'S' - Start of System Hours
        EVENT_START_MARKET   = 8'h51, // 'Q' - Start of Market Hours
        EVENT_END_MARKET     = 8'h4D, // 'M' - End of Market Hours
        EVENT_END_SYSTEM     = 8'h45, // 'E' - End of System Hours
        EVENT_END_MESSAGES   = 8'h43  // 'C' - End of Messages
    } sys_event_code_e;

    // ------------------------------------------------------------------------
    // MOLDUDP64 TRANSPORT HEADER (20 Bytes)
    // ------------------------------------------------------------------------
    typedef struct packed {
        logic [79:0] session;         // 10 Bytes ASCII Session ID
        logic [63:0] sequence_number; // 8 Bytes Sequence Number
        logic [15:0] message_count;   // 2 Bytes Number of ITCH messages in packet
    } moldudp64_hdr_t;

    // ------------------------------------------------------------------------
    // ITCH 5.0 PROTOCOL PACKED STRUCTS (Raw Wire Big-Endian Format)
    // Note: In SystemVerilog packed structs, the first field declared is MSB.
    // ------------------------------------------------------------------------

    // Message Type 'S': System Event (12 Bytes total: 1 byte type + 11 payload)
    typedef struct packed {
        logic [7:0]  msg_type;        // 'S' (0x53)
        logic [15:0] stock_locate;    // Locate code
        logic [15:0] tracking_number; // Tracking number
        logic [47:0] timestamp;       // Nanoseconds since midnight
        logic [7:0]  event_code;      // 'O', 'S', 'Q', 'M', 'E', 'C'
    } itch_sys_event_t;

    // Message Type 'R': Stock Directory (39 Bytes)
    typedef struct packed {
        logic [7:0]  msg_type;        // 'R' (0x52)
        logic [15:0] stock_locate;
        logic [15:0] tracking_number;
        logic [47:0] timestamp;
        logic [63:0] stock;           // 8-character ASCII Stock Symbol
        logic [7:0]  market_category; 
        logic [7:0]  financial_status;
        logic [31:0] round_lot_size;
        logic [7:0]  round_lots_only;
        logic [7:0]  issue_class;
        logic [15:0] issue_subtype;
        logic [7:0]  authenticity;
    } itch_stock_dir_t;

    // Message Type 'A': Add Order - No MPID Attributed (36 Bytes)
    typedef struct packed {
        logic [7:0]  msg_type;        // 'A' (0x41)
        logic [15:0] stock_locate;
        logic [15:0] tracking_number;
        logic [47:0] timestamp;
        logic [63:0] order_ref_num;   // Order Reference Number
        logic [7:0]  buy_sell;        // 'B' or 'S'
        logic [31:0] shares;          // Quantity
        logic [63:0] stock;           // 8-character ASCII Stock Symbol
        logic [31:0] price;           // Fixed point: 4 decimal places
    } itch_add_order_t;

    // Message Type 'F': Add Order - With MPID Attributed (40 Bytes)
    typedef struct packed {
        logic [7:0]  msg_type;        // 'F' (0x46)
        logic [15:0] stock_locate;
        logic [15:0] tracking_number;
        logic [47:0] timestamp;
        logic [63:0] order_ref_num;
        logic [7:0]  buy_sell;
        logic [31:0] shares;
        logic [63:0] stock;
        logic [31:0] price;
        logic [31:0] attribution;     // 4-character ASCII MPID
    } itch_add_order_mpid_t;

    // Message Type 'E': Order Executed (31 Bytes)
    typedef struct packed {
        logic [7:0]  msg_type;        // 'E' (0x45)
        logic [15:0] stock_locate;
        logic [15:0] tracking_number;
        logic [47:0] timestamp;
        logic [63:0] order_ref_num;
        logic [31:0] executed_shares;
        logic [63:0] match_number;
    } itch_order_exec_t;

    // Message Type 'C': Order Executed With Price (36 Bytes)
    typedef struct packed {
        logic [7:0]  msg_type;        // 'C' (0x43)
        logic [15:0] stock_locate;
        logic [15:0] tracking_number;
        logic [47:0] timestamp;
        logic [63:0] order_ref_num;
        logic [31:0] executed_shares;
        logic [63:0] match_number;
        logic [7:0]  printable;       // 'Y' or 'N'
        logic [31:0] exec_price;
    } itch_order_exec_price_t;

    // Message Type 'X': Order Cancel (23 Bytes)
    typedef struct packed {
        logic [7:0]  msg_type;        // 'X' (0x58)
        logic [15:0] stock_locate;
        logic [15:0] tracking_number;
        logic [47:0] timestamp;
        logic [63:0] order_ref_num;
        logic [31:0] canceled_shares;
    } itch_order_cancel_t;

    // Message Type 'D': Order Delete (19 Bytes)
    typedef struct packed {
        logic [7:0]  msg_type;        // 'D' (0x44)
        logic [15:0] stock_locate;
        logic [15:0] tracking_number;
        logic [47:0] timestamp;
        logic [63:0] order_ref_num;
    } itch_order_delete_t;

    // Message Type 'U': Order Replace (35 Bytes)
    typedef struct packed {
        logic [7:0]  msg_type;        // 'U' (0x55)
        logic [15:0] stock_locate;
        logic [15:0] tracking_number;
        logic [47:0] timestamp;
        logic [63:0] orig_order_ref_num;
        logic [63:0] new_order_ref_num;
        logic [31:0] shares;
        logic [31:0] price;
    } itch_order_replace_t;

    // Message Type 'P': Trade Non-Cross (44 Bytes)
    typedef struct packed {
        logic [7:0]  msg_type;        // 'P' (0x50)
        logic [15:0] stock_locate;
        logic [15:0] tracking_number;
        logic [47:0] timestamp;
        logic [63:0] order_ref_num;
        logic [7:0]  buy_sell;
        logic [31:0] shares;
        logic [63:0] stock;
        logic [31:0] price;
        logic [63:0] match_number;
    } itch_trade_t;

    // ------------------------------------------------------------------------
    // INTERNAL PARSED EVENT STRUCT (Normalized for Matching Engine / Strategy)
    // Little-endian converted fields, single clock domain internal bus
    // ------------------------------------------------------------------------
    typedef struct packed {
        logic        valid;              // Pulse indicating valid parsed event
        logic [7:0]  msg_type;           // Message type
        logic [15:0] stock_locate;       // Symbol locate ID
        logic [47:0] timestamp;          // Nanoseconds timestamp
        logic [63:0] order_ref_num;      // Order Reference Number
        logic [63:0] new_order_ref_num;  // For Order Replace ('U')
        logic [63:0] stock_symbol;       // 8 ASCII chars stock symbol
        logic        is_buy;             // 1 = Buy ('B'), 0 = Sell ('S')
        logic [31:0] shares;             // Quantity / Shares
        logic [31:0] price;              // Price (fixed point 4 decimals)
        logic [63:0] match_number;       // Match Number (for Executed/Trade)
    } parsed_order_event_t;

    // ------------------------------------------------------------------------
    // TELEMETRY / LOG ENTRY STRUCT (Pushed to AXI DMA -> PS Memory)
    // ------------------------------------------------------------------------
    typedef struct packed {
        logic [63:0] hw_timestamp_cycles; // Internal 64-bit hardware clock cycle counter
        logic [47:0] itch_timestamp;      // Exchange timestamp
        logic [63:0] order_ref_num;      // Order Ref
        logic [31:0] price;              // Execution / Trigger Price
        logic [31:0] shares;             // Executed Shares
        logic [15:0] stock_locate;       // Stock locate ID
        logic [7:0]  action_code;        // Action taken (e.g. 0x01 = Order Placed, 0x02 = Cancelled)
        logic [7:0]  reserved;           // Padding / Status flags
    } hft_telemetry_log_t;

    // ------------------------------------------------------------------------
    // BEST BID AND OFFER (BBO) TOP-OF-BOOK STRUCT
    // ------------------------------------------------------------------------
    typedef struct packed {
        logic        valid;              // Pulse indicating BBO update
        logic [15:0] stock_locate;       // Stock locate ID
        logic [31:0] best_bid_price;     // Highest Buy Price
        logic [31:0] best_bid_shares;    // Volume at Best Buy Price
        logic [31:0] best_ask_price;     // Lowest Sell Price
        logic [31:0] best_ask_shares;    // Volume at Best Sell Price
        logic [31:0] spread;             // Ask Price - Bid Price
    } bbo_event_t;

endpackage : hft_pkg
