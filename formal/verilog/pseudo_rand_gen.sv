// Generated by SandPiper(TM) 1.9-2018/02/11-beta from Redwood EDA.
// (Installed here: /home/steve/mono/sandpiper/distro.)
// Redwood EDA, LLC does not claim intellectual property rights to this file and provides no warranty regarding its correctness or quality.


`include "sandpiper_gen.vh"





//
// Signals declared top-level.
//

// For |default$lfsr.
logic [LFSR_WIDTH-1:0] DEFAULT_lfsr_a1,
                       DEFAULT_lfsr_a2;

// For |default$reset.
logic DEFAULT_reset_a0,
      DEFAULT_reset_a1;



generate


   //
   // Scope: |default
   //

      // For $lfsr.
      always_ff @(posedge clk) DEFAULT_lfsr_a2[LFSR_WIDTH-1:0] <= DEFAULT_lfsr_a1[LFSR_WIDTH-1:0];

      // For $reset.
      always_ff @(posedge clk) DEFAULT_reset_a1 <= DEFAULT_reset_a0;




endgenerate




generate   // This is awkward, but we need to go into 'generate' context in the line that `includes the declarations file.
