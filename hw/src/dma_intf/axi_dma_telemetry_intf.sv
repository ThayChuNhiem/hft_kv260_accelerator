// ============================================================================
// File Name   : axi_dma_telemetry_intf.sv
// Project     : Tick-to-Trade HFT Accelerator (AMD Xilinx Kria KV260)
// Description : Hardware Telemetry Logging Interface for Xilinx AXI DMA IP.
//               Encapsulates hft_telemetry_log_t records into 64-bit AXI4-Stream
//               packets for direct Memory-Mapped DMA streaming to PS DDR4 RAM.
// Standard    : SystemVerilog IEEE 1800-2017
// ============================================================================

import hft_pkg::*;

module axi_dma_telemetry_intf #(
    parameter int AXIS_DATA_WIDTH = 64,
    parameter int AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8,
    parameter int TELEMETRY_FIFO_DEPTH = 512
)(
    input  logic                        clk,
    input  logic                        rst_n,

    // ------------------------------------------------------------------------
    // Internal Hardware Event Pulse & Telemetry Input (From Fast Path PL)
    // ------------------------------------------------------------------------
    input  logic                        in_log_valid,
    input  hft_telemetry_log_t          in_log_data,

    // ------------------------------------------------------------------------
    // AXI4-Stream Master Interface (To Xilinx AXI DMA S2MM Stream Input)
    // ------------------------------------------------------------------------
    output logic [AXIS_DATA_WIDTH-1:0] m_axis_dma_tdata,
    output logic [AXIS_KEEP_WIDTH-1:0] m_axis_dma_tkeep,
    output logic                        m_axis_dma_tvalid,
    output logic                        m_axis_dma_tlast,
    input  logic                        m_axis_dma_tready,

    // Status Signals
    output logic [63:0]                 out_total_logs_sent,
    output logic                        out_fifo_full,
    output logic                        out_fifo_empty
);

    // ------------------------------------------------------------------------
    // Telemetry Record: hft_telemetry_log_t = 272 Bits (34 Bytes)
    // Structured into 5 x 64-bit Words for AXI DMA Transfer:
    //   Word 0: [63:0]   Hardware Cycle Timestamp
    //   Word 1: [127:64] Exchange Timestamp [47:0] + Reserved [15:0]
    //   Word 2: [191:128] Order Ref Num [63:0]
    //   Word 3: [255:192] Execution Price [31:0] + Executed Shares [31:0]
    //   Word 4: [319:256] Stock Locate [15:0] + Action Code [7:0] + Reserved [40:0]
    // ------------------------------------------------------------------------

    typedef enum logic [2:0] {
        ST_IDLE,
        ST_SEND_W0,
        ST_SEND_W1,
        ST_SEND_W2,
        ST_SEND_W3,
        ST_SEND_W4
    } state_e;

    state_e current_state;

    // Registers
    hft_telemetry_log_t log_reg;
    logic [63:0] logs_sent_cnt;

    assign out_total_logs_sent = logs_sent_cnt;
    assign out_fifo_full       = (current_state != ST_IDLE);
    assign out_fifo_empty      = (current_state == ST_IDLE);

    // FSM State Machine for Streaming Log Records to AXI DMA
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state     <= ST_IDLE;
            m_axis_dma_tdata  <= '0;
            m_axis_dma_tkeep  <= '0;
            m_axis_dma_tvalid <= 1'b0;
            m_axis_dma_tlast  <= 1'b0;
            logs_sent_cnt     <= '0;
            log_reg           <= '0;
        end else begin
            case (current_state)

                ST_IDLE: begin
                    m_axis_dma_tvalid <= 1'b0;
                    m_axis_dma_tlast  <= 1'b0;

                    if (in_log_valid) begin
                        log_reg       <= in_log_data;
                        current_state <= ST_SEND_W0;
                    end
                end

                ST_SEND_W0: begin
                    if (m_axis_dma_tready || !m_axis_dma_tvalid) begin
                        m_axis_dma_tvalid <= 1'b1;
                        m_axis_dma_tkeep  <= 8'hFF;
                        m_axis_dma_tlast  <= 1'b0;
                        m_axis_dma_tdata  <= log_reg.hw_timestamp_cycles;
                        current_state     <= ST_SEND_W1;
                    end
                end

                ST_SEND_W1: begin
                    if (m_axis_dma_tready) begin
                        m_axis_dma_tdata  <= {16'b0, log_reg.itch_timestamp};
                        current_state     <= ST_SEND_W2;
                    end
                end

                ST_SEND_W2: begin
                    if (m_axis_dma_tready) begin
                        m_axis_dma_tdata  <= log_reg.order_ref_num;
                        current_state     <= ST_SEND_W3;
                    end
                end

                ST_SEND_W3: begin
                    if (m_axis_dma_tready) begin
                        m_axis_dma_tdata  <= {log_reg.price, log_reg.shares};
                        current_state     <= ST_SEND_W4;
                    end
                end

                ST_SEND_W4: begin
                    if (m_axis_dma_tready) begin
                        m_axis_dma_tdata  <= {log_reg.stock_locate, log_reg.action_code, 40'b0};
                        m_axis_dma_tkeep  <= 8'hE0; // First 3 bytes valid (34 bytes total)
                        m_axis_dma_tlast  <= 1'b1;  // Assert TLAST for DMA packet boundary
                        logs_sent_cnt     <= logs_sent_cnt + 1'b1;
                        current_state     <= ST_IDLE;
                    end
                end

                default: current_state <= ST_IDLE;
            endcase
        end
    end

endmodule : axi_dma_telemetry_intf
