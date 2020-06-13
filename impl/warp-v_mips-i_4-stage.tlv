\m4_TLV_version 1d --noline: tl-x.org
m4+definitions(['
   m4_define(['M4_ISA'], ['MIPSI'])
   m4_define(['M4_VIZ'], 0)
'])
\SV
   // Include WARP-V.
   m4_include_lib(['./warp-v.tlv'])
m4+module_def
\TLV
   m4+warpv()
   m4+warpv_makerchip_cnt10_tb()
   m4+makerchip_pass_fail()
\SV
   endmodule
