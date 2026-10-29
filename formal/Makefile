# Makefile for WARP-V riscv-formal

SHELL=/bin/bash

export PATH:=$(shell pwd)/env/bin:$(shell pwd)/env:$(PATH)
NPROC?=$(shell nproc)

# The WARP-V configuration to verify. Override on the command line, e.g. "make verif STANDARD_CONFIG=1-stage".
# Each STANDARD_CONFIG requires a corresponding depths/<STANDARD_CONFIG>.cfg.
STANDARD_CONFIG?=4-stage
# Compressed instruction support is incomplete (and fails formal), so it is disabled by default.
EXT_C?=0
# Include debug signals (TL-Verilog-named signals, for viewing traces). These contain forward references to arrays,
# which Yosys 0.39+ rejects, so use DEBUG_SIGS=0 with newer Yosys.
DEBUG_SIGS?=1

# Build tools from source (make_env.sh) only if they are not already available (e.g. from OSS CAD Suite).
ENV_DEP:=$(if $(shell command -v sby),,env)

.PHONY: all clean compile verif results env riscv-formal clean_env tos_agree FORCE

all: verif

# Agree to SandPiper ToS.
tos_agree:
	echo -e "\e[0Ksection_start:`date +%s`:tos-agree[collapsed=true]\r\e[0KAgreeing to sandpiper-saas TOS"
	yes | sandpiper-saas -h > /dev/null
	echo -e "\e[0Ksection_end:`date +%s`:tos-agree\r\e[0K"

# Record the configuration, rewriting out/config only when it changes, so that a configuration change triggers a rebuild.
CONFIG_ID:=STANDARD_CONFIG=$(STANDARD_CONFIG) EXT_C=$(EXT_C) DEBUG_SIGS=$(DEBUG_SIGS)
out/config: FORCE
	@mkdir -p out
	@[[ "$$(cat $@ 2>/dev/null)" == '$(CONFIG_ID)' ]] || echo '$(CONFIG_ID)' > $@

# Run SandPiper-SaaS(TM).
out/warp-v_formal.sv: ../warp-v.tlv out/config
	rm -rf out/warp-v_formal*.sv out/sv_url_inc
	@# Note: Currently "--m5def FORMAL=1" only works as the final args due to https://gitlab.com/rweda/sandpiper-saas/-/issues/2
	@# sandpiper-saas exits successfully even if there are errors, so check its output for errors.
	set -o pipefail; \
	sandpiper-saas -i ../warp-v.tlv -o warp-v_formal.sv --outdir out --sv_url_inc --iArgs $(if $(filter 1,$(DEBUG_SIGS)),--debugSigsGtkwave --debugSigsYosys) \
	   --m5def STANDARD_CONFIG=$(STANDARD_CONFIG) --m5def EXT_C=$(EXT_C) --m5def FORMAL=1 2>&1 | tee out/sandpiper.log
	@if grep -qE '^(Error|ERROR|m4:)' out/sandpiper.log; then echo "Error: SandPiper compilation reported errors (see above)." 1>&2; rm -f $@; exit 1; fi
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
	@mkdir -p out
	@# Claire rejected my pull request to add --basedir option, so we have a local copy of genchecks.py.
	sed "s/\.\.\/\.\./{os.environ.get\('RISCV_FORMAL_RELATIVE_PATH'\)}/" riscv-formal/checks/genchecks.py > out/genchecks.py

# The riscv-formal configuration for this WARP-V configuration.
out/checks.cfg: checks.cfg depths/$(STANDARD_CONFIG).cfg out/config
	cat checks.cfg depths/$(STANDARD_CONFIG).cfg > $@
	if (( $(EXT_C) )); then echo -e '\n[defines]\n`define RISCV_FORMAL_COMPRESSED' >> $@; fi

# Generate the checks (in out/checks).
out/checks/makefile: out/checks.cfg out/genchecks.py out/warp-v_formal.sv riscv-formal/README.md
	@# Should use this, but until Claire accepts pull request, we use a modified genchecks.py in /out.
	@#python3 riscv-formal/checks/genchecks.py --basedir riscv-formal
	cd out && RISCV_FORMAL_RELATIVE_PATH=../riscv-formal PYTHONPATH='$(CURDIR)/env/share/python3' python3 genchecks.py checks

verif: out/checks/makefile $(ENV_DEP)
	echo -e "\e[0Ksection_start:`date +%s`:verif[collapsed=true]\r\e[0KVerification"
	yosys -V
	@# Failing checks are reported by check_results.sh.
	-$(MAKE) -k -C out/checks -j$(NPROC)
	echo -e "\e[0Ksection_end:`date +%s`:verif\r\e[0K"
	./check_results.sh out/checks

# Report results of a previous "make verif".
results:
	./check_results.sh out/checks

clean:
	rm -rf out checks

clean_env: clean
	rm -rf env env_build
