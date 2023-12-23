# Makefile for WARP-V riscv-formal

SHELL=/bin/bash

export PATH:=$(shell pwd)/env/bin:$(shell pwd)/env:$(PATH)
NPROC?=$(shell nproc)

.PHONY: all clean compile verif env riscv-formal clean_env


# Agree to SandPiper ToS.
tos_agree:
	echo -e "\e[0Ksection_start:`date +%s`:tos-agree[collapsed=true]\r\e[0KAgreeing to sandpiper-saas TOS"
	yes | sandpiper-saas -h > /dev/null
	echo -e "\e[0Ksection_end:`date +%s`:tos-agree\r\e[0K"

# Run SandPiper-SaaS(TM).
out/warp-v_formal.sv: ../warp-v.tlv
	rm -rf out
	mkdir out
	@# Note: Currently "--m5def FORMAL=1" only works as the final args due to https://gitlab.com/rweda/sandpiper-saas/-/issues/2
	sandpiper-saas -i ../warp-v.tlv -o warp-v_formal.sv --outdir out --sv_url_inc --iArgs --debugSigsGtkwave --debugSigsYosys --m5def FORMAL=1
	#/home/steve/repos/mono/sandpiper/bin/sandpiper -i ../warp-v.tlv -o warp-v_formal.sv --outdir out --m5out out/warp-v_formal.m5out.tlv --iArgs --debugSigsGtkwave --debugSigsYosys --m5def FORMAL=1

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

out/genchecks.py: riscv-formal/checks/genchecks.py
	@# Claire rejected my pull request to add --basedir option, so we have a local copy of genchecks.py.
	sed "s/\.\.\/\.\./{os.environ.get\('RISCV_FORMAL_RELATIVE_PATH'\)}/" riscv-formal/checks/genchecks.py > out/genchecks.py

verif: checks.cfg out/warp-v_formal.sv out/genchecks.py env riscv-formal
	@# Should use this, but until Claire accepts pull request, we make a modified genchecks.py in /out.
	@#python3 riscv-formal/checks/genchecks.py --basedir riscv-formal
	echo -e "\e[0Ksection_start:`date +%s`:verif[collapsed=true]\r\e[0KVerification"
	yosys -V
	bison --version
	RISCV_FORMAL_RELATIVE_PATH=riscv-formal PYTHONPATH='$(CURDIR)/env/share/python3' python3 '$(CURDIR)/out/genchecks.py'

	$(MAKE) -k -C checks -j$(NPROC)
	echo -e "\e[0Ksection_end:`date +%s`:verif\r\e[0K"

all: verif

clean:
	rm -rf out checks

clean_env: clean
	rm -rf env env_build
	