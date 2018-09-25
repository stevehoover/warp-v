# Makefile for WARP-V riscv-formal

export PATH:=$(shell pwd)/env/bin:$(PATH)

.PHONY: all compile verif

compile: build.sv

build.sv: warp-v_formal.tlv
	rm -rf sp_obj
	@# Invoke SandPiper. Need to provide input path reaching up the hierarchy to permit higher-level file inclusion.
	sandpiper -i ../formal/warp-v_formal.tlv -o build.sv --obj sp_obj -p verilog

verif: checks.cfg genchecks.py build.sv
	@#python3 riscv-formal/checks/genchecks.py --basedir ../riscv-formal
	python3 ./genchecks.py --basedir ./riscv-formal
	$(MAKE) -k -C checks -j$$(nproc)

all: verif

clean:
	rm build.sv build_gen.sv
	rm -rf sp_obj
