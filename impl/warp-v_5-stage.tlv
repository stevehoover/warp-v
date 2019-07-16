\m4_TLV_version 1d -p verilog --noline: tl-x.org
m4+definitions
   // Configure for impl.
   m4_define(['M4_TB'], 1)
   m4_define(['M4_FORMAL'], 0)
\SV
   // Include WARP-V.
   m4_include_lib(['./warp-v.tlv'])
m4+module_def
\TLV
   m4+cpu()
   m4+tb()
\SV
   endmodule
