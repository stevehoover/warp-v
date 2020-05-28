\m4_TLV_version 1d: tl-x.org
\SV
   // -----------------------------------------------------------------------------
   // Copyright (c) 2018, Steven F. Hoover
   // 
   // Redistribution and use in source and binary forms, with or without
   // modification, are permitted provided that the following conditions are met:
   // 
   //     * Redistributions of source code must retain the above copyright notice,
   //       this list of conditions and the following disclaimer.
   //     * Redistributions in binary form must reproduce the above copyright
   //       notice, this list of conditions and the following disclaimer in the
   //       documentation and/or other materials provided with the distribution.
   //     * The name Steven F. Hoover
   //       may not be used to endorse or promote products derived from this software
   //       without specific prior written permission.
   // 
   // THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
   // AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
   // IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
   // DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE
   // FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
   // DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
   // SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
   // CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
   // OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
   // OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
   // -----------------------------------------------------------------------------
   // This code is mastered in https://github.com/stevehoover/warp-v.git

m4+definitions(['

   // A highly-parameterized CPU generator, configurable for:
   //   o An ISA of your choice, where the following ISAs are currently defined herein:
   //      - An uber-simple mini CPU for academic use
   //      - RISC-V (incomplete)
   //   o Pipeline staging (from 1 to 7 stages)
   //   o Architectural parameters, like memory size, etc.

   // This file includes:
   //   o The configurable (esp. for pipeline depth) ISA-independent CPU logic.
   //   o ISA-specific decode and execute logic for mini-CPU, RISC-V, and a dummy
   //    (for diagrams).
   //   o A simple RISC-V assembler. (The Mini ISA needs no assembler as it uses strings for instructions.)
   //   o A tiny test program for each ISA

   // Notes:
   //   o THIS CODE MAKES HEAVY USE OF MACRO PREPROCESSING WITH M4 (https://www.gnu.org/software/m4/manual/m4.html),
   //     AS WELL AS "M4+" MACROS SUPPORTED BY PERL PREPROCESSING. NEITHER OF THESE ARE
   //     CURRENTLY DOCUMENTED OR SUPPORTED FOR GENERAL USE. This design is shared to illustrate
   //     the potential. While we openly welcome collaboration, there are no current expectations that folks
   //     will be able to evolve the design independently. If you are interested in collaboration,
   //     please contact steve.hoover@redwoodeda.com.
   //   o The preprocessed code is represented in the "Nav-TLV" tab. You can debug using
   //     Nav-TLV and find corresponding source lines by clicking Nav-TLV line numbers.
   //   o The "Diagram" may fail to generate due to the size of the design.
   


   // The CPU

   // The code is parameterized, using the M4 macro preprocessor, for adjustable pipeline
   // depth.
   //
   // Overview:
   //   o One instruction traverses the single free-flowing CPU pipeline per cycle.
   //   o There is no branch or condition or target prediction.
   //   o Instructions are in-order, but the uarch supports loads that return their
   //     data out of order (though, they don't).
   //
   // Redirects:
   //
   // The PC is redirected, and inflight instructions are squashed (their results are
   // not committed) for:
   //   o no-fetch cycles (squashes only the no-fetch instruction itself)
   //   o 2nd-issue of split (long-latency) instructions (squashes only the clobbered instruction itself,
   //     which reissues next cycle)
   //   o jumps, which go to an absolute jump target address
   //   o predicted-taken branches, which speculatively redirect to the computed branch target
   //   o unconditioned and mispredicted taken branches, which go to branch target
   //   o mispredicted not-taken branches which go to the next sequential PC
   //   o instructions that read or write a pending register
   //     (See "Loads", below.)
   //   o traps, which go to a trap target
  
   //
   // Loads:
   //
   // Load instructions complete without writing their destination registers. Destination
   // registers are instead marked "pending", and reads of pending registers are replayed.
   // This could again result in a read of the same pending register and can repeat until
   // the load returns. Writes to pending registers are also replayed, so there can be at
   // most one oustanding load to any given register. This way, out-of-order loads are
   // supported (though loads are implemented to have a fixed latency). A returning load
   // reserves an instruction slot at the beginning of the pipeline to reserve a register
   // write port. The returning load writes its result and clears the destination
   // register's pending flag.
   //
   // To support L1 and L2 caches, it would be reasonable to delay register write (if
   // necessary) to wait for L1 hits (extending the bypass window), and mark "pending"
   // for L1 misses. Power could be saved by going idle on replay until load will return
   // data.
   //
   // Long-latency pipelined instructions:
   //
   // Long-latency pipelined instructions can utilize the same split issue and pending
   // mechanisms as load instructions.
   //
   // Long-latency non-pipelined instructions:
   //
   // FP and mul/div are likely to take multiple cycles to execute, may not be pipelined, and 
   // are likely to utilize the ALU iteratively. These are followed by "no-fetch" cycles until
   // the next redirect (which will be a second issue of the instruction).
   // It doesn't matter whether registers are marked pending, but we do.
   //
   // Bypass:
   //
   // Register bypass is provided if one instruction's result is not written to the
   // register file in time for the next instruction's read. An additional bypass is
   // provided for each additional cycle between read and write.
   //
   // Memory:
   //
   // The program is stored in its own instruction memory (for simplicity).
   // Data memory is separate.
   //
   
   // TODO: It might be cleaner to split /instr into two scopes: /fetch_instr and /commit_instr, where
   //       /fetch_instr reflects the instruction fetched from i-memory (1st issue), and /commit_instr reflects the
   //       instruction that will be committed (2nd issue). The difference is long-latency instructions which commit
   //       in place of the fetch instruction. There have been several subtle bugs where the fetch
   //       instruction leaks into the commit instruction (esp. reg. bypass), and this would help to
   //       avoid them.
   // TODO: Replays can be injected later in the pipeline - at the end of fetch. Unlike redirect, we
   //       already have the raw instruction bits to inject. The replay mechanism can be separated from
   //       redirects.
   
   
   // ============
   // Mini-CPU ISA
   // ============
   
   // A dirt-simple CPU for educational purposes.

   // What's interesting about this CPU?
   //   o It's super small.
   //   o It's easy to play with an learn from.
   //   o Instructions are short, kind-of-readable strings, so no assembler is needed.
   //     They would map directly to a denser (~17-bit) encoding if desired.
   //   o The only instruction formats are op, load, and store.
   //   o Branch/Jump: There is no special format for control-flow instructions. Any
   //     instruction can write the PC (relative or absolute). A conditional branch
   //     will typically utilize a condition operation that provides a branch target or
   //     zero. The condition can be predicted as per traditional branch prediction
   //     (though there is no branch predictor in this example as it stands).

   // ISA:
   //
   // Instructions are 5-character strings: "D=1o2"
   //
   // =: Appears in every instruction (just for readability).
   // D, 2, 1: "a" - "h" for register values;
   //          "0" - "7" for immediate constants (sources, or "0" for unused dest);
   //          "P" for absolute dest PC (jump);
   //          "p" for relative dest PC (branch), PC = PC + 1 + result(signed).
   //
   // o: operator
   //   Op: (D = 1 o 2) (Eg: "c=a+b"):
   //     +, -, *, /: Arithmetic. *, / are unsigned.
   //     =, !, <, >, [, ]: Compare (D = (1 o r) ? all-1s : 0) (] is >=, [ is <=)
   //        (On booleans these are XNOR, XOR, !1&2, 1&!2, !1|2, 1|!2)
   //     &, |: Bitwise
   //        (Can be used on booleans as well as vectors.)
   //     (There are no operators for NAND and NOR and unary !.)
   //     ~: Extended constant (D = {1[2:0], 2[2:0]})
   //     ,: Combine (D = {1[11:6], 2[5:0]})
   //     ?: Conditional (D = 2 ? `0 : 1)
   //   Load (Eg: "c=a{b") (D = [1 + 2] (typically 1 would be an immediate offset):
   //     {: Load
   //   Store (Eg: "0=a}b") ([2] = 1):
   //     }: Store
   //
   // A full-width immediate load sequence, to load octal 2017 is:
   //   a=2~0
   //   b=1~7
   //   a=a,b

   // A typical local conditional branch sequence is:
   //   a=0-6  // offset
   //   c=c-1  // decrementing loop counter
   //   p=a?c  // branch by a (to PC+1-6) if c is non-negative (MSB==0)



   // ==========
   // RISC-V ISA
   // ==========
   
   // This design is a RISC-V (RV32I) implementation.
   // The ISA is characterized using M4 macros, and the microarchitecture is generated from this characterization, so
   // the ISA can be modified through M4 definitions.
   // Notes:
   //   o Unaligned load/store are handled by trapping, though no s/w is available to handle the trap.
   // The implementation is based on "The RISC-V Instruction Set Manual Vol. I: User-Level ISA," Version 2.2: https://riscv.org/specifications/

   
   
   // ======
   // MIPS I
   // ======
   
   // WIP.
   // Unlike RISC-V, this does not use M4 to characterize the ISA.
   // Not implemented:
   //   o FPU
   //   o Mult/Div and HI/LO regs
   //   o Branch/Load delay slots
   // No compliance testing has been done. This code is intended to demonstrate the flexibility of TL-Verilog,
   // not to provide a production-worthy MIPS I design.
   
   
   // =====
   // Power
   // =====
   
   // WIP. 
   // Unlike RISC-V, this does not use M4 to characterize the ISA.
   // No compliance testing has been done. This code is intended to demonstrate the flexibility of TL-Verilog,
   // not to provide a production-worthy Power design.
   
   
   // =========
   // DUMMY ISA
   // =========

   // This "ISA" can be selected to produce diagrams of the CPU without the ISA details.
   // It is also useful as a starting point and reference for other ISAs, as it illustrates which signals are required.



   // =========
   // Libraries
   // =========
   



   // =============
   // Configuration
   // =============
   
   // This is where you configure the CPU.
   // m4_default(..) allows external definition to take precedence.

   // Machine:
   // ISA:
   m4_default(['M4_ISA'], ['RISCV']) // MINI, RISCV, MIPSI, POWER, DUMMY, etc.
   // Select a standard configuration:
   m4_default(['M4_STANDARD_CONFIG'], ['4-stage'])  // 1-stage, 4-stage, 6-stage, none (and define individual parameters).
   
   // A multi-core implementation (currently RISC-V only) should:
   //   m4_define_hier(['M4_CORE'], #)
   //   m4_define_hier(['M4_VC'], #)
   //   m4_define_hier(['M4_PRIO'], #)
   // prior to inclusion of this file.
   m4_ifelse(M4_CORE_CNT, ['M4_CORE_CNT'], ['
      // In not externally defined:
      m4_define_hier(['M4_CORE'], 1)  // Number of cores.
      m4_define_hier(['M4_VC'], 2)    // VCs (meaningful if > 1 core).
      m4_define_hier(['M4_PRIO'], 2)  // Number of priority levels in the NoC.
   '])
   // Inclusions for multi-core only:
   m4_ifexpr(M4_CORE_CNT > 1, ['
      m4_ifelse(M4_ISA, ['RISCV'], [''], ['m4_errprint(['Multi-core supported for RISC-V only.']m4_new_line)'])
      m4_include_url(['https:/']['/raw.githubusercontent.com/stevehoover/tlv_lib/481188115b4338567df916460d462ca82401e211/fundamentals_lib.tlv'])
      m4_include_url(['https:/']['/raw.githubusercontent.com/stevehoover/tlv_flow_lib/7a2b37cc0ccd06bc66984c37e17ceb970fd6f339/pipeflow_lib.tlv'])
   '])
   
   // Include testbench (for Makerchip simulation) (defaulted to 1).
   m4_default(['M4_IMPL'], 0)  // For implementation (vs. simulation).
   // Build for formal verification (defaulted to 0).
   m4_default(['M4_FORMAL'], 0)  // 1 to enable code for formal verification

   
   // Which program to assemble.
   m4_define(M4_PROG_NAME, ['cnt10'])

   // A hook for a software-controlled reset. None by default.
   m4_define(['m4_soft_reset'], 1'b0)

   // A hook for CPU back-pressure in M4_REG_RD_STAGE.
   // Various sources of back-pressure can add to this expression.
   // Currently, this is envisioned for CSR writes that cannot be processed, such as
   // NoC packet writes.
   m4_define(['m4_cpu_blocked'], 1'b0)


   // Define the implementation configuration, including pipeline depth and staging.
   // Define the following:
   //   Stages:
   //     M4_NEXT_PC_STAGE: Determining fetch PC for the NEXT instruction (not this one).
   //     M4_FETCH_STAGE: Instruction fetch.
   //     M4_DECODE_STAGE: Instruction decode.
   //     M4_BRANCH_PRED_STAGE: Branch predict (taken/not-taken). Currently, we mispredict to a known branch target,
   //                           so branch prediction is only relevant if target is computed before taken/not-taken is known.
   //                           For other ISAs prediction is forced to fallthrough, and there is no pred-taken redirect.
   //     M4_REG_RD_STAGE: Register file read.
   //     M4_EXECUTE_STAGE: Operation execution.
   //     M4_RESULT_STAGE: Select execution result.
   //     M4_BRANCH_TARGET_CALC_STAGE: Calculate branch target (generally EXECUTE, but some designs
   //                                  might produce offset from EXECUTE, then compute target).
   //     M4_MEM_WR_STAGE: Memory write.
   //     M4_REG_WR_STAGE: Register file write.
   //     Deltas (default to 0):
   //       M4_DELAY_BRANCH_TARGET_CALC: 1 to delay branch target calculation 1 stage from its nominal (ISA-specific) stage.
   //   Latencies (default to 0):
   //     M4_LD_RETURN_ALIGN: Alignment of load return pseudo-instruction into |mem pipeline.
   //                         If |mem stages reflect nominal alignment w/ load instruction, this is the
   //                         nominal load latency.
   //     Deltas (default to 0):
   //       M4 EXTRA_PRED_TAKEN_BUBBLE: 0 or 1. 0 aligns PC_MUX with BRANCH_TARGET_CALC.
   //       M4_EXTRA_REPLAY_BUBBLE:     0 or 1. 0 aligns PC_MUX with RD_REG for replays.
   //       M4_EXTRA_JUMP_BUBBLE:       0 or 1. 0 aligns PC_MUX with EXECUTE for jumps.
   //       M4_EXTRA_PRED_TAKEN_BUBBLE: 0 or 1. 0 aligns PC_MUX with EXECUTE for pred_taken.
   //       M4_EXTRA_INDIRECT_JUMP_BUBBLE: 0 or 1. 0 aligns PC_MUX with EXECUTE for indirect_jump.
   //       M4_EXTRA_BRANCH_BUBBLE:     0 or 1. 0 aligns PC_MUX with EXECUTE for branches.
   //       M4_EXTRA_TRAP_BUBBLE:       0 or 1. 0 aligns PC_MUX with EXECUTE for traps.
   //   M4_BRANCH_PRED: {fallthrough, two_bit, ...}
   //   M4_DATA_MEM_WORDS: Number of data memory locations.
   m4_case(M4_STANDARD_CONFIG,
      ['1-stage'], ['
         // No pipeline
         m4_defines(
            (M4_NEXT_PC_STAGE, 0),
            (M4_FETCH_STAGE, 0),
            (M4_DECODE_STAGE, 0),
            (M4_BRANCH_PRED_STAGE, 0),
            (M4_REG_RD_STAGE, 0),
            (M4_EXECUTE_STAGE, 0),
            (M4_RESULT_STAGE, 0),
            (M4_REG_WR_STAGE, 0),
            (M4_MEM_WR_STAGE, 0),
            (M4_LD_RETURN_ALIGN, 1))
         m4_default(['M4_BRANCH_PRED'], ['fallthrough'])
         m4_define_hier(['M4_DATA_MEM_WORDS'], 32)
      '],
      ['4-stage'], ['
         // A reasonable 4-stage pipeline.
         m4_defines(
            (M4_NEXT_PC_STAGE, 0),
            (M4_FETCH_STAGE, 0),
            (M4_DECODE_STAGE, 1),
            (M4_BRANCH_PRED_STAGE, 1),
            (M4_REG_RD_STAGE, 1),
            (M4_EXECUTE_STAGE, 2),
            (M4_RESULT_STAGE, 2),
            (M4_REG_WR_STAGE, 3),
            (M4_MEM_WR_STAGE, 3),
            (M4_EXTRA_REPLAY_BUBBLE, 1),
            (M4_LD_RETURN_ALIGN, 4))
         m4_define(['M4_BRANCH_PRED'], ['two_bit'])
         m4_define_hier(['M4_DATA_MEM_WORDS'], 32)
      '],
      ['6-stage'], ['
         // Deep pipeline
         m4_defines(
            (M4_NEXT_PC_STAGE, 1),
            (M4_FETCH_STAGE, 1),
            (M4_DECODE_STAGE, 3),
            (M4_BRANCH_PRED_STAGE, 4),
            (M4_REG_RD_STAGE, 4),
            (M4_EXECUTE_STAGE, 5),
            (M4_RESULT_STAGE, 5),
            (M4_REG_WR_STAGE, 6),
            (M4_MEM_WR_STAGE, 7),
            (M4_EXTRA_REPLAY_BUBBLE, 1),
            (M4_LD_RETURN_ALIGN, 7))
         m4_default(['M4_BRANCH_PRED'], ['two_bit'])
         m4_define_hier(['M4_DATA_MEM_WORDS'], 32)
      ']
   )
   
   
   // --------------------------
   // ISA-Specific Configuration
   // --------------------------

   m4_case(M4_ISA, ['MINI'], ['
         // Mini-CPU Configuration:
         // Force predictor to fallthrough, since we can't predict early enough to help.
         m4_define(['M4_BRANCH_PRED'], ['fallthrough'])
      '], ['RISCV'], ['
         // RISC-V Configuration:

         // ISA options:

         // Currently supported uarch variants:
         //   RV32I 2.0, w/ no ISA extensions.

         // Machine width
         m4_define_vector(['M4_WORD'], 32)  // 32 or RV32X or 64 for RV64X.
         // ISA extensions,  1, or 0 (following M4 boolean convention).
         m4_defines(
            (['M4_EXT_E'], 1),
            (['M4_EXT_I'], 1),
            (['M4_EXT_M'], 1),
            (['M4_EXT_A'], 0),
            (['M4_EXT_F'], 0),
            (['M4_EXT_D'], 0),
            (['M4_EXT_Q'], 0),
            (['M4_EXT_L'], 0),
            (['M4_EXT_C'], 0),
            (['M4_EXT_B'], 0),
            (['M4_EXT_J'], 0),
            (['M4_EXT_T'], 0),
            (['M4_EXT_P'], 0),
            (['M4_EXT_V'], 0),
            (['M4_EXT_N'], 0))
         
         // For the time[h] CSR register, after this many cycles, time increments.
         m4_define_vector(M4_CYCLES_PER_TIME_UNIT, 1000000000)
      '], ['MIPSI'], ['
      '], ['POWER'], ['
      '], ['
         // Dummy "ISA".
         m4_define_hier(M4_DATA_MEM_WORDS, 4) // Override for narrow address.
         // Force predictor to fallthrough, since we can't predict early enough to help.
         m4_define(['M4_BRANCH_PRED'], ['fallthrough'])
      ']
   )
   
   // =====Done Defining Configuration=====
   
   // Characterize ISA and apply configuration.
   
   // Characterize the ISA, including:
   // M4_NOMINAL_BR_TARGET_CALC_STAGE: An expression that will evaluate to the earliest stage at which the branch target
   //                                  can be available.
   // M4_HAS_INDIRECT_JUMP: (0/1) Does this ISA have indirect jumps.
   // Defaults:
   m4_define(['M4_HAS_INDIRECT_JUMP'], 0)
   m4_case(M4_ISA, ['MINI'], ['
         // Mini-CPU Characterization:
         m4_define(['M4_NOMINAL_BRANCH_TARGET_CALC_STAGE'], ['M4_EXECUTE_STAGE'])
      '], ['RISCV'], ['
         // RISC-V Characterization:
         m4_define(['M4_NOMINAL_BRANCH_TARGET_CALC_STAGE'], ['M4_DECODE_STAGE'])
         m4_define(['M4_HAS_INDIRECT_JUMP'], 1)
      '], ['MIPSI'], ['
         // MIPS I Characterization:
         m4_define(['M4_NOMINAL_BRANCH_TARGET_CALC_STAGE'], ['M4_DECODE_STAGE'])
         m4_define(['M4_HAS_INDIRECT_JUMP'], 1)
      '], ['POWER'], ['
      '], ['DUMMY'], ['
         // DUMMY Characterization:
         m4_define(['M4_NOMINAL_BRANCH_TARGET_CALC_STAGE'], ['M4_EXECUTE_STAGE'])
      ']
   )

   // Supply defaults for extra cycles.
   m4_defines(
      (M4_DELAY_BRANCH_TARGET_CALC, 0),
      (M4_EXTRA_PRED_TAKEN_BUBBLE, 0),
      (M4_EXTRA_REPLAY_BUBBLE, 0),
      (M4_EXTRA_JUMP_BUBBLE, 0),
      (M4_EXTRA_BRANCH_BUBBLE, 0),
      (M4_EXTRA_INDIRECT_JUMP_BUBBLE, 0),
      (M4_EXTRA_NON_PIPELINED_BUBBLE, 1),
      (M4_EXTRA_TRAP_BUBBLE, 1)
   )
   
   // Calculated stages:
   m4_define(M4_BRANCH_TARGET_CALC_STAGE, m4_eval(M4_NOMINAL_BRANCH_TARGET_CALC_STAGE + M4_DELAY_BRANCH_TARGET_CALC))
   // Calculated alignments:
   m4_define(M4_REG_BYPASS_STAGES,  m4_eval(M4_REG_WR_STAGE - M4_REG_RD_STAGE))

   // Latencies/bubbles calculated from stage parameters and extra bubbles:
   // (zero bubbles minimum if triggered in next_pc; minimum bubbles = computed-stage - next_pc-stage)
   m4_define(['M4_PRED_TAKEN_BUBBLES'], m4_eval(M4_BRANCH_PRED_STAGE - M4_NEXT_PC_STAGE + M4_EXTRA_PRED_TAKEN_BUBBLE))
   m4_define(['M4_REPLAY_BUBBLES'],     m4_eval(M4_REG_RD_STAGE - M4_NEXT_PC_STAGE + M4_EXTRA_REPLAY_BUBBLE))
   m4_define(['M4_JUMP_BUBBLES'],       m4_eval(M4_EXECUTE_STAGE - M4_NEXT_PC_STAGE + M4_EXTRA_JUMP_BUBBLE))
   m4_define(['M4_BRANCH_BUBBLES'],     m4_eval(M4_EXECUTE_STAGE - M4_NEXT_PC_STAGE + M4_EXTRA_BRANCH_BUBBLE))
   m4_define(['M4_INDIRECT_JUMP_BUBBLES'], m4_eval(M4_EXECUTE_STAGE - M4_NEXT_PC_STAGE + M4_EXTRA_INDIRECT_JUMP_BUBBLE))
   m4_define(['M4_NON_PIPELINED_BUBBLES'], m4_eval(M4_EXECUTE_STAGE - M4_NEXT_PC_STAGE + M4_EXTRA_NON_PIPELINED_BUBBLE))
   m4_define(['M4_TRAP_BUBBLES'],       m4_eval(M4_EXECUTE_STAGE - M4_NEXT_PC_STAGE + M4_EXTRA_TRAP_BUBBLE))
   m4_define(['M4_SECOND_ISSUE_BUBBLES'], 0)  // Bubbles between second issue of a long-latency instruction and
                                              // the replay of the instruction it squashed (so always zero).
   m4_define(['M4_NO_FETCH_BUBBLES'], 0)  // Bubbles between a no-fetch cycle and the next cycles (so always zero).
   
   
   
   // Retiming experiment.
   //
   // The idea here, is to move all logic into @0 and see how well synthesis results compare vs. the timed model with
   // retiming enabled. In theory, synthesis should be able to produce identical results.
   //
   // Unfortunately, this modeling doesn't work because of the redirection logic. When timed @0, the $GoodPathMask would
   // need to be redistributed, with each bit in a different stage to enable $commit to be computed in @0. So, to make
   // this work, each bit of $GoodPathMask would have to become a separate signal, and each signal assignment would need
   // its own @stage scope, affected by M4_RETIMING_EXPERIMENT. Since this is all generated by M4 ugliness, it was too
   // complicated to justify the experiment.
   //
   // For now, the RETIMING_EXPERIMENT sets $commit to 1'b1, and produces results that make synthesis look good.
   //
   // This option moves all logic into stage 0 (after determining relative timing interactions based on their original configuration).
   // The resulting SV is to be used for retiming experiments to see how well logic synthesis is able to retime the design.
   m4_ifelse(M4_RETIMING_EXPERIMENT, ['M4_RETIMING_EXPERIMENT'], [''], ['
      m4_define(['M4_NEXT_PC_STAGE'], 0)
      m4_define(['M4_FETCH_STAGE'], 0)
      m4_define(['M4_DECODE_STAGE'], 0)
      m4_define(['M4_BRANCH_PRED_STAGE'], 0)
      m4_define(['M4_BRANCH_TARGET_CALC_STAGE'], 0)
      m4_define(['M4_REG_RD_STAGE'], 0)
      m4_define(['M4_EXECUTE_STAGE'], 0)
      m4_define(['M4_RESULT_STAGE'], 0)
      m4_define(['M4_REG_WR_STAGE'], 0)
      m4_define(['M4_MEM_WR_STAGE'], 0)
   '])
   
   
   
   // ========================
   // Check Legality of Config
   // ========================
   
   // (Not intended to be exhaustive.)
   
   // Check that expressions are ordered.
   m4_define(['m4_ordered'], ['
      m4_ifelse($2, [''], [''], ['
         m4_ifelse(m4_eval(m4_echo($1) > m4_echo($2)), 1,
                   ['m4_errprint(['$1 (']$1[') is greater than $2 (']$2[').']m4_new_line())'])
         m4_ordered(m4_shift($@))
      '])
   '])
   // TODO:; It should be M4_NEXT_PC_STAGE-1, below.
   m4_ordered(['M4_NEXT_PC_STAGE'], ['M4_FETCH_STAGE'], ['M4_DECODE_STAGE'], ['M4_BRANCH_PRED_STAGE'], ['M4_REG_RD_STAGE'],
              ['M4_EXECUTE_STAGE'], ['M4_RESULT_STAGE'], ['M4_REG_WR_STAGE'], ['M4_MEM_WR_STAGE'])
   
   // Check reg bypass limit
   m4_ifelse(m4_eval(M4_REG_BYPASS_STAGES > 3), 1, ['m4_errprint(['Too many stages of register bypass (']M4_REG_BYPASS_STAGES['.'])'])
   


   // ==================
   // Default Parameters
   // ==================
   // These may be overridden by specific ISA.

   m4_define(M4_BIG_ENDIAN, ['0'])


   // =======================
   // ISA-specific Parameters
   // =======================

   // Macros for ISA-specific code.
   
   m4_define(M4_isa, m4_translit(M4_ISA, ['A-Z'], ['a-z']))   // A lower-case version of M4_ISA.
   
   // Instruction Memory macros are responsible for providing the instruction memory interface for fetch, as:
   // Inputs:
   //   |fetch@M4_FETCH$Pc[m4_eval(M4_PC_MIN + m4_width(M4_NUM_INSTRS-1) - 1):M4_PC_MIN]
   // Outputs:
   //   |fetch/instr?$fetch$raw[M4_INSTR_RANGE] (at or after @M4_FETCH_STAGE--at for retiming experiment; +1 for fast array read)
   m4_default(['M4_IMEM_MACRO_NAME'], M4_isa['_imem'])
   
   // For each ISA, define:
   //   m4_define_vector(['M4_INSTR'], XX)   // (or, m4_define_vector_with_fields(...)) Instruction vector.
   //   m4_define_vector(['M4_ADDR'], XX)    // An address.
   //   m4_define(['M4_BITS_PER_ADDR'], XX)  // Each memory address holds XX bits.
   //   m4_define_vector(['M4_WORD'], XX)    // Width of general-purpose registers.
   //   m4_define_hier(['M4_REGS'], XX)      // General-purpose register file.

   m4_case(M4_ISA,
      ['MINI'], ['
         m4_define_vector_with_fields(M4_INSTR, 40, DEST_CHAR, 32, EQUALS_CHAR, 24, SRC1_CHAR, 16, OP_CHAR, 8, SRC2_CHAR, 0)
         m4_define_vector(M4_ADDR, 12)
         m4_define(['M4_BITS_PER_ADDR'], 12)  // Each memory address holds 12 bits.
         m4_define_vector(M4_WORD, 12)
         m4_define_hier(M4_REGS, 8)   // (Plural to avoid name conflict w/ SV "reg" keyword.)
      '],
      ['RISCV'], ['
         // Definitions matching "The RISC-V Instruction Set Manual Vol. I: User-Level ISA", Version 2.2.

         m4_define_vector(['M4_INSTR'], 32)
         m4_define_vector(['M4_ADDR'], 32)
         m4_define(['M4_BITS_PER_ADDR'], 8)  // 8 for byte addressing.
         m4_define_vector(['M4_WORD'], 32)
         m4_define_hier(['M4_REGS'], 32, 1)
      '],
      ['MIPSI'], ['
         m4_define_vector_with_fields(M4_INSTR, 32, OPCODE, 26, RS, 21, RT, 16, RD, 11, SHAMT, 6, FUNCT, 0)
         m4_define_vector(['M4_ADDR'], 32)
         m4_define(['M4_BITS_PER_ADDR'], 8)  // 8 for byte addressing.
         m4_define_vector(['M4_WORD'], 32)
         m4_define_hier(['M4_REGS'], 32, 1)
      '],
      ['POWER'], ['
      '],
      ['DUMMY'], ['
         m4_define_vector(M4_INSTR, 2)
         m4_define_vector(M4_ADDR, 2)
         m4_define(['M4_BITS_PER_ADDR'], 2)
         m4_define_vector(M4_WORD, 2)
         m4_define_hier(M4_REGS, 8)
      '])
   
   
   
   
   // Computed ISA uarch Parameters (based on ISA-specific parameters).

   m4_define(['M4_ADDRS_PER_WORD'], m4_eval(M4_WORD_CNT / M4_BITS_PER_ADDR))
   m4_define(['M4_SUB_WORD_BITS'], m4_width(m4_eval(M4_ADDRS_PER_WORD - 1)))
   m4_define(['M4_ADDRS_PER_INSTR'], m4_eval(M4_INSTR_CNT / M4_BITS_PER_ADDR))
   m4_define(['M4_SUB_PC_BITS'], m4_width(m4_eval(M4_ADDRS_PER_INSTR - 1)))
   m4_define_vector(['M4_PC'], M4_ADDR_HIGH, M4_SUB_PC_BITS)
   m4_define(['M4_FULL_PC'], ['{$Pc, M4_SUB_PC_BITS'b0}'])
   m4_define_hier(M4_DATA_MEM_ADDRS, m4_eval(M4_DATA_MEM_WORDS_HIGH * M4_ADDRS_PER_WORD))  // Addressable data memory locations.
   m4_define(['M4_INJECT_RETURNING_LD'], m4_eval(M4_LD_RETURN_ALIGN > 0))
   m4_define(['M4_PENDING_ENABLED'], M4_INJECT_RETURNING_LD)
   
   
   // =========
   // Redirects
   // =========

   // TODO: It is possible to create a generic macro for a pipeline with redirects.
   //       The PC redirection would become $ANY redirection. Redirected transactions would come from subhierarchy of
   //       pipeline, eg: |fetch/branch_redir$pc (instead of |fetch$branch_target).
   // TODO: The code would be a little cleaner to create a multi-line macro body for redirect conditions, such as
   //     \TLV redirect_conditions()
   //        m4_redirect_condition_logic
   //   which becomes:
   //     \TLV redirect_conditions()
   //        @2
   //           $trigger1_redir = $trigger1 && >>2$GoodPath[2];  // Aborting trigger.
   //        @2
   //           $trigger2_redir = $trigger2 && !(1'b0 || $trigger1) && >>2$GoodPath[2];
   //        @3
   //           $trigger3_redir = $trigger3 && !(1'b0 || $trigger1) && >>3$GoodPath[3];
   //        ...
   //   This would replace m4_redir_cond (and m4_redirect_masking_triggers).

   // Redirects are described in the TLV code. Supporting macro definitions are here.

   // m4_process_redirect_conditions appends definitions to the following macros whose initial values are given here.
   m4_define(['m4_redirect_list'], ['['-100']'])  // list fed to m4_ordered
   m4_define(['m4_redirect_squash_terms'], [''])  // & terms to apply to $GoodPathMask, each reflects the redirect shadow and abort of a trigger that becomes visible.
   m4_define(['m4_redirect_shadow_terms'], [''])  // & terms to apply to $RvfiGoodPathMask, each reflects the redirect shadow of a trigger that becomes visible (for formal verif only).
   m4_define(['m4_redirect_pc_terms'], [''])      // ternary operator terms for redirecting PC (later-stage redirects must be first)
   m4_define(['m4_abort_terms'], ['1'b0'])        // || terms for an instruction's abort condition
   m4_define(['m4_redirect_masking_triggers'], ['1'b0']) // || terms combining earlier aborting triggers on the same instruction, using "$1" for alignment.
                                                         // Each trigger uses this term as it is built to mask its effect, so aborting triggers have the final say.
   //m4_define(['m4_redirect_signal_list'], ['{0{1'b0}}'])  // concatenation terms for each trigger condition (naturally-aligned). Start w/ a 0-bit term for concatenation.
   // Redirection conditions. These conditions must be defined from fewest bubble cycles to most.
   // See redirection logic for more detail.
   // Create several defines with items per redirect condition.
   m4_define(['M4_NUM_REDIRECT_CONDITIONS'], 0)  // Incremented for each condition.
   m4_define(['m4_process_redirect_conditions'],
             ['m4_ifelse(['$@'], ['['']'],
                         [''],
                         ['m4_process_redirect_condition($1, M4_NUM_REDIRECT_CONDITIONS)
                           m4_process_redirect_conditions(m4_shift($@))
                         ']
                        )
               m4_define(['M4_NUM_REDIRECT_CONDITIONS'], m4_eval(M4_NUM_REDIRECT_CONDITIONS + 1))
             '])
   m4_define(['M4_MAX_REDIRECT_BUBBLES'], M4_TRAP_BUBBLES)

   // Called by m4_process_redirect_conditions (plural) for each redirect condition from fewest bubbles to most to append
   // to various definitions, initialized above.
   // Args:
   //   $1: name of define of number of bubble cycles
   //   $2: condition signal of triggering instr
   //   $3: target PC signal of triggering instruction
   //   $4: 1 for an aborting redirect (0 otherwise)
   //   $5: (opt) 1 to freeze fetch until subsequent redirect
   m4_define(['m4_process_redirect_condition'],
             ['// expression in @M4_NEXT_PC_STAGE asserting for the redirect condition.
               // = instruction triggers this condition && it's on the current path && it's not masked by an earlier aborting redirect
               //   of this instruction.
               // Params: $@ (m4_redirect_masking_triggers contains param use)
               m4_pushdef(['m4_redir_cond'],
                          ['(>>m4_echo($1)$2 && !(']m4_echo(m4_redirect_masking_triggers)[') && $GoodPathMask[m4_echo($1)])'])
               m4_define(['m4_redirect_list'],
                         m4_dquote(m4_redirect_list, ['$1']))
               m4_define(['m4_redirect_squash_terms'],
                         ['']m4_quote(m4_redirect_squash_terms)[' & (m4_echo(']m4_redir_cond($@)[') ? {{m4_eval(M4_MAX_REDIRECT_BUBBLES + 1 - m4_echo($1) - $4){1'b1}}, {m4_eval(m4_echo($1) + $4){1'b0}}} : {m4_eval(M4_MAX_REDIRECT_BUBBLES + 1){1'b1}})'])
               m4_define(['m4_redirect_shadow_terms'],
                         ['']m4_quote(m4_redirect_shadow_terms)[' & (m4_echo(']m4_redir_cond($@)[') ? {{m4_eval(M4_MAX_REDIRECT_BUBBLES + 1 - m4_echo($1)     ){1'b1}}, {m4_eval(m4_echo($1)     ){1'b0}}} : {m4_eval(M4_MAX_REDIRECT_BUBBLES + 1){1'b1}})'])
               m4_define(['m4_redirect_pc_terms'],
                         ['m4_echo(']m4_redir_cond($@)[') ? {>>m4_echo($1)$3, m4_ifelse($5, 1, 1'b1, 1'b0)} : ']m4_quote(m4_redirect_pc_terms)[' '])
               m4_ifelse(['$4'], ['1'],
                  ['m4_define(['m4_abort_terms'],
                              m4_dquote(m4_abort_terms)['[' || $2']'])
                    m4_define(['m4_redirect_masking_triggers'],
                              m4_dquote(m4_redirect_masking_triggers)['[' || >>$['']1$2']'])'])
               //m4_define(['m4_redirect_signal_list'],
               //          ['']m4_dquote(m4_redirect_signal_list)['[', $2']'])
               m4_popdef(['m4_redir_cond'])
             '])

   // Specify and process redirect conditions.
   m4_process_redirect_conditions(
      ['['M4_SECOND_ISSUE_BUBBLES'], $second_issue, $Pc, 1'],
      ['['M4_NO_FETCH_BUBBLES'], $NoFetch, $Pc, 1, 1'],
      m4_ifelse(M4_BRANCH_PRED, ['fallthrough'], [''], ['['['M4_PRED_TAKEN_BUBBLES'], $pred_taken_branch, $branch_target, 0'],'])
      ['['M4_REPLAY_BUBBLES'], $replay, $Pc, 1'],
      ['['M4_JUMP_BUBBLES'], $jump, $jump_target, 0'],
      ['['M4_BRANCH_BUBBLES'], $mispred_branch, $branch_redir_pc, 0'],
      m4_ifelse(M4_HAS_INDIRECT_JUMP, 1, ['['['M4_INDIRECT_JUMP_BUBBLES'], $indirect_jump, $indirect_jump_target, 0'],'], [''])
      ['['M4_NON_PIPELINED_BUBBLES'], $non_pipelined, $Pc, 0, 1'],
      ['['M4_TRAP_BUBBLES'], $aborting_trap, $trap_target, 1'],
      ['['M4_TRAP_BUBBLES'], $non_aborting_trap, $trap_target, 0'])

   // Ensure proper order.
   // TODO: It would be great to auto-sort.
   m4_ordered(m4_redirect_list)

   
   // A macro for generating a when condition for instruction logic (just for a bit of power savings). (We probably won't
   // bother using it, but it's available in any case.)
   // m4_prev_instr_valid_through(redirect_bubbles) is deasserted by redirects up to the given number of cycles on the previous instruction.
   // Since we can be looking back an arbitrary number of cycles, we'll force invalid if $reset.
   m4_define(['m4_prev_instr_valid_through'],
             ['(! $reset && >>m4_eval(1 - $1)$next_good_path_mask[$1])'])
   //same as <<m4_eval($1)$GoodPathMask[$1]), but accessible 1 cycle earlier and without $reset term.

   
   // ====
   // CSRs
   // ====
   
   // Macro to define a new CSR.
   // Eg: m4_define_csr(['mycsr'], ['12'b123'], ['12, NIBBLE_FIELD, 8, BYTE_FIELD'], ['12'b0'], ['12'hFFF'], 1)
   //  $1: CSR name (lowercase)
   //  $2: CSR index
   //  $3: CSR fields (as in m4_define_fields)
   //  $4: Reset value
   //  $5: Writable bits mask
   //  $6: 0, 1, RO indicating whether to allow side-effect writes.
   //      If 1, these signals in scope |fetch@M4_EXECUTE_STAGE must provide a write value:
   //         o $csr_<csr_name>_hw_wr: 1/0, 1 if a write is to occur (like hw_wr_mask == '0)
   //         o $csr_<csr_name>_hw_wr_value: the value to write
   //         o $csr_<csr_name>_hw_wr_mask: mask of bits to write
   //        Side-effect writes take place prior to corresponding CSR software reads and writes, though it should be
   //        rare that a bit can be written by both hardware and software.
   //      If RO, the CSR is read-only and code can be simpler. The CSR signal must be provided:
   //         o $csr_<csr_name>: The read-only CSR value (used in |fetch@M4_EXECUTE_STAGE).
   // Variables set by this macro:
   // List of CSRs.
   m4_define(['m4_csrs'], [''])
   // Arguments given to this macro for each CSR.
   // Initial value of CSR read result expression, initialized to ternary default case (X).
   m4_define(['m4_csrrx_rslt_expr'], ['M4_WORD_CNT'bx'])
   // Initial value of OR expression for whether CSR index is valid.
   m4_define(['m4_valid_csr_expr'], ['1'b0'])

   // m4_define_csr(name, index (12-bit SV-value), fields (as in m4_define_vector), reset_value (SV-value), writable_mask (SV-value), side-effect_writes (bool))
   // Adds a CSR.
   // Requires provision of: $csr_<name>_hw_[wr, wr_mask, wr_value].
   m4_define(
      ['m4_define_csr'],
      ['m4_define_vector_with_fields(['M4_CSR_']m4_to_upper(['$1']), $3)
        m4_define(['m4_csrs'], 
                  m4_dquote(m4_quote(m4_csrs['']m4_ifelse(m4_csrs, [''], [''], [','])$1)))
        m4_define(['m4_csr_']$1['_args'], ['$@'])
        // 32'b0 = ['{{']m4_eval(32 - m4_echo(['M4_CSR_']m4_to_upper(['$1'])['_CNT'])){1'b0}}, ['$csr_']$1['}']
        m4_define(['m4_csrrx_rslt_expr'], m4_dquote(['$is_csr_']$1[' ? {{']m4_eval(32 - m4_echo(['M4_CSR_']m4_to_upper(['$1'])['_CNT'])){1'b0}}, ['$csr_']$1['} : ']m4_csrrx_rslt_expr))
        m4_define(['m4_valid_csr_expr'], m4_dquote(m4_valid_csr_expr[' || $is_csr_']$1))
      ']
   )
   
   m4_case(M4_ISA, ['RISCV'], ['
      m4_ifelse(M4_NO_COUNTER_CSRS, ['1'], [''], ['
         // Define Counter CSRs
         //            Name            Index       Fields                              Reset Value                    Writable Mask                       Side-Effect Writes
         m4_define_csr(['cycle'],      12'hC00,    ['32, CYCLE_LOW, 0'],               ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_define_csr(['cycleh'],     12'hC80,    ['32, CYCLEH_LOW, 0'],              ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_define_csr(['time'],       12'hC01,    ['32, CYCLE_LOW, 0'],               ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_define_csr(['timeh'],      12'hC81,    ['32, CYCLEH_LOW, 0'],              ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_define_csr(['instret'],    12'hC02,    ['32, INSTRET_LOW, 0'],             ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_define_csr(['instreth'],   12'hC82,    ['32, INSTRETH_LOW, 0'],            ['32'b0'],                     ['{32{1'b1}}'],                     1)
      '])
      
      // For NoC support
      m4_ifexpr(M4_CORE_CNT > 1, ['
         // As defined in: https://docs.google.com/document/d/1cDUv8cuYF2kha8r6DSv-8pwszsrSP3vXsTiAugRkI1k/edit?usp=sharing
         // TODO: Find appropriate indices.
         //            Name            Index       Fields                              Reset Value                    Writable Mask                       Side-Effect Writes
         m4_define_csr(['pktdest'],    12'h800,    ['M4_CORE_INDEX_HIGH, DEST, 0'],    ['M4_CORE_INDEX_HIGH'b0'],     ['{M4_CORE_INDEX_HIGH{1'b1}}'],      0)
         m4_define_csr(['pktwrvc'],    12'h801,    ['M4_VC_INDEX_HIGH, VC, 0'],        ['M4_VC_INDEX_HIGH'b0'],       ['{M4_VC_INDEX_HIGH{1'b1}}'],        0)
         m4_define_csr(['pktwr'],      12'h802,    ['M4_WORD_HIGH, DATA, 0'],          ['M4_WORD_HIGH'b0'],           ['{M4_WORD_HIGH{1'b1}}'],            0)
         m4_define_csr(['pkttail'],    12'h803,    ['M4_WORD_HIGH, DATA, 0'],          ['M4_WORD_HIGH'b0'],           ['{M4_WORD_HIGH{1'b1}}'],            0)
         m4_define_csr(['pktctrl'],    12'h804,    ['1, BLOCK, 0'],                    ['1'b0'],                      ['1'b1'],                            0)
         m4_define_csr(['pktrdvcs'],   12'h808,    ['M4_VC_HIGH, VCS, 0'],             ['M4_VC_HIGH'b0'],             ['{M4_VC_HIGH{1'b1}}'],              0)
         m4_define_csr(['pktavail'],   12'h809,    ['M4_VC_HIGH, AVAIL_MASK, 0'],      ['M4_VC_HIGH'b0'],             ['{M4_VC_HIGH{1'b1}}'],              1)
         m4_define_csr(['pktcomp'],    12'h80a,    ['M4_VC_HIGH, AVAIL_MASK, 0'],      ['M4_VC_HIGH'b0'],             ['{M4_VC_HIGH{1'b1}}'],              1)
         m4_define_csr(['pktrd'],      12'h80b,    ['M4_WORD_HIGH, DATA, 0'],          ['M4_WORD_HIGH'b0'],           ['{M4_WORD_HIGH{1'b0}}'],            RO)
         m4_define_csr(['pktinfo'],    12'h80c,    ['m4_eval(M4_CORE_INDEX_HIGH + 3), SRC, 3, MID, 2, AVAIL, 1, COMP, 0'],
                                                                            ['m4_eval(M4_CORE_INDEX_HIGH + 3)'b100'], ['m4_eval(M4_CORE_INDEX_HIGH + 3)'b0'], 1)
         // TODO: Unimplemented: pkthead, pktfree, pktmax, pktmin.
      '])
   '])

   // ==========================
   // ISA Code Generation Macros
   // ==========================
   //
   
   // -------------------------------------------------
   // TODO: Here are some thoughts for providing generic instruction definitions that can be used across all ISAs, even outside of CPUs (and would improve upon RISC-V macros).
   //       None of this is implemented, just sketching.
   //
   // Define fields. Fields are extracted from instructions.
   // Fields have a name, an extraction spec, and a condition under which the field may be defined.
   // Extraction specs specify where the bits come from, and the select is a mutually-exclusive condition under which the extraction spec applies. E.g.:
   //
   //   m4_instr_field(['my_instr'], ['imm'], (18, 0), ['$i_type || $j_type'], ['(31, 18), (12, 8)'])
   //
   // defines $my_instr_imm_field[18:0] that comes from {$my_instr_instr[31:18], $my_instr_instr[13:0]}.
   // ($i_type || $j_type) is verified to assert for all instructions which define this field. If this string begins with "?" is is used as the when expression
   // for $my_instr_imm_field, otherwise, a generated instruction-granular condition is used.
   //
   // As an improvement, fields can be specified with different extraction specs for different instructions. E.g.:
   //
   //   m4_instr_field(['my_instr'], ['imm'], (18, 0), ['$i_type || $j_type'], ['(31, 18), (12, 8)'], ['i'], ['$b_type'], ['(31, 15), 2'b00'], ['b'])
   //
   // defines $my_instr_imm_field[18:0] that comes from {$my_instr_instr[31:18], $my_instr_instr[13:0]}, or, if $b_type, {$my_instr_instr[31:15], 2'b00}.
   // Also defined will be $my_instr_imm_i_field[18:0] and $my_instr_imm_b_field[18:0].
   //
   // Assembly instruction formats can be defined. E.g.:
   //
   //   m4_asm_format(['my_instr'], ['op_imm'], ['/?(.ovf)\s+ r(\d+)\s=\sr(\d+), (\d+)/, FLAG, ovf, D, rd, D, r1, D, imm'])  // WIP
   //
   // specifies a format that might be used to assemble an ADD instruction. E.g.:
   //
   //   m4_asm(['my_instr'], ['ADD.ovf r3 = r10, 304'])
   //
   // "FLAG" specifies a value that if present is a 1-bit, else 0-bit.
   // "D" specifies a decimal value.
   // Instructions are assembled based on field definitions and instruction definitions.
   //
   // Instructions are then defined. e.g.:
   //
   //   m4_define_instr(['my_instr'], ['JMP'], ['op_jump'], ['imm(18,5)'], ['r1'], ['imm(4,0)=xxx00'], ['11000101'])
   //
   // defines a JMP instruction.
   // The fields of the instruction, msb-to-lsb, are listed following the mnemonic and asm_format.
   // Fields containing only 01x chars are used to decode the instruction, producing $is_<mnemonic>_inst.
   // Fields containing "=" similarly, provided bits that are required of the instruction.
   // Fields can have a bit range, in which case fields by the same name will be joined appropriately.
   // Fields are verified to be defined in positions for which the field has a corresponding extraction spec.
   // The assembly type is verified to define exactly the necessary fields.
   //
   // Multiple instructions can share the same execution logic, producing a single result value.
   // To do this for JMP and RET, rather than ['JMP'] and ['RET'] args, provide, e.g., ['JMP:JUMP'], and ['RET:JUMP'].
   // A "JUMP" result will be selected for either instruction.
   //
   // ISA-specific versions of the above macros can be created that drop the first argument.
   // 
   // --------------------------------------------------
   
   m4_case(M4_ISA, ['MINI'], ['
      // An out-of-place correction for the fact that in Mini-CPU, instruction
      // addresses are to different memory than data, and the memories have different widths.
      m4_define_vector(['M4_PC'], 10, 0)
      
   '], ['RISCV'], ['
      
      // --------------------------------------
      // Associate each op5 value with an instruction type.
      // --------------------------------------
      
      // TODO:
      // We construct M4_OP5_XXXXX_TYPE, and verify each instruction against that.
      // Instruction fields are constructed and valid based on op5.
      //...
      // TO UPDATE:
      // We construct localparam INSTR_TYPE_X_MASK as a mask, one bit per op5 indicating whether the op5 is of the type.
      // Instantiated recursively for each instruction type.
      // Initializes m4_instr_type_X_mask_expr which will build up a mask, one bit per op5.
      m4_define(['m4_instr_types'],
                ['m4_ifelse(['$1'], [''], [''],
                            ['m4_define(['m4_instr_type_$1_mask_expr'], ['0'])m4_instr_types(m4_shift($@))'])'])
      // Instantiated recursively for each instruction type in \SV_plus context after characterizing each type.
      // Declares localparam INSTR_TYPE_X_MASK as m4_instr_type_X_mask_expr.
      m4_define(['m4_instr_types_sv'],
                ['m4_ifelse(['$1'], [''], [''],
                            ['localparam INSTR_TYPE_$1_MASK = m4_instr_type_$1_mask_expr; m4_instr_types_sv(m4_shift($@))'])'])
      // Instantiated recursively for each instruction type in \SV_plus context to decode instruction type.
      // Creates "assign $$is_x_type = INSTR_TYPE_X_MASK[$raw_op5];" for each type.
      m4_define(['m4_types_decode'],
                ['m4_ifelse(['$1'], [''], [''],
                            ['['assign $$is_']m4_translit(['$1'], ['A-Z'], ['a-z'])['_type = INSTR_TYPE_$1_MASK[$raw_op5]; ']m4_types_decode(m4_shift($@))'])'])
      // Instantiated for each op5 in \SV_plus context.
      m4_define(['m4_op5'],
                ['m4_define(['M4_OP5_$1_TYPE'], $2)['localparam [4:0] OP5_$3 = 5'b$1;']m4_define(['m4_instr_type_$2_mask_expr'], m4_quote(m4_instr_type_$2_mask_expr)[' | (1 << 5'b$1)'])'])
      
      
      // --------------------------------
      // Characterize each instruction mnemonic
      // --------------------------------
      
      // Each instruction is defined by instantiating m4_instr(...), e.g.: 
      //    m4_instr(B, 32, I, 11000, 000, BEQ)
      // which instantiates an instruction-type-specific macro, e.g.:
      //    m4_instrB(32, I, 11000, 000, BEQ)
      // which produces (or defines macros for):
      //   o instruction decode logic ($is_<mnemonic>_instr = ...;)
      //   o for debug, an expression to produce the MNEMONIC.
      //   o result MUX expression to select result of the appropriate execution expression
      //   o $illegal_instruction expression
      //   o localparam definitions for fields
      //   o m4_asm(<MNEMONIC>, ...) to assemble instructions to their binary representations
      
      // Return 1 if the given instruction is supported, [''] otherwise.
      // m4_instr_supported(<args-of-m4_instr(...)>)
      m4_define(['m4_instr_supported'],
                ['m4_ifelse(M4_EXT_$3, 1,
                            ['m4_ifelse(M4_WORD_CNT, ['$2'], 1, [''])'],
                            [''])'])
      
      // Instantiated (in \SV_plus context) for each instruction.
      // m4_instr(<instr-type-char(s)>, <type-specific-args>)
      // This instantiates m4_instr<type>(type-specific-args>)
      m4_define_hide(['m4_instr'],
                     ['// check instr type
                       // TODO: (IMMEDIATELY) Re-enable 2 lines below.
                       //m4_ifelse(M4_OP5_$4_TYPE, $1, [''],
                       //          ['m4_errprint(['Instruction ']m4_argn($#, $@)[''s type ($1) is inconsistant with its op5 code ($4) of type ']M4_OP5_$4_TYPE[' on line ']m4___line__[' of file ']m4_FILE.m4_new_line)'])
                       // if instrs extension is supported and instr is for the right machine width, "
                       m4_ifelse(m4_instr_supported($@), 1, ['m4_show(['localparam [6:0] ']']m4_argn($#, $@)['['_INSTR_OPCODE = 7'b$4['']11;m4_instr$1(m4_shift($@))'])'],
                                 [''])'])
      
      
      // Decode logic for instructions with various opcode/func bits that dictate the mnemonic.
      // (This would be easier if we could use 'x', but Yosys doesn't support ==?/!=? operators.)

      // Helpers to deal with "rm" cases:
      m4_define(['m4_op5_and_funct3'],
                ['$raw_op5 == 5'b$3 m4_ifelse($4, ['rm'], [''], ['&& $raw_funct3 == 3'b$4'])'])
      m4_define(['m4_funct3_localparam'],
                ['m4_ifelse(['$2'], ['rm'], [''], [' localparam [2:0] $1_INSTR_FUNCT3 = 3'b$2;'])'])
      // m4_asm_<MNEMONIC> output for funct3 or rm, returned in unquoted context so arg references can be produced. 'rm' is always the last m4_asm_<MNEMONIC> arg (m4_arg(#)).
      //   Args: $1: MNEMONIC, $2: funct3 field of instruction definition (or 'rm')
      m4_define(['m4_asm_funct3'], ['['m4_ifelse($2, ['rm'], ['3'b']m4_argn(']m4_arg(#)[', m4_echo(']m4_arg(@)[')), ['$1_INSTR_FUNCT3'])']'])

      // Opcode + funct3 + funct7 (R-type). $@ as for m4_instrX(..), $7: MNEMONIC, $8: number of bits of leading bits of funct7 to interpret. If 5, for example, use the term funct5.
      m4_define(['m4_instr_funct7'],
                ['m4_instr_decode_expr($7, m4_op5_and_funct3($@)[' && $raw_funct7'][6:m4_eval(7-$8)][' == $8'b$5'], $7)m4_funct3_localparam(['$7'], ['$4'])[' localparam [6:0] $7_INSTR_FUNCT$8 = $8'b$5;']'])
      // For cases w/ extra shamt bit that cuts into funct7.
      m4_define(['m4_instr_funct6'],
                ['m4_instr_decode_expr($7, m4_op5_and_funct3($@)[' && $raw_funct7[6:1] == 6'b$5'], $7)m4_funct3_localparam(['$7'], ['$4'])[' localparam [6:0] $7_INSTR_FUNCT6 = 6'b$5;']'])
      // Opcode + funct3 + func7[1:0] (R4-type)
      m4_define(['m4_instr_funct2'],
                ['m4_instr_decode_expr($6, m4_op5_and_funct3($@)[' && $raw_funct7[1:0] == 2'b$5'], $6)m4_funct3_localparam(['$6'], ['$4'])[' localparam [1:0] $6_INSTR_FUNCT2 = 2'b$5;']'])
      // Opcode + funct3 + funct7[6:2] (R-type where funct7 has two lower bits that do not distinguish mnemonic.)
      m4_define(['m4_instr_funct5'],
                ['m4_instr_decode_expr($6, m4_op5_and_funct3($@)[' && $raw_funct7[6:2] == 5'b$5'], $6)m4_funct3_localparam(['$6'], ['$4'])[' localparam [4:0] $6_INSTR_FUNCT5 = 5'b$5;']'])
      // Opcode + funct3
      m4_define(['m4_instr_funct3'],
                ['m4_instr_decode_expr($5, m4_op5_and_funct3($@), $6)m4_funct3_localparam(['$5'], ['$4'])'])
      // Opcode
      m4_define(['m4_instr_no_func'],
                ['m4_instr_decode_expr($4, ['$raw_op5 == 5'b$3'])'])
      
      // m4_instr_decode_expr macro, to extend the following definitions to reflect the given instruction <mnemonic>:
      m4_define(['m4_decode_expr'], [''])          // instructiton decode: $is_<mnemonic>_instr = ...; ...
      m4_define(['m4_rslt_mux_expr'], [''])        // result combining expr.: ({32{$is_<mnemonic>_instr}} & $<mnemonic>_rslt) | ...
      m4_define(['m4_illegal_instr_expr'], [''])   // $illegal instruction exception expr: && ! $is_<mnemonic>_instr ...
      m4_define(['m4_mnemonic_expr'], [''])        // $is_<mnemonic>_instr ? "<MNEMONIC>" : ...
      m4_define_hide(
         ['m4_instr_decode_expr'],
         ['m4_define(
              ['m4_decode_expr'],
              m4_dquote(m4_decode_expr['$is_']m4_translit($1, ['A-Z'], ['a-z'])['_instr = $2;m4_plus_new_line   ']))
           m4_ifelse(['$3'], ['no_dest'],
              [''],
              ['m4_define(
                 ['m4_rslt_mux_expr'],
                 m4_dquote(m4_rslt_mux_expr[' |']['m4_plus_new_line       ({']M4_WORD_CNT['{$is_']m4_translit($1, ['A-Z'], ['a-z'])['_instr}} & $']m4_translit($1, ['A-Z'], ['a-z'])['_rslt)']))'])
           m4_define(
              ['m4_illegal_instr_expr'],
              m4_dquote(m4_illegal_instr_expr[' && ! $is_']m4_translit($1, ['A-Z'], ['a-z'])['_instr']))
           m4_define(
              ['m4_mnemonic_expr'],
              m4_dquote(m4_mnemonic_expr['$is_']m4_translit($1, ['A-Z'], ['a-z'])['_instr ? "$1']m4_substr(['          '], m4_len(['$1']))['" : ']))'])
      
      // The first arg of m4_instr(..) is a type, and a type-specific macro is invoked. Types are those defined by RISC-V, plus:
      //   R2: R-type with a hard-coded rs2 value. (assuming illegal instruction exception should be thrown for wrong value--not clear in RISC-V spec)
      //   If: I-type with leading bits of imm[11:...] used as function bits.
      // Unique to each instruction type, eg:
      //   m4_instr(U, 32, I, 01101,      LUI)
      //   m4_instr(J, 32, I, 11011,      JAL)
      //   m4_instr(B, 32, I, 11000, 000, BEQ)
      //   m4_instr(S, 32, I, 01000, 000, SB)
      //   m4_instr(I, 32, I, 00100, 000, ADDI)
      //   m4_instr(If, 64, I, 00100, 101, 000000, SRLI)  // (imm[11:6] are used like funct7[6:1] and must be 000000)
      //   m4_instr(R, 32, I, 01100, 000, 0000000, ADD)
      //   m4_instr(R4, 32, F, 10000, rm, 10, FMADD.D)
      //   m4_instr(R2, 32, F, 10100, rm, 0101100, 00000, FSQRT.S)
      //   m4_instr(R2, 32, A, 01011, 010, 00010, 00000, LR.W)  // (5 bits for funct7 for all "A"-ext instrs)
      //   m4_instr(R, 32, A, 01011, 010, 00011, SC.W)          //   "

      // This defines assembler macros as follows. Fields are ordered rd, rs1, rs2, imm:
      //   I: m4_asm_ADDI(r4, r1, 0),
      //   R: m4_asm_ADD(r4, r1, r2),
      //   R2: m4_asm_FSQRT.S(r4, r1, 000),  // rm == 000
      //   R4: m4_asm_FMADD.S(r4, r1, r2, r3, 000),  // rm == 000
      //   S: m4_asm_SW(r1, r2, 100),  // Store r13 into [r10] + 4
      //   B: m4_asm_BLT(r1, r2, 1000), // Branch if r1 < r2 to PC + 13'b1000 (where lsb = 0)
      //   For "A"-extension instructions, an additional final arg is REQUIRED to provide 2 binary bits for aq and rl.
      // Macro definitions include 2 parts:
      //   o Hardware definitions: m4_instr_<mnemonic>($@)
      //   o Assembler definition of m4_asm_<MNEMONIC>: m4_define(['m4_asm_<MNEMONIC>'], ['m4_asm_instr_str(...)'])
      m4_define(['m4_instrI'], ['m4_instr_funct3($@)m4_define(['m4_asm_$5'], ['m4_asm_instr_str(I, ['$5'], $']['@){12'b']m4_arg(3)[', m4_asm_reg(']m4_arg(2)['), $5_INSTR_FUNCT3, m4_asm_reg(']m4_arg(1)['), $5_INSTR_OPCODE}'])'])
      m4_define(['m4_instrIf'], ['m4_instr_funct7($@, ['$6'], m4_len($5))m4_define(['m4_asm_$6'], ['m4_asm_instr_str(I, ['$6'], $']['@){['$6_INSTR_FUNCT']m4_len($5)[', ']m4_eval(12-m4_len($5))'b']m4_arg(3)[', m4_asm_reg(']m4_arg(2)['), $6_INSTR_FUNCT3, m4_asm_reg(']m4_arg(1)['), $6_INSTR_OPCODE}'])'])
      // TODO: Convert all R types to RR, adding funct7 values.
      //       Delete m4_instrR below.
      //       Rename all RR to R.
      //       Uncomment 2 lines under "// check instr type", above.
      m4_define(['m4_instrRR'], ['m4_instr_funct7($@, ['$6'], m4_ifelse($2, ['A'], 5, 7))m4_define(['m4_asm_$6'], ['m4_asm_instr_str(R, ['$6'], $']['@){m4_ifelse($2, ['A'], ['$6_INSTR_FUNCT5, ']']m4_arg(2)['[''], ['$6_INSTR_FUNCT7']), m4_asm_reg(']m4_arg(3)['), m4_asm_reg(']m4_arg(2)['), ']m4_asm_funct3(['$6'], ['$4'])[', m4_asm_reg(']m4_arg(1)['), $6_INSTR_OPCODE}'])'])
      m4_define(['m4_instrR'], ['m4_instr_funct3($@)m4_define(['m4_asm_$5'], ['m4_asm_instr_str(R, ['$5'], $']['@){7'b['']m4_ifelse(']m4_arg(4)[', [''], 0, ']m4_arg(4)['), m4_asm_reg(']m4_arg(3)['), m4_asm_reg(']m4_arg(2)['), ']m4_asm_funct3(['$5'], ['$4'])[', m4_asm_reg(']m4_arg(1)['), $5_INSTR_OPCODE}'])'])
      m4_define(['m4_instrR2'], ['m4_instr_funct7($@, 7)m4_define(['m4_asm_$7'], ['m4_asm_instr_str(R, ['$7'], $']['@){m4_ifelse($2, ['A'], ['$7_INSTR_FUNCT5, ']']m4_arg(2)['[''], ['$7_INSTR_FUNCT7']), 5'b$6, m4_asm_reg(']m4_arg(2)['), ']m4_asm_funct3(['$7'], ['$4'])[', m4_asm_reg(']m4_arg(1)['), $7_INSTR_OPCODE}'])'])
      m4_define(['m4_instrR4'], ['m4_instr_funct2($@)m4_define(['m4_asm_$6'], ['m4_asm_instr_str(R, ['$6'], $']['@){m4_asm_reg(']m4_arg(4)['), $6_INSTR_FUNCT2, m4_asm_reg(']m4_arg(3)['), m4_asm_reg(']m4_arg(2)['), ']m4_asm_funct3(['$6'], ['$4'])[', m4_asm_reg(']m4_arg(1)['), $6_INSTR_OPCODE}'])'])
      m4_define(['m4_instrS'], ['m4_instr_funct3($@, ['no_dest'])m4_define(['m4_asm_$5'], ['m4_asm_instr_str(S, ['$5'], $']['@){m4_asm_imm_field(']m4_arg(3)[', 12, 11, 5), m4_asm_reg(']m4_arg(2)['), m4_asm_reg(']m4_arg(1)['), ']m4_asm_funct3(['$5'], ['$4'])[', m4_asm_imm_field(']m4_arg(3)[', 12, 4, 0), $5_INSTR_OPCODE}'])'])
      m4_define(['m4_instrB'], ['m4_instr_funct3($@, ['no_dest'])m4_define(['m4_asm_$5'], ['m4_asm_instr_str(B, ['$5'], $']['@){m4_asm_imm_field(']m4_arg(3)[', 13, 12, 12), m4_asm_imm_field(']m4_arg(3)[', 13, 10, 5), m4_asm_reg(']m4_arg(2)['), m4_asm_reg(']m4_arg(1)['), ']m4_asm_funct3(['$5'], ['$4'])[', m4_asm_imm_field(']m4_arg(3)[', 13, 4, 1), m4_asm_imm_field(']m4_arg(3)[', 13, 11, 11), $5_INSTR_OPCODE}'])'])
      m4_define(['m4_instrJ'], ['m4_instr_no_func($@)'])// TODO: asm
      m4_define(['m4_instrU'], ['m4_instr_no_func($@)'])// TODO: asm
      m4_define(['m4_instr_'], ['m4_instr_no_func($@)'])

      // For each instruction type.
      // Declare localparam[31:0] INSTR_TYPE_X_MASK, initialized to 0 that will be given a 1 bit for each op5 value of its type.
      m4_define(['m4_instr_types_args'], ['I, R, R2, R4, S, B, J, U, _'])
      m4_instr_types(m4_instr_types_args)


      // Instruction fields (User ISA Manual 2.2, Fig. 2.2)
      m4_define_fields(['M4_INSTR'], 32, FUNCT7, 25, RS2, 20, RS1, 15, FUNCT3, 12, RD, 7, OP5, 2, OP2, 0)


      //=========
      // Specifically for assembler.

      // An 20-bit immediate binary zero string.
      m4_define(['m4_asm_imm_zero'], ['00000000000000000000'])
      // Zero-extend to n bits. E.g. m4_asm_zero_ext(1001, 7) => 0001001
      m4_define(['m4_asm_zero_ext'], ['m4_substr(m4_asm_imm_zero, 0, m4_eval($2 - m4_len($1)))$1'])
      // Extract bits from a binary immediate value.
      // m4_asm_imm_field(binary-imm, imm-length, max-bit, min-bit)
      // E.g. m4_asm_imm_field(101011, 17, 7, 3) => 5'b00101
      m4_define(['m4_asm_imm_field'], ['m4_eval($3 - $4 + 1)'b['']m4_substr(m4_asm_zero_ext($1, $2), m4_eval($2 - $3 - 1), m4_eval($3 - $4 + 1))'])
      // Register operand.
      m4_define(['m4_asm_reg'], ['m4_ifelse(m4_substr(['$1'], 0, 1), ['r'], [''], ['m4_errprint(['$1 passed to register field.'])'])5'd['']m4_substr(['$1'], 1)'])

      // For debug, a string for an asm instruction.
      m4_define(['m4_asm_mem_expr'], [''])
      // m4_asm_instr_str(<type>, <mnemonic>, <m4_asm-args>)
      m4_define(['m4_asm_instr_str'], ['m4_pushdef(['m4_str'], ['($1) $2 m4_shift(m4_shift($@))'])m4_define(['m4_asm_mem_expr'],
                                                       m4_dquote(m4_asm_mem_expr[' "']m4_str['']m4_substr(['                                        '], m4_len(m4_quote(m4_str)))['", ']))m4_popdef(['m4_str'])'])
      // Assemble an instruction.
      // m4_asm(FOO, ...) defines m4_inst# as m4_asm_FOO(...), counts instructions in M4_NUM_INSTRS ,and outputs a comment.
      m4_define(['m4_asm'], ['m4_define(['m4_instr']M4_NUM_INSTRS, ['m4_asm_$1(m4_shift($@))'])['/']['/ Inst #']M4_NUM_INSTRS: $@m4_define(['M4_NUM_INSTRS'], m4_eval(M4_NUM_INSTRS + 1))'])

      //=========
   '], ['MIPSI'], ['
   '], ['POWER'], ['
   '], ['DUMMY'], ['
   '])
   
   // Macro initialization.
   m4_define(['M4_NUM_INSTRS'], 0)


   // Define m4+module_def macro to be used as a region line providing the module definition, either inside makerchip,
   // or outside for formal.
   m4_define(['m4_module_def'],
             ['m4_ifelse(M4_FORMAL, 0,
                         ['\SV['']m4_new_line['']m4_makerchip_module'],
                         ['   module warpv(input logic clk,
            input logic reset,
            output logic failed,
            output logic passed,
            output logic  rvfi_valid, 
            output logic [31:0] rvfi_insn,
            output logic [63 : 0] rvfi_order,
            output logic rvfi_halt,
            output logic rvfi_trap,       
            output logic rvfi_halt,       
            output logic rvfi_intr,       
            output logic [4: 0] rvfi_rs1_addr,   
            output logic [4: 0] rvfi_rs2_addr,   
            output logic [31: 0] rvfi_rs1_rdata,  
            output logic [31: 0] rvfi_rs2_rdata,  
            output logic [4: 0] rvfi_rd_addr,    
            output logic [31: 0] rvfi_rd_wdata,   
            output logic [31:0] rvfi_pc_rdata,   
            output logic [31:0] rvfi_pc_wdata ,   
            output logic [31:0] rvfi_mem_addr,   
            output logic [3: 0] rvfi_mem_rmask,  
            output logic [3: 0] rvfi_mem_wmask,  
            output logic [31: 0] rvfi_mem_rdata,  
            output logic [31: 0] rvfi_mem_wdata);'])'])
'])
\SV





//============================//
//                            //
//         MINI-CPU           //
//                            //
//============================//
                         
\TLV mini_cnt10_prog()
   \SV_plus
      m4_define(['M4_NUM_INSTRS'], 13)
      
      // The program in an instruction memory.
      logic [M4_INSTR_RANGE] instrs [0:M4_NUM_INSTRS-1];
      
      // /=====================\
      // | Count to 10 Program |
      // \=====================/
      //
      // (The program I wrote in the language I created in the CPU I wrote in a language I created.)
      
      // Add 1,2,3,...,9 (in that order).
      // Store incremental results in memory locations 1..9. (1, 3, 6, 10, ..., 45)
      //
      // Regs:
      // b: cnt
      // c: nine
      // d: out
      // e: tmp
      // f: offset
      // g: store addr
      
      assign instrs = '{
         "g=0~0", //     store_addr = 0
         "b=0~1", //     cnt = 1
         "c=1~1", //     nine = 9
         "d=0~0", //     out = 0
         "f=0-6", //     offset = -6
         "d=d+b", //  -> out += cnt
         "b=b+1", //     cnt ++
         "g=g+1", //     store_addr++
         "0=d}g", //     store out at store_addr
         "e=c-b", //     tmp = nine - cnt
         "p=f?e", //  ^- branch back if tmp >= 0
         "e=0{c", //     load the final value into tmp
         "P=0-1"  //     TERMINATE by jumping to -1
      };

\TLV mini_imem(_prog_name)
   m4+indirect(['mini_']_prog_name['_prog'])
   |fetch
      /instr
         @M4_FETCH_STAGE
            ?$fetch
               $raw[M4_INSTR_RANGE] = *instrs\[$Pc[m4_eval(M4_PC_MIN + m4_width(M4_NUM_INSTRS-1) - 1):M4_PC_MIN]\];

\TLV mini_gen()
   // No M4-generated code for mini.


// Decode logic for Mini-CPU.
// Context: within pipestage
// Inputs:
//    $raw[11:0]
// Outputs:
//    $ld
//    $st
//    $illegal
//    $conditional_branch
//    ...
\TLV mini_decode()
   // Characters
   $dest_char[7:0] = $raw[39:32];
   /src[2:1]
      $char[7:0] = (#src == 1) ? /instr$raw[M4_INSTR_SRC1_CHAR_RANGE] : /instr$raw[M4_INSTR_SRC2_CHAR_RANGE];
   $op_char[7:0] = $raw[15:8];

   // Dest
   $dest_is_reg = ($dest_char >= "a" && $dest_char <= "h") || $second_issue;
   $dest_reg_valid = $dest_is_reg;
   $fetch_instr_dest_reg[7:0] = $dest_char - "a";
   $dest_reg[2:0] = $second_issue ? /orig_inst$dest_reg : $fetch_instr_dest_reg[2:0];
   $jump = $dest_char == "P";
   $branch = $dest_char == "p";
   $no_dest = $dest_char == "0";
   $write_pc = $jump || $branch;
   $div_mul = 1'b0;
   $dest_valid = $write_pc || $dest_is_reg;
   $illegal_dest = !($dest_is_reg || 
                     (($branch || $jump || $no_dest) && ! $ld));  // Load must have reg dest.

   /src[*]
      // Src1
      $is_reg = $char >= "a" && $char <= "h";
      $reg_tmp[7:0] = $char - "a";
      $reg[2:0] = $reg_tmp[2:0];
      $is_imm = $char >= "0" && $char < "8";
      $imm_tmp[7:0] = $char - "0";
      $imm_value[11:0] = {9'b0, $imm_tmp[2:0]};
      $illegal = !($is_reg || $is_imm);

   // Opcode:
   /op
      $char[7:0] = /instr$op_char;
      // Arithmetic
      $add = $char == "+";
      $sub = $char == "-";
      $mul = $char == "*";
      $div = $char == "/";
      // Compare and bool (w/ 1 bit rslt)
      $eq = $char == "=";
      $ne = $char == "!";
      $lt = $char == "<";
      $gt = $char == ">";
      $le = $char == "[";
      $ge = $char == "]";
      $and = $char == "&";
      $or = $char == "|";
      // Wide Immediate
      $wide_imm = $char == "~";
      $combine = $char == ",";
      // Conditional
      $conditional = $char == "?";
      // Memory
      $ld = $char == "{";
      $st = $char == "}";
      // Opcode classes:
      $arith = $add || $sub || $mul || $div;
      $compare = $eq || $ne || $lt || $gt || $le || $ge;
      $bitwise = $and || $or;
      $full = $arith || $bitwise || $wide_imm || $combine || $conditional;
      //$op3 = $compare || $full;
      $mem = $ld || $st;
      $illegal = !($compare || $full || $mem);
   $op_compare = /op$compare;
   $op_full = /op$full;
   $ld = /op$ld;
   $spec_ld = $ld;
   $st = /op$st;
   $illegal = $illegal_dest || (| /src[*]$illegal) || /op$illegal;

   // Branch instructions with a condition (that might be worth predicting).
   //$branch_predict = $branch && /op$conditional;
   $conditional_branch = $branch;  // All branches (any instruction with "p" dest) is conditional (where condition is that result != 0).


// Execution unit logic for Mini.
// Context: pipeline
\TLV mini_exe(@_exe_stage, @_rslt_stage)
   @M4_REG_RD_STAGE
      /src[*]
         $valid = /instr$valid_decode && ($is_reg || $is_imm);
         ?$valid
            $value[M4_WORD_RANGE] = $is_reg ? $reg_value :
                                              $imm_value;
   // Note that some result muxing is performed in @_exe_stage, and the rest in @_rslt_stage.
   @_exe_stage
      ?$op_compare
         $compare_rslt =
            /op$eq ? /src[1]$value == /src[2]$value :
            /op$ne ? /src[1]$value != /src[2]$value :
            /op$lt ? /src[1]$value < /src[2]$value :
            /op$gt ? /src[1]$value > /src[2]$value :
            /op$le ? /src[1]$value <= /src[2]$value :
            /op$ge ? /src[1]$value >= /src[2]$value :
                     1'b0;
      ?$op_full
         $op_full_rslt[11:0] =
            /op$add ? /src[1]$value + /src[2]$value :
            /op$sub ? /src[1]$value - /src[2]$value :
            /op$mul ? /src[1]$value * /src[2]$value :
            /op$div ? /src[1]$value * /src[2]$value :
            /op$and ? /src[1]$value & /src[2]$value :
            /op$or ? /src[1]$value | /src[2]$value :
            /op$wide_imm ? {6'b0, /src[1]$value[2:0], /src[2]$value[2:0]} :
            /op$combine ? {/src[1]$value[5:0], /src[2]$value[5:0]} :
            /op$conditional ? (/src[2]$value[11] ? 12'b0 : /src[1]$value) :
                              12'b0;
      ?$valid_st
         $st_value[M4_WORD_RANGE] = /src[1]$value;

      $valid_ld_st = $valid_ld || $valid_st;
      ?$valid_ld_st
         $addr[M4_ADDR_RANGE] = $ld ? (/src[1]$value + /src[2]$value) : /src[2]$value;
      // Always predict taken; mispredict if jump or unconditioned branch or
      //   conditioned branch with positive condition.
      ?$branch
         $taken = $rslt != 12'b0;
      $st_mask[0:0] = 1'b1;
      $non_aborting_isa_trap = 1'b0;
      $aborting_isa_trap = 1'b0;
   @_rslt_stage
      ?$dest_valid
         $rslt[11:0] =
            $second_issue ? /orig_inst$ld_value :  // (Only loads are issued twice.)
            $st ? /src[1]$value :
            $op_full ? $op_full_rslt :
            $op_compare ? {12{$compare_rslt}} :
                  12'b0;
         
      // Jump (Dest = "P") and Branch (Dest = "p") Targets.
      ?$jump
         $jump_target[M4_PC_RANGE] = $rslt[M4_PC_RANGE];
   @M4_BRANCH_TARGET_CALC_STAGE
      ?$branch
         $branch_target[M4_PC_RANGE] = $Pc + M4_PC_CNT'b1 + $rslt[M4_PC_RANGE];








//============================//
//                            //
//          RISC-V            //
//                            //
//============================//

// Define all instructions of the program (as Verilog expressions for the binary value in m4_instr#.
\TLV riscv_cnt10_prog()

   // /=====================\
   // | Count to 10 Program |
   // \=====================/
   //

   // Add 1,2,3,...,9 (in that order).
   // Store incremental results in memory locations 0..9. (1, 3, 6, 10, ...)
   //
   // Regs:
   // 1: cnt
   // 2: ten
   // 3: out
   // 4: tmp
   // 5: offset
   // 6: store addr

   m4_asm(ORI, r8, r0, 1011)
   m4_asm(ORI, r9, r0, 1010)
   m4_asm(ORI, r11, r0, 10101010)
   m4_asm(MUL, r10, r9, r8)
   //m4_asm(ORI, r0, r0, 0)
   //m4_asm(ORI, r0, r0, 0)
   //m4_asm(ORI, r0, r0, 0)
   m4_asm(MUL, r12, r11, r9)
   
   
   // m4_asm(ORI, r6, r0, 0)        //     store_addr = 0
   // m4_asm(ORI, r1, r0, 1)        //     cnt = 1
   // m4_asm(ORI, r2, r0, 1010)     //     ten = 10
   // m4_asm(ORI, r3, r0, 0)        //     out = 0
   // m4_asm(ADD, r3, r1, r3)       //  -> out += cnt
   // m4_asm(SW, r6, r3, 0)         //     store out at store_addr
   // m4_asm(ADDI, r1, r1, 1)       //     cnt ++
   // m4_asm(ADDI, r6, r6, 100)     //     store_addr++
   // m4_asm(BLT, r1, r2, 1111111110000) //  ^- branch back if cnt < 10
   // m4_asm(LW, r4, r6,   111111111100) //     load the final value into tmp
   // m4_asm(BGE, r1, r2, 1111111010100) //     TERMINATE by branching to -1

\TLV riscv_imem(_prog_name)
   m4+indirect(['riscv_']_prog_name['_prog'])
   
   // ==============
   // IMem and Fetch
   // ==============
   
   m4_ifelse_block(M4_IMPL, 1, ['
   
   // For implementation
   // ------------------
   
   // A Vivado-friendly, hard-coded instruction memory (without a separate mem file). Verilator does not like this.
   |fetch
      /instr_mem[M4_NUM_INSTRS-1:0]
         @M4_FETCH_STAGE
            // This instruction is selected from all instructions, based on #instr_mem. Not sure if this will synthesize well.
            $instr[31:0] =
               m4_forloop(['m4_instr_ind'], 0, M4_NUM_INSTRS, [' (#instr_mem == m4_instr_ind) ? m4_echo(['m4_instr']m4_instr_ind) :']) 32'b0;
      /instr
         @M4_FETCH_STAGE
            ?$fetch
               // Fetch the raw instruction from program memory.
               $raw[M4_INSTR_RANGE] = |fetch/instr_mem[$Pc[m4_eval(M4_PC_MIN + m4_width(M4_NUM_INSTRS-1) - 1):M4_PC_MIN]]$instr;
   '], M4_FORMAL, 0, ['
   
   // For simulation
   // --------------
   
   // (Vivado doesn't like this)
   \SV_plus
      // The program in an instruction memory.
      logic [M4_INSTR_RANGE] instrs [0:M4_NUM_INSTRS-1];
      logic [40*8-1:0] instr_strs [0:M4_NUM_INSTRS];
      
      assign instrs = '{
         m4_instr0['']m4_forloop(['m4_instr_ind'], 1, M4_NUM_INSTRS, [', m4_echo(['m4_instr']m4_instr_ind)'])
      };
      
      // String representations of the instructions for debug.
      assign instr_strs = '{m4_asm_mem_expr "END                                     "};

   |fetch
      /instr
         @M4_FETCH_STAGE
            ?$fetch
               $raw[M4_INSTR_RANGE] = *instrs\[$Pc[m4_eval(M4_PC_MIN + m4_width(M4_NUM_INSTRS-1) - 1):M4_PC_MIN]\];
   '], ['
   
   // For formal
   // ----------
   
   // No instruction memory.
   |fetch
      /instr
         @M4_FETCH_STAGE
            ?$fetch
               `BOGUS_USE($$raw[M4_INSTR_RANGE])
   '])


// M4-generated code.
\TLV riscv_gen()

   
   // v---------------------
   // Instruction characterization

   // M4 ugliness for instruction characterization.
   
   // For each opcode[6:2]
   // (User ISA Manual 2.2, Table 19.1)
   // Associate opcode[6:2] ([1:0] are 2'b11) with mnemonic and instruction type.
   // Instruction type is not in the table, but there seems to be a single instruction type for each of these,
   // so that is mapped here as well.
   // op5(bits, type, mnemonic)
   \SV_plus
      m4_op5(00000, I, LOAD)
      m4_op5(00001, I, LOAD_FP)
      m4_op5(00010, _, CUSTOM_0)
      m4_op5(00011, _, MISC_MEM)
      m4_op5(00100, I, OP_IMM)
      m4_op5(00101, U, AUIPC)
      m4_op5(00110, I, OP_IMM_32)
      m4_op5(00111, _, 48B1)
      m4_op5(01000, S, STORE)
      m4_op5(01001, S, STORE_FP)
      m4_op5(01010, _, CUSTOM_1)
      m4_op5(01011, R2, AMO)  // (R-type, but rs2 = const for some, based on funct7 which doesn't exist for I-type?? R-type w/ ignored R2?)
      m4_op5(01100, R, OP)
      m4_op5(01101, U, LUI)
      m4_op5(01110, R, OP_32)
      m4_op5(01111, _, 64B)
      m4_op5(10000, R4, MADD)
      m4_op5(10001, R4, MSUB)
      m4_op5(10010, R4, NMSUB)
      m4_op5(10011, R4, NMADD)
      m4_op5(10100, R2, OP_FP)  // (R-type, but rs2 = const for some, based on funct7 which doesn't exist for I-type?? R-type w/ ignored R2?)
      m4_op5(10101, _, RESERVED_1)
      m4_op5(10110, _, CUSTOM_2_RV128)
      m4_op5(10111, _, 48B2)
      m4_op5(11000, B, BRANCH)
      m4_op5(11001, I, JALR)
      m4_op5(11010, _, RESERVED_2)
      m4_op5(11011, J, JAL)
      m4_op5(11100, I, SYSTEM)
      m4_op5(11101, _, RESERVED_3)
      m4_op5(11110, _, CUSTOM_3_RV128)
      m4_op5(11111, _, 80B)
      
   \SV_plus
      m4_instr_types_sv(m4_instr_types_args)
      
   \SV_plus
      // Instruction characterization.
      // (User ISA Manual 2.2, Table 19.2)
      // instr(type,  // (this is simply verified vs. op5)
      //       |  bit-width,
      //       |  |   extension, 
      //       |  |   |  opcode[6:2],  // (aka op5)
      //       |  |   |  |      func3,   // (if applicable)
      //       |  |   |  |      |    mnemonic)
      m4_instr(U, 32, I, 01101,      LUI)
      m4_instr(U, 32, I, 00101,      AUIPC)
      m4_instr(J, 32, I, 11011,      JAL)
      m4_instr(I, 32, I, 11001, 000, JALR)
      m4_instr(B, 32, I, 11000, 000, BEQ)
      m4_instr(B, 32, I, 11000, 001, BNE)
      m4_instr(B, 32, I, 11000, 100, BLT)
      m4_instr(B, 32, I, 11000, 101, BGE)
      m4_instr(B, 32, I, 11000, 110, BLTU)
      m4_instr(B, 32, I, 11000, 111, BGEU)
      m4_instr(I, 32, I, 00000, 000, LB)
      m4_instr(I, 32, I, 00000, 001, LH)
      m4_instr(I, 32, I, 00000, 010, LW)
      m4_instr(I, 32, I, 00000, 100, LBU)
      m4_instr(I, 32, I, 00000, 101, LHU)
      m4_instr(S, 32, I, 01000, 000, SB)
      m4_instr(S, 32, I, 01000, 001, SH)
      m4_instr(S, 32, I, 01000, 010, SW)
      m4_instr(I, 32, I, 00100, 000, ADDI)
      m4_instr(I, 32, I, 00100, 010, SLTI)
      m4_instr(I, 32, I, 00100, 011, SLTIU)
      m4_instr(I, 32, I, 00100, 100, XORI)
      m4_instr(I, 32, I, 00100, 110, ORI)
      m4_instr(I, 32, I, 00100, 111, ANDI)
      m4_instr(I, 32, I, 00100, 001, SLLI)
      m4_instr(I, 32, I, 00100, 101, SRLI_SRAI)  // Two instructions distinguished by an immediate bit, treated as a single instruction.
      m4_instr(RR, 32, I, 01100, 000, 0000000, ADD)
      m4_instr(RR, 32, I, 01100, 000, 0100000, SUB)
      m4_instr(R, 32, I, 01100, 001, SLL)
      m4_instr(R, 32, I, 01100, 010, SLT)
      m4_instr(R, 32, I, 01100, 011, SLTU)
      m4_instr(R, 32, I, 01100, 100, XOR)
      m4_instr(RR, 32, I, 01100, 101, 0000000, SRL)
      m4_instr(RR, 32, I, 01100, 101, 0100000, SRA)
      m4_instr(R, 32, I, 01100, 110, OR)
      m4_instr(R, 32, I, 01100, 111, AND)
      //m4_instr(_, 32, I, 00011, 000, FENCE)
      //m4_instr(_, 32, I, 00011, 001, FENCE_I)
      //m4_instr(_, 32, I, 11100, 000, ECALL_EBREAK)  // Two instructions distinguished by an immediate bit, treated as a single instruction.
      m4_instr(I, 32, I, 11100, 001, CSRRW)
      m4_instr(I, 32, I, 11100, 010, CSRRS)
      m4_instr(I, 32, I, 11100, 011, CSRRC)
      m4_instr(I, 32, I, 11100, 101, CSRRWI)
      m4_instr(I, 32, I, 11100, 110, CSRRSI)
      m4_instr(I, 32, I, 11100, 111, CSRRCI)
      m4_instr(I, 64, I, 00000, 110, LWU)
      m4_instr(I, 64, I, 00000, 011, LD)
      m4_instr(S, 64, I, 01000, 011, SD)
      m4_instr(I, 64, I, 00100, 001, SLLI)
      m4_instr(I, 64, I, 00100, 101, SRLI_SRAI)  // Two instructions distinguished by an immediate bit, treated as a single instruction.
      m4_instr(I, 64, I, 00110, 000, ADDIW)
      m4_instr(I, 64, I, 00110, 001, SLLIW)
      m4_instr(I, 64, I, 00110, 101, SRLIW_SRAIW)  // Two instructions distinguished by an immediate bit, treated as a single instruction.
      m4_instr(R, 64, I, 01110, 000, 0000000, ADDW)
      m4_instr(R, 64, I, 01110, 000, 0100000, SUBW)
      m4_instr(R, 64, I, 01110, 001, SLLW)
      m4_instr(RR, 64, I, 01110, 101, 0000000, SRLW)
      m4_instr(RR, 64, I, 01110, 101, 0100000, SRAW)
      m4_instr(RR, 32, M, 01100, 000, 0000001, MUL)      // all muldiv set to RR for now!
      m4_instr(RR, 32, M, 01100, 001, 0000001, MULH)
      m4_instr(RR, 32, M, 01100, 010, 0000001, MULHSU)   
      m4_instr(RR, 32, M, 01100, 011, 0000001, MULHU)
      m4_instr(RR, 32, M, 01100, 100, 0000001, DIV)
      m4_instr(RR, 32, M, 01100, 101, 0000001, DIVU)
      m4_instr(RR, 32, M, 01100, 110, 0000001, REM)
      m4_instr(RR, 32, M, 01100, 111, 0000001, REMU)
      // m4_instr(R, 32, M, 01100, 000, MUL)
      // m4_instr(R, 32, M, 01100, 001, MULH)
      // m4_instr(R, 32, M, 01100, 010, MULHSU)
      // m4_instr(R, 32, M, 01100, 011, MULHU)
      // m4_instr(R, 32, M, 01100, 100, DIV)
      // m4_instr(R, 32, M, 01100, 101, DIVU)
      // m4_instr(R, 32, M, 01100, 110, REM)
      // m4_instr(R, 32, M, 01100, 111, REMU)
      m4_instr(RR, 64, M, 01110, 000, 0000001, MULW)
      m4_instr(RR, 64, M, 01110, 100, 0000001, DIVW)
      m4_instr(RR, 64, M, 01110, 101, 0000001, DIVUW)
      m4_instr(RR, 64, M, 01110, 110, 0000001, REMW)
      m4_instr(RR, 64, M, 01110, 111, 0000001, REMUW)
      // RV32A and RV64A
      // NOT IMPLEMENTED. These are distinct in the func7 field.
      // RV32F and RV64F
      // NOT IMPLEMENTED.
      // RV32D and RV64D
      // NOT IMPLEMENTED.


   // ^---------------------
   

// Logic for a single CSR.
\TLV riscv_csr(csr_name, csr_index, fields, reset_value, writable_mask, side_effects)
   //--------------
   /['']/ CSR m4_to_upper(csr_name)
   //--------------
   @M4_DECODE_STAGE
      $is_csr_['']csr_name = $raw[31:20] == csr_index;
   @M4_EXECUTE_STAGE
      // CSR update. Counting on synthesis to optimize each bit, based on writable_mask.
      // Conditionally include code for h/w and s/w write based on side_effect param (0 - s/w, 1 - s/w + h/w, RO - neither).
      m4_define(['M4_THIS_CSR_RANGE'], m4_echo(['M4_CSR_']m4_to_upper(csr_name)['_RANGE']))
      
      m4_ifelse_block(side_effects, 1, ['
      // hw_wr_mask conditioned by hw_wr.
      $csr_['']csr_name['']_hw_wr_en_mask[M4_THIS_CSR_RANGE] = {m4_echo(['M4_CSR_']m4_to_upper(csr_name)['_HIGH']){$csr_['']csr_name['']_hw_wr}} & $csr_['']csr_name['']_hw_wr_mask;
      // The CSR value, updated by side-effect writes.
      $upd_csr_['']csr_name[M4_THIS_CSR_RANGE] =
           ($csr_['']csr_name['']_hw_wr_en_mask & $csr_['']csr_name['']_hw_wr_value) | (~ $csr_['']csr_name['']_hw_wr_en_mask & $csr_['']csr_name);
      '], side_effects, 0, ['
      // The CSR value with no side-effect writes.
      $upd_csr_['']csr_name[M4_THIS_CSR_RANGE] = $csr_['']csr_name;
      '], ['
      '])
      m4_ifelse_block(side_effects, RO, ['
      '], ['
      // Next value of the CSR.
      $csr_['']csr_name['']_masked_wr_value[M4_THIS_CSR_RANGE] =
           $csr_wr_value[M4_THIS_CSR_RANGE] & writable_mask;
      <<1$csr_['']csr_name[M4_THIS_CSR_RANGE] =
           $reset ? reset_value :
           ! $commit
                  ? $upd_csr_['']csr_name :
           $is_csr_write && $is_csr_['']csr_name
                  ? $csr_['']csr_name['']_masked_wr_value | ($upd_csr_['']csr_name & ~ writable_mask) :
           $is_csr_set   && $is_csr_['']csr_name
                  ? $upd_csr_['']csr_name |   $csr_['']csr_name['']_masked_wr_value :
           $is_csr_clear && $is_csr_['']csr_name
                  ? $upd_csr_['']csr_name & ~ $csr_['']csr_name['']_masked_wr_value :
           // No CSR instruction update, only h/w side-effects.
                    $upd_csr_['']csr_name;
      '])

// Define all CSRs.
\TLV riscv_csrs(csrs)
   m4_foreach(csr, csrs, ['
   m4+riscv_csr(m4_echo(['m4_csr_']csr['_args']))
   '])

\TLV riscv_csr_logic()
   m4_ifelse_block(m4_csrs, [''], [''], ['
   // CSR write value for CSR write instructions.
   $csr_wr_value[M4_WORD_RANGE] = $raw_funct3[2] ? {27'b0, $raw_rs1} : /src[1]$reg_value;
   '])

   // Counter CSR
   //
   m4_ifelse_block(M4_NO_COUNTER_CSRS, ['1'], [''], ['
   // Count within time unit. This is not reset on writes to time CSR, so time CSR is only accurate to time unit.
   $RemainingCyclesWithinTimeUnit[m4_width(M4_CYCLES_PER_TIME_UNIT_CNT)-1:0] <=
        ($reset || $time_unit_expires) ?
               m4_width(M4_CYCLES_PER_TIME_UNIT_CNT)'d['']m4_eval(M4_CYCLES_PER_TIME_UNIT_CNT - 1) :
               $RemainingCyclesWithinTimeUnit - m4_width(M4_CYCLES_PER_TIME_UNIT_CNT)'b1;
   $time_unit_expires = !( | $RemainingCyclesWithinTimeUnit);  // reaches zero
   
   $full_csr_cycle_hw_wr_value[63:0]   = {$csr_cycleh,   $csr_cycle  } + 64'b1;
   $full_csr_time_hw_wr_value[63:0]    = {$csr_timeh,    $csr_time   } + 64'b1;
   $full_csr_instret_hw_wr_value[63:0] = {$csr_instreth, $csr_instret} + 64'b1;

   // CSR h/w side-effect write signals.
   $csr_cycle_hw_wr = 1'b1;
   $csr_cycle_hw_wr_mask[31:0] = {32{1'b1}};
   $csr_cycle_hw_wr_value[31:0] = $full_csr_cycle_hw_wr_value[31:0];
   $csr_cycleh_hw_wr = 1'b1;
   $csr_cycleh_hw_wr_mask[31:0] = {32{1'b1}};
   $csr_cycleh_hw_wr_value[31:0] = $full_csr_cycle_hw_wr_value[63:32];
   $csr_time_hw_wr = $time_unit_expires;
   $csr_time_hw_wr_mask[31:0] = {32{1'b1}};
   $csr_time_hw_wr_value[31:0] = $full_csr_time_hw_wr_value[31:0];
   $csr_timeh_hw_wr = $time_unit_expires;
   $csr_timeh_hw_wr_mask[31:0] = {32{1'b1}};
   $csr_timeh_hw_wr_value[31:0] = $full_csr_time_hw_wr_value[63:32];
   $csr_instret_hw_wr = $commit;
   $csr_instret_hw_wr_mask[31:0] = {32{1'b1}};
   $csr_instret_hw_wr_value[31:0] = $full_csr_instret_hw_wr_value[31:0];
   $csr_instreth_hw_wr = $commit;
   $csr_instreth_hw_wr_mask[31:0] = {32{1'b1}};
   $csr_instreth_hw_wr_value[31:0] = $full_csr_instret_hw_wr_value[63:32];
   '])
   
   // For multicore CSRs:
   m4_ifelse_block(m4_eval(M4_CORE_CNT > 1), ['1'], ['
   $csr_pktavail_hw_wr = 1'b0;
   $csr_pktavail_hw_wr_mask[M4_VC_RANGE]  = {M4_VC_HIGH{1'b1}};
   $csr_pktavail_hw_wr_value[M4_VC_RANGE] = {M4_VC_HIGH{1'b1}};
   $csr_pktcomp_hw_wr = 1'b0;
   $csr_pktcomp_hw_wr_mask[M4_VC_RANGE]   = {M4_VC_HIGH{1'b1}};
   $csr_pktcomp_hw_wr_value[M4_VC_RANGE]  = {M4_VC_HIGH{1'b1}};
   //$csr_pktrd_hw_wr = 1'b0;
   //$csr_pktrd_hw_wr_mask[M4_WORD_RANGE]   = {M4_WORD_HIGH{1'b1}};
   //$csr_pktrd_hw_wr_value[M4_WORD_RANGE]  = {M4_WORD_HIGH{1'b0}};
   $csr_pktinfo_hw_wr = 1'b0;
   $csr_pktinfo_hw_wr_mask[M4_CSR_PKTINFO_RANGE]  = {M4_CSR_PKTINFO_HIGH{1'b1}};
   $csr_pktinfo_hw_wr_value[M4_CSR_PKTINFO_RANGE] = {M4_CSR_PKTINFO_HIGH{1'b0}};
   '])

// These are expanded in a separate TLV  macro because multi-line expansion is a no-no for line tracking.
// This keeps the implications contained.
\TLV riscv_decode_expr()
   m4_echo(m4_decode_expr)

\TLV riscv_rslt_mux_expr()
   $rslt[M4_WORD_RANGE] =
       $second_issue ? /orig_inst$late_rslt :
                       M4_WORD_CNT'b0['']m4_echo(m4_rslt_mux_expr);

\TLV riscv_decode()
   // TODO: ?$valid_<stage> conditioning should be replaced by use of m4_prev_instr_valid_through(..).
   ?$valid_decode

      // =================================

      // Extract fields of $raw (instruction) into $raw_<field>[x:0].
      m4_into_fields(['M4_INSTR'], ['$raw'])
      `BOGUS_USE($raw_op2)  // Delete once it's used.
      // Extract immediate fields into type-specific signals.
      // (User ISA Manual 2.2, Fig. 2.4)
      $raw_i_imm[31:0] = {{21{$raw[31]}}, $raw[30:20]};
      $raw_s_imm[31:0] = {{21{$raw[31]}}, $raw[30:25], $raw[11:7]};
      $raw_b_imm[31:0] = {{20{$raw[31]}}, $raw[7], $raw[30:25], $raw[11:8], 1'b0};
      $raw_u_imm[31:0] = {$raw[31:12], {12{1'b0}}};
      $raw_j_imm[31:0] = {{12{$raw[31]}}, $raw[19:12], $raw[20], $raw[30:21], 1'b0};
      // Extract other type/instruction-specific fields.
      $raw_shamt[6:0] = $raw[26:20];
      $raw_aq = $raw[26];
      $raw_rl = $raw[25];
      $raw_rs3[4:0] = $raw[31:27];
      $raw_rm[2:0] = $raw_funct3;
      `BOGUS_USE($raw_shamt $raw_aq $raw_rl $raw_rs3 $raw_rm)  // Avoid "unused" messages. Remove these as they become used.

      // Instruction type decode
      \SV_plus
         m4_types_decode(m4_instr_types_args)

      // Instruction decode.
      m4+riscv_decode_expr()
      
      m4_ifelse_block(M4_EXT_M, 1, ['
      // Instruction requires integer mul/div unit and is long-latency.
      $div_mul = $is_mul_instr ||
                 $is_mulh_instr ||
                 $is_mulhsu_instr ||
                 $is_mulhu_instr ||
                 $is_div_instr ||
                 $is_divu_instr ||
                 $is_rem_instr ||
                 $is_remu_instr;
      /*$div_mul = $is_div_instr ||
                 $is_divu_instr ||
                 $is_rem_instr ||
                 $is_remu_instr;*/
      $multype_instr = $is_mul_instr ||
                       $is_mulh_instr ||
                       $is_mulhsu_instr ||
                       $is_mulhu_instr;             
      '], ['
      $div_mul = 1'b0;
      $multype_instr = 1'b0;
      '])

      // Some I-type instructions have a funct7 field rather than immediate bits, so these must factor into the illegal instruction expression explicitly.
      $illegal_itype_with_funct7 = ( $is_srli_srai_instr m4_ifelse(M4_WORD_CNT, 64, ['|| $is_srliw_sraiw_instr']) ) && | {$raw_funct7[6], $raw_funct7[4:0]};
      $illegal = $illegal_itype_with_funct7['']m4_illegal_instr_expr;
      $conditional_branch = $is_b_type;
   $jump = $is_jal_instr;  // "Jump" in RISC-V means unconditional. (JALR is a separate redirect condition.)
   $branch = $is_b_type;
   $indirect_jump = $is_jalr_instr;
   ?$valid_decode
      $ld = $raw[6:3] == 4'b0;
      $st = $is_s_type;
      $ld_st = $ld || $st;
      $ld_st_word = $ld_st && ($raw_funct3[1] == 1'b1);
      $ld_st_half = $ld_st && ($raw_funct3[1:0] == 2'b01);
      //$ld_st_byte = $ld_st && ($raw_funct3[1:0] == 2'b00);
      `BOGUS_USE($is___type $is_u_type)

      // Output signals.
      /src[2:1]
         // Reg valid for this source, based on instruction type.
         $is_reg = /instr$is_r_type || /instr$is_r4_type || (/instr$is_i_type && (#src == 1)) || /instr$is_r2_type || /instr$is_s_type || /instr$is_b_type;
         $reg[M4_REGS_INDEX_RANGE] = (#src == 1) ? /instr$raw_rs1 : /instr$raw_rs2;
           
      // For debug.
      $mnemonic[10*8-1:0] = m4_mnemonic_expr "ILLEGAL   ";
      `BOGUS_USE($mnemonic)
   // Condition signals must not themselves be conditioned (currently).
   $dest_reg[M4_REGS_INDEX_RANGE] = $second_issue ? /orig_inst$dest_reg : $raw_rd;
   $dest_reg_valid = (($valid_decode && ! $is_s_type && ! $is_b_type) || $second_issue) &&
                     | $dest_reg;   // r0 not valid.
   // Actually load.
   $spec_ld = $valid_decode && $ld;
   
   // CSR decode.
   $is_csr_write = $is_csrrw_instr || $is_csrrwi_instr;
   $is_csr_set   = $is_csrrs_instr || $is_csrrsi_instr;
   $is_csr_clear = $is_csrrc_instr || $is_csrrci_instr;
   $is_csr_instr = $is_csr_write ||
                   $is_csr_set   ||
                   $is_csr_clear;
   $valid_csr = m4_valid_csr_expr;
   $csr_trap = $is_csr_instr && ! $valid_csr;

\TLV riscv_exe(@_exe_stage, @_rslt_stage)
   @M4_BRANCH_TARGET_CALC_STAGE
      ?$valid_decode_branch
         $branch_target[M4_PC_RANGE] = $Pc[M4_PC_RANGE] + $raw_b_imm[M4_PC_RANGE];
         $misaligned_pc = | $raw_b_imm[1:0];
      ?$jump  // (JAL, not JALR)
         $jump_target[M4_PC_RANGE] = $Pc[M4_PC_RANGE] + $raw_j_imm[M4_PC_RANGE];
         $misaligned_jump_target = $raw_j_imm[1];
   @_exe_stage
      // Execution.
      $valid_exe = $valid_decode; // Execute if we decoded.
      
      // Compute results for each instruction, independent of decode (power-hungry, but fast).
      ?$valid_exe
         $equal = /src[1]$reg_value == /src[2]$reg_value;
      ?$branch
         $taken =
            $is_j_type ||
            ($is_beq_instr && $equal) ||
            ($is_bne_instr && ! $equal) ||
            (($is_blt_instr || $is_bltu_instr || $is_bge_instr || $is_bgeu_instr) &&
             (($is_bge_instr || $is_bgeu_instr) ^
              (({($is_blt_instr ^ /src[1]$reg_value[M4_WORD_MAX]), /src[1]$reg_value[M4_WORD_MAX-1:0]} <
                {($is_blt_instr ^ /src[2]$reg_value[M4_WORD_MAX]), /src[2]$reg_value[M4_WORD_MAX-1:0]}
               ) ^ ((/src[1]$reg_value[M4_WORD_MAX] != /src[2]$reg_value[M4_WORD_MAX]) & $is_bge_instr)
              )
             )
            );
      ?$indirect_jump  // (JALR)
         $indirect_jump_full_target[31:0] = /src[1]$reg_value + $raw_i_imm;
         $indirect_jump_target[M4_PC_RANGE] = $indirect_jump_full_target[M4_PC_RANGE];
         $misaligned_indirect_jump_target = $indirect_jump_full_target[1];
      ?$valid_exe
         // Compute each individual instruction result, combined per-instruction by a macro.
         // TODO: Could provide some macro magic to specify combined instructions w/ a single result and mux select.
         //       This would reduce code below and probably improve implementation.
         
         $lui_rslt[M4_WORD_RANGE] = {$raw_u_imm[31:12], 12'b0};
         $auipc_rslt[M4_WORD_RANGE] = M4_FULL_PC + $raw_u_imm;
         $jal_rslt[M4_WORD_RANGE] = M4_FULL_PC + 4;
         $jalr_rslt[M4_WORD_RANGE] = M4_FULL_PC + 4;
         // Load instructions. If returning ld is enabled, load instructions write no meaningful result, so we use zeros.
         m4_ifelse_block(M4_INJECT_RETURNING_LD, 1, ['
         $lb_rslt[M4_WORD_RANGE] = 32'b0;
         $lh_rslt[M4_WORD_RANGE] = 32'b0;
         $lw_rslt[M4_WORD_RANGE] = 32'b0;
         $lbu_rslt[M4_WORD_RANGE] = 32'b0;
         $lhu_rslt[M4_WORD_RANGE] = 32'b0;
         '], ['
         $lb_rslt[M4_WORD_RANGE] = /orig_inst$ld_rslt;
         $lh_rslt[M4_WORD_RANGE] = /orig_inst$ld_rslt;
         $lw_rslt[M4_WORD_RANGE] = /orig_inst$ld_rslt;
         $lbu_rslt[M4_WORD_RANGE] = /orig_inst$ld_rslt;
         $lhu_rslt[M4_WORD_RANGE] = /orig_inst$ld_rslt;
         '])
         $addi_rslt[M4_WORD_RANGE] = /src[1]$reg_value + $raw_i_imm;  // TODO: This has its own adder; could share w/ add/sub.
         $xori_rslt[M4_WORD_RANGE] = /src[1]$reg_value ^ $raw_i_imm;
         $ori_rslt[M4_WORD_RANGE] = /src[1]$reg_value | $raw_i_imm;
         $andi_rslt[M4_WORD_RANGE] = /src[1]$reg_value & $raw_i_imm;
         $slli_rslt[M4_WORD_RANGE] = /src[1]$reg_value << $raw_i_imm[5:0];
         // TODO: Should combine SRL and SRLI, and SRA and SRAI.
         $srli_intermediate_rslt[M4_WORD_RANGE] = /src[1]$reg_value >> $raw_i_imm[5:0];
         $srai_intermediate_rslt[M4_WORD_RANGE] = /src[1]$reg_value[M4_WORD_MAX] ? $srli_intermediate_rslt | ((M4_WORD_HIGH'b0 - 1) << (M4_WORD_HIGH - $raw_i_imm[5:0]) ): $srli_intermediate_rslt;
         $srl_rslt[M4_WORD_RANGE] = /src[1]$reg_value >> /src[2]$reg_value[4:0];
         $sra_rslt[M4_WORD_RANGE] = /src[1]$reg_value[M4_WORD_MAX] ? $srl_rslt | ((M4_WORD_HIGH'b0 - 1) << (M4_WORD_HIGH - /src[2]$reg_value[4:0]) ): $srl_rslt;
         $slti_rslt[M4_WORD_RANGE] =  (/src[1]$reg_value[M4_WORD_MAX] == $raw_i_imm[M4_WORD_MAX]) ? $sltiu_rslt : {M4_WORD_MAX'b0,/src[1]$reg_value[M4_WORD_MAX]};
         $sltiu_rslt[M4_WORD_RANGE] = (/src[1]$reg_value < $raw_i_imm) ? 1 : 0;
         $srli_srai_rslt[M4_WORD_RANGE] = ($raw_i_imm[10] == 1) ? $srai_intermediate_rslt : $srli_intermediate_rslt;
         $add_sub_rslt[M4_WORD_RANGE] = ($raw_funct7[5] == 1) ?  /src[1]$reg_value - /src[2]$reg_value : /src[1]$reg_value + /src[2]$reg_value;
         $add_rslt[M4_WORD_RANGE] = $add_sub_rslt;
         $sub_rslt[M4_WORD_RANGE] = $add_sub_rslt;
         $sll_rslt[M4_WORD_RANGE] = /src[1]$reg_value << /src[2]$reg_value[4:0];
         $slt_rslt[M4_WORD_RANGE] = (/src[1]$reg_value[M4_WORD_MAX] == /src[2]$reg_value[M4_WORD_MAX]) ? $sltu_rslt : {M4_WORD_MAX'b0,/src[1]$reg_value[M4_WORD_MAX]};
         $sltu_rslt[M4_WORD_RANGE] = (/src[1]$reg_value < /src[2]$reg_value) ? 1 : 0;
         $xor_rslt[M4_WORD_RANGE] = /src[1]$reg_value ^ /src[2]$reg_value;
         $or_rslt[M4_WORD_RANGE] = /src[1]$reg_value | /src[2]$reg_value;
         $and_rslt[M4_WORD_RANGE] = /src[1]$reg_value & /src[2]$reg_value;
         // CSR read instructions have the same result expression. Counting on synthesis to optimize result mux.
         $csrrw_rslt[M4_WORD_RANGE]  = m4_csrrx_rslt_expr;
         $csrrs_rslt[M4_WORD_RANGE]  = $csrrw_rslt;
         $csrrc_rslt[M4_WORD_RANGE]  = $csrrw_rslt;
         $csrrwi_rslt[M4_WORD_RANGE] = $csrrw_rslt;
         $csrrsi_rslt[M4_WORD_RANGE] = $csrrw_rslt;
         $csrrci_rslt[M4_WORD_RANGE] = $csrrw_rslt;
         
         // "M" Extension.
         
         m4_ifelse_block(M4_EXT_M, 1, ['
         $clk = *clk;
         $resetn = !(*reset);         
         $validin_mul = 1'b1;         
         m4+warpv_mul(|fetch/instr,/mul1, $mulblock_rslt, $wrm, $waitm, $readym, $clk, $resetn, /src[1]$reg_value, /src[2]$reg_value, $instr_type_mul, $validin_mul)
         // this 'looks' as expected but Sandpiper says "Currently, signals used as 'when' conditions may not themselves be under a 'when' condition within their behavioral scope."
         m4+warpv_div(|fetch/instr,/div1, $divblock_rslt, $wrd, $waitd, $readyd, $clk, $resetn, /src[1]$reg_value, /src[2]$reg_value, $instr_type_div, $validin_mul)
         $instr_type_mul[3:0] = {$is_mulhu_instr,$is_mulhsu_instr,$is_mulh_instr,$is_mul_instr};
         $instr_type_div[3:0] = {$is_remu_instr,$is_rem_instr,$is_divu_instr,$is_div_instr};
               
         //$div_mul_rslt[31:0] = $div_mul ? $divblock_rslt : $mulblock_rslt;         
         //?$second_issue
         /orig_inst           
            //$divmul_late_rslt[31:0] = |fetch/instr$div_mul_rslt;
            $divmul_late_rslt[31:0] = |fetch/instr$div_mul ? |fetch/instr$divblock_rslt : |fetch/instr$mulblock_rslt;
         $mul_rslt[M4_WORD_RANGE]      = /orig_inst$late_rslt;
         $mulh_rslt[M4_WORD_RANGE]     = /orig_inst$late_rslt;
         $mulhsu_rslt[M4_WORD_RANGE]   = /orig_inst$late_rslt;
         $mulhu_rslt[M4_WORD_RANGE]    = /orig_inst$late_rslt;
         $div_rslt[M4_WORD_RANGE]      = /orig_inst$late_rslt;
         $divu_rslt[M4_WORD_RANGE]     = /orig_inst$late_rslt;
         $rem_rslt[M4_WORD_RANGE]      = /orig_inst$late_rslt;
         $remu_rslt[M4_WORD_RANGE]     = /orig_inst$late_rslt;
         // TODO : when condition wrt output
         //?$div_mul     
         //$instr_type_div[3:0] = {$is_remu_instr,$is_rem_instr,$is_divu_instr,$is_div_instr};
            //?$second_issue
         '])
         `BOGUS_USE ($wrm $wrd $readyd $readym $waitm $waitd)
   // CSR logic
   // ---------
   m4+riscv_csrs((m4_csrs))
   @_exe_stage
      m4+riscv_csr_logic()
      
      // Memory inputs.
      ?$valid_exe
         $unnatural_addr_trap = ($ld_st_word && ($addr[1:0] != 2'b00)) || ($ld_st_half && $addr[0]);
      $ld_st_cond = $ld_st && $valid_exe;
      ?$ld_st_cond
         $addr[M4_ADDR_RANGE] = /src[1]$reg_value + ($ld ? $raw_i_imm : $raw_s_imm);
         
         // Hardware assumes natural alignment. Otherwise, trap, and handle in s/w (though no s/w provided).
      $st_cond = $st && $valid_exe;
      ?$st_cond
         // Provide a value to store, naturally-aligned to memory, that will work regardless of the lower $addr bits.
         $st_reg_value[M4_WORD_RANGE] = /src[2]$reg_value;
         $st_value[M4_WORD_RANGE] =
              $ld_st_word ? $st_reg_value :            // word
              $ld_st_half ? {2{$st_reg_value[15:0]}} : // half
                            {4{$st_reg_value[7:0]}};   // byte
         $st_mask[3:0] =
              $ld_st_word ? 4'hf :                     // word
              $ld_st_half ? ($addr[1] ? 4'hc : 4'h3) : // half
                            (4'h1 << $addr[1:0]);      // byte
      // Swizzle bytes for load result (assuming natural alignment).
      ?$second_issue
         /orig_inst
            $spec_ld_cond = $spec_ld;
            ?$spec_ld_cond
               // (Verilator didn't like indexing $ld_value by signal math, so we do these the long way.)
               $sign_bit =
                  ! $raw_funct3[2] && (  // Signed && ...
                     $ld_st_word ? $ld_value[31] :
                     $ld_st_half ? ($addr[1] ? $ld_value[31] : $ld_value[15]) :
                                   (($addr[1:0] == 2'b00) ? $ld_value[7] :
                                    ($addr[1:0] == 2'b01) ? $ld_value[15] :
                                    ($addr[1:0] == 2'b10) ? $ld_value[23] :
                                                            $ld_value[31]
                                   )
                  );
               {$ld_rslt[M4_WORD_RANGE], $ld_mask[3:0]} =
                    $ld_st_word ? {$ld_value, 4'b1111} :
                    $ld_st_half ? {{16{$sign_bit}}, $addr[1] ? {$ld_value[31:16], 4'b1100} :
                                                               {$ld_value[15:0] , 4'b0011}} :
                                  {{24{$sign_bit}}, ($addr[1:0] == 2'b00) ? {$ld_value[7:0]  , 4'b0001} :
                                                    ($addr[1:0] == 2'b01) ? {$ld_value[15:8] , 4'b0010} :
                                                    ($addr[1:0] == 2'b10) ? {$ld_value[23:16], 4'b0100} :
                                                                            {$ld_value[31:24], 4'b1000}};
               `BOGUS_USE($ld_mask) // It's only for formal verification.
            $late_rslt[M4_WORD_RANGE] = $div_mul ? $divmul_late_rslt : $ld_rslt;  // TODO: || ...
      // ISA-specific trap conditions:
      // I can't see in the spec which of these is to commit results. I've made choices that make riscv-formal happy.
      $non_aborting_isa_trap = ($branch && $taken && $misaligned_pc) ||
                               ($jump && $misaligned_jump_target) ||
                               ($indirect_jump && $misaligned_indirect_jump_target);
      $aborting_isa_trap =     ($ld_st && $unnatural_addr_trap) ||
                               $csr_trap;
      
   @_rslt_stage
      // Mux the correct result.
      m4+riscv_rslt_mux_expr()
   


//============================//
//                            //
//           MIPS I           //
//                            //
//============================//


\TLV mipsi_cnt10_prog()
   \SV_plus
      m4_define(['M4_NUM_INSTRS'], 11)
      
      // The program in an instruction memory.
      logic [M4_INSTR_RANGE] instrs [0:M4_NUM_INSTRS-1];
      
      // /=====================\
      // | Count to 10 Program |
      // \=====================/
      
      // Add 1,2,3,...,9 (in that order).
      // Store incremental results in memory locations 1..9. (1, 3, 6, 10, ..., 45)
      //
      // Regs:
      // 1: cnt
      // 2: ten
      // 3: out
      // 4: tmp
      // 5: offset
      // 6: store addr
      
      assign instrs = '{
        {6'd13, 5'd0, 5'd6, 16'd0},             //    store_addr = 0
        {6'd13, 5'd0, 5'd1, 16'd1},             //    cnt = 1
        {6'd13, 5'd0, 5'd2, 16'd10},            //    ten = 10
        {6'd13, 5'd0, 5'd3, 16'd0},             //    out = 0
        {6'd0,  5'd1, 5'd3, 5'd3, 5'd0, 6'd32}, // -> out += cnt
        {6'd43, 5'd6, 5'd3, 16'd0},             //    store out at store_addr
        {6'd8,  5'd1, 5'd1, 16'd1},             //    cnt ++
        {6'd8,  5'd6, 5'd6, 16'd4},             //    store_addr++
        {6'd5,  5'd1, 5'd2, (~ 16'd4)},         // ^- branch back if cnt != ten
        {6'd35, 5'd6, 5'd4, (~ 16'd3)},         //    load the final value into tmp
        {6'd0,  26'd13}                         //    BREAK
      };

\TLV mipsi_imem(_prog_name)
   m4+indirect(['mipsi_']_prog_name['_prog'])
   |fetch
      /instr
         @M4_FETCH_STAGE
            ?$fetch
               $raw[M4_INSTR_RANGE] = *instrs\[$Pc[m4_eval(M4_PC_MIN + m4_width(M4_NUM_INSTRS-1) - 1):M4_PC_MIN]\];

\TLV mipsi_gen()
   // No M4-generated code for MIPS I.


// Decode logic for MIPS I.
// Context: within pipestage
// Inputs:
//    $raw[31:0]
// Outputs:
//    $ld
//    $st
//    $illegal
//    $conditional_branch
//    ...
\TLV mipsi_decode()
   // TODO: ?$valid_<stage> conditioning should be replaced by use of m4_prev_instr_valid_through(..).
   ?$valid_decode

      // Extract fields of $raw (instruction) into $raw_<field>[x:0].
      m4_into_fields(['M4_INSTR'], ['$raw'])
      $raw_immediate[15:0] = $raw[15:0];
      $raw_address[25:0] = $raw[25:0];
      
      // Instruction Format
      $rtype = $raw_opcode == 6'b000000;
      $jtype = $raw_opcode == 6'b000010 || $raw_opcode == 6'b000011;
      $itype = ! $rtype && ! $jtype;
      
      // Load/Store
      //$is_lb  = $raw_opcode == 6'b100000;
      $is_lh  = $raw_opcode == 6'b100001;
      //$is_lwl = $raw_opcode == 6'b100010;
      //$is_lw  = $raw_opcode == 6'b100011;
      $is_lbu = $raw_opcode == 6'b100100;
      $is_lhu = $raw_opcode == 6'b100101;
      //$is_lwr = $raw_opcode == 6'b100110;
      //$is_sb  = $raw_opcode == 6'b101000;
      $is_sh  = $raw_opcode == 6'b101001;
      //$is_swl = $raw_opcode == 6'b101010;
      //$is_sw  = $raw_opcode == 6'b101011;
      //$is_swr = $raw_opcode == 6'b101100;
      
      // ALU
      $is_add   = $rtype && $raw_funct == 6'b100000;
      $is_addu  = $rtype && $raw_funct == 6'b100001;
      $is_sub   = $rtype && $raw_funct == 6'b100010;
      $is_subu  = $rtype && $raw_funct == 6'b100011;
      $is_and   = $rtype && $raw_funct == 6'b100100;
      $is_or    = $rtype && $raw_funct == 6'b100101;
      $is_xor   = $rtype && $raw_funct == 6'b100110;
      $is_nor   = $rtype && $raw_funct == 6'b100111;
      $is_slt   = $rtype && $raw_funct == 6'b101010;
      $is_sltu  = $rtype && $raw_funct == 6'b101011;
      $is_addi  = $raw_opcode == 6'b001000;
      $is_addiu = $raw_opcode == 6'b001001;
      $is_slti  = $raw_opcode == 6'b001010;
      $is_sltiu = $raw_opcode == 6'b001011;
      $is_andi  = $raw_opcode == 6'b001100;
      $is_ori   = $raw_opcode == 6'b001101;
      $is_xori  = $raw_opcode == 6'b001110;
      $is_lui   = $raw_opcode == 6'b001111;
      
      // Shift
      $is_sll  = $rtype && $raw_funct == 6'b000000;
      $is_srl  = $rtype && $raw_funct == 6'b000010;
      $is_sra  = $rtype && $raw_funct == 6'b000011;
      $is_sllv = $rtype && $raw_funct == 6'b000100;
      $is_srlv = $rtype && $raw_funct == 6'b000110;
      $is_srav = $rtype && $raw_funct == 6'b000111;
      
      /*
      // Mul/Div
      $is_mfhi  = $rtype && $raw_funct == 6'b010000;
      $is_mthi  = $rtype && $raw_funct == 6'b010001;
      $is_mflo  = $rtype && $raw_funct == 6'b010010;
      $is_mtlo  = $rtype && $raw_funct == 6'b010011;
      $is_mult  = $rtype && $raw_funct == 6'b011000;
      $is_multu = $rtype && $raw_funct == 6'b011001;
      $is_div   = $rtype && $raw_funct == 6'b011010;
      $is_divu  = $rtype && $raw_funct == 6'b011011;
      */
      $div_mul = 1'b0;
      
      // Jump/Branch
      $is_jr     = $rtype && $raw_funct == 6'b001000;
      $is_jalr   = $rtype && $raw_funct == 6'b001001;
      $is_bltz   = $raw_opcode == 6'b000001 && $raw_rt[4] == 1'b0 && $raw_rt[0] == 1'b0;
      $is_bgez   = $raw_opcode == 6'b000001 && $raw_rt[4] == 1'b0 && $raw_rt[0] == 1'b1;
      $is_bltzal = $raw_opcode == 6'b000001 && $raw_rt[4] == 1'b1 && $raw_rt[0] == 1'b0;
      $is_bgezal = $raw_opcode == 6'b000001 && $raw_rt[4] == 1'b1 && $raw_rt[0] == 1'b1;
      $is_j      = $raw_opcode == 6'b000010;
      $is_jal    = $raw_opcode == 6'b000011;
      $is_beq    = $raw_opcode == 6'b000100;
      $is_bne    = $raw_opcode == 6'b000101;
      $is_blez   = $raw_opcode == 6'b000110;
      $is_bgtz   = $raw_opcode == 6'b000111;
      
      // Exception
      $is_syscall = $rtype && $raw_funct == 6'b001100;
      $is_break   = $rtype && $raw_funct == 6'b001101;
      
      // FPU
      // TODO: NOT IMPLEMENTED
      
      
      $illegal = 1'b0;  // MIPS I doesn't have an illegal instruction exception, just UNPREDICTABLE behavior.
      $conditional_branch = $raw_opcode == 6'b000001 || $raw_opcode[5:2] == 4'b0001;

      
      // Special-Case Formats
      $link_reg = $is_bltzal && $is_bgezal && $is_jal;
      $unsigned_imm = $is_addiu || $is_sltiu;
      $jump = $is_j || $is_jal;
      $indirect_jump = $is_jr || $is_jalr;
      $branch_or_jump = ($raw_opcode[5:3] == 3'b000) && ! $rtype;  // (does not include syscall & break)
      $ld = $raw_opcode[5:3] == 3'b100;
      $st = $raw_opcode[5:3] == 3'b101;
      $ld_st = $ld || $st;
      $ld_st_word = $ld_st && $raw_opcode[1] == 1'b1;
      $ld_st_half = $is_lh || $is_lhu || $is_sh;
      //$ld_st_byte = ...;

      // Output signals.
      /src[2:1]
         // Reg valid for this source, based on instruction type.
         $is_reg =
             (#src == 1) ? ! /instr$jtype :
                           /instr$rtype || /instr$st || /instr$is_beq || /instr$is_bne;
         $reg[M4_REGS_INDEX_RANGE] =
             (#src == 1) ? /instr$raw_rs :
                           /instr$raw_rt;
      $imm_value[M4_WORD_RANGE] = {{16{$raw_immediate[15] && ! $unsigned_imm}}, $raw_immediate[15:0]};
      
   // Condition signals must not themselves be conditioned (currently).
   $dest_reg[M4_REGS_INDEX_RANGE] = $second_issue ? /orig_inst$dest_reg : $link_reg ? 5'b11111 : $itype ? $raw_rt : $raw_rd;
   $dest_reg_valid = (($valid_decode && ! ((($is_j || $conditional_branch) && ! $link_reg) || $st || $is_syscall || $is_break)) || $second_issue) &&
                     | $dest_reg;   // r0 not valid.
                     // Note that load is considered to have a valid dest (which may be marked pending).
   $branch = $valid_decode && $conditional_branch;   // (Should be $decode_valid_branch, but keeping consistent with other ISAs.)
   $decode_valid_jump = $valid_decode && $jump;
   $decode_valid_indirect_jump = $valid_decode && $indirect_jump;
   // Actually load.
   $spec_ld = $valid_decode && $ld;   // (Should be $decode_valid_ld, but keeping consistent with other ISAs.)


// Execution unit logic for MIPS I.
// Context: pipeline
\TLV mipsi_exe(@_exe_stage, @_rslt_stage)
   @M4_BRANCH_TARGET_CALC_STAGE
      // TODO: Branch delay slot not implemented.
      // (PC is an instruction address, not a byte address.)
      ?$valid_decode_branch
         $branch_target[M4_PC_RANGE] = $pc_inc + $imm_value[29:0];
      ?$decode_valid_jump  // (JAL, not JALR)
         $jump_target[M4_PC_RANGE] = {$Pc[M4_PC_MAX:28], $raw_address[25:0]};
   @_exe_stage
      // Execution.
      $valid_exe = $valid_decode; // Execute if we decoded.
      
      ?$valid_exe
         // Mux immediate values with register values. (Could be REG_RD or EXE stage.)
         // Mux register value and immediate to produce operand 2.
         $op2_value[M4_WORD_RANGE] = ($raw_opcode[5:3] == 3'b001) ? $imm_value : /src[2]$reg_value;
         // Mux RS[4:0] and SHAMT to produce shift amount.
         $shift_amount[4:0] = ($is_sllv || $is_srlv || $is_srav) ? /src[2]$reg_value[4:0] : $raw_shamt;
         
         $equal = /src[1]$reg_value == /src[2]$reg_value;
         $equal_zero = ! | /src[1]$reg_value;
         $ltz = /src[1]$reg_value[31];
         $gtz = ! $ltz && ! $equal_zero;
      ?$branch
         $taken =
            $jtype ||
            ($is_jr || $is_jalr) ||
            ($is_beq  &&   $equal) ||
            ($is_bne  && ! $equal) ||
            (($is_bltz || $is_bltzal) &&   $ltz) ||
            (($is_bgez || $is_bgezal) && ! $ltz) ||
            ($is_blez && ! $gtz) ||
            ($is_bgtz &&   $gtz);
      ?$decode_valid_indirect_jump  // (JR/JALR)
         $indirect_jump_target[M4_PC_RANGE] = /src[1]$reg_value[M4_PC_RANGE];
      ?$valid_exe
         // Compute each individual instruction result, combined per-instruction by a macro.
         
         // Load/Store
         // Load instructions. If returning ld is enabled, load instructions write no meaningful result, so we use zeros.
         $ld_rslt[M4_WORD_RANGE] = m4_ifelse(M4_INJECT_RETURNING_LD, 1, ['32'b0'], ['/orig_inst$ld_rslt']);
         
         $add_sub_rslt[M4_WORD_RANGE] = ($is_sub || $is_subu) ? /src[1]$reg_value - $op2_value : /src[1]$reg_value + $op2_value;
         $is_add_sub = $is_add || $is_sub || $is_addu || $is_subu || $is_addi || $is_addiu;
         $compare_rslt[M4_WORD_RANGE] = {31'b0, (/src[1]$reg_value < $op2_value) ^ /src[1]$reg_value[31] ^ $op2_value[31]};
         $is_compare = $is_slt || $is_sltu || $is_slti || $is_sltiu;
         $logical_rslt[M4_WORD_RANGE] =
                 ({32{$is_and || $is_andi}} & (/src[1]$reg_value & $op2_value)) |
                 ({32{$is_or  || $is_ori }} & (/src[1]$reg_value | $op2_value)) |
                 ({32{$is_xor || $is_xori}} & (/src[1]$reg_value ^ $op2_value)) |
                 ({32{$is_nor            }} & (/src[1]$reg_value | ~ /src[2]$reg_value));
         $is_logical = $is_and || $is_andi || $is_or || $is_ori || $is_xor || $is_xori || $is_nor;
         $shift_rslt[M4_WORD_RANGE] =
                 ({32{$is_sll || $is_sllv}} & (/src[1]$reg_value << $shift_amount)) |
                 ({32{$is_srl || $is_srlv}} & (/src[1]$reg_value >> $shift_amount)) |
                 ({32{$is_sra || $is_srav}} & (/src[1]$reg_value << $shift_amount));
         $is_shift = $is_sll || $is_srl || $is_sra || $is_sllv || $is_srlv || $is_srav;
         $lui_rslt[M4_WORD_RANGE] = {$raw_immediate, 16'b0}; 
         
   @_rslt_stage
      ?$valid_exe
         $rslt[M4_WORD_RANGE] =
              $second_issue ? /orig_inst$ld_rslt :
                 ({32{$spec_ld}}    & $ld_rslt) |
                 ({32{$is_add_sub}} & $add_sub_rslt) |
                 ({32{$is_compare}} & $compare_rslt) |
                 ({32{$is_logical}} & $logical_rslt) |
                 ({32{$is_shift}}   & $shift_rslt) |
                 ({32{$is_lui}}     & $lui_rslt) |
                 ({32{$branch_or_jump}} & {$pc_inc, 2'b0});   // (no delay slot)
         
         
         
      // Memory inputs.
      // TODO: Logic for load/store is cut-n-paste from RISC-V, blindly assuming it is spec'ed the same for MIPS I?
      //       Load/Store half instructions unique vs. RISC-V and are not treated properly.
      ?$valid_exe
         $unnatural_addr_trap = ($ld_st_word && ($addr[1:0] != 2'b00)) || ($ld_st_half && $addr[0]);
      $ld_st_cond = $ld_st && $valid_exe;
      ?$ld_st_cond
         $addr[M4_ADDR_RANGE] = /src[1]$reg_value + $imm_value;
         
         // Hardware assumes natural alignment. Otherwise, trap, and handle in s/w (though no s/w provided).
      $st_cond = $st && $valid_exe;
      ?$st_cond
         // Provide a value to store, naturally-aligned to memory, that will work regardless of the lower $addr bits.
         $st_reg_value[M4_WORD_RANGE] = /src[2]$reg_value;
         $st_value[M4_WORD_RANGE] =
              $ld_st_word ? $st_reg_value :            // word
              $ld_st_half ? {2{$st_reg_value[15:0]}} : // half
                            {4{$st_reg_value[7:0]}};   // byte
         $st_mask[3:0] =
              $ld_st_word ? 4'hf :                     // word
              $ld_st_half ? ($addr[1] ? 4'hc : 4'h3) : // half
                            (4'h1 << $addr[1:0]);      // byte
      // Swizzle bytes for load result (assuming natural alignment).
      ?$second_issue
         /orig_inst
            // (Verilator didn't like indexing $ld_value by signal math, so we do these the long way.)
            $sign_bit =
               ! ($is_lbu || $is_lhu) && (  // Signed && ...
                  $ld_st_word ? $ld_value[31] :
                  $ld_st_half ? ($addr[1] ? $ld_value[31] : $ld_value[15]) :
                                (($addr[1:0] == 2'b00) ? $ld_value[7] :
                                 ($addr[1:0] == 2'b01) ? $ld_value[15] :
                                 ($addr[1:0] == 2'b10) ? $ld_value[23] :
                                                         $ld_value[31]
                                )
               );
            $ld_rslt[M4_WORD_RANGE] =
                 $ld_st_word ? $ld_value :
                 $ld_st_half ? {{16{$sign_bit}}, $addr[1] ? $ld_value[31:16] :
                                                            $ld_value[15:0] } :
                               {{24{$sign_bit}}, ($addr[1:0] == 2'b00) ? $ld_value[7:0]   :
                                                 ($addr[1:0] == 2'b01) ? $ld_value[15:8]  :
                                                 ($addr[1:0] == 2'b10) ? $ld_value[23:16] :
                                                                         $ld_value[31:24]};
      
      
      // ISA-specific trap conditions:
      $non_aborting_isa_trap = $is_break || $is_syscall;
      $aborting_isa_trap =     ($ld_st && $unnatural_addr_trap);



//============================//
//                            //
//          POWER             //
//                            //
//============================//


\TLV power_cnt10_prog()
   \SV_plus
      m4_define(['M4_NUM_INSTRS'], 2)
      
      // The program in an instruction memory.
      logic [M4_INSTR_RANGE] instrs [0:M4_NUM_INSTRS-1];
      
      // /=====================\
      // | Count to 10 Program |
      // \=====================/
      
      // Add 1,2,3,...,9 (in that order).
      // Store incremental results in memory locations 1..9. (1, 3, 6, 10, ..., 45)
      //
      // Regs:
      // b: cnt
      // c: nine
      // d: out
      // e: tmp
      // f: offset
      // g: store addr
      
      assign instrs = '{
        32'b00000000000000000000000000000000,
        32'b00000000000000000000000000000000
      };

\TLV power_imem(_prog_name)
   m4+indirect(['mipsi_']_prog_name['_prog'])
   |fetch
      /instr
         @M4_FETCH_STAGE
            ?$fetch
               $raw[M4_INSTR_RANGE] = *instrs\[$Pc[m4_eval(M4_PC_MIN + m4_width(M4_NUM_INSTRS-1) - 1):M4_PC_MIN]\];

\TLV power_gen()
   // No M4-generated code for POWER.


// Decode logic for Power.
// Context: within pipestage
// Inputs:
//    $raw[31:0]
// Outputs:
//    $ld
//    $st
//    $illegal
//    $conditional_branch
//    ...
\TLV power_decode()
   // TODO

// Execution unit logic for POWER.
// Context: pipeline
\TLV power_exe(@_exe_stage, @_rslt_stage)
   @M4_REG_RD_STAGE
      /src[*]
         $valid = /instr$valid_decode && ($is_reg || $is_imm);
         ?$valid
            $value[M4_WORD_RANGE] = $is_reg ? $reg_value :
                                              $imm_value;
   // Note that some result muxing is performed in @_exe_stage, and the rest in @_rslt_stage.
   @_exe_stage
      ?$valid_st
         $st_value[M4_WORD_RANGE] = /src[1]$value;

      $valid_ld_st = $valid_ld || $valid_st;
      ?$valid_ld_st
         $addr[M4_ADDR_RANGE] = $ld ? (/src[1]$value + /src[2]$value) : /src[2]$value;
      // Always predict taken; mispredict if jump or unconditioned branch or
      //   conditioned branch with positive condition.
      ?$branch
         $taken = $rslt != 12'b0;
      $st_mask[0:0] = 1'b1;
      $non_aborting_isa_trap = 1'b0;
      $aborting_isa_trap = 1'b0;
   @_rslt_stage
      ?$dest_valid
         $rslt[11:0] =
            $second_issue ? /orig_inst$ld_value :
            $st ? /src[1]$value :
            $op_full ? $op_full_rslt :
            $op_compare ? {12{$compare_rslt}} :
                  12'b0;
         
      // Jump (Dest = "P") and Branch (Dest = "p") Targets.
      ?$jump
         $jump_target[M4_PC_RANGE] = $rslt[M4_PC_RANGE];
   @M4_BRANCH_TARGET_CALC_STAGE
      ?$branch
         $branch_target[M4_PC_RANGE] = $Pc + M4_PC_CNT'b1 + $rslt[M4_PC_RANGE];


//============================//
//                            //
//        DUMMY-CPU           //
//                            //
//============================//

\TLV dummy_imem()
   // Dummy IMem contains 2 dummy instructions.
   |fetch
      /instr
         @M4_FETCH_STAGE
            ?$fetch
               $raw[M4_INSTR_RANGE] = $Pc[M4_PC_MIN:M4_PC_MIN] == 1'b0 ? 2'b01 : 2'b10;

\TLV dummy_gen()
   // No M4-generated code for dummy.

\TLV dummy_decode()
   /src[2:1]
      `BOGUS_USE(/instr$raw[0])
      $is_reg = 1'b0;
      $reg[M4_REGS_INDEX_RANGE] = 3'b1;
      $value[M4_WORD_RANGE] = 2'b1;
   $dest_reg_valid = 1'b1;
   $dest_reg[M4_REGS_INDEX_RANGE] = $second_issue ? /orig_inst$dest_reg : 3'b0;
   $ld = 1'b0;
   $spec_ld = $ld;
   $st = 1'b0;
   $illegal = 1'b0;
   $branch = 1'b0;
   $jump = 1'b0;
   $div_mul = 1'b0;
   $conditional_branch = $branch;
   ?$valid_decode_branch

// Execution unit logic for RISC-V.
// Context: pipeline
\TLV dummy_exe(@_exe_stage, @_rslt_stage)
   @M4_REG_RD_STAGE
      $exe_rslt[M4_WORD_RANGE] = 2'b1;
   // Note that some result muxing is performed in @_exe_stage, and the rest in @_rslt_stage.
   @_exe_stage
      $st_value[M4_WORD_RANGE] = /src[1]$reg_value;
      $addr[M4_ADDR_RANGE] = /src[2]$reg_value;
      $taken = $rslt != 2'b0;
      $st_mask[0:0] = 1'b1;
      $non_aborting_isa_trap = 1'b0;
      $aborting_isa_trap = 1'b0;
   @_rslt_stage
      $rslt[M4_WORD_RANGE] =
         $second_issue ? /orig_inst$ld_value :
         $st ? /src[1]$value :
         $exe_rslt;
         
      // Jump (Dest = "P") and Branch (Dest = "p") Targets.
      $jump_target[M4_PC_RANGE] = $rslt[M4_PC_RANGE];
   @M4_BRANCH_TARGET_CALC_STAGE
      $branch_target[M4_PC_RANGE] = $Pc + M4_PC_CNT'b1 + $rslt[M4_PC_RANGE];
         




//=========================//
//                         //
//   MEMORY COMPONENT(S)   //
//                         //
//=========================//

// A memory component provides a word-wide memory striped in M4_ADDRS_PER_WORD independent banks to provide
// address-granular write. The access protocol is asynchronous and out-of-order, accepting
// a read or write (load or store) each cycle, where stores are visible to loads on the following cycle.
// Relative to |fetch/instr:
// On $valid_st, stores the data $st_value at $addr, masked by $st_mask.
// On $spec_ld, loads the word at $addr (ignoring intra-word bits).
// The returned load result can be accessed from /_cpu|mem/data<<M4_ALIGNMENT_VALUE$ANY as $ld_value and $ld
// (along w/ everything else in the input instruction).

// A fake memory with fixed latency.
// The memory is placed in the fetch pipeline.
// TODO: (/_cpu, @_mem, @_align)
\TLV fixed_latency_fake_memory(/_cpu, M4_ALIGNMENT_VALUE)
   // This macro assumes little-endian.
   m4_ifelse(M4_BIG_ENDIAN, 0, [''], ['m4_errprint(['Error: fixed_latency_fake_memory macro only supports little-endian memory.'])'])
   |fetch
      /instr
         // ====
         // Load
         // ====
         @M4_MEM_WR_STAGE
            /bank[M4_ADDRS_PER_WORD-1:0]
               $ANY = /instr$ANY; // Find signal from outside of /bank.
               /mem[M4_DATA_MEM_WORDS_RANGE]
               ?$spec_ld
                  $ld_value[(M4_WORD_HIGH / M4_ADDRS_PER_WORD) - 1 : 0] = /mem[$addr[M4_DATA_MEM_WORDS_INDEX_MAX + M4_SUB_WORD_BITS : M4_SUB_WORD_BITS]]$Value;
         
               // Array writes are not currently permitted to use assignment
               // syntax, so \always_comb is used, and this must be outside of
               // when conditions, so we need to use if. <<1 because no <= support
               // in this context. (This limitation will be lifted.)

               // =====
               // Store
               // =====

               \SV_plus
                  always @ (posedge clk) begin
                     if ($valid_st && $st_mask[#bank])
                        /mem[$addr[M4_DATA_MEM_WORDS_INDEX_MAX + M4_SUB_WORD_BITS : M4_SUB_WORD_BITS]]<<0$$Value[(M4_WORD_HIGH / M4_ADDRS_PER_WORD) - 1 : 0] <= $st_value[(#bank + 1) * (M4_WORD_HIGH / M4_ADDRS_PER_WORD) - 1: #bank * (M4_WORD_HIGH / M4_ADDRS_PER_WORD)];
                  end
            // Combine $ld_value per bank, assuming little-endian.
            //$ld_value[M4_WORD_RANGE] = /bank[*]$ld_value;
            // Unfortunately formal verification tools can't handle multiple packed dimensions produced by the expression above, so we
            // build the concatination.
            $ld_value[M4_WORD_RANGE] = {m4_forloop(['m4_ind'], 0, M4_ADDRS_PER_WORD, ['m4_ifelse(m4_ind, 0, [''], [', '])/bank[m4_eval(M4_ADDRS_PER_WORD - m4_ind - 1)]$ld_value'])};

   // Return loads in |mem pipeline. We just hook up the |mem pipeline to the |fetch pipeline w/ the
   // right alignment.
   |mem
      /data
         @m4_eval(m4_strip_prefix(['@M4_MEM_WR_STAGE']) - M4_ALIGNMENT_VALUE)
            $ANY = /_cpu|fetch/instr>>M4_ALIGNMENT_VALUE$ANY;
            /src[2:1]
               $ANY = /_cpu|fetch/instr/src>>M4_ALIGNMENT_VALUE$ANY;




//========================//
//                        //
//   Branch Predictors    //
//                        //
//========================//

// Branch predictor macros:
// Context: pipeline
// Inputs:
//   @M4_EXECUTE_STAGE
//      $reset
//      $branch: This instruction is a branch.
//      ?$branch
//         $taken: This branch is taken.
// Outputs:
//   @M4_BRANCH_PRED_STAGE
//      $pred_taken
\TLV branch_pred_fallthrough()
   @M4_BRANCH_PRED_STAGE
      $pred_taken = 1'b0;

\TLV branch_pred_two_bit()
   @M4_BRANCH_PRED_STAGE
      ?$branch
         $pred_taken = >>m4_stage_eval(@M4_EXECUTE_STAGE + 1 - @M4_BRANCH_PRED_STAGE)$BranchState[1];
   @M4_EXECUTE_STAGE
      $branch_or_reset = ($branch && $commit) || $reset;
      ?$branch_or_reset
         $BranchState[1:0] <=
            $reset ? 2'b01 :
            $taken ? ($BranchState == 2'b11 ? $RETAIN : $BranchState + 2'b1) :
                     ($BranchState == 2'b00 ? $RETAIN : $BranchState - 2'b1);



//===============//
// "M" Extension //
// Followed by multiply / divide macros //
//===============//

\SV
   m4_ifexpr(M4_EXT_M == 1, ['
      m4_ifelse(M4_ISA, ['RISCV'], [''], ['m4_errprint(['M-ext supported for RISC-V only.']m4_new_line)'])
      /* verilator lint_off WIDTH */
      /* verilator lint_off CASEINCOMPLETE */   
      m4_sv_include_url(['https:/']['/raw.githubusercontent.com/shivampotdar/warp-v/m_ext/muldiv/picorv32_div_opt.sv'])
      m4_sv_include_url(['https:/']['/raw.githubusercontent.com/shivampotdar/warp-v/m_ext/muldiv/picorv32_pcpi_fast_mul.sv'])
   '])

\TLV m_extension()
   m4_define(['M4_DIV_LATENCY'], 3)  // Relative to typical 1-cycle latency instructions.
   @M4_NEXT_PC_STAGE
      $second_issue_div_mul = >>m4_eval(1 + M4_EXECUTE_STAGE - M4_NEXT_PC_STAGE)$trigger_next_pc_div_mul_second_issue;
   @M4_EXECUTE_STAGE
      {$div_mul_stall, $stall_cnt[5:0]} =
           $reset ? '0 :
           $second_issue ? '0 :
           ($commit && $div_mul) ? {1'b1, 6'b1} :
           >>1$div_mul_stall ? {1'b1, >>1$stall_cnt + 6'b1} :
                    '0;
      $trigger_next_pc_div_mul_second_issue = $div_mul_stall && ($stall_cnt == (M4_DIV_LATENCY + 1 - (M4_EXECUTE_STAGE - M4_NEXT_PC_STAGE)));
      //$div_mul_rslt[31:0] = 32'h55555555;

\TLV warpv_mul(/_top, /_name, $_rslt, $_wr, $_wait, $_ready, $_clk, $_reset, $_op_a, $_op_b, $_instr_type, $_muldiv_valid)
   /_name      
      
      // instr type is one hot encoding of the required M type instruction
      // the idea is to concatenate is_*_instr from WARP-V and pass on to this module
         
      $opcode[2:0] = (/_top$_instr_type == 4'b0001) ? 3'b000 : // mull 
                     (/_top$_instr_type == 4'b0010) ? 3'b001 : // mulh
                     (/_top$_instr_type == 4'b0100) ? 3'b010 : // mulhsu
                     (/_top$_instr_type == 4'b1000) ? 3'b011 : // mulhu
                                                      3'b000 ; // default to mul, but this case 
                                                               // should not be encountered ideally

      $mul_insn[31:0] = {7'b0000001,10'b0011000101,$opcode,5'b00101,7'b0110011};
                        // {  funct7  ,{rs2, rs1} (X), funct3, rd (X),  opcode  }   
       
      \SV_plus
            picorv32_pcpi_fast_mul mul(
                  .clk           (/_top$_clk), 
                  .resetn        (/_top$_reset),
                  .pcpi_valid    (/_top$_muldiv_valid),
                  .pcpi_insn     ($mul_insn),
                  .pcpi_rs1      (/_top$_op_a),
                  .pcpi_rs2      (/_top$_op_b),
                  .pcpi_wr       (/_top$['']$_wr),
                  .pcpi_rd       (/_top$['']$_rslt[31:0]),
                  .pcpi_wait     (/_top$['']$_wait),
                  .pcpi_ready    (/_top$['']$_ready)
            );
   
\TLV warpv_div(/_top, /_name, $_rslt, $_wr, $_wait, $_ready, $_clk, $_reset, $_op_a, $_op_b, $_instr_type, $_muldiv_valid)
   /_name
      
      // instr type is one hot encoding of the required M type instruction
      // the idea is to concatenate is_*_instr from WARP-V and pass on to this module
         
      $opcode[2:0] = (/_top$_instr_type == 4'b0001 ) ? 3'b100 : // div
                     (/_top$_instr_type == 4'b0010 ) ? 3'b101 : // divu
                     (/_top$_instr_type == 4'b0100 ) ? 3'b110 : // rem
                     (/_top$_instr_type == 4'b1000 ) ? 3'b111 : // remu
                                                       3'b100 ; // default to mul, but this case 
                                                                // should not be encountered ideally
      $div_insn[31:0] = {7'b0000001,10'b0011000101,3'b000,5'b00101,7'b0110011} | ($opcode << 12);
                        // {  funct7  ,{rs2, rs1} (X), funct3, rd (X),  opcode  }   
      
      \SV_plus
            picorv32_pcpi_div div(
                  .clk           (/_top$_clk), 
                  .resetn        (/_top$_reset),
                  .pcpi_valid    (/_top$_muldiv_valid),
                  .pcpi_insn     ($div_insn),
                  .pcpi_rs1      (/_top$_op_a),
                  .pcpi_rs2      (/_top$_op_b),
                  .pcpi_rd       (/_top$['']$_rslt[31:0]),
                  .pcpi_wait     (/_top$['']$_wait),
                  .pcpi_wr       (/_top$['']$_wr),
                  .pcpi_ready    (/_top$['']$_ready)
               );

//===============//
// "F" Extension //
//===============//

\TLV f_extension()
   // TODO: Get the ordering and defaulting behavior right for this:
   m4_define(['M4_EXT_F'], 1)
   
   // This macro uses Berkeley Hard-Float to implement "F" extension support in risc-v.
   // Floating-point operations (any instructions that write a floating-point register) abort (after)
   // and no-fetch in the front-end until the dest FP reg has been written. This is a low-performance
   // implementation, but with this approach, no reg-bypass logic is needed.
   |fetch
      @M4_NEXT_PC_STAGE
         $NoFetch = 
      @M4_EXECUTE_STAGE
         $abort = ...
      
//=========================//
//                         //
//        THE CPU          //
//       (All ISAs)        //
//                         //
//=========================//

\TLV cpu(/_cpu)
   // Generated logic
   m4+indirect(M4_isa['_gen'])

   // Instruction memory and fetch of $raw.
   m4+indirect(M4_IMEM_MACRO_NAME, M4_PROG_NAME)


   // /=========\
   // | The CPU |
   // \=========/

   |fetch
      /instr
         m4+m_extension()
         // Provide a longer reset to cover the pipeline depth.
         @m4_stage_eval(@M4_NEXT_PC_STAGE<<1)
            $soft_reset = (m4_soft_reset) || *reset;
            $Cnt[7:0] <= $soft_reset   ? 8'b0 :       // reset
                         $Cnt == 8'hFF ? 8'hFF :      // max out to avoid wrapping
                                         $Cnt + 8'b1; // increment
            $reset = $soft_reset || $Cnt < m4_eval(M4_LD_RETURN_ALIGN + M4_MAX_REDIRECT_BUBBLES + 3);
         @M4_FETCH_STAGE
            $fetch = ! $reset && ! $NoFetch;
            // (M4_IMEM_MACRO_NAME instantiation produces ?$fetch$raw.)
         @M4_NEXT_PC_STAGE
            
            // ========
            // Overview
            // ========
            
            // Terminology:
            //
            // Instruction: An instruction, as viewed by the CPU pipeline (i.e. ld and returning_ld are separate instructions,
            //              and the returning_ld and the instruction it clobbers are one in the same).
            // ISA Instruction: An instruction, as defined by the ISA.
            // Good-Path (vs. Bad-Path): On the proper flow of execution of the program, excluding aborted instructions.
            // Path (of an instruction): The sequence of instructions that led to a particular instruction.
            // Current Path: The sequence of instructions fetched by next-PC logic that are not known to be bad-path.
            // Redirect: Adjust the PC from the predicted next-PC.
            // Redirect Shadow: Between the instruction causing the redirect and the redirect target instruction.
            // Bubbles: The cycles in the redirect shadow.
            // Commit: Results are made visible to subsequent instructions.
            // Abort: Do not commit. All aborts are also redirects and put the instruction on bad path. Non-aborting
            //        redirects do not mark the triggering instruction as bad-path. Aborts mask future redirects on the
            //        aborted instruction.
            // Retire: Commit results of an ISA instruction.
            
            // Control flow:
            //
            // Redirects include (earliest to latest):
            //   o Returning load: (aborting) A returning load clobbers an instruction and takes its slot, resulting in a
            //                     one-cycle redirect to repeat the clobbered instruction.
            //   o Predict-taken branch: A predicted-taken branch must determine the target before it can redirect the PC.
            //                           (This might be followed up by a mispredition.)
            //   o Replay: (aborting) Replay the same instruction (because a source register is pending (awaiting a long-latency/2nd issuing instruction))
            //   o Jump: A jump instruction.
            //   o Mispredicted branch: A branch condition was mispredicted.
            //   o Aborting traps: (aborting) illegal instructions, others?
            //   o Non-aborting traps: misaligned PC target
            
            // ==============
            // Redirect Logic
            // ==============
                            
            // PC logic will redirect the PC for conditions on current-path instructions. PC logic keeps track of which
            // instructions are on the current path with a $GoodPathMask. $GoodPathMask[n] of an instruction indicates
            // whether the instruction n instructions prior to this instruction is on its path.
            //
            //                 $GoodPathMask for Redir'edX => {o,X,o,o,y,y,o,o} == {1,1,1,1,0,0,1,1}
            // Waterfall View: |
            //                 V
            // 0)       oooooooo                  Good-path
            // 1) InstX  ooooooXo  (Non-aborting) Good-path
            // 2)         ooooooxx
            // 3) InstY    ooYyyxxx  (Aborting)
            // 4) InstZ     ooyyxZxx
            // 5) Redir'edY  oyyxxxxx
            // 6) TargetY     ooxxxxxx
            // 7) Redir'edX    oxxxxxxx
            // 8) TargetX       oooooooo          Good-path
            // 9) Not redir'edZ  oooooooo         Good-path
            //
            // Above depicts a waterfall diagram where three triggering redirection conditions X, Y, and Z are detected on three different
            // instructions. A trigger in the 1st depicted stage, M4_NEXT_PC_STAGE, results in a zero-bubble redirect so it would be
            // a condition that is factored directly into the next-PC logic of the triggering instruction, and it would have
            // no impact on the $GoodPathMask.
            //
            // Waveform View:
            //
            //   Inst 0123456789
            //        ---------- /
            // GPM[7]        ooxxxxxxoo
            // GPM[6]       oXxxxxxxoo
            // GPM[5]      oooxZxxxoo
            // GPM[4]     oooyxxxxoo
            // GPM[3]    oooyyxxxoo
            // GPM[2]   oooYyyxxoo
            // GPM[1]  oooooyoxoo
            // GPM[0] oooooooooo
            //          /
            //         Triggers for InstY
            //
            // In the waveform view, the mask shifts up each cycle, as instructions age, and trigger conditions mask instructions
            // in the shadow, down to the redirect target (GPM[0]).
            //
            // Terminology:
            //   Triggering instruction: The instruction on which the condition is detected.
            //   Redirected instruction: The instruction whose next PC is redirected.
            //   Redirection target instruction: The first new-path instruction resulting from the redirection.
            //
            // Above, Y redirects first, though it is for a later instruction than X. The redirections for X and Y are taken
            // because their instructions are on the path of the redirected instructions. Z is not on the path of its
            // potentially-redirected instruction, so no redirection happens.
            //
            // For simultaneous conditions on different instructions, the PC must redirect to the earlier instruction's
            // redirect target, so later-stage redirects take priority in the PC-mux.
            //
            // Aborting redirects result in the aborting instruction being marked as bad-path. Aborted instructions will
            // not commit. Subsequent redirect conditions on aborting instructions are ignored. (For conditions within the
            // same stage, this is accomplished by the PC-mux prioritization.)
            
            
            // Macros are defined elsewhere based on the ordered set of conditions that generate code here.
            
            // Redirect Shadow
            // A mask of stages ahead of this one (older) in which instructions are on the path of this instruction.
            // Index 1 is ahead by 1, etc.
            // In the example above, $GoodPathMask for Redir'edX == {0,0,0,0,1,1,0,0}
            //     (Looking up in the waterfall diagram from its first "o", in reverse order {o,X,o,o,y,y,o,o}.)
            // The LSB is fetch-valid. It only exists for m4_prev_instr_valid_through macro.
            $next_good_path_mask[M4_MAX_REDIRECT_BUBBLES+1:0] =
               // Shift up and mask w/ redirect conditions.
               {$GoodPathMask[M4_MAX_REDIRECT_BUBBLES:0]
                // & terms for each condition (order doesn't matter since masks are the same within a cycle)
                m4_redirect_squash_terms,
                1'b1}; // Shift in 1'b1 (fetch-valid).
            
            $GoodPathMask[M4_MAX_REDIRECT_BUBBLES+1:0] <=
               <<1$reset ? m4_eval(M4_MAX_REDIRECT_BUBBLES + 2)'b0 :  // All bad-path (through self) on reset (next mask based on next reset).
               $next_good_path_mask;
            
            m4_ifelse_block(M4_FORMAL, ['1'], ['
            // Formal verfication must consider trapping instructions. For this, we need to maintain $RvfiGoodPathMask, which is similar to
            // $GoodPathMask, except that it does not mask out aborted instructions.
            $next_rvfi_good_path_mask[M4_MAX_REDIRECT_BUBBLES+1:0] =
               {$RvfiGoodPathMask[M4_MAX_REDIRECT_BUBBLES:0]
                m4_redirect_shadow_terms,
                1'b1};
            $RvfiGoodPathMask[M4_MAX_REDIRECT_BUBBLES+1:0] <=
               <<1$reset ? m4_eval(M4_MAX_REDIRECT_BUBBLES + 2)'b0 :
               $next_rvfi_good_path_mask;
            '])
            
            
            // A returning load clobbers the instruction.
            // (Could do this with lower latency. Right now it goes through memory pipeline $ANY, and
            //  it is non-speculative. Both could easily be fixed.)
            $second_issue_ld = /_cpu|mem/data>>M4_LD_RETURN_ALIGN$valid_ld && 1'b['']M4_INJECT_RETURNING_LD;
            $second_issue = $second_issue_ld m4_ifelse(M4_EXT_M, 1, ['|| $second_issue_div_mul']);
            // Recirculate returning load.
            ?$second_issue
               // This scope holds the original load for a returning load.
               /orig_inst
                  // TODO: ... non-loads.
                  $ANY = /_cpu|mem/data>>M4_LD_RETURN_ALIGN$ANY;
                  /src[2:1]
                     $ANY = /_cpu|mem/data/src>>M4_LD_RETURN_ALIGN$ANY;
            
            // Next PC
            $pc_inc[M4_PC_RANGE] = $Pc + M4_PC_CNT'b1;
            // Current parsing does not allow concatenated state on left-hand-side, so, first, a non-state expression.
            {$next_pc[M4_PC_RANGE], $next_no_fetch} =
               $reset ? {M4_PC_CNT'b0, 1'b0} :
               // ? : terms for each condition (order does matter)
               m4_redirect_pc_terms
                          ({$pc_inc, 1'b0});
            // Then as state.
            $Pc[M4_PC_RANGE] <= $next_pc;
            $NoFetch <= $next_no_fetch;
         
         @M4_DECODE_STAGE

            // ======
            // DECODE
            // ======

            // Decode of the fetched instruction
            $valid_decode = $fetch;  // Always decode if we fetch.
            $valid_decode_branch = $valid_decode && $branch;
            // A load that will return later.
            //$split_ld = $spec_ld && 1'b['']M4_INJECT_RETURNING_LD;
            m4+indirect(M4_isa['_decode'])
         m4+indirect(['branch_pred_']M4_BRANCH_PRED)
         
         @M4_REG_RD_STAGE
            // Pending value to write to dest reg. Loads (not replaced by returning ld) write pending.
            $reg_wr_pending = $ld && ! $second_issue && 1'b['']M4_INJECT_RETURNING_LD;
            `BOGUS_USE($reg_wr_pending)  // Not used if no bypass and no pending.
            
            // ======
            // Reg Rd
            // ======
            
            // Obtain source register values and pending bit for source registers. Bypass up to 3
            // stages.
            // It is not necessary to bypass pending, as we could delay the replay, but we implement
            // bypass for performance.
            // Pending has an additional read for the dest register as we need to replay for write-after-write
            // hazard as well as write-after-read. To replay for dest write with the same timing, we must also
            // bypass the dest reg's pending bit.
            /M4_REGS_HIER
            /src[2:1]
               $is_reg_condition = $is_reg && /instr$valid_decode;  // Note: $is_reg can be set for RISC-V sr0.
               ?$is_reg_condition
                  {$reg_value[M4_WORD_RANGE], $pending} =
                     m4_ifelse(M4_ISA, ['RISCV'], ['($reg == M4_REGS_INDEX_CNT'b0) ? {M4_WORD_CNT'b0, 1'b0} :  // Read r0 as 0 (not pending).'])
                     // Bypass stages. Both register and pending are bypassed.
                     // Bypassed registers must be from instructions that are good-path as of this instruction or are 2nd issuing.
                     m4_ifexpr(M4_REG_BYPASS_STAGES >= 1, ['(/instr>>1$dest_reg_valid && (/instr$GoodPathMask[1] || /instr>>1$second_issue) && (/instr>>1$dest_reg == $reg)) ? {/instr>>1$rslt, /instr>>1$reg_wr_pending} :'])
                     m4_ifexpr(M4_REG_BYPASS_STAGES >= 2, ['(/instr>>2$dest_reg_valid && (/instr$GoodPathMask[2] || /instr>>2$second_issue) && (/instr>>2$dest_reg == $reg)) ? {/instr>>2$rslt, /instr>>2$reg_wr_pending} :'])
                     m4_ifexpr(M4_REG_BYPASS_STAGES >= 3, ['(/instr>>3$dest_reg_valid && (/instr$GoodPathMask[3] || /instr>>3$second_issue) && (/instr>>3$dest_reg == $reg)) ? {/instr>>3$rslt, /instr>>3$reg_wr_pending} :'])
                     {/instr/regs[$reg]>>M4_REG_BYPASS_STAGES$value, m4_ifelse(M4_PENDING_ENABLED, ['0'], ['1'b0'], ['/instr/regs[$reg]>>M4_REG_BYPASS_STAGES$pending'])};
               // Replay if this source register is pending.
               $replay = $is_reg_condition && $pending;
               $dummy = 1'b0;  // Dummy signal to pull through $ANY expressions when not building verification harness (since SandPiper currently complains about empty $ANY).
            // Also replay for pending dest reg to keep writes in order. Bypass dest reg pending to support this.
            $is_dest_condition = $dest_reg_valid && /instr$valid_decode;  // Note, $dest_reg_valid is 0 for RISC-V sr0.
            ?$is_dest_condition
               $dest_pending =
                  m4_ifelse(M4_ISA, ['RISCV'], ['($dest_reg == M4_REGS_INDEX_CNT'b0) ? 1'b0 :  // Read r0 as 0 (not pending). Not actually necessary, but it cuts off read of non-existent rs0, which might be an issue for formal verif tools.'])
                  // Bypass stages. Both register and pending are bypassed.
                  m4_ifexpr(M4_REG_BYPASS_STAGES >= 1, ['(>>1$dest_reg_valid && ($GoodPathMask[1] || /instr>>1$second_issue) && (>>1$dest_reg == $dest_reg)) ? >>1$reg_wr_pending :'])
                  m4_ifexpr(M4_REG_BYPASS_STAGES >= 2, ['(>>2$dest_reg_valid && ($GoodPathMask[2] || /instr>>2$second_issue) && (>>2$dest_reg == $dest_reg)) ? >>2$reg_wr_pending :'])
                  m4_ifexpr(M4_REG_BYPASS_STAGES >= 3, ['(>>3$dest_reg_valid && ($GoodPathMask[3] || /instr>>3$second_issue) && (>>3$dest_reg == $dest_reg)) ? >>3$reg_wr_pending :'])
                  m4_ifelse(M4_PENDING_ENABLED, ['0'], ['1'b0'], ['/regs[$dest_reg]>>M4_REG_BYPASS_STAGES$pending']);
            // Combine replay conditions for pending source or dest registers.
            $replay = | /src[*]$replay || ($is_dest_condition && $dest_pending);
         
         // =======
         // Execute
         // =======
         m4+indirect(M4_isa['_exe'], @M4_EXECUTE_STAGE, @M4_RESULT_STAGE)
         
         @M4_BRANCH_PRED_STAGE
            m4_ifelse(M4_BRANCH_PRED, ['fallthrough'], [''], ['$pred_taken_branch = $pred_taken && $branch;'])
         @M4_EXECUTE_STAGE

            // =======
            // Control
            // =======
            
            // Execute stage redirect conditions.
            $non_pipelined = $div_mul;
            $replay_trap = m4_cpu_blocked;
            $aborting_trap = $replay_trap || $illegal || $aborting_isa_trap;
            $non_aborting_trap = $non_aborting_isa_trap;
            $mispred_branch = $branch && ! ($conditional_branch && ($taken == $pred_taken));
            ?$valid_decode_branch
               $branch_redir_pc[M4_PC_RANGE] =
                  // If fallthrough predictor, branch mispred always redirects taken, otherwise PC+1 for not-taken.
                  m4_ifelse(M4_BRANCH_PRED, ['fallthrough'], [''], ['(! $taken) ? $Pc + M4_PC_CNT'b1 :'])
                  $branch_target;

            $trap_target[M4_PC_RANGE] = $replay_trap ? $Pc : {M4_PC_CNT{1'b1}};  // TODO: What should this be? Using ones to terminate test for now.
            
            // Determine whether the instruction should commit it's result.
            //
            // Abort: Instruction triggers a condition causing a no-commit.
            // Commit: Ultimate decision to commit results of this instruction, considering aborts and
            //         prior-instruction redirects (good-path)
            //
            // Treatment of loads:
            //    Loads will commit. They write a garbage value and "pending" to the register file.
            //    Returning loads clobber an instruction. This instruction is $abort'ed (as is the
            //    returning load, since they are one in the same). Returning load must explicitly
            //    write results.
            //
            
            $abort = m4_abort_terms;  // Note that register bypass logic requires that abort conditions also redirect.
            // $commit = m4_prev_instr_valid_through(M4_MAX_REDIRECT_BUBBLES + 1), where +1 accounts for this
            // instruction's redirects. However, to meet timing, we consider this instruction separately, so,
            // commit if valid as of the latest redirect from prior instructions and not abort of this instruction.
            m4_ifelse(M4_RETIMING_EXPERIMENT_ALWAYS_COMMIT, ['M4_RETIMING_EXPERIMENT_ALWAYS_COMMIT'], ['
            // Normal case:
            $commit = m4_prev_instr_valid_through(M4_MAX_REDIRECT_BUBBLES) && ! $abort;
            '], ['
            // For the retiming experiments, $commit is determined too late, and it is inconvenient to make the $GoodPathMask
            // logic retimable. Let's drive it to 1'b1 for now, and give synthesis the benefit of the doubt.
            $commit = 1'b1 && ! $abort;
            '])
            
            // Conditions that commit results.
            $valid_dest_reg_valid = ($dest_reg_valid && $commit) || $second_issue;
            $valid_ld = $ld && $commit;
            $valid_st = $st && $commit;

   m4+fixed_latency_fake_memory(/_cpu, 0)
   |fetch
      /instr
         @M4_REG_WR_STAGE
            // =========
            // Reg Write
            // =========

            $reg_write = $reset ? 1'b0 : $valid_dest_reg_valid;
            \SV_plus
               always @ (posedge clk) begin
                  if ($reg_write)
                     /regs[$dest_reg]<<0$$value[M4_WORD_RANGE] <= $rslt;
               end
            m4_ifelse_block(M4_PENDING_ENABLED, 1, ['
            // Write $pending along with $value, but coded differently because it must be reset.
            /regs[*]
               <<1$pending = ! /instr$reset && (((#regs == /instr$dest_reg) && /instr$valid_dest_reg_valid) ? /instr$reg_wr_pending : $pending);
            '])
            
         @M4_REG_WR_STAGE
            `BOGUS_USE(/orig_inst/src[2]$dummy) // To pull $dummy through $ANY expressions, avoiding empty expressions.

\TLV warpv_makerchip_cnt10_tb()
   |fetch
      /instr
         @M4_REG_WR_STAGE
            // Assert these to end simulation (before Makerchip cycle limit).
            $ReachedEnd <= $reset ? 1'b0 : $ReachedEnd || $Pc == {M4_PC_CNT{1'b1}};
            $Reg4Became45 <= $reset ? 1'b0 : $Reg4Became45 || ($ReachedEnd && /regs[4]$value == M4_WORD_CNT'd45);
            $passed = ! $reset && $ReachedEnd && $Reg4Became45;
            $failed = ! $reset && (*cyc_cnt > 200 || (*cyc_cnt > 5 && $commit && $illegal));

\TLV formal()
   // Instructions are presented to RVFI in reg wr stage. Loads cannot be presented until their load
   // data returns, so it is the returning ld that is presented. The instruction to present to RVFI
   // is provided in /instr/original. RVFI inputs are generally connected from this context,
   // except for the returning ld data. Also signals which are not relevant to loads are pulled straight from
   // /instr to avoid unnecessary recirculation.
   |fetch
      /instr
         @M4_REG_WR_STAGE
            
            $pc[M4_PC_RANGE] = $Pc[M4_PC_RANGE];  // A version of PC we can pull through $ANYs.
            // This scope is a copy of /instr or /instr/orig_inst if $second_issue.
            /original
               $ANY = /instr$second_issue ? /instr/orig_inst$ANY : /instr$ANY;
               /src[2:1]
                  $ANY = /instr$second_issue ? /instr/orig_inst/src$ANY : /instr/src$ANY;

            // RVFI interface for formal verification.
            $trap = $aborting_trap ||
                    $non_aborting_trap;
            $rvfi_trap        = ! $reset && >>m4_eval(-M4_MAX_REDIRECT_BUBBLES + 1)$next_rvfi_good_path_mask[M4_MAX_REDIRECT_BUBBLES] &&
                                $trap && ! $replay && ! $second_issue;  // Good-path trap, not aborted for other reasons.
            // Order for the instruction/trap for RVFI check. (For split instructions, this is associated with the 1st issue, not the 2nd issue.)
            $rvfi_order[63:0] = $reset                  ? 64'b0 :
                                ($commit || $rvfi_trap) ? >>1$rvfi_order + 64'b1 :
                                                          $RETAIN;
            $rvfi_valid       = ! <<m4_eval(M4_REG_WR_STAGE - (M4_NEXT_PC_STAGE - 1))$reset &&    // Avoid asserting before $reset propagates to this stage.
                                (($commit && ! $ld) || $rvfi_trap || $second_issue);
            *rvfi_valid       = $rvfi_valid;
            *rvfi_halt        = $rvfi_trap;
            *rvfi_trap        = $rvfi_trap;
            /original
               *rvfi_insn        = $raw;
               *rvfi_order       = $rvfi_order;
               *rvfi_intr        = 1'b0;
               *rvfi_rs1_addr    = /src[1]$is_reg ? $raw_rs1 : 5'b0;
               *rvfi_rs2_addr    = /src[2]$is_reg ? $raw_rs2 : 5'b0;
               *rvfi_rs1_rdata   = /src[1]$is_reg ? /src[1]$reg_value : M4_WORD_CNT'b0;
               *rvfi_rs2_rdata   = /src[2]$is_reg ? /src[2]$reg_value : M4_WORD_CNT'b0;
               *rvfi_rd_addr     = (/instr$dest_reg_valid && ! $abort) ? $raw_rd : 5'b0;
               *rvfi_rd_wdata    = *rvfi_rd_addr  ? /instr$rslt : 32'b0;
            *rvfi_pc_rdata    = {/original$pc[31:2], 2'b00};
            *rvfi_pc_wdata    = {$reset          ? M4_PC_CNT'b0 :
                                 $second_issue   ? /orig_inst$pc + 1'b1 :
                                 $trap           ? $trap_target :
                                 $jump           ? $jump_target :
                                 $mispred_branch ? ($taken ? $branch_target[M4_PC_RANGE] : $pc + M4_PC_CNT'b1) :
                                 m4_ifelse(M4_BRANCH_PRED, ['fallthrough'], [''], ['$pred_taken_branch ? $branch_target[M4_PC_RANGE] :'])
                                 $indirect_jump  ? $indirect_jump_target :
                                 $pc[31:2] +1'b1, 2'b00};
            *rvfi_mem_addr    = (/original$ld || $valid_st) ? {/original$addr[M4_ADDR_MAX:2], 2'b0} : 0;
            *rvfi_mem_rmask   = /original$ld ? /orig_inst$ld_mask : 0;
            *rvfi_mem_wmask   = $valid_st ? $st_mask : 0;
            *rvfi_mem_rdata   = /original$ld ? /orig_inst$ld_value : 0;
            *rvfi_mem_wdata   = $valid_st ? $st_value : 0;

            `BOGUS_USE(/src[2]$dummy)

// Ingress/Egress packet buffers between the CPU and NoC.
// Packet buffers are m4+vc_flop_fifo_v2(...)s. See m4+vc_flop_fifo_v2 definition in tlv_flow_lib package
//   and instantiations below for interface.
// NoC must provide |egress_out interface and |ingress_in m4+vc_flop_fifo_v2(...) interface.
\TLV noc_cpu_buffers(/_cpu, #depth)
   // Egress FIFO.
   // Block CPU |fetch pipeline if blocked.
   m4_define(['m4_cpu_blocked'], m4_cpu_blocked || /_cpu|egress_in<<M4_EXECUTE_STAGE$pkt_wr_blocked || /_cpu|ingress_out<<M4_EXECUTE_STAGE$pktrd_blocked)
   |egress_in
      // Stage numbering has @0 == |fetch@M4_EXECUTE_STAGE 
      @0
         $ANY = /_cpu|fetch/instr>>M4_EXECUTE_STAGE$ANY;  // (including $reset)
         $is_pkt_wr = $is_csr_write && ($is_csr_pktwr || $is_csr_pkttail);
         $vc[M4_VC_INDEX_RANGE] = $csr_pktwrvc[M4_VC_INDEX_RANGE];
         // This PKTWR write is blocked if the skid buffer blocked last cycle.
         $pkt_wr_blocked = $is_pkt_wr && /skid_buffer>>1$push_blocked;
      @1
         $valid_pkt_wr = $is_pkt_wr && $commit;
         /skid_buffer
            // Hold the write if blocked.
            // This give 1 cycle of slop so we have time to check validity and generate a replay if blocked.
            $push_blocked = $valid_pkt_wr && /_cpu/vc[$csr_pktwrvc]|egress_in$blocked;
            $ANY = >>1$push_blocked ? >>1$ANY : |egress_in$ANY;
         /trans
            $flit[M4_WORD_RANGE] = |egress_in/skid_buffer$csr_wr_value;
   /vc[*]
      |egress_in
         @1
            $vc_trans_valid = /_cpu|egress_in/skid_buffer$valid_pkt_wr && (/_cpu|egress_in/skid_buffer$vc == #vc);
   m4+vc_flop_fifo_v2(/_cpu, |egress_in, @1, |egress_out, @1, #depth, /trans, M4_VC_RANGE, M4_PRIO_RANGE)
   /vc[*]
      |egress_out
         @0
            $has_credit = 1'b0 /*FIX*/;
            $Prio[M4_PRIO_INDEX_RANGE] <= '0;
   |egress_out
      /trans
         @1
            `BOGUS_USE($flit)
   
   // Ingress FIFO.
   //
   // To avoid a critical path, we replay
   //   CSR read of PKTRD if there was a
   //   CSR write of PKTRDVCS the cycle prior.
   // This allows us to use a value of PKTRDVCS that is one cycle old.
   // Staging of CSR read of PKTRD is:
   //   @DECODE
   //      - Determine CSR write of PKTRDVCS
   //   @EXECUTE-1 (which is likely @REG_RD)
   //      - Detect PKTRDVCS change
   //      - Arb VC FIFOs and MUX data among VCs
   //   @EXECUTE
   //      - Bypass VC FIFOs
   //      - CSR mux and result MUX
   |fetch
      /instr
         // Data from VC_FIFO is made available by the end of |ingress_out@-1(arb/byp) == M4_EXECUTE_STAGE-1
         // reflecting prior-prior!-stage PKTRDVCS
         // so it can be captured in PKTRD and used by M4_EXECUTE_STAGE (== |ingress_out@0(out))
         @M4_EXECUTE_STAGE  // == |ingress_out@0
            // CSR PKTRD is written by hardware as the head of the ingress buffer.
            // Write if there is head data, else, CSR is invalid.
            $csr_pktrd_valid = /_cpu|ingress_out<<M4_EXECUTE_STAGE$trans_valid;
            ?$csr_pktrd_valid
               $csr_pktrd[M4_WORD_RANGE] = /_cpu|ingress_out/trans<<M4_EXECUTE_STAGE$flit;
   |ingress_out
      @-1
         // Note that we access signals here that are produced in @M4_DECODE_STAGE, so @M4_DECODE_STAGE must not be the same physical stage as @M4_EXECUTE_STAGE.
         $ANY = /_cpu|fetch/instr>>M4_EXECUTE_STAGE$ANY;
         $is_pktrd = $is_csr_instr && $is_csr_pktrd;
         // Detect a recent change to PKTRDVCS that could invalidate the use of a stale PKTRDVCS value and must avoid read (which will force a replay).
         $pktrdvcs_changed = >>1$is_csr_write && >>1$is_csr_pktrdvcs;
         $do_pktrd = $is_pktrd && ! $pktrdvcs_changed;
      @0
         // Replay for PKTRD with no data read.
         $pktrd_blocked = $is_pktrd && ! $trans_valid;
   /vc[*]
      |ingress_out
         @-1
            $has_credit = /_cpu|ingress_out>>1$csr_pktrdvcs[#vc] &&
                          /_cpu|ingress_out$do_pktrd;
            $Prio[M4_PRIO_INDEX_RANGE] <= '0;
   m4+vc_flop_fifo_v2(/_cpu, |ingress_in, @0, |ingress_out, @0, #depth, /trans, M4_VC_RANGE, M4_PRIO_RANGE)
   /M4_VC_HIER
      |ingress_in
         @0
            $vc_trans_valid = 1'b0;  // TODO
   |ingress_in
      @0
         $reset = *reset;  // TODO
      /trans
         @0
            $flit[31:0] = 32'b0;  // TODO


m4+module_def

\TLV warpv()
   // =================
   //
   //    THE MODEL
   //
   // =================
   

   m4+cpu(/top)
   m4_ifelse_block(M4_FORMAL, 1, ['
   m4+formal()
   '], [''])

// Hookup Makerchip *passed/*failed signals to CPU $passed/$failed.
// Args:
//   /_hier: Scope of core(s), e.g. [''] or ['/core[*]'].
\TLV makerchip_pass_fail(/_hier)
   |done
      @0
         // Assert these to end simulation (before Makerchip cycle limit).
         *passed = & /top/_hier|fetch/instr>>M4_REG_WR_STAGE$passed;
         *failed = | /top/_hier|fetch/instr>>M4_REG_WR_STAGE$failed;

\TLV
   /* verilator lint_off WIDTH */  // Let's be strict about bit widths.
   m4_ifelse_block(m4_eval(M4_CORE_CNT > 1), ['1'], ['
   // Multi-core
   /M4_CORE_HIER
      m4+noc_cpu_buffers(/core, 4)
      m4+cpu(/core)
      m4+warpv_makerchip_cnt10_tb()
   //m4+simple_ring(/core, |noc_in, @1, |noc_out, @1, /top<>0$reset, |rg, /trans)
   m4+makerchip_pass_fail(core[*])
   '], ['
   // Single Core.
   m4+warpv()
   m4+warpv_makerchip_cnt10_tb() // parameterise to other programs
   m4+makerchip_pass_fail()
   '])
\SV
   endmodule
