`timescale 1ns / 1ps

package can_agent_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import can_txn_pkg::*;
    import can_driver_pkg::*;
    import can_monitor_pkg::*;

    typedef uvm_sequencer #(can_seq_item) can_sequencer;

    class can_agent extends uvm_agent;
        `uvm_component_utils(can_agent)

        can_driver    drv;
        can_monitor   mon;
        can_sequencer seqr;

        uvm_analysis_port #(can_seq_item) ap;

        function new(string name = "can_agent", uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);

            mon = can_monitor::type_id::create("mon", this);

            if (get_is_active() == UVM_ACTIVE) begin
                drv  = can_driver::type_id::create("drv", this);
                seqr = can_sequencer::type_id::create("seqr", this);
            end
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);

            // Forward monitor's analysis port to the agent boundary
            ap = mon.ap;

            if (get_is_active() == UVM_ACTIVE) begin
                drv.seq_item_port.connect(seqr.seq_item_export);
            end
        endfunction

    endclass : can_agent

endpackage : can_agent_pkg