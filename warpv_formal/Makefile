all: compile genchecks verif clean

compile:
	rm -rf sp_obj
	sandpiper -i ../../../riscv-formal/cores/warpv_formal/warp-v_formal.tlv -o build.sv --obj sp_obj -p verilog

genchecks:
	python3 ../../checks/genchecks.py

verif:
	$(MAKE) -i -k -C checks -j4
clean:
#	rm build.sv build_gen.sv
