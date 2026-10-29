\m5_TLV_version 1d: tl-x.org
\m5
   / This file can be used to build a coarsely-configured implementation of WARP-V within makerchip.com.
   / This enables exploration of a generated model (as TL-Verilog (without macros) and/or Verilog/SystemVerilog).
   / Simulation waveforms can be explored.
   /
   / High-level settings are described here. For detailed settings, consult the included warp-v.tlv file.
   
   
   / -----------------------------------------------------------
   / CONFIGURATION:
   
   / ISA. Legal Values: [MINI, RISCV, MIPSI, DUMMY]
   var(ISA, RISCV)
   
   / Standard configuration. Legal Values: [1-stage, 2-stage, 4-stage, 6-stage, none (and define individual parameters)]
   var(STANDARD_CONFIG, 4-stage)
   
   
   / OPTIONAL CONFIGURATION:
   
   / Branch predictor. Legal Values: [fallthrough, two_bit]
   /var(BRANCH_PRED, fallthrough)
   
   
   / DETAILED CONFIGURATION:
   
   / (See included warp-v.tlv)
   
   / -----------------------------------------------------------
   
\SV
   // Include WARP-V.
   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/warp-v/master/warp-v.tlv'])
  
m4+module_def()
\TLV
   m5+warpv_top()
\SV
   endmodule
