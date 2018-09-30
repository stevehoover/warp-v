# Makefile for WARP-V riscv-formal

SHELL=/bin/bash

export PATH:=$(shell pwd)/env/bin:$(PATH)

.PHONY: all compile verif env riscv-formal

env: env/PASSED

# Use env/PASSED to indicate that the environment has been successfully built.
env/PASSED:
	@# Just update timestamp if that's all that's needed, or make_env.sh.
	if [ -e env/PASSED ]; then touch env/PASSED; else ./make_env.sh; fi

riscv-formal: riscv-formal/README.md

# Use riscv-formal to indicate that the git submodules have been installed.
riscv-formal/README.md:
	@# Just update timestamp if that's all that's needed, or install git submodules.
	if [ -e riscv-formal/README.md ]; then touch riscv-formal/README.md; else git submodule init; git submodule update; fi

compile: build.sv

build.sv:
	rm -rf sp_obj
	@# Invoke SandPiper. Need to provide input path reaching up the hierarchy to permit higher-level file inclusion.
	sandpiper -i ../formal/warp-v_formal.tlv -o build.sv --obj sp_obj -p verilog

verif: build.sv env riscv-formal
	@# Should use this, but until Clifford accepts pull request, we have a local copy of genchecks.py.
	@#python3 riscv-formal/checks/genchecks.py --basedir ../riscv-formal
	python3 ./genchecks.py --basedir ./riscv-formal
	$(MAKE) -k -C checks -j$$(nproc)

all: verif

clean:
	rm build.sv build_gen.sv
	rm -rf sp_obj
