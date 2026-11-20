`timescale 1ns / 1ps

module crc_calc #(
    parameter int   CRC_W       = 15,
    parameter       CRC_POLY    = 'h4599
)(
    input   logic               i_clk,
    input   logic               i_rst_p,

    input   logic               i_crc_en,
    input   logic               i_crc_clear,
    input   logic               i_crc_last,
    output  logic               o_crc_done,

    input   logic               i_crc_bit,
    
    output  logic   [CRC_W-1:0] o_crc_result
);

    // CRC Calculation Steps: 
    function automatic logic [CRC_W-1:0] crc_step(input logic [CRC_W-1:0] crc_sr, input logic bit_in);
        logic fb; // Feedback Signal from the last register
        fb = bit_in ^ crc_sr[CRC_W-1];
        return {crc_sr[CRC_W-2:0],1'b0} ^ (fb ? CRC_POLY : '0);        
         
    endfunction

    // Sample Interface Registers:
    logic en_q, bit_q, last_q;
    always_ff @(posedge i_clk) begin 
        if(i_rst_p) begin
            en_q    <= 1'b0;
            bit_q   <= 1'b0;
            last_q  <= 1'b0;
        end else begin
            en_q    <= i_crc_en;
            bit_q   <= i_crc_bit;
            last_q  <= i_crc_last;
        end
    end

    // CRC Register and Done Flag Logic
    logic   [CRC_W-1:0] crc_reg;
    always_ff @(posedge i_clk) begin
        if(i_rst_p || i_crc_clear) begin
            crc_reg     <= '0;
            o_crc_done  <= '0;    
        end else begin
            if(en_q) 
                crc_reg <= crc_step(crc_reg, bit_q);
            o_crc_done <= en_q & last_q;
        end
    end

    assign o_crc_result = crc_reg;
endmodule
