\m5_TLV_version 1d: tl-x.org
\SV
   // Local test harness for the crt0 / entry-point mechanism (m5_assemble's positional Entry arg).
   // Includes the LOCAL warp-v.tlv (which, with var(local, 1), pulls the LOCAL risc-v_defs.tlv).
   // Provide warp-v.tlv and risc-v_defs.tlv as additionalFiles when compiling in Makerchip.
   //
   // The crt0 preamble inits sp, `call`s the named Entry, and maps its a0 return to pass/fail
   // (0 => pass). Switch PROG_NAME to `crt0test_fortran` to exercise a non-`main` entry name
   // (Fortran's `MAIN__`), proving the mechanism is entry-name-agnostic, matching what the CE pane
   // now detects and sends per language.
   m4_include_lib(['./warp-v.tlv'])
\m5
   var(VIZ, 1)
   / Select the test program: `crt0test` (C-style `main`), `crt0test_fortran` (`MAIN__`), or
   / `crt0test_fortran_runtime` (gfortran C-ABI `main` + runtime shim, STOP-based pass/fail).
   var(PROG_NAME, crt0test)
   / Simulated CE source-VIZ metadata for the main() program below (base64 JSON). Only meaningful
   / for the `crt0test` (C) program; harmless when running the Fortran variant.
   var(ce_source_viz_data, ['eyJzb3VyY2VfY29kZSI6ImludCBtYWluKCkge1xuICBpbnQgc3VtID0gMDtcbiAgaW50IGk7XG4gIGZvciAoaSA9IDE7IGkgPCAxMDsgaSsrKSB7XG4gICAgc3VtICs9IGk7XG4gIH1cbiAgcmV0dXJuIHN1bSAtIDQ1O1xufSIsImFzbV9saW5lcyI6WyJBRERJIGEwLCB6ZXJvLCAwIiwiQURESSB0MCwgemVybywgMSIsIkFEREkgdDEsIHplcm8sIDEwIiwiQUREIGEwLCBhMCwgdDAiLCJBRERJIHQwLCB0MCwgMSIsIkJMVCB0MCwgdDEsIGxvb3AiLCJBRERJIHQyLCB6ZXJvLCA0NSIsIlNVQiBhMCwgYTAsIHQyIiwiUkVUIl0sImFzbV9saW5lX3RvX3NvdXJjZV9saW5lIjpbMiw0LDQsNSw0LDQsNyw3LDhdfQ=='])
   / C-style program: a main() assembled with a positional Entry symbol -> crt0 preamble prepended.
   TLV_fn(riscv_crt0test_prog, {
      ~assemble(['
         # main() computing sum(1..9) - 45 == 0, returned in a0 (0 => pass).
         main:
            ADDI a0, zero, 0       # sum = 0
            ADDI t0, zero, 1       # i = 1
            ADDI t1, zero, 10      # ten = 10
         loop:
            ADD a0, a0, t0         # sum += i
            ADDI t0, t0, 1         # i++
            BLT t0, t1, loop       # if i < 10 goto loop
            ADDI t2, zero, 45      # t2 = 45
            SUB a0, a0, t2         # a0 = sum - 45
            ret                    # return a0
      '], main)
   })
   / Fortran-style program: same computation, but the entry unit is named `MAIN__` (as gfortran emits).
   / Verifies crt0 `call`s whatever Entry symbol it is given, not a hard-coded `main`.
   TLV_fn(riscv_crt0test_fortran_prog, {
      ~assemble(['
         # MAIN__() computing sum(1..9) - 45 == 0, returned in a0 (0 => pass).
         MAIN__:
            ADDI a0, zero, 0
            ADDI t0, zero, 1
            ADDI t1, zero, 10
         loop:
            ADD a0, a0, t0
            ADDI t0, t0, 1
            BLT t0, t1, loop
            ADDI t2, zero, 45
            SUB a0, a0, t2
            ret
      '], MAIN__)
   })

   / Fortran runtime-shim test: enters at the gfortran-style C-ABI `main` wrapper (made bare-metal-safe
   / by the shim's stubbed `_gfortran_set_args`/`_gfortran_set_options`), which calls the void `MAIN__`.
   / MAIN__ computes sum(1..9)-45 and `STOP`s that value via `_gfortran_stop_numeric` (0 => pass).
   / Assembled with Entry=main, Runtime=fortran, so m5_assemble injects `runtime_shim_fortran`.
   TLV_fn(riscv_crt0test_fortran_runtime_prog, {
      ~assemble(['
         main:                         # gfortran C-ABI wrapper
            call _gfortran_set_args    #   no-op via shim
            call _gfortran_set_options #   no-op via shim
            call MAIN__                #   run the Fortran program unit
            li a0, 0                   #   normal completion returns 0
            ret
         MAIN__:                       # void Fortran program unit
            ADDI a0, zero, 0
            ADDI t0, zero, 1
            ADDI t1, zero, 10
         loop:
            ADD a0, a0, t0
            ADDI t0, t0, 1
            BLT t0, t1, loop
            ADDI t2, zero, 45
            SUB a0, a0, t2             #   a0 = sum(1..9) - 45 = 0
            call _gfortran_stop_numeric  # STOP a0  (0 => pass via shim)
      '], main, fortran)
   })

// The top module.
m4+module_def()
\TLV
   m5+warpv_top()
\SV
   endmodule
