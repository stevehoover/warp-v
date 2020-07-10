# RISC-V F-Extension Files

* This directory contains the copy of	Berkeley's HardFloat Floating-Point verilog modules by John Hauser, which are neccesary for performing Floating-point operations in Warp-V.
* The verilog module are inherited from "http://www.jhauser.us/arithmetic/HardFloat.html" with source files in [HardFloat-1.zip](http://www.jhauser.us/arithmetic/HardFloat-1.zip)   with RISC-V variant.
* `topmodule.tlv` contains TL-Verilog marcos which is inheriting/calling the Hardfloat modules in TL-V context.
* `hardfloat_verilog` contains the actual verilog modules
