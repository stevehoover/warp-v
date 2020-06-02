# RISC-V M-Extension Files

* In this directory, multiplication and divide modules from [picorv32](https://github.com/cliffordwolf/picorv32) are inherited with necessary changes.
* `picorv32_div_opt.sv` and `picorv32_pcpi_fast_mul.sv` are imported in WARP-V.
* `div_opt_testbench.tlv` is to test division module independently.
* `mul_opt_testbench.tlv` is to test multiplication module independently.
* `muldiv_tlv_macro.tlv` is the macro code to be used as is in WARP-V as is and can also be used to test both modules in one file.
