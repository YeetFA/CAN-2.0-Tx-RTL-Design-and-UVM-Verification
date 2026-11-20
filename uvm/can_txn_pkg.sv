`timescale 1ps/1ps

package can_txn_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    class can_seq_item extends uvm_sequence_item;
        `uvm_object_utils(can_seq_item)
        function new(string name = "can_seq_item");
            super.new(name);            
        endfunction

        // Random Stimilus:
        rand bit [10:0] id;
        rand bit [63:0] data;
        rand bit [3:0]  dlc;

        rand bit        ack_response;       // 1 = ACK (dominant 0), 0 = NACK (Recessive 1)
        rand bit        reset_mid_frame;    // 1 = Assert sync reset during transmission.
        
        // Observed Response:
        bit             observed_bits [$];  // Serial bitstream captured from o_can_tx.
        bit             ack_error;
        bit             done;
        bit             was_reset;          // Flag indicating frame was aborted via reset.

        // Constraints:
        
        // 1) Data Length Weighted Distribution:
        constraint c_valid_dlc {
            dlc dist {
                0       := 15,
                [1:7]   := 55,
                8       := 25,
                [9:15]  := 5    // Tests clamping behaviour (dlc>8 is clamped to 8)
            };
        }
        
        // 2) CAN 2.0A rule: Top 7 MSB of ID must not be all recessive:
        constraint c_valid_id {
            id[10:4] != 7'b111_1111;
        }

        function string convert2string();
            return $sformatf(
                "ID=0x%03h DLC=%0d DATA=0x%016h ACK_INJ=%0b RST=%0b | OBS_BITS=%0d DONE=%0b ACK_ERR=%0b",
                id, dlc, data, ack_response, reset_mid_frame, observed_bits.size(), done, ack_error
            );
        endfunction        
    endclass
endpackage