`timescale 1ns / 1ps

package can_scoreboard_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import can_txn_pkg::*;

    class can_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(can_scoreboard)

        uvm_analysis_imp #(can_seq_item, can_scoreboard) analysis_export;

        int total_frames  = 0;
        int passed_frames = 0;
        int failed_frames = 0;
        int ack_count     = 0;
        int nack_count    = 0;
        int reset_count   = 0;

        function new(string name = "can_scoreboard", uvm_component parent);
            super.new(name, parent);
            analysis_export = new("analysis_export", this);
        endfunction

        // Golden Reference Model: Build expected CAN 2.0A serial bitstream
        function automatic void build_expected_bits(
            input  can_seq_item txn,
            output bit          exp_bits [$],
            output int          ack_slot_idx
        );
            logic [14:0] crc_rg = 15'h0000;
            bit          raw_bits [$];
            int          eff_bytes = (txn.dlc > 4'd8) ? 8 : int'(txn.dlc);
            bit          last_b = 1'b0;
            int          run_len = 0;

            exp_bits.delete();

            // 1. Assemble unstuffed frame fields (SOF -> Data)
            raw_bits.push_back(1'b0); // SOF
            for (int i = 10; i >= 0; i--) raw_bits.push_back(txn.id[i]);
            raw_bits.push_back(1'b0); // RTR (Data Frame)
            raw_bits.push_back(1'b0); // IDE (Standard 11-bit ID)
            raw_bits.push_back(1'b0); // r0  (Reserved)
            for (int i = 3; i >= 0; i--)  raw_bits.push_back(txn.dlc[i]);
            for (int i = 0; i < eff_bytes * 8; i++) raw_bits.push_back(txn.data[63 - i]);

            // 2. Compute CAN CRC-15 (Generator polynomial: 0x4599)
            foreach (raw_bits[idx]) begin
                bit crc_nxt = raw_bits[idx] ^ crc_rg[14];
                crc_rg = {crc_rg[13:0], 1'b0} ^ (crc_nxt ? 15'h4599 : 15'h0000);
            end
            for (int i = 14; i >= 0; i--) raw_bits.push_back(crc_rg[i]);

            // 3. Apply CAN Bit Stuffing (insert complement bit after 5 identical consecutive bits)
            foreach (raw_bits[idx]) begin
                bit cur_b = raw_bits[idx];
                exp_bits.push_back(cur_b);

                if (run_len > 0 && cur_b == last_b)
                    run_len++;
                else begin
                    last_b  = cur_b;
                    run_len = 1;
                end

                if (run_len == 5) begin
                    exp_bits.push_back(~cur_b);
                    last_b  = ~cur_b;
                    run_len = 1;
                end
            end

            // 4. Fixed-form unstuffed trailer (CRC Delim + ACK Slot + 7-bit EOF + 3-bit IFS)
            exp_bits.push_back(1'b1); // CRC Delimiter
            ack_slot_idx = exp_bits.size();
            exp_bits.push_back(1'b1); // ACK Slot (TX outputs recessive 1)
            exp_bits.push_back(1'b1); // ACK Delimiter
            repeat (7) exp_bits.push_back(1'b1); // End of Frame (EOF)
            repeat (3) exp_bits.push_back(1'b1); // Interframe Space (IFS)
        endfunction

        // Helper to format a bit queue into a binary string for clear error diagnostics
        function automatic string bits_to_str(const ref bit q [$], input int max_len = -1);
            string s = "";
            int limit = (max_len < 0 || max_len > q.size()) ? q.size() : max_len;
            for (int i = 0; i < limit; i++) begin
                s = {s, q[i] ? "1" : "0"};
            end
            return s;
        endfunction

        // Analysis port callback from monitor
        virtual function void write(can_seq_item txn);
            bit exp_bits [$];
            int ack_slot_idx;
            bit frame_ok = 1'b1;

            total_frames++;
            build_expected_bits(txn, exp_bits, ack_slot_idx);

            // Case 1: Mid-frame synchronous reset abort
            if (txn.was_reset) begin
                reset_count++;
                if (txn.done !== 1'b0 || txn.ack_error !== 1'b0) begin
                    `uvm_error("SB_RST_ERR", $sformatf(
                        "Mid-frame reset frame asserted status flags! DONE=%0b ACK_ERR=%0b | %s",
                        txn.done, txn.ack_error, txn.convert2string()
                    ))
                    frame_ok = 1'b0;
                end
                if (txn.observed_bits.size() >= exp_bits.size()) begin
                    `uvm_error("SB_RST_LEN", $sformatf(
                        "Mid-frame reset frame did not abort early (OBS_BITS=%0d >= FULL=%0d) | %s",
                        txn.observed_bits.size(), exp_bits.size(), txn.convert2string()
                    ))
                    frame_ok = 1'b0;
                end
                for (int i = 0; i < txn.observed_bits.size(); i++) begin
                    if (txn.observed_bits[i] !== exp_bits[i]) begin
                        `uvm_error("SB_RST_BIT", $sformatf(
                            "Pre-reset bit mismatch at bit[%0d]: exp=%0b got=%0b | %s",
                            i, exp_bits[i], txn.observed_bits[i], txn.convert2string()
                        ))
                        frame_ok = 1'b0;
                        break;
                    end
                end
            end
            // Case 2: NACK error abort (i_can_rx stayed recessive 1 in ACK slot)
            else if (!txn.ack_response) begin
                int check_len = ack_slot_idx + 1; // Up through ACK slot
                nack_count++;

                if (txn.ack_error !== 1'b1 || txn.done !== 1'b0) begin
                    `uvm_error("SB_NACK_FLAG", $sformatf(
                        "Expected ACK_ERR=1 and DONE=0 on NACK frame, got ACK_ERR=%0b DONE=%0b | %s",
                        txn.ack_error, txn.done, txn.convert2string()
                    ))
                    frame_ok = 1'b0;
                end

                if (txn.observed_bits.size() < check_len) begin
                    `uvm_error("SB_NACK_LEN", $sformatf(
                        "NACK frame aborted too early: got %0d bits, expected at least %0d bits through ACK slot | %s",
                        txn.observed_bits.size(), check_len, txn.convert2string()
                    ))
                    frame_ok = 1'b0;
                end else begin
                    for (int i = 0; i < check_len; i++) begin
                        if (txn.observed_bits[i] !== exp_bits[i]) begin
                            `uvm_error("SB_NACK_BIT", $sformatf(
                                "NACK frame bit mismatch at bit[%0d]: exp=%0b got=%0b | %s",
                                i, exp_bits[i], txn.observed_bits[i], txn.convert2string()
                            ))
                            frame_ok = 1'b0;
                            break;
                        end
                    end
                end
            end
            // Case 3: Normal ACKed CAN frame transmission
            else begin
                ack_count++;

                if (txn.done !== 1'b1 || txn.ack_error !== 1'b0) begin
                    `uvm_error("SB_ACK_FLAG", $sformatf(
                        "Expected DONE=1 and ACK_ERR=0 on ACKed frame, got DONE=%0b ACK_ERR=%0b | %s",
                        txn.done, txn.ack_error, txn.convert2string()
                    ))
                    frame_ok = 1'b0;
                end

                // Check bit-by-bit across the expected frame (allow <= 1 trailing idle bit if DUT holds IFS/IDLE 1 extra tick)
                if (txn.observed_bits.size() < exp_bits.size() ||
                    txn.observed_bits.size() > exp_bits.size() + 1) begin
                    `uvm_error("SB_LEN_ERR", $sformatf(
                        "Frame length mismatch: expected %0d bits (or %0d), got %0d bits | %s\n  EXP: %s\n  GOT: %s",
                        exp_bits.size(), exp_bits.size() + 1, txn.observed_bits.size(), txn.convert2string(),
                        bits_to_str(exp_bits), bits_to_str(txn.observed_bits)
                    ))
                    frame_ok = 1'b0;
                end else begin
                    for (int i = 0; i < exp_bits.size(); i++) begin
                        if (txn.observed_bits[i] !== exp_bits[i]) begin
                            `uvm_error("SB_BIT_ERR", $sformatf(
                                "Bitstream mismatch at bit[%0d]: expected %0b, got %0b | %s\n  EXP: %s\n  GOT: %s",
                                i, exp_bits[i], txn.observed_bits[i], txn.convert2string(),
                                bits_to_str(exp_bits), bits_to_str(txn.observed_bits)
                            ))
                            frame_ok = 1'b0;
                            break;
                        end
                    end
                end
            end

            if (frame_ok) begin
                passed_frames++;
                `uvm_info("SB_PASS", $sformatf(
                    "PASS [%0s]: %s",
                    txn.was_reset ? "RESET" : (txn.ack_response ? "ACK" : "NACK"),
                    txn.convert2string()
                ), UVM_MEDIUM)
            end else begin
                failed_frames++;
            end
        endfunction

        virtual function void report_phase(uvm_phase phase);
            super.report_phase(phase);
            `uvm_info("SB_SUMMARY", $sformatf(
                "\n============================================================\n  CAN TX SCOREBOARD SUMMARY\n  Total Frames  : %0d (ACK=%0d, NACK=%0d, RESET=%0d)\n  Passed Frames : %0d\n  Failed Frames : %0d\n============================================================",
                total_frames, ack_count, nack_count, reset_count, passed_frames, failed_frames
            ), UVM_NONE)

            if (failed_frames > 0 || total_frames == 0) begin
                `uvm_error("SB_FAIL", $sformatf("Scoreboard detected %0d failed frames (total=%0d)!", failed_frames, total_frames))
            end
        endfunction

    endclass : can_scoreboard

endpackage : can_scoreboard_pkg