# ==============================================================================
# CAN 2.0A Transmitter UVM Verification Makefile (Verilator + UVM-Verilator)
# ==============================================================================

VERILATOR   = verilator
TOP_MODULE  = can_tb_top
OBJ_DIR     = obj_dir
SIM_BIN     = $(OBJ_DIR)/V$(TOP_MODULE)
VCD_FILE    = can_uvm.vcd

COV_DIR     = logs
COV_DAT     = $(COV_DIR)/coverage.dat
COV_INFO    = $(COV_DIR)/coverage.info
RTL_INFO    = $(COV_DIR)/rtl_coverage.info
COV_HTML    = cov_html
COV_ANNOT   = $(COV_DIR)/annotated

UVM_HOME    = ./uvm-verilator/src
UVM_PKG     = $(UVM_HOME)/uvm_pkg.sv

# Default test & verbosity (override from CLI: make run TEST=can_dlc_test)
TEST        ?= can_full_test
VERBOSITY   ?= UVM_MEDIUM
EXTRA_ARGS  ?=

# Suppress harmless UVM_NO_DPI component regex name-check warnings
UVM_FLAGS   = +UVM_TESTNAME=$(TEST) \
              +UVM_VERBOSITY=$(VERBOSITY) \
              +uvm_set_severity=reporter,UVM/COMP/NAME,UVM_WARNING,UVM_NONE \
              $(EXTRA_ARGS)

# Base Verilator compile flags
VFLAGS      = --binary -j 0 --timing --trace --trace-structs -DUVM_NO_DPI \
              -Wno-WIDTHTRUNC -Wno-WIDTHEXPAND -Wno-IGNOREDRETURN \
              -Wno-CONSTRAINTIGN -Wno-TIMESCALEMOD \
              +incdir+$(UVM_HOME) \
              --top-module $(TOP_MODULE)

# RTL source files
RTL_SRCS    = rtl/memory.sv \
              rtl/crc_calc.sv \
              rtl/bit_stuffer.sv \
              rtl/can_tx_top.sv

# UVM testbench files (strict package dependency order)
UVM_SRCS    = uvm/dut_if.sv \
              uvm/can_txn_pkg.sv \
              uvm/can_seq_pkg.sv \
              uvm/can_driver_pkg.sv \
              uvm/can_mon_pkg.sv \
              uvm/can_agent_pkg.sv \
              uvm/can_scoreboard_pkg.sv \
              uvm/can_coverage_pkg.sv \
              uvm/can_env_pkg.sv \
              uvm/can_test_pkg.sv \
              uvm/can_tb_top.sv

# ==============================================================================
# Primary Targets
# ==============================================================================
.PHONY: all compile run test_full test_dlc test_stuffing test_nack test_reset cov cov_text cov_view wave clean help

all: compile run

compile: $(SIM_BIN)

$(SIM_BIN): $(RTL_SRCS) $(UVM_SRCS)
	$(VERILATOR) $(VFLAGS) $(UVM_PKG) $(RTL_SRCS) $(UVM_SRCS)

run: $(SIM_BIN)
	./$(SIM_BIN) $(UVM_FLAGS)

# ==============================================================================
# Individual UVM Test Targets
# ==============================================================================
test_full: $(SIM_BIN)
	$(MAKE) run TEST=can_full_test

test_dlc: $(SIM_BIN)
	$(MAKE) run TEST=can_dlc_test

test_stuffing: $(SIM_BIN)
	$(MAKE) run TEST=can_stuffing_test

test_nack: $(SIM_BIN)
	$(MAKE) run TEST=can_nack_test

test_reset: $(SIM_BIN)
	$(MAKE) run TEST=can_reset_test

# ==============================================================================
# Code & Functional Coverage Targets
# ==============================================================================
cov:
	rm -rf $(OBJ_DIR) $(COV_DIR) $(COV_HTML)
	mkdir -p $(COV_DIR)
	$(VERILATOR) $(VFLAGS) cov_config.vlt --coverage $(UVM_PKG) $(RTL_SRCS) $(UVM_SRCS)
	./$(SIM_BIN) $(UVM_FLAGS) +UVM_TESTNAME=can_full_test +verilator+coverage+file+$(COV_DAT)
	verilator_coverage --write-info $(COV_INFO) $(COV_DAT)
	lcov --extract $(COV_INFO) "rtl/*" -o $(RTL_INFO) --ignore-errors empty,source
	genhtml $(RTL_INFO) --output-directory $(COV_HTML) --ignore-errors source
	@echo "============================================================"
	@echo "  HTML coverage report ready: $(COV_HTML)/index.html"
	@echo "============================================================"

cov_text:
	verilator_coverage --annotate $(COV_ANNOT) $(COV_DAT)
	@echo "Annotated RTL source files written to $(COV_ANNOT)/"

cov_view:
	explorer.exe "$$(wslpath -w $(COV_HTML)/index.html)"

# ==============================================================================
# Waveform & Cleanup
# ==============================================================================
wave:
	gtkwave $(VCD_FILE) &

clean:
	rm -rf $(OBJ_DIR) $(VCD_FILE) $(COV_DIR) $(COV_HTML)

help:
	@echo "Available targets:"
	@echo "  make compile        - Build standard Verilator UVM binary"
	@echo "  make run            - Run default test (TEST=$(TEST))"
	@echo "  make test_full      - Run full regression (can_full_test)"
	@echo "  make test_dlc       - Run DLC sweep & clamping test (can_dlc_test)"
	@echo "  make test_stuffing  - Run bit stuffing stress test (can_stuffing_test)"
	@echo "  make test_nack      - Run NACK error abort test (can_nack_test)"
	@echo "  make test_reset     - Run mid-frame reset & recovery test (can_reset_test)"
	@echo "  make cov            - Rebuild with --coverage, run regression, build HTML report"
	@echo "  make cov_text       - Generate annotated line-by-line RTL files in logs/annotated/"
	@echo "  make cov_view       - Run 'make cov' and open cov_html/index.html in Windows browser"
	@echo "  make wave           - Open $(VCD_FILE) in GTKWave"
	@echo "  make clean          - Remove $(OBJ_DIR), $(VCD_FILE), $(COV_DIR), and $(COV_HTML)"