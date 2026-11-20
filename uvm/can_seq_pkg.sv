`timescale 1ps/1ps

package can_seq_pkg;
import uvm_pkg::*;
import can_txn_pkg::*;
`include "uvm_macros.svh"

    // Base Sequence: Default Settings
    class can_base_seq extends uvm_sequence #(can_seq_item);
        `uvm_object_utils(can_base_seq)

        function new(string name = "can_base_seq");
            super.new(name);
        endfunction

        virtual task send_item(
            input logic [10:0] id,
            input logic [3:0]  dlc,
            input logic [63:0] data,
            input bit          ack   = 1'b1,
            input bit          reset = 1'b0
        );
            can_seq_item req;
            req = can_seq_item::type_id::create("req");
            start_item(req);
            req.id              = id;
            req.dlc             = dlc;
            req.data            = data;
            req.ack_response    = ack;
            req.reset_mid_frame = reset;
            finish_item(req);
        endtask
    endclass

    // DLC clamping test: Check whether dlc constraints are sent properly or not.
    class can_dlc_sweep_seq extends can_base_seq;
        `uvm_object_utils(can_dlc_sweep_seq)

        function new(string name = "can_dlc_sweep_seq");
            super.new(name);
        endfunction

        virtual task body();
            can_seq_item req;
            int dlc_list [11] = '{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 15};

            // Test all valid DLCs (0 to 8) and out-of-range DLCs (9, 15)
            foreach (dlc_list[i]) begin
                int d_val;
                case (i)
                    0: d_val = 0;  1: d_val = 1;  2: d_val = 2;  3: d_val = 3;
                    4: d_val = 4;  5: d_val = 5;  6: d_val = 6;  7: d_val = 7;
                    8: d_val = 8;  9: d_val = 9; 10: d_val = 15;
                endcase

                req = can_seq_item::type_id::create("req");
                start_item(req);
                if (!req.randomize() with {
                    dlc             == 4'(d_val);
                    ack_response    == 1'b1;
                    reset_mid_frame == 1'b0;
                }) `uvm_fatal("SEQ", "Randomization failed in can_dlc_sweep_seq")
                finish_item(req);
            end
        endtask
    endclass

    // Bit Stuffing Test: Send long runs of 1s and 0s for a stress test.
    class can_stuffing_seq extends can_base_seq;
        `uvm_object_utils(can_stuffing_seq)

        function new(string name = "can_stuffing_seq");
            super.new(name);
        endfunction

        virtual task body();
            // Directed edge cases: 5 consecutive 0s in ID, all-0 data, all-1 data, alternating nibbles
            send_item(11'b000_0011_1110, 4'd8, 64'h0000_0000_0000_0000, 1'b1, 1'b0);
            send_item(11'b111_1100_0001, 4'd8, 64'hFFFF_FFFF_FFFF_FFFF, 1'b1, 1'b0);
            send_item(11'b101_0000_0111, 4'd4, 64'h00FF_00FF_0000_0000, 1'b1, 1'b0);
            send_item(11'h123,           4'd8, 64'hDEADBEEF_CAFEBABE, 1'b1, 1'b0);
        endtask
    endclass

    // NACK Response Test: Check if the Transciever aborts after ack_error.
    class can_nack_seq extends can_base_seq;
        `uvm_object_utils(can_nack_seq)

        function new(string name = "can_nack_seq");
            super.new(name);
        endfunction

        virtual task body();
            can_seq_item req;
            repeat (3) begin
                req = can_seq_item::type_id::create("req");
                start_item(req);
                if (!req.randomize() with {
                    ack_response    == 1'b0;
                    reset_mid_frame == 1'b0;
                }) `uvm_fatal("SEQ", "Randomization failed in can_nack_seq")
                finish_item(req);
            end
        endtask
    endclass

    // Mid-Frame Reset Test: Send in a sync. reset signal to check frame abort process.
    class can_reset_seq extends can_base_seq;
        `uvm_object_utils(can_reset_seq)

        function new(string name = "can_reset_seq");
            super.new(name);
        endfunction

        virtual task body();
            // 1. Frame aborted mid-transmission by synchronous reset
            send_item(11'h2AA, 4'd6, 64'h1122_3344_5566_0000, 1'b1, 1'b1);
            // 2. Normal frame immediately after reset to verify clean recovery
            send_item(11'h155, 4'd4, 64'hAABB_CCDD_0000_0000, 1'b1, 1'b0);
        endtask
    endclass
    
    // Full Regression Test: Run all scenarios back to back.
    class can_full_seq extends can_base_seq;
        `uvm_object_utils(can_full_seq)

        function new(string name = "can_full_seq");
            super.new(name);
        endfunction

        virtual task body();
            can_dlc_sweep_seq dlc_seq;
            can_stuffing_seq  stuff_seq;
            can_nack_seq      nack_seq;
            can_reset_seq     rst_seq;
            can_seq_item      rand_req;

            dlc_seq   = can_dlc_sweep_seq::type_id::create("dlc_seq");
            stuff_seq = can_stuffing_seq::type_id::create("stuff_seq");
            nack_seq  = can_nack_seq::type_id::create("nack_seq");
            rst_seq   = can_reset_seq::type_id::create("rst_seq");

            `uvm_info("FULL_SEQ", "--- Running DLC Sweep Sequence ---", UVM_LOW)
            dlc_seq.start(m_sequencer);

            `uvm_info("FULL_SEQ", "--- Running Bit Stuffing Stress Sequence ---", UVM_LOW)
            stuff_seq.start(m_sequencer);

            `uvm_info("FULL_SEQ", "--- Running NACK Error Sequence ---", UVM_LOW)
            nack_seq.start(m_sequencer);

            `uvm_info("FULL_SEQ", "--- Running Mid-Frame Reset Sequence ---", UVM_LOW)
            rst_seq.start(m_sequencer);

            `uvm_info("FULL_SEQ", "--- Running 10 Constrained-Random Frames ---", UVM_LOW)
            repeat (10) begin
                rand_req = can_seq_item::type_id::create("rand_req");
                start_item(rand_req);
                if (!rand_req.randomize())
                    `uvm_fatal("FULL_SEQ", "Randomization failed")
                finish_item(rand_req);
            end
        endtask
    endclass


endpackage