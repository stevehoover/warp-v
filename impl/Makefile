# Makefile for WARP-V implementations.

SHELL=/bin/bash

.PHONY: all clean

all: verilog/warp-v_5-stage.sv

# Run SandPiper Cloud Edition(TM) (SandPiper(TM) in the cloud for open-source code).
verilog/warp-v_5-stage.sv verilog/warp-v_5-stage_gen.sv: warp-v_5-stage.tlv
	rm -rf out
	mkdir -p verilog
	curl -F 'warp-v_5-stage.tlv=@warp-v_5-stage.tlv' -F 'warp-v.tlv=@../warp-v.tlv' http://localhost:8888/sandpiper | tar -zx && cat out/stdout
	exit `cat out/status`
	mv out/warp-v_5-stage*.sv verilog
	# HACKS: These fix bugs in the generated code.
	sed -i 's/wire( \[[^\[]\] L1_Mem_Value_)/reg$1/' out/warp-v_5-stage.sv

clean:
	rm -rf out verilog
