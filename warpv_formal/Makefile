all: compile genchecks verif clean

compile:
	- sandpiper -i ../../../riscv-formal/cores/warpv_formal/warp-v_formal.tlv -o build.sv --m4out m4out -p verilog

genchecks:
	python3 ../../checks/genchecks.py

verif:
	$(MAKE) -i -k -C checks -j4
clean:
#	rm build.sv build_gen.sv
