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
   //   o If you've come here to learn about RISC-V design with TL-Verilog, you might be better served
   //     to start with these models created in the Microprocessor for You in Thirty Hours (MYTH) Workshop:
   //     https://github.com/stevehoover/RISC-V_MYTH_Workshop/blob/master/student_projects.md.
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
   //     data out of order (though, they do not).
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
   //   o Load instructions complete without writing their destination registers. Destination
   //     registers are instead marked "pending", and reads of pending registers are replayed.
   //   o This could again result in a read of the same pending register and can repeat until
   //     the load returns. Writes to pending registers are also replayed, so there can be at
   //     most one oustanding load to any given register. 
   //   o This way, out-of-order loads are
   //     supported (though loads are implemented to have a fixed latency). A returning load
   //     reserves an instruction slot at the beginning of the pipeline to reserve a register
   //     write port. The returning load writes its result and clears the destination
   //     register's pending flag.
   //
   // To support L1 and L2 caches, it would be reasonable to delay register write (if
   // necessary) to wait for L1 hits (extending the bypass window), and mark "pending"
   // for L1 misses. Power could be saved by going idle on replay until load will return
   // data.
   //
   // Long-latency pipelined instructions:
   //
   //    Long-latency pipelined instructions can utilize the same split issue and pending
   //    mechanisms as load instructions.
   //
   // Long-latency non-pipelined instructions:
   //
   //   o In the current implementation, bit manipulation(few), floating point and integer multiplication / 
   //     division instructions are non-pipelined, followed by "no-fetch" cycles 
   //     until the next redirect (which will be a second issue of the instruction).
   //   o The data required during second can be passed to the commit stage using /orig_inst scope
   //   o It does not matter whether registers are marked pending, but we do.
   //   o Process redirect conditions take care of the correct handling of PC for such instrctions.
   //   o \TLV m_extension() can serve as a reference implementation for correctly stalling the pipeline
   //     for such instructions
   // 
   // Handling loads and long-latency instructions:
   //    
   //   o For any instruction that requires second issue, some of its attributes (such as
   //     destination register, raw value, rs1/rs2/rd) depending on where they are consumed
   //     need to be retained. $ANY construct is used to make this logic generic and use-dependent. 
   //   o In case of loads, the /orig_load_inst scope is used to hook up the 
   //     mem pipeline to the CPU pipeline in first pipestage (of CPU) to reserve slot for the load 
   //     flowing from mem to CPU in the second issue.
   //   o For non-pipelined instructions such as mul-div, the /hold_inst scope retains the values
   //     till the second issue. 
   //   o Both the scopes are merged into /orig_inst scope depending on which instruction the second
   //     issue belongs to.
   //
   // Bypass:
   //
   //    Register bypass is provided if one instruction's result is not written to the
   //    register file in time for the next instruction's read. An additional bypass is
   //    provided for each additional cycle between read and write.
   //
   // Memory:
   //
   //    The program is stored in its own instruction memory (for simplicity).
   //    Data memory is separate.
   //
   
   // TODO: It might be cleaner to split /instr into two scopes: /fetch_instr and /commit_instr, where
   //       /fetch_instr reflects the instruction fetched from i-memory (1st issue), and /commit_instr reflects the
   //       instruction that will be committed (2nd issue). The difference is long-latency instructions which commit
   //       in place of the fetch instruction. There have been several subtle bugs where the fetch
   //       instruction leaks into the commit instruction (esp. reg. bypass), and this would help to
   //       avoid them.
   //
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
   //     ~ : Extended constant (D = {1[2:0], 2[2:0]})
   //     , : Combine (D = {1[11:6], 2[5:0]})
   //     ? : Conditional (D = 2 ? `0 : 1)
   //   Load (Eg: "c=a:b") (D = [1 + 2] (typically 1 would be an immediate offset):
   //     ) : Load
   //   Store (Eg: "0=a;b") ([2] = 1):
   //     ( : Store
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
   
   // This design is a RISC-V (RV32IMF) implementation.
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
      // If not externally defined:
      m4_define_hier(['M4_CORE'], 1)  // Number of cores.
      m4_define_hier(['M4_VC'], 2)    // VCs (meaningful if > 1 core).
      m4_define_hier(['M4_PRIO'], 2)  // Number of priority levels in the NoC.
      m4_define(['M4_MAX_PACKET_SIZE'], 3)   // Max number of payload flits in a packet.
      m4_define_vector_with_fields(M4_FLIT, 32, UNUSED, m4_eval(M4_CORE_INDEX_CNT * 2 + M4_VC_INDEX_CNT) , SRC, m4_eval(M4_CORE_INDEX_CNT + M4_VC_INDEX_CNT), VC, M4_CORE_INDEX_CNT, DEST, 0)
   '])
   // Inclusions for multi-core only:
   m4_ifexpr(M4_CORE_CNT > 1, ['
      m4_ifelse(M4_ISA, ['RISCV'], [''], ['m4_errprint(['Multi-core supported for RISC-V only.']m4_new_line)'])
      m4_include_url(['https:/']['/raw.githubusercontent.com/stevehoover/tlv_lib/481188115b4338567df916460d462ca82401e211/fundamentals_lib.tlv'])
      m4_include_url(['https:/']['/raw.githubusercontent.com/stevehoover/tlv_flow_lib/7a2b37cc0ccd06bc66984c37e17ceb970fd6f339/pipeflow_lib.tlv'])
   '])
   
   // Include visualization
   m4_default(['M4_VIZ'], 1)
   // Include testbench (for Makerchip simulation) (defaulted to 1).
   m4_default(['M4_IMPL'], 0)  // For implementation (vs. simulation).
   // Build for formal verification (defaulted to 0).
   m4_default(['M4_FORMAL'], 0)  // 1 to enable code for formal verification
	m4_default(['M4_RISCV_FORMAL_ALTOPS'], 0)  // riscv-formal uses alternate operations (add/sub and xor with a constant value)
                                              // instead of actual mul/div, this is enabled automatically when formal is used, 
                                              // can be enabled manually for testing in Makerchip environment.

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
      ['2-stage'], ['
         // 2-stage pipeline.
         m4_defines(
            (M4_NEXT_PC_STAGE, 0),
            (M4_FETCH_STAGE, 0),
            (M4_DECODE_STAGE, 0),
            (M4_BRANCH_PRED_STAGE, 0),
            (M4_REG_RD_STAGE, 0),
            (M4_EXECUTE_STAGE, 1),
            (M4_RESULT_STAGE, 1),
            (M4_REG_WR_STAGE, 1),
            (M4_MEM_WR_STAGE, 1),
            (M4_LD_RETURN_ALIGN, 2))
         m4_define(['M4_BRANCH_PRED'], ['two_bit'])
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
         //   RV32IM 2.0, w/ FA ISA extensions WIP.

         // Machine width
         m4_define_vector(['M4_WORD'], 32)  // 32 or RV32X or 64 for RV64X.
         // ISA extensions,  1, or 0 (following M4 boolean convention).
         // TODO. Currently formal checks are broken when M4_EXT_F is set to 1.
         // TODO. Currently formal checks takes long time(~48 mins) when M4_EXT_B is set to 1.
         //       Hence, its disabled at present.
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

   // Which program to assemble.
   // this depends on the ISA extension(s) choice
   m4_ifelse(M4_EXT_M, 1, ['m4_define(['M4_PROG_NAME'], ['divmul_test'])'], ['m4_define(['M4_PROG_NAME'], ['cnt10'])'])
   //m4_ifelse(M4_EXT_F, 1, ['m4_define(['M4_PROG_NAME'], ['fpu_test'])'], ['m4_define(['M4_PROG_NAME'], ['cnt10'])'])
   //m4_ifelse(M4_EXT_B, 1, ['m4_define(['M4_PROG_NAME'], ['bmi_test'])'], ['m4_define(['M4_PROG_NAME'], ['cnt10'])'])

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
   // Unfortunately, this modeling does not work because of the redirection logic. When timed @0, the $GoodPathMask would
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
         m4_define_hier(['M4_FPUREGS'], 32, 0)
         
         // Controls SV generation:
         m4_define(['m4_use_localparams'], 0)
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
      ['['M4_SECOND_ISSUE_BUBBLES'], $second_issue, $second_issue_ld ? $Pc : $pc_inc, 1'],
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
         m4_define_csr(['cycle'],      12'hC00,    ['32, CYCLE, 0'],               ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_define_csr(['cycleh'],     12'hC80,    ['32, CYCLEH, 0'],              ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_define_csr(['time'],       12'hC01,    ['32, CYCLE, 0'],               ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_define_csr(['timeh'],      12'hC81,    ['32, CYCLEH, 0'],              ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_define_csr(['instret'],    12'hC02,    ['32, INSTRET, 0'],             ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_define_csr(['instreth'],   12'hC82,    ['32, INSTRETH, 0'],            ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_ifelse_block(M4_EXT_F, 1, ['
         m4_define_csr(['fflags'],     12'h001,    ['5, FFLAGS, 0'],               ['5'b0'],                      ['{5{1'b1}}'],                      1)
         m4_define_csr(['frm'],        12'h002,    ['3, FRM, 0'],                  ['3'b0'],                      ['{3{1'b1}}'],                      1)
         m4_define_csr(['fcsr'],       12'h003,    ['8, FCSR, 0'],                 ['8'b0'],                      ['{8{1'b1}}'],                      1)
         '])                                
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
         m4_define_csr(['core'],       12'h80d,    ['M4_CORE_INDEX_HIGH, CORE, 0'],    ['M4_CORE_INDEX_HIGH'b0'],     ['{M4_CORE_INDEX_HIGH{1'b1}}'],      RO)
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
   // For CPU instructions, it would be a good idea to try to link this instruction description with
   // GCC's (whatever that might be). Either output GCC compatible descriptions or convert GCC to what we do here
   // --------------------------------------------------
   
   m4_case(M4_ISA, ['MINI'], ['
      // An out-of-place correction for the fact that in Mini-CPU, instruction
      // addresses are to different memory than data, and the memories have different widths.
      m4_define_vector(['M4_PC'], 10, 0)
      
   '], ['RISCV'], ['
      // Included as tlv lib file.
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
            output logic [1: 0] rvfi_ixl,
            output logic [1: 0] rvfi_mode,
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
   m4_ifexpr(M4_CORE_CNT > 1, ['m4_include_lib(['https://raw.githubusercontent.com/stevehoover/tlv_flow_lib/4bcf06b71272556ec7e72269152561902474848e/pipeflow_lib.tlv'])'])
   m4_ifelse(M4_ISA, ['RISCV'], ['m4_include_lib(['https://raw.githubusercontent.com/stevehoover/warp-v_includes/8b5cfb9ffd9830aaf44297280682bedfe8bef3e3/risc-v_defs.tlv'])'])




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
         
         "0=d;g",  //    store out at store_addr, 
         "e=c-b", //     tmp = nine - cnt
         "p=f?e", //     branch back if tmp >= 0
         "e=0)c", //     load the final value into tmp
         "P=0-1"  //     TERMINATE by jumping to -1
      }; 

\TLV mini_imem(_prog_name)
   m4+indirect(['mini_']_prog_name['_prog'])
   m4+instrs_for_viz()
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
      $ld = $char == ")";
      $st = $char == "(";
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
   // Default program for RV32I test
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
 
   m4_asm(ORI, r6, r0, 0)        //     store_addr = 0
   m4_asm(ORI, r1, r0, 1)        //     cnt = 1
   m4_asm(ORI, r2, r0, 1010)     //     ten = 10
   m4_asm(ORI, r3, r0, 0)        //     out = 0
   m4_asm(ADD, r3, r1, r3)       //  -> out += cnt
   m4_asm(SW, r6, r3, 0)         //     store out at store_addr
   m4_asm(ADDI, r1, r1, 1)       //     cnt ++
   m4_asm(ADDI, r6, r6, 100)     //     store_addr++
   m4_asm(BLT, r1, r2, 1111111110000) //  ^- branch back if cnt < 10
   m4_asm(LW, r4, r6,   111111111100) //     load the final value into tmp
   m4_asm(BGE, r1, r2, 1111111010100) //     TERMINATE by branching to -1

\TLV riscv_divmul_test_prog()
   // /==========================\
   // | M-extension Test Program |
   // \==========================/
   //
   //3 MULs followed by 3 DIVs, check r11-r15 for correct results

   m4_asm(ORI, r8, r0, 1011)
   m4_asm(ORI, r9, r0, 1010)
   m4_asm(ORI, r10, r0, 10101010)
   m4_asm(MUL, r11, r8, r9)
   m4_asm(ORI, r6, r0, 0)
   m4_asm(SW, r6, r11, 0)
   m4_asm(MUL, r12, r9, r10)
   m4_asm(LW, r4, r6, 0)
   m4_asm(ADDI, r6, r6, 100)
   m4_asm(SW, r6, r12, 0)
   m4_asm(MUL, r13, r8, r10)
   m4_asm(DIV, r14, r11, r8)
   m4_asm(DIV, r15, r13, r10)
   m4_asm(LW, r5, r6, 0)
   m4_asm(ADDI, r4, r0, 101101)
   m4_asm(BGE, r8, r9, 111111111110)

\TLV riscv_fpu_test_prog()
   // /==========================\
   // | F-extension Test Program |
   // \==========================/
   //
   m4_asm(LUI, r1, 01110001010101100000)
   m4_asm(ADDI, r1, r1, 010001000001)
   m4_asm(LUI, r2, 01100101100101001111)
   m4_asm(ADDI, r2, r2, 010001000000)
   m4_asm(LUI, r3, 01001101110111110001)
   m4_asm(ADDI, r3, r3, 010000000000)
   m4_asm(FMVWX, r1, r1)
   m4_asm(FMVWX, r2, r2)
   m4_asm(FMVWX, r3, r3)
   m4_asm(FSW, r0, r1, 000001000000)
   m4_asm(FSW, r0, r2, 000001000100)
   m4_asm(FLW, r16, r0, 000001000000)
   m4_asm(FLW, r17, r0, 000001000100)
   m4_asm(FMADDS, r5, r1, r2, r3, 000)
   m4_asm(FMSUBS, r6, r1, r2, r3, 000)
   m4_asm(FNMSUBS, r7, r1, r2, r3, 000)
   m4_asm(FNMADDS, r8, r1, r2, r3, 000)
   m4_asm(CSRRS, r20, r0, 10)
   m4_asm(CSRRS, r20, r0, 11)
   m4_asm(FADDS, r9, r1, r2, 000)
   m4_asm(FSUBS, r10, r1, r2, 000)
   m4_asm(FMULS, r11, r1, r2, 000)
   m4_asm(FDIVS, r12, r1, r2, 000)
   m4_asm(CSRRS, r20, r0, 10)
   m4_asm(CSRRS, r20, r0, 11)
   m4_asm(FSQRTS, r13, r1, 000)
   m4_asm(CSRRS, r20, r0, 10)
   m4_asm(CSRRS, r20, r0, 11)
   m4_asm(FSGNJS, r14, r1, r2)
   m4_asm(FSGNJNS, r15, r1, r2)
   m4_asm(FSGNJXS, r16, r1, r2)
   m4_asm(FMINS, r17, r1, r2)
   m4_asm(FMAXS, r18, r1, r2)
   m4_asm(FCVTSW, r23, r2, 000)
   m4_asm(CSRRS, r20, r0, 10)
   m4_asm(CSRRS, r20, r0, 11)
   m4_asm(FCVTSWU, r24, r3, 000)
   m4_asm(FMVXW, r5, r11)
   m4_asm(CSRRS, r20, r0, 10)
   m4_asm(CSRRS, r20, r0, 11)
   m4_asm(FEQS, r19, r1, r2)
   m4_asm(FLTS, r20, r2, r1)
   m4_asm(FLES, r21, r1, r2)
   m4_asm(FCLASSS, r22, r1)
   m4_asm(FEQS, r19, r1, r2)
   m4_asm(CSRRS, r20, r0, 10)
   m4_asm(CSRRS, r20, r0, 11)
   m4_asm(FCVTWS, r12, r23, 000)
   m4_asm(FCVTWUS, r13, r24, 000)
   m4_asm(ORI, r0, r0, 0)
   
\TLV riscv_bmi_test_prog()
   // /==========================\
   // | B-extension Test Program |
   // \==========================/
   //
   m4_asm(LUI, r1, 01110001010101100000)
   m4_asm(ADDI, r1, r1, 010001000001)
   m4_asm(ADDI, r2, r2, 010001000010)
   m4_asm(ADDI, r3, r3, 010000000011)
   m4_asm(ANDN, r5, r1, r2)
   m4_asm(ORN, r6, r1, r2)
   m4_asm(XNOR, r7, r1, r2)
   m4_asm(SLO, r8, r1, r2)
   m4_asm(SRO, r20, r1, r2)
   m4_asm(ROL, r20, r1, r2)
   m4_asm(ROR, r9, r1, r2)
   m4_asm(SBCLR, r10, r1, r2)
   m4_asm(SBSET, r11, r1, r2)
   m4_asm(SBINV, r12, r1, r2)
   m4_asm(SBEXT, r20, r1, r2)
   m4_asm(GORC, r20, r1, r2)
   m4_asm(GREV, r13, r1, r2)
   m4_asm(SLOI, r8, r1, 111)
   m4_asm(SROI, r20, r1, 111)
   m4_asm(RORI, r9, r1, 111)
   m4_asm(SBCLRI, r10, r1, 111)
   m4_asm(SBSETI, r11, r1, 111)
   m4_asm(SBINVI, r12, r1, 111)
   m4_asm(SBEXTI, r20, r1, 111)
   m4_asm(GORCI, r20, r1, 111)
   m4_asm(GREVI, r13, r1, 111)
   m4_asm(CLMUL, r14, r1, r2)
   m4_asm(CLMULR, r15, r1, r2)
   m4_asm(CLZ, r19, r1)
   m4_asm(CTZ, r20, r1)
   m4_asm(PCNT, r21, r1)
   m4_asm(CRC32B, r22, r1)
   m4_asm(CRC32H, r23, r1)
   m4_asm(CRC32W, r24, r1)
   m4_asm(CRC32CB, r26, r1)
   m4_asm(CRC32CH, r27, r1)
   m4_asm(CRC32CW, r28, r1)
   m4_asm(MIN, r9, r1, r2)
   m4_asm(MAX, r10, r1, r2)
   m4_asm(MINU, r11, r1, r2)
   m4_asm(MAXU, r12, r1, r2)
   m4_asm(SHFL, r13, r1, r2)
   m4_asm(UNSHFL, r14, r1, r2)
   m4_asm(BDEP, r15, r1, r2)
   m4_asm(BEXT, r16, r1, r2)
   m4_asm(PACK, r17, r1, r2)
   m4_asm(PACKU, r18, r1, r2)
   m4_asm(PACKH, r19, r1, r2)
   m4_asm(BFP, r20, r1, r2)
   m4_asm(SHFLI, r21, r1, 11111)
   m4_asm(UNSHFLI, r22, r1, 11111)
   m4_asm(ORI, r0, r0, 0)
   
\TLV riscv_imem(_prog_name)
   m4+indirect(['riscv_']_prog_name['_prog'])
   m4+instrs_for_viz()
   
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
   m4_ifelse_block(M4_EXT_F, 1, ['
   // If the value of $raw_rm (or rm field in instruction encoding) is 3'b111(dynamic RoundingMode) or if $fpu_second_issue_div_sqrt
   // occurs then, take the previous "rm"(RoundingMode) stored in "frm" CSR or else take that from instruction encoding itself.
   // NOTE. In first issue of fpu_div_sqrt itself the vaild $raw_rm value get stored/latched in "frm" CSR,
   //       so to use that at time of second issue of fpu_div_sqrt. 
   $fpufcsr[7:0] = {(((|fetch/instr>>1$raw_rm[2:0] == 3'b111) || $fpu_second_issue_div_sqrt) ? >>1$csr_fcsr[7:5] : |fetch/instr$raw_rm[2:0] ) ,|fetch/instr/fpu1$exception_invaild_output, |fetch/instr/fpu1$exception_infinite_output, |fetch/instr/fpu1$exception_overflow_output, |fetch/instr/fpu1$exception_underflow_output, |fetch/instr/fpu1$exception_inexact_output};
   '])
   
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
   m4_ifelse_block(M4_EXT_F, 1, ['
   $csr_fflags_hw_wr = (($commit && ($fpu_csr_fflags_type_instr || $fpu_fflags_type_instr))  || $fpu_second_issue_div_sqrt);
   $csr_fflags_hw_wr_mask[4:0] = {5{1'b1}};
   $csr_fflags_hw_wr_value[4:0] = {(($fpufcsr[7:5] == 3'b111) ? >>1$csr_fflags[4:0] : $fpufcsr[4:0])};
   
   $csr_frm_hw_wr = ($commit && $fpu_csr_fflags_type_instr);
   $csr_frm_hw_wr_mask[2:0] = {3{1'b1}};
   $csr_frm_hw_wr_value[2:0] = {(($fpufcsr[7:5] == 3'b111) ? >>1$csr_frm[2:0] : $fpufcsr[7:5])};
   
   $csr_fcsr_hw_wr = (($commit && ($fpu_csr_fflags_type_instr || $fpu_fflags_type_instr))  || $fpu_second_issue_div_sqrt);
   $csr_fcsr_hw_wr_mask[7:0] = {8{1'b1}};
   $csr_fcsr_hw_wr_value[7:0] = {($fpu_fflags_type_instr) ? {>>1$csr_fcsr[7:5], $fpufcsr[4:0]} : (($fpufcsr[7:5] == 3'b111) ? >>1$csr_fcsr : $fpufcsr)};
   '])
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
   // in case of second issue, the results are pulled out of the /orig_inst or /load_inst scope. 
   // no alignment is needed as the rslt mux and the long latency results both appear in the same pipestage.

   // in the case of second isssue for multiplication with ALTOPS enabled (or running formal checks for M extension), 
   // the module gives out the result in two cycles but we explicitly flop the $mul_rslt 
   // (by alignment with 3+NON_PIPELINED_BUBBLES to augment the 5 cycle behavior of the mul operation

   $rslt[M4_WORD_RANGE] =
         $second_issue_ld ? /orig_load_inst$ld_rslt : m4_ifelse_block(M4_EXT_M, 1, ['
         ($second_issue_div_mul && |fetch/instr>>M4_NON_PIPELINED_BUBBLES$stall_cnt_upper_div) ? |fetch/instr$divblock_rslt : 
         ($second_issue_div_mul && |fetch/instr>>M4_NON_PIPELINED_BUBBLES$stall_cnt_upper_mul) ? |fetch/instr['']m4_ifelse(M4_RISCV_FORMAL_ALTOPS,1,>>m4_eval(3+M4_NON_PIPELINED_BUBBLES))$mulblock_rslt :
         ']) m4_ifelse_block(M4_EXT_F, 1, ['
         ($fpu_second_issue_div_sqrt && |fetch/instr>>M4_NON_PIPELINED_BUBBLES$stall_cnt_max_fpu) ? |fetch/instr/fpu1$output_div_sqrt11 : 
         ']) m4_ifelse_block(M4_EXT_B, 1, ['
         ($second_issue_clmul_crc && |fetch/instr>>M4_NON_PIPELINED_BUBBLES$stall_cnt_max_clmul) ? |fetch/instr$clmul_output : 
         ($second_issue_clmul_crc && |fetch/instr>>M4_NON_PIPELINED_BUBBLES$stall_cnt_max_crc) ? |fetch/instr$rvb_crc_output : 
         '])
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
      $divtype_instr = ($is_div_instr || $is_divu_instr || $is_rem_instr || $is_remu_instr);
      $multype_instr = ($is_mul_instr || $is_mulh_instr || $is_mulhsu_instr || $is_mulhu_instr);
      $div_mul       = ($multype_instr || $divtype_instr);
      '], ['
      $div_mul = 1'b0;
      $multype_instr = 1'b0;
      `BOGUS_USE($multype_instr)
      '])

      m4_ifelse_block(M4_EXT_F, 1, ['
      // Instruction requires floating point unit and is long-latency.
      // TODO. Current implementation decodes the floating type instructions seperatly.
      // Hence can have a macro or signal to differentiate the type of instruction related to a particular extension or 
      // could be better to use just $op5 decode for this.
      
      // These instructions modifies FP CSR's "frm" and generates "fflags".
      $fpu_csr_fflags_type_instr = $is_fmadds_instr ||
                                   $is_fmsubs_instr ||
                                   $is_fnmsubs_instr ||
                                   $is_fnmadds_instr ||
                                   $is_fadds_instr ||
                                   $is_fsubs_instr ||
                                   $is_fmuls_instr ||
                                   $is_fdivs_instr ||
                                   $is_fsqrts_instr ||
                                   $is_fcvtws_instr ||
                                   $is_fcvtwus_instr ||
                                   $is_fcvtsw_instr ||
                                   $is_fcvtswu_instr;
      // These instructions do not modify FP CSR's "frm", but they do generate "fflags".
      $fpu_fflags_type_instr = $is_fmins_instr ||
                               $is_fmaxs_instr ||
                               $is_feqs_instr ||
                               $is_flts_instr ||
                               $is_fles_instr;
      // Generalized FP instrucions.                               
      $fpu_type_instr = $fpu_csr_fflags_type_instr ||
                        $fpu_fflags_type_instr ||
                        $is_flw_instr ||
                        $is_fsw_instr ||
                        $is_fsgnjs_instr ||
                        $is_fsgnjns_instr ||
                        $is_fsgnjxs_instr ||
                        $is_fmvxw_instr ||
                        $is_fclasss_instr ||
                        $is_fmvwx_instr;
      $fpu_div_sqrt_type_instr = $is_fdivs_instr || $is_fsqrts_instr;
      $fmvxw_type_instr = $is_fmvxw_instr;
      $fcvtw_s_type_instr = $is_fcvtws_instr || $is_fcvtwus_instr;
      '])
      
      m4_ifelse_block(M4_EXT_B, 1, ['
      // These are long-latency Instruction requires B-extension enabled.
      $clmul_type_instr = $is_clmul_instr ||
                          $is_clmulr_instr ||
                          $is_clmulh_instr ;
      $crc_type_instr =  $is_crc32b_instr ||
                          $is_crc32w_instr ||
                          $is_crc32h_instr ||
                          $is_crc32cb_instr ||
                          $is_crc32cw_instr ||
                          $is_crc32ch_instr;
      $clmul_crc_type_instr = $clmul_type_instr || $crc_type_instr;
      '])

      $is_srli_srai_instr = $is_srli_instr || $is_srai_instr;
      // Some I-type instructions have a funct7 field rather than immediate bits, so these must factor into the illegal instruction expression explicitly.
      $illegal_itype_with_funct7 = ( $is_srli_srai_instr m4_ifelse(M4_WORD_CNT, 64, ['|| $is_srliw_sraiw_instr']) ) && | {$raw_funct7[6], $raw_funct7[4:0]};
      $illegal = ($illegal_itype_with_funct7['']m4_illegal_instr_expr) ||
                 ($raw[1:0] != 2'b11); // All legal instructions have opcode[1:0] == 2'b11. We ignore these bits in decode logic.
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
   $dest_reg[M4_REGS_INDEX_RANGE] = m4_ifelse(M4_EXT_M, 1, ['$second_issue_div_mul ? |fetch/instr/hold_inst>>M4_NON_PIPELINED_BUBBLES$dest_reg :'])
                                    m4_ifelse(M4_EXT_B, 1, ['$second_issue_clmul_crc ? |fetch/instr/hold_inst>>M4_NON_PIPELINED_BUBBLES$dest_reg :'])
                                    $second_issue_ld ? |fetch/instr/orig_inst$dest_reg : $raw_rd;
   $dest_reg_valid = m4_ifelse(M4_EXT_F, 1, ['((! $fpu_type_instr) ||  $fmvxw_type_instr || $fcvtw_s_type_instr) &&']) (($valid_decode && ! $is_s_type && ! $is_b_type) || $second_issue) &&
                     | $dest_reg;   // r0 not valid.
   
   m4_ifelse_block(M4_EXT_F, 1, ['
   // Implementing a different encoding for floating point instructions.
   ?$valid_decode
      // Output signals. seperate FPU source
      /fpusrc[3:1]
         // Reg valid for this fpu source, based on instruction type.
         $is_fpu_reg = ( (#fpusrc != 3) && /instr$is_r_type) || /instr$is_r4_type || ( (#fpusrc != 3) && /instr$is_r2_type) || (/instr$is_i_type && (#fpusrc == 1) && (#fpusrc != 3)) || ( (#fpusrc != 3) && /instr$is_s_type);
         $fpu_reg[M4_FPUREGS_INDEX_RANGE] = (#fpusrc == 1) ? /instr$raw_rs1 : (#fpusrc == 2) ? /instr$raw_rs2 : /instr$raw_rs3;
         
   $dest_fpu_reg[M4_FPUREGS_INDEX_RANGE] = $fpu_second_issue_div_sqrt ? |fetch/instr/hold_inst>>M4_NON_PIPELINED_BUBBLES$dest_fpu_reg :
                                    $second_issue_ld ? |fetch/instr/orig_inst$dest_fpu_reg : $raw_rd;
   $dest_fpu_reg_valid = ($fpu_type_instr && (! $fmvxw_type_instr) && (! $fcvtw_s_type_instr) ) && (($valid_decode && ! $is_s_type && ! $is_b_type) || $second_issue);
   '])
   
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
   // if M_EXT is enabled, this handles the stalling logic
   m4_ifelse_block(M4_EXT_M, 1, ['
   m4+m_extension()
   '])

   // if F_EXT is enabled, this handles the stalling logic
   m4_ifelse_block(M4_EXT_F, 1, ['
   m4+f_extension()
   '])

   // if B_EXT is enabled, this handles the stalling logic
   m4_ifelse_block(M4_EXT_B, 1, ['
   m4+b_extension()
   '])
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
      m4_ifelse_block(M4_EXT_M, 1, ['
      // Verilog instantiation must happen outside when conditions' scope
      $divblk_valid = $divtype_instr && $commit;
      $mulblk_valid = $multype_instr && $commit;
      /* verilator lint_off WIDTH */
      /* verilator lint_off CASEINCOMPLETE */   
      m4+warpv_mul(|fetch/instr,/mul1, $mulblock_rslt, $wrm, $waitm, $readym, $clk, $resetn, $mul_in1, $mul_in2, $instr_type_mul, $mulblk_valid)
      m4+warpv_div(|fetch/instr,/div1, $divblock_rslt, $wrd, $waitd, $readyd, $clk, $resetn, $div_in1, $div_in2, $instr_type_div, >>1$div_stall)
      // for the division module, the valid signal must be asserted for the entire computation duration, hence >>1$div_stall is used for this purpose
      // for multiplication it is just a single cycle pulse to start operating

      /* verilator lint_on CASEINCOMPLETE */
      /* verilator lint_on WIDTH */
      // use $ANY for passing attributes from long-latency div/mul instructions into the pipeline 
      // stall_cnt_upper_div indicates that the results for div module are ready. The second issue of the instruction takes place
      // M4_NON_PIPELINED_BUBBLES after this point (depending on pipeline depth)
      // retain till next M-type instruction, to be used again at second issue
      '])
 
      m4_ifelse_block(M4_EXT_F, 1, ['
      // "F" Extension.

      // TODO. Current implementation of FPU is not optimized in terms of encode-decode of instruction inside macro, hence its latency and generated logic increases.
      // Need to call fpu_exe macro inside this ifelse_block itself and simplify it to optimize the unit.
      /* verilator lint_off WIDTH */
      /* verilator lint_off CASEINCOMPLETE */
      
      $fpu_div_sqrt_valid = >>1$fpu_div_sqrt_stall;
      $input_valid = $fpu_div_sqrt_type_instr && |fetch/instr$fpu_div_sqrt_stall && |fetch/instr$commit;
      `BOGUS_USE($fpu_div_sqrt_valid)
      // Main FPU execution
      m4+fpu_exe(/fpu1,|fetch/instr, 8, 24, 32, $operand_a, $operand_b, $operand_c, $int_input, $int_output, $fpu_operation, $rounding_mode, $nreset, $clock, $input_valid, $outvalid, $lt_compare, $eq_compare, $gt_compare, $unordered, $output_result, $output_div_sqrt11, $output_class, $exception_invaild_output, $exception_infinite_output, $exception_overflow_output, $exception_underflow_output, $exception_inexact_output)
      
      // Sign-injection macros
      m4+sgn_mv_injn(8, 24, $operand_a, $operand_b, $fsgnjs_output)
      m4+sgn_neg_injn(8, 24, $operand_a, $operand_b, $fsgnjns_output)
      m4+sgn_abs_injn(8, 24, $operand_a, $operand_b, $fsgnjxs_output)
      /* verilator lint_on WIDTH */
      /* verilator lint_on CASEINCOMPLETE */
      '])
      
      
      m4_ifelse_block(M4_EXT_B, 1, ['
      // "B" Extension.
      // TODO. Current implementation of BMI is not optimized in terms of encode-decode of instruction inside macro, hence its latency and generated logic increases.

      // Main BMI Macro's

      $din_valid_bext_dep = ($is_gorc_instr || $is_gorci_instr || $is_shfl_instr || $is_unshfl_instr || $is_bdep_instr || $is_bext_instr || $is_shfli_instr || $is_unshfli_instr) && |fetch/instr$commit;
      $din_valid_clmul = ($is_clmul_instr || $is_clmulr_instr || $is_clmulh_instr) && |fetch/instr$commit;
      $din_valid_rvb_crc = ($is_crc32b_instr || $is_crc32h_instr || $is_crc32w_instr || $is_crc32cb_instr || $is_crc32ch_instr || $is_crc32cw_instr) && |fetch/instr$commit;
      $din_valid_rvb_bitcnt = ($is_pcnt_instr || $is_sextb_instr || $is_sexth_instr) && |fetch/instr$commit;
      
      /* verilator lint_off WIDTH */
      /* verilator lint_off CASEINCOMPLETE */
      /* verilator lint_off PINMISSING */
      /* verilator lint_off CASEOVERLAP */
      m4+clz_final(|fetch/instr, /clz_stage, 32, 0, 1, $input_a, $clz_final_output)
      m4+ctz_final(|fetch/instr, /ctz_stage, /reverse, 32, 0, 1, $input_a, $ctz_final_output)
      m4+popcnt(|fetch/instr, /pop_stage, $input_a, $popcnt_output, 32)
      m4+andn($input_a, $input_b, $andn_output[31:0])
      m4+orn($input_a, $input_b, $orn_output[31:0])
      m4+xnor($input_a, $input_b, $xnor_output[31:0])
      m4+pack($input_a, $input_b, $pack_output, 32)
      m4+packu($input_a, $input_b, $packu_output, 32)
      m4+packh($input_a, $input_b, $packh_output, 32)
      m4+minu($input_a, $input_b, $minu_output, 32)
      m4+maxu($input_a, $input_b, $maxu_output, 32)
      m4+min($input_a, $input_b, $min_output, 32)
      m4+max($input_a, $input_b, $max_output, 32)
      m4+sbset($input_a, $input_b, $sbset_output, 32)
      m4+sbclr($input_a, $input_b, $sbclr_output, 32)
      m4+sbinv($input_a, $input_b, $sbinv_output, 32)
      m4+sbext($input_a, $input_b, $sbext_output, 32)
      m4+sbseti($input_a, $input_b, $sbseti_output, 32)
      m4+sbclri($input_a, $input_b, $sbclri_output, 32)
      m4+sbinvi($input_a, $input_b, $sbinvi_output, 32)
      m4+sbexti($input_a, $input_b, $sbexti_output, 32)
      m4+slo($input_a, $input_b, $slo_output, 32)
      m4+sro($input_a, $input_b, $sro_output, 32)
      m4+sloi($input_a, $input_b, $sloi_output, 32)
      m4+sroi($input_a, $input_b, $sroi_output, 32)
      m4+rorl_final(32, 1, $input_a, $sftamt, $rorl_final_output, 31, 0)
      m4+rorr_final(32, 1, $input_a, $sftamt, $rorr_final_output, 31, 0)
      m4+brev_final(|fetch/instr, /brev_stage, 32, 32, 0, 1, $input_a, $sftamt, $grev_final_output)
      m4+bext_dep(1, |fetch/instr, 32, 1, 1, 0, $bmi_clk, $bmi_reset, $din_valid_bext_dep, $din_ready_bext_dep, $input_a, $input_b, $raw[3], $raw[13], $raw[14], $raw[29], $raw[30], $dout_valid_bext_dep, $dout_ready_bext_dep, $bext_dep_output[31:0])
      m4+bfp($input_a, $input_b, $bfp_output, 32)
      m4+clmul(1, |fetch/instr, 32, $bmi_clk, $bmi_reset, $din_valid_clmul, $din_ready_clmul, $input_a, $input_b, $raw[3], $raw[12], $raw[13], $dout_valid_clmul, $dout_ready_clmul, $clmul_output[31:0])
      m4+rvb_crc(1, |fetch/instr, 32, $bmi_clk, $bmi_reset, $din_valid_rvb_crc, $din_ready_rvb_crc, $input_a, $raw[20], $raw[21], $raw[23], $dout_valid_rvb_crc, $dout_ready_rvb_crc, $rvb_crc_output[31:0])
      m4+rvb_bitcnt(1, |fetch/instr, 32, 0, $bmi_clk, $bmi_reset, $din_valid_rvb_bitcnt, $din_ready_rvb_bitcnt, $input_a, $raw[3], $raw[20], $raw[21], $raw[22], $dout_valid_rvb_bitcnt, $dout_ready_rvb_bitcnt, $rvb_bitcnt_output[31:0])
      /* verilator lint_on WIDTH */
      /* verilator lint_on CASEINCOMPLETE */
      /* verilator lint_on PINMISSING */
      /* verilator lint_on CASEOVERLAP */

      `BOGUS_USE($din_ready_rvb_bitcnt $din_ready_bext_dep $din_ready_rvb_crc $din_ready_clmul)
      '])

      // hold_inst scope is not needed when long latency instructions are disabled
      m4_ifelse(m4_eval(M4_EXT_M || M4_EXT_F || M4_EXT_B), 1, ['
      // ORed with 1'b0 for maintaining correct behavior for all 3 combinations of F & M, only F and only M 
      /hold_inst
         $ANY = 1'b0 m4_ifelse(M4_EXT_M, 1, [' || (|fetch/instr$mulblk_valid || (|fetch/instr$div_stall && |fetch/instr$commit))']) m4_ifelse(M4_EXT_F, 1, [' || (|fetch/instr$fpu_div_sqrt_stall && |fetch/instr$commit)']) m4_ifelse(M4_EXT_B, 1, [' || ((|fetch/instr$clmul_stall || |fetch/instr$crc_stall) && |fetch/instr$commit)']) ? |fetch/instr$ANY : >>1$ANY;
         /src[2:1]
            $ANY = 1'b0 m4_ifelse(M4_EXT_M, 1, [' || (|fetch/instr$mulblk_valid || (|fetch/instr$div_stall && |fetch/instr$commit))']) m4_ifelse(M4_EXT_F, 1, [' || (|fetch/instr$fpu_div_sqrt_stall && |fetch/instr$commit)']) m4_ifelse(M4_EXT_B, 1, [' || ((|fetch/instr$clmul_stall || |fetch/instr$crc_stall) && |fetch/instr$commit)']) ? |fetch/instr/src$ANY : >>1$ANY;
      '])
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
         
         $lui_rslt[M4_WORD_RANGE]   = {$raw_u_imm[31:12], 12'b0};
         $auipc_rslt[M4_WORD_RANGE] = M4_FULL_PC + $raw_u_imm;
         $jal_rslt[M4_WORD_RANGE]   = M4_FULL_PC + 4;
         $jalr_rslt[M4_WORD_RANGE]  = M4_FULL_PC + 4;
         // Load instructions. If returning ld is enabled, load instructions write no meaningful result, so we use zeros.
         m4_ifelse_block(M4_INJECT_RETURNING_LD, 1, ['
         $lb_rslt[M4_WORD_RANGE]    = M4_WORD_CNT'b0;
         $lh_rslt[M4_WORD_RANGE]    = M4_WORD_CNT'b0;
         $lw_rslt[M4_WORD_RANGE]    = M4_WORD_CNT'b0;
         $lbu_rslt[M4_WORD_RANGE]   = M4_WORD_CNT'b0;
         $lhu_rslt[M4_WORD_RANGE]   = M4_WORD_CNT'b0;
         m4_ifelse_block(M4_EXT_F, 1, ['
         $flw_rslt[M4_WORD_RANGE] = 32'b0;
         '])
         '], ['
         $lb_rslt[M4_WORD_RANGE]    = /orig_inst$ld_rslt;
         $lh_rslt[M4_WORD_RANGE]    = /orig_inst$ld_rslt;
         $lw_rslt[M4_WORD_RANGE]    = /orig_inst$ld_rslt;
         $lbu_rslt[M4_WORD_RANGE]   = /orig_inst$ld_rslt;
         $lhu_rslt[M4_WORD_RANGE]   = /orig_inst$ld_rslt;
         m4_ifelse_block(M4_EXT_F, 1, ['
         $flw_rslt[M4_WORD_RANGE]   = /orig_inst$ld_rslt;
         '])
         '])
         $addi_rslt[M4_WORD_RANGE]  = /src[1]$reg_value + $raw_i_imm;  // TODO: This has its own adder; could share w/ add/sub.
         $xori_rslt[M4_WORD_RANGE]  = /src[1]$reg_value ^ $raw_i_imm;
         $ori_rslt[M4_WORD_RANGE]   = /src[1]$reg_value | $raw_i_imm;
         $andi_rslt[M4_WORD_RANGE]  = /src[1]$reg_value & $raw_i_imm;
         $slli_rslt[M4_WORD_RANGE]  = /src[1]$reg_value << $raw_i_imm[5:0];
         $srli_intermediate_rslt[M4_WORD_RANGE] = /src[1]$reg_value >> $raw_i_imm[5:0];
         $srai_intermediate_rslt[M4_WORD_RANGE] = /src[1]$reg_value[M4_WORD_MAX] ? $srli_intermediate_rslt | ((M4_WORD_HIGH'b0 - 1) << (M4_WORD_HIGH - $raw_i_imm[5:0]) ): $srli_intermediate_rslt;
         $srl_rslt[M4_WORD_RANGE]   = /src[1]$reg_value >> /src[2]$reg_value[4:0];
         $sra_rslt[M4_WORD_RANGE]   = /src[1]$reg_value[M4_WORD_MAX] ? $srl_rslt | ((M4_WORD_HIGH'b0 - 1) << (M4_WORD_HIGH - /src[2]$reg_value[4:0]) ): $srl_rslt;
         $slti_rslt[M4_WORD_RANGE]  =  (/src[1]$reg_value[M4_WORD_MAX] == $raw_i_imm[M4_WORD_MAX]) ? $sltiu_rslt : {M4_WORD_MAX'b0,/src[1]$reg_value[M4_WORD_MAX]};
         $sltiu_rslt[M4_WORD_RANGE] = (/src[1]$reg_value < $raw_i_imm) ? 1 : 0;
         $srai_rslt[M4_WORD_RANGE]  = $srai_intermediate_rslt;
         $srli_rslt[M4_WORD_RANGE]  = $srli_intermediate_rslt;
         $add_sub_rslt[M4_WORD_RANGE] = ($raw_funct7[5] == 1) ?  /src[1]$reg_value - /src[2]$reg_value : /src[1]$reg_value + /src[2]$reg_value;
         $add_rslt[M4_WORD_RANGE]   = $add_sub_rslt;
         $sub_rslt[M4_WORD_RANGE]   = $add_sub_rslt;
         $sll_rslt[M4_WORD_RANGE]   = /src[1]$reg_value << /src[2]$reg_value[4:0];
         $slt_rslt[M4_WORD_RANGE]   = (/src[1]$reg_value[M4_WORD_MAX] == /src[2]$reg_value[M4_WORD_MAX]) ? $sltu_rslt : {M4_WORD_MAX'b0,/src[1]$reg_value[M4_WORD_MAX]};
         $sltu_rslt[M4_WORD_RANGE]  = (/src[1]$reg_value < /src[2]$reg_value) ? 1 : 0;
         $xor_rslt[M4_WORD_RANGE]   = /src[1]$reg_value ^ /src[2]$reg_value;
         $or_rslt[M4_WORD_RANGE]    = /src[1]$reg_value | /src[2]$reg_value;
         $and_rslt[M4_WORD_RANGE]   = /src[1]$reg_value & /src[2]$reg_value;
         // CSR read instructions have the same result expression. Counting on synthesis to optimize result mux.
         $csrrw_rslt[M4_WORD_RANGE]  = m4_csrrx_rslt_expr;
         $csrrs_rslt[M4_WORD_RANGE]  = $csrrw_rslt;
         $csrrc_rslt[M4_WORD_RANGE]  = $csrrw_rslt;
         $csrrwi_rslt[M4_WORD_RANGE] = $csrrw_rslt;
         $csrrsi_rslt[M4_WORD_RANGE] = $csrrw_rslt;
         $csrrci_rslt[M4_WORD_RANGE] = $csrrw_rslt;
         
         // "M" Extension.
         
         m4_ifelse_block(M4_EXT_M, 1, ['
         // for Verilog modules instantiation
         $clk = *clk;
         $resetn = !(*reset);

         $instr_type_mul[3:0]    = $reset ? '0 : $mulblk_valid ? {$is_mulhu_instr,$is_mulhsu_instr,$is_mulh_instr,$is_mul_instr} : $RETAIN;
         $mul_in1[M4_WORD_RANGE] = $reset ? '0 : $mulblk_valid ? /src[1]$reg_value : $RETAIN;
         $mul_in2[M4_WORD_RANGE] = $reset ? '0 : $mulblk_valid ? /src[2]$reg_value : $RETAIN;
         
         $instr_type_div[3:0]    = $reset ? '0 : $divblk_valid ? {$is_remu_instr,$is_rem_instr,$is_divu_instr,$is_div_instr} : $RETAIN;
         $div_in1[M4_WORD_RANGE] = $reset ? '0 : $divblk_valid ? /src[1]$reg_value : $RETAIN;
         $div_in2[M4_WORD_RANGE] = $reset ? '0 : $divblk_valid ? /src[2]$reg_value : $RETAIN;
         
         // result signals for div/mul can be pulled down to 0 here, as they are assigned only in the second issue

         $mul_rslt[M4_WORD_RANGE]      = M4_WORD_CNT'b0;
         $mulh_rslt[M4_WORD_RANGE]     = M4_WORD_CNT'b0;
         $mulhsu_rslt[M4_WORD_RANGE]   = M4_WORD_CNT'b0;
         $mulhu_rslt[M4_WORD_RANGE]    = M4_WORD_CNT'b0;
         $div_rslt[M4_WORD_RANGE]      = M4_WORD_CNT'b0;
         $divu_rslt[M4_WORD_RANGE]     = M4_WORD_CNT'b0;
         $rem_rslt[M4_WORD_RANGE]      = M4_WORD_CNT'b0;
         $remu_rslt[M4_WORD_RANGE]     = M4_WORD_CNT'b0;
         `BOGUS_USE ($wrm $wrd $readyd $readym $waitm $waitd)
         '])
      
         // "F" Extension.
         
         m4_ifelse_block(M4_EXT_F, 1, ['
         // Determining the type of fpu_operation according to the fpu_exe macro
         $fpu_operation[4:0] = ({5{$is_fmadds_instr }}  & 5'h2 ) |
                               ({5{$is_fmsubs_instr }}  & 5'h3 ) |
                               ({5{$is_fnmsubs_instr}}  & 5'h4 ) |
                               ({5{$is_fnmadds_instr}}  & 5'h5 ) |
                               ({5{$is_fadds_instr  }}  & 5'h6 ) |
                               ({5{$is_fsubs_instr  }}  & 5'h7 ) |
                               ({5{$is_fmuls_instr  }}  & 5'h8 ) |
                               ({5{$is_fdivs_instr  }}  & 5'h9 ) |
                               ({5{$is_fsqrts_instr }}  & 5'ha ) |
                               ({5{$is_fsgnjs_instr }}  & 5'hb ) |
                               ({5{$is_fsgnjns_instr}}  & 5'hc ) |
                               ({5{$is_fsgnjxs_instr}}  & 5'hd ) |
                               ({5{$is_fmins_instr  }}  & 5'he ) |
                               ({5{$is_fmaxs_instr  }}  & 5'hf ) |
                               ({5{$is_fcvtws_instr }}  & 5'h10) |
                               ({5{$is_fcvtwus_instr}}  & 5'h11) |
                               ({5{$is_fmvxw_instr  }}  & 5'h12) |
                               ({5{$is_feqs_instr   }}  & 5'h13) |
                               ({5{$is_flts_instr   }}  & 5'h14) |
                               ({5{$is_fles_instr   }}  & 5'h15) |
                               ({5{$is_fclasss_instr}}  & 5'h16) |
                               ({5{$is_fcvtsw_instr }}  & 5'h17) |
                               ({5{$is_fcvtswu_instr}}  & 5'h18) |
                               ({5{$is_fmvwx_instr  }}  & 5'h19);
         // Needed for division-sqrt module  
         $nreset = ! *reset;
         $clock = *clk;

         // Operands
         $operand_a[31:0] = /fpusrc[1]$fpu_reg_value;
         $operand_b[31:0] = /fpusrc[2]$fpu_reg_value;
         $operand_c[31:0] = /fpusrc[3]$fpu_reg_value;
         // rounding mode as per the RISC-V specs (synchronizing with HardFloat module)
         $rounding_mode[2:0] = (|fetch/instr$raw_rm == 3'b000) ? 3'b000 :
                               (|fetch/instr$raw_rm == 3'b001) ? 3'b010 :
                               (|fetch/instr$raw_rm == 3'b010) ? 3'b011 :
                               (|fetch/instr$raw_rm == 3'b011) ? 3'b100 :
                               (|fetch/instr$raw_rm == 3'b100) ? 3'b001 :
                               (|fetch/instr$raw_rm == 3'b111) ? $csr_fcsr[7:5] : 3'bxxx;
         $int_input[31:0] = /src[1]$reg_value;

         // Results
         $fmadds_rslt[M4_WORD_RANGE]  = /fpu1$output_result;
         $fmsubs_rslt[M4_WORD_RANGE]  = /fpu1$output_result;
         $fnmadds_rslt[M4_WORD_RANGE] = /fpu1$output_result;
         $fnmsubs_rslt[M4_WORD_RANGE] = /fpu1$output_result;
         $fadds_rslt[M4_WORD_RANGE]   = /fpu1$output_result;
         $fsubs_rslt[M4_WORD_RANGE]   = /fpu1$output_result;
         $fmuls_rslt[M4_WORD_RANGE]   = /fpu1$output_result;
         $fsgnjs_rslt[M4_WORD_RANGE]  = $fsgnjs_output;
         $fsgnjns_rslt[M4_WORD_RANGE] = $fsgnjns_output;
         $fsgnjxs_rslt[M4_WORD_RANGE] = $fsgnjxs_output;
         $fmins_rslt[M4_WORD_RANGE]   = /fpu1$output_result;
         $fmaxs_rslt[M4_WORD_RANGE]   = /fpu1$output_result;
         $fcvtws_rslt[M4_WORD_RANGE]  = /fpu1$int_output;
         $fcvtwus_rslt[M4_WORD_RANGE] = /fpu1$int_output;
         $fmvxw_rslt[M4_WORD_RANGE]   = /fpusrc[1]$fpu_reg_value;
         $feqs_rslt[M4_WORD_RANGE]    = {31'b0 , /fpu1$eq_compare};
         $flts_rslt[M4_WORD_RANGE]    = {31'b0 , /fpu1$lt_compare}; 
         $fles_rslt[M4_WORD_RANGE]    = {31'b0 , {/fpu1$eq_compare & /fpu1$lt_compare}};
         $fclasss_rslt[M4_WORD_RANGE] = {28'b0, /fpu1$output_class};
         $fcvtsw_rslt[M4_WORD_RANGE]  = /fpu1$output_result;
         $fcvtswu_rslt[M4_WORD_RANGE] = /fpu1$output_result;
         $fmvwx_rslt[M4_WORD_RANGE]   = /src[1]$reg_value;
         
         // Pulling Instructions from /orig_inst scope
         $fdivs_rslt[M4_WORD_RANGE]   = M4_WORD_CNT'b0;
         $fsqrts_rslt[M4_WORD_RANGE]  = M4_WORD_CNT'b0;
         `BOGUS_USE(/fpu1$in_ready /fpu1$sqrtresult /fpu1$unordered /fpu1$exception_invaild_output /fpu1$exception_infinite_output /fpu1$exception_overflow_output /fpu1$exception_underflow_output /fpu1$exception_inexact_output)
         '])
         
         m4_ifelse_block(M4_EXT_B, 1, ['
         // Currently few of the instructions are custom build in TL-Verilog and will work fine on inputs in power of 2.
         $is_src_type_instr =     $is_andn_instr       ||
                                  $is_orn_instr        ||
                                  $is_xnor_instr       ||
                                  $is_slo_instr        ||
                                  $is_sro_instr        ||
                                  $is_rol_instr        ||
                                  $is_ror_instr        ||
                                  $is_sbclr_instr      ||
                                  $is_sbset_instr      ||
                                  $is_sbinv_instr      ||
                                  $is_sbext_instr      ||
                                  $is_gorc_instr       ||
                                  $is_grev_instr       ||
                                  $is_clz_instr        ||
                                  $is_ctz_instr        ||
                                  $is_pcnt_instr       ||
                                  $is_sextb_instr      ||
                                  $is_sexth_instr      ||
                                  $is_crc32b_instr     ||
                                  $is_crc32h_instr     ||
                                  $is_crc32w_instr     ||
                                  $is_crc32cb_instr    ||
                                  $is_crc32ch_instr    ||
                                  $is_crc32cw_instr    ||
                                  $is_clmul_instr      ||
                                  $is_clmulr_instr     ||
                                  $is_clmulh_instr     ||
                                  $is_min_instr        ||
                                  $is_max_instr        ||
                                  $is_minu_instr       ||
                                  $is_maxu_instr       ||
                                  $is_shfl_instr       ||
                                  $is_unshfl_instr     ||
                                  $is_bdep_instr       ||
                                  $is_bext_instr       ||
                                  $is_pack_instr       ||
                                  $is_packu_instr      ||
                                  $is_packh_instr      ||
                                  $is_bfp_instr;
         
         $is_imm_type_instr =     $is_sloi_instr       ||
                                  $is_sroi_instr       ||
                                  $is_sbclri_instr     ||
                                  $is_sbseti_instr     ||
                                  $is_sbinvi_instr     ||
                                  $is_sbexti_instr     ||
                                  $is_gorci_instr      ||
                                  $is_grevi_instr      ||
                                  $is_shfli_instr      ||
                                  $is_unshfli_instr;
         
         $bmi_reset = *reset;
         $bmi_clk = *clk;
         
         // Operands
         $input_a[31:0] = /src[1]$reg_value;
         $input_b[31:0] = $is_src_type_instr ? /src[2]$reg_value : $raw_i_imm;
         $sftamt[4:0] = $input_b[4:0];
         `BOGUS_USE($is_imm_type_instr $sftamt)

         // Results
         $andn_rslt[M4_WORD_RANGE]   = $andn_output;
         $orn_rslt[M4_WORD_RANGE]    = $orn_output;
         $xnor_rslt[M4_WORD_RANGE]   = $xnor_output;
         $slo_rslt[M4_WORD_RANGE]    = $slo_output;
         $sro_rslt[M4_WORD_RANGE]    = $sro_output;
         $rol_rslt[M4_WORD_RANGE]    = $rorl_final_output;
         $ror_rslt[M4_WORD_RANGE]    = $rorr_final_output;
         $sbclr_rslt[M4_WORD_RANGE]  = $sbclr_output;
         $sbset_rslt[M4_WORD_RANGE]  = $sbset_output;
         $sbinv_rslt[M4_WORD_RANGE]  = $sbinv_output;
         $sbext_rslt[M4_WORD_RANGE]  = $sbext_output;
         $gorc_rslt[M4_WORD_RANGE]   = $bext_dep_output;
         $grev_rslt[M4_WORD_RANGE]   = $grev_final_output;
         $sloi_rslt[M4_WORD_RANGE]   = $sloi_output;
         $sroi_rslt[M4_WORD_RANGE]   = $sroi_output;
         $rori_rslt[M4_WORD_RANGE]   = $rorr_final_output;
         $sbclri_rslt[M4_WORD_RANGE] = $sbclri_output;
         $sbseti_rslt[M4_WORD_RANGE] = $sbseti_output;
         $sbinvi_rslt[M4_WORD_RANGE] = $sbinvi_output;
         $sbexti_rslt[M4_WORD_RANGE] = $sbexti_output;
         $gorci_rslt[M4_WORD_RANGE]  = $bext_dep_output;
         $grevi_rslt[M4_WORD_RANGE]  = $grev_final_output;
         $clz_rslt[M4_WORD_RANGE]    = {26'b0, $clz_final_output};
         $ctz_rslt[M4_WORD_RANGE]    = {26'b0, $ctz_final_output};
         $pcnt_rslt[M4_WORD_RANGE]   = {26'b0, $popcnt_output};
         $sextb_rslt[M4_WORD_RANGE]   = $rvb_bitcnt_output;
         $sexth_rslt[M4_WORD_RANGE]   = $rvb_bitcnt_output;
         $min_rslt[M4_WORD_RANGE] = $min_output;
         $max_rslt[M4_WORD_RANGE] = $max_output;
         $minu_rslt[M4_WORD_RANGE] = $minu_output;
         $maxu_rslt[M4_WORD_RANGE] = $maxu_output;
         $shfl_rslt[M4_WORD_RANGE] = $bext_dep_output;
         $unshfl_rslt[M4_WORD_RANGE] = $bext_dep_output;
         $bdep_rslt[M4_WORD_RANGE] = $bext_dep_output;
         $bext_rslt[M4_WORD_RANGE] = $bext_dep_output;
         $pack_rslt[M4_WORD_RANGE] = $pack_output;
         $packu_rslt[M4_WORD_RANGE] = $packu_output;
         $packh_rslt[M4_WORD_RANGE] = $packh_output;
         $bfp_rslt[M4_WORD_RANGE] = $bfp_output;
         $shfli_rslt[M4_WORD_RANGE] = $bext_dep_output;
         $unshfli_rslt[M4_WORD_RANGE] = $bext_dep_output;

         $clmul_rslt[M4_WORD_RANGE]  = M4_WORD_CNT'b0;
         $clmulr_rslt[M4_WORD_RANGE] = M4_WORD_CNT'b0;
         $clmulh_rslt[M4_WORD_RANGE] = M4_WORD_CNT'b0;
         $crc32b_rslt[M4_WORD_RANGE] = M4_WORD_CNT'b0;
         $crc32h_rslt[M4_WORD_RANGE] = M4_WORD_CNT'b0;
         $crc32w_rslt[M4_WORD_RANGE] = M4_WORD_CNT'b0;
         $crc32cb_rslt[M4_WORD_RANGE] = M4_WORD_CNT'b0;
         $crc32ch_rslt[M4_WORD_RANGE] = M4_WORD_CNT'b0;
         $crc32cw_rslt[M4_WORD_RANGE] = M4_WORD_CNT'b0;
         
         $dout_ready_bext_dep = $dout_valid_bext_dep && |fetch/instr$commit;
         $dout_ready_clmul = $dout_valid_clmul && |fetch/instr$commit;
         $dout_ready_rvb_crc = $dout_valid_rvb_crc && |fetch/instr$commit;
         $dout_ready_rvb_bitcnt = $dout_valid_rvb_bitcnt && |fetch/instr$commit;
         '])

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
         $addr[M4_ADDR_RANGE] = m4_ifelse(M4_EXT_F, 1, ['($is_fsw_instr ? /src[1]$reg_value : /src[1]$reg_value)'],['/src[1]$reg_value']) + ($ld ? $raw_i_imm : $raw_s_imm);
         
         // Hardware assumes natural alignment. Otherwise, trap, and handle in s/w (though no s/w provided).
      $st_cond = $st && $valid_exe;
      ?$st_cond
         // Provide a value to store, naturally-aligned to memory, that will work regardless of the lower $addr bits.
         $st_reg_value[M4_WORD_RANGE] = m4_ifelse_block(M4_EXT_F, 1, ['$is_fsw_instr ? /fpusrc[2]$fpu_reg_value :'])
                                                        /src[2]$reg_value;
         $st_value[M4_WORD_RANGE] =
              $ld_st_word ? $st_reg_value :            // word
              $ld_st_half ? {2{$st_reg_value[15:0]}} : // half
                            {4{$st_reg_value[7:0]}};   // byte
         $st_mask[3:0] =
              $ld_st_word ? 4'hf :                     // word
              $ld_st_half ? ($addr[1] ? 4'hc : 4'h3) : // half
                            (4'h1 << $addr[1:0]);      // byte

      // Swizzle bytes for load result (assuming natural alignment) and pass to /orig_load_inst scope
      ?$second_issue_ld
         /orig_load_inst
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
   m4+instrs_for_viz()
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



//==================//
//      RISC-V      //
//  "M" Extension   //
//==================//

\SV
   m4_ifelse_block(M4_EXT_M, 1, ['
      m4_ifelse(M4_ISA, ['RISCV'], [''], ['m4_errprint(['M-ext supported for RISC-V only.']m4_new_line)'])
      m4_ifelse_block(M4_FORMAL, ['1'], ['
         m4_define(M4_RISCV_FORMAL_ALTOPS, 1)         // enable ALTOPS if compiling for formal verification of M extension
      '])
      m4_ifelse_block(M4_RISCV_FORMAL_ALTOPS, 1, ['
			`define RISCV_FORMAL_ALTOPS
		'])
      /* verilator lint_off WIDTH */
      /* verilator lint_off CASEINCOMPLETE */
      // TODO : Update links after merge to master!
      m4_sv_include_url(['https:/']['/raw.githubusercontent.com/stevehoover/warp-v_includes/master/divmul/picorv32_pcpi_div.sv'])
      m4_sv_include_url(['https:/']['/raw.githubusercontent.com/stevehoover/warp-v_includes/master/divmul/picorv32_pcpi_fast_mul.sv'])
      /* verilator lint_on CASEINCOMPLETE */
      /* verilator lint_on WIDTH */
         
   '])

\TLV m_extension()

   // RISC-V M-Extension instructions in WARP-V are fixed latency
   // As of today, to handle those instructions, WARP-V pipeline is stalled for the given latency, and the
   // results are written back through a second issue at the end of stalling duration.
   // Verilog modules are inherited from PicoRV32, and are located in the ./muldiv directory.
   // Since the modules have a fixed latency, their valid signals are instantiated as valid decode for M-type
   // instructions is detected, and results are put in /orig_inst scope to be used in second issue.

   // This macro handles the stalling logic using a counter, and triggers second issue accordingly.

   // latency for division is different for ALTOPS case
   m4_ifelse(M4_RISCV_FORMAL_ALTOPS, 1, ['
        m4_define(['M4_DIV_LATENCY'], 12)
   '],['
        m4_define(['M4_DIV_LATENCY'], 37)
   '])
   m4_define(['M4_MUL_LATENCY'], 5)       // latency for multiplication is 2 cycles in case of ALTOPS,
                                          // but we flop it for 5 cycles (in rslt_mux) to augment the normal
                                          // second issue behavior

   // Relative to typical 1-cycle latency instructions.

   @M4_NEXT_PC_STAGE
      $second_issue_div_mul = >>M4_NON_PIPELINED_BUBBLES$trigger_next_pc_div_mul_second_issue;
   @M4_EXECUTE_STAGE
      {$div_stall, $mul_stall, $stall_cnt[5:0]} =    $reset ? '0 :
                                                     $second_issue_div_mul ? '0 :
                                                     ($commit && $div_mul) ? {$divtype_instr, $multype_instr, 6'b1} :
                                                     >>1$div_stall ? {1'b1, 1'b0, >>1$stall_cnt + 6'b1} :
                                                     >>1$mul_stall ? {1'b0, 1'b1, >>1$stall_cnt + 6'b1} :
                                                     '0;
                                                     
      $stall_cnt_upper_mul = ($stall_cnt == M4_MUL_LATENCY);
      $stall_cnt_upper_div = ($stall_cnt == M4_DIV_LATENCY);
      $trigger_next_pc_div_mul_second_issue = ($div_stall && $stall_cnt_upper_div) || ($mul_stall && $stall_cnt_upper_mul);

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
      // this module is located in ./muldiv/picorv32_pcpi_fast_mul.sv
      \SV_plus      
            picorv32_pcpi_fast_mul #(.EXTRA_MUL_FFS(1), .EXTRA_INSN_FFS(1), .MUL_CLKGATE(0)) mul(
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
                                                       3'b100 ; // default to div, but this case 
                                                                // should not be encountered ideally
      $div_insn[31:0] = {7'b0000001,10'b0011000101,3'b000,5'b00101,7'b0110011} | ($opcode << 12);
                     // {  funct7  ,{rs2, rs1} (X), funct3, rd (X),  opcode  }   
      // this module is located in ./muldiv/picorv32_div_opt.sv
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

//==================//
//      RISC-V      //
//  "F" Extension   //
//==================//

\SV
   m4_ifelse_block(M4_EXT_F, 1, ['
      m4_ifelse(M4_ISA, ['RISCV'], [''], ['m4_errprint(['F-ext supported for RISC-V only.']m4_new_line)'])
      /* verilator lint_off WIDTH */
      /* verilator lint_off CASEINCOMPLETE */   
      m4_include_url(['https:/']['/raw.githubusercontent.com/stevehoover/warp-v_includes/master/fpu/topmodule.tlv'])
      /* verilator lint_on CASEINCOMPLETE */
      /* verilator lint_on WIDTH */
   '])

\TLV fpu_exe(/_name, /_top, #_expwidth, #_sigwidth, #_intwidth, $_input1, $_input2, $_input3, $_int_input, $_int_output, $_operation, $_roundingmode, $_nreset, $_clock, $_input_valid, $_outvalid, $_lt_compare, $_eq_compare, $_gt_compare, $_unordered, $_output, $_output11 , $_output_class, $_exception_invaild_output, $_exception_infinite_output, $_exception_overflow_output, $_exception_underflow_output, $_exception_inexact_output) 
   /_name
      $control = 1'b1;
      
      $is_neg_infinite = /_top['']$_input1[(#_expwidth + #_sigwidth) - 1] && (& /_top['']$_input1[(#_expwidth + #_sigwidth) - 2 : (#_sigwidth - 1)]) && (! (| /_top['']$_input1[(#_sigwidth - 2) : 0]));
      $is_pos_infinite = (! /_top['']$_input1[(#_expwidth + #_sigwidth) - 1]) && (& /_top['']$_input1[(#_expwidth + #_sigwidth) - 2 : (#_sigwidth - 1)]) && (! (| /_top['']$_input1[(#_sigwidth - 2) : 0]));
      $is_neg_zero = /_top['']$_input1[(#_expwidth + #_sigwidth) - 1] && (! (| /_top['']$_input1[(#_expwidth + #_sigwidth) - 2 : (#_sigwidth - 1)])) && (! (| /_top['']$_input1[(#_sigwidth - 2) : 0]));
      $is_neg_normal = /_top['']$_input1[(#_expwidth + #_sigwidth) - 1] && ((! (& /_top['']$_input1[(#_expwidth + #_sigwidth) - 2 : (#_sigwidth - 1)])) && (| /_top['']$_input1[(#_sigwidth - 2) : 0]));
      $is_neg_subnormal = /_top['']$_input1[(#_expwidth + #_sigwidth) - 1] && (! (| /_top['']$_input1[(#_expwidth + #_sigwidth) - 2 : (#_sigwidth - 1)])) && (| /_top['']$_input1[(#_sigwidth - 2) : 0]);
      $is_pos_zero = (! /_top['']$_input1[(#_expwidth + #_sigwidth) - 1]) && (! (| /_top['']$_input1[(#_expwidth + #_sigwidth) - 2 : (#_sigwidth - 1)])) && (! (| /_top['']$_input1[(#_sigwidth - 2) : 0]));
      $is_pos_normal = (! /_top['']$_input1[(#_expwidth + #_sigwidth) - 1]) && ((! (& /_top['']$_input1[(#_expwidth + #_sigwidth) - 2 : (#_sigwidth - 1)])) && (| /_top['']$_input1[(#_sigwidth - 2) : 0]));
      $is_pos_subnormal = (! /_top['']$_input1[(#_expwidth + #_sigwidth) - 1]) && (! (| /_top['']$_input1[(#_expwidth + #_sigwidth) - 2 : (#_sigwidth - 1)])) && (| /_top['']$_input1[(#_sigwidth - 2) : 0]);
      
      m4+fn_to_rec(1, #_expwidth, #_sigwidth, /_top['']$_input1, $fn_to_rec_a) 
      m4+fn_to_rec(2, #_expwidth, #_sigwidth, /_top['']$_input2, $fn_to_rec_b) 
      m4+fn_to_rec(3, #_expwidth, #_sigwidth, /_top['']$_input3, $fn_to_rec_c) 
      
      $is_operation_int_to_recfn = (/_top['']$_operation == 5'h17  ||  /_top['']$_operation == 5'h18);
      ?$is_operation_int_to_recfn
         $signedin = (/_top['']$_operation == 5'h17) ? 1'b1 : 1'b0 ;
         m4+int_to_recfn(1, #_expwidth, #_sigwidth, #_intwidth, $control, $signedin, /_top['']$_int_input, /_top['']$_roundingmode, $output_int_to_recfn, $exception_flags_int_to_recfn)
         
      
      $is_operation_class = (/_top['']$_operation == 5'h16);
      ?$is_operation_class
         m4+is_sig_nan(1, #_expwidth, #_sigwidth, $fn_to_rec_a, $issignan)
         $_output_class[3:0] = $is_neg_infinite   ? 4'h0 :
                              $is_neg_normal     ? 4'h1 :
                              $is_neg_subnormal  ? 4'h2 :
                              $is_neg_zero       ? 4'h3 :
                              $is_pos_zero       ? 4'h4 :
                              $is_pos_subnormal  ? 4'h5 :
                              $is_pos_normal     ? 4'h6 :
                              $is_pos_infinite   ? 4'h7 :
                              $issignan         ? 4'h8 : 4'h9;
      
      $is_operation_add_sub = (/_top['']$_operation == 5'h6  ||  /_top['']$_operation == 5'h7);
      ?$is_operation_add_sub
         $subOp = (/_top['']$_operation == 5'h6) ? 1'b0 : 1'b1;
         m4+add_sub_recfn(1, #_expwidth, #_sigwidth, $control, $subOp, $fn_to_rec_a, $fn_to_rec_b, /_top['']$_roundingmode, $output_add_sub, $exception_flags_add_sub)
         
      $is_operation_mul = (/_top['']$_operation == 5'h8);
      ?$is_operation_mul
         m4+mul_recfn(1, #_expwidth, #_sigwidth, $control, $fn_to_rec_a, $fn_to_rec_b, /_top['']$_roundingmode, $output_mul, $exception_flags_mul)
         
      $is_operation_div_sqrt = (/_top['']$_operation == 5'h9 || /_top['']$_operation == 5'ha);
      //?$is_operation_div_sqrt
      $div_sqrt_Op = (/_top['']$_operation == 5'h9) ? 1'b0 : 1'b1;
      //<Currently it's just one time>
      $get_valid = /_top['']$_input_valid;
      $operand_div_sqrt_a[(#_expwidth + #_sigwidth):0] = ($get_valid) ? $fn_to_rec_a[(#_expwidth + #_sigwidth):0] : $RETAIN;
      $operand_div_sqrt_b[(#_expwidth + #_sigwidth):0] = ($get_valid) ? $fn_to_rec_b[(#_expwidth + #_sigwidth):0] : $RETAIN;
      m4+div_sqrt_recfn_small(1, #_expwidth, #_sigwidth, /_top['']$_nreset, /_top['']$_clock, $control, $in_ready, $get_valid, $div_sqrt_Op, $operand_div_sqrt_a, $operand_div_sqrt_b, /_top['']$_roundingmode, $_outvalid, $sqrtresult, $output_div_sqrt, $exception_flags_div_sqrt)
      $result_div_sqrt_temp[(#_expwidth + #_sigwidth):0] = ($_outvalid) ? $output_div_sqrt : $RETAIN;
      
      $is_operation_compare = (/_top['']$_operation == 5'he || /_top['']$_operation == 5'hf || /_top['']$_operation == 5'h13 || /_top['']$_operation == 5'h14 || /_top['']$_operation == 5'h15);
      ?$is_operation_compare
         $signaling_compare =  ($fn_to_rec_a == $fn_to_rec_b) ? 1'b0 : 1'b1;
         m4+compare_recfn(1, #_expwidth, #_sigwidth, $fn_to_rec_a, $fn_to_rec_b, $signaling_compare, $_lt_compare, $_eq_compare, $_gt_compare, $_unordered, $exception_flags_compare)
         $output_min[(#_expwidth + #_sigwidth):0] = ($_gt_compare == 1'b1) ? $fn_to_rec_b : $fn_to_rec_a;
         $output_max[(#_expwidth + #_sigwidth):0] = ($_gt_compare == 1'b1) ? $fn_to_rec_a : $fn_to_rec_b;
         
      $is_operation_mul_add = (/_top['']$_operation == 5'h2 || /_top['']$_operation == 5'h3 || /_top['']$_operation == 5'h4 || /_top['']$_operation == 5'h5);
      ?$is_operation_mul_add
         $op_mul_add[1:0] = (/_top['']$_operation == 5'h2) ? 2'b00 :
                     (/_top['']$_operation == 5'h3) ? 2'b01 :
                     (/_top['']$_operation == 5'h4) ? 2'b10 :
                     (/_top['']$_operation == 5'h5) ? 2'b11 : 2'hx;
         m4+mul_add_recfn(1, #_expwidth, #_sigwidth, $control, $op_mul_add, $fn_to_rec_a, $fn_to_rec_b, $fn_to_rec_c, /_top['']$_roundingmode, $output_mul_add, $exception_flags_mul_add)
         
      $final_output_module[(#_expwidth + #_sigwidth):0] = (/_top['']$_operation == 5'h2 || /_top['']$_operation == 5'h3 || /_top['']$_operation == 5'h4 || /_top['']$_operation == 5'h5) ? $output_mul_add :
                                                      (/_top['']$_operation == 5'h6 || /_top['']$_operation == 5'h7) ? $output_add_sub :
                                                      (/_top['']$_operation == 5'h8) ? $output_mul :
                                                      //(/_top['']$_operation == 5'h9 || /_top['']$_operation == 5'ha) ? $output_div_sqrt :
                                                      ( $_outvalid && (/_top['']$_operation == 5'h9 || /_top['']$_operation == 5'ha)) ? $result_div_sqrt_temp :
                                                      (/_top['']$_operation == 5'he) ? $output_min :
                                                      (/_top['']$_operation == 5'hf) ? $output_max :
                                                      (/_top['']$_operation == 5'h17  ||  /_top['']$_operation == 5'h18) ? $output_int_to_recfn : $RETAIN;
      
      $is_operation_recfn_to_int = (/_top['']$_operation == 5'h10  ||  /_top['']$_operation == 5'h11);
      ?$is_operation_recfn_to_int
         $signedout = (/_top['']$_operation == 5'h10) ? 1'b1 : 1'b0 ;
         m4+recfn_to_int(1, #_expwidth, #_sigwidth, #_intwidth, $control, $signedout, $fn_to_rec_a, /_top['']$_roundingmode, $_int_output, $exception_flags_recfn_to_int)
         
      m4+rec_to_fn(1, #_expwidth, #_sigwidth, $final_output_module, $result_fn)
      m4+rec_to_fn(2, #_expwidth, #_sigwidth, $result_div_sqrt_temp, $result_fn11)
      // Output for div_sqrt module
      $_output11[(#_expwidth + #_sigwidth) - 1:0] = $result_fn11;
      // Output for other modules
      $_output[(#_expwidth + #_sigwidth) - 1:0] = $result_fn;
      // Exception Flags with their mask according to RISC-V specs.
      $exception_flags_all[4:0] =   $is_operation_add_sub ? {$exception_flags_add_sub & 5'b10111} :
                                           $is_operation_mul ? {$exception_flags_mul & 5'b10111} :
       ($is_operation_div_sqrt || $outvalid) && !$sqrtresult ? {$exception_flags_div_sqrt & 5'b11111} :
       ($is_operation_div_sqrt || $outvalid) && $sqrtresult  ? {$exception_flags_div_sqrt & 5'b10001} :
                                       $is_operation_compare ? {$exception_flags_compare & 5'b10000} :
                                      $is_operation_mul_add  ? {$exception_flags_mul_add & 5'b10111} :
                                  $is_operation_int_to_recfn ? {$exception_flags_int_to_recfn & 5'b10001} :
                                  $is_operation_recfn_to_int ? {2'b00, ($exception_flags_recfn_to_int & 5'b10001)} :
                                                               >>1$exception_flags_all;
      {$_exception_invaild_output, $_exception_infinite_output, $_exception_overflow_output, $_exception_underflow_output, $_exception_inexact_output} = $exception_flags_all[4:0];

\TLV f_extension()
   
   // RISC-V F-Extension instructions in WARP-V are fixed latency
   // As of today, to handle those instructions, WARP-V pipeline is stalled for the given latency, and the
   // results are written back through a second issue at the end of stalling duration.
   // Verilog modules are inherited from Berkeley Hard-Float to implement "F" extension support, and are located in the ./fpu directory.
   // Since the modules have a fixed latency, their valid signals are instantiated as valid decode for F-type
   // instructions is detected, and results are put in /orig_inst scope to be used in second issue.
   // This macro handles the stalling logic using a counter, and triggers second issue accordingly.
   
   m4_define(['M4_FPU_DIV_LATENCY'], 26)  // Relative to typical 1-cycle latency instructions.
   @M4_NEXT_PC_STAGE
      $fpu_second_issue_div_sqrt = >>M4_NON_PIPELINED_BUBBLES$trigger_next_pc_fpu_div_sqrt_second_issue;
   @M4_EXECUTE_STAGE
      {$fpu_div_sqrt_stall, $fpu_stall_cnt[5:0]} =    $reset ? 7'b0 :
                                                   <<m4_eval(M4_EXECUTE_STAGE - M4_NEXT_PC_STAGE)$fpu_second_issue_div_sqrt ? 7'b0 :
                                                   ($commit && $fpu_div_sqrt_type_instr) ? {$fpu_div_sqrt_type_instr, 6'b1} :
                                                   >>1$fpu_div_sqrt_stall ? {1'b1, >>1$fpu_stall_cnt + 6'b1} :
                                                   7'b0;
      $stall_cnt_max_fpu = ($fpu_stall_cnt == M4_FPU_DIV_LATENCY);
      $trigger_next_pc_fpu_div_sqrt_second_issue = ($fpu_div_sqrt_stall && $stall_cnt_max_fpu) || (|fetch/instr/fpu1$outvalid);


//==================//
//      RISC-V      //
//  "B" Extension   // WIP. NOT FROZEN
//==================//

\SV
   m4_ifelse_block(M4_EXT_B, 1, ['
      m4_ifelse(M4_ISA, ['RISCV'], [''], ['m4_errprint(['B-ext supported for RISC-V only.']m4_new_line)'])
      /* verilator lint_off WIDTH */
      /* verilator lint_off PINMISSING */
      /* verilator lint_off CASEOVERLAP */
      m4_include_url(['https:/']['/raw.githubusercontent.com/stevehoover/warp-v_includes/master/b-ext/top_bext_module.tlv'])
      /* verilator lint_on WIDTH */
      /* verilator lint_on CASEOVERLAP */
      /* verilator lint_on PINMISSING */   
   '])      
\TLV b_extension()

   // Few of RISC-V B-Extension instructions (CRC and CMUL) in WARP-V are of fixed latency.
   // At present we refered to the same way latency in M-extension is handled.
   // Verilog modules for those inst. are inherited from Clifford Wolf's draft implementation, located inside warp-v_includes in ./b-ext directory.
   // Although the latency of different variant of CRC instr's are different, we are using a common FIXED LATENCY
   // for those instr's.

   m4_define(['M4_CLMUL_LATENCY'], 5)
   m4_define(['M4_CRC_LATENCY'], 5)
   @M4_NEXT_PC_STAGE
      $second_issue_clmul_crc = >>M4_NON_PIPELINED_BUBBLES$trigger_next_pc_clmul_crc_second_issue;
   @M4_EXECUTE_STAGE
      {$clmul_stall, $crc_stall, $clmul_crc_stall_cnt[5:0]} =  $reset ? '0 :
                                         $second_issue_clmul_crc ? '0 :
                                         ($commit && $clmul_crc_type_instr) ? {$clmul_type_instr, $crc_type_instr, 6'b1} :
                                         >>1$clmul_stall ? {1'b1, 1'b0, >>1$clmul_crc_stall_cnt + 6'b1} :
                                         >>1$crc_stall ? {1'b0, 1'b1, >>1$clmul_crc_stall_cnt + 6'b1} :
                                         '0;
      
      $stall_cnt_max_clmul = ($clmul_crc_stall_cnt == M4_CLMUL_LATENCY);
      $stall_cnt_max_crc   = ($clmul_crc_stall_cnt == M4_CRC_LATENCY);
      $trigger_next_pc_clmul_crc_second_issue = ($clmul_stall && $stall_cnt_max_clmul) || ($crc_stall && $stall_cnt_max_crc);
      

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
            $second_issue = $second_issue_ld m4_ifelse(M4_EXT_M, 1, ['|| $second_issue_div_mul']) m4_ifelse(M4_EXT_F, 1, ['|| $fpu_second_issue_div_sqrt']) m4_ifelse(M4_EXT_B, 1, ['|| $second_issue_clmul_crc']);
            // Recirculate returning load or the div_mul_result from /orig_inst scope
            
            ?$second_issue_ld
               // This scope holds the original load for a returning load.
               /orig_load_inst
                  $ANY = /_cpu|mem/data>>M4_LD_RETURN_ALIGN$ANY;
                  /src[2:1]
                     $ANY = /_cpu|mem/data/src>>M4_LD_RETURN_ALIGN$ANY;
            ?$second_issue
               /orig_inst
                  // pull values from /orig_load_inst or /hold_inst depending on which second issue
                  $ANY = |fetch/instr$second_issue_ld ? |fetch/instr/orig_load_inst$ANY : m4_ifelse(M4_EXT_M, 1, ['|fetch/instr$second_issue_div_mul ? |fetch/instr/hold_inst>>M4_NON_PIPELINED_BUBBLES$ANY :']) m4_ifelse(M4_EXT_F, 1, ['|fetch/instr$fpu_second_issue_div_sqrt ? |fetch/instr/hold_inst>>M4_NON_PIPELINED_BUBBLES$ANY :']) m4_ifelse(M4_EXT_B, 1, ['|fetch/instr$second_issue_clmul_crc ? |fetch/instr/hold_inst>>M4_NON_PIPELINED_BUBBLES$ANY :']) |fetch/instr/orig_load_inst$ANY;
                  /src[2:1]
                     $ANY = |fetch/instr$second_issue_ld ? |fetch/instr/orig_load_inst/src$ANY : m4_ifelse(M4_EXT_M, 1, ['|fetch/instr$second_issue_div_mul ? |fetch/instr/hold_inst/src>>M4_NON_PIPELINED_BUBBLES$ANY :']) m4_ifelse(M4_EXT_F, 1, ['|fetch/instr$fpu_second_issue_div_sqrt ? |fetch/instr/hold_inst/src>>M4_NON_PIPELINED_BUBBLES$ANY :']) m4_ifelse(M4_EXT_B, 1, ['|fetch/instr$second_issue_clmul_crc ? |fetch/instr/hold_inst/src>>M4_NON_PIPELINED_BUBBLES$ANY :']) |fetch/instr/orig_load_inst/src$ANY;
            
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
            $replay_int = | /src[*]$replay || ($is_dest_condition && $dest_pending);

            m4_ifelse_block(M4_EXT_F, 1, ['
            //
            // ======
            // Reg Rd for Floating Point Unit
            // ======
            // 
            /M4_FPUREGS_HIER
            /fpusrc[3:1]
               $is_fpu_reg_condition = $is_fpu_reg && /instr$valid_decode;  // Note: $is_fpu_reg can be set for RISC-V sr0.
               ?$is_fpu_reg_condition
                  {$fpu_reg_value[M4_WORD_RANGE], $pending_fpu} =
                     m4_ifelse(M4_ISA, ['RISCV'], ['// Note: f0 is not hardwired to ground as r0 does'])
                     // Bypass stages. Both register and pending are bypassed.
                     // Bypassed registers must be from instructions that are good-path as of this instruction or are 2nd issuing.
                     m4_ifexpr(M4_REG_BYPASS_STAGES >= 1, ['(/instr>>1$dest_fpu_reg_valid && (/instr$GoodPathMask[1] || /instr>>1$second_issue) && (/instr>>1$dest_fpu_reg == $fpu_reg)) ? {/instr>>1$rslt, /instr>>1$reg_wr_pending} :'])
                     m4_ifexpr(M4_REG_BYPASS_STAGES >= 2, ['(/instr>>2$dest_fpu_reg_valid && (/instr$GoodPathMask[2] || /instr>>2$second_issue) && (/instr>>2$dest_fpu_reg == $fpu_reg)) ? {/instr>>2$rslt, /instr>>2$reg_wr_pending} :'])
                     m4_ifexpr(M4_REG_BYPASS_STAGES >= 3, ['(/instr>>3$dest_fpu_reg_valid && (/instr$GoodPathMask[3] || /instr>>3$second_issue) && (/instr>>3$dest_fpu_reg == $fpu_reg)) ? {/instr>>3$rslt, /instr>>3$reg_wr_pending} :'])
                     {/instr/fpuregs[$fpu_reg]>>M4_REG_BYPASS_STAGES$fpuvalue, m4_ifelse(M4_PENDING_ENABLED, ['0'], ['1'b0'], ['/instr/fpuregs[$fpu_reg]>>M4_REG_BYPASS_STAGES$pending_fpu'])};
               // Replay if FPU source register is pending.
               $replay_fpu = $is_fpu_reg_condition && $pending_fpu;

            // Also replay for pending dest reg to keep writes in order. Bypass dest reg pending to support this.
            $is_dest_fpu_condition = $dest_fpu_reg_valid && /instr$valid_decode;
            ?$is_dest_fpu_condition
               $dest_fpu_pending =
                  m4_ifelse(M4_ISA, ['RISCV'], ['// Note: f0 is not hardwired to ground as r0 does'])
                  // Bypass stages. Both register and pending are bypassed.
                  m4_ifexpr(M4_REG_BYPASS_STAGES >= 1, ['(>>1$dest_fpu_reg_valid && ($GoodPathMask[1] || /instr>>1$second_issue) && (>>1$dest_fpu_reg == $dest_fpu_reg)) ? >>1$reg_wr_pending :'])
                  m4_ifexpr(M4_REG_BYPASS_STAGES >= 2, ['(>>2$dest_fpu_reg_valid && ($GoodPathMask[2] || /instr>>2$second_issue) && (>>2$dest_fpu_reg == $dest_fpu_reg)) ? >>2$reg_wr_pending :'])
                  m4_ifexpr(M4_REG_BYPASS_STAGES >= 3, ['(>>3$dest_fpu_reg_valid && ($GoodPathMask[3] || /instr>>3$second_issue) && (>>3$dest_fpu_reg == $dest_fpu_reg)) ? >>3$reg_wr_pending :'])
                  m4_ifelse(M4_PENDING_ENABLED, ['0'], ['1'b0'], ['/fpuregs[$dest_fpu_reg]>>M4_REG_BYPASS_STAGES$pending_fpu']);
            // Combine replay conditions for pending source or dest registers.
            $replay_fpu = | /fpusrc[*]$replay_fpu || ($is_dest_fpu_condition && $dest_fpu_pending);
            '])
            $replay = $replay_int m4_ifelse(M4_EXT_F, 1, ['|| $replay_fpu']);
         
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
            $non_pipelined = $div_mul m4_ifelse(M4_EXT_F, 1, ['|| $fpu_div_sqrt_type_instr']) m4_ifelse(M4_EXT_B, 1, ['|| $clmul_crc_type_instr']);
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
            $valid_dest_reg_valid = ($dest_reg_valid && $commit) || ($second_issue m4_ifelse_block(M4_EXT_F, 1, ['&&  (!>>M4_LD_RETURN_ALIGN$is_flw_instr) && (!$fpu_second_issue_div_sqrt)']) );

            m4_ifelse_block(M4_EXT_F, 1, ['
            $valid_dest_fpu_reg_valid = ($dest_fpu_reg_valid && $commit) || ($fpu_second_issue_div_sqrt || ($second_issue && >>M4_LD_RETURN_ALIGN$is_flw_instr));
            '])
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
            m4_ifelse_block(M4_EXT_F, 1, ['
            // Reg Write (Floating Point Register)
            // TODO. Seperate the $rslt comit to both "int" and "fpu" regs.
            $fpu_reg_write = $reset ? 1'b0 : $valid_dest_fpu_reg_valid;
            \SV_plus
               always @ (posedge clk) begin
                  if ($fpu_reg_write)
                     /fpuregs[$dest_fpu_reg]<<0$$fpuvalue[M4_WORD_RANGE] <= $rslt;
               end
            m4_ifelse_block(M4_PENDING_ENABLED, 1, ['
            // Write $pending along with $value, but coded differently because it must be reset.
            /fpuregs[*]
               <<1$pending_fpu = ! /instr$reset && (((#fpuregs == /instr$dest_fpu_reg) && /instr$valid_dest_fpu_reg_valid) ? /instr$reg_wr_pending : $pending_fpu);
              '])
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
         @M4_EXECUTE_STAGE
            // characterise non-speculatively in execute stage

            $pc[M4_PC_RANGE] = $Pc[M4_PC_RANGE];  // A version of PC we can pull through $ANYs.
            // RVFI interface for formal verification.
            $trap = $aborting_trap ||
                    $non_aborting_trap;
            $rvfi_trap        = ! $reset && >>m4_eval(-M4_MAX_REDIRECT_BUBBLES + 1)$next_rvfi_good_path_mask[M4_MAX_REDIRECT_BUBBLES] &&
                                $trap && ! $replay && ! $second_issue;  // Good-path trap, not aborted for other reasons.
            
            // Order for the instruction/trap for RVFI check. (For split instructions, this is associated with the 1st issue, not the 2nd issue.)
            $rvfi_order[63:0] = $reset                  ? 64'b0 :
                                ($commit || $rvfi_trap) ? >>1$rvfi_order + 64'b1 :
                                                          $RETAIN;
         @M4_REG_WR_STAGE
            // verify in register writeback stage

            // This scope is a copy of /orig_inst if $second_issue, else pull current instruction

            /original
               $ANY = /instr$second_issue ? /instr/orig_inst$ANY : /instr$ANY;
               /src[2:1]instr
                  $ANY = /instr$second_issue ? /instr/orig_inst/src$ANY : /instr/src$ANY;

            $would_reissue = ($ld || $div_mul);
            $retire = ($commit && !$would_reissue ) || $second_issue;
            // a load or div_mul instruction commits results in the second issue, hence the first issue is non-retiring
            // for the first issue of these instructions, $rvfi_valid is not asserted and hence the current outputs are 
            // not considered by riscv-formal

            $rvfi_valid       = ! |fetch/instr<<m4_eval(M4_REG_WR_STAGE - (M4_NEXT_PC_STAGE - 1))$reset &&    // Avoid asserting before $reset propagates to this stage.
                                ($retire || $rvfi_trap );
            *rvfi_valid       = $rvfi_valid;
            *rvfi_halt        = $rvfi_trap;
            *rvfi_trap        = $rvfi_trap;
            *rvfi_ixl         = 2'd1;
            *rvfi_mode        = 2'd3;
            /original
               *rvfi_insn        = $raw;
               *rvfi_order       = $rvfi_order;
               *rvfi_intr        = 1'b0;
               *rvfi_rs1_addr    = /src[1]$is_reg ? $raw_rs1 : 5'b0;
               *rvfi_rs2_addr    = /src[2]$is_reg ? $raw_rs2 : 5'b0;
               *rvfi_rs1_rdata   = /src[1]$is_reg ? /src[1]$reg_value : M4_WORD_CNT'b0;
               *rvfi_rs2_rdata   = /src[2]$is_reg ? /src[2]$reg_value : M4_WORD_CNT'b0;
               *rvfi_rd_addr     = (/instr$dest_reg_valid && ! $abort) ? $raw_rd : 5'b0;
               *rvfi_rd_wdata    = (| *rvfi_rd_addr) ? /instr$rslt : 32'b0;
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
            *rvfi_mem_rmask   = /original$ld ? /orig_load_inst$ld_mask : 0;
            *rvfi_mem_wmask   = $valid_st ? $st_mask : 0;
            *rvfi_mem_rdata   = /original$ld ? /orig_load_inst$ld_value : 0;
            *rvfi_mem_wdata   = $valid_st ? $st_value : 0;

            `BOGUS_USE(/src[2]$dummy)

// Ingress/Egress packet buffers between the CPU and NoC.
// Packet buffers are m4+vc_flop_fifo_v2(...)s. See m4+vc_flop_fifo_v2 definition in tlv_flow_lib package
//   and instantiations below for interface.
// A header flit is inserted containing {src, dest}.
// NoC must provide |egress_out interface and |ingress_in m4+vc_flop_fifo_v2(...) interface.
\TLV noc_cpu_buffers(/_cpu, #depth)
   // Egress FIFO.


   |egress_in
      @-1
         $reset = *reset;
      /instr
         // Stage numbering has @0 == |fetch@M4_EXECUTE_STAGE 
         @0
            $ANY = /_cpu|fetch/instr>>M4_EXECUTE_STAGE$ANY;  // (including $reset)
            $is_pkt_wr = $is_csr_write && ($is_csr_pktwr || $is_csr_pkttail);
            $vc[M4_VC_INDEX_RANGE] = $csr_pktwrvc[M4_VC_INDEX_RANGE];
            // This PKTWR write is blocked if the skid buffer blocked last cycle.
            $pkt_wr_blocked = $is_pkt_wr && |egress_in/skid_buffer>>1$push_blocked;
         @1
            $valid_pkt_wr = $is_pkt_wr && $commit;
            $valid_pkt_tail = $valid_pkt_wr && $is_csr_pkttail;
            $insert_header = |egress_in/skid_buffer$valid_pkt_wr && ! $InPacket;
            // Assert after inserting header up to insertion of tail.
            $InPacket <= $insert_header || ($InPacket && ! (|egress_in/skid_buffer$valid_pkt_tail && ! |egress_in/skid_buffer$push_blocked));
      @1

         /skid_buffer
            $ANY = >>1$push_blocked ? >>1$ANY : |egress_in/instr$ANY;
            // Hold the write if blocked, including the write of the header in separate signals.
            // This give 1 cycle of slop so we have time to check validity and generate a replay if blocked.
            // Note that signals in this scope are captured versions reflecting the flit and its producing instruction.
            $push_blocked = $valid_pkt_wr && (/_cpu/vc[$vc]|egress_in$blocked || ! |egress_in/instr$InPacket);
            // Header
            // Construct header flit.
            $src[M4_CORE_INDEX_RANGE] = #m4_strip_prefix(/_cpu);
            $header_flit[31:0] = {{M4_FLIT_UNUSED_CNT{1'b0}},
                                  $src,
                                  $vc,
                                  $csr_pktdest[m4_echo(M4_CORE_INDEX_RANGE)]
                                 };
         /flit
             // TODO. ADD a WHEN condition.
            {$tail, $flit[M4_WORD_RANGE]} = |egress_in/instr$insert_header ? {1'b0, |egress_in/skid_buffer$header_flit} :
                                                                             {|egress_in/skid_buffer$valid_pkt_tail, |egress_in/skid_buffer$csr_wr_value};
   /vc[*]
      |egress_in
         @1
            $vc_trans_valid = /_cpu|egress_in/skid_buffer$valid_pkt_wr && (/_cpu|egress_in/skid_buffer$vc == #vc);
   m4+vc_flop_fifo_v2(/_cpu, |egress_in, @1, |egress_out, @1, #depth, /flit, M4_VC_RANGE, M4_PRIO_RANGE)
   
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
               $csr_pktrd[M4_WORD_RANGE] = /_cpu|ingress_out/flit<<M4_EXECUTE_STAGE$flit;
   |ingress_out
      @-1
         // Note that we access signals here that are produced in @M4_DECODE_STAGE, so @M4_DECODE_STAGE must not be the same physical stage as @M4_EXECUTE_STAGE.
         /instr
            $ANY = /_cpu|fetch/instr>>M4_EXECUTE_STAGE$ANY;
         $is_pktrd = /instr$is_csr_instr && /instr$is_csr_pktrd;
         // Detect a recent change to PKTRDVCS that could invalidate the use of a stale PKTRDVCS value and must avoid read (which will force a replay).
         $pktrdvcs_changed = /instr>>1$is_csr_write && /instr>>1$is_csr_pktrdvcs;
         $do_pktrd = $is_pktrd && ! $pktrdvcs_changed;
      @0
         // Replay for PKTRD with no data read.
         $pktrd_blocked = $is_pktrd && ! $trans_valid;
   /vc[*]
      |ingress_out
         @-1
            $has_credit = /_cpu|ingress_out/instr>>1$csr_pktrdvcs[#vc] &&
                          /_cpu|ingress_out$do_pktrd;
            $Prio[M4_PRIO_INDEX_RANGE] <= '0;
   m4+vc_flop_fifo_v2(/_cpu, |ingress_in, @0, |ingress_out, @0, #depth, /flit, M4_VC_RANGE, M4_PRIO_RANGE)

\TLV noc_insertion_ring(/_cpu, #_depth)
   /vc[*]
      |ingress_in
         @0
            $vc_match = /_cpu|rg_arriving>>m4_align(0, 0)$vc == #vc;
            $vc_trans_valid = /_cpu|ingress_in$trans_valid && /_cpu|ingress_in/arriving$body && $vc_match;
   |ingress_in
      @0
         /arriving
            $ANY = /_cpu|rg_arriving<>0$ANY;
         $blocked = 
            /arriving$body ? ! >>1$trans_valid :   // Body flits may only follow a flit in the last cycle.
                             ! /_cpu/vc[/arriving$vc]|ingress_in$would_bypass;  // Head flits may only enter an empty FIFO.
         $trans_valid = $avail && ! $blocked;
         
   /vc[*]
      |egress_out
         @0
            // Per-VC backpressure from NoC.
            $has_credit = ! /_cpu|egress_out$blocked &&   // propagate blocked
                          (! /_cpu|egress_out$body || (/_cpu|egress_out$body_vc == #vc));   // avoid interleaving packets
            $Prio[M4_PRIO_INDEX_RANGE] <= '0;
   |egress_out
      @-1
         $reset = *reset;
      @0
         // This is a body flit (includes invalid body flits and tail flit) if last cycle was a tail flit and 
         $body = $reset   ? 1'b0 :
                 >>1$body ? ! >>1$valid_tail :
                            >>1$valid_head;
         $body_vc[M4_VC_INDEX_RANGE] = >>1$valid_head ? /flit>>1$flit[M4_FLIT_VC_RANGE] : $RETAIN;
      @1
         $avail = $trans_valid;
         $valid_head = $trans_valid && ! $body;
         $valid_tail = $trans_valid && /flit$tail;
   m4+insertion_ring(/_cpu, |egress_out, @1, |ingress_in, @0, /_cpu|ingress_in<<1$reset, |rg, /flit, 2, #_depth)



// +++++++++++++++++++++++++++++++++++++++++++++++++++
// MOVE OUT


// Register insertion ring.
//
// See diagram here: https://docs.google.com/drawings/d/1VS_oaNYgT3p4b64nGSAjs5FKSvs_-s8OTfTY4gQjX6o/edit?usp=sharing
//
// This macro provides a ring with support for multi-flit packets. It is unable to utilize the m4+simple_ring macro because flits
// pulled from the ring to the insertion FIFO are pulled prior to the ring flit mux, whereas the ring macros
// pull the output flit after. This difference implies that the other ring macros support local loopback, whereas
// this one does not; packets will loopback around the ring.
//
// This ring does not support multiple VCs.
//
// Packets are contiguous on the ring without gaps.
// Once a packet is completely loaded into the insertion FIFO, it can be injected contiguously into
// the ring between packets on the ring, at which time it essentially becomes part of the ring, so the
// ring expands to absorb it. Any valid flits from the ring are absorbed into the insertion FIFO during
// insertion. The ring shrinks by absorbing idle slots as the FIFO drains. Only once the FIFO is empty
// can it be filled with a new insertion packet.
//
// Support for multiple-VCs could be added in a few ways, including:
//   o via a credit mechanism
//   o VC-specific ring slots
//   o per-VC insertion FIFOs (or ring-ingress FIFOs plus one insertion buffer) providing source
//     buffering; packets make a full circuit around the ring and back to their source to ensure
//     draining or preservation of the insertion FIFO.)
//
// For traffic from node, FIFO permits only one packet from node at a time, and fully buffers.
// Head packet and control info are not included.
//
// Control information, except head/tail, is provided in a header flit. As such, there is no support for data
// lagging 1 cycle behind control info. Control info and the decision for accepting packets based on it are
// up to the caller, but must include $dest.
//
// Flits traverse the ring from index 0 to N-1 continuing back to 0, until they reach
// their destination.
//
// The interface matches simple_ring_v2(..) with the following modifications.
//
// Input interface:
//   - $tail is required in /_flit
//   - Additional arg for #_depth: FIFO depth; at least max packet size, including header flit
//   - Removal of >>_data_delay arg
//   - Removal of $_avail_expr arg
//   - /_flit (/_trans) arg is not optional
//   - Calling context must provide /_hop|_name/arriving?$valid@0$acceptable. E.g.:
//          {..., $dest} = $head ? $data[..];
//          $acceptable = $dest
\TLV insertion_ring(/_hop, |_in, @_in, |_out, @_out, $_reset, |_name, /_flit, #_hop_dist, #_depth)
   m4_pushdef(['m4_in_delay'], m4_defaulted_arg(#_in_delay, 0))
   m4_pushdef(['m4_hop_dist'], m4_defaulted_arg(#_hop_dist, 1))
   m4_pushdef(['m4_hop_name'], m4_strip_prefix(/_hop))
   m4_pushdef(['M4_HOP'], ['M4_']m4_translit(m4_hop_name, ['a-z'], ['A-Z']))
   m4_pushdef(['m4_prev_hop_index'], (m4_hop_name + m4_echo(M4_HOP['_CNT']) - 1) % m4_echo(M4_HOP['_CNT']))
   
   // ========
   // The Flow
   // ========

   // Relax the timing on input backpressure with a skid buffer.
   m4+skid_buffer(/_hop, |_in, @_in, |_name['']_in_present, @0, /_flit, $_reset)
   // Block head flit if FIFO not empty.
   m4+connect(/_hop, |_name['']_in_present, @0, |_name['']_node_to_fifo, @0, /_flit, [''], ['|| (! /_hop|_name['']_fifo_in<>0$would_bypass && $head)'])
   // Pipeline for ring hop.
   m4+pipe(ff, m4_hop_dist, /_hop, |_name, @0, |_name['']_leaving, @0, /_flit)
   // Connect hops in a ring.
   |_name['']_arriving
      @0
         $ANY = /_hop[(#m4_hop_name + m4_echo(M4_HOP['_CNT']) - 1) % m4_echo(M4_HOP['_CNT'])]|_name['']_leaving<>0$ANY;
         /_flit
            $ANY = /_hop[(#m4_hop_name + m4_echo(M4_HOP['_CNT']) - 1) % m4_echo(M4_HOP['_CNT'])]|_name['']_leaving/_flit<>0$ANY;
   |_name['']_leaving
      @0
         $blocked = /_hop[(#m4_hop_name + 1) % m4_echo(M4_HOP['_CNT'])]|_name['']_arriving<>0$blocked;
   // Fork off ring
   m4+fork(/_hop, |_name['']_arriving, @0, $head_out, |_name['']_off_ramp, @0, $true, |_name['']_continuing, @0, /_flit)
   // Fork from off-ramp out or into FIFO
   m4+fork(/_hop, |_name['']_off_ramp, @0, $head_out, |_out, @_out, $true, |_name['']_deflected, @0, /_flit)
   // Flop prior to FIFO.
   m4+stage(ff, /_hop, |_name['']_deflected, @0, |_name['']_deflected_st1, @1, /_flit)
   // Mux into FIFO. (Priority to deflected blocks node.)
   m4+arb2(/_hop, |_name['']_deflected_st1, @1, |_name['']_node_to_fifo, @0, |_name['']_fifo_in, @0, /_flit)
   // The insertion FIFO.
   m4+flop_fifo_v2(/_hop, |_name['']_fifo_in, @0, |_name['']_fifo_out, @0, #_depth, /_flit)
   // Block FIFO output until a full packet is ready (tail from node in FIFO)
   m4+connect(/_hop, |_name['']_fifo_out, @0, |_name['']_fifo_inj, @0, /_flit, [''], ['|| ! (/_hop|_name['']_fifo_in<>0$node_tail_flit_in_fifo)'])
   // Ring
   m4+arb2(/_hop, |_name['']_fifo_inj, @0, |_name['']_continuing, @0, |_name, @0, /_flit)


   // Decode arriving header flit.
   |_name['']_arriving
      @0
         // Characterize arriving flit (head/tail/body, header)
         {$vc[M4_VC_INDEX_RANGE], $dest[m4_echo(M4_HOP['_INDEX_RANGE'])]} =
            $reset  ? '0 :
            ! $body ? {/flit$flit[M4_FLIT_VC_RANGE], /flit$flit[M4_FLIT_DEST_RANGE]} :
                      {>>1$vc, >>1$dest};
         $body = $reset   ? 1'b0 :
                 >>1$body ? ! >>1$valid_tail :
                            >>1$valid_head;
         $valid_head = $accepted && ! $body;
         $valid_tail = $accepted && /flit$tail;
         // The ring is expanded through the insertion FIFO (or one additional staging flop before it)
         // Asserts with the first absorbed flit, deasserts for the first flit that can stay on the ring.
         $valid_dest = $dest == #m4_hop_name;
         $head_out = ! /_hop|_out<>0$blocked && $valid_dest;
         $true = 1'b1; // (ok signal for fork along continuing path)
   |_name['']_off_ramp
      @0
         $head_out = /_hop|_name['']_arriving<>0$head_out;
         $true = 1'b1;  // (ok signal for fork to FIFO)
   |_name['']_in_present
      @0
         $head = $reset                          ? 1'b0 :
                 (>>1$accepted && /flit>>1$tail) ? 1'b1 :
                 (>>1$accepted && >>1$head)      ? 1'b0 :
                                                   $RETAIN;
   |_name['']_fifo_in
      @0
         // The FIFO can hold only one packet at a time.
         // Keep track of whether the FIFO (or bypass path) contains tail. This asserts for tail flit to FIFO, and deasserts after
         // tail is sent from FIFO. Streaming single-flit packets is possible without gaps.
         // XXX It will deassert for a minimum of 1 cycle (since $would_bypass enables a flit from node).
         $node_tail_flit_in_fifo =
              $reset ? 1'b0 :
              /_hop|_name['']_node_to_fifo<>0$accepted && /_hop|_name['']_node_to_fifo/flit<>0$tail ? 1'b1 :
              $would_bypass ? 1'b0 :
                   $RETAIN;

   m4_popdef(['m4_in_delay'])
   m4_popdef(['m4_hop_dist'])
   m4_popdef(['m4_hop_name'])
   m4_popdef(['M4_HOP'])
   m4_popdef(['m4_prev_hop_index'])


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

// Can be used to build for many-core without a NoC (during development).
\TLV dummy_noc(/_cpu)
   |fetch
      @M4_EXECUTE_STAGE
         /instr
            $csr_pktrd[31:0] = 32'b0;
   
// For building just the insertion ring in isolation.
// The diagram builds, but unfortunately it is messed up :(.
\TLV main_ring_only()
   /* verilator lint_on WIDTH */  // Let's be strict about bit widths.
   /M4_CORE_HIER
      |egress_out
         /flit
            @0
               $bogus_head = ((#core == 0) && | ((1 << (*cyc_cnt - 2)) & 10'b00000000100)) ||
                             ((#core == 1) && | ((1 << (*cyc_cnt - 2)) & 10'b00000000000));
               $tail       = ((#core == 0) && | ((1 << (*cyc_cnt - 2)) & 10'b00000001000)) ||
                             ((#core == 0) && | ((1 << (*cyc_cnt - 2)) & 10'b00000000000));
               $bogus_mid  = ((#core == 0) && | ((1 << (*cyc_cnt - 2)) & 10'b00000000000)) ||
                             ((#core == 1) && | ((1 << (*cyc_cnt - 2)) & 10'b00000000000));
               $bogus_src[M4_CORE_INDEX_RANGE] = #core;
               $bogus_dest[M4_CORE_INDEX_RANGE] = 1;
               $bogus_vc[M4_VC_INDEX_RANGE] = 0;
               $flit[M4_FLIT_RANGE] = $bogus_head ? {*cyc_cnt[M4_FLIT_UNUSED_CNT-3:0], 2'b01      , $bogus_vc, $bogus_src, $bogus_dest}
                                                  : {*cyc_cnt[M4_FLIT_UNUSED_CNT-3:0], $tail, 1'b0, m4_eval(M4_VC_INDEX_CNT + M4_CORE_INDEX_CNT * 2)'b1};
         @0
            $avail = /flit$bogus_head || /flit$tail || /flit$bogus_mid;
      m4+insertion_ring(/core, |egress_out, @1, |ingress_in, @0, /core|ingress_in<<1$reset, |rg, /flit, 4, 4)  // /flit, hop_latency, FIFO_depth
      |ingress_in
         @0
            $blocked = 1'b0;
            /flit
               `BOGUS_USE($flit)
   *passed = *cyc_cnt > 40;
   *failed = 1'b0;




// ===
// VIZ
// ===

//
// Logic for VIZ specific to ISA
//

\TLV mipsi_viz_logic()
   // nothing

\TLV mini_viz_logic()
   // nothing

\TLV riscv_viz_logic()
   // Code that supports 
   |fetch
      @M4_MEM_WR_STAGE
         /instr
            // A type-independent immediate value, for debug. (For R-type, funct7 is used as immediate).
            $imm_value[M4_WORD_RANGE] =
                 ({M4_WORD_CNT{$is_i_type}} & $raw_i_imm) |
                 ({M4_WORD_CNT{$is_r_type}} & {25'b0, $raw_funct7}) |
                 ({M4_WORD_CNT{$is_s_type}} & $raw_s_imm) |
                 ({M4_WORD_CNT{$is_b_type}} & $raw_b_imm) |
                 ({M4_WORD_CNT{$is_u_type}} & $raw_u_imm) |
                 ({M4_WORD_CNT{$is_j_type}} & $raw_j_imm);

\TLV dummy_viz_logic()
   // dummy

// *instrs must be consumed local to its definition (because it is local to the generate block).
\TLV instrs_for_viz()
   m4_ifelse_block(M4_VIZ, 1, ['
   |fetch
      @M4_REG_WR_STAGE
         m4_ifelse_block(M4_ISA, ['MINI'], [''], ['
         // There is an issue with \viz code indexing causing signals to be packed, and if a packed value
         // has different fields on different clocks, Verilator throws warnings.
         // These are unconditioned versions of the problematic signals.
         /instr
            /src[*]
               $unconditioned_reg[M4_REGS_INDEX_RANGE] = $reg;
               $unconditioned_is_reg = $is_reg;
               $unconditioned_reg_value[M4_WORD_RANGE] = $reg_value;
         /instr_mem
            $instr[M4_INSTR_RANGE] = *instrs[instr_mem];
         '])
         /instr_mem
            m4_case(M4_ISA, ['MINI'], ['
            '], ['RISCV'], ['
            $instr_str[40*8-1:0] = *instr_strs[instr_mem];
            '], ['MIPSI'], ['
            '], ['DUMMY'], ['
            '])
   '])

\TLV cpu_viz()
   m4+indirect(M4_isa['_viz_logic'])
   |fetch
      @M4_REG_WR_STAGE  // Visualize everything happening at the same time.
         /instr_mem[m4_eval(M4_NUM_INSTRS-1):0]  // TODO: Cleanly report non-integer ranges.
            \viz_alpha
               renderEach: function() {
                  // Instruction memory is constant, so just create it once.
                  if (!global.instr_mem_drawn) {
                     global.instr_mem_drawn = [];
                  }
                  if (!global.instr_mem_drawn[this.getIndex()]) {
                     global.instr_mem_drawn[this.getIndex()] = true;
                     m4_ifelse_block_tmp(['                     '], M4_ISA, ['MINI'], ['
                        let instr_str = '$instr'.goTo(0).asString();
                     '], M4_ISA, ['RISCV'], ['
                        let instr_str = '$instr_str'.asString() + ": " + '$instr'.asBinaryStr(NaN);
                     '], M4_ISA, ['MIPSI'], ['
                        let instr_str = '$instr'.asBinaryStr(NaN);
                     '], ['
                        let instr_str = '$instr'.goTo(0).asString();
                     '])
                     this.getCanvas().add(new fabric.Text(instr_str, {
                        top: 18 * this.getIndex(),  // TODO: Add support for '#instr_mem'.
                        left: m4_case(M4_ISA, ['MINI'], 20, ['RISCV'], -580, ['MIPSI'], -580, ['DUMMY'], 20),
                        fontSize: 14,
                        fontFamily: "monospace"
                     }));
                  }
               }
         /instr
            \viz_alpha
               //
               renderEach: function() {
                  debugger;
                  //
                  // PC instr_mem pointer
                  //
                  let $Pc = '$Pc';
                  let color = !('$commit'.asBool()) ? "gray" :
                              '$abort'.asBool()        ? "red" :
                                                         "blue";
                  let pcPointer = new fabric.Text("->", {
                     top: 18 * $Pc.asInt(),
                     left: m4_case(M4_ISA, ['MINI'], 0, ['RISCV'], -600, ['MIPSI'], -600, ['DUMMY'], 0),
                     fill: color,
                     fontSize: 14,
                     fontFamily: "monospace"
                  });
                  //
                  //
                  // Fetch Instruction
                  //
                  // TODO: indexing only works in direct lineage.  let fetchInstr = new fabric.Text('|fetch/instr_mem[$Pc]$instr'.asString(), {  // TODO: make indexing recursive.
                  //let fetchInstr = new fabric.Text('$raw'.asString("--"), {
                  //   top: 50,
                  //   left: 90,
                  //   fill: color,
                  //   fontSize: 14,
                  //   fontFamily: "monospace"
                  //});
                  //
                  // Instruction with values.
                  //
                  m4_ifelse_block(M4_ISA, ['MINI'], ['
                     let str = '$dest_char'.asString();
                     str += "(" + ('$dest_valid'.asBool(false) ? '$rslt'.asInt(NaN) : "---") + ")\n =";
                     str += '/src[1]$char'.asString();
                     str += "(" + ('/src[1]$valid'.asBool(false) ? '/src[1]$value'.asInt(NaN) : "--") + ")\n   ";
                     str += '/op$char'.asString("-");
                     str += '/src[2]$char'.asString();
                     str += "(" + ('/src[2]$valid'.asBool(false) ? '/src[2]$value'.asInt(NaN) : "--") + ")";
                  '], M4_ISA, ['RISCV'], ['
                     let regStr = (valid, regNum, regValue) => {
                        return valid ? `r${regNum} (${regValue})` : `rX`;
                     };
                     let srcStr = (src) => {
                        return '/src[src]$unconditioned_is_reg'.asBool(false)
                                   ? `\n      ${regStr(true, '/src[src]$unconditioned_reg'.asInt(NaN), '/src[src]$unconditioned_reg_value'.asInt(NaN))}`
                                   : "";
                     };
                     let str = `${regStr('$dest_reg_valid'.asBool(false), '$dest_reg'.asInt(NaN), '$rslt'.asInt(NaN))}\n` +
                               `  = ${'$mnemonic'.asString()}${srcStr(1)}${srcStr(2)}\n` +
                               `      i[${'$imm_value'.asInt(NaN)}]`;
                  '], M4_ISA, ['MIPSI'], ['
                     // TODO: Almost same as RISC-V. Avoid cut-n-paste.
                     let regStr = (valid, regNum, regValue) => {
                        return valid ? `r${regNum} (${regValue})` : `rX`;
                     };
                     let srcStr = (src) => {
                        return '/src[src]$unconditioned_is_reg'.asBool(false)
                                   ? `\n      ${regStr(true, '/src[src]$unconditioned_reg'.asInt(NaN), '/src[src]$unconditioned_reg_value'.asInt(NaN))}`
                                   : "";
                     };
                     let str = `${regStr('$dest_reg_valid'.asBool(false), '$dest_reg'.asInt(NaN), '$rslt'.asInt(NaN))}\n` +
                               `  = ${'$raw_opcode'.asInt()}${srcStr(1)}${srcStr(2)}\n` +
                               `      i[${'$imm_value'.asInt(NaN)}]`;
                  '], ['
                  '])
                  let instrWithValues = new fabric.Text(str, {
                     top: 70,
                     left: 90,
                     fill: color,
                     fontSize: 14,
                     fontFamily: "monospace"
                  });
                  return {objects: [pcPointer, instrWithValues]};
               }
            //
            // Register file
            //
            
            /regs[M4_REGS_RANGE]  // TODO: Fix [*]
               \viz_alpha
                   
                  initEach: function() {
                     let regname = new fabric.Text("Integer", {
                           top: -20,
                           left: m4_case(M4_ISA, ['MINI'], 192, ['RISCV'], 367, ['MIPSI'], 392, ['DUMMY'], 192),
                           fontSize: 14,
                           fontFamily: "monospace"
                        });
                     let reg = new fabric.Text("", {
                        top: 18 * this.getIndex(),
                        left: m4_case(M4_ISA, ['MINI'], 200, ['RISCV'], 375, ['MIPSI'], 400, ['DUMMY'], 200),
                        fontSize: 14,
                        fontFamily: "monospace"
                     });
                     return {objects: {regname: regname, reg: reg}};
                  },
                  renderEach: function() {
                     let mod = '/instr$reg_write'.asBool(false) && ('/instr$dest_reg'.asInt(-1) == this.getScope("regs").index);
                     let pending = '$pending'.asBool(false);
                     let reg = parseInt(this.getIndex());
                     let regIdent = ("M4_ISA" == "MINI") ? String.fromCharCode("a".charCodeAt(0) + reg) : reg.toString();
                     let oldValStr = mod ? `(${'$value'.asInt(NaN).toString()})` : "";
                     this.getInitObject("reg").setText(
                        regIdent + ": " +
                        '$value'.step(1).asInt(NaN).toString() + oldValStr);
                     this.getInitObject("reg").setFill(pending ? "red" : mod ? "blue" : "black");
                  }
            /regcsr
               \viz_alpha
                  initEach: function() {
                     let cycle = new fabric.Text("", {
                        top: 18 * 33,
                        left: m4_case(M4_ISA, ['MINI'], 200, ['RISCV'], 375, ['MIPSI'], 400, ['DUMMY'], 200),
                        fontSize: 14,
                        fontFamily: "monospace"
                     });
                     let cycleh = new fabric.Text("", {
                        top: 18 * 34,
                        left: m4_case(M4_ISA, ['MINI'], 200, ['RISCV'], 375, ['MIPSI'], 400, ['DUMMY'], 200),
                        fontSize: 14,
                        fontFamily: "monospace"
                     });
                     let time = new fabric.Text("", {
                        top: 18 * 35,
                        left: m4_case(M4_ISA, ['MINI'], 200, ['RISCV'], 375, ['MIPSI'], 400, ['DUMMY'], 200),
                        fontSize: 14,
                        fontFamily: "monospace"
                     });
                     let timeh = new fabric.Text("", {
                        top: 18 * 36,
                        left: m4_case(M4_ISA, ['MINI'], 200, ['RISCV'], 375, ['MIPSI'], 400, ['DUMMY'], 200),
                        fontSize: 14,
                        fontFamily: "monospace"
                     });
                     let instret = new fabric.Text("", {
                        top: 18 * 37,
                        left: m4_case(M4_ISA, ['MINI'], 200, ['RISCV'], 375, ['MIPSI'], 400, ['DUMMY'], 200),
                        fontSize: 14,
                        fontFamily: "monospace"
                     });
                     let instreth = new fabric.Text("", {
                        top: 18 * 38,
                        left: m4_case(M4_ISA, ['MINI'], 200, ['RISCV'], 375, ['MIPSI'], 400, ['DUMMY'], 200),
                        fontSize: 14,
                        fontFamily: "monospace"
                     });
                     return {objects: {cycle: cycle, cycleh: cycleh, time: time, timeh: timeh, instret: instret, instreth: instreth}};
                     },
                     renderEach: function() {
                        var cyclemod = '/instr$csr_cycle_hw_wr'.asBool(false);
                        var cyclehmod = '/instr$csr_cycleh_hw_wr'.asBool(false);
                        var timemod = '/instr$csr_time_hw_wr'.asBool(false);
                        var timehmod = '/instr$csr_timeh_hw_wr'.asBool(false);
                        var instretmod = '/instr$csr_instret_hw_wr'.asBool(false);
                        var instrethmod = '/instr$csr_instreth_hw_wr'.asBool(false);
                        var cyclename    = String("cycle");
                        var cyclehname   = String("cycleh");
                        var timename     = String("time");
                        var timehname    = String("timeh");
                        var instretname  = String("instret");
                        var instrethname = String("instreth");
                        var oldValcycle    = cyclemod    ? `(${'/instr$csr_cycle'.asInt(NaN).toString()})` : "";
                        var oldValcycleh   = cyclehmod   ? `(${'/instr$csr_cycleh'.asInt(NaN).toString()})` : "";
                        var oldValtime     = timemod     ? `(${'/instr$csr_time'.asInt(NaN).toString()})` : "";
                        var oldValtimeh    = timehmod    ? `(${'/instr$csr_timeh'.asInt(NaN).toString()})` : "";
                        var oldValinstret  = instretmod  ? `(${'/instr$csr_instret'.asInt(NaN).toString()})` : "";
                        var oldValinstreth = instrethmod ? `(${'/instr$csr_instreth'.asInt(NaN).toString()})` : "";
                        this.getInitObject("cycle").setText(
                           cyclename + ": " +
                           '/instr$csr_cycle'.step(1).asInt(NaN).toString() + oldValcycle);
                        this.getInitObject("cycleh").setText(
                           cyclehname + ": " +
                           '/instr$csr_cycleh'.step(1).asInt(NaN).toString() + oldValcycleh);
                        this.getInitObject("time").setText(
                           timename + ": " +
                           '/instr$csr_time'.step(1).asInt(NaN).toString() + oldValtime);
                        this.getInitObject("timeh").setText(
                           timehname + ": " +
                           '/instr$csr_timeh'.step(1).asInt(NaN).toString() + oldValtimeh);
                        this.getInitObject("instret").setText(
                           instretname + ": " +
                           '/instr$csr_instret'.step(1).asInt(NaN).toString() + oldValinstret);
                        this.getInitObject("instreth").setText(
                           instrethname + ": " +
                           '/instr$csr_instreth'.step(1).asInt(NaN).toString() + oldValinstreth);
                        this.getInitObject("cycle").setFill( cyclemod ? "blue" : "black");
                        this.getInitObject("cycleh").setFill( cyclehmod ? "blue" : "black");
                        this.getInitObject("time").setFill( timemod ? "blue" : "black");
                        this.getInitObject("timeh").setFill( timehmod ? "blue" : "black");
                        this.getInitObject("instret").setFill( instretmod ? "blue" : "black");
                        this.getInitObject("instreth").setFill( instrethmod ? "blue" : "black");
                     }
            m4_ifelse_block(M4_EXT_F, 1, ['
            /fpuregs[M4_FPUREGS_RANGE]  // TODO: Fix [*]
               \viz_alpha
                  initEach: function() {
                     let regname = new fabric.Text("Floating Point", {
                              top: -20,
                              left: m4_case(M4_ISA, ['MINI'], 175, ['RISCV'], 225, ['MIPSI'], 375, ['DUMMY'], 175),
                              fontSize: 14,
                              fontFamily: "monospace"
                           });
                     let fpureg = new fabric.Text("", {
                        top: 18 * this.getIndex(),
                        left: m4_case(M4_ISA, ['MINI'], 200, ['RISCV'], 250, ['MIPSI'], 400, ['DUMMY'], 200),
                        fontSize: 14,
                        fontFamily: "monospace"
                     });
                     return {objects: {regname :regname, fpureg: fpureg}};
                  },
                  renderEach: function() {
                     let mod = '/instr$fpu_reg_write'.asBool(false) && ('/instr$dest_fpu_reg'.asInt(-1) == this.getScope("fpuregs").index);
                     let pending = '$pending_fpu'.asBool(false);
                     let reg = parseInt(this.getIndex());
                     let regIdent = ("M4_ISA" == "MINI") ? String.fromCharCode("a".charCodeAt(0) + reg) : reg.toString();
                     let oldValStr = mod ? `(${'$fpuvalue'.asInt(NaN).toString(16)})` : "";
                     this.getInitObject("fpureg").setText(
                        regIdent + ": " +
                        '$fpuvalue'.step(1).asInt(NaN).toString(16) + oldValStr);
                     this.getInitObject("fpureg").setFill(pending ? "red" : mod ? "blue" : "black");
                  }
            /fpucsr
               \viz_alpha
                  initEach: function() {
                     let fcsr = new fabric.Text("", {
                        top: 18 * 33,
                        left: m4_case(M4_ISA, ['MINI'], 200, ['RISCV'], 250, ['MIPSI'], 400, ['DUMMY'], 200),
                        fontSize: 14,
                        fontFamily: "monospace"
                     });
                     let frm = new fabric.Text("", {
                        top: 18 * 34,
                        left: m4_case(M4_ISA, ['MINI'], 200, ['RISCV'], 250, ['MIPSI'], 400, ['DUMMY'], 200),
                        fontSize: 14,
                        fontFamily: "monospace"
                     });
                     let fflags = new fabric.Text("", {
                        top: 18 * 35,
                        left: m4_case(M4_ISA, ['MINI'], 200, ['RISCV'], 250, ['MIPSI'], 400, ['DUMMY'], 200),
                        fontSize: 14,
                        fontFamily: "monospace"
                     });
                     return {objects: {fcsr: fcsr, frm: frm, fflags: fflags}};
                  },
                  renderEach: function() {
                     var fcsrmod = '/instr$csr_fcsr_hw_wr'.asBool(false);
                     var frmmod = '/instr$csr_frm_hw_wr'.asBool(false);
                     var fflagsmod = '/instr$csr_fflags_hw_wr'.asBool(false);
                     var fcsrname = String("fcsr");
                     var frmname = String("frm");
                     var fflagsname = String("fflags");
                     var oldValfcsr = fcsrmod ? `(${'/instr$csr_fcsr'.asInt(NaN).toString(16)})` : "";
                     var oldValfrm =  frmmod ? `(${'/instr$csr_frm'.asInt(NaN).toString(16)})` : "";
                     var oldValfflags = fflagsmod ? `(${'/instr$csr_fflags'.asInt(NaN).toString(16)})` : "";
                     this.getInitObject("fcsr").setText(
                        fcsrname + ": " +
                        '/instr$csr_fcsr'.step(1).asInt(NaN).toString(16) + oldValfcsr);
                     this.getInitObject("frm").setText(
                        frmname + ": " +
                        '/instr$csr_frm'.step(1).asInt(NaN).toString(16) + oldValfrm);
                     this.getInitObject("fflags").setText(
                        fflagsname + ": " +
                        '/instr$csr_fflags'.step(1).asInt(NaN).toString(16) + oldValfflags);
                     this.getInitObject("fcsr").setFill( fcsrmod ? "blue" : "black");
                     this.getInitObject("frm").setFill( frmmod ? "blue" : "black");
                     this.getInitObject("fflags").setFill( fflagsmod ? "blue" : "black");
                  }
               '])

            /bank[M4_ADDRS_PER_WORD-1:0]
               /mem[M4_DATA_MEM_WORDS_RANGE]
                  \viz_alpha
                     initEach: function() {
                        let regname = new fabric.Text("Data Memory", {
                                 top: -20,
                                 left: m4_case(M4_ISA, ['MINI'], 255, ['RISCV'], 455, ['MIPSI'], 455, ['DUMMY'], 255) + this.getScope("bank").index * 30 + 30,
                                 fontSize: 14,
                                 fontFamily: "monospace"
                              });
                        let data = new fabric.Text("", {
                           top: 18 * this.getIndex(),
                           left: m4_case(M4_ISA, ['MINI'], 300, ['RISCV'], 500, ['MIPSI'], 500, ['DUMMY'], 300) + this.getScope("bank").index * 30 + 30,
                           fontSize: 14,
                           fontFamily: "monospace"
                        });
                        let index = (this.getScope("bank").index != 0) ? null :
                           new fabric.Text("", {
                              top: 18 * this.getIndex(),
                              left: m4_case(M4_ISA, ['MINI'], 300, ['RISCV'], 500, ['MIPSI'], 500, ['DUMMY'], 300) + this.getScope("bank").index * 30,
                              fontSize: 14,
                              fontFamily: "monospace"
                           });
                        return {objects: {regname: regname, data: data, index: index}};
                     },
                     renderEach: function() {
                        // BUG: It seems this is not getting called for every /bank[*].
                        console.log(`Render ${this.getScope("bank").index},${this.getScope("mem").index}`);
                        let mod = '/instr$st'.asBool(false) && ('/instr$addr'.asInt(-1) >> M4_SUB_WORD_BITS == this.getIndex());
                        let oldValStr = mod ? `(${'$Value'.asInt(NaN).toString()})` : "";
                        if (this.getInitObject("index")) {
                           let addrStr = parseInt(this.getIndex()).toString();
                           this.getInitObject("index").setText(addrStr + ":");
                        }
                        this.getInitObject("data").setText('$Value'.step(1).asInt(NaN).toString() + oldValStr);
                        this.getInitObject("data").setFill(mod ? "blue" : "black");
                     }




// Hookup Makerchip *passed/*failed signals to CPU $passed/$failed.
// Args:
//   /_hier: Scope of core(s), e.g. [''] or ['/core[*]'].
\TLV makerchip_pass_fail(/_hier)
   |done
      @0
         // Assert these to end simulation (before Makerchip cycle limit).
         *passed = & /top/_hier|fetch/instr>>M4_REG_WR_STAGE$passed;
         *failed = | /top/_hier|fetch/instr>>M4_REG_WR_STAGE$failed;


\TLV //disabled_main()
   /* verilator lint_on WIDTH */  // Let's be strict about bit widths.
   m4_ifelse_block(m4_eval(M4_CORE_CNT > 1), ['1'], ['
   // Multi-core
   /M4_CORE_HIER
      // TODO: Find a better place for this:
      // Block CPU |fetch pipeline if blocked.
      m4_define(['m4_cpu_blocked'], m4_cpu_blocked || /core|egress_in/instr<<M4_EXECUTE_STAGE$pkt_wr_blocked || /core|ingress_out<<M4_EXECUTE_STAGE$pktrd_blocked)
      m4+cpu(/core)
      //m4+dummy_noc(/core)
      m4+noc_cpu_buffers(/core, m4_eval(M4_MAX_PACKET_SIZE + 1))
      m4+noc_insertion_ring(/core, m4_eval(M4_MAX_PACKET_SIZE + 1))
      m4+warpv_makerchip_cnt10_tb()
   //m4+simple_ring(/core, |noc_in, @1, |noc_out, @1, /top<>0$reset, |rg, /flit)
   m4+makerchip_pass_fail(/core[*])
   /M4_CORE_HIER
      m4_ifelse_block(M4_VIZ, 1, ['
      m4+cpu_viz(/top)
      '])
   '], ['
   // Single Core.
   m4+warpv()
   m4+warpv_makerchip_cnt10_tb()
   m4+makerchip_pass_fail()
   m4_ifelse_block(M4_VIZ, 1, ['
   m4+cpu_viz(/top)
   '])
   '])

\SV
   endmodule
