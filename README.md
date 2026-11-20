# CAN 2.0A Transmitter RTL & UVM Verification

Synthesizable CAN 2.0A (Standard 11-bit ID) Transmitter IP in SystemVerilog with a self-checking UVM verification environment built for Verilator (`uvm-verilator`).

## Repository Structure
- `rtl/` — CAN 2.0A TX RTL modules (`can_tx_top.sv`, `bit_stuffer.sv`, `crc_calc.sv`, `memory.sv`)
- `uvm/` — UVM testbench (`dut_if.sv`, transaction, sequences, driver, monitor, agent, golden-model scoreboard, functional coverage subscriber, environment, tests, and top module)
- `Makefile` & `cov_config.vlt` — Build, regression, waveform, and RTL coverage automation

## Quick Start
1. Clone `uvm-verilator` into the project root:
   ```bash
   git clone [https://github.com/antmicro/uvm-verilator.git](https://github.com/antmicro/uvm-verilator.git)

2. Compile and run the full 30-frame UVM regression:
    ```Bash
    make
3. Run individual directed tests:
    ```Bash
    make test_dlc
    make test_stuffing
    make test_nack
    make test_reset
4. Generate RTL line/toggle HTML coverage (cov_html/index.html):
    ```Bash
    make cov
5. View HTML Coverage & Waveform (GTKWave):
    ```Bash
    make cov_view
    make wave