\m5_TLV_version 1d: tl-x.org
\SV
   // An illustration of WARP-V with custom instructions.

   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/warp-v/2652a1c33bcc4640f94063d6f1d5be6da6f28f88/warp-v.tlv'])
\m5
   / A test program.
   var(PROG_NAME, my_custom)
   TLV_fn(riscv_my_custom_prog, {
      ~assemble(['
         # /=====================\
         # | Count to 10 Program |
         # \=====================/
         #
         # Default program for RV32I test
         # Add 1,2,3,...,9 (in that order).
         # Store incremental results in memory locations 0..9. (1, 3, 6, 10, ...)
         #
         # Regs:
         # t1: cnt
         # t2: ten
         # t3: out
         # t4: tmp
         # t5: offset
         # t6: store addr
         reset:
            ORI t6, zero, 0          #     store_addr = 0
            ORI t1, zero, 1          #     cnt = 1
            ORI t2, zero, 10         #     ten = 10
            ORI t3, zero, 0          #     out = 0
         loop:
            BADD t3, t1, t3          #  -> out += cnt
            SW t3, 0(t6)             #     store out at store_addr
            BADDI t1, t1, 1          #     cnt ++
            ADDI t6, t6, 4           #     store_addr++
            BLT t1, t2, loop         #  ^- branch back if cnt < 10
         # Result should be 0x2d.
            LW t4, -4(t6)            #     load the final value into tmp
            ADDI t5, zero, 0x2d      #     expected result (0x2d)
            BEQ t4, t5, pass         #     pass if as expected
         
            # Branch to one of these to report pass/fail to the default testbench.
         fail:
            ADD t5, t5, zero         #     nop fail
         pass:
            ADD t4, t4, zero         #     nop pass
         
      '])
   })
   
// The top module.
m4+module_def()
\TLV
   m5+warpv_with_custom_instructions(
      ['R, 32, I, 01110, 000, 0000000, BADD'],
      ['I, 32, I, 00110, 000, BADDI'],
      \TLV
         $badd_rslt[31:0]  = {24'b0, /src[1]$reg_value[7:0] + /src[2]$reg_value[7:0]};
         $baddi_rslt[31:0] = {24'b0, /src[1]$reg_value[7:0] + $raw_i_imm[7:0]};
      )
\SV
   endmodule
