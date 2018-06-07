all: compile genchecks verif clean

compile:
	- sandpiper -i warp-v.tlv -o build.sv --html out.html --m4out m4out -p verilog

genchecks:
	python3 ../../checks/genchecks.py

verif:
	$(MAKE) -i -k -C checks 
clean:
	rm build.sv build_gen.sv
