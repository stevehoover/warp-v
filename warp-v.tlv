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
   //       /fetch_instr reflects the instruction fetched from i-memory, and /commit_instr reflects the
   //       instruction that will be committed. The difference is returning_ld instructions which commit
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
   
   // This design is an incomplete RISC-V implementation.
   // Most instructions are characterized. The primary missing pieces are:
   //   o expressions for executing many instructions
   //   o ISA extensions
   //   o byte-level addressing
   // The implementation is based on "The RISC-V Instruction Set Manual Vol. I: User-Level ISA," Version 2.2: https://riscv.org/specifications/

                     
                     
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
   m4_default(['M4_ISA'], ['RISCV']) // MINI, RISCV, DUMMY, etc.
   // Select a standard configuration:
   m4_default(['M4_STANDARD_CONFIG'], ['5-stage'])  // 1-stage, 5-stage, 7-stage, none (and define individual parameters).
   
   // Include testbench (for Makerchip simulation) (defaulted to 1).
   m4_default(['M4_TB'], 1)  // 0 to disable testbench and instrumentation code.
   // Build for formal verification (defaulted to 0).
   m4_default(['M4_FORMAL'], 0)  // 1 to enable code for formal verification


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
   //       M4_EXTRA_JUMP_BUBBLE:       0 or 1. 0 aligns PC_MUX with EXECUTE for jumps.
   //       M4_EXTRA_PRED_TAKEN_BUBBLE: 0 or 1. 0 aligns PC_MUX with EXECUTE for pred_taken.
   //       M4_EXTRA_INDIRECT_JUMP_BUBBLE: 0 or 1. 0 aligns PC_MUX with EXECUTE for indirect_jump.
   //       M4_EXTRA_REPLAY_BUBBLE:     0 or 1. 0 aligns PC_MUX with EXECUTE for replays.
   //       M4_EXTRA_BRANCH_BUBBLE:     0 or 1. 0 aligns PC_MUX with EXECUTE for branches.
   //   M4_BRANCH_PRED: {fallthrough, two_bit, ...}
   //   M4_DATA_MEM_WORDS: Number of data memory locations.
   m4_case(M4_STANDARD_CONFIG,
      ['5-stage'], ['
         // A reasonable 5-stage pipeline.
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
            (M4_LD_RETURN_ALIGN, 4))
         m4_define(['M4_BRANCH_PRED'], ['two_bit'])
         m4_define_hier(M4_DATA_MEM_WORDS, 32)
      '],
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
         m4_define(['M4_BRANCH_PRED'], ['fallthrough'])
         m4_define_hier(M4_DATA_MEM_WORDS, 32)
      '],
      ['7-stage'], ['
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
         m4_define(['M4_BRANCH_PRED'], ['two_bit'])
         m4_define_hier(M4_DATA_MEM_WORDS, 32)
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
            (['M4_EXT_M'], 0),
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
   m4_case(M4_ISA, ['MINI'], ['
         // Mini-CPU Characterization:
         m4_define(['M4_NOMINAL_BRANCH_TARGET_CALC_STAGE'], ['M4_EXECUTE_STAGE'])
      '], ['RISCV'], ['
         // RISC-V Characterization:
         m4_define(['M4_NOMINAL_BRANCH_TARGET_CALC_STAGE'], ['M4_DECODE_STAGE'])
      '], ['DUMMY'], ['
         // DUMMY Characterization:
         m4_define(['M4_NOMINAL_BRANCH_TARGET_CALC_STAGE'], ['M4_EXECUTE_STAGE'])
      ']
   )

   // Supply defaults for extra cycles.
   m4_defines(
      (M4_DELAY_BRANCH_TARGET_CALC, 0),
      (M4_EXTRA_JUMP_BUBBLE, 0),
      (M4_EXTRA_PRED_TAKEN_BUBBLE, 0),
      (M4_EXTRA_INDIRECT_JUMP_BUBBLE, 0),
      (M4_EXTRA_REPLAY_BUBBLE, 0),
      (M4_EXTRA_BRANCH_BUBBLE, 0)
   )
   
   // Calculated stages:
   m4_define(M4_REG_BYPASS_STAGES,  m4_eval(M4_REG_WR_STAGE - M4_REG_RD_STAGE))
   m4_define(M4_BRANCH_TARGET_CALC_STAGE, m4_eval(M4_NOMINAL_BRANCH_TARGET_CALC_STAGE + M4_DELAY_BRANCH_TARGET_CALC))

   // Latencies/bubbles calculated from stage parameters and extra bubbles:
   // (zero bubbles minimum if triggered in next_pc; minimum bubbles = computed-stage - next_pc-stage)
   m4_define(['M4_PRED_TAKEN_BUBBLES'], m4_eval(M4_BRANCH_PRED_STAGE - M4_NEXT_PC_STAGE + M4_EXTRA_PRED_TAKEN_BUBBLE))
   m4_define(['M4_REPLAY_BUBBLES'],     m4_eval(M4_REG_RD_STAGE - M4_NEXT_PC_STAGE + M4_EXTRA_REPLAY_BUBBLE))
   m4_define(['M4_JUMP_BUBBLES'],       m4_eval(M4_EXECUTE_STAGE - M4_NEXT_PC_STAGE + M4_EXTRA_JUMP_BUBBLE))
   m4_define(['M4_BRANCH_BUBBLES'],     m4_eval(M4_EXECUTE_STAGE - M4_NEXT_PC_STAGE + M4_EXTRA_BRANCH_BUBBLE))
   m4_define(['M4_INDIRECT_JUMP_BUBBLES'], m4_eval(M4_EXECUTE_STAGE - M4_NEXT_PC_STAGE + M4_EXTRA_INDIRECT_JUMP_BUBBLE))
   m4_define(['M4_TRAP_BUBBLES'],       m4_eval(M4_EXECUTE_STAGE - M4_NEXT_PC_STAGE + 1))  // Could parameterize w/ M4_EXTRA_TRAP_BUBBLE (rather than always 1), but not perf-critical.
   m4_define(['M4_RETURNING_LD_BUBBLES'], 0)
   // TODO: Make the returning_ld mechanism optional (where load instruction writes reg file).
   
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

         m4_define(M4_NUM_INSTRS, 13)  // (Must match program exactly.)

      '],
      ['RISCV'], ['
         // Definitions matching "The RISC-V Instruction Set Manual Vol. I: User-Level ISA", Version 2.2.

         m4_define_vector(['M4_INSTR'], 32)
         m4_define_vector(['M4_ADDR'], 32)
         m4_define(['M4_BITS_PER_ADDR'], 8)  // 8 for byte addressing.
         m4_define_vector(['M4_WORD'], 32)
         m4_define_hier(['M4_REGS'], 32, 1)

         m4_define(M4_NUM_INSTRS, 11)  // (Must match program exactly.)

      '],
      ['DUMMY'], ['
         m4_define_vector(M4_INSTR, 2)
         m4_define_vector(M4_ADDR, 2)
         m4_define(['M4_BITS_PER_ADDR'], 2)
         m4_define_vector(M4_WORD, 2)
         m4_define_hier(M4_REGS, 8)

         m4_define(M4_NUM_INSTRS, 2)  // (Must match program exactly.)

      '])
   
   
   
   
   // Computed ISA uarch Parameters (based on ISA-specific parameters).

   m4_define(['M4_ADDRS_PER_WORD'], m4_eval(M4_WORD_CNT / M4_BITS_PER_ADDR))
   m4_define(['M4_SUB_WORD_BITS'], m4_width(m4_eval(M4_ADDRS_PER_WORD - 1)))
   m4_define(['M4_ADDRS_PER_INSTR'], m4_eval(M4_INSTR_CNT / M4_BITS_PER_ADDR))
   m4_define(['M4_SUB_PC_BITS'], m4_width(m4_eval(M4_ADDRS_PER_INSTR - 1)))
   m4_define_vector(['M4_PC'], M4_ADDR_HIGH, M4_SUB_PC_BITS)
   m4_define(['M4_FULL_PC'], ['{$Pc, M4_SUB_PC_BITS'b0}'])
   m4_define_hier(M4_DATA_MEM_ADDRS, m4_eval(M4_DATA_MEM_WORDS_HIGH * M4_ADDRS_PER_WORD))  // Addressable data memory locations.

   
   
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
   //m4_define(['m4_redirect_signal_list'], ['{0{1'b0}}'])  // concatination terms for each trigger condition (naturally-aligned). Start w/ a 0-bit term for concatination.
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
   // to various definitions, initializes above.
   // Args:
   //   $1: name of define of number of bubble cycles
   //   $2: condition signal of triggering instr
   //   $3: target PC signal of triggering instructiton
   //   $4: 1 for an aborting redirect (0 otherwise)
   m4_define(['m4_process_redirect_condition'],
             ['// expression in @M4_NEXT_PC_STAGE asserting for the redirect condition.
               // = instruction triggers this condition && it's on the current path && it's not masked by an earlier aborting redirect
               //   of this instruction.
               // Params: $@ (m4_redirect_masking_triggers contains param use)
               m4_pushdef(['m4_redir_cond'],
                          ['(>>m4_echo($1)$2 && !(']m4_echo(m4_redirect_masking_triggers)[') && $GoodPathMask[m4_echo($1)])'])
               //m4_define(['$1_order'], $5)   // Order of this condition. (Not used, so commented)
               m4_define(['m4_redirect_list'],
                         m4_dquote(m4_redirect_list, ['$1']))
               m4_define(['m4_redirect_squash_terms'],
                         ['']m4_redirect_squash_terms[' & (m4_echo(']m4_redir_cond($@)[') ? {{m4_eval(M4_TRAP_BUBBLES + 1 - m4_echo($1) - $4){1'b1}}, {m4_eval(m4_echo($1) + $4){1'b0}}} : {m4_eval(M4_TRAP_BUBBLES + 1){1'b1}})'])
               m4_define(['m4_redirect_shadow_terms'],
                         ['']m4_redirect_shadow_terms[' & (m4_echo(']m4_redir_cond($@)[') ? {{m4_eval(M4_TRAP_BUBBLES + 1 - m4_echo($1)     ){1'b1}}, {m4_eval(m4_echo($1)     ){1'b0}}} : {m4_eval(M4_TRAP_BUBBLES + 1){1'b1}})'])
               m4_define(['m4_redirect_pc_terms'],
                         ['m4_echo(']m4_redir_cond($@)[') ? >>m4_echo($1)$3 : ']m4_redirect_pc_terms[' '])
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
      ['['M4_RETURNING_LD_BUBBLES'], $returning_ld, $Pc, 1'],
      m4_ifelse(M4_BRANCH_PRED, ['fallthrough'], [''], ['['['M4_PRED_TAKEN_BUBBLES'], $pred_taken_branch, $branch_target, 0'],'])
      ['['M4_REPLAY_BUBBLES'], $replay, $Pc, 1'],
      ['['M4_JUMP_BUBBLES'], $jump, $jump_target, 0'],
      ['['M4_BRANCH_BUBBLES'], $mispred_branch, $branch_redir_pc, 0'],
      m4_ifelse(M4_ISA, ['RISCV'], ['['['M4_INDIRECT_JUMP_BUBBLES'], $indirect_jump, $indirect_jump_target, 0'],'], [''])
      ['['M4_TRAP_BUBBLES'], $aborting_trap, $trap_target, 1'],
      ['['M4_TRAP_BUBBLES'], $non_aborting_trap, $trap_target, 0'])

   // Ensure proper order.
   // TODO: It would be great to auto-sort.
   m4_ordered(m4_redirect_list)

      
   // m4_valid_as_of(M4_BLAH_STAGE) can be used to determine if an instruction is known to be invalid at a certain pipeline stage.
   // It can be used as the when condition for logic in the give stage (just for a bit of power savings). We probably won't
   // bother using it, but it's available in any case. It can be used as:
   // @M4_BLAH_STAGE
   //    $blah_valid = m4_valid_as_of(M4_BLAH_STAGE)
   //    ?$blah_valid
   //       ...
   // m4_valid_as_of(M4_NEXT_PC_STAGE) is fetch-valid (we know we need a new PC, but we don't know the PC or we know it can't
   //    be fetched -- currently 1'b1).
   // m4_valid_as_of(M4_NEXT_PC_STAGE + 1) is de-asserted by one-bubble redirects from previous instruction.
   // m4_valid_as_of(M4_NEXT_PC_STAGE + 2) is de-asserted by one- and two-bubble redirects from previous instruction and
   //    two-bubble redirects from previous previous instruction.
   // etc.
   // Since we can be looking back an arbitrary number of cycles, we'll force invalid if $reset.
   m4_define(['m4_valid_as_of'],
             ['(! $reset && >>m4_eval(M4_NEXT_PC_STAGE - ($1) + 1)$next_good_path_mask[($1) - M4_NEXT_PC_STAGE])'])
   //same as >>m4_eval(M4_NEXT_PC_STAGE - $1)$GoodPathMask[$1 - M4_NEXT_PC_STAGE]), but accessible 1 cycle earlier and without $reset term.



   // ======================
   // Code Generation Macros
   // ======================
   //
   m4_case(M4_ISA, ['MINI'], ['
      // An out-of-place correction for the fact that in Mini-CPU, instruction
      // addresses are to different memory than data, and the memories have different widths.
      m4_define_vector(['M4_PC'], 10, 0)
      
   '], ['RISCV'], ['
      // For each op5 value, we associate an instruction type.
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
      // Return 1 if the given instruction is supported, [''] otherwise.
      m4_define(['m4_instr_supported'],
                ['m4_ifelse(M4_EXT_$3, 1, ['m4_ifelse(M4_WORD_CNT, ['$2'], 1,
                                                    [''])'],
                            [''])'])
      // Instantiated (in \SV_plus context) for each instruction.
      m4_define_hide(['m4_instr'],
                     ['// check instr type
                       m4_ifelse(M4_OP5_$4_TYPE, $1, [''],
                                 ['m4_errprint(['Instruction ']m4_argn($#, $@)[''s type ($1) is inconsistant with its op5 code ($4) of type ']M4_OP5_$4_TYPE[' on line ']m4___line__[' of file ']m4_FILE.m4_new_line)'])
                       // if instrs extension is supported and instr is for the right machine width, "
                       m4_ifelse(m4_instr_supported($@), 1, ['m4_show(['localparam [6:0] ']']m4_argn($#, $@)['['_INSTR_OPCODE = 7'b$4['']11;m4_instr$1(m4_shift($@))'])'],
                                 [''])'])
      m4_define(['m4_instr_func'],
                ['m4_instr_decode_expr($5, ['$raw_op5 == 5'b$3 && $raw_funct3 == 3'b$4'], $6)[' localparam [2:0] $5_INSTR_FUNCT3 = 3'b']$4;'])
      m4_define(['m4_instr_no_func'],
                ['m4_instr_decode_expr($4, ['$raw_op5 == 5'b$3'])'])
      // Macros to create, for each instruction (xxx):
      //   o instructiton decode: $is_xxx_instr = ...; ...
      //   o result combining expr.: ({32{$is_xxx_instr}} & $xxx_rslt) | ...
      //   o $illegal computation: && ! $is_xxx_instr ...
      //   o $mnemonic: $is_xxx_instr ? "XXX" : ...
      m4_define(['m4_decode_expr'], [''])
      m4_define(['m4_rslt_mux_expr'], [''])
      m4_define(['m4_illegal_instr_expr'], [''])
      m4_define(['m4_mnemonic_expr'], [''])
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
      // Unique to each instruction type.
      // This includes assembler macros as follows. Fields are ordered rd, rs1, rs2, imm:
      //   I: m4_asm_ADDI(r4, r1, 0),
      //   R: m4_asm_ADD(r4, r1, r2),  // optional 4th arg for funct7
      //   S: m4_asm_SW(r1, r2, 100),  // Store r13 into [r10] + 4
      //   B: m4_asm_BLT(r1, r2, 1000), // Branch if r1 < r2 to PC + 13'b1000 (where lsb = 0)
      m4_define(['m4_instrI'], ['m4_instr_func($@)m4_define(['m4_asm_$5'], ['m4_asm_instr_str(I, ['$5'], $']['@){12'b']m4_arg(3)[', m4_asm_reg(']m4_arg(2)['), $5_INSTR_FUNCT3, m4_asm_reg(']m4_arg(1)['), $5_INSTR_OPCODE}'])'])
      m4_define(['m4_instrR'], ['m4_instr_func($@)m4_define(['m4_asm_$5'], ['m4_asm_instr_str(R, ['$5'], $']['@){7'b['']m4_ifelse(']m4_arg(4)[', [''], 0, ']m4_arg(4)['), m4_asm_reg(']m4_arg(3)['), m4_asm_reg(']m4_arg(2)['), $5_INSTR_FUNCT3, m4_asm_reg(']m4_arg(1)['), $5_INSTR_OPCODE}'])'])
      m4_define(['m4_instrRI'], ['m4_instr_func($@)'])
      m4_define(['m4_instrR4'], ['m4_instr_func($@)'])
      m4_define(['m4_instrS'], ['m4_instr_func($@, ['no_dest'])m4_define(['m4_asm_$5'], ['m4_asm_instr_str(S, ['$5'], $']['@){m4_asm_imm_field(']m4_arg(3)[', 12, 11, 5), m4_asm_reg(']m4_arg(2)['), m4_asm_reg(']m4_arg(1)['), $5_INSTR_FUNCT3, m4_asm_imm_field(']m4_arg(3)[', 12, 4, 0), $5_INSTR_OPCODE}'])'])
      m4_define(['m4_instrB'], ['m4_instr_func($@, ['no_dest'])m4_define(['m4_asm_$5'], ['m4_asm_instr_str(B, ['$5'], $']['@){m4_asm_imm_field(']m4_arg(3)[', 13, 12, 12), m4_asm_imm_field(']m4_arg(3)[', 13, 10, 5), m4_asm_reg(']m4_arg(2)['), m4_asm_reg(']m4_arg(1)['), $5_INSTR_FUNCT3, m4_asm_imm_field(']m4_arg(3)[', 13, 4, 1), m4_asm_imm_field(']m4_arg(3)[', 13, 11, 11), $5_INSTR_OPCODE}'])'])
      m4_define(['m4_instrJ'], ['m4_instr_no_func($@)'])
      m4_define(['m4_instrU'], ['m4_instr_no_func($@)'])
      m4_define(['m4_instr_'], ['m4_instr_no_func($@)'])

      // For each instruction type.
      // Declare localparam[31:0] INSTR_TYPE_X_MASK, initialized to 0 that will be given a 1 bit for each op5 value of its type.
      m4_define(['m4_instr_types_args'], ['I, R, RI, R4, S, B, J, U, _'])
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
      // Specific asm instruction macros, in cases where the type-based defaults are insufficient.
      m4_define(['m4_asm_ADD'], ['m4_asm_ADD_SUB($1, $2, $3)'])
      m4_define(['m4_asm_SUB'], ['m4_asm_ADD_SUB($1, $2, $3, 0100000)'])

      // For debug, a string for an asm instruction.
      m4_define(['m4_asm_mem_expr'], [''])
      // m4_asm_instr_str(<type>, <mnemonic>, <m4_asm-args>)
      m4_define(['m4_asm_instr_str'], ['m4_pushdef(['m4_str'], ['($1) $2 m4_shift(m4_shift($@))'])m4_define(['m4_asm_mem_expr'],
                                                       m4_dquote(m4_asm_mem_expr[' "']m4_str['']m4_substr(['                                        '], m4_len(m4_quote(m4_str)))['", ']))m4_popdef(['m4_str'])'])

      //=========
   '], ['DUMMY'], ['
   '])


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
/* verilator lint_on WIDTH */  // Let's be strict about bit widths.






//============================//
//                            //
//         MINI-CPU           //
//                            //
//============================//

\TLV mini_cnt10_prog()
   \SV_plus
      
      // /=====================\
      // | Count to 10 Program |
      // \=====================/
      //
      // (The program I wrote, within the model I wrote, within the program I wrote.)
      
      // Add 1,2,3,...,10 (in that order).
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
   $dest_is_reg = ($dest_char >= "a" && $dest_char <= "h") || $returning_ld;
   $dest_reg_valid = $dest_is_reg;
   $fetch_instr_dest_reg[7:0] = $dest_char - "a";
   $dest_reg[2:0] = $returning_ld ? /original_ld$dest_reg : $fetch_instr_dest_reg[2:0];
   $jump = $dest_char == "P";
   $branch = $dest_char == "p";
   $no_dest = $dest_char == "0";
   $write_pc = $jump || $branch;
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


// Execution unit logic for RISC-V.
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
            $returning_ld ? /original_ld$ld_value :
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

\TLV riscv_cnt10_prog()
   m4_ifexpr(M4_TB, ['
   \SV_plus
      logic [40*8-1:0] instr_strs [0:M4_NUM_INSTRS];
      
      // /=====================\
      // | Count to 10 Program |
      // \=====================/
      //
      
      // Add 1,2,3,...,10 (in that order).
      // Store incremental results in memory locations 0..9. (1, 3, 6, 10, ...)
      //
      // Regs:
      // 1: cnt
      // 2: ten
      // 3: out
      // 4: tmp
      // 5: offset
      // 6: store addr
      
      assign instrs = '{
         m4_asm_ORI(r6, r0, 0),        //     store_addr = 0
         m4_asm_ORI(r1, r0, 1),        //     cnt = 1
         m4_asm_ORI(r2, r0, 1010),     //     ten = 10
         m4_asm_ORI(r3, r0, 0),        //     out = 0
         m4_asm_ADD(r3, r1, r3),       //  -> out += cnt
         m4_asm_SW(r6, r3, 0),         //     store out at store_addr
         m4_asm_ADDI(r1, r1, 1),       //     cnt ++
         m4_asm_ADDI(r6, r6, 100),     //     store_addr++
         m4_asm_BLT(r1, r2, 1111111110000), //  ^- branch back if cnt < 10
         m4_asm_LW(r4, r6,   111111111100), //     load the final value into tmp
         m4_asm_BGE(r1, r2, 1111111010100)  //     TERMINATE by branching to -1
      };
      
      assign instr_strs = '{m4_asm_mem_expr "END                                     "};
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
      m4_op5(01011, RI, AMO)  // (R-type, but rs2 = const for some, based on funct7 which doesn't exist for I-type?? R-type w/ ignored R2?)
      m4_op5(01100, R, OP)
      m4_op5(01101, U, LUI)
      m4_op5(01110, R, OP_32)
      m4_op5(01111, _, 64B)
      m4_op5(10000, R4, MADD)
      m4_op5(10001, R4, MSUB)
      m4_op5(10010, R4, NMSUB)
      m4_op5(10011, R4, NMADD)
      m4_op5(10100, RI, OP_FP)  // (R-type, but rs2 = const for some, based on funct7 which doesn't exist for I-type?? R-type w/ ignored R2?)
      m4_op5(10101, _, RESERVED_1)
      m4_op5(10110, _, CUSTOM_2_RV128)
      m4_op5(10111, _, 48B2)
      m4_op5(11000, B, BRANCH)
      m4_op5(11001, I, JALR)
      m4_op5(11010, _, RESERVED_2)
      m4_op5(11011, J, JAL)
      m4_op5(11100, _, SYSTEM)
      m4_op5(11101, _, RESERVED_3)
      m4_op5(11110, _, CUSTOM_3_RV128)
      m4_op5(11111, _, 80B)
      
   \SV_plus
      // Not sure these are ever used.
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
      m4_instr(R, 32, I, 01100, 000, ADD_SUB)  // Treated as a single instruction.
      m4_instr(R, 32, I, 01100, 001, SLL)
      m4_instr(R, 32, I, 01100, 010, SLT)
      m4_instr(R, 32, I, 01100, 011, SLTU)
      m4_instr(R, 32, I, 01100, 100, XOR)
      m4_instr(R, 32, I, 01100, 101, SRL_SRA)  // Treated as a single instruction.
      m4_instr(R, 32, I, 01100, 110, OR)
      m4_instr(R, 32, I, 01100, 111, AND)
      //m4_instr(_, 32, I, 00011, 000, FENCE)
      //m4_instr(_, 32, I, 00011, 001, FENCE_I)
      //m4_instr(_, 32, I, 11100, 000, ECALL_EBREAK)  // Two instructions distinguished by an immediate bit, treated as a single instruction.
      //m4_instr(_, 32, I, 11100, 001, CSRRW)
      //m4_instr(_, 32, I, 11100, 010, CSRRS)
      //m4_instr(_, 32, I, 11100, 011, CSRRC)
      //m4_instr(_, 32, I, 11100, 101, CSRRWI)
      //m4_instr(_, 32, I, 11100, 110, CSRRSI)
      //m4_instr(_, 32, I, 11100, 111, CSRRCI)
      m4_instr(I, 64, I, 00000, 110, LWU)
      m4_instr(I, 64, I, 00000, 011, LD)
      m4_instr(S, 64, I, 01000, 011, SD)
      m4_instr(I, 64, I, 00100, 001, SLLI)
      m4_instr(I, 64, I, 00100, 101, SRLI_SRAI)  // Two instructions distinguished by an immediate bit, treated as a single instruction.
      m4_instr(I, 64, I, 00110, 000, ADDIW)
      m4_instr(I, 64, I, 00110, 001, SLLIW)
      m4_instr(I, 64, I, 00110, 101, SRLIW_SRAIW)  // Two instructions distinguished by an immediate bit, treated as a single instruction.
      m4_instr(R, 64, I, 01110, 000, ADDW_SUBW)  // Two instructions distinguished by an immediate bit, treated as a single instruction.
      m4_instr(R, 64, I, 01110, 001, SLLW)
      m4_instr(R, 64, I, 01110, 101, SRLW_SRAW)  // Two instructions distinguished by an immediate bit, treated as a single instruction.
      m4_instr(R, 32, M, 01100, 000, MUL)
      m4_instr(R, 32, M, 01100, 001, MULH)
      m4_instr(R, 32, M, 01100, 010, MULHSU)
      m4_instr(R, 32, M, 01100, 011, MULHU)
      m4_instr(R, 32, M, 01100, 100, DIV)
      m4_instr(R, 32, M, 01100, 101, DIVU)
      m4_instr(R, 32, M, 01100, 110, REM)
      m4_instr(R, 32, M, 01100, 111, REMU)
      m4_instr(R, 64, M, 01110, 000, MULW)
      m4_instr(R, 64, M, 01110, 100, DIVW)
      m4_instr(R, 64, M, 01110, 101, DIVUW)
      m4_instr(R, 64, M, 01110, 110, REMW)
      m4_instr(R, 64, M, 01110, 111, REMUW)
      // RV32A and RV64A
      // NOT IMPLEMENTED. These are distinct in the func7 field.
      // RV32F and RV64F
      // NOT IMPLEMENTED.
      // RV32D and RV64D
      // NOT IMPLEMENTED.


   // ^---------------------

// These are expanded in a separate TLV  macro because multi-line expansion is a no-no for line tracking.
// This keeps the implications contained.
\TLV riscv_decode_expr()
   m4_echo(m4_decode_expr)

\TLV riscv_rslt_mux_expr()
   $rslt[M4_WORD_RANGE] =
       $returning_ld ? /original_ld$ld_rslt :
       M4_WORD_CNT'b0['']m4_echo(m4_rslt_mux_expr);

\TLV riscv_decode()
   // TODO: ?$valid_<stage> conditioning should be replaced by use of m4_valid_as_of(M4_BLAH_STAGE).
   ?$valid_decode

      // =================================

      // Extract fields of $raw (instruction) into $raw_<field>[x:0].
      m4_into_fields(['M4_INSTR'], ['$raw'])
      `BOGUS_USE($raw_funct7 $raw_op2)  // Delete once its used.
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

      $illegal = 1'b1['']m4_illegal_instr_expr;
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
         $is_reg = /instr$is_r_type || /instr$is_r4_type || (/instr$is_i_type && (#src == 1)) || /instr$is_ri_type || /instr$is_s_type || /instr$is_b_type;
         $reg[M4_REGS_INDEX_RANGE] = (#src == 1) ? /instr$raw_rs1 : /instr$raw_rs2;
           
      // For debug.
      $mnemonic[10*8-1:0] = m4_mnemonic_expr "ILLEGAL   ";
      `BOGUS_USE($mnemonic)
   // Condition signals must not themselves be conditioned (currently).
   $dest_reg[M4_REGS_INDEX_RANGE] = $returning_ld ? /original_ld$dest_reg : $raw_rd;
   $dest_reg_valid = (($valid_decode && ! $is_s_type && ! $is_b_type) || $returning_ld) &&
                     | $dest_reg;   // r0 not valid.
   // Actually load.
   $spec_ld = $valid_decode && $ld;
   
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
               {($is_blt_instr ^ /src[2]$reg_value[M4_WORD_MAX]), /src[2]$reg_value[M4_WORD_MAX-1:0]}) ^ ((/src[1]$reg_value[M4_WORD_MAX] != /src[2]$reg_value[M4_WORD_MAX]) & $is_bge_instr)
              )
             )
            );
      ?$indirect_jump  // (JALR)
         $indirect_jump_full_target[31:0] = /src[1]$reg_value + $raw_i_imm;
         $indirect_jump_target[M4_PC_RANGE] = $indirect_jump_full_target[M4_PC_RANGE];
         $misaligned_indirect_jump_target = $indirect_jump_full_target[1];
      ?$valid_exe
         // Compute each individual instruction result, combined per-instruction by a macro.
         
         $lui_rslt[M4_WORD_RANGE] = {$raw_u_imm[31:12], 12'b0};
         $auipc_rslt[M4_WORD_RANGE] = M4_FULL_PC + $raw_u_imm;
         $jal_rslt[M4_WORD_RANGE] = M4_FULL_PC + 4;
         $jalr_rslt[M4_WORD_RANGE] = M4_FULL_PC + 4;
         $lb_rslt[M4_WORD_RANGE] = 32'b0;    // Load results arrive w/ returning load.
         $lh_rslt[M4_WORD_RANGE] = 32'b0;    // So, these are unused.
         $lw_rslt[M4_WORD_RANGE] = 32'b0;
         $lbu_rslt[M4_WORD_RANGE] = 32'b0;
         $lhu_rslt[M4_WORD_RANGE] = 32'b0;
         $addi_rslt[M4_WORD_RANGE] = /src[1]$reg_value + $raw_i_imm;  // Note: this has its own adder; could share w/ add/sub.
         $xori_rslt[M4_WORD_RANGE] = /src[1]$reg_value ^ $raw_i_imm;
         $ori_rslt[M4_WORD_RANGE] = /src[1]$reg_value | $raw_i_imm;
         $andi_rslt[M4_WORD_RANGE] = /src[1]$reg_value & $raw_i_imm;
         $slli_rslt[M4_WORD_RANGE] = /src[1]$reg_value << $raw_i_imm[5:0];
         $srli_intermediate_rslt[M4_WORD_RANGE] = /src[1]$reg_value >> $raw_i_imm[5:0];
         $srai_intermediate_rslt[M4_WORD_RANGE] = /src[1]$reg_value[M4_WORD_MAX] ? $srli_intermediate_rslt | ((M4_WORD_HIGH'b0 - 1) << (M4_WORD_HIGH - $raw_i_imm[5:0]) ): $srli_intermediate_rslt;
         $sra_intermediate_rslt[M4_WORD_RANGE] = /src[1]$reg_value[M4_WORD_MAX] ? $srl_intermediate_rslt | ((M4_WORD_HIGH'b0 - 1) << (M4_WORD_HIGH - /src[2]$reg_value[4:0]) ): $srl_intermediate_rslt;
         $srl_intermediate_rslt[M4_WORD_RANGE] = /src[1]$reg_value >> /src[2]$reg_value[4:0];
         $slti_rslt[M4_WORD_RANGE] =  (/src[1]$reg_value[M4_WORD_MAX] == $raw_i_imm[M4_WORD_MAX]) ? $sltiu_rslt : {M4_WORD_MAX'b0,/src[1]$reg_value[M4_WORD_MAX]};
         $sltiu_rslt[M4_WORD_RANGE] = (/src[1]$reg_value < $raw_i_imm) ? 1 : 0;
         $srli_srai_rslt[M4_WORD_RANGE] = ($raw_i_imm[10] == 1) ? $srai_intermediate_rslt : $srli_intermediate_rslt;
         $add_sub_rslt[M4_WORD_RANGE] =  ($raw_funct7[5] == 1) ?  /src[1]$reg_value - /src[2]$reg_value : /src[1]$reg_value + /src[2]$reg_value;
         $sll_rslt[M4_WORD_RANGE] = /src[1]$reg_value << /src[2]$reg_value[4:0];
         $slt_rslt[M4_WORD_RANGE] = (/src[1]$reg_value[M4_WORD_MAX] == /src[2]$reg_value[M4_WORD_MAX]) ? $sltu_rslt : {M4_WORD_MAX'b0,/src[1]$reg_value[M4_WORD_MAX]};
         $sltu_rslt[M4_WORD_RANGE] = (/src[1]$reg_value < /src[2]$reg_value) ? 1 : 0;
         $xor_rslt[M4_WORD_RANGE] = /src[1]$reg_value ^ /src[2]$reg_value;
         $srl_sra_rslt[M4_WORD_RANGE] = ($raw_funct7[5] == 1) ? $sra_intermediate_rslt : $srl_intermediate_rslt;
         $or_rslt[M4_WORD_RANGE] = /src[1]$reg_value | /src[2]$reg_value;
         $and_rslt[M4_WORD_RANGE] = /src[1]$reg_value & /src[2]$reg_value;
   @_exe_stage
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
      ?$returning_ld
         /original_ld
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
      // ISA-specific trap conditions:
      // I can't see in the spec which of these is to commit results. I've made choices that make riscv-formal happy.
      $non_aborting_isa_trap = ($branch && $taken && $misaligned_pc) ||
                               ($jump && $misaligned_jump_target) ||
                               ($indirect_jump && $misaligned_indirect_jump_target);
      $aborting_isa_trap =     ($ld_st && $unnatural_addr_trap);
      
   @_rslt_stage
      // Mux the correct result.
      m4+riscv_rslt_mux_expr()
   



//============================//
//                            //
//        DUMMY-CPU           //
//                            //
//============================//

\TLV dummy_cnt10_prog()
   \SV_plus
      assign instrs = '{2'b1, 2'b10};

\TLV dummy_gen()
   // No M4-generated code for dummy.

\TLV dummy_decode()
   /src[2:1]
      `BOGUS_USE(/instr$raw[0])
      $is_reg = 1'b0;
      $reg[M4_REGS_INDEX_RANGE] = 3'b1;
      $value[M4_WORD_RANGE] = 2'b1;
   $dest_reg_valid = 1'b1;
   $dest_reg[M4_REGS_INDEX_RANGE] = $returning_ld ? /original_ld$dest_reg : 3'b0;
   $ld = 1'b0;
   $spec_ld = $ld;
   $st = 1'b0;
   $illegal = 1'b0;
   $branch = 1'b0;
   $jump = 1'b0;
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
         $returning_ld ? /original_ld$ld_value :
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
// The returned load result can be accessed from /cpu|mem/data<<M4_ALIGNMENT_VALUE$ANY as $ld_value and $ld
// (along w/ everything else in the input instruction).

// A fake memory with fixed latency.
// The memory is placed in the fetch pipeline.
// TODO: (/_cpu, @_mem, @_align)
\TLV fixed_latency_fake_memory(/cpu, M4_ALIGNMENT_VALUE)
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
            $ANY = /cpu|fetch/instr>>M4_ALIGNMENT_VALUE$ANY;
            /src[2:1]
               $ANY = /cpu|fetch/instr/src>>M4_ALIGNMENT_VALUE$ANY;




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
      $branch_or_reset = $branch || $reset;
      ?$branch_or_reset
         $BranchState[1:0] <=
            $reset ? 2'b01 :
            $taken ? ($BranchState == 2'b11 ? $RETAIN : $BranchState + 2'b1) :
                     ($BranchState == 2'b00 ? $RETAIN : $BranchState - 2'b1);




//=========================//
//                         //
//        THE CPU          //
//       (All ISAs)        //
//                         //
//=========================//

\TLV cpu()
   
   // Generated logic
   m4+indirect(M4_isa['_gen'])

   m4_ifelse_block(M4_TB, 1, ['
   // The program in an instruction memory.
   \SV_plus
      logic [M4_INSTR_RANGE] instrs [0:M4_NUM_INSTRS-1];
   m4+indirect(M4_isa['_cnt10_prog'])
   '])


   // /=========\
   // | The CPU |
   // \=========/

   |fetch
      /instr
         // Provide a longer reset to cover the pipeline depth.
         @m4_stage_eval(@M4_NEXT_PC_STAGE<<1)
            $Cnt[7:0] <= *reset        ? 8'b0 :       // reset
                         $Cnt == 8'hFF ? 8'hFF :      // max out to avoid wrapping
                                         $Cnt + 8'b1; // increment
            $reset = *reset || $Cnt < m4_eval(M4_LD_RETURN_ALIGN + M4_MAX_REDIRECT_BUBBLES + 3);
         
         @M4_FETCH_STAGE
            $fetch = ! $reset;  // always fetch
            ?$fetch

               // =====
               // Fetch
               // =====

               // Fetch the raw instruction from program memory (or, for formal, tie it off).
               $raw[M4_INSTR_RANGE] = m4_ifelse(M4_TB, 0, ['32'bx'], ['*instrs\[$Pc[m4_eval(M4_PC_MIN + m4_width(M4_NUM_INSTRS-1) - 1):M4_PC_MIN]\]']);
            
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
            //   o Replay: (aborting) Replay the same instruction (because a source register is pending (awaiting a returning_ld))
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
            //         Triggers for Inst 3
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
            // The LSB is fetch-valid. It only exists for m4_valid_as_of macro.
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
            $returning_ld = /top|mem/data>>M4_LD_RETURN_ALIGN$valid_ld;
            // Recirculate returning load.
            ?$returning_ld
               // This scope holds the original load for a returning load.
               /original_ld
                  $ANY = /top|mem/data>>M4_LD_RETURN_ALIGN$ANY;
                  /src[2:1]
                     $ANY = /top|mem/data/src>>M4_LD_RETURN_ALIGN$ANY;
            
            // Next PC
            $Pc[M4_PC_RANGE] <=
               $reset ? M4_PC_CNT'b0 :
               // ? : terms for each condition (order does matter)
               m4_redirect_pc_terms
                        $Pc + M4_PC_CNT'b1;
         
         @M4_DECODE_STAGE

            // ======
            // DECODE
            // ======

            // Decode of the fetched instruction
            $valid_decode = $fetch;  // Always decode if we fetch.
            $valid_decode_branch = $valid_decode && $branch;
            m4+indirect(M4_isa['_decode'])
         m4+indirect(['branch_pred_']M4_BRANCH_PRED)
         
         @M4_REG_RD_STAGE
            // Pending value to write to dest reg. Loads (not replaced by returning ld) write pending.
            $reg_wr_pending = $ld && ! $returning_ld;
            
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
                     // Bypassed registers must be from instructions that are good-path as of this instruction or are returning_ld.
                     m4_ifexpr(M4_REG_BYPASS_STAGES >= 1, ['(/instr>>1$dest_reg_valid && (/instr$GoodPathMask[1] || /instr>>1$returning_ld) && (/instr>>1$dest_reg == $reg)) ? {/instr>>1$rslt, /instr>>1$reg_wr_pending} :'])
                     m4_ifexpr(M4_REG_BYPASS_STAGES >= 2, ['(/instr>>2$dest_reg_valid && (/instr$GoodPathMask[2] || /instr>>2$returning_ld) && (/instr>>2$dest_reg == $reg)) ? {/instr>>2$rslt, /instr>>2$reg_wr_pending} :'])
                     m4_ifexpr(M4_REG_BYPASS_STAGES >= 3, ['(/instr>>3$dest_reg_valid && (/instr$GoodPathMask[3] || /instr>>3$returning_ld) && (/instr>>3$dest_reg == $reg)) ? {/instr>>3$rslt, /instr>>3$reg_wr_pending} :'])
                     {/instr/regs[$reg]>>M4_REG_BYPASS_STAGES$value, /instr/regs[$reg]>>M4_REG_BYPASS_STAGES$pending};
               // Replay if this source register is pending.
               $replay = $is_reg_condition && $pending;
               $dummy = 1'b0;  // Dummy signal to pull through $ANY expressions when not building verification harness (since SandPiper currently complains about empty $ANY).
            // Also replay for pending dest reg to keep writes in order. Bypass dest reg pending to support this.
            $is_dest_condition = $dest_reg_valid && /instr$valid_decode;  // Note, $dest_reg_valid is 0 for RISC-V sr0.
            ?$is_dest_condition
               $dest_pending =
                  m4_ifelse(M4_ISA, ['RISCV'], ['($dest_reg == M4_REGS_INDEX_CNT'b0) ? 1'b0 :  // Read r0 as 0 (not pending). Not actually necessary, but it cuts off read of non-existent rs0, which might be an issue for formal verif tools.'])
                  // Bypass stages. Both register and pending are bypassed.
                  m4_ifexpr(M4_REG_BYPASS_STAGES >= 1, ['(>>1$dest_reg_valid && ($GoodPathMask[1] || /instr>>1$returning_ld) && (>>1$dest_reg == $dest_reg)) ? >>1$reg_wr_pending :'])
                  m4_ifexpr(M4_REG_BYPASS_STAGES >= 2, ['(>>2$dest_reg_valid && ($GoodPathMask[2] || /instr>>2$returning_ld) && (>>2$dest_reg == $dest_reg)) ? >>2$reg_wr_pending :'])
                  m4_ifexpr(M4_REG_BYPASS_STAGES >= 3, ['(>>3$dest_reg_valid && ($GoodPathMask[3] || /instr>>3$returning_ld) && (>>3$dest_reg == $dest_reg)) ? >>3$reg_wr_pending :'])
                  /regs[$dest_reg]>>M4_REG_BYPASS_STAGES$pending;
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
            $aborting_trap = $illegal || $aborting_isa_trap;
            $non_aborting_trap = $non_aborting_isa_trap;
            $mispred_branch = $branch && ! ($conditional_branch && ($taken == $pred_taken));
            ?$valid_decode_branch
               $branch_redir_pc[M4_PC_RANGE] =
                  // If fallthrough predictor, branch mispred always redirects taken, otherwise PC+1 for not-taken.
                  m4_ifelse(['M4_BRANCH_PRED'], ['fallthrough'], [''], ['(! $taken) ? $Pc + M4_PC_CNT'b1 :'])
                  $branch_target;

            $trap_target[M4_PC_RANGE] = M4_PC_CNT'b0;  // TODO: What should this be?
            
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
            // $commit = m4_valid_as_of(M4_NEXT_PC_STAGE + M4_MAX_REDIRECT_BUBBLES + 1), where +1 accounts for this
            // instruction's redirects. However, to meet timing, we consider this instruction separately, so,
            // commit if valid as of the latest redirect from prior instructions and not abort of this instruction.
            $commit = m4_valid_as_of(M4_NEXT_PC_STAGE + M4_MAX_REDIRECT_BUBBLES) && ! $abort;
            
            // Conditions that commit results.
            $valid_dest_reg_valid = ($dest_reg_valid && $commit) || $returning_ld;
            $valid_ld = $ld && $commit;
            $valid_st = $st && $commit;

   m4+fixed_latency_fake_memory(/top, 0)
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
            // Write $pending along with $value, but coded differently because it must be reset.
            /regs[*]
               <<1$pending = ! /instr$reset && (((#regs == /instr$dest_reg) && /instr$valid_dest_reg_valid) ? /instr$reg_wr_pending : $pending);

         @M4_REG_WR_STAGE
            `BOGUS_USE(/original_ld/src[2]$dummy) // To pull $dummy through $ANY expressions, avoiding empty expressions.

\TLV tb()
   |fetch
      /instr
         @M4_REG_WR_STAGE
            // Assert these to end simulation (before Makerchip cycle limit).
            $ReachedEnd <= $reset ? 1'b0 : $ReachedEnd || $Pc == {M4_PC_CNT{1'b1}};
            $Reg4Became45 <= $reset ? 1'b0 : $Reg4Became45 || ($ReachedEnd && /regs[4]$value == M4_WORD_CNT'd45);
            *passed = ! *reset && $ReachedEnd && $Reg4Became45;
            *failed = ! *reset && (*cyc_cnt > 200 || (! |fetch/instr>>3$reset && |fetch/instr>>6$commit && |fetch/instr>>6$illegal));

\TLV formal()
   |fetch
      @M4_REG_WR_STAGE
         /instr
            $pc[M4_PC_RANGE] = $Pc[M4_PC_RANGE];  // A version of PC we can pull through $ANYs.
            // This scope is a copy of /instr or /instr/original_ld if $returning_ld.
            /original
               $ANY = /instr$returning_ld ? /instr/original_ld$ANY : /instr$ANY;
               /src[2:1]
                  $ANY = /instr$returning_ld ? /instr/original_ld/src$ANY : /instr/src$ANY;

            // RVFI interface for formal verification.
            $trap = $aborting_trap ||
                    $non_aborting_trap;
            $rvfi_trap        = ! $reset && >>m4_eval(-M4_MAX_REDIRECT_BUBBLES + 1)$next_rvfi_good_path_mask[M4_MAX_REDIRECT_BUBBLES] &&
                                $trap && ! $replay && ! $returning_ld;  // Good-path trap, not aborted for other reasons.
            // Order for the instruction/trap for RVFI check. (For ld, this is associated with the ld itself, not the returning_ld.)
            $rvfi_order[63:0] = $reset                  ? 64'b0 :
                                ($commit || $rvfi_trap) ? >>1$rvfi_order + 64'b1 :
                                                          $RETAIN;
            $rvfi_valid       = ! <<m4_eval(M4_REG_WR_STAGE - (M4_NEXT_PC_STAGE - 1))$reset &&    // Avoid asserting before $reset propagates to this stage.
                                (($commit && ! $ld) || $rvfi_trap || $returning_ld);
            *rvfi_valid       = $rvfi_valid;
            *rvfi_insn        = /original$raw;
            *rvfi_halt        = $rvfi_trap;
            *rvfi_trap        = $rvfi_trap;
            *rvfi_order       = /original$rvfi_order;
            *rvfi_intr        = 1'b0;
            *rvfi_rs1_addr    = /original/src[1]$is_reg ? /original$raw_rs1 : 5'b0;
            *rvfi_rs2_addr    = /original/src[2]$is_reg ? /original$raw_rs2 : 5'b0;
            *rvfi_rs1_rdata   = /original/src[1]$is_reg ? /original/src[1]$reg_value : M4_WORD_CNT'b0;
            *rvfi_rs2_rdata   = /original/src[2]$is_reg ? /original/src[2]$reg_value : M4_WORD_CNT'b0;
            *rvfi_rd_addr     = ($dest_reg_valid && ! /original$abort) ? /original$raw_rd : 5'b0;
            *rvfi_rd_wdata    = *rvfi_rd_addr  ? $rslt : 32'b0;
            *rvfi_pc_rdata    = {/original$pc[31:2], 2'b00};
            *rvfi_pc_wdata    = {$reset         ? M4_PC_CNT'b0 :
                                 $returning_ld   ? /original_ld$pc + 1'b1 :
                                 $trap           ? $trap_target :
                                 $jump           ? $jump_target :
                                 $mispred_branch ? ($taken ? $branch_target[M4_PC_RANGE] : $pc + M4_PC_CNT'b1) :
                                 m4_ifelse(M4_BRANCH_PRED, ['fallthrough'], [''], ['$pred_taken_branch ? $branch_target[M4_PC_RANGE] :'])
                                 $indirect_jump  ? $indirect_jump_target :
                                 $pc[31:2] +1'b1, 2'b00};
            *rvfi_mem_addr    = (/original$ld || $valid_st) ? {/original$addr[M4_ADDR_MAX:2], 2'b0} : 0;
            *rvfi_mem_rmask   = /original$ld ? /original_ld$ld_mask : 0;
            *rvfi_mem_wmask   = $valid_st ? $st_mask : 0;
            *rvfi_mem_rdata   = /original$ld ? /original_ld$ld_value : 0;
            *rvfi_mem_wdata   = $valid_st ? $st_value : 0;

            `BOGUS_USE(/src[2]$dummy)

m4+module_def

\TLV
   // =================
   //
   //    THE MODEL
   //
   // =================
   
   m4+cpu()
   m4_ifelse_block(M4_TB, 1, ['
   m4+tb()
   '])
\SV
   endmodule

