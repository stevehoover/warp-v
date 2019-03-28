
This directory contains files used for exploring the implementation of WARP-V, including:
  - `top.v`: A single-file extraction of the WARP-V code. [Download](https://raw.githubusercontent.com/stevehoover/warp-v/master/impl/top.v).
    <a href="http://www.makerchip.com/sandbox?code_url=https:%2F%2Fraw.githubusercontent.com%2Fstevehoover%2Fwarp-v%2Fmaster%2Fimpl%2Ftop.v" target="_blank">Open in Makerchip</a>.
    It was created using `-noline -p verilog`, and included files were inlined manually. There is no automation to reproduce/update.
  
  
    There is error at line 2626 in `top.v` file which says "Procedural assignment to non-register `L1_Mem_Value_a3` is not permitted, left-hand side should be reg/integer/time/genvar". So the declaration of `L1_Mem_Value_a3` is changed from `wire` to `reg` at line 2608.
    There is error at line 2654 in `top.v` file which says "Procedural assignment to non-register `FETCH_Instr_Regs_value_a3` is not permitted, left-hand side should be reg/integer/time/genvar". So the declaration of `FETCH_Instr_Regs_value_a3` is changed from `wire` to `reg` at line 988.
    Verilator *pragmas*`/* verilator lint_save */ /* verilator lint_off UNOPTFLAT */ bit [256:0] RW_rand_raw; bit [256+63:0] RW_rand_vect; pseudo_rand #(.WIDTH(257)) pseudo_rand (clk, reset, RW_rand_raw[256:0]); assign RW_rand_vect[256+63:0] = {RW_rand_raw[62:0], RW_rand_raw}; /* verilator lint_restore */ /* verilator lint_off WIDTH */ /* verilator lint_off UNOPTFLAT */` which is in the last part of line 109 is commented (eliminated). As this line is from an m4 macro that provides a pseudo random string of bits used by the m4_rand macro, which is not used for synthesis and analysis purposes in software like Vivado, also it gives an error which says "module 'pseudo_rand' not found" so the code can be eliminated. But to keep this line unchanged, `psuedo_rand` has to be defined.
