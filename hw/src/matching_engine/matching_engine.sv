// ============================================================================
// File Name   : matching_engine.sv
// Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
// Description : Ultra-low latency Hardware Limit Order Book (LOB) & Matching Engine.
//               Uses FPGA Block RAM (BRAM / URAM) for Level 3 (L3) order tracking.
//               Guarantees Best Bid & Offer (BBO) Top-of-Book updates in <= 2 clock cycles (10 ns).
// Standard    : SystemVerilog IEEE 1800-2017
// ============================================================================

import hft_pkg::*;

module matching_engine #(
    parameter int L3_RAM_DEPTH = 1024, // Number of L3 order entries in BRAM (1024 slots)
    parameter int RAM_ADDR_BITS = $clog2(L3_RAM_DEPTH)
)(
    input  logic                clk,
    input  logic                rst_n,

    // ------------------------------------------------------------------------
    // Parsed Event Input (From itch_parser.sv)
    // ------------------------------------------------------------------------
    input  parsed_order_event_t in_event,
    input  logic                in_event_valid,

    // ------------------------------------------------------------------------
    // Best Bid & Offer (BBO) Output (To Strategy / Order Entry)
    // ------------------------------------------------------------------------
    output bbo_event_t          out_bbo,
    output logic                out_bbo_valid,
    output logic                out_trade_trigger,

    // ------------------------------------------------------------------------
    // Telemetry & Status Registers
    // ------------------------------------------------------------------------
    output logic [63:0]         out_total_bbo_updates,
    output logic [63:0]         out_active_order_count
);

    // ------------------------------------------------------------------------
    // L3 ORDER ENTRY STRUCT (Stored in FPGA Block RAM - BRAM/URAM)
    // ------------------------------------------------------------------------
    typedef struct packed {
        logic        valid;         // 1 = Order Active in Book
        logic [15:0] stock_locate;  // Stock Locate ID
        logic        is_buy;        // 1 = Buy ('B'), 0 = Sell ('S')
        logic [31:0] price;         // Order Price
        logic [31:0] shares;        // Remaining Shares
    } l3_order_entry_t;

    // Dual-Port Block RAM Array (Inferred BRAM / URAM)
    l3_order_entry_t l3_ram [0:L3_RAM_DEPTH-1];

    // ------------------------------------------------------------------------
    // Top-of-Book (BBO) Registers
    // ------------------------------------------------------------------------
    logic [31:0] best_bid_price_reg;
    logic [31:0] best_bid_shares_reg;
    logic [31:0] best_ask_price_reg;
    logic [31:0] best_ask_shares_reg;

    logic [63:0] bbo_update_cnt;
    logic [63:0] active_orders_cnt;

    // Pipeline Registers for 2-Cycle Update
    logic        stage1_valid;
    parsed_order_event_t stage1_event;
    l3_order_entry_t     stage1_ram_read;
    logic [RAM_ADDR_BITS-1:0] stage1_ram_addr;

    assign out_total_bbo_updates  = bbo_update_cnt;
    assign out_active_order_count = active_orders_cnt;

    // ------------------------------------------------------------------------
    // STAGE 1 (Clock Cycle 1): BRAM Read & Fast Top-of-Book (BBO) Comparison
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stage1_valid    <= 1'b0;
            stage1_event    <= '0;
            stage1_ram_read <= '0;
            stage1_ram_addr <= '0;
        end else begin
            stage1_valid <= in_event_valid;
            if (in_event_valid) begin
                stage1_event    <= in_event;
                // Index L3 BRAM using low bits of Order Reference Number
                stage1_ram_addr <= in_event.order_ref_num[RAM_ADDR_BITS-1:0];
                stage1_ram_read <= l3_ram[in_event.order_ref_num[RAM_ADDR_BITS-1:0]];
            end
        end
    end

    // ------------------------------------------------------------------------
    // STAGE 2 (Clock Cycle 2): BRAM Write, BBO Update & Trade Trigger Output
    // ------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            best_bid_price_reg  <= 32'h00000000; // 0
            best_bid_shares_reg <= 32'h00000000;
            best_ask_price_reg  <= 32'hFFFFFFFF; // Max Infinity
            best_ask_shares_reg <= 32'h00000000;
            
            out_bbo             <= '0;
            out_bbo_valid       <= 1'b0;
            out_trade_trigger   <= 1'b0;
            bbo_update_cnt      <= '0;
            active_orders_cnt   <= '0;

            // Clear BRAM contents on reset
            for (int i = 0; i < L3_RAM_DEPTH; i++) begin
                l3_ram[i] <= '0;
            end
        end else begin
            // Default pulse clear
            out_bbo_valid     <= 1'b0;
            out_trade_trigger <= 1'b0;

            if (stage1_valid) begin
                case (stage1_event.msg_type)

                    // --------------------------------------------------------
                    // MSG 'A' or 'F': ADD ORDER (Fast BBO Evaluation in Cycle 2)
                    // --------------------------------------------------------
                    MSG_ADD_ORDER, MSG_ADD_ORDER_MPID: begin
                        // 1. Write new order to L3 BRAM
                        l3_ram[stage1_ram_addr].valid        <= 1'b1;
                        l3_ram[stage1_ram_addr].stock_locate <= stage1_event.stock_locate;
                        l3_ram[stage1_ram_addr].is_buy       <= stage1_event.is_buy;
                        l3_ram[stage1_ram_addr].price        <= stage1_event.price;
                        l3_ram[stage1_ram_addr].shares       <= stage1_event.shares;
                        active_orders_cnt                    <= active_orders_cnt + 1'b1;

                        // 2. Evaluate Best Bid (BUY Side)
                        if (stage1_event.is_buy) begin
                            if (stage1_event.price > best_bid_price_reg) begin
                                // New Highest Buy Price -> Update Best Bid Immediately!
                                best_bid_price_reg  <= stage1_event.price;
                                best_bid_shares_reg <= stage1_event.shares;
                                bbo_update_cnt      <= bbo_update_cnt + 1'b1;
                                out_bbo_valid       <= 1'b1;
                            end else if (stage1_event.price == best_bid_price_reg) begin
                                // Same Price Level -> Accumulate Shares
                                best_bid_shares_reg <= best_bid_shares_reg + stage1_event.shares;
                                bbo_update_cnt      <= bbo_update_cnt + 1'b1;
                                out_bbo_valid       <= 1'b1;
                            end
                        end
                        // 3. Evaluate Best Ask (SELL Side)
                        else begin
                            if (stage1_event.price < best_ask_price_reg) begin
                                // New Lowest Sell Price -> Update Best Ask Immediately!
                                best_ask_price_reg  <= stage1_event.price;
                                best_ask_shares_reg <= stage1_event.shares;
                                bbo_update_cnt      <= bbo_update_cnt + 1'b1;
                                out_bbo_valid       <= 1'b1;
                            end else if (stage1_event.price == best_ask_price_reg) begin
                                // Same Price Level -> Accumulate Shares
                                best_ask_shares_reg <= best_ask_shares_reg + stage1_event.shares;
                                bbo_update_cnt      <= bbo_update_cnt + 1'b1;
                                out_bbo_valid       <= 1'b1;
                            end
                        end
                    end

                    // --------------------------------------------------------
                    // MSG 'E' or 'C': ORDER EXECUTED (Deduct Shares)
                    // --------------------------------------------------------
                    MSG_ORDER_EXECUTED, MSG_ORDER_EXEC_PRICE: begin
                        if (stage1_ram_read.valid) begin
                            if (stage1_ram_read.shares <= stage1_event.shares) begin
                                l3_ram[stage1_ram_addr].valid <= 1'b0; // Fully Executed
                                if (active_orders_cnt > 0) active_orders_cnt <= active_orders_cnt - 1'b1;
                            end else begin
                                l3_ram[stage1_ram_addr].shares <= stage1_ram_read.shares - stage1_event.shares;
                            end

                            // Update BBO shares if top-of-book order executed
                            if (stage1_ram_read.is_buy && stage1_ram_read.price == best_bid_price_reg) begin
                                if (best_bid_shares_reg > stage1_event.shares)
                                    best_bid_shares_reg <= best_bid_shares_reg - stage1_event.shares;
                                else
                                    best_bid_shares_reg <= '0;
                                out_bbo_valid <= 1'b1;
                            end else if (!stage1_ram_read.is_buy && stage1_ram_read.price == best_ask_price_reg) begin
                                if (best_ask_shares_reg > stage1_event.shares)
                                    best_ask_shares_reg <= best_ask_shares_reg - stage1_event.shares;
                                else
                                    best_ask_shares_reg <= '0;
                                out_bbo_valid <= 1'b1;
                            end
                        end
                    end

                    // --------------------------------------------------------
                    // MSG 'D' or 'X': ORDER DELETE / CANCEL
                    // --------------------------------------------------------
                    MSG_ORDER_DELETE, MSG_ORDER_CANCEL: begin
                        if (stage1_ram_read.valid) begin
                            l3_ram[stage1_ram_addr].valid <= 1'b0;
                            if (active_orders_cnt > 0) active_orders_cnt <= active_orders_cnt - 1'b1;

                            // Update BBO if top-of-book order deleted
                            if (stage1_ram_read.is_buy && stage1_ram_read.price == best_bid_price_reg) begin
                                if (best_bid_shares_reg > stage1_ram_read.shares)
                                    best_bid_shares_reg <= best_bid_shares_reg - stage1_ram_read.shares;
                                else
                                    best_bid_shares_reg <= '0;
                                out_bbo_valid <= 1'b1;
                            end else if (!stage1_ram_read.is_buy && stage1_ram_read.price == best_ask_price_reg) begin
                                if (best_ask_shares_reg > stage1_ram_read.shares)
                                    best_ask_shares_reg <= best_ask_shares_reg - stage1_ram_read.shares;
                                else
                                    best_ask_shares_reg <= '0;
                                out_bbo_valid <= 1'b1;
                            end
                        end
                    end

                    default: ;
                endcase

                // Output BBO Event
                out_bbo.valid           <= out_bbo_valid;
                out_bbo.stock_locate    <= stage1_event.stock_locate;
                out_bbo.best_bid_price  <= best_bid_price_reg;
                out_bbo.best_bid_shares <= best_bid_shares_reg;
                out_bbo.best_ask_price  <= best_ask_price_reg;
                out_bbo.best_ask_shares <= best_ask_shares_reg;
                
                if (best_ask_price_reg > best_bid_price_reg)
                    out_bbo.spread <= best_ask_price_reg - best_bid_price_reg;
                else
                    out_bbo.spread <= '0;

                // Trade Signal Trigger: Detect Cross-Spread Opportunity (Bid >= Ask)
                if (best_bid_price_reg >= best_ask_price_reg && best_bid_price_reg > 0 && best_ask_price_reg < 32'hFFFFFFFF) begin
                    out_trade_trigger <= 1'b1;
                end
            end
        end
    end

endmodule : matching_engine
