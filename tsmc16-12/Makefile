# Makefile for WARP-V implementations.

SHELL=/bin/bash

.PHONY: all clean

WARPV_TLV=$(shell ls warp-v_*.tlv)
WARPV_OUT=$(patsubst warp-v_%.tlv,out/%/status,$(WARPV_TLV))

all: $(WARPV_OUT)

# Run SandPiper Cloud Edition(TM) (SandPiper(TM) in the cloud for open-source code).
out/%/status: warp-v_%.tlv ../warp-v.tlv
	yes | sandpiper -i $< -f ../warp-v.tlv -o warp-v_$(patsubst warp-v_%.tlv,%,$<).sv --outdir out --sv_url_inc --iArgs

impl:
	#vivado -mode tcl -source Vivado/impl.tcl 

impl_gui:
	 #vivado -source Vivado/impl.tcl 

clean: clean_compile clean_impl

clean_compile:
	rm -rf out

clean_impl:
	#rm -rf Vivado/out
	#find . -type f -iname \*.rpt -delete  
	#find . -type f -iname \*.dcp -delete 
	#find . -type f -iname \*.log -delete
	#find . -type f -iname \*.str -delete
	#find . -type f -iname \*.jou -delete
	#rm viv\*
#FETCH_Instr_Regs_value_a0
