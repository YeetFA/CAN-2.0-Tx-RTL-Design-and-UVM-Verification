`timescale 1ns / 1ps

module memory #(
    parameter int WIDTH = 128,
    parameter int DATA_W = 1
)(
    
    input   logic                       i_clk,
    
    // WRITE PORT
    input   logic                       i_wr_en,
    input   logic [$clog2(WIDTH)-1:0]   i_wr_addr,
    input   logic [DATA_W-1:0]          i_wr_data,

    // READ PORT
    input   logic                       i_rd_en,
    input   logic [$clog2(WIDTH)-1:0]   i_rd_addr,
    output  logic [DATA_W-1:0]          o_rd_data
    
);

    logic [DATA_W-1:0] mem [WIDTH-1:0];

    always_ff @(posedge i_clk) begin // Write Logic
        if(i_wr_en)
            mem[i_wr_addr] <= i_wr_data;        
    end 

    always_ff @(posedge i_clk) begin  //Read Logic
        if(i_rd_en)
            o_rd_data <= mem[i_rd_addr];
    end

endmodule
