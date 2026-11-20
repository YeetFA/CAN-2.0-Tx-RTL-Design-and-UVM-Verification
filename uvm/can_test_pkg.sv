`timescale 1ns / 1ps

package can_test_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import can_txn_pkg::*;
    import can_seq_pkg::*;
    import can_agent_pkg::*;
    import can_env_pkg::*;

    // -------------------------------------------------------------------------
    // Base Test
    // -------------------------------------------------------------------------
    class can_base_test extends uvm_test;
        `uvm_component_utils(can_base_test)

        can_env env;

        function new(string name = "can_base_test", uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = can_env::type_id::create("env", this);
        endfunction

        virtual function void end_of_elaboration_phase(uvm_phase phase);
            super.end_of_elaboration_phase(phase);
            uvm_root::get().print_topology();        
        endfunction

        virtual task run_phase(uvm_phase phase);
            can_full_seq seq;
            phase.raise_objection(this);
            seq = can_full_seq::type_id::create("seq");
            seq.start(env.agent.seqr);
            #200ns;
            phase.drop_objection(this);
        endtask
    endclass : can_base_test

    // -------------------------------------------------------------------------
    // Individual Scenario Tests (for Makefile +UVM_TESTNAME targets)
    // -------------------------------------------------------------------------
    class can_dlc_test extends can_base_test;
        `uvm_component_utils(can_dlc_test)
        function new(string name = "can_dlc_test", uvm_component parent);
            super.new(name, parent);
        endfunction
        virtual task run_phase(uvm_phase phase);
            can_dlc_sweep_seq seq;
            phase.raise_objection(this);
            seq = can_dlc_sweep_seq::type_id::create("seq");
            seq.start(env.agent.seqr);
            #200ns;
            phase.drop_objection(this);
        endtask
    endclass : can_dlc_test

    class can_stuffing_test extends can_base_test;
        `uvm_component_utils(can_stuffing_test)
        function new(string name = "can_stuffing_test", uvm_component parent);
            super.new(name, parent);
        endfunction
        virtual task run_phase(uvm_phase phase);
            can_stuffing_seq seq;
            phase.raise_objection(this);
            seq = can_stuffing_seq::type_id::create("seq");
            seq.start(env.agent.seqr);
            #200ns;
            phase.drop_objection(this);
        endtask
    endclass : can_stuffing_test

    class can_nack_test extends can_base_test;
        `uvm_component_utils(can_nack_test)
        function new(string name = "can_nack_test", uvm_component parent);
            super.new(name, parent);
        endfunction
        virtual task run_phase(uvm_phase phase);
            can_nack_seq seq;
            phase.raise_objection(this);
            seq = can_nack_seq::type_id::create("seq");
            seq.start(env.agent.seqr);
            #200ns;
            phase.drop_objection(this);
        endtask
    endclass : can_nack_test

    class can_reset_test extends can_base_test;
        `uvm_component_utils(can_reset_test)
        function new(string name = "can_reset_test", uvm_component parent);
            super.new(name, parent);
        endfunction
        virtual task run_phase(uvm_phase phase);
            can_reset_seq seq;
            phase.raise_objection(this);
            seq = can_reset_seq::type_id::create("seq");
            seq.start(env.agent.seqr);
            #200ns;
            phase.drop_objection(this);
        endtask
    endclass : can_reset_test

    class can_full_test extends can_base_test;
        `uvm_component_utils(can_full_test)
        function new(string name = "can_full_test", uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass : can_full_test

endpackage : can_test_pkg