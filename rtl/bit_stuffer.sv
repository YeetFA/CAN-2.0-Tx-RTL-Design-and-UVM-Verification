`timescale 1ns / 1ps

module bit_stuffer (
    input  logic i_clk,
    input  logic i_rst_p,
        
    input  logic i_phase_valid,     // high from SOF through the CRC sequence

    input  logic i_mem_data,        // unstuffed bit from the 128x1 memory
    output logic o_st_data,

    input  logic i_data_valid,
    output logic o_st_valid,
    
    output logic o_stuff_flag       // tells the stream FSM not to advance
);

    logic       last_bit;
    logic [2:0] run_cnt;            // 0 = no run, 1..5 = run length

    assign o_stuff_flag = i_phase_valid && (run_cnt == 3'd5);

    // Mux: stuff bit, pass-through, or buffer (enable low)
    always_comb begin
        if (o_stuff_flag) begin
            o_st_data  = ~last_bit;
            o_st_valid = 1'b1;
        end else begin
            o_st_data  = i_mem_data;
            o_st_valid = i_data_valid;
        end
    end

    always_ff @(posedge i_clk) begin
        if (i_rst_p) begin
            last_bit <= 1'b0;
            run_cnt  <= 3'd0;
        end else if (!i_phase_valid) begin
                run_cnt <= 3'd0;                 // reset run outside stuffed region
            end else if (o_stuff_flag) begin
                last_bit <= ~last_bit;           // stuff bit becomes the new run
                run_cnt  <= 3'd1;
            end else if (i_data_valid)
                if (run_cnt != 3'd0 && i_mem_data == last_bit) begin
                    run_cnt <= run_cnt + 3'd1;   // extend run (max reaches 5)
            end else begin
                    last_bit    <= i_mem_data;         // start new run
                    run_cnt     <= 3'd1;
        end
    end
endmodule
