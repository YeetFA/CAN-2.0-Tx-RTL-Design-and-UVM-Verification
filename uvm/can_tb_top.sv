`timescale 1ns / 1ps

module can_tb_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import can_txn_pkg::*;
    import can_seq_pkg::*;
    import can_driver_pkg::*;
    import can_monitor_pkg::*;
    import can_agent_pkg::*;
    import can_scoreboard_pkg::*;
    import can_coverage_pkg::*;
    import can_env_pkg::*;
    import can_test_pkg::*;

    localparam int CLK_PERIOD    = 10;
    localparam int TICKS_PER_BIT = 16;

    logic i_clk;
    logic i_rst_p;

    // -------------------------------------------------------------------------
    // Clock & Initial Reset Generation
    // -------------------------------------------------------------------------
    initial begin
        i_clk = 1'b0;
        forever #(CLK_PERIOD / 2) i_clk = ~i_clk;
    end

    initial begin
        i_rst_p = 1'b1;
        repeat (5) @(posedge i_clk);
        i_rst_p = 1'b0;
    end

    // -------------------------------------------------------------------------
    // Interface Instantiation (Allow driver to also assert mid-frame reset)
    // -------------------------------------------------------------------------
    dut_if vif (
        .i_clk (i_clk)
    );

    logic dut_rst_p;
    assign dut_rst_p = i_rst_p | vif.i_rst_p;

    // -------------------------------------------------------------------------
    // Bit-Tick Generator (1 tick every 16 system clocks)
    // -------------------------------------------------------------------------
    int tick_cnt;
    always_ff @(posedge i_clk) begin
        if (dut_rst_p) begin
            tick_cnt           <= 0;
            vif.i_can_bit_tick <= 1'b0;
        end else if (tick_cnt == TICKS_PER_BIT - 1) begin
            tick_cnt           <= 0;
            vif.i_can_bit_tick <= 1'b1;
        end else begin
            tick_cnt           <= tick_cnt + 1;
            vif.i_can_bit_tick <= 1'b0;
        end
    end

    // -------------------------------------------------------------------------
    // DUT Instantiation
    // -------------------------------------------------------------------------
    can_tx_top dut (
        .i_clk           (i_clk),
        .i_rst_p         (vif.i_rst_p),
        .i_can_data      (vif.i_can_data),
        .i_can_id        (vif.i_can_id),
        .i_can_dlc       (vif.i_can_dlc),
        .i_can_bit_tick  (vif.i_can_bit_tick),
        .i_can_start     (vif.i_can_start),
        .o_can_busy      (vif.o_can_busy),
        .o_can_done      (vif.o_can_done),
        .o_can_ack_error (vif.o_can_ack_error),
        .o_can_tx        (vif.o_can_tx),
        .i_can_rx        (vif.i_can_rx)
    );

    // -------------------------------------------------------------------------
    // Watchdog Timer
    // -------------------------------------------------------------------------
    initial begin
        #5ms;
        `uvm_fatal("WATCHDOG", "Simulation timed out after 5ms!")
    end

    // -------------------------------------------------------------------------
    // UVM Config DB & Test Execution
    // -------------------------------------------------------------------------
    initial begin
        string test_name;
        $dumpfile("can_uvm.vcd");
        $dumpvars(0, can_tb_top);

        uvm_config_db #(virtual dut_if)::set(null, "*", "vif", vif);
        if($value$plusargs("UVM_TESTNAME=%s",test_name))
            run_test();
        else
            run_test("can_full_test");
    end

endmodule : can_tb_top