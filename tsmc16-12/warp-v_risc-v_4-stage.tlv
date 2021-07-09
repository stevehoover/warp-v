\m4_TLV_version 1d -p verilog --noline: tl-x.org
m4+definitions(['
   m4_define(['M4_ISA'], ['RISCV'])
   m4_define(['M4_STANDARD_CONFIG'], ['4-stage'])
   m4_define(['M4_IMPL'], 1)
   m4_define(['M4_VIZ'], 0)
'])
\SV
   // Include WARP-V.
   m4_include_lib(['./warp-v.tlv'])
m4+module_def
\TLV
   m4+warpv()
   // Connect *passed/*failed to preserve logic.
   |fetch
      /instr
         @M4_EXECUTE_STAGE
            *passed = $valid_exe && ! $reset && $Pc == '1;
            *failed = 1'b0;
\SV
   endmodule
