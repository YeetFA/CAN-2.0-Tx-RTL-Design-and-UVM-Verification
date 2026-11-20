`timescale 1ns / 1ps

package can_coverage_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import can_txn_pkg::*;

    class can_coverage extends uvm_subscriber #(can_seq_item);
        `uvm_component_utils(can_coverage)

        int cov_stuff_bits;

        // SINCE VERILATOR DOES NOT SUPPORT & IGNORE
        // COVERPOINT/COVERGROUPS AS OF NOW (v5.042 COVERIGN ERROR),
        // WE ARE BYPASSING THAT WITH INT VARIABLES FOR EACH BIN 
        // TO CALCULATE COVERAGE OURSELVES.
        // (I KNOW ITS NOT THE STANDARD WAY BUT STILL...)

        // TOGGLE AND LINE COVERAGE ARE STILL SUPPORTED WITH HTML THOUGH. 
        

        
        // Deterministic functional coverage bin hit counters

        int hit_dlc_zero     = 0;
        int hit_dlc_mid      = 0; // 1..7
        int hit_dlc_eight    = 0; // 8
        int hit_dlc_clamped  = 0; // 9..15

        int hit_id_low       = 0; // 0x000..0x1FF
        int hit_id_mid       = 0; // 0x200..0x5FF
        int hit_id_high      = 0; // 0x600..0x7EF

        int hit_outcome_ack  = 0;
        int hit_outcome_nack = 0;
        int hit_outcome_rst  = 0;

        int hit_stuff_light  = 0; // 0..4 stuff bits
        int hit_stuff_med    = 0; // 5..14 stuff bits
        int hit_stuff_heavy  = 0; // >= 15 stuff bits

        int total_sampled    = 0;

        function new(string name = "can_coverage", uvm_component parent);
            super.new(name, parent);
        endfunction

        // Estimate number of stuffed bits inserted in the frame (47 fixed base bits + 8*eff_dlc)
        function automatic int calc_stuff_count(can_seq_item t);
            int eff_bytes = (t.dlc > 4'd8) ? 8 : int'(t.dlc);
            int unstuffed_len = 47 + (eff_bytes * 8);
            int diff = t.observed_bits.size() - unstuffed_len;
            return (diff > 0) ? diff : 0;
        endfunction

        // uvm_subscriber analysis write callback
        virtual function void write(can_seq_item t);
            total_sampled++;
            cov_stuff_bits = calc_stuff_count(t);

            // Update DLC bins
            if (t.dlc == 4'd0)       hit_dlc_zero++;
            else if (t.dlc <= 4'd7)  hit_dlc_mid++;
            else if (t.dlc == 4'd8)  hit_dlc_eight++;
            else                     hit_dlc_clamped++;

            // Update ID priority bins
            if (t.id <= 11'h1FF)      hit_id_low++;
            else if (t.id <= 11'h5FF) hit_id_mid++;
            else                      hit_id_high++;

            // Update Outcome bins
            if (t.was_reset) begin
                hit_outcome_rst++;
            end else if (t.ack_response) begin
                hit_outcome_ack++;
                if (cov_stuff_bits < 5)       hit_stuff_light++;
                else if (cov_stuff_bits < 15) hit_stuff_med++;
                else                          hit_stuff_heavy++;
            end else begin
                hit_outcome_nack++;
            end
        endfunction

        virtual function void report_phase(uvm_phase phase);
            int bins_hit = 0;
            int total_bins = 13;
            real cov_pct;
            string summary_msg;
            
            super.report_phase(phase);

            if (hit_dlc_zero     > 0) bins_hit++;
            if (hit_dlc_mid      > 0) bins_hit++;
            if (hit_dlc_eight    > 0) bins_hit++;
            if (hit_dlc_clamped  > 0) bins_hit++;

            if (hit_id_low       > 0) bins_hit++;
            if (hit_id_mid       > 0) bins_hit++;
            if (hit_id_high      > 0) bins_hit++;

            if (hit_outcome_ack  > 0) bins_hit++;
            if (hit_outcome_nack > 0) bins_hit++;
            if (hit_outcome_rst  > 0) bins_hit++;

            if (hit_stuff_light  > 0) bins_hit++;
            if (hit_stuff_med    > 0) bins_hit++;
            if (hit_stuff_heavy  > 0) bins_hit++;

            cov_pct = (real'(bins_hit) / real'(total_bins)) * 100.0;

            summary_msg = $sformatf(
                "\n============================================================\n  CAN TX FUNCTIONAL COVERAGE SUMMARY (%0.1f%% - %0d/%0d bins)\n  Total Transactions Sampled : %0d\n------------------------------------------------------------\n  [DLC]     0=%0d | 1..7=%0d | 8=%0d | Clamped(9..15)=%0d\n  [ID]      HighPrio(0x000..1FF)=%0d | Mid(0x200..5FF)=%0d | Low(0x600..7EF)=%0d\n  [OUTCOME] ACK=%0d | NACK_Abort=%0d | MidFrame_Reset=%0d\n  [STUFF]   Light(<5)=%0d | Med(5..14)=%0d | Heavy(>=15)=%0d\n============================================================",
                cov_pct, bins_hit, total_bins, total_sampled,
                hit_dlc_zero, hit_dlc_mid, hit_dlc_eight, hit_dlc_clamped,
                hit_id_low, hit_id_mid, hit_id_high,
                hit_outcome_ack, hit_outcome_nack, hit_outcome_rst,
                hit_stuff_light, hit_stuff_med, hit_stuff_heavy
            );

            `uvm_info("COV_SUMMARY", summary_msg, UVM_NONE)
        endfunction

    endclass : can_coverage

endpackage : can_coverage_pkg