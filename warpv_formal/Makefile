all: compile genchecks verif clean

compile:
	rm -rf sp_obj
	# Invoke SandPiper. Need to provide input path reaching up the hierarchy to permit file inclusion in warp-v repo.
	sandpiper -i ../../../riscv-formal/cores/warpv_formal/warp-v_formal.tlv -o build.sv --obj sp_obj -p verilog

genchecks:
	python3 ../../checks/genchecks.py

verif:
	$(MAKE) -k -C checks -j4
clean:
#	rm build.sv build_gen.sv
