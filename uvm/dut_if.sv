`timescale 1ps/1ps

interface dut_if (input i_clk);

    logic           i_rst_p;
    logic   [63:0]  i_can_data;
    logic   [10:0]  i_can_id;
    logic   [3:0]   i_can_dlc;
    
    logic           i_can_bit_tick;
    logic           i_can_start;
    logic           o_can_busy;
    logic           o_can_done;
    logic           o_can_ack_error;

    logic           o_can_tx;
    logic           i_can_rx;   
endinterface
