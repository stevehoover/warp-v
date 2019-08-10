# Makefile for WARP-V implementations.

SHELL=/bin/bash

.PHONY: all clean

all: verilog/warp-v_5-stage.sv verilog/warp-v_5-stage_retime.sv

# Run SandPiper Cloud Edition(TM) (SandPiper(TM) in the cloud for open-source code).
verilog/warp-v_%.sv: warp-v_%.tlv ../warp-v.tlv
	rm -rf out
	mkdir -p verilog
	curl -F 'top.tlv=@$<' -F 'files[]=@../warp-v.tlv' http://saas.makerchip.com/sandpiper | tar -zx && cat out/stdout
	exit `cat out/status`
	cp out/warp-v_*.sv verilog
	# HACKS: These fix bugs in the generated code.
	sed -i 's/wire\( \[[^\[]\+\] L1_Mem_Value_\)/reg\1/' $@
	sed -i 's/wire\( \[[^\[]\+\] FETCH_Instr_Regs_vae_\)/reg\1/' $(patsubst %.sv,%_gen.sv,$@)
clean:
	rm -rf out verilog

#FETCH_Instr_Regs_value_a0
