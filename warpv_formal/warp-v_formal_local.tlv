\m4_TLV_version 1d: tl-x.org
m4+definitions
   // This file is almost identical to its non-local counterpart. It differs in that it is expected to be
   // compiled from its own repository.
   
   // Configure for formal verification.
   m4_define(['M4_TB'], 0)
   m4_define(['M4_FORMAL'], 1)
   
   // Include WARP-V.
   m4_include_lib(['../warp-v.tlv'])  // This path assumes use by pre-commit script.
m4+module_def
\TLV
   m4+cpu()
   m4+formal()
\SV
   endmodule