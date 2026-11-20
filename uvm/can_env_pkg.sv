`timescale 1ns / 1ps

package can_env_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import can_agent_pkg::*;
    import can_scoreboard_pkg::*;
    import can_coverage_pkg::*;

    class can_env extends uvm_env;
        `uvm_component_utils(can_env)

        can_agent       agent;
        can_scoreboard  sb;
        can_coverage    cov;

        function new(string name = "can_env", uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = can_agent::type_id::create("agent", this);
            sb    = can_scoreboard::type_id::create("sb", this);
            cov   = can_coverage::type_id::create("cov",this);
        endfunction

        virtual function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.ap.connect(sb.analysis_export);
            agent.ap.connect(cov.analysis_export);
        endfunction

    endclass : can_env

endpackage : can_env_pkg