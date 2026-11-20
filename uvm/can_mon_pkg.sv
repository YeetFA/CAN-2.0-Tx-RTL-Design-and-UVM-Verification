`timescale 1ns / 1ps

package can_monitor_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import can_txn_pkg::*;

    class can_monitor extends uvm_monitor;
        `uvm_component_utils(can_monitor)

        virtual dut_if vif;
        uvm_analysis_port #(can_seq_item) ap;

        function new(string name = "can_monitor", uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual dut_if)::get(this, "", "vif", vif)) begin
                `uvm_fatal(get_type_name(), "NOVIF_MON: Didn't get handle to virtual interface")
            end
        endfunction

        virtual task run_phase(uvm_phase phase);
            can_seq_item mon_item;

            // Wait for initial reset release
            @(posedge vif.i_clk);
            wait (!vif.i_rst_p);

            forever begin
                // 1. Wait for a new transmission start request
                @(posedge vif.i_clk);
                if (vif.i_can_start && !vif.i_rst_p) begin
                    bit sof_seen = 1'b0;
                    mon_item = can_seq_item::type_id::create("mon_item");

                    // Sample parallel inputs at the start of the transaction
                    mon_item.id              = vif.i_can_id;
                    mon_item.dlc             = vif.i_can_dlc;
                    mon_item.data            = vif.i_can_data;
                    mon_item.ack_response    = 1'b0;
                    mon_item.was_reset       = 1'b0;
                    mon_item.ack_error       = 1'b0;
                    mon_item.done            = 1'b0;
                    mon_item.observed_bits.delete();

                    // 2. Wait for o_can_busy to assert
                    while (vif.o_can_busy !== 1'b1 && !vif.i_rst_p) begin
                        @(posedge vif.i_clk);
                    end

                    // 3. Capture serial bitstream on each i_can_bit_tick from SOF until o_can_busy falls
                    while (vif.o_can_busy === 1'b1) begin
                        @(posedge vif.i_clk);

                        if (vif.i_rst_p) begin
                            mon_item.was_reset = 1'b1;
                            break;
                        end

                        if (vif.i_can_bit_tick) begin
                            if (!sof_seen && (vif.o_can_tx === 1'b0))
                                sof_seen = 1'b1;

                            if (sof_seen) begin
                                mon_item.observed_bits.push_back(vif.o_can_tx);
                                if (vif.i_can_rx === 1'b0)
                                    mon_item.ack_response = 1'b1;
                            end
                        end

                        if (vif.o_can_done)
                            mon_item.done = 1'b1;
                        if (vif.o_can_ack_error)
                            mon_item.ack_error = 1'b1;
                    end

                    // 4. Sample final status flags on the edge where o_can_busy drops
                    if (!mon_item.was_reset) begin
                        if (vif.o_can_done)
                            mon_item.done = 1'b1;
                        if (vif.o_can_ack_error)
                            mon_item.ack_error = 1'b1;
                    end

                    `uvm_info("MON", $sformatf("Captured frame: %s", mon_item.convert2string()), UVM_MEDIUM)
                    ap.write(mon_item);
                end
            end
        endtask

    endclass : can_monitor

endpackage : can_monitor_pkg