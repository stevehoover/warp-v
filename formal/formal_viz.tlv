\m5_TLV_version 1d: tl-x.org
\m5
   / For viewing a riscv-formal counterexample trace in Makerchip (Waveform and VIZ, including RVFI VIZ).
   / Compile this in Makerchip, then open the trace using File > Waveforms > Open Waveform (in Chrome or Edge).
   / The configuration and warp-v.tlv commit below must match those that produced the trace.
   use(m5-1.0)
   var(FORMAL, 1)
   / Match "make verif" settings (STANDARD_CONFIG, EXT_C).
   var(STANDARD_CONFIG, 4-stage)
   var(EXT_C, 0)
\SV
   // Replace "master" with the commit ID that produced the trace.
   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/warp-v/master/warp-v.tlv'])
m4+module_def()
\TLV
   m5+warpv_top()
\SV
   endmodule
