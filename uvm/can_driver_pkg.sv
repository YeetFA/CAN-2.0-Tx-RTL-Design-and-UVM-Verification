`timescale 1ns / 1ps

package can_driver_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import can_txn_pkg::*;

    class can_driver extends uvm_driver #(can_seq_item);
        `uvm_component_utils(can_driver)

        virtual dut_if vif;
        can_seq_item   req_item;

        function new(string name = "can_driver", uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual dut_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal(get_type_name(), "NOVIF_DRV: Didn't get handle to virtual interface")
            end
        endfunction

        // Helper: Compute exact ACK slot bit index so driver knows when to assert i_can_rx
        function automatic int calc_ack_pos(can_seq_item item);
            logic [14:0] crc_rg = 15'h0000;
            logic        raw_bits [$];
            int          eff_bytes = (item.dlc > 4'd8) ? 8 : int'(item.dlc);
            logic        last_b = 1'b0;
            int          run_len = 0;
            int          stuffed_cnt = 0;

            raw_bits.push_back(1'b0); // SOF
            for (int i = 10; i >= 0; i--) raw_bits.push_back(item.id[i]);
            raw_bits.push_back(1'b0); // RTR
            raw_bits.push_back(1'b0); // IDE
            raw_bits.push_back(1'b0); // r0
            for (int i = 3; i >= 0; i--)  raw_bits.push_back(item.dlc[i]);
            for (int i = 0; i < eff_bytes * 8; i++) raw_bits.push_back(item.data[63 - i]);

            foreach (raw_bits[idx]) begin
                logic crc_nxt = raw_bits[idx] ^ crc_rg[14];
                crc_rg = {crc_rg[13:0], 1'b0} ^ (crc_nxt ? 15'h4599 : 15'h0000);
            end
            for (int i = 14; i >= 0; i--) raw_bits.push_back(crc_rg[i]);

            foreach (raw_bits[idx]) begin
                logic cur_b = raw_bits[idx];
                stuffed_cnt++;
                if (run_len > 0 && cur_b == last_b)
                    run_len++;
                else begin
                    last_b  = cur_b;
                    run_len = 1;
                end
                if (run_len == 5) begin
                    stuffed_cnt++;
                    last_b  = ~last_b;
                    run_len = 1;
                end
            end
            return stuffed_cnt + 1; // +1 skips CRC Delimiter to land on ACK Slot
        endfunction

        virtual task run_phase(uvm_phase phase);
            // Safe defaults
            vif.i_rst_p     <= 1'b0;
            vif.i_can_start <= 1'b0;
            vif.i_can_id    <= '0;
            vif.i_can_dlc   <= '0;
            vif.i_can_data  <= '0;
            vif.i_can_rx    <= 1'b1;

            // Wait for initial reset release
            @(posedge vif.i_clk);
            wait (!vif.i_rst_p);

            forever begin
                seq_item_port.get_next_item(req_item);
                drive_frame(req_item);
                seq_item_port.item_done();
            end
        endtask

        virtual task drive_frame(can_seq_item item);
            int ack_pos  = calc_ack_pos(item);
            int bit_idx  = 0;
            bit sof_seen = 1'b0;

            // 1. Launch frame on rising clock edge
            @(posedge vif.i_clk);
            vif.i_can_id    <= item.id;
            vif.i_can_dlc   <= item.dlc;
            vif.i_can_data  <= item.data;
            vif.i_can_start <= 1'b1;
            vif.i_can_rx    <= 1'b1;

            @(posedge vif.i_clk);
            vif.i_can_start <= 1'b0;

            // 2. Wait until DUT enters busy state
            wait (vif.o_can_busy == 1'b1);

            // 3. Track bit ticks through STREAM phase starting from SOF
            while (vif.o_can_busy == 1'b1) begin
                @(posedge vif.i_clk);

                // Mid-frame synchronous reset test
                if (item.reset_mid_frame && (bit_idx == 10)) begin
                    vif.i_rst_p  <= 1'b1;
                    vif.i_can_rx <= 1'b1;
                    repeat (3) @(posedge vif.i_clk);
                    vif.i_rst_p  <= 1'b0;
                    @(posedge vif.i_clk);
                    return;
                end

                if (vif.i_can_bit_tick) begin
                    if (!sof_seen && (vif.o_can_tx == 1'b0))
                        sof_seen = 1'b1;

                    if (sof_seen) begin
                        bit_idx++;
                        vif.i_can_rx <= (bit_idx == ack_pos) ? (item.ack_response ? 1'b0 : 1'b1) : 1'b1;
                    end
                end
            end

            vif.i_can_rx <= 1'b1;
            repeat (2) @(posedge vif.i_clk);
        endtask

    endclass : can_driver

endpackage : can_driver_pkg