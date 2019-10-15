# Makefile for WARP-V implementations.

SHELL=/bin/bash

.PHONY: all clean

WARPV_TLV=$(shell ls warp-v_*.tlv)
WARPV_OUT=$(patsubst warp-v_%.tlv,out/%/status,$(WARPV_TLV))

all: $(WARPV_OUT)

# Run SandPiper Cloud Edition(TM) (SandPiper(TM) in the cloud for open-source code).
out/%/status: warp-v_%.tlv ../warp-v.tlv
	@echo "Processing $< using SandPiper(TM) SaaS Edition."
	@mkdir -p out/$(patsubst warp-v_%.tlv,%,$<)
	@cd out/$(patsubst warp-v_%.tlv,%,$<) \
	  && cp ../../$< . \
	  && curl -F 'top.tlv=@$<' -F 'files[]=@../../../warp-v.tlv' http://saas.makerchip.com/sandpiper | tar -zx && cat out/stdout \
		&& mv out/* . && rmdir out \
		&& (exit `cat status`) \
	  && sed -i 's/wire\( \[[^\[]\+\] L1_Mem_Value_\)/reg\1/' $(patsubst warp-v_%.tlv,warp-v_%.sv,$<) \
	  && sed -i 's/wire\( \[[^\[]\+\] FETCH_Instr_Regs_vae_\)/reg\1/' $(patsubst %.tlv,%_gen.sv,$<)
	@# Above sed HACKS fix bugs in the generated code.

impl:
	vivado -mode tcl -source fpga_impl/impl.tcl 

impl_gui:
	 vivado -source fpga_impl/impl.tcl 

clean: clean_compile clean_impl

clean_compile:
	rm -rf out

clean_impl:
	find . -type f -iname \*.rpt -delete  
	find . -type f -iname \*.dcp -delete 
	find . -type f -iname \*.log -delete
	find . -type f -iname \*.str -delete
	find . -type f -iname \*.jou -delete
	rm fpga_impl/fpga_impl.xdc fpga_impl/fpga_impl_netlist.v
#FETCH_Instr_Regs_value_a0
