\m4_TLV_version 1d: tl-x.org
\SV
   // Configure for formal verification.
   m4_define(['M4_TB'], 0)
   m4_define(['M4_FORMAL'], 1)
   
   // Include WARP-V.
   m4_include_lib(['../../../warp-v/warp-v.tlv'])  // This path assumes use according to the warpv_formal/README.md.
