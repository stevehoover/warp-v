# Makefile for WARP-V simulation
# TODO: Hacked-together and incomplete.

SHELL=/bin/bash

.PHONY: all clean compile verif


# Run SandPiper Cloud Edition(TM) (SandPiper(TM) in the cloud for open-source code).
out/%/top.sv: %.tlv ../warp-v.tlv
	rm -rf out
	curl -F 'top.tlv=@$<' -F 'files[]=@../warp-v.tlv' http://saas.makerchip.com/sandpiper | tar -zx && cat out/stdout
	exit `cat out/$*/status`

# TODO: verilator command is assumed to exist.
out/%/sim.log: out/%.sv
	verilator +incdir+../formal/verilog +incdir+../formal/verilog/proj_default $< ../formal/verilog/clk_gate.v

all: verif

clean:
	rm -rf out


out/sim/%/status: out/%/status
	verilator +incdir+
	

default: show_config go_default

.PHONY: default go_default go_debug go_valgrind show_config prep prep_dbg compile run

# This must point to the root of the VERILATOR kit
VERILATOR_ROOT := /usr/local/share/verilator
#export VERILATOR_ROOT
# VERILATOR := $(VERILATOR_ROOT)/bin/verilator
VERILATOR := verilator
#SP_REPO := /var/www/SandPiper_dev

# Pick up PERL and other variable settings
include $(VERILATOR_ROOT)/include/verilated.mk

DEBUG_QUIET = --debug --debugi 0 --gdbbt --no-dump-tree
DEBUG_ON = --debug --trace-dups --gdbbt

##############################################################

SRC_DIR = .
LIB_DIR = $(SP_REPO)/webserver/lib
export LIB_DIR

##############################################################
go_default:   prep     compile run
go_debug:     prep_dbg compile run

VERILATOR_FLAGS = --cc +librescan +libext+.sv --top-module makerchip -y $(SRC_DIR) -y $(SP_REPO)/verilog -y $(SP_REPO)/verilog/sandhost -y $(SP_REPO)/verilog/proj_default -y $(LIB_DIR) +incdir+$(SRC_DIR) +incdir+$(SRC_DIR)/sv_url_inc +incdir+$(SP_REPO)/verilog +incdir+$(SP_REPO)/verilog/sandhost +incdir+$(SP_REPO)/verilog/proj_default +incdir+$(LIB_DIR) makerchip.sv
VERILATOR_FLAGS += --assert --trace

#prep: Is the very first time we're running a Verilation
#so we make sure to run with --gdbbt, so if it dumps we'll get a trace.
prep:
        $(VERILATOR) $(DEBUG_QUIET) $(VERILATOR_FLAGS)
prep_dbg:
        $(VERILATOR) $(DEBUG_ON)    $(VERILATOR_FLAGS)

compile: lib
        cd obj_dir ; cp $(LIB_DIR)/sim_main.cpp . ; $(MAKE) -j 3 -f $(LIB_DIR)/Makefile_obj

run:
        obj_dir/simx +verilator+error+limit+100

######################################################################

obj_dir:
        mkdir $@

######################################################################

maintainer-copy::
clean mostlyclean distclean maintainer-clean::
        -rm -rf obj_dir *.log *.dmp *.vpd core
