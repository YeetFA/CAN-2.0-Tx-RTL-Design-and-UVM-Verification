`timescale 1ns / 1ps

module can_tx_top #(
    parameter int SOF_OFFSET  = 0,
    parameter int ID_OFFSET   = 1,
    parameter int RTR_OFFSET  = 12,
    parameter int IDE_OFFSET  = 13,
    parameter int R0_OFFSET   = 14,
    parameter int DLC_OFFSET  = 15,
    parameter int DATA_OFFSET = 19,
    parameter int CRC_OFFSET  = 83,
    parameter int CRC_W       = 15
)(
    input  logic        i_clk,
    input  logic        i_rst_p,

    input  logic [63:0] i_can_data,
    input  logic [10:0] i_can_id,
    input  logic [3:0]  i_can_dlc,

    input  logic        i_can_bit_tick,
    input  logic        i_can_start,
    output logic        o_can_busy,
    output logic        o_can_done,
    output logic        o_can_ack_error,

    output logic        o_can_tx,
    input  logic        i_can_rx
);

    // -------------------------------------------------------------------------
    // Local Parameters & Sampled Frame Registers
    // -------------------------------------------------------------------------
    localparam int UNSTUFFED_MEM_W = 128;
    localparam int STUFFED_MEM_W   = 256;

    logic [10:0] id_reg;
    logic [3:0]  dlc_reg;
    logic [63:0] data_reg;

    // Effective byte count (CAN 2.0A allows 0..8 bytes; clamp >8 to 8)[cite: 14, 80]
    logic [3:0]  eff_bytes;
    logic [6:0]  data_bits_len;      // 0 to 64[cite: 80]
    logic [6:0]  crc_input_end_addr; // Last unstuffed address before CRC (18 + data_bits_len)
    logic [7:0]  stuffed_total_len;  // Total stuffed bits stored in stuffed_mem
    logic [7:0]  ack_slot_idx;       // Index of ACK slot in stuffed_mem

    assign eff_bytes          = (dlc_reg > 4'd8) ? 4'd8 : dlc_reg;
    assign data_bits_len      = {eff_bytes, 3'b000};
    assign crc_input_end_addr = 7'd18 + data_bits_len;

    // -------------------------------------------------------------------------
    // Submodule Interconnect Signals
    // -------------------------------------------------------------------------
    logic                                  umem_wr_en;
    logic [$clog2(UNSTUFFED_MEM_W)-1:0]    umem_wr_addr;
    logic                                  umem_wr_data;
    logic                                  umem_rd_en;
    logic [$clog2(UNSTUFFED_MEM_W)-1:0]    umem_rd_addr;
    logic                                  umem_rd_data;

    logic                                  smem_wr_en;
    logic [$clog2(STUFFED_MEM_W)-1:0]      smem_wr_addr;
    logic                                  smem_wr_data;
    logic                                  smem_rd_en;
    logic [$clog2(STUFFED_MEM_W)-1:0]      smem_rd_addr;
    logic                                  smem_rd_data;

    logic               crc_en;
    logic               crc_clear;
    logic               crc_last;
    logic               crc_done;
    logic               crc_bit;
    logic [CRC_W-1:0]   crc_result;

    logic               bs_phase_valid;
    logic               bs_stuff_flag;
    logic               bs_data;
    logic               bs_st_data;
    logic               bs_data_valid;
    logic               bs_st_valid;

    // -------------------------------------------------------------------------
    // Submodule Instantiations[cite: 81, 82, 83, 84]
    // -------------------------------------------------------------------------
    memory #(
        .WIDTH  (UNSTUFFED_MEM_W),
        .DATA_W (1)
    ) unstuffed_memory (
        .i_clk     (i_clk),
        .i_wr_en   (umem_wr_en),
        .i_wr_addr (umem_wr_addr),
        .i_wr_data (umem_wr_data),
        .i_rd_en   (umem_rd_en),
        .i_rd_addr (umem_rd_addr),
        .o_rd_data (umem_rd_data)
    );

    memory #(
        .WIDTH  (STUFFED_MEM_W),
        .DATA_W (1)
    ) stuffed_memory (
        .i_clk     (i_clk),
        .i_wr_en   (smem_wr_en),
        .i_wr_addr (smem_wr_addr),
        .i_wr_data (smem_wr_data),
        .i_rd_en   (smem_rd_en),
        .i_rd_addr (smem_rd_addr),
        .o_rd_data (smem_rd_data)
    );

    bit_stuffer bitstuffer (
        .i_clk         (i_clk),
        .i_rst_p       (i_rst_p),
        .i_phase_valid (bs_phase_valid),
        .i_mem_data    (bs_data),
        .o_st_data     (bs_st_data),
        .i_data_valid  (bs_data_valid),
        .o_st_valid    (bs_st_valid),
        .o_stuff_flag  (bs_stuff_flag)
    );

    crc_calc #(
        .CRC_W    (CRC_W),
        .CRC_POLY ('h4599)
    ) crc_calculator (
        .i_clk        (i_clk),
        .i_rst_p      (i_rst_p),
        .i_crc_en     (crc_en),
        .i_crc_clear  (crc_clear),
        .i_crc_last   (crc_last),
        .o_crc_done   (crc_done),
        .i_crc_bit    (crc_bit),
        .o_crc_result (crc_result)
    );

    // -------------------------------------------------------------------------
    // Control FSM Definition[cite: 78]
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
        IDLE,
        FETCH,
        CRC_CLEAR,
        CRC_FEED,
        CRC_WAIT,
        CRC_STORE,
        STUFF_PREFETCH,
        BIT_STUFF,
        STUFF_TAIL,
        STREAM_PREFETCH,
        STREAM,
        COMPLETE
    } state_t;

    state_t state, next_state;

    logic [6:0] step_cnt;
    logic [6:0] stuff_rd_idx;
    logic [7:0] stuff_wr_idx;
    logic [7:0] stream_idx;
    logic       rd_valid_d;
    logic       ack_seen;

    logic [6:0] stuff_last_logical_idx;
    assign stuff_last_logical_idx = crc_input_end_addr + 7'd15;

    function automatic logic [6:0] map_unstuffed_addr(
        input logic [6:0] logical_idx,
        input logic [6:0] end_data_addr
    );
        if (logical_idx <= end_data_addr)
            return logical_idx;
        else
            return CRC_OFFSET[6:0] + (logical_idx - end_data_addr - 7'd1);
    endfunction

    // Single continuous driver for o_can_tx (recessive 1 outside STREAM)[cite: 10, 75]
    assign o_can_tx = (state == STREAM) ? smem_rd_data : 1'b1;

    // -------------------------------------------------------------------------
    // State Register
    // -------------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_rst_p)
            state <= IDLE;
        else
            state <= next_state;
    end

    // -------------------------------------------------------------------------
    // Next-State Combinational Logic
    // -------------------------------------------------------------------------
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (i_can_start)
                    next_state = FETCH;
            end

            FETCH: begin
                if (step_cnt == crc_input_end_addr)
                    next_state = CRC_CLEAR;
            end

            CRC_CLEAR: begin
                next_state = CRC_FEED;
            end

            CRC_FEED: begin
                if (step_cnt == crc_input_end_addr)
                    next_state = CRC_WAIT;
            end

            CRC_WAIT: begin
                if (crc_done)
                    next_state = CRC_STORE;
            end

            CRC_STORE: begin
                if (step_cnt == 7'd14)
                    next_state = STUFF_PREFETCH;
            end

            STUFF_PREFETCH: begin
                next_state = BIT_STUFF;
            end

            BIT_STUFF: begin
                if (!bs_stuff_flag && (stuff_rd_idx > stuff_last_logical_idx))
                    next_state = STUFF_TAIL;
            end

            STUFF_TAIL: begin
                if (step_cnt == 7'd12)
                    next_state = STREAM_PREFETCH;
            end

            STREAM_PREFETCH: begin
                if(i_can_bit_tick)
                    next_state = STREAM;
            end

            STREAM: begin
                if (i_can_bit_tick) begin
                    if ((stream_idx == ack_slot_idx) && (i_can_rx != 1'b0))
                        next_state = IDLE;
                    else if (stream_idx == stuffed_total_len - 8'd1)
                        next_state = COMPLETE;
                end
            end

            COMPLETE: begin
                next_state = IDLE;
            end

            default: next_state = IDLE;
        endcase
    end

    // -------------------------------------------------------------------------
    // Datapath & Sequential Control (o_can_tx is NOT assigned here)
    // -------------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_rst_p) begin
            id_reg            <= '0;
            dlc_reg           <= '0;
            data_reg          <= '0;
            step_cnt          <= '0;
            stuff_rd_idx      <= '0;
            stuff_wr_idx      <= '0;
            stream_idx        <= '0;
            stuffed_total_len <= '0;
            ack_slot_idx      <= '0;
            ack_seen          <= '0;
            rd_valid_d        <= 1'b0;
            o_can_busy        <= 1'b0;
            o_can_done        <= 1'b0;
            o_can_ack_error   <= 1'b0;
        end else begin
            o_can_done <= 1'b0;

            case (state)
                IDLE: begin
                    o_can_busy <= 1'b0;
                    step_cnt   <= '0;
                    rd_valid_d <= 1'b0;

                    if (i_can_start) begin
                        id_reg          <= i_can_id;
                        dlc_reg         <= i_can_dlc;
                        data_reg        <= i_can_data;
                        o_can_busy      <= 1'b1;
                        o_can_ack_error <= 1'b0;
                    end
                end

                FETCH: begin
                    if (step_cnt == crc_input_end_addr)
                        step_cnt <= '0;
                    else
                        step_cnt <= step_cnt + 7'd1;
                end

                CRC_CLEAR: begin
                    step_cnt   <= '0;
                    rd_valid_d <= 1'b0;
                end

                CRC_FEED: begin
                    rd_valid_d <= 1'b1;
                    if (step_cnt == crc_input_end_addr)
                        step_cnt <= '0;
                    else
                        step_cnt <= step_cnt + 7'd1;
                end

                CRC_WAIT: begin
                    rd_valid_d <= 1'b0;
                    step_cnt   <= '0;
                end

                CRC_STORE: begin
                    if (step_cnt == 7'd14)
                        step_cnt <= '0;
                    else
                        step_cnt <= step_cnt + 7'd1;
                end

                STUFF_PREFETCH: begin
                    stuff_rd_idx <= '0;
                    stuff_wr_idx <= '0;
                end

                BIT_STUFF: begin
                    if (bs_st_valid)
                        stuff_wr_idx <= stuff_wr_idx + 8'd1;

                    if (!bs_stuff_flag) begin
                        if (stuff_rd_idx > stuff_last_logical_idx)
                            step_cnt <= '0;
                        else
                            stuff_rd_idx <= stuff_rd_idx + 7'd1;
                    end
                end

                STUFF_TAIL: begin
                    stuff_wr_idx <= stuff_wr_idx + 8'd1;
                    if (step_cnt == 7'd1)
                        ack_slot_idx <= stuff_wr_idx;

                    if (step_cnt == 7'd12) begin
                        stuffed_total_len <= stuff_wr_idx + 8'd1;
                        step_cnt          <= '0;
                    end else begin
                        step_cnt <= step_cnt + 7'd1;
                    end
                end

                STREAM_PREFETCH: begin
                    stream_idx <= 8'd0;
                end

                STREAM: begin
                    if (stream_idx == ack_slot_idx && i_can_rx == 1'b0)
                        ack_seen <= 1'b1;

                    if (i_can_bit_tick) begin
                        ack_seen <= 1'b0;
                        if ((stream_idx == ack_slot_idx) && !(ack_seen || (i_can_rx == 1'b0))) begin
                        o_can_ack_error <= 1'b1;
                        o_can_busy      <= 1'b0;
                        end else begin
                            stream_idx <= stream_idx + 8'd1;
                        end
                    end else begin
                        ack_seen <= 1'b0;
                    end
                end

                COMPLETE: begin
                    o_can_busy <= 1'b0;
                    o_can_done <= 1'b1;
                end

                default: begin
                    o_can_busy <= 1'b0;
                end
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Combinational Submodule Drive Logic
    // -------------------------------------------------------------------------
    // 1. Unstuffed Memory Write Mux (FETCH & CRC_STORE)
    always_comb begin
        umem_wr_en   = 1'b0;
        umem_wr_addr = '0;
        umem_wr_data = 1'b0;

        if (state == FETCH) begin
            umem_wr_en   = 1'b1;
            umem_wr_addr = step_cnt;

            if (step_cnt == SOF_OFFSET[6:0])
                umem_wr_data = 1'b0;
            else if (step_cnt < RTR_OFFSET[6:0])
                umem_wr_data = id_reg[10 - (step_cnt - ID_OFFSET[6:0])];
            else if (step_cnt == RTR_OFFSET[6:0])
                umem_wr_data = 1'b0;
            else if (step_cnt == IDE_OFFSET[6:0])
                umem_wr_data = 1'b0;
            else if (step_cnt == R0_OFFSET[6:0])
                umem_wr_data = 1'b0;
            else if (step_cnt < DATA_OFFSET[6:0])
                umem_wr_data = dlc_reg[3 - (step_cnt - DLC_OFFSET[6:0])];
            else
                umem_wr_data = data_reg[63 - (step_cnt - DATA_OFFSET[6:0])];
        end else if (state == CRC_STORE) begin
            umem_wr_en   = 1'b1;
            umem_wr_addr = CRC_OFFSET[6:0] + step_cnt;
            umem_wr_data = crc_result[14 - step_cnt];
        end
    end

    // 2. Unstuffed Memory Read Mux (CRC_FEED & BIT_STUFF)
    logic [6:0] prefetch_rd_idx;
    assign prefetch_rd_idx = stuff_rd_idx + 7'd1;

    always_comb begin
        umem_rd_en   = 1'b0;
        umem_rd_addr = '0;

        if (state == CRC_FEED) begin
            umem_rd_en   = 1'b1;
            umem_rd_addr = step_cnt;
        end else if (state == STUFF_PREFETCH) begin
            umem_rd_en   = 1'b1;
            umem_rd_addr = 7'd0;
        end else if (state == BIT_STUFF) begin
            umem_rd_en   = !bs_stuff_flag; 
            if (prefetch_rd_idx <= stuff_last_logical_idx)
                umem_rd_addr = map_unstuffed_addr(prefetch_rd_idx, crc_input_end_addr);
            else
                umem_rd_addr = '0;
        end
    end

    // 3. CRC Calculator Control
    logic last_crc_bit_d;
    always_ff @(posedge i_clk) begin
        if (i_rst_p)
            last_crc_bit_d <= 1'b0;
        else
            last_crc_bit_d <= (state == CRC_FEED) && (step_cnt == crc_input_end_addr);
    end

    assign crc_clear = (state == CRC_CLEAR);
    assign crc_en    = rd_valid_d;
    assign crc_bit   = umem_rd_data;
    assign crc_last  = last_crc_bit_d;

    // 4. Bit Stuffer Control
    assign bs_phase_valid = (state == BIT_STUFF);
    assign bs_data_valid  = (state == BIT_STUFF) && (stuff_rd_idx <= stuff_last_logical_idx);
    assign bs_data        = umem_rd_data;
    
    // 5. Stuffed Memory Write & Read Control
    always_comb begin
        smem_wr_en   = 1'b0;
        smem_wr_addr = stuff_wr_idx;
        smem_wr_data = 1'b1;

        if (state == BIT_STUFF) begin
            smem_wr_en   = bs_st_valid;
            smem_wr_data = bs_st_data;
        end else if (state == STUFF_TAIL) begin
            smem_wr_en   = 1'b1;
            smem_wr_data = 1'b1;
        end
    end

    always_comb begin
        smem_rd_en   = 1'b0;
        smem_rd_addr = '0;

        if (state == STREAM_PREFETCH) begin
            smem_rd_en   = 1'b1;
            smem_rd_addr = 8'd0;
        end else if (state == STREAM) begin
            smem_rd_en   = 1'b1;
            smem_rd_addr = i_can_bit_tick ? (stream_idx + 8'd1) : stream_idx;
        end
    end
endmodule
