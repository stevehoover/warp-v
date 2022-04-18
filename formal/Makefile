# Makefile for WARP-V riscv-formal

SHELL=/bin/bash

export PATH:=$(shell pwd)/env/bin:$(PATH)

.PHONY: all clean compile verif env riscv-formal


# Agree to SandPiper ToS.
tos_agree:
	yes | sandpiper-saas

# Run SandPiper-SaaS(TM).
out/warp-v_formal.sv: ../warp-v.tlv
	rm -rf out
	mkdir out
	# Note: Currently "--m4def M4_FORMAL=1" only works as the final args due to https://gitlab.com/rweda/sandpiper-saas/-/issues/2
	sandpiper-saas -i ../warp-v.tlv -o warp-v_formal.sv --outdir out --sv_url_inc --iArgs --debugSigsGtkwave --debugSigsYosys --m4def M4_FORMAL=1
	
env: env/PASSED

# Use env/PASSED to indicate that the environment has been successfully built.
env/PASSED:
	@# Just update timestamp if that's all that's needed, or make_env.sh.
	if [ -e env/PASSED ]; then touch env/PASSED; else ./make_env.sh; fi

riscv-formal: riscv-formal/README.md

# Use riscv-formal/README.md to indicate that the git submodules have been installed.
riscv-formal/README.md:
	@# Just update timestamp if that's all that's needed, or install git submodules.
	if [ -e riscv-formal/README.md ]; then touch riscv-formal/README.md; else git submodule init; git submodule update; fi

compile: out/warp-v_formal.sv

verif: checks.cfg out/warp-v_formal.sv env riscv-formal
	@# Should use this, but until Clifford accepts pull request, we have a local copy of genchecks.py.
	@#python3 riscv-formal/checks/genchecks.py --basedir riscv-formal
	bison --version
	python3 $(CURDIR)/riscv-formal/checks/genchecks.py checks $(CURDIR)/riscv-formal
	$(MAKE) -k -C checks -j$$(nproc)

all: verif

clean:
	rm -rf out checks
