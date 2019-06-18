# Makefile for WARP-V implementations.

SHELL=/bin/bash

.PHONY: all clean

all: verilog/warp-v_5-stage.sv

# Run SandPiper Cloud Edition(TM) (SandPiper(TM) in the cloud for open-source code).
verilog/warp-v_5-stage.sv verilog/warp-v_5-stage_gen.sv: warp-v_5-stage.tlv
	rm -rf out
	mkdir -p verilog
	curl -F 'top.tlv=@warp-v_5-stage.tlv' -F 'files[]=@../warp-v.tlv' http://saas.makerchip.com/sandpiper | tar -zx && cat out/stdout
	exit `cat out/status`
	cp out/warp-v_5-stage*.sv verilog
	# HACKS: These fix bugs in the generated code.
	sed -i 's/wire\( \[[^\[]\+\] L1_Mem_Value_\)/reg\1/' verilog/warp-v_5-stage.sv
clean:
	rm -rf out verilog
