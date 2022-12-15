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

   // For usage examples, visit warp-v.org.

\SV
   m4_include_lib(['https://raw.githubusercontent.com/stevehoover/tlv_lib/3543cfd9d7ef9ae3b1e5750614583959a672084d/fundamentals_lib.tlv'])
\m4
   m4_use(m5)
   //+m4_def(warpv_includes, ['['https://raw.githubusercontent.com/stevehoover/warp-v_includes/ca70d4e2538ae9fe792f9db1d3eafbac5d4a9a2c/']'])
   // TODO: TEMPORARY
   m4_def(warpv_includes, ['['./warp-v_includes_m5/']'])

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
   
   // Futures:
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
   //
   // TODO: Once Makerchip supports multifile editing, split this up.
   //       WARP should be a library, and each CPU uses this library to create a CPU.
   //       Stages should be defined using a generic mechanism (just defining m5_*_STAGE constants).
   //       Redirects should be defined using a generic mechanism to define each redirect, then
   //       instantiate the logic (including PC logic).
   //       IMem, RF should be m4+ macros.
   //       Should create generic instruction definition macros (like the RISC-V ones, but generic).


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
   // Note that WARP-V has a configurator at warp-v.org.
   
   // m5_default_def(..) allows external definition to take precedence.

   // Default parameters for formal verification continuous integration testing.
   // m5_FORMAL is only used within Makerchip in debug mode (for VIZ).
   //m5_default_def(FORMAL, 1)  // Uncomment to test formal verification in Makerchip.
   m4_ifelse(m5_FORMAL, 1, ['
      m5_default_def(
         ISA, RISCV,
         EXT_M, 1,
         VIZ, 1,
         STANDARD_CONFIG, 4-stage)
      m5_default_def(RISCV_FORMAL_ALTOPS, m5_EXT_M)
   '])

   // Machine:
   m5_default_def(
     ['# ISA (MINI, RISCV, MIPSI, POWER, DUMMY, etc.)'],
     ISA, RISCV,
     ['# A standard configuration that provides default values. (1-stage, 2-stage, 4-stage, 6-stage, none (and define individual parameters))'],
     STANDARD_CONFIG, 4-stage,
     ['# Number of words in the data memory.'],
     DMEM_SIZE, 32)
   
   // --------------
   // For multi-core
   // --------------
   m5_default_def(
     ['# Number of cores. Previously this was defined externally as m5_CORE_CNT (via m5_define_hier), so accept that too.'],
     NUM_CORES, m4_ifelse(m5_CORE_CNT, ['m5_CORE_CNT'], 1, m5_CORE_CNT))

   // Only relevant, and only defined, if m5_NUM_CORES > 1:

   m4_ifexpr(m5_NUM_CORES > 1, ['m5_default_def(
     ['# VCs (meaningful if > 1 core).'],
     NUM_VCS, 2,
     ['# Number of priority levels in the NoC (meaningful if > 1 core).'],
     NUM_PRIOS, 2,
     ['# Max number of payload flits in a packet.'],
     MAX_PACKET_SIZE, 3)'])
   
   m5_default_def(
     ['# Include visualization'],
     VIZ, 1,
     ['# For implementation (vs. simulation). (0/1)'],
     IMPL, 0,
     ['# Build for formal verification (0/1).'],
     FORMAL, 0,
     ['# riscv-formal uses alternate operations (add/sub and xor with a constant value)
         instead of actual mul/div, this is enabled automatically when formal is used. 
         This can be enabled for testing in Makerchip environment.'],
     RISCV_FORMAL_ALTOPS, 0)
   m5_default_def(
      ['# IMem style: SRAM, HARDCODED_ARRAY, STUBBED, EXTERN'],
      IMEM_STYLE, m4_ifelse(m5_IMPL, 0, HARDCODED_ARRAY, SRAM),
      ['# DMem style: SRAM, ARRAY, STUBBED'],
      DMEM_STYLE, m4_ifelse(m5_IMPL, 0, ARRAY, SRAM),
      ['# RF style: ARRAY, STUBBED'],
      RF_STYLE, ARRAY)

   m4_default_def(
     
     ['# A hook for a software-controlled reset. None by default.'],
     soft_reset, 1'b0,
     
     ['# A hook for CPU back-pressure in m5_REG_RD_STAGE.
         Various sources of back-pressure can add to this expression.
         Currently, this is envisioned for CSR writes that cannot be processed, such as
         NoC packet writes.'],
     cpu_blocked, 1'b0)

   // Define the implementation configuration, including pipeline depth and staging.
   // Define the following:
   //   Stages:
   //     m5_NEXT_PC_STAGE: Determining fetch PC for the NEXT instruction (not this one).
   //     m5_FETCH_STAGE: Instruction fetch.
   //     m5_DECODE_STAGE: Instruction decode.
   //     m5_BRANCH_PRED_STAGE: Branch predict (taken/not-taken). Currently, we mispredict to a known branch target,
   //                           so branch prediction is only relevant if target is computed before taken/not-taken is known.
   //                           For other ISAs prediction is forced to fallthrough, and there is no pred-taken redirect.
   //     m5_REG_RD_STAGE: Register file read.
   //     m5_EXECUTE_STAGE: Operation execution.
   //     m5_RESULT_STAGE: Select execution result.
   //     m5_BRANCH_TARGET_CALC_STAGE: Calculate branch target (generally EXECUTE, but some designs
   //                                  might produce offset from EXECUTE, then compute target).
   //     m5_MEM_WR_STAGE: Memory write.
   //     m5_REG_WR_STAGE: Register file write.
   //     Deltas (default to 0):
   //       m5_DELAY_BRANCH_TARGET_CALC: 1 to delay branch target calculation 1 stage from its nominal (ISA-specific) stage.
   //   Latencies (default to 0):
   //     m5_LD_RETURN_ALIGN: Alignment of load return pseudo-instruction into |mem pipeline.
   //                         If |mem stages reflect nominal alignment w/ load instruction, this is the
   //                         nominal load latency.
   //     Deltas (default to 0):
   //       M4 EXTRA_PRED_TAKEN_BUBBLE: 0 or 1. 0 aligns PC_MUX with BRANCH_TARGET_CALC.
   //       m5_EXTRA_REPLAY_BUBBLE:     0 or 1. 0 aligns PC_MUX with RD_REG for replays.
   //       m5_EXTRA_JUMP_BUBBLE:       0 or 1. 0 aligns PC_MUX with EXECUTE for jumps.
   //       m5_EXTRA_PRED_TAKEN_BUBBLE: 0 or 1. 0 aligns PC_MUX with EXECUTE for pred_taken.
   //       m5_EXTRA_INDIRECT_JUMP_BUBBLE: 0 or 1. 0 aligns PC_MUX with EXECUTE for indirect_jump.
   //       m5_EXTRA_BRANCH_BUBBLE:     0 or 1. 0 aligns PC_MUX with EXECUTE for branches.
   //       m5_EXTRA_TRAP_BUBBLE:       0 or 1. 0 aligns PC_MUX with EXECUTE for traps.
   //   m5_BRANCH_PRED: {fallthrough, two_bit, ...}
   m4_case(m5_STANDARD_CONFIG,
      ['1-stage'], ['
         // No pipeline
         m5_default_def(
            NEXT_PC_STAGE, 0,
            FETCH_STAGE, 0,
            DECODE_STAGE, 0,
            BRANCH_PRED_STAGE, 0,
            REG_RD_STAGE, 0,
            EXECUTE_STAGE, 0,
            RESULT_STAGE, 0,
            REG_WR_STAGE, 0,
            MEM_WR_STAGE, 0,
            LD_RETURN_ALIGN, 1)
         m5_default_def(BRANCH_PRED, fallthrough)
      '],
      ['2-stage'], ['
         // 2-stage pipeline.
         m5_default_def(
            NEXT_PC_STAGE, 0,
            FETCH_STAGE, 0,
            DECODE_STAGE, 0,
            BRANCH_PRED_STAGE, 0,
            REG_RD_STAGE, 0,
            EXECUTE_STAGE, 1,
            RESULT_STAGE, 1,
            REG_WR_STAGE, 1,
            MEM_WR_STAGE, 1,
            LD_RETURN_ALIGN, 2)
         m5_default_def(BRANCH_PRED, two_bit)
      '],
      ['4-stage'], ['
         // A reasonable 4-stage pipeline.
         m5_default_def(
            NEXT_PC_STAGE, 0,
            FETCH_STAGE, 0,
            DECODE_STAGE, 1,
            BRANCH_PRED_STAGE, 1,
            REG_RD_STAGE, 1,
            EXECUTE_STAGE, 2,
            RESULT_STAGE, 2,
            REG_WR_STAGE, 3,
            MEM_WR_STAGE, 3,
            EXTRA_REPLAY_BUBBLE, 1,
            LD_RETURN_ALIGN, 4)
         m5_default_def(BRANCH_PRED, two_bit)
      '],
      ['6-stage'], ['
         // Deep pipeline
         m5_default_def(
            NEXT_PC_STAGE, 1,
            FETCH_STAGE, 1,
            DECODE_STAGE, 3,
            BRANCH_PRED_STAGE, 4,
            REG_RD_STAGE, 4,
            EXECUTE_STAGE, 5,
            RESULT_STAGE, 5,
            REG_WR_STAGE, 6,
            MEM_WR_STAGE, 7,
            EXTRA_REPLAY_BUBBLE, 1,
            LD_RETURN_ALIGN, 7)
         m5_default_def(BRANCH_PRED, two_bit)
      ']
   )
   
   // Supply defaults for extra cycles.
   m5_default_def(
      DELAY_BRANCH_TARGET_CALC, 0,
      EXTRA_PRED_TAKEN_BUBBLE, 0,
      EXTRA_REPLAY_BUBBLE, 0,
      EXTRA_JUMP_BUBBLE, 0,
      EXTRA_BRANCH_BUBBLE, 0,
      EXTRA_INDIRECT_JUMP_BUBBLE, 0,
      EXTRA_NON_PIPELINED_BUBBLE, 1,
      EXTRA_TRAP_BUBBLE, 1)

   // --------------------------
   // ISA-Specific Configuration
   // --------------------------
   m4_case(m5_ISA, MINI, ['
         // Mini-CPU Configuration:
         // Force predictor to fallthrough, since we can't predict early enough to help.
         m5_def(BRANCH_PRED, fallthrough)
      '], RISCV, ['
         // RISC-V Configuration:

         // ISA options:

         // Currently supported uarch variants:
         //   RV32IM 2.0, w/ FA ISA extensions WIP.

         // Machine width
         m5_default_def(
           ['# Include visualization. (0/1)'],
           VIZ, 1,
           ['# Width of a "word". (32 for RV32X or 64 for RV64X)'],
           WORD_WIDTH, 32)
         m5_define_vector(WORD, m5_WORD_WIDTH)
         // ISA extensions,  1, or 0 (following M4 boolean convention).
         // TODO. Currently formal checks are broken when m5_EXT_F is set to 1.
         // TODO. Currently formal checks takes long time(~48 mins) when m5_EXT_B is set to 1.
         //       Hence, its disabled at present.
         m5_default_def(
            EXT_I, 1,
            EXT_E, 0,
            EXT_M, 0,
            EXT_A, 0,
            EXT_F, 0,
            EXT_D, 0,
            EXT_Q, 0,
            EXT_L, 0,
            EXT_C, 0,
            EXT_B, 0,
            EXT_J, 0,
            EXT_T, 0,
            EXT_P, 0,
            EXT_V, 0,
            EXT_N, 0)
         
         m5_default_def(['# For the time[h] CSR register, after this many cycles, time increments.'],
                   CYCLES_PER_TIME_UNIT, 1000000000)
      '], MIPSI, ['
      '], POWER, ['
      '], ['
         // Dummy "ISA".
         m5_def(DMEM_SIZE, 4)  // Override for narrow address.
         // Force predictor to fallthrough, since we can't predict early enough to help.
         m5_def(BRANCH_PRED, ['fallthrough'])
      ']
   )
   
   m5_default_def(VIZ, 0)   // Default to 0 unless already defaulted to 1, based on ISA.
   m5_default_def(
     ['# Which program to assemble. The default depends on the ISA extension(s) choice.'],
     PROG_NAME, m4_ifelse(m5_ISA, RISCV, m4_ifelse(m5_EXT_F, 1, fpu_test, m4_ifelse(m5_EXT_M, 1, divmul_test, m4_ifelse(m5_EXT_B, 1, bmi_test, cnt10))), cnt10))
   //m4_ifelse(m5_EXT_F, 1, fpu_test, cnt10)
   //m4_ifelse(m5_EXT_B, 1, bmi_test, cnt10)

   // =====Done Defining Configuration=====
   
   
   m5_define_hier(DATA_MEM_WORDS, m5_DMEM_SIZE)
   
   // For multi-core only:
   m4_ifexpr(m5_NUM_CORES > 1, ['
   
      // Define hierarchies based on parameters.
      m5_define_hier(CORE, m5_NUM_CORES)
      m5_define_hier(VC, m5_NUM_VCS)
      m5_define_hier(PRIO, m5_NUM_PRIOS)
      
      // RISC-V Only
      m4_ifelse(m5_ISA, ['RISCV'], [''], ['m4_errprint(['Multi-core supported for RISC-V only.']m4_new_line)'])
      
      // Headere flit fields. 
      m5_define_vector_with_fields(FLIT, 32, UNUSED, m4_eval(m5_CORE_INDEX_CNT * 2 + m5_VC_INDEX_CNT), VC, m4_eval(m5_CORE_INDEX_CNT * 2), SRC, m5_CORE_INDEX_CNT, DEST, 0)
   '])

   // Characterize ISA and apply configuration.
   
   // Characterize the ISA, including:
   // m5_NOMINAL_BRANCH_TARGET_CALC_STAGE: An expression that will evaluate to the earliest stage at which the branch target
   //                                      can be available.
   // m5_HAS_INDIRECT_JUMP: (0/1) Does this ISA have indirect jumps.
   // Defaults:
   m5_def(HAS_INDIRECT_JUMP, 0)
   m4_case(m5_ISA, ['MINI'], ['
         // Mini-CPU Characterization:
         m5_macro(NOMINAL_BRANCH_TARGET_CALC_STAGE, ['m5_EXECUTE_STAGE'])
      '], ['RISCV'], ['
         // RISC-V Characterization:
         m5_macro(NOMINAL_BRANCH_TARGET_CALC_STAGE, ['m5_DECODE_STAGE'])
         m5_def(HAS_INDIRECT_JUMP, 1)
      '], ['MIPSI'], ['
         // MIPS I Characterization:
         m5_macro(NOMINAL_BRANCH_TARGET_CALC_STAGE, ['m5_DECODE_STAGE'])
         m5_macro(HAS_INDIRECT_JUMP, 1)
      '], ['POWER'], ['
      '], ['DUMMY'], ['
         // DUMMY Characterization:
         m5_macro(NOMINAL_BRANCH_TARGET_CALC_STAGE, ['m5_DECODE_STAGE'])
      ']
   )
   
   // Calculated stages:
   m5_macro(BRANCH_TARGET_CALC_STAGE, m4_eval(m5_NOMINAL_BRANCH_TARGET_CALC_STAGE + m5_DELAY_BRANCH_TARGET_CALC))
   // Calculated alignments:
   m5_macro(REG_BYPASS_STAGES,  m4_eval(m5_REG_WR_STAGE - m5_REG_RD_STAGE))

   // Latencies/bubbles calculated from stage parameters and extra bubbles:
   // (zero bubbles minimum if triggered in next_pc; minimum bubbles = computed-stage - next_pc-stage)
   m5_def(PRED_TAKEN_BUBBLES, m4_eval(m5_BRANCH_PRED_STAGE - m5_NEXT_PC_STAGE + m5_EXTRA_PRED_TAKEN_BUBBLE),
          REPLAY_BUBBLES,     m4_eval(m5_REG_RD_STAGE - m5_NEXT_PC_STAGE + m5_EXTRA_REPLAY_BUBBLE),
          JUMP_BUBBLES,       m4_eval(m5_EXECUTE_STAGE - m5_NEXT_PC_STAGE + m5_EXTRA_JUMP_BUBBLE),
          BRANCH_BUBBLES,     m4_eval(m5_EXECUTE_STAGE - m5_NEXT_PC_STAGE + m5_EXTRA_BRANCH_BUBBLE),
          INDIRECT_JUMP_BUBBLES, m4_eval(m5_EXECUTE_STAGE - m5_NEXT_PC_STAGE + m5_EXTRA_INDIRECT_JUMP_BUBBLE),
          NON_PIPELINED_BUBBLES, m4_eval(m5_EXECUTE_STAGE - m5_NEXT_PC_STAGE + m5_EXTRA_NON_PIPELINED_BUBBLE),
          TRAP_BUBBLES,       m4_eval(m5_EXECUTE_STAGE - m5_NEXT_PC_STAGE + m5_EXTRA_TRAP_BUBBLE),
          ['# Bubbles between second issue of a long-latency instruction and
              the replay of the instruction it squashed (so always zero).'],
          SECOND_ISSUE_BUBBLES, 0)
   m5_def(['# Bubbles between a no-fetch cycle and the next cycles (so always zero).'],
          NO_FETCH_BUBBLES, 0)
   
   m4_def(stages_js, [''])
   // Define stages
   //   $1: VIZ left of stage in diagram
   //   $2: Stage name
   //   $3: Next $1
   m5_macro(stages, ['m4_ifelse(['$2'],,,['m4_append(stages_js, ['defineStage("$2", ']m5_$2_STAGE - m5_NEXT_PC_STAGE[', $1, $3); '])m5_stages(m4_shift(m4_shift($@)))'])'])
   m5_stages(
      8.5, NEXT_PC,
      13, FETCH,
      21, DECODE,
      33, BRANCH_PRED,
      41, REG_RD,
      58, EXECUTE,
      73.3, RESULT,
      77.2, REG_WR,
      93, MEM_WR,
      100)
   
   m5_macro(VIZ_STAGE, m5_MEM_WR_STAGE)

   
   
   // Retiming experiment.
   //
   // The idea here, is to move all logic into @0 and see how well synthesis results compare vs. the timed model with
   // retiming enabled. In theory, synthesis should be able to produce identical results.
   //
   // Unfortunately, this modeling does not work because of the redirection logic. When timed @0, the $GoodPathMask would
   // need to be redistributed, with each bit in a different stage to enable $commit to be computed in @0. So, to make
   // this work, each bit of $GoodPathMask would have to become a separate signal, and each signal assignment would need
   // its own @stage scope, affected by m5_RETIMING_EXPERIMENT. Since this is all generated by M4 ugliness, it was too
   // complicated to justify the experiment.
   //
   // For now, the RETIMING_EXPERIMENT sets $commit to 1'b1, and produces results that make synthesis look good.
   //
   // This option moves all logic into stage 0 (after determining relative timing interactions based on their original configuration).
   // The resulting SV is to be used for retiming experiments to see how well logic synthesis is able to retime the design.
   
   m4_ifelse(m5_RETIMING_EXPERIMENT, ['m5_RETIMING_EXPERIMENT'], [''], ['
      m5_def(NEXT_PC_STAGE, 0,
             FETCH_STAGE, 0,
             DECODE_STAGE, 0,
             BRANCH_PRED_STAGE, 0,
             BRANCH_TARGET_CALC_STAGE, 0,
             REG_RD_STAGE, 0,
             EXECUTE_STAGE, 0,
             RESULT_STAGE, 0,
             REG_WR_STAGE, 0,
             MEM_WR_STAGE, 0)
   '])
   
   
   
   // ========================
   // Check Legality of Config
   // ========================
   
   // (Not intended to be exhaustive.)

\m5
   // Check that expressions are ordered.
   fn(ordered, ..., {
      m5_ifeq(['$2'], [''], [''], {
         m5_if(m5_$1 > m5_$2, {
            m4_errprint(['$1 (']m5_$1[') is greater than $2 (']m5_$2[').']m4_nl())
         })
         ordered(m4_shift($@))
      })
   })
   // TODO:; It should be m5_NEXT_PC_STAGE-1, below.
   ordered(NEXT_PC_STAGE, FETCH_STAGE, DECODE_STAGE, BRANCH_PRED_STAGE, REG_RD_STAGE,
           EXECUTE_STAGE, RESULT_STAGE, REG_WR_STAGE, MEM_WR_STAGE)

   // Check reg bypass limit
   if(m5_REG_BYPASS_STAGES > 3, ['m4_errprint(['Too many stages of register bypass (']m5_REG_BYPASS_STAGES[').'])'])
\m4
   


   // ==================
   // Default Parameters
   // ==================
   // These may be overridden by specific ISA.

   m5_def(BIG_ENDIAN, 0)


   // =======================
   // ISA-specific Parameters
   // =======================

   // Macros for ISA-specific code.
   
   m4_define(m5_isa, m4_translit(m5_ISA, ['A-Z'], ['a-z']))   // A lower-case version of m5_ISA.
   
   // Instruction Memory macros are responsible for providing the instruction memory interface for fetch, as:
   // Inputs:
   //   |fetch@m5_FETCH$Pc[m4_eval(m5_PC_MIN + m4_width(m5_NUM_INSTRS-1) - 1):m5_PC_MIN]
   // Outputs:
   //   |fetch/instr?$fetch$raw[m5_INSTR_RANGE] (at or after @m5_FETCH_STAGE--at for retiming experiment; +1 for fast array read)
   m5_default_def(IMEM_MACRO_NAME, m5_isa['_imem'])
   
   // For each ISA, define:
   //   m5_define_vector(INSTR, XX)   // (or, m5_define_vector_with_fields(...)) Instruction vector.
   //   m5_define_vector(ADDR, XX)    // An address.
   //   m4_define(BITS_PER_ADDR, XX)  // Each memory address holds XX bits.
   //   m5_define_vector(WORD, XX)    // Width of general-purpose registers.
   //   m5_define_hier(REGS, XX)      // General-purpose register file.

   m4_case(m5_ISA,
      ['MINI'], ['
         m5_define_vector_with_fields(INSTR, 40, DEST_CHAR, 32, EQUALS_CHAR, 24, SRC1_CHAR, 16, OP_CHAR, 8, SRC2_CHAR, 0)
         m5_define_vector(ADDR, 12)
         m5_def(BITS_PER_ADDR, 12)  // Each memory address holds 12 bits.
         m5_define_vector(WORD, 12)
         m5_define_hier(REGS, 8)   // (Plural to avoid name conflict w/ SV "reg" keyword.)
      '],
      ['RISCV'], ['
         // Definitions matching "The RISC-V Instruction Set Manual Vol. I: User-Level ISA", Version 2.2.

         m5_define_vector(INSTR, 32)
         m5_define_vector(ADDR, 32)
         m5_def(BITS_PER_ADDR, 8)  // 8 for byte addressing.
         m5_define_vector(WORD, 32)
         m5_define_hier(REGS, m4_ifelse(m5_EXT_E, 1, 16, 32), 1)
         m5_define_hier(FPU_REGS, 32, 0)   // (though, the hierarchy is called /regs, not /fpu_regs)
      '],
      ['MIPSI'], ['
         m5_define_vector_with_fields(INSTR, 32, OPCODE, 26, RS, 21, RT, 16, RD, 11, SHAMT, 6, FUNCT, 0)
         m5_define_vector(ADDR, 32)
         m4_define(['m5_BITS_PER_ADDR'], 8)  // 8 for byte addressing.
         m5_define_vector(WORD, 32)
         m5_define_hier(REGS, 32, 1)
      '],
      ['POWER'], ['
      '],
      ['DUMMY'], ['
         m5_define_vector(INSTR, 2)
         m5_define_vector(ADDR, 2)
         m4_define(['m5_BITS_PER_ADDR'], 2)
         m5_define_vector(WORD, 2)
         m5_define_hier(REGS, 8)
      '])
   
   
   
   
   // Computed ISA uarch Parameters (based on ISA-specific parameters).

   m5_def(ADDRS_PER_WORD, m4_eval(m5_WORD_CNT / m5_BITS_PER_ADDR))
   m5_def(SUB_WORD_BITS, m4_width(m4_eval(m5_ADDRS_PER_WORD - 1)))
   m5_def(ADDRS_PER_INSTR, m4_eval(m5_INSTR_CNT / m5_BITS_PER_ADDR))
   m5_def(SUB_PC_BITS, m4_width(m4_eval(m5_ADDRS_PER_INSTR - 1)))
   m5_define_vector(PC, m5_ADDR_HIGH, m5_SUB_PC_BITS)
   m5_def(FULL_PC, ['{$Pc, m5_SUB_PC_BITS'b0}'])
   m5_define_hier(DATA_MEM_ADDRS, m4_eval(m5_DATA_MEM_WORDS_HIGH * m5_ADDRS_PER_WORD))  // Addressable data memory locations.
   m5_def(INJECT_RETURNING_LD, m4_eval(m5_LD_RETURN_ALIGN > 0))
   m5_def(PENDING_ENABLED, m5_INJECT_RETURNING_LD)
   
                                                    
   // ==============
   // VIZ Parameters                               
   // ==============
   
   
   m5_def(['# Amount to shift mem left (to make room for FP regs).'],
          VIZ_MEM_LEFT_ADJUST, m4_ifelse(m5_EXT_F, 1, 170, 0))


   
   // =========
   // Redirects
   // =========

   // These macros characterize redirects, generate logic, and generate visualization.
   
   // Redirect processing is performed based on the following:
   //   o Redirects are currently provided in a strict order that is not parameterized.
   //   o Redirects on earlier instructions mask those of later instructions (using $GoodPathMask and
   //     prioritization within the redirect cycle).
   //   o A redirect may mask later redirect triggers on the same instruction, depending whether
   //     the redirect is aborting or non-aborting.
   //      o Non-aborting redirects do not mask later redirect triggers, so later non-aborting
   //        redirects have priority.
   //      o Aborting redirects mask later redirect triggers, so earlier aborting
   //        redirects have priority
   
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
   m4_def(redirect_list, ['-100'])  // list fed to m4_ordered
   m4_def(redirect_squash_terms, ['['']'])  // & terms to apply to $GoodPathMask, each reflects the redirect shadow and abort of a trigger that becomes visible.
   m4_def(redirect_shadow_terms, ['['']'])  // & terms to apply to $RvfiGoodPathMask, each reflects the redirect shadow of a trigger that becomes visible (for formal verif only).
   m4_def(redirect_pc_terms, [''])      // ternary operator terms for redirecting PC (later-stage redirects must be first)
   m4_def(abort_terms, ['1'b0'])        // || terms for an instruction's abort condition
   m4_def(redirect_masking_triggers, ['1'b0']) // || terms combining earlier aborting triggers on the same instruction, using "$1" for alignment.
                                                         // Each trigger uses this term as it is built to mask its effect, so aborting triggers have the final say.
   m4_def(redirect_viz, [''])                 // JS code to provide parameters for visualization of the waterfall diagram.
   m4_def(redirect_cell_viz, [''])            // JS code to provide parameters for visualization of a cell of waterfall diagram.
   // Redirection conditions. These conditions must be defined from fewest bubble cycles to most.
   // See redirection logic for more detail.
   // Create several defines with items per redirect condition.
   m5_def(NUM_REDIRECT_CONDITIONS, 0)  // Incremented for each condition.
   m4_def(process_redirect_conditions,
          ['m4_ifelse(['$@'], ['['']'],
                      [''],
                      ['m4_process_redirect_condition($1, m5_NUM_REDIRECT_CONDITIONS)
                       m4_process_redirect_conditions(m4_shift($@))
                       ']
                     )
           m5_def(NUM_REDIRECT_CONDITIONS, m4_eval(m5_NUM_REDIRECT_CONDITIONS + 1))
           '])
   m5_def(MAX_REDIRECT_BUBBLES, m5_TRAP_BUBBLES)

   // Called by m4_process_redirect_conditions (plural) for each redirect condition from fewest bubbles to most to append
   // to various definitions, initialized above.
   // Args:
   //   $1: name of define of number of bubble cycles (The same name can be used multiple times, but once per aborting redirect.)
   //   $2: condition signal of triggering instr. This condition must be explicitly masked by earlier
   //       trigger conditions that take priority.
   //   $3: target PC signal of triggering instruction
   //   $4: 1 for an aborting redirect (0 otherwise)
   //   $5: VIZ text  for redirect bullet
   //   $6: VIZ color for redirect bullet
   //   $7: VIZ bullet left
   //   $8: VIZ bullet top
   //   $9: 1 for bad-path redirects (used by RVFI only)
   //   $10: (opt) ['wait'] to freeze fetch until subsequent redirect
   m4_def(process_redirect_condition,
          ['// expression in @m5_NEXT_PC_STAGE asserting for the redirect condition.
            // = instruction triggers this condition && it's on the current path && it's not masked by an earlier aborting redirect
            //   of this instruction.
            // Params: $@ (m4_redirect_masking_triggers contains param use)
            //0
            m4_push(redir_cond,
                       ['(>>']m5_$1_BUBBLES['$2 && !(']m4_echo(m4_redirect_masking_triggers)[') && $GoodPathMask'][m5_$1_BUBBLES][')'])
            m4_append(redirect_list, m5_$1_BUBBLES)
            m4_append(redirect_squash_terms,
                      [' & (']m4_redir_cond($@)[' ? {{']m4_eval(m5_MAX_REDIRECT_BUBBLES + 1 - m5_$1_BUBBLES - $4)['{1'b1}}, {']m4_eval(m5_$1_BUBBLES + $4)['{1'b0}}} : {']m4_eval(m5_MAX_REDIRECT_BUBBLES + 1)['{1'b1}})'])
            m4_append(redirect_shadow_terms,
                      [' & (']m4_redir_cond($@)[' ? {{']m4_eval(m5_MAX_REDIRECT_BUBBLES + 1 - m5_$1_BUBBLES - $9)['{1'b1}}, {']m4_eval(m5_$1_BUBBLES + $9)['{1'b0}}} : {']m4_eval(m5_MAX_REDIRECT_BUBBLES + 1)['{1'b1}})'])
            m4_prepend(redirect_pc_terms,
                       ['']m4_redir_cond($@)[' ? {>>']m5_$1_BUBBLES['$3, ']m4_ifelse($10, wait, 1'b1, 1'b0)['} : '])
            m4_ifelse(['$4'], 1,
               ['//m5_def(ABORT_BEFORE_$1, m4_abort_terms)   // The instruction was aborted prior to this abort condition.
                 m4_append(abort_terms,
                           [' || $2'])
                 m4_append(redirect_masking_triggers,
                           ['[' || >>m5_$']['1_BUBBLES$2']'])'])
            m4_append(redirect_viz,
                      ['ret.$2 = redirect_cond("$2", $5, $6, $7, $8); '])
            m4_append(redirect_cell_viz,
                      ['if (stage == ']m5_$1_BUBBLES[') {ret = ret.concat(render_redir("$2", '/instr$2', $5, $6, ']m4_ifelse(m5_EXTRA_$1_BUBBLE, 1, 1, 0)['))}; '])
            m4_pop(redir_cond)
          '])

   // Specify and process redirect conditions.
   // TODO: Found a bug...
   //       Priority is naturally given to later triggers.
   //       Must explicitly mask earlier higher-priority triggers.
   //    

   m4_process_redirect_conditions(
      ['SECOND_ISSUE, $second_issue, $Pc, 1, "2nd", "orange", 11.8, 26.2, 1'],
      ['NO_FETCH, $NoFetch, $Pc, 1, "...", "red", 11.8, 30, 1, wait'],
      m4_ifelse(m5_BRANCH_PRED, fallthrough, [''], ['['PRED_TAKEN, $pred_taken_branch, $branch_target, 0, "PT", "#0080ff", 37.4, 26.2, 0'],'])
      ['REPLAY, $replay, $Pc, 1, "Re", "#ff8000", 50, 29.1, 0'],
      ['JUMP, $jump, $jump_target, 0, "Jp", "purple", 61, 11, 0'],
      ['BRANCH, $mispred_branch, $branch_redir_pc, 0, "Br", "blue", 70, 20, 0'],
      m4_ifelse(m5_HAS_INDIRECT_JUMP, 1, ['['INDIRECT_JUMP, $indirect_jump, $indirect_jump_target, 0, "IJ", "purple", 68, 16, 0'],'], [''])
      ['NON_PIPELINED, $non_pipelined, $pc_inc, 0, "NP", "red", 75.6, 25, 1, wait'],
      ['TRAP, $aborting_trap, $trap_target, 1, "AT", "#ff0080", 75.6, 7, 0'],
      ['TRAP, $non_aborting_trap, $trap_target, 0, "T", "#ff0080", 75.6, 12, 0'])

   // Ensure proper order.
   // TODO: It would be great to auto-sort.
   // TODO: JUMP timing is nominally DECODE for most uarch's (immediate jumps), but this ordering forces
   //       redirect to be no earlier than REPLAY (REG_RD).
   m5_ordered(m4_redirect_list)

   
   // A macro for generating a when condition for instruction logic (just for a bit of power savings). (We probably won't
   // bother using it, but it's available in any case.)
   // m4_prev_instr_valid_through(redirect_bubbles) is deasserted by redirects up to the given number of cycles on the previous instruction.
   // Since we can be looking back an arbitrary number of cycles, we'll force invalid if $reset.
   m4_def(prev_instr_valid_through,
          ['(! $reset && >>m4_eval(1 - $1)$next_good_path_mask[$1])'])
   //same as <<m4_eval($1)$GoodPathMask[$1]), but accessible 1 cycle earlier and without $reset term.

   
   // ====
   // CSRs
   // ====
   
   // Macro to define a new CSR.
   // Eg: m4_define_csr(['mycsr'], ['12'b123'], ['12, NIBBLE_FIELD, 8, BYTE_FIELD'], ['12'b0'], ['12'hFFF'], 1)
   //  $1: CSR name (lowercase)
   //  $2: CSR index
   //  $3: CSR fields (as in m5_define_fields)
   //  $4: Reset value
   //  $5: Writable bits mask
   //  $6: 0, 1, RO indicating whether to allow side-effect writes.
   //      If 1, these signals in scope |fetch@m5_EXECUTE_STAGE must provide a write value:
   //         o $csr_<csr_name>_hw_wr: 1/0, 1 if a write is to occur (like hw_wr_mask == '0)
   //         o $csr_<csr_name>_hw_wr_value: the value to write
   //         o $csr_<csr_name>_hw_wr_mask: mask of bits to write
   //        Side-effect writes take place prior to corresponding CSR software reads and writes, though it should be
   //        rare that a bit can be written by both hardware and software.
   //      If RO, the CSR is read-only and code can be simpler. The CSR signal must be provided:
   //         o $csr_<csr_name>: The read-only CSR value (used in |fetch@m5_EXECUTE_STAGE).
   // Variables set by this macro:
   m4_def(['# List of CSRs.'],
          csrs, [''])
   m4_def(num_csrs, 0)
   // Arguments given to this macro for each CSR.
   // Initial value of CSR read result expression, initialized to ternary default case (X).
   m4_def(csrrx_rslt_expr, ['m5_WORD_CNT'bx'])
   // Initial value of OR expression for whether CSR index is valid.
   m4_def(valid_csr_expr, ['1'b0'])
   // VIZ initEach and renderEach JS code to define fabricjs objects for the CSRs.
   m4_def(csr_viz_init_each, [''])
   m4_def(csr_viz_render_each, [''])

   // m4_define_csr(name, index (12-bit SV-value), fields (as in m5_define_vector), reset_value (SV-value), writable_mask (SV-value), side-effect_writes (bool))
   // Adds a CSR.
   // Requires provision of: $csr_<name>_hw_[wr, wr_mask, wr_value].
   m4_def(
      define_csr,
      ['m5_define_vector_with_fields(['CSR_']m4_to_upper(['$1']), $3)
        m4_def(csrs,
               m4_dquote(m4_quote(m4_csrs['']m4_ifelse(m4_csrs, [''], [''], [','])$1)))
        m4_def(csr_$1_args, ['$@'])
        // 32'b0 = ['{{']m4_eval(32 - m4_echo(['m5_CSR_']m4_to_upper(['$1'])['_CNT'])){1'b0}}, ['$csr_']$1['}']
        m4_def(csrrx_rslt_expr, m4_dquote(['$is_csr_']$1[' ? {{']m4_eval(32 - m4_echo(['m5_CSR_']m4_to_upper(['$1'])['_CNT'])){1'b0}}, ['$csr_']$1['} : ']m4_csrrx_rslt_expr))
        m4_def(valid_csr_expr, m4_dquote(m4_valid_csr_expr[' || $is_csr_']$1))
        // VIZ
        m4_def(csr_viz_init_each, m4_csr_viz_init_each['csr_objs["$1_box"] = new fabric.Rect({top: 40 + 18 * ']m4_num_csrs[', left: 20, fill: "white", width: 175, height: 14, visible: true}); csr_objs["$1"] = new fabric.Text("", {top: 40 + 18 * ']m4_num_csrs[', left: 30, fontSize: 14, fontFamily: "monospace"}); '])
        m4_def(csr_viz_render_each, m4_csr_viz_render_each['let old_val_$1 = '/instr$csr_$1'.asInt(NaN).toString(); let val_$1 = '/instr$csr_$1'.step(1).asInt(NaN).toString(); let $1mod = m4_ifelse($6, 1, '/instr$csr_$1_hw_wr'.asBool(false), val_$1 === old_val_$1); let $1name = String("$1"); let oldVal$1    = $1mod    ? `(${old_val_$1})` : ""; this.getInitObject("$1").set({text: $1name + ": " + val_$1 + oldVal$1}); this.getInitObject("$1").set({fill: $1mod ? "blue" : "black"}); '])
        m4_def(num_csrs, m4_eval(m4_num_csrs + 1))
      ']
   )
   
   m4_case(m5_ISA, RISCV, ['
      m4_ifelse(m5_NO_COUNTER_CSRS, 1, [''], ['
         // Define Counter CSRs
         //            Name        Index       Fields                          Reset Value                    Writable Mask                       Side-Effect Writes
         m4_define_csr(cycle,      12'hC00,    ['32, CYCLE, 0'],               ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_define_csr(cycleh,     12'hC80,    ['32, CYCLEH, 0'],              ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_define_csr(time,       12'hC01,    ['32, CYCLE, 0'],               ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_define_csr(timeh,      12'hC81,    ['32, CYCLEH, 0'],              ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_define_csr(instret,    12'hC02,    ['32, INSTRET, 0'],             ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_define_csr(instreth,   12'hC82,    ['32, INSTRETH, 0'],            ['32'b0'],                     ['{32{1'b1}}'],                     1)
         m4_ifelse(m5_EXT_F, 1, ['
          m4_define_csr(fflags,    12'h001,    ['5, FFLAGS, 0'],               ['5'b0'],                      ['{5{1'b1}}'],                      1)
          m4_define_csr(frm,       12'h002,    ['3, FRM, 0'],                  ['3'b0'],                      ['{3{1'b1}}'],                      1)
          m4_define_csr(fcsr,      12'h003,    ['8, FCSR, 0'],                 ['8'b0'],                      ['{8{1'b1}}'],                      1)
         '])                                
      '])
      
      // For NoC support
      m4_ifexpr(m5_NUM_CORES > 1, ['
         // As defined in: https://docs.google.com/document/d/1cDUv8cuYF2kha8r6DSv-8pwszsrSP3vXsTiAugRkI1k/edit?usp=sharing
         // TODO: Find appropriate indices.
         //            Name        Index       Fields                              Reset Value                    Writable Mask                       Side-Effect Writes
         m4_define_csr(pktdest,    12'h800,    ['m5_CORE_INDEX_HIGH, DEST, 0'],    ['m5_CORE_INDEX_HIGH'b0'],     ['{m5_CORE_INDEX_HIGH{1'b1}}'],      0)
         m4_define_csr(pktwrvc,    12'h801,    ['m5_VC_INDEX_HIGH, VC, 0'],        ['m5_VC_INDEX_HIGH'b0'],       ['{m5_VC_INDEX_HIGH{1'b1}}'],        0)
         m4_define_csr(pktwr,      12'h802,    ['m5_WORD_HIGH, DATA, 0'],          ['m5_WORD_HIGH'b0'],           ['{m5_WORD_HIGH{1'b1}}'],            0)
         m4_define_csr(pkttail,    12'h803,    ['m5_WORD_HIGH, DATA, 0'],          ['m5_WORD_HIGH'b0'],           ['{m5_WORD_HIGH{1'b1}}'],            0)
         m4_define_csr(pktctrl,    12'h804,    ['1, BLOCK, 0'],                    ['1'b0'],                      ['1'b1'],                            0)
         m4_define_csr(pktrdvcs,   12'h808,    ['m5_VC_HIGH, VCS, 0'],             ['m5_VC_HIGH'b0'],             ['{m5_VC_HIGH{1'b1}}'],              0)
         m4_define_csr(pktavail,   12'h809,    ['m5_VC_HIGH, AVAIL_MASK, 0'],      ['m5_VC_HIGH'b0'],             ['{m5_VC_HIGH{1'b1}}'],              1)
         m4_define_csr(pktcomp,    12'h80a,    ['m5_VC_HIGH, AVAIL_MASK, 0'],      ['m5_VC_HIGH'b0'],             ['{m5_VC_HIGH{1'b1}}'],              1)
         m4_define_csr(pktrd,      12'h80b,    ['m5_WORD_HIGH, DATA, 0'],          ['m5_WORD_HIGH'b0'],           ['{m5_WORD_HIGH{1'b0}}'],            RO)
         m4_define_csr(core,       12'h80d,    ['m5_CORE_INDEX_HIGH, CORE, 0'],    ['m5_CORE_INDEX_HIGH'b0'],     ['{m5_CORE_INDEX_HIGH{1'b1}}'],      RO)
         m4_define_csr(pktinfo,    12'h80c,    ['m4_eval(m5_CORE_INDEX_HIGH + 3), SRC, 3, MID, 2, AVAIL, 1, COMP, 0'],
                                                                            ['m4_eval(m5_CORE_INDEX_HIGH + 3)'b100'], ['m4_eval(m5_CORE_INDEX_HIGH + 3)'b0'], 1)
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
   
   m4_case(m5_ISA, MINI, ['
      // An out-of-place correction for the fact that in Mini-CPU, instruction
      // addresses are to different memory than data, and the memories have different widths.
      m5_define_vector(PC, 10, 0)
      
   '], RISCV, ['
      // Included as tlv lib file.
   '], MIPSI, ['
   '], POWER, ['
   '], DUMMY, ['
   '])
   
   // Macro initialization.
   m5_def(NUM_INSTRS, 0)


   // Define m4+module_def macro to be used as a region line providing the module definition, either inside makerchip,
   // or outside for formal.
   m4_pragma_disable_quote_checks
   m4_def(module_def,
          ['m4_ifelse(m5_FORMAL, 0,
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
         output logic [31:0] rvfi_pc_wdata,
         output logic [31:0] rvfi_mem_addr,
         output logic [3: 0] rvfi_mem_rmask,
         output logic [3: 0] rvfi_mem_wmask,
         output logic [31: 0] rvfi_mem_rdata,
         output logic [31: 0] rvfi_mem_wdata);'])'])
   m4_pragma_enable_quote_checks

   // TODO: Remove after released to Makerchip/SaaS.
   m4_def(ifdef_tlv, ['m4_ifdef(['m4tlv_$1__body'], m4_shift($@))'])
\m5
   // Generate \SV content, including sv_include_url, include_url, and /* verilator lint... */
   // based on model config.
   fn(sv_content, {
      m4_ifelse(m5_ISA, RISCV, ['
         // Functions to append to sv_out. Verilator lint pragmas and SV includes.
         m4_var(sv_out, [''])
         m4_proc(verilator_lint, on_off, tag, ['
            // TODO: Use m4_output_sv_line in place of show...
            m4_append_var(sv_out, ['']m4_nl['   ']['m4_show(['m4_ifelse(m4_include_url_depth, ['0'], [''], ['['']m4_nl['   ']'])['/* verilator lint_']']']m4_on_off m4_tag['['[' */']'])'])
         '])
         m4_proc(sv_inc, file, ['
            m4_append_var(sv_out, m4_nl['   ']['m4_sv_include_url(m4_warpv_includes']m4_dquote(m4_file)[')'])
         '])
         m4_proc(tlv_inc, file, ['
            m4_append_var(sv_out, m4_nl['   ']['m4_include_url(m4_warpv_includes']m4_dquote(m4_file)[')'])
         '])
         
         // Heavy-handed lint_off's based on config.
         // TODO: Clean these up as best possible. Some are due to 3rd-party SV modules.
         m4_if(m5_EXT_B || m5_EXT_F, m4_verilator_lint(off, WIDTH))
         m4_if(m5_EXT_B, m4_verilator_lint(off, PINMISSING))
         m4_if(m5_EXT_B, m4_verilator_lint(off, SELRANGE))

         m4_if(m5_EXT_M, ['
            m4_ifelse(m5_RISCV_FORMAL_ALTOPS, 1, ['
             `define RISCV_FORMAL_ALTOPS         // enable ALTOPS if compiling for formal verification of M extension
            '])
            m4_verilator_lint(off, WIDTH)
            m4_verilator_lint(off, CASEINCOMPLETE)
            // TODO : Update links after merge to master!
            m4_sv_inc(['divmul/picorv32_pcpi_div.sv'])
            m4_sv_inc(['divmul/picorv32_pcpi_fast_mul.sv'])
            m4_verilator_lint(on, CASEINCOMPLETE)
            m4_verilator_lint(on, WIDTH)
         '])

         m4_if(m5_EXT_B, ['
            m4_verilator_lint(off, WIDTH)
            m4_verilator_lint(off, PINMISSING)
            m4_verilator_lint(off, CASEOVERLAP)
            m4_tlv_inc(['b-ext/top_bext_module.tlv'])
            m4_verilator_lint(on, WIDTH)
            m4_verilator_lint(on, CASEOVERLAP)
            m4_verilator_lint(on, PINMISSING)
         '])

         m4_if(m5_EXT_F, ['
            m4_verilator_lint(off, WIDTH)
            m4_verilator_lint(off, CASEINCOMPLETE)
            m4_tlv_inc(['fpu/topmodule.tlv'])
            m4_verilator_lint(on, CASEINCOMPLETE)
            m4_verilator_lint(on, WIDTH)
         '])
      '])
      m4_out(m4_sv_out)
   })
\SV
   m4_ifexpr(m5_NUM_CORES > 1, ['m4_include_lib(['https://raw.githubusercontent.com/stevehoover/tlv_flow_lib/5895e0625b0f8f17bb2e21a83de6fa1c9229a846/pipeflow_lib.tlv'])'])
   m4_ifelse(m5_ISA, RISCV, ['m4_include_lib(m4_warpv_includes['risc-v_defs.tlv'])'])
   m4_echo(m5_sv_content())


// A default testbench for all ISAs.
// Requires m4+makerchip_pass_fail(..).
\TLV default_makerchip_tb()
   |fetch
      /instr
         @m5_MEM_WR_STAGE
            $passed = ! $reset && ($Pc == (m5_NUM_INSTRS - 1)) && $good_path;
            $failed = *cyc_cnt > 200;



//============================//
//                            //
//         MINI-CPU           //
//                            //
//============================//
                         
\TLV mini_cnt10_prog()
   \SV_plus
      m5_def(NUM_INSTRS, 13)
      
      // The program in an instruction memory.
      logic [m5_INSTR_RANGE] instrs [0:m5_NUM_INSTRS-1];
      
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
   // Instantiate the program. (This approach is required for an m4-defined name.)
   m4_def(prog, ['mini_']_prog_name['_prog'])
   m4+m4_prog()
   |fetch
      /instr
         @m5_FETCH_STAGE
            ?$fetch
               $raw[m5_INSTR_RANGE] = *instrs\[$Pc[m4_eval(m5_PC_MIN + m4_width(m5_NUM_INSTRS-1) - 1):m5_PC_MIN]\];

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
      $char[7:0] = (#src == 1) ? /instr$raw[m5_INSTR_SRC1_CHAR_RANGE] : /instr$raw[m5_INSTR_SRC2_CHAR_RANGE];
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
   @m5_REG_RD_STAGE
      /src[*]
         $valid = /instr$valid_decode && ($is_reg || $is_imm);
         ?$valid
            $value[m5_WORD_RANGE] = $is_reg ? $reg_value :
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
         $st_value[m5_WORD_RANGE] = /src[1]$value;

      $valid_ld_st = $valid_ld || $valid_st;
      ?$valid_ld_st
         $addr[m5_ADDR_RANGE] = $ld ? (/src[1]$value + /src[2]$value) : /src[2]$value;
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
         $jump_target[m5_PC_RANGE] = $rslt[m5_PC_RANGE];
   @m5_BRANCH_TARGET_CALC_STAGE
      ?$branch
         $branch_target[m5_PC_RANGE] = $Pc + m5_PC_CNT'b1 + $rslt[m5_PC_RANGE];

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
 
   m4_asm(ORI, x6, x0, 0)        //     store_addr = 0
   m4_asm(ORI, x1, x0, 1)        //     cnt = 1
   m4_asm(ORI, x2, x0, 1010)     //     ten = 10
   m4_asm(ORI, x3, x0, 0)        //     out = 0
   m4_asm(ADD, x3, x1, x3)       //  -> out += cnt
   m4_asm(SW, x6, x3, 0)         //     store out at store_addr
   m4_asm(ADDI, x1, x1, 1)       //     cnt ++
   m4_asm(ADDI, x6, x6, 100)     //     store_addr++
   m4_asm(BLT, x1, x2, 1111111110000) //  ^- branch back if cnt < 10
   m4_asm(LW, x4, x6,   111111111100) //     load the final value into tmp
   m4_asm(BGE, x1, x2, 1111111010100) //     TERMINATE by branching to -1

\TLV riscv_divmul_test_prog()
   // /==========================\
   // | M-extension Test Program |
   // \==========================/
   //
   //3 MULs followed by 3 DIVs, check r11-r15 for correct results

   m4_asm(ORI, x8, x0, 1011)
   m4_asm(ORI, x9, x0, 1010)
   m4_asm(ORI, x10, x0, 10101010)
   m4_asm(MUL, x11, x8, r9)
   m4_asm(ORI, x6, x0, 0)
   m4_asm(SW, x6, x11, 0)
   m4_asm(MUL, x12, x9, r10)
   m4_asm(LW, x4, x6, 0)
   m4_asm(ADDI, x6, x6, 100)
   m4_asm(SW, x6, x12, 0)
   m4_asm(MUL, x13, x8, x10)
   m4_asm(DIV, x14, x11, x8)
   m4_asm(DIV, x15, x13, x10)
   m4_asm(LW, x5, x6, 0)
   m4_asm(ADDI, x4, x0, 101101)
   m4_asm(BGE, x8, x9, 111111111110)

\TLV riscv_fpu_test_prog()
   // /==========================\
   // | F-extension Test Program |
   // \==========================/
   //
   m4_asm(LUI, x1, 01110001010101100000)
   m4_asm(ADDI, x1, x1, 010001000001)
   m4_asm(LUI, x2, 01100101100101001111)
   m4_asm(ADDI, x2, x2, 010001000000)
   m4_asm(LUI, x3, 01001101110111110001)
   m4_asm(ADDI, x3, x3, 010000000000)
   m4_asm(FMVWX, x1, x1)
   m4_asm(FMVWX, x2, x2)
   m4_asm(FMVWX, x3, x3)
   m4_asm(FSW, x0, x1, 000001000000)
   m4_asm(FSW, x0, x2, 000001000100)
   m4_asm(FLW, x16, x0, 000001000000)
   m4_asm(FLW, x17, x0, 000001000100)
   m4_asm(FMADDS, x5, x1, x2, x3, 000)
   m4_asm(FMSUBS, x6, x1, x2, x3, 000)
   m4_asm(FNMSUBS, x7, x1, x2, x3, 000)
   m4_asm(FNMADDS, x8, x1, x2, x3, 000)
   m4_asm(CSRRS, x20, x0, 10)
   m4_asm(CSRRS, x20, x0, 11)
   m4_asm(FADDS, x9, x1, x2, 000)
   m4_asm(FSUBS, x10, x1, x2, 000)
   m4_asm(FMULS, x11, x1, x2, 000)
   m4_asm(FDIVS, x12, x1, x2, 000)
   m4_asm(CSRRS, x20, x0, 10)
   m4_asm(CSRRS, x20, x0, 11)
   m4_asm(FSQRTS, x13, x1, 000)
   m4_asm(CSRRS, x20, x0, 10)
   m4_asm(CSRRS, x20, x0, 11)
   m4_asm(FSGNJS, x14, x1, x2)
   m4_asm(FSGNJNS, x15, x1, x2)
   m4_asm(FSGNJXS, x16, x1, x2)
   m4_asm(FMINS, x17, x1, x2)
   m4_asm(FMAXS, x18, x1, x2)
   m4_asm(FCVTSW, x23, x2, 000)
   m4_asm(CSRRS, x20, x0, 10)
   m4_asm(CSRRS, x20, x0, 11)
   m4_asm(FCVTSWU, x24, x3, 000)
   m4_asm(FMVXW, x5, x11)
   m4_asm(CSRRS, x20, x0, 10)
   m4_asm(CSRRS, x20, x0, 11)
   m4_asm(FEQS, x19, x1, x2)
   m4_asm(FLTS, x20, x2, x1)
   m4_asm(FLES, x21, x1, x2)
   m4_asm(FCLASSS, x22, x1)
   m4_asm(FEQS, x19, x1, x2)
   m4_asm(CSRRS, x20, x0, 10)
   m4_asm(CSRRS, x20, x0, 11)
   m4_asm(FCVTWS, x12, x23, 000)
   m4_asm(FCVTWUS, x13, x24, 000)
   m4_asm(ORI, x0, x0, 0)
   
\TLV riscv_bmi_test_prog()
   // /==========================\
   // | B-extension Test Program |
   // \==========================/
   //
   m4_asm(LUI, x1, 01110001010101100000)
   m4_asm(ADDI, x1, x1, 010001000001)
   m4_asm(ADDI, x2, x2, 010001000010)
   m4_asm(ADDI, x3, x3, 010000000011)
   m4_asm(ANDN, x5, x1, x2)
   m4_asm(ORN, x6, x1, x2)
   m4_asm(XNOR, x7, x1, x2)
   m4_asm(SLO, x8, x1, x2)
   m4_asm(SRO, x20, x1, x2)
   m4_asm(ROL, x20, x1, x2)
   m4_asm(ROR, x9, x1, x2)
   m4_asm(SBCLR, x10, x1, x2)
   m4_asm(SBSET, x11, x1, x2)
   m4_asm(SBINV, x12, x1, x2)
   m4_asm(SBEXT, x20, x1, x2)
   m4_asm(GORC, x20, x1, x2)
   m4_asm(GREV, x13, x1, x2)
   m4_asm(SLOI, x8, x1, 111)
   m4_asm(SROI, x20, x1, 111)
   m4_asm(RORI, x9, x1, 111)
   m4_asm(SBCLRI, x10, x1, 111)
   m4_asm(SBSETI, x11, x1, 111)
   m4_asm(SBINVI, x12, x1, 111)
   m4_asm(SBEXTI, x20, x1, 111)
   m4_asm(GORCI, x20, x1, 111)
   m4_asm(GREVI, x13, x1, 111)
   m4_asm(CLMUL, x14, x1, x2)
   m4_asm(CLMULR, x15, x1, x2)
   m4_asm(CLZ, x19, x1)
   m4_asm(CTZ, x20, x1)
   m4_asm(PCNT, x21, x1)
   m4_asm(CRC32B, x22, x1)
   m4_asm(CRC32H, x23, x1)
   m4_asm(CRC32W, x24, x1)
   m4_asm(CRC32CB, x26, x1)
   m4_asm(CRC32CH, x27, x1)
   m4_asm(CRC32CW, x28, x1)
   m4_asm(MIN, x9, x1, x2)
   m4_asm(MAX, x10, x1, x2)
   m4_asm(MINU, x11, x1, x2)
   m4_asm(MAXU, x12, x1, x2)
   m4_asm(SHFL, x13, x1, x2)
   m4_asm(UNSHFL, x14, x1, x2)
   m4_asm(BDEP, x15, x1, x2)
   m4_asm(BEXT, x16, x1, x2)
   m4_asm(PACK, x17, x1, x2)
   m4_asm(PACKU, x18, x1, x2)
   m4_asm(PACKH, x19, x1, x2)
   m4_asm(BFP, x20, x1, x2)
   m4_asm(SHFLI, x21, x1, 11111)
   m4_asm(UNSHFLI, x22, x1, 11111)
   m4_asm(ORI, x0, x0, 0)
   
// Provides the instruction memory and fetch logic, producing.
//   $raw
//   *instrs[]
//   *instr_strs[]
\TLV riscv_imem(_prog_name)
   // Instantiate the program. (This approach is required for an m4-defined name.)
   m4_def(prog, ['riscv_']_prog_name['_prog'])
   m4+m4_prog()
   
   // ==============
   // IMem and Fetch
   // ==============
   
   /* DMEM_STYLE: m5_DMEM_STYLE, FORMAL: m5_FORMAL */
   m4+ifelse(m5_FORMAL, 1,
      \TLV
         // For formal
         // ----------
   
         // No instruction memory.
         |fetch
            /instr
               @m5_FETCH_STAGE
                  ?$fetch
                     `BOGUS_USE($$raw[m5_INSTR_RANGE])
      , m5_IMEM_STYLE, SRAM,
      \TLV
         |fetch
            /instr
               @m5_FETCH_STAGE
                  // For SRAM
                  // --------
                  m5_default_def(IMEM_SIZE, 1024)
                  m5_define_hier(IMEM_SRAM, m5_IMEM_SIZE)
                  \SV_plus
                    sram #(
                      .NB_COL(4),                           // Specify number of columns (number of bytes)
                      .COL_WIDTH(8),                        // Specify column width (byte width, typically 8 or 9)
                      .RAM_DEPTH(m5_IMEM_SRAM_CNT),         // Specify RAM depth (number of entries)
                      .RAM_PERFORMANCE("LOW_LATENCY"),      // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
                      .INIT_FILE("")                        // Specify name/location of RAM initialization file if using one (leave blank if not)
                    ) imem (
                      .addra($Pc[m5_IMEM_SRAM_INDEX_MAX+2:m5_IMEM_SRAM_INDEX_MIN+2]),  // Port A address bus, width determined from RAM_DEPTH
                      .addrb(m5_IMEM_SRAM_INDEX_CNT'b0),         // Port B address bus, width determined from RAM_DEPTH
                      .dina(32'b0),                         // Port A RAM input data, width determined from NB_COL*COL_WIDTH
                      .dinb(32'b0),                         // Port B RAM input data, width determined from NB_COL*COL_WIDTH
                      .clka(clk),                           // Clock
                      .wea(4'b0),                           // Port A write enable, width determined from NB_COL
                      .web(4'b0),                           // Port B write enable, width determined from NB_COL
                      .ena(1'b1),                           // Port A RAM Enable, for additional power savings, disable port when not in use
                      .enb(1'b0),                           // Port B RAM Enable, for additional power savings, disable port when not in use
                      .rsta(1'b0),                          // Port A output reset (does not affect memory contents)
                      .rstb(1'b0),                          // Port B output reset (does not affect memory contents)
                      .regcea(1'b1),                        // Port A output register enable
                      .regceb(1'b0),                        // Port B output register enable
                      .douta(>>1$$raw[m5_INSTR_RANGE]),        // Port A RAM output data, width determined from NB_COL*COL_WIDTH
                      .doutb()                              // Port B RAM output data, width determined from NB_COL*COL_WIDTH
                    );
      , m5_IMEM_STYLE, EXTERN,
      \TLV
         |fetch
            /instr
               @m5_FETCH_STAGE
                  ?$fetch
                     *imem_addr = $next_pc;
               @m4_eval(m5_FETCH_STAGE + 1)
                  ?$fetch
                     $raw[m5_INSTR_RANGE] = *imem_data;
      , m5_IMEM_STYLE, STUBBED,
      \TLV
         |fetch
            /instr
               @m5_DECODE_STAGE
                  $raw[m5_INSTR_RANGE] = {$Pc, $Pc[31:30]};
      ,
      \TLV
         // Default to HARDCODED_ARRAY
         // For simulation
         // --------------
         
         \SV_plus
            // The program in an instruction memory.
            logic [m5_INSTR_RANGE] instrs [0:m5_NUM_INSTRS-1];
            logic [40*8-1:0] instr_strs [0:m5_NUM_INSTRS];
            
            m4_forloop(['m4_instr_ind'], 0, m5_NUM_INSTRS, ['assign instrs[m4_instr_ind] = m4_echo(['m4_instr']m4_instr_ind); '])
            
            // String representations of the instructions for debug.
            m4_forloop(['m4_instr_ind'], 0, m5_NUM_INSTRS, ['assign instr_strs[m4_instr_ind] = "m4_echo(['m4_instr_str']m4_instr_ind)"; '])
            assign instr_strs[m5_NUM_INSTRS] = "END                                     ";
         
         |fetch
            m4+ifelse(m5_VIZ, 1,
               \TLV
                  /instr_mem[m4_eval(m5_NUM_INSTRS-1):0]
                     @m5_VIZ_STAGE
                        $instr[m5_INSTR_RANGE] = *instrs[instr_mem];
                        $instr_str[40*8-1:0] = *instr_strs[instr_mem];
               )
            /instr
               @m5_FETCH_STAGE
                  ?$fetch
                     $raw[m5_INSTR_RANGE] = *instrs\[$Pc[m4_eval(m5_PC_MIN + m4_width(m5_NUM_INSTRS-1) - 1):m5_PC_MIN]\];
      )

// Logic for a single CSR.
\TLV riscv_csr(csr_name, csr_index, fields, reset_value, writable_mask, side_effects)
   //--------------
   /['']/ CSR m4_to_upper(csr_name)
   //--------------
   @m5_DECODE_STAGE
      $is_csr_['']csr_name = $raw[31:20] == csr_index;
   @m5_EXECUTE_STAGE
      // CSR update. Counting on synthesis to optimize each bit, based on writable_mask.
      // Conditionally include code for h/w and s/w write based on side_effect param (0 - s/w, 1 - s/w + h/w, RO - neither).
      m5_def(THIS_CSR_RANGE, m4_echo(['m5_CSR_']m4_to_upper(csr_name)['_RANGE']))
      
      m4+ifelse(side_effects, 1,
         \TLV
            // hw_wr_mask conditioned by hw_wr.
            $csr_['']csr_name['']_hw_wr_en_mask[m5_THIS_CSR_RANGE] = {m4_echo(['m5_CSR_']m4_to_upper(csr_name)['_HIGH']){$csr_['']csr_name['']_hw_wr}} & $csr_['']csr_name['']_hw_wr_mask;
            // The CSR value, updated by side-effect writes.
            $upd_csr_['']csr_name[m5_THIS_CSR_RANGE] =
                 ($csr_['']csr_name['']_hw_wr_en_mask & $csr_['']csr_name['']_hw_wr_value) | (~ $csr_['']csr_name['']_hw_wr_en_mask & $csr_['']csr_name);
         , side_effects, 0,
         \TLV
            // The CSR value with no side-effect writes.
            $upd_csr_['']csr_name[m5_THIS_CSR_RANGE] = $csr_['']csr_name;
         )
      m4+ifelse(side_effects, RO,
         \TLV
         ,
         \TLV
            // Next value of the CSR.
            $csr_['']csr_name['']_masked_wr_value[m5_THIS_CSR_RANGE] =
                 $csr_wr_value[m5_THIS_CSR_RANGE] & writable_mask;
            <<1$csr_['']csr_name[m5_THIS_CSR_RANGE] =
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
         )

// Define all CSRs.
\TLV riscv_csrs(csrs)
   // TODO: This doesn't maintain alignment. Need an m4+foreach macro.
   m4_foreach(csr, csrs, ['
   m4+riscv_csr(m4_echo(['m4_csr_']csr['_args']))
   '])

\TLV riscv_csr_logic()
   m4+ifelse(m4_csrs, [''], [''],
      \TLV
         // CSR write value for CSR write instructions.
         $csr_wr_value[m5_WORD_RANGE] = $raw_funct3[2] ? {27'b0, $raw_rs1} : /src[1]$reg_value;
      )

   // Counter CSR
   //
   m4+ifelse(m5_NO_COUNTER_CSRS, 1,
      \TLV
      ,
      \TLV
         // Count within time unit. This is not reset on writes to time CSR, so time CSR is only accurate to time unit.
         $RemainingCyclesWithinTimeUnit[m4_width(m5_CYCLES_PER_TIME_UNIT)-1:0] <=
              ($reset || $time_unit_expires) ?
                     m4_width(m5_CYCLES_PER_TIME_UNIT)'d['']m4_eval(m5_CYCLES_PER_TIME_UNIT - 1) :
                     $RemainingCyclesWithinTimeUnit - m4_width(m5_CYCLES_PER_TIME_UNIT)'b1;
         $time_unit_expires = !( | $RemainingCyclesWithinTimeUnit);  // reaches zero

         $full_csr_cycle_hw_wr_value[63:0]   = {$csr_cycleh,   $csr_cycle  } + 64'b1;
         $full_csr_time_hw_wr_value[63:0]    = {$csr_timeh,    $csr_time   } + 64'b1;
         $full_csr_instret_hw_wr_value[63:0] = {$csr_instreth, $csr_instret} + 64'b1;
         m4+ifelse(m5_EXT_F, 1,
            \TLV
               // If the value of $raw_rm (or rm field in instruction encoding) is 3'b111(dynamic RoundingMode) or if $fpu_second_issue_div_sqrt
               // occurs then, take the previous "rm"(RoundingMode) stored in "frm" CSR or else take that from instruction encoding itself.
               // NOTE. In first issue of fpu_div_sqrt itself the vaild $raw_rm value get stored/latched in "frm" CSR,
               //       so to use that at time of second issue of fpu_div_sqrt. 
               $fpufcsr[7:0] = {(((/instr>>1$raw_rm[2:0] == 3'b111) || $fpu_second_issue_div_sqrt) ? >>1$csr_fcsr[7:5] : |fetch/instr$raw_rm[2:0] ) ,|fetch/instr/fpu1$exception_invaild_output, |fetch/instr/fpu1$exception_infinite_output, |fetch/instr/fpu1$exception_overflow_output, |fetch/instr/fpu1$exception_underflow_output, |fetch/instr/fpu1$exception_inexact_output};
            )
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
         m4+ifelse(m5_EXT_F, 1,
            \TLV
               $csr_fflags_hw_wr = (($commit && ($fpu_csr_fflags_type_instr || $fpu_fflags_type_instr))  || $fpu_second_issue_div_sqrt);
               $csr_fflags_hw_wr_mask[4:0] = {5{1'b1}};
               $csr_fflags_hw_wr_value[4:0] = {(($fpufcsr[7:5] == 3'b111) ? >>1$csr_fflags[4:0] : $fpufcsr[4:0])};

               $csr_frm_hw_wr = ($commit && $fpu_csr_fflags_type_instr);
               $csr_frm_hw_wr_mask[2:0] = {3{1'b1}};
               $csr_frm_hw_wr_value[2:0] = {(($fpufcsr[7:5] == 3'b111) ? >>1$csr_frm[2:0] : $fpufcsr[7:5])};

               $csr_fcsr_hw_wr = (($commit && ($fpu_csr_fflags_type_instr || $fpu_fflags_type_instr))  || $fpu_second_issue_div_sqrt);
               $csr_fcsr_hw_wr_mask[7:0] = {8{1'b1}};
               $csr_fcsr_hw_wr_value[7:0] = {($fpu_fflags_type_instr) ? {>>1$csr_fcsr[7:5], $fpufcsr[4:0]} : (($fpufcsr[7:5] == 3'b111) ? >>1$csr_fcsr : $fpufcsr)};
            )
      )
   
   // For multicore CSRs:
   m4+ifelse(m4_eval(m5_NUM_CORES > 1), 1,
      \TLV
         $csr_pktavail_hw_wr = 1'b0;
         $csr_pktavail_hw_wr_mask[m5_VC_RANGE]  = {m5_VC_HIGH{1'b1}};
         $csr_pktavail_hw_wr_value[m5_VC_RANGE] = {m5_VC_HIGH{1'b1}};
         $csr_pktcomp_hw_wr = 1'b0;
         $csr_pktcomp_hw_wr_mask[m5_VC_RANGE]   = {m5_VC_HIGH{1'b1}};
         $csr_pktcomp_hw_wr_value[m5_VC_RANGE]  = {m5_VC_HIGH{1'b1}};
         //$csr_pktrd_hw_wr = 1'b0;
         //$csr_pktrd_hw_wr_mask[m5_WORD_RANGE]   = {m5_WORD_HIGH{1'b1}};
         //$csr_pktrd_hw_wr_value[m5_WORD_RANGE]  = {m5_WORD_HIGH{1'b0}};
         $csr_pktinfo_hw_wr = 1'b0;
         $csr_pktinfo_hw_wr_mask[m5_CSR_PKTINFO_RANGE]  = {m5_CSR_PKTINFO_HIGH{1'b1}};
         $csr_pktinfo_hw_wr_value[m5_CSR_PKTINFO_RANGE] = {m5_CSR_PKTINFO_HIGH{1'b0}};
         $csr_core[m5_CORE_INDEX_RANGE] = #core;
      )

// These are expanded in a separate TLV  macro because multi-line expansion is a no-no for line tracking.
// This keeps the implications contained.
\m4
   m4_TLV_proc(riscv_decode_expr, ['
      m4_out(m4_echo(m4_decode_expr))
   '])

\TLV riscv_rslt_mux_expr()
   // in case of second issue, the results are pulled out of the /orig_inst or /load_inst scope. 
   // no alignment is needed as the rslt mux and the long latency results both appear in the same pipestage.

   // in the case of second isssue for multiplication with ALTOPS enabled (or running formal checks for M extension), 
   // the module gives out the result in two cycles but we explicitly flop the $mul_rslt 
   // (by alignment with 3+NON_PIPELINED_BUBBLES to augment the 5 cycle behavior of the mul operation

   $rslt[m5_WORD_RANGE] =
         $second_issue_ld ? /orig_load_inst$ld_rslt : m4_ifelse_block(m5_EXT_M, 1, ['
         ($second_issue_div_mul && |fetch/instr>>m5_NON_PIPELINED_BUBBLES$stall_cnt_upper_div) ? |fetch/instr$divblock_rslt : 
         ($second_issue_div_mul && |fetch/instr>>m5_NON_PIPELINED_BUBBLES$stall_cnt_upper_mul) ? |fetch/instr['']m4_ifelse(m5_RISCV_FORMAL_ALTOPS,1,>>m4_eval(3+m5_NON_PIPELINED_BUBBLES))$mulblock_rslt :
         ']) m4_ifelse_block(m5_EXT_F, 1, ['
         ($fpu_second_issue_div_sqrt && |fetch/instr>>m5_NON_PIPELINED_BUBBLES$stall_cnt_max_fpu) ? |fetch/instr/fpu1$output_div_sqrt11 : 
         ']) m4_ifelse_block(m5_EXT_B, 1, ['
         ($second_issue_clmul_crc && |fetch/instr>>m5_NON_PIPELINED_BUBBLES$stall_cnt_max_clmul) ? |fetch/instr$clmul_output : 
         ($second_issue_clmul_crc && |fetch/instr>>m5_NON_PIPELINED_BUBBLES$stall_cnt_max_crc) ? |fetch/instr$rvb_crc_output : 
         '])
         m5_WORD_CNT'b0['']m4_echo(m4_rslt_mux_expr);
   
\m4
   m4_TLV_proc(instr_types_decode, ..., ['
      m4_out(\SV_plus)
      m4_out(m4_types_decode(m4_instr_types_args))
   '])

\TLV riscv_decode()
   // TODO: ?$valid_<stage> conditioning should be replaced by use of m4_prev_instr_valid_through(..).
   ?$valid_decode
      // =================================

      // Extract fields of $raw (instruction) into $raw_<field>[x:0].
      m5_into_fields(INSTR, ['$raw'])
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
      m4+instr_types_decode()

      // Instruction decode.
      m4+riscv_decode_expr()
      
      m4+ifelse(m5_EXT_M, 1,
         \TLV
            // Instruction requires integer mul/div unit and is long-latency.
            $divtype_instr = ($is_div_instr || $is_divu_instr || $is_rem_instr || $is_remu_instr);
            $multype_instr = ($is_mul_instr || $is_mulh_instr || $is_mulhsu_instr || $is_mulhu_instr);
            $div_mul       = ($multype_instr || $divtype_instr);
         ,
         \TLV
            $div_mul = 1'b0;
            $multype_instr = 1'b0;
            `BOGUS_USE($multype_instr)
         )

      m4+ifelse(m5_EXT_F, 1,
         \TLV
            // Instruction requires floating point unit and is long-latency.
            // TODO. Current implementation decodes the floating type instructions seperatly.
            // Hence can have a macro or signal to differentiate the type of instruction related to a particular extension or 
            // could be better to use just $op5 decode for this.

            // Categorize FP instrs that read int regs.
            $fcvts_w_type_instr = $is_fcvtsw_instr ||
                                  $is_fcvtswu_instr;
            $fcvtw_s_type_instr = $is_fcvtws_instr ||
                                  $is_fcvtwus_instr;
            $fpu_div_sqrt_type_instr = $is_fdivs_instr || $is_fsqrts_instr;
            $fmvxw_type_instr = $is_fmvxw_instr;
            $fmvwx_type_instr = $is_fmvwx_instr;
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
                                         $fcvtw_s_type_instr ||
                                         $fcvts_w_type_instr;
            // These instructions do not modify FP CSR's "frm", but they do generate "fflags".
            $fpu_fflags_type_instr = $is_fmins_instr ||
                                     $is_fmaxs_instr ||
                                     $is_feqs_instr ||
                                     $is_flts_instr ||
                                     $is_fles_instr;
            // Generalized FP instrucions.                               
            $fpu_type_instr = $fpu_csr_fflags_type_instr ||
                              $fpu_fflags_type_instr ||
                              $fmvxw_type_instr ||
                              $fmvwx_type_instr ||
                              $is_flw_instr ||
                              $is_fsw_instr ||
                              $is_fsgnjs_instr ||
                              $is_fsgnjns_instr ||
                              $is_fsgnjxs_instr ||
                              $is_fclasss_instr;
            // FPU instrs with int dest reg.
            $fpu_instr_with_int_dest = $is_feqs_instr ||
                                       $is_flts_instr ||
                                       $is_fles_instr ||
                                       $is_fclasss_instr ||
                                       $fmvxw_type_instr ||
                                       $fcvtw_s_type_instr;
            // FPU instrs with all int srcs.
            $fpu_instr_with_int_src = $fcvts_w_type_instr ||
                                      $fmvwx_type_instr ||
                                      $is_flw_instr;
            $fpu_instr_with_int_src1 = $is_fsw_instr;
         )
      
      m4+ifelse(m5_EXT_B, 1,
         \TLV
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
         )

      $is_srli_srai_instr = $is_srli_instr || $is_srai_instr;
      // Some I-type instructions have a funct7 field rather than immediate bits, so these must factor into the illegal instruction expression explicitly.
      $illegal_itype_with_funct7 = ( $is_srli_srai_instr m4_ifelse(m5_WORD_CNT, 64, ['|| $is_srliw_sraiw_instr']) ) && | {$raw_funct7[6], $raw_funct7[4:0]};
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
         $is_reg =
             m4_ifelse(m5_EXT_F, 1, (! /instr$fpu_type_instr || /instr$fpu_instr_with_int_src || ((#src == 1) && /instr$fpu_instr_with_int_src1)) &&)
             (/instr$is_r_type || /instr$is_r4_type || (/instr$is_i_type && (#src == 1)) || /instr$is_r2_type || /instr$is_s_type || /instr$is_b_type);
         $reg[m5_REGS_INDEX_RANGE] = (#src == 1) ? /instr$raw_rs1[m5_REGS_INDEX_RANGE] : /instr$raw_rs2[m5_REGS_INDEX_RANGE];
         
   // Condition signals must not themselves be conditioned (currently).
   $dest_reg[m5_REGS_INDEX_RANGE] = m4_ifelse(m5_EXT_M, 1, ['$second_issue_div_mul ? |fetch/instr/hold_inst>>m5_NON_PIPELINED_BUBBLES$dest_reg :'])
                                    m4_ifelse(m5_EXT_B, 1, ['$second_issue_clmul_crc ? |fetch/instr/hold_inst>>m5_NON_PIPELINED_BUBBLES$dest_reg :'])
                                    $second_issue_ld ? |fetch/instr/orig_inst$dest_reg : $raw_rd[m5_REGS_INDEX_RANGE];
   $dest_reg_valid = m4_ifelse(m5_EXT_F, 1, ['((! $fpu_type_instr) || $fpu_instr_with_int_dest) &&']) (($valid_decode && ! $is_s_type && ! $is_b_type) || $second_issue) &&
                     | $dest_reg;   // r0 not valid.  TODO: Huh? What about FP? No formal failure?
   
   m4+ifelse(m5_EXT_F, 1,
      \TLV
         // Implementing a different encoding for floating point instructions.
         ?$valid_decode
            /fpu
               // Output signals. seperate FPU source
               /src[3:1]
                  // Reg valid for this fpu source, based on instruction type.
                  $is_reg = (/instr$fpu_type_instr && ! /instr$fpu_instr_with_int_src && ! ((#src == 1) && /instr$fpu_instr_with_int_src1)) &&
                            (((#src != 3) && /instr$is_r_type) ||
                             /instr$is_r4_type ||
                             ((#src != 3) && /instr$is_r2_type) ||
                             (/instr$is_i_type && (#src == 1) && (#src != 3)) ||
                             ((#src != 3) && /instr$is_s_type)
                            );
                  $reg[m5_FPU_REGS_INDEX_RANGE] = (#src == 1) ? /instr$raw_rs1 : (#src == 2) ? /instr$raw_rs2 : /instr$raw_rs3;
   
               $dest_reg[m5_FPU_REGS_INDEX_RANGE] = /instr$fpu_second_issue_div_sqrt ? /instr/hold_inst/fpu>>m5_NON_PIPELINED_BUBBLES$dest_reg :
                                                 /instr$second_issue_ld ? /instr/orig_inst/fpu$dest_reg : /instr$raw_rd;
               $dest_reg_valid = (/instr$fpu_type_instr && ! /instr$fpu_instr_with_int_dest) && ((/instr$valid_decode && ! /instr$is_s_type && ! /instr$is_b_type) || /instr$second_issue);
      )
   
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
   m4_ifelse(m5_EXT_M, 1, ['m4+m_extension()'])

   // if F_EXT is enabled, this handles the stalling logic
   m4_ifelse(m5_EXT_F, 1, ['m4+f_extension()'])

   // if B_EXT is enabled, this handles the stalling logic
   m4_ifelse(m5_EXT_B, 1, ['m4+b_extension()'])
   
   @m5_BRANCH_TARGET_CALC_STAGE
      ?$valid_decode_branch
         $branch_target[m5_PC_RANGE] = $Pc[m5_PC_RANGE] + $raw_b_imm[m5_PC_RANGE];
         $misaligned_pc = | $raw_b_imm[1:0];
      ?$jump  // (JAL, not JALR)
         $jump_target[m5_PC_RANGE] = $Pc[m5_PC_RANGE] + $raw_j_imm[m5_PC_RANGE];
         $misaligned_jump_target = $raw_j_imm[1];
   @_exe_stage
      // Execution.
      $valid_exe = $valid_decode; // Execute if we decoded.
      m4+ifelse(m5_EXT_M, 1,
         \TLV
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
            // m5_NON_PIPELINED_BUBBLES after this point (depending on pipeline depth)
            // retain till next M-type instruction, to be used again at second issue
         )
 
      m4+ifelse(m5_EXT_F, 1,
         \TLV
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
         )
      
      
      m4+ifelse(m5_EXT_B, 1,
         \TLV
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
            // %Warning-MULTIDRIVEN reported by Verilator for $raw because not all bits are pulled to this stage. Rather than lint_on, this will pull all bits.
            `BOGUS_USE($raw)
            /* verilator lint_on WIDTH */
            /* verilator lint_on CASEINCOMPLETE */
            /* verilator lint_on PINMISSING */
            /* verilator lint_on CASEOVERLAP */

            `BOGUS_USE($din_ready_rvb_bitcnt $din_ready_bext_dep $din_ready_rvb_crc $din_ready_clmul)
         )

      // hold_inst scope is not needed when long latency instructions are disabled
      m4_ifelse(m4_eval(m5_EXT_M || m5_EXT_F || m5_EXT_B), 1, ['
      // ORed with 1'b0 for maintaining correct behavior for all 3 combinations of F & M, only F and only M.
      // TODO: This becomes a one-liner once $ANY acts on subscope.
      /hold_inst
         $ANY = 1'b0 m4_ifelse(m5_EXT_M, 1, [' || (|fetch/instr$mulblk_valid || (|fetch/instr$div_stall && |fetch/instr$commit))']) m4_ifelse(m5_EXT_F, 1, [' || (|fetch/instr$fpu_div_sqrt_stall && |fetch/instr$commit)']) m4_ifelse(m5_EXT_B, 1, [' || ((|fetch/instr$clmul_stall || |fetch/instr$crc_stall) && |fetch/instr$commit)']) ? |fetch/instr$ANY : >>1$ANY;
         /src[2:1]
            $ANY = 1'b0 m4_ifelse(m5_EXT_M, 1, [' || (|fetch/instr$mulblk_valid || (|fetch/instr$div_stall && |fetch/instr$commit))']) m4_ifelse(m5_EXT_F, 1, [' || (|fetch/instr$fpu_div_sqrt_stall && |fetch/instr$commit)']) m4_ifelse(m5_EXT_B, 1, [' || ((|fetch/instr$clmul_stall || |fetch/instr$crc_stall) && |fetch/instr$commit)']) ? |fetch/instr/src$ANY : >>1$ANY;
         m4+ifelse(m5_EXT_F, 1,
            \TLV
               /fpu
                  $ANY = 1'b0 m4_ifelse(m5_EXT_M, 1, [' || (|fetch/instr$mulblk_valid || (|fetch/instr$div_stall && |fetch/instr$commit))']) || (|fetch/instr$fpu_div_sqrt_stall && |fetch/instr$commit) m4_ifelse(m5_EXT_B, 1, [' || ((|fetch/instr$clmul_stall || |fetch/instr$crc_stall) && |fetch/instr$commit)']) ? |fetch/instr/fpu$ANY : >>1$ANY;
                  ///src[2:1]
                  //   $ANY = 1'b0 m4_ifelse(m5_EXT_M, 1, [' || (|fetch/instr$mulblk_valid || (|fetch/instr$div_stall && |fetch/instr$commit))']) || (|fetch/instr$fpu_div_sqrt_stall && |fetch/instr$commit) m4_ifelse(m5_EXT_B, 1, [' || ((|fetch/instr$clmul_stall || |fetch/instr$crc_stall) && |fetch/instr$commit)']) ? |fetch/instr/fpu/src$ANY : >>1$ANY;
            )
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
              (({($is_blt_instr ^ /src[1]$reg_value[m5_WORD_MAX]), /src[1]$reg_value[m5_WORD_MAX-1:0]} <
                {($is_blt_instr ^ /src[2]$reg_value[m5_WORD_MAX]), /src[2]$reg_value[m5_WORD_MAX-1:0]}
               ) ^ ((/src[1]$reg_value[m5_WORD_MAX] != /src[2]$reg_value[m5_WORD_MAX]) & $is_bge_instr)
              )
             )
            );
      ?$indirect_jump  // (JALR)
         $indirect_jump_full_target[31:0] = /src[1]$reg_value + $raw_i_imm;
         $indirect_jump_target[m5_PC_RANGE] = $indirect_jump_full_target[m5_PC_RANGE];
         $misaligned_indirect_jump_target = $indirect_jump_full_target[1];
      ?$valid_exe
         // Compute each individual instruction result, combined per-instruction by a macro.
         // TODO: Could provide some macro magic to specify combined instructions w/ a single result and mux select.
         //       This would reduce code below and probably improve implementation.
         
         $lui_rslt[m5_WORD_RANGE]   = {$raw_u_imm[31:12], 12'b0};
         $auipc_rslt[m5_WORD_RANGE] = m5_FULL_PC + $raw_u_imm;
         $jal_rslt[m5_WORD_RANGE]   = m5_FULL_PC + 4;
         $jalr_rslt[m5_WORD_RANGE]  = m5_FULL_PC + 4;
         // Load instructions. If returning ld is enabled, load instructions write no meaningful result, so we use zeros.
         m4+ifelse(m5_INJECT_RETURNING_LD, 1,
            \TLV
               $lb_rslt[m5_WORD_RANGE]    = m5_WORD_CNT'b0;
               $lh_rslt[m5_WORD_RANGE]    = m5_WORD_CNT'b0;
               $lw_rslt[m5_WORD_RANGE]    = m5_WORD_CNT'b0;
               $lbu_rslt[m5_WORD_RANGE]   = m5_WORD_CNT'b0;
               $lhu_rslt[m5_WORD_RANGE]   = m5_WORD_CNT'b0;
               m4_ifelse_block(m5_EXT_F, 1, ['
               $flw_rslt[m5_WORD_RANGE] = 32'b0;
               '])
            ,
            \TLV
               $lb_rslt[m5_WORD_RANGE]    = /orig_load_inst$ld_rslt;
               $lh_rslt[m5_WORD_RANGE]    = /orig_load_inst$ld_rslt;
               $lw_rslt[m5_WORD_RANGE]    = /orig_load_inst$ld_rslt;
               $lbu_rslt[m5_WORD_RANGE]   = /orig_load_inst$ld_rslt;
               $lhu_rslt[m5_WORD_RANGE]   = /orig_load_inst$ld_rslt;
               m4_ifelse_block(m5_EXT_F, 1, ['
               $flw_rslt[m5_WORD_RANGE]   = /orig_load_inst$ld_rslt;
               '])
            )
         $addi_rslt[m5_WORD_RANGE]  = /src[1]$reg_value + $raw_i_imm;  // TODO: This has its own adder; could share w/ add/sub.
         $xori_rslt[m5_WORD_RANGE]  = /src[1]$reg_value ^ $raw_i_imm;
         $ori_rslt[m5_WORD_RANGE]   = /src[1]$reg_value | $raw_i_imm;
         $andi_rslt[m5_WORD_RANGE]  = /src[1]$reg_value & $raw_i_imm;
         $slli_rslt[m5_WORD_RANGE]  = /src[1]$reg_value << $raw_i_imm[5:0];
         $srli_intermediate_rslt[m5_WORD_RANGE] = /src[1]$reg_value >> $raw_i_imm[5:0];
         $srai_intermediate_rslt[m5_WORD_RANGE] = /src[1]$reg_value[m5_WORD_MAX] ? $srli_intermediate_rslt | ((m5_WORD_HIGH'b0 - 1) << (m5_WORD_HIGH - $raw_i_imm[5:0]) ): $srli_intermediate_rslt;
         $srl_rslt[m5_WORD_RANGE]   = /src[1]$reg_value >> /src[2]$reg_value[4:0];
         $sra_rslt[m5_WORD_RANGE]   = /src[1]$reg_value[m5_WORD_MAX] ? $srl_rslt | ((m5_WORD_HIGH'b0 - 1) << (m5_WORD_HIGH - /src[2]$reg_value[4:0]) ): $srl_rslt;
         $slti_rslt[m5_WORD_RANGE]  =  (/src[1]$reg_value[m5_WORD_MAX] == $raw_i_imm[m5_WORD_MAX]) ? $sltiu_rslt : {m5_WORD_MAX'b0,/src[1]$reg_value[m5_WORD_MAX]};
         $sltiu_rslt[m5_WORD_RANGE] = (/src[1]$reg_value < $raw_i_imm) ? 1 : 0;
         $srai_rslt[m5_WORD_RANGE]  = $srai_intermediate_rslt;
         $srli_rslt[m5_WORD_RANGE]  = $srli_intermediate_rslt;
         $add_sub_rslt[m5_WORD_RANGE] = ($raw_funct7[5] == 1) ?  /src[1]$reg_value - /src[2]$reg_value : /src[1]$reg_value + /src[2]$reg_value;
         $add_rslt[m5_WORD_RANGE]   = $add_sub_rslt;
         $sub_rslt[m5_WORD_RANGE]   = $add_sub_rslt;
         $sll_rslt[m5_WORD_RANGE]   = /src[1]$reg_value << /src[2]$reg_value[4:0];
         $slt_rslt[m5_WORD_RANGE]   = (/src[1]$reg_value[m5_WORD_MAX] == /src[2]$reg_value[m5_WORD_MAX]) ? $sltu_rslt : {m5_WORD_MAX'b0,/src[1]$reg_value[m5_WORD_MAX]};
         $sltu_rslt[m5_WORD_RANGE]  = (/src[1]$reg_value < /src[2]$reg_value) ? 1 : 0;
         $xor_rslt[m5_WORD_RANGE]   = /src[1]$reg_value ^ /src[2]$reg_value;
         $or_rslt[m5_WORD_RANGE]    = /src[1]$reg_value | /src[2]$reg_value;
         $and_rslt[m5_WORD_RANGE]   = /src[1]$reg_value & /src[2]$reg_value;
         // CSR read instructions have the same result expression. Counting on synthesis to optimize result mux.
         $csrrw_rslt[m5_WORD_RANGE]  = m4_csrrx_rslt_expr;
         $csrrs_rslt[m5_WORD_RANGE]  = $csrrw_rslt;
         $csrrc_rslt[m5_WORD_RANGE]  = $csrrw_rslt;
         $csrrwi_rslt[m5_WORD_RANGE] = $csrrw_rslt;
         $csrrsi_rslt[m5_WORD_RANGE] = $csrrw_rslt;
         $csrrci_rslt[m5_WORD_RANGE] = $csrrw_rslt;
         
         // "M" Extension.
         
         m4+ifelse(m5_EXT_M, 1,
            \TLV
               // for Verilog modules instantiation
               $clk = *clk;
               $resetn = !(*reset);

               $instr_type_mul[3:0]    = $reset ? '0 : $mulblk_valid ? {$is_mulhu_instr,$is_mulhsu_instr,$is_mulh_instr,$is_mul_instr} : $RETAIN;
               $mul_in1[m5_WORD_RANGE] = $reset ? '0 : $mulblk_valid ? /src[1]$reg_value : $RETAIN;
               $mul_in2[m5_WORD_RANGE] = $reset ? '0 : $mulblk_valid ? /src[2]$reg_value : $RETAIN;

               $instr_type_div[3:0]    = $reset ? '0 : $divblk_valid ? {$is_remu_instr,$is_rem_instr,$is_divu_instr,$is_div_instr} : $RETAIN;
               $div_in1[m5_WORD_RANGE] = $reset ? '0 : $divblk_valid ? /src[1]$reg_value : $RETAIN;
               $div_in2[m5_WORD_RANGE] = $reset ? '0 : $divblk_valid ? /src[2]$reg_value : $RETAIN;

               // result signals for div/mul can be pulled down to 0 here, as they are assigned only in the second issue

               $mul_rslt[m5_WORD_RANGE]      = m5_WORD_CNT'b0;
               $mulh_rslt[m5_WORD_RANGE]     = m5_WORD_CNT'b0;
               $mulhsu_rslt[m5_WORD_RANGE]   = m5_WORD_CNT'b0;
               $mulhu_rslt[m5_WORD_RANGE]    = m5_WORD_CNT'b0;
               $div_rslt[m5_WORD_RANGE]      = m5_WORD_CNT'b0;
               $divu_rslt[m5_WORD_RANGE]     = m5_WORD_CNT'b0;
               $rem_rslt[m5_WORD_RANGE]      = m5_WORD_CNT'b0;
               $remu_rslt[m5_WORD_RANGE]     = m5_WORD_CNT'b0;
               `BOGUS_USE ($wrm $wrd $readyd $readym $waitm $waitd)
            )
      
         // "F" Extension.
         
         // TODO: Move this under /fpu.
         m4+ifelse(m5_EXT_F, 1,
            \TLV
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
               $operand_a[31:0] = /fpu/src[1]$reg_value;
               $operand_b[31:0] = /fpu/src[2]$reg_value;
               $operand_c[31:0] = /fpu/src[3]$reg_value;
               // rounding mode as per the RISC-V specs (synchronizing with HardFloat module)
               $rounding_mode[2:0] = (|fetch/instr$raw_rm == 3'b000) ? 3'b000 :
                                     (|fetch/instr$raw_rm == 3'b001) ? 3'b010 :
                                     (|fetch/instr$raw_rm == 3'b010) ? 3'b011 :
                                     (|fetch/instr$raw_rm == 3'b011) ? 3'b100 :
                                     (|fetch/instr$raw_rm == 3'b100) ? 3'b001 :
                                     (|fetch/instr$raw_rm == 3'b111) ? $csr_fcsr[7:5] : 3'bxxx;
               $int_input[31:0] = /src[1]$reg_value;

               // Results
               $fmadds_rslt[m5_WORD_RANGE]  = /fpu1$output_result;
               $fmsubs_rslt[m5_WORD_RANGE]  = /fpu1$output_result;
               $fnmadds_rslt[m5_WORD_RANGE] = /fpu1$output_result;
               $fnmsubs_rslt[m5_WORD_RANGE] = /fpu1$output_result;
               $fadds_rslt[m5_WORD_RANGE]   = /fpu1$output_result;
               $fsubs_rslt[m5_WORD_RANGE]   = /fpu1$output_result;
               $fmuls_rslt[m5_WORD_RANGE]   = /fpu1$output_result;
               $fsgnjs_rslt[m5_WORD_RANGE]  = $fsgnjs_output;
               $fsgnjns_rslt[m5_WORD_RANGE] = $fsgnjns_output;
               $fsgnjxs_rslt[m5_WORD_RANGE] = $fsgnjxs_output;
               $fmins_rslt[m5_WORD_RANGE]   = /fpu1$output_result;
               $fmaxs_rslt[m5_WORD_RANGE]   = /fpu1$output_result;
               $fcvtws_rslt[m5_WORD_RANGE]  = /fpu1$int_output;
               $fcvtwus_rslt[m5_WORD_RANGE] = /fpu1$int_output;
               $fmvxw_rslt[m5_WORD_RANGE]   = /fpu/src[1]$reg_value;
               $feqs_rslt[m5_WORD_RANGE]    = {31'b0 , /fpu1$eq_compare};
               $flts_rslt[m5_WORD_RANGE]    = {31'b0 , /fpu1$lt_compare}; 
               $fles_rslt[m5_WORD_RANGE]    = {31'b0 , {/fpu1$eq_compare & /fpu1$lt_compare}};
               $fclasss_rslt[m5_WORD_RANGE] = {28'b0, /fpu1$output_class};
               $fcvtsw_rslt[m5_WORD_RANGE]  = /fpu1$output_result;
               $fcvtswu_rslt[m5_WORD_RANGE] = /fpu1$output_result;
               $fmvwx_rslt[m5_WORD_RANGE]   = /src[1]$reg_value;

               // Pulling Instructions from /orig_inst scope
               $fdivs_rslt[m5_WORD_RANGE]   = m5_WORD_CNT'b0;
               $fsqrts_rslt[m5_WORD_RANGE]  = m5_WORD_CNT'b0;
               `BOGUS_USE(/fpu1$in_ready /fpu1$sqrtresult /fpu1$unordered /fpu1$exception_invaild_output /fpu1$exception_infinite_output /fpu1$exception_overflow_output /fpu1$exception_underflow_output /fpu1$exception_inexact_output)
            )
         
         m4+ifelse(m5_EXT_B, 1,
            \TLV
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
               $andn_rslt[m5_WORD_RANGE]   = $andn_output;
               $orn_rslt[m5_WORD_RANGE]    = $orn_output;
               $xnor_rslt[m5_WORD_RANGE]   = $xnor_output;
               $slo_rslt[m5_WORD_RANGE]    = $slo_output;
               $sro_rslt[m5_WORD_RANGE]    = $sro_output;
               $rol_rslt[m5_WORD_RANGE]    = $rorl_final_output;
               $ror_rslt[m5_WORD_RANGE]    = $rorr_final_output;
               $sbclr_rslt[m5_WORD_RANGE]  = $sbclr_output;
               $sbset_rslt[m5_WORD_RANGE]  = $sbset_output;
               $sbinv_rslt[m5_WORD_RANGE]  = $sbinv_output;
               $sbext_rslt[m5_WORD_RANGE]  = $sbext_output;
               $gorc_rslt[m5_WORD_RANGE]   = $bext_dep_output;
               $grev_rslt[m5_WORD_RANGE]   = $grev_final_output;
               $sloi_rslt[m5_WORD_RANGE]   = $sloi_output;
               $sroi_rslt[m5_WORD_RANGE]   = $sroi_output;
               $rori_rslt[m5_WORD_RANGE]   = $rorr_final_output;
               $sbclri_rslt[m5_WORD_RANGE] = $sbclri_output;
               $sbseti_rslt[m5_WORD_RANGE] = $sbseti_output;
               $sbinvi_rslt[m5_WORD_RANGE] = $sbinvi_output;
               $sbexti_rslt[m5_WORD_RANGE] = $sbexti_output;
               $gorci_rslt[m5_WORD_RANGE]  = $bext_dep_output;
               $grevi_rslt[m5_WORD_RANGE]  = $grev_final_output;
               $clz_rslt[m5_WORD_RANGE]    = {26'b0, $clz_final_output};
               $ctz_rslt[m5_WORD_RANGE]    = {26'b0, $ctz_final_output};
               $pcnt_rslt[m5_WORD_RANGE]   = {26'b0, $popcnt_output};
               $sextb_rslt[m5_WORD_RANGE]   = $rvb_bitcnt_output;
               $sexth_rslt[m5_WORD_RANGE]   = $rvb_bitcnt_output;
               $min_rslt[m5_WORD_RANGE] = $min_output;
               $max_rslt[m5_WORD_RANGE] = $max_output;
               $minu_rslt[m5_WORD_RANGE] = $minu_output;
               $maxu_rslt[m5_WORD_RANGE] = $maxu_output;
               $shfl_rslt[m5_WORD_RANGE] = $bext_dep_output;
               $unshfl_rslt[m5_WORD_RANGE] = $bext_dep_output;
               $bdep_rslt[m5_WORD_RANGE] = $bext_dep_output;
               $bext_rslt[m5_WORD_RANGE] = $bext_dep_output;
               $pack_rslt[m5_WORD_RANGE] = $pack_output;
               $packu_rslt[m5_WORD_RANGE] = $packu_output;
               $packh_rslt[m5_WORD_RANGE] = $packh_output;
               $bfp_rslt[m5_WORD_RANGE] = $bfp_output;
               $shfli_rslt[m5_WORD_RANGE] = $bext_dep_output;
               $unshfli_rslt[m5_WORD_RANGE] = $bext_dep_output;

               $clmul_rslt[m5_WORD_RANGE]  = m5_WORD_CNT'b0;
               $clmulr_rslt[m5_WORD_RANGE] = m5_WORD_CNT'b0;
               $clmulh_rslt[m5_WORD_RANGE] = m5_WORD_CNT'b0;
               $crc32b_rslt[m5_WORD_RANGE] = m5_WORD_CNT'b0;
               $crc32h_rslt[m5_WORD_RANGE] = m5_WORD_CNT'b0;
               $crc32w_rslt[m5_WORD_RANGE] = m5_WORD_CNT'b0;
               $crc32cb_rslt[m5_WORD_RANGE] = m5_WORD_CNT'b0;
               $crc32ch_rslt[m5_WORD_RANGE] = m5_WORD_CNT'b0;
               $crc32cw_rslt[m5_WORD_RANGE] = m5_WORD_CNT'b0;

               $dout_ready_bext_dep = $dout_valid_bext_dep && |fetch/instr$commit;
               $dout_ready_clmul = $dout_valid_clmul && |fetch/instr$commit;
               $dout_ready_rvb_crc = $dout_valid_rvb_crc && |fetch/instr$commit;
               $dout_ready_rvb_bitcnt = $dout_valid_rvb_bitcnt && |fetch/instr$commit;
            )

   // CSR logic
   // ---------
   m4+riscv_csrs([''](m4_csrs)[''])
   @_exe_stage
      m4+riscv_csr_logic()
      
      // Memory inputs.
      ?$valid_exe
         $unnatural_addr_trap = ($ld_st_word && ($addr[1:0] != 2'b00)) || ($ld_st_half && $addr[0]);
      $ld_st_cond = $ld_st && $valid_exe;
      ?$ld_st_cond
         $addr[m5_ADDR_RANGE] = m4_ifelse(m5_EXT_F, 1, ['($is_fsw_instr ? /src[1]$reg_value : /src[1]$reg_value)'],['/src[1]$reg_value']) + ($ld ? $raw_i_imm : $raw_s_imm);
         
         // Hardware assumes natural alignment. Otherwise, trap, and handle in s/w (though no s/w provided).
      $st_cond = $st && $valid_exe;
      ?$st_cond
         // Provide a value to store, naturally-aligned to memory, that will work regardless of the lower $addr bits.
         $st_reg_value[m5_WORD_RANGE] = m4_ifelse(m5_EXT_F, 1, ['$is_fsw_instr ? /fpu/src[2]$reg_value :'])
                                                  /src[2]$reg_value;
         $st_value[m5_WORD_RANGE] =
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
               {$ld_rslt[m5_WORD_RANGE], $ld_mask[3:0]} =
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
      m5_def(NUM_INSTRS, 11)
      
      // The program in an instruction memory.
      logic [m5_INSTR_RANGE] instrs [0:m5_NUM_INSTRS-1];
      
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
   // Instantiate the program. (This approach is required for an m4-defined name.)
   m4_def(prog, ['mipsi_']_prog_name['_prog'])
   m4+m4_prog()
   |fetch
      /instr
         @m5_FETCH_STAGE
            ?$fetch
               $raw[m5_INSTR_RANGE] = *instrs\[$Pc[m4_eval(m5_PC_MIN + m4_width(m5_NUM_INSTRS-1) - 1):m5_PC_MIN]\];

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
      m4_into_fields(['m5_INSTR'], ['$raw'])
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
         $reg[m5_REGS_INDEX_RANGE] =
             (#src == 1) ? /instr$raw_rs :
                           /instr$raw_rt;
      $imm_value[m5_WORD_RANGE] = {{16{$raw_immediate[15] && ! $unsigned_imm}}, $raw_immediate[15:0]};
      
   // Condition signals must not themselves be conditioned (currently).
   $dest_reg[m5_REGS_INDEX_RANGE] = $second_issue ? /orig_inst$dest_reg : $link_reg ? 5'b11111 : $itype ? $raw_rt : $raw_rd;
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
   @m5_BRANCH_TARGET_CALC_STAGE
      // TODO: Branch delay slot not implemented.
      // (PC is an instruction address, not a byte address.)
      ?$valid_decode_branch
         $branch_target[m5_PC_RANGE] = $pc_inc + $imm_value[29:0];
      ?$decode_valid_jump  // (JAL, not JALR)
         $jump_target[m5_PC_RANGE] = {$Pc[m5_PC_MAX:28], $raw_address[25:0]};
   @_exe_stage
      // Execution.
      $valid_exe = $valid_decode; // Execute if we decoded.
      
      ?$valid_exe
         // Mux immediate values with register values. (Could be REG_RD or EXE stage.)
         // Mux register value and immediate to produce operand 2.
         $op2_value[m5_WORD_RANGE] = ($raw_opcode[5:3] == 3'b001) ? $imm_value : /src[2]$reg_value;
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
         $indirect_jump_target[m5_PC_RANGE] = /src[1]$reg_value[m5_PC_RANGE];
      ?$valid_exe
         // Compute each individual instruction result, combined per-instruction by a macro.
         
         // Load/Store
         // Load instructions. If returning ld is enabled, load instructions write no meaningful result, so we use zeros.
         $ld_rslt[m5_WORD_RANGE] = m4_ifelse(m5_INJECT_RETURNING_LD, 1, ['32'b0'], ['/orig_inst$ld_rslt']);
         
         $add_sub_rslt[m5_WORD_RANGE] = ($is_sub || $is_subu) ? /src[1]$reg_value - $op2_value : /src[1]$reg_value + $op2_value;
         $is_add_sub = $is_add || $is_sub || $is_addu || $is_subu || $is_addi || $is_addiu;
         $compare_rslt[m5_WORD_RANGE] = {31'b0, (/src[1]$reg_value < $op2_value) ^ /src[1]$reg_value[31] ^ $op2_value[31]};
         $is_compare = $is_slt || $is_sltu || $is_slti || $is_sltiu;
         $logical_rslt[m5_WORD_RANGE] =
                 ({32{$is_and || $is_andi}} & (/src[1]$reg_value & $op2_value)) |
                 ({32{$is_or  || $is_ori }} & (/src[1]$reg_value | $op2_value)) |
                 ({32{$is_xor || $is_xori}} & (/src[1]$reg_value ^ $op2_value)) |
                 ({32{$is_nor            }} & (/src[1]$reg_value | ~ /src[2]$reg_value));
         $is_logical = $is_and || $is_andi || $is_or || $is_ori || $is_xor || $is_xori || $is_nor;
         $shift_rslt[m5_WORD_RANGE] =
                 ({32{$is_sll || $is_sllv}} & (/src[1]$reg_value << $shift_amount)) |
                 ({32{$is_srl || $is_srlv}} & (/src[1]$reg_value >> $shift_amount)) |
                 ({32{$is_sra || $is_srav}} & (/src[1]$reg_value << $shift_amount));
         $is_shift = $is_sll || $is_srl || $is_sra || $is_sllv || $is_srlv || $is_srav;
         $lui_rslt[m5_WORD_RANGE] = {$raw_immediate, 16'b0}; 
         
   @_rslt_stage
      ?$valid_exe
         $rslt[m5_WORD_RANGE] =
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
         $addr[m5_ADDR_RANGE] = /src[1]$reg_value + $imm_value;
         
         // Hardware assumes natural alignment. Otherwise, trap, and handle in s/w (though no s/w provided).
      $st_cond = $st && $valid_exe;
      ?$st_cond
         // Provide a value to store, naturally-aligned to memory, that will work regardless of the lower $addr bits.
         $st_reg_value[m5_WORD_RANGE] = /src[2]$reg_value;
         $st_value[m5_WORD_RANGE] =
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
            $ld_rslt[m5_WORD_RANGE] =
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
      m5_def(NUM_INSTRS, 2)
      
      // The program in an instruction memory.
      logic [m5_INSTR_RANGE] instrs [0:m5_NUM_INSTRS-1];
      
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
   // Instantiate the program. (This approach is required for an m4-defined name.)
   m4_def(prog, ['power_']_prog_name['_prog'])
   m4+m4_prog()
   |fetch
      /instr
         @m5_FETCH_STAGE
            ?$fetch
               $raw[m5_INSTR_RANGE] = *instrs\[$Pc[m4_eval(m5_PC_MIN + m4_width(m5_NUM_INSTRS-1) - 1):m5_PC_MIN]\];

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
   @m5_REG_RD_STAGE
      /src[*]
         $valid = /instr$valid_decode && ($is_reg || $is_imm);
         ?$valid
            $value[m5_WORD_RANGE] = $is_reg ? $reg_value :
                                              $imm_value;
   // Note that some result muxing is performed in @_exe_stage, and the rest in @_rslt_stage.
   @_exe_stage
      ?$valid_st
         $st_value[m5_WORD_RANGE] = /src[1]$value;

      $valid_ld_st = $valid_ld || $valid_st;
      ?$valid_ld_st
         $addr[m5_ADDR_RANGE] = $ld ? (/src[1]$value + /src[2]$value) : /src[2]$value;
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
         $jump_target[m5_PC_RANGE] = $rslt[m5_PC_RANGE];
   // TODO: Depends on $rslt. Check timing.
   @m5_BRANCH_TARGET_CALC_STAGE
      ?$branch
         $branch_target[m5_PC_RANGE] = $Pc + m5_PC_CNT'b1 + $rslt[m5_PC_RANGE];


//============================//
//                            //
//        DUMMY-CPU           //
//                            //
//============================//

\TLV dummy_imem()
   // Dummy IMem contains 2 dummy instructions.
   |fetch
      /instr
         @m5_FETCH_STAGE
            ?$fetch
               $raw[m5_INSTR_RANGE] = $Pc[m5_PC_MIN:m5_PC_MIN] == 1'b0 ? 2'b01 : 2'b10;

\TLV dummy_gen()
   // No M4-generated code for dummy.

\TLV dummy_decode()
   /src[2:1]
      `BOGUS_USE(/instr$raw[0])
      $is_reg = 1'b0;
      $reg[m5_REGS_INDEX_RANGE] = 3'b1;
      $value[m5_WORD_RANGE] = 2'b1;
   $dest_reg_valid = 1'b1;
   $dest_reg[m5_REGS_INDEX_RANGE] = $second_issue ? /orig_inst$dest_reg : 3'b0;
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
   @m5_REG_RD_STAGE
      $exe_rslt[m5_WORD_RANGE] = 2'b1;
   // Note that some result muxing is performed in @_exe_stage, and the rest in @_rslt_stage.
   @_exe_stage
      $st_value[m5_WORD_RANGE] = /src[1]$reg_value;
      $addr[m5_ADDR_RANGE] = /src[2]$reg_value;
      $taken = $rslt != 2'b0;
      $st_mask[0:0] = 1'b1;
      $non_aborting_isa_trap = 1'b0;
      $aborting_isa_trap = 1'b0;
   @_rslt_stage
      $rslt[m5_WORD_RANGE] =
         $second_issue ? /orig_inst$ld_value :
         $st ? /src[1]$value :
         $exe_rslt;
         
      // Jump (Dest = "P") and Branch (Dest = "p") Targets.
      $jump_target[m5_PC_RANGE] = $rslt[m5_PC_RANGE];
   @m5_BRANCH_TARGET_CALC_STAGE
      $branch_target[m5_PC_RANGE] = $Pc + m5_PC_CNT'b1 + /instr$raw[m5_PC_CNT-1:0]; // $raw represents immediate field
         




//=========================//
//                         //
//   MEMORY COMPONENT(S)   //
//                         //
//=========================//

// A memory component provides a word-wide memory striped in m5_ADDRS_PER_WORD independent banks to provide
// address-granular write. The access protocol is asynchronous and out-of-order, accepting
// a read or write (load or store) each cycle, where stores are visible to loads on the following cycle.
// Relative to |fetch/instr:
// On $valid_st, stores the data $st_value at $addr, masked by $st_mask.
// On $spec_ld, loads the word at $addr (ignoring intra-word bits).
// The returned load result can be accessed from /_cpu|mem/data<<m5_ALIGNMENT_VALUE$ANY as $ld_value and $ld
// (along w/ everything else in the input instruction).

// A fake memory with fixed latency.
// The memory is placed in the fetch pipeline.
// TODO: (/_cpu, @_mem, @_align)
\TLV fixed_latency_fake_memory(/_cpu, m5_ALIGNMENT_VALUE)
   // This macro assumes little-endian.
   m4_ifelse(m5_BIG_ENDIAN, 0, [''], ['m4_errprint(['Error: fixed_latency_fake_memory macro only supports little-endian memory.'])'])
   |fetch
      /instr
         // ====
         // Load
         // ====
         @m5_MEM_WR_STAGE
            /* DMEM_STYLE: m5_DMEM_STYLE */
            m4+ifelse(m5_DMEM_STYLE, STUBBED,
               \TLV
                  $ld_data[m5_WORD_RANGE] = <<1$valid_st ? <<1$st_value ^ $addr : 32'b0;
                  `BOGUS_USE($st_mask)
               , m5_DMEM_STYLE, SRAM,
               \TLV
                  // For SRAM
                  // --------
                  \SV_plus
                    sram #(
                      .NB_COL(4),                           // Specify number of columns (number of bytes)
                      .COL_WIDTH(8),                        // Specify column width (byte width, typically 8 or 9)
                      .RAM_DEPTH(m5_DATA_MEM_WORDS_HIGH),   // Specify RAM depth (number of entries)
                      .RAM_PERFORMANCE("LOW_LATENCY"),      // Select "HIGH_PERFORMANCE" or "LOW_LATENCY" 
                      .INIT_FILE("")                        // Specify name/location of RAM initialization file if using one (leave blank if not)
                    ) dmem (
                      .addra($addr),                        // Port A address bus, width determined from RAM_DEPTH
                      .addrb($addr),                        // Port B address bus, width determined from RAM_DEPTH
                      .dina($st_value),                     // Port A RAM input data, width determined from NB_COL*COL_WIDTH
                      .dinb(32'b0),                         // Port B RAM input data, width determined from NB_COL*COL_WIDTH
                      .clka(clk),                           // Clock
                      .wea({4{$valid_st}} & $st_mask),      // Port A write enable, width determined from NB_COL
                      .web(4'b0),                           // Port B write enable, width determined from NB_COL
                      .ena($valid_st),                      // Port A RAM Enable, for additional power savings, disable port when not in use
                      .enb($spec_ld),                       // Port B RAM Enable, for additional power savings, disable port when not in use
                      .rsta(1'b0),                          // Port A output reset (does not affect memory contents)
                      .rstb(1'b0),                          // Port B output reset (does not affect memory contents)
                      .regcea(1'b0),                        // Port A output register enable
                      .regceb($spec_ld),                    // Port B output register enable
                      .douta(),                             // Port A RAM output data, width determined from NB_COL*COL_WIDTH
                      .doutb(>>1$$ld_data[m5_WORD_RANGE])   // Port B RAM output data, width determined from NB_COL*COL_WIDTH
                    );
               , m5_DMEM_STYLE, EXTERN,
               \TLV  
                  *dmem_addrb = $addr;
                  *dmem_enb   = !$valid_ld;  // Active low enable
                  *dmem_addra = $addr;
                  *dmem_dina  = $st_value;
                  *dmem_dinb  = 32'b0;
                  *dmem_wea   = {4{$valid_st}} & $st_mask;
                  *dmem_web   = 4'b0;
                  *dmem_wea0  = !(| *dmem_wea); // Active low write
                  *dmem_ena   = !$valid_st;  // Active low enable
                  >>1$ld_data[m5_WORD_RANGE]  = *dmem_doutb;
               ,
               \TLV
                  // Array. Required for VIZ.
                  /bank[m4_eval(m5_ADDRS_PER_WORD-1):0]
                     $ANY = /instr$ANY; // Find signal from outside of /bank.
                     /mem[m5_DATA_MEM_WORDS_RANGE]
                     ?$spec_ld
                        $ld_data[(m5_WORD_HIGH / m5_ADDRS_PER_WORD) - 1 : 0] = /mem[$addr[m5_DATA_MEM_WORDS_INDEX_MAX + m5_SUB_WORD_BITS : m5_SUB_WORD_BITS]]$Value;

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
                              /mem[$addr[m5_DATA_MEM_WORDS_INDEX_MAX + m5_SUB_WORD_BITS : m5_SUB_WORD_BITS]]<<0$$^Value[(m5_WORD_HIGH / m5_ADDRS_PER_WORD) - 1 : 0] <= $st_value[(#bank + 1) * (m5_WORD_HIGH / m5_ADDRS_PER_WORD) - 1: #bank * (m5_WORD_HIGH / m5_ADDRS_PER_WORD)];
                        end
                  // Combine $ld_data per bank, assuming little-endian.
                  //$ld_data[m5_WORD_RANGE] = /bank[*]$ld_data;
                  // Unfortunately formal verification tools can't handle multiple packed dimensions produced by the expression above, so we
                  // build the concatination.
                  $ld_data[m5_WORD_RANGE] = {m4_forloop(['m4_ind'], 0, m5_ADDRS_PER_WORD, ['m4_ifelse(m4_ind, 0, [''], [', '])/bank[m4_eval(m5_ADDRS_PER_WORD - m4_ind - 1)]$ld_data'])};
               )
   // Return loads in |mem pipeline. We just hook up the |mem pipeline to the |fetch pipeline w/ the
   // right alignment.
   |mem
      /data
         // This becomes a one-liner once $ANY acts on subscopes.
         @m4_eval(m4_strip_prefix(['@m5_MEM_WR_STAGE']) - m5_ALIGNMENT_VALUE)
            $ANY = /_cpu|fetch/instr>>m5_ALIGNMENT_VALUE$ANY;
            /src[2:1]
               $ANY = /_cpu|fetch/instr/src>>m5_ALIGNMENT_VALUE$ANY;
            m4+ifelse(m5_EXT_F, 1,
               \TLV
                  /fpu
                     $ANY = /_cpu|fetch/instr/fpu>>m5_ALIGNMENT_VALUE$ANY;
                     ///src[2:1]
                     //   $ANY = /_cpu|fetch/instr/fpu/src>>m5_ALIGNMENT_VALUE$ANY;
               )
         // For consistency with other memories, assign $ld_value in @m5_MEM_WR_STAGE+1. 
         @m4_eval(m4_strip_prefix(['@m5_MEM_WR_STAGE']) - m5_ALIGNMENT_VALUE + 1)
            $ld_value[m5_WORD_RANGE] = /_cpu|fetch/instr>>m5_ALIGNMENT_VALUE$ld_data;




//========================//
//                        //
//   Branch Predictors    //
//                        //
//========================//

// Branch predictor macros:
// Context: pipeline
// Inputs:
//   @m5_EXECUTE_STAGE
//      $reset
//      $branch: This instruction is a branch.
//      ?$branch
//         $taken: This branch is taken.
// Outputs:
//   @m5_BRANCH_PRED_STAGE
//      $pred_taken
\TLV branch_pred_fallthrough()
   @m5_BRANCH_PRED_STAGE
      $pred_taken = 1'b0;

\TLV branch_pred_two_bit()
   @m5_BRANCH_PRED_STAGE
      ?$branch
         $pred_taken = >>m4_stage_eval(@m5_EXECUTE_STAGE + 1 - @m5_BRANCH_PRED_STAGE)$BranchState[1];
   @m5_EXECUTE_STAGE
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

\TLV m_extension()

   // RISC-V M-Extension instructions in WARP-V are fixed latency
   // As of today, to handle those instructions, WARP-V pipeline is stalled for the given latency, and the
   // results are written back through a second issue at the end of stalling duration.
   // Verilog modules are inherited from PicoRV32, and are located in the ./muldiv directory.
   // Since the modules have a fixed latency, their valid signals are instantiated as valid decode for M-type
   // instructions is detected, and results are put in /orig_inst scope to be used in second issue.

   // This macro handles the stalling logic using a counter, and triggers second issue accordingly.

   // latency for division is different for ALTOPS case
   m4_ifelse(m5_RISCV_FORMAL_ALTOPS, 1, ['
        m5_def(DIV_LATENCY, 12)
   '],['
        m5_def(DIV_LATENCY, 37)
   '])
   m5_def(MUL_LATENCY, 5)       // latency for multiplication is 2 cycles in case of ALTOPS,
                                // but we flop it for 5 cycles (in rslt_mux) to augment the normal
                                // second issue behavior

   // Relative to typical 1-cycle latency instructions.

   @m5_NEXT_PC_STAGE
      $second_issue_div_mul = >>m5_NON_PIPELINED_BUBBLES$trigger_next_pc_div_mul_second_issue;
   @m5_EXECUTE_STAGE
      {$div_stall, $mul_stall, $stall_cnt[5:0]} =    $reset ? '0 :
                                                     $second_issue_div_mul ? '0 :
                                                     ($commit && $div_mul) ? {$divtype_instr, $multype_instr, 6'b1} :
                                                     >>1$div_stall ? {1'b1, 1'b0, >>1$stall_cnt + 6'b1} :
                                                     >>1$mul_stall ? {1'b0, 1'b1, >>1$stall_cnt + 6'b1} :
                                                     '0;
                                                     
      $stall_cnt_upper_mul = ($stall_cnt == m5_MUL_LATENCY);
      $stall_cnt_upper_div = ($stall_cnt == m5_DIV_LATENCY);
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
   
   m5_def(FPU_DIV_LATENCY, 26)  // Relative to typical 1-cycle latency instructions.
   @m5_NEXT_PC_STAGE
      $fpu_second_issue_div_sqrt = >>m5_NON_PIPELINED_BUBBLES$trigger_next_pc_fpu_div_sqrt_second_issue;
   @m5_EXECUTE_STAGE
      {$fpu_div_sqrt_stall, $fpu_stall_cnt[5:0]} =    $reset ? 7'b0 :
                                                   <<m4_eval(m5_EXECUTE_STAGE - m5_NEXT_PC_STAGE)$fpu_second_issue_div_sqrt ? 7'b0 :
                                                   ($commit && $fpu_div_sqrt_type_instr) ? {$fpu_div_sqrt_type_instr, 6'b1} :
                                                   >>1$fpu_div_sqrt_stall ? {1'b1, >>1$fpu_stall_cnt + 6'b1} :
                                                   7'b0;
      $stall_cnt_max_fpu = ($fpu_stall_cnt == m5_FPU_DIV_LATENCY);
      $trigger_next_pc_fpu_div_sqrt_second_issue = ($fpu_div_sqrt_stall && $stall_cnt_max_fpu) || (|fetch/instr/fpu1$outvalid);


//==================//
//      RISC-V      //
//  "B" Extension   // WIP. NOT FROZEN
//==================//

\TLV b_extension()

   // Few of RISC-V B-Extension instructions (CRC and CMUL) in WARP-V are of fixed latency.
   // At present we refered to the same way latency in M-extension is handled.
   // Verilog modules for those inst. are inherited from Clifford Wolf's draft implementation, located inside warp-v_includes in ./b-ext directory.
   // Although the latency of different variant of CRC instr's are different, we are using a common FIXED LATENCY
   // for those instr's.

   m5_def(CLMUL_LATENCY, 5)
   m5_def(CRC_LATENCY, 5)
   @m5_NEXT_PC_STAGE
      $second_issue_clmul_crc = >>m5_NON_PIPELINED_BUBBLES$trigger_next_pc_clmul_crc_second_issue;
   @m5_EXECUTE_STAGE
      {$clmul_stall, $crc_stall, $clmul_crc_stall_cnt[5:0]} =  $reset ? '0 :
                                         $second_issue_clmul_crc ? '0 :
                                         ($commit && $clmul_crc_type_instr) ? {$clmul_type_instr, $crc_type_instr, 6'b1} :
                                         >>1$clmul_stall ? {1'b1, 1'b0, >>1$clmul_crc_stall_cnt + 6'b1} :
                                         >>1$crc_stall ? {1'b0, 1'b1, >>1$clmul_crc_stall_cnt + 6'b1} :
                                         '0;
      
      $stall_cnt_max_clmul = ($clmul_crc_stall_cnt == m5_CLMUL_LATENCY);
      $stall_cnt_max_crc   = ($clmul_crc_stall_cnt == m5_CRC_LATENCY);
      $trigger_next_pc_clmul_crc_second_issue = ($clmul_stall && $stall_cnt_max_clmul) || ($crc_stall && $stall_cnt_max_crc);
      

//=========================//
//                         //
//        THE CPU          //
//       (All ISAs)        //
//                         //
//=========================//

\TLV cpu(/_cpu)
   // Generated logic
   // Instantiate the _gen macro for the right ISA. (This approach is required for an m4-defined name.)
   m4_def(gen, m5_isa['_gen'])
   m4+m4_gen()
   // Instruction memory and fetch of $raw.
   m4+m5_IMEM_MACRO_NAME(m5_PROG_NAME)


   // /=========\
   // | The CPU |
   // \=========/

   |fetch
      /instr
         
         
         // Provide a longer reset to cover the pipeline depth.
         @m4_stage_eval(@m5_NEXT_PC_STAGE<<1)
            $soft_reset = (m4_soft_reset) || *reset;
            $Cnt[7:0] <= $soft_reset   ? 8'b0 :       // reset
                         $Cnt == 8'hFF ? 8'hFF :      // max out to avoid wrapping
                                         $Cnt + 8'b1; // increment
            $reset = $soft_reset || $Cnt < m4_eval(m5_LD_RETURN_ALIGN + m5_MAX_REDIRECT_BUBBLES + 3);
         @m5_FETCH_STAGE
            $fetch = ! $reset && ! $NoFetch;
            // (m5_IMEM_MACRO_NAME instantiation produces ?$fetch$raw.)
         @m5_NEXT_PC_STAGE
            
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
            //                 $GoodPathMask for Redir'edX => {o,X,o,y,y,y,o,o} == {1,1,1,1,0,0,1,1}
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
            // instructions. A trigger in the 1st depicted stage, m5_NEXT_PC_STAGE, results in a zero-bubble redirect so it would be
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
            $next_good_path_mask[m5_MAX_REDIRECT_BUBBLES+1:0] =
               // Shift up and mask w/ redirect conditions.
               {$GoodPathMask[m5_MAX_REDIRECT_BUBBLES:0]
                // & terms for each condition (order doesn't matter since masks are the same within a cycle)
                m4_echo(m4_redirect_squash_terms),
                1'b1}; // Shift in 1'b1 (fetch-valid).
            
            $GoodPathMask[m5_MAX_REDIRECT_BUBBLES+1:0] <=
               <<1$reset ? m4_eval(m5_MAX_REDIRECT_BUBBLES + 2)'b0 :  // All bad-path (through self) on reset (next mask based on next reset).
               $next_good_path_mask;
            
            m4+ifelse(m5_FORMAL, 1,
               \TLV
                  // Formal verfication must consider trapping instructions. For this, we need to maintain $RvfiGoodPathMask, which is similar to
                  // $GoodPathMask, except that it does not mask out aborted instructions.
                  $next_rvfi_good_path_mask[m5_MAX_REDIRECT_BUBBLES+1:0] =
                     {$RvfiGoodPathMask[m5_MAX_REDIRECT_BUBBLES:0]
                      m4_echo(m4_redirect_shadow_terms),
                      1'b1};
                  $RvfiGoodPathMask[m5_MAX_REDIRECT_BUBBLES+1:0] <=
                     <<1$reset ? m4_eval(m5_MAX_REDIRECT_BUBBLES + 2)'b0 :
                     $next_rvfi_good_path_mask;
               )
            
            
            // A returning load clobbers the instruction.
            // (Could do this with lower latency. Right now it goes through memory pipeline $ANY, and
            //  it is non-speculative. Both could easily be fixed.)
            $second_issue_ld = /_cpu|mem/data>>m5_LD_RETURN_ALIGN$valid_ld && 1'b['']m5_INJECT_RETURNING_LD;
            $second_issue = ($second_issue_ld m4_ifelse(m5_EXT_M, 1, ['|| $second_issue_div_mul']) m4_ifelse(m5_EXT_F, 1, ['|| $fpu_second_issue_div_sqrt']) m4_ifelse(m5_EXT_B, 1, ['|| $second_issue_clmul_crc']));
            // Recirculate returning load or the div_mul_result from /orig_inst scope
            
            // This reduces significantly once $ANY acts on subscope.
            ?$second_issue_ld
               // This scope holds the original load for a returning load.
               /orig_load_inst
                  $ANY = /_cpu|mem/data>>m5_LD_RETURN_ALIGN$ANY;
                  /src[2:1]
                     $ANY = /_cpu|mem/data/src>>m5_LD_RETURN_ALIGN$ANY;
                  m4+ifelse(m5_EXT_F, 1,
                     \TLV
                        /fpu
                           $ANY = /_cpu|mem/data/fpu>>m5_LD_RETURN_ALIGN$ANY;
                           ///src[2:1]
                           //   $ANY = /_cpu|mem/data/fpu/src>>m5_LD_RETURN_ALIGN$ANY;
                     )
            ?$second_issue
               /orig_inst
                  // pull values from /orig_load_inst or /hold_inst depending on which second issue
                  $ANY = |fetch/instr$second_issue_ld ? |fetch/instr/orig_load_inst$ANY : m4_ifelse(m5_EXT_M, 1, ['|fetch/instr$second_issue_div_mul ? |fetch/instr/hold_inst>>m5_NON_PIPELINED_BUBBLES$ANY :']) m4_ifelse(m5_EXT_F, 1, ['|fetch/instr$fpu_second_issue_div_sqrt ? |fetch/instr/hold_inst>>m5_NON_PIPELINED_BUBBLES$ANY :']) m4_ifelse(m5_EXT_B, 1, ['|fetch/instr$second_issue_clmul_crc ? |fetch/instr/hold_inst>>m5_NON_PIPELINED_BUBBLES$ANY :']) |fetch/instr/orig_load_inst$ANY;
                  /src[2:1]
                     $ANY = |fetch/instr$second_issue_ld ? |fetch/instr/orig_load_inst/src$ANY : m4_ifelse(m5_EXT_M, 1, ['|fetch/instr$second_issue_div_mul ? |fetch/instr/hold_inst/src>>m5_NON_PIPELINED_BUBBLES$ANY :']) m4_ifelse(m5_EXT_F, 1, ['|fetch/instr$fpu_second_issue_div_sqrt ? |fetch/instr/hold_inst/src>>m5_NON_PIPELINED_BUBBLES$ANY :']) m4_ifelse(m5_EXT_B, 1, ['|fetch/instr$second_issue_clmul_crc ? |fetch/instr/hold_inst/src>>m5_NON_PIPELINED_BUBBLES$ANY :']) |fetch/instr/orig_load_inst/src$ANY;
                  m4+ifelse(m5_EXT_F, 1,
                     \TLV
                        /fpu
                           $ANY = |fetch/instr$second_issue_ld ? |fetch/instr/orig_load_inst/fpu$ANY : m4_ifelse(m5_EXT_M, 1, ['|fetch/instr$second_issue_div_mul ? |fetch/instr/hold_inst/fpu>>m5_NON_PIPELINED_BUBBLES$ANY :']) |fetch/instr$fpu_second_issue_div_sqrt ? |fetch/instr/hold_inst/fpu>>m5_NON_PIPELINED_BUBBLES$ANY : m4_ifelse(m5_EXT_B, 1, ['|fetch/instr$second_issue_clmul_crc ? |fetch/instr/hold_inst/fpu>>m5_NON_PIPELINED_BUBBLES$ANY :']) |fetch/instr/orig_load_inst/fpu$ANY;
                           ///src[3:1]
                           //   $ANY = |fetch/instr$second_issue_ld ? |fetch/instr/orig_load_inst/fpu/src$ANY : m4_ifelse(m5_EXT_M, 1, ['|fetch/instr$second_issue_div_mul ? |fetch/instr/hold_inst/fpu/src>>m5_NON_PIPELINED_BUBBLES$ANY :']) |fetch/instr$fpu_second_issue_div_sqrt ? |fetch/instr/hold_inst/fpu/src>>m5_NON_PIPELINED_BUBBLES$ANY : m4_ifelse(m5_EXT_B, 1, ['|fetch/instr$second_issue_clmul_crc ? |fetch/instr/hold_inst/fpu/src>>m5_NON_PIPELINED_BUBBLES$ANY :']) |fetch/instr/orig_load_inst/fpu/src$ANY;
                     )
            // Next PC
            $pc_inc[m5_PC_RANGE] = $Pc + m5_PC_CNT'b1;
            // Current parsing does not allow concatenated state on left-hand-side, so, first, a non-state expression.
            {$next_pc[m5_PC_RANGE], $next_no_fetch} =
               $reset ? {m5_PC_CNT'b0, 1'b0} :
               // ? : terms for each condition (order does matter)
               m4_redirect_pc_terms
                          ({$pc_inc, 1'b0});
            // Then as state.
            $Pc[m5_PC_RANGE] <= $next_pc;
            $NoFetch <= $next_no_fetch;
         
         @m5_DECODE_STAGE

            // ======
            // DECODE
            // ======

            // Decode of the fetched instruction
            $valid_decode = $fetch;  // Always decode if we fetch.
            $valid_decode_branch = $valid_decode && $branch;
            // A load that will return later.
            //$split_ld = $spec_ld && 1'b['']m5_INJECT_RETURNING_LD;
            // Instantiate the program. (This approach is required for an m4-defined name.)
            m4_def(decode_macro_name, m5_isa['_decode'])
            m4+m4_decode_macro_name()
         // Instantiate the program. (This approach is required for an m4-defined name.)
         m4_def(branch_pred_macro_name, ['branch_pred_']m5_BRANCH_PRED)
         m4+m4_branch_pred_macro_name()
         
         @m5_REG_RD_STAGE
            // Pending value to write to dest reg. Loads (not replaced by returning ld) write pending.
            $reg_wr_pending = $ld && ! $second_issue && 1'b['']m5_INJECT_RETURNING_LD;
            `BOGUS_USE($reg_wr_pending)  // Not used if no bypass and no pending.
            
            // ======
            // Reg Rd
            // ======
            
            // Obtain source register values and pending bit for source registers.
            m4+operands( , /src, 2:1)
            /src[*]
               $dummy = 1'b0;  // Dummy signal to pull through $ANY expressions when not building verification harness (since SandPiper currently complains about empty $ANY).
            
            m4+ifelse(m5_EXT_F, 1,
               \TLV
                  //
                  // ======
                  // Reg Rd for Floating Point Unit
                  // ======
                  //
                  /fpu
                     m4+operands(fpu_, /fpu_src, 3:1)
               )
            $replay = ($pending_replay m4_ifelse(m5_EXT_F, 1, ['|| /fpu$pending_replay']));
         
         // =======
         // Execute
         // =======
         
         // Instantiate the program. (This approach is required for an m4-defined name.)
         m4_def(exe_macro_name, m5_isa['_exe'])
         m4+m4_exe_macro_name(@m5_EXECUTE_STAGE, @m5_RESULT_STAGE)
         
         @m5_BRANCH_PRED_STAGE
            m4_ifelse(m5_BRANCH_PRED, ['fallthrough'], [''], ['$pred_taken_branch = $pred_taken && $branch;'])
         @m5_EXECUTE_STAGE

            // =======
            // Control
            // =======
            
            // A version of PC we can pull through $ANYs.
            $pc[m5_PC_RANGE] = $Pc[m5_PC_RANGE];
            `BOGUS_USE($pc)
            
            
            // Execute stage redirect conditions.
            $non_pipelined = $div_mul m4_ifelse(m5_EXT_F, 1, ['|| $fpu_div_sqrt_type_instr']) m4_ifelse(m5_EXT_B, 1, ['|| $clmul_crc_type_instr']);
            $replay_trap = m4_cpu_blocked;
            $aborting_trap = ($replay_trap || ($valid_decode && $illegal) || $aborting_isa_trap);
            $non_aborting_trap = $non_aborting_isa_trap;
            $mispred_branch = $branch && ! ($conditional_branch && ($taken == $pred_taken));
            ?$valid_decode_branch
               $branch_redir_pc[m5_PC_RANGE] =
                  // If fallthrough predictor, branch mispred always redirects taken, otherwise PC+1 for not-taken.
                  m4_ifelse(m5_BRANCH_PRED, ['fallthrough'], [''], ['(! $taken) ? $Pc + m5_PC_CNT'b1 :'])
                  $branch_target;

            $trap_target[m5_PC_RANGE] = $replay_trap ? $Pc : {m5_PC_CNT{1'b1}};  // TODO: What should this be? Using ones to terminate test for now.
            
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
            // $commit = m4_prev_instr_valid_through(m5_MAX_REDIRECT_BUBBLES + 1), where +1 accounts for this
            // instruction's redirects. However, to meet timing, we consider this instruction separately, so,
            // commit if valid as of the latest redirect from prior instructions and not abort of this instruction.
            m4_ifelse_block(m5_RETIMING_EXPERIMENT_ALWAYS_COMMIT, ['m5_RETIMING_EXPERIMENT_ALWAYS_COMMIT'], ['
            // Normal case:
            $good_path = m4_prev_instr_valid_through(m5_MAX_REDIRECT_BUBBLES);
            $commit = $good_path && ! $abort;
            '], ['
            // For the retiming experiments, $commit is determined too late, and it is inconvenient to make the $GoodPathMask
            // logic retimable. Let's drive it to 1'b1 for now, and give synthesis the benefit of the doubt.
            $commit = 1'b1 && ! $abort;
            '])
            
            // Conditions that commit results.
            $valid_dest_reg_valid = ($dest_reg_valid && $commit) || ($second_issue m4_ifelse(m5_EXT_F, 1, ['&&  (! >>m5_LD_RETURN_ALIGN$is_flw_instr) && (! $fpu_second_issue_div_sqrt)']) );

            m4_ifelse_block(m5_EXT_F, 1, ['
            /fpu
               $valid_dest_reg_valid = ($dest_reg_valid && /instr$commit) || (/instr$fpu_second_issue_div_sqrt || (/instr$second_issue && /instr>>m5_LD_RETURN_ALIGN$is_flw_instr));
            '])
            $valid_ld = $ld && $commit;
            $valid_st = $st && $commit;

   m4+fixed_latency_fake_memory(/_cpu, 0)
   |fetch
      /instr
         // =========
         // Reg Write
         // =========
         m4+rf_wr(/regs, m5_REGS_RANGE, /instr$valid_dest_reg_valid, /instr$dest_reg, /instr$rslt, /instr$reg_wr_pending)

         // ======
         // FPU RF
         // ======
         m4+ifelse(m5_EXT_F, 1,
            \TLV
               /fpu
                  // TODO: $reg_wr_pending can go under /fpu?
                  m4+rf_wr(/regs, m5_FPU_REGS_RANGE, /fpu$valid_dest_reg_valid, /fpu$dest_reg, /instr$rslt, /instr$reg_wr_pending)
            )

         @m5_REG_WR_STAGE
            `BOGUS_USE(/orig_inst/src[2]$dummy) // To pull $dummy through $ANY expressions, avoiding empty expressions.

         // TODO. Seperate the $rslt and $reg_wr_pending committed to both "int" and "fpu" regs.


\TLV operands(_rf, /_src, _src_range)
   // Obtain source register values and pending bit for int or fp source registers. Bypass up to 3
   // stages.
   // It is not necessary to bypass pending, as we could delay the replay, but we implement
   // bypass for performance.
   // Pending has an additional read for the dest register as we need to replay for write-after-write
   // hazard as well as write-after-read. To replay for dest write with the same timing, we must also
   // bypass the dest reg's pending bit.
   m4_ifexpr(m5_REG_BYPASS_STAGES >= 1, ['$bypass_avail1 = >>1$valid_dest_reg_valid && (/instr$GoodPathMask[1] || /instr>>1$second_issue);'])
   m4_ifexpr(m5_REG_BYPASS_STAGES >= 2, ['$bypass_avail2 = >>2$valid_dest_reg_valid && (/instr$GoodPathMask[2] || /instr>>2$second_issue);'])
   m4_ifexpr(m5_REG_BYPASS_STAGES >= 3, ['$bypass_avail3 = >>3$valid_dest_reg_valid && (/instr$GoodPathMask[3] || /instr>>3$second_issue);'])
   /src[_src_range]
      $is_reg_condition = $is_reg && /instr$valid_decode;  // Note: $is_reg can be set for RISC-V sr0.
      ?$is_reg_condition
         $rf_value[m5_WORD_RANGE] =
              m4_ifelse(m5_RF_STYLE, STUBBED, ['{/instr$Pc[31:2], /instr$Pc[31:30]}'], /instr/regs[$reg]>>m5_REG_BYPASS_STAGES$value);
         /* verilator lint_off WIDTH */  // TODO: Disabling WIDTH to work around what we think is https://github.com/verilator/verilator/issues/1613, when --fmtPackAll is in use.
         {$reg_value[m5_WORD_RANGE], $pending} =
            m4_ifelse(m5_ISA['']_rf, ['RISCV'], ['($reg == m5_REGS_INDEX_CNT'b0) ? {m5_WORD_CNT'b0, 1'b0} :  // Read r0 as 0 (not pending).'])
            // Bypass stages. Both register and pending are bypassed.
            // Bypassed registers must be from instructions that are good-path as of this instruction or are 2nd issuing.
            m4_ifexpr(m5_REG_BYPASS_STAGES >= 1, ['(/instr$bypass_avail1 && (/instr>>1$dest_reg == $reg)) ? {/instr>>1$rslt, /instr>>1$reg_wr_pending} :'])
            m4_ifexpr(m5_REG_BYPASS_STAGES >= 2, ['(/instr$bypass_avail2 && (/instr>>2$dest_reg == $reg)) ? {/instr>>2$rslt, /instr>>2$reg_wr_pending} :'])
            m4_ifexpr(m5_REG_BYPASS_STAGES >= 3, ['(/instr$bypass_avail3 && (/instr>>3$dest_reg == $reg)) ? {/instr>>3$rslt, /instr>>3$reg_wr_pending} :'])
            {$rf_value, m4_ifelse(m5_PENDING_ENABLED, 0, ['1'b0'], ['/instr/regs[$reg]>>m5_REG_BYPASS_STAGES$pending'])};
         /* verilator lint_on WIDTH */
      // Replay if source register is pending.
      $replay = $is_reg_condition && $pending;
   
   // Also replay for pending dest reg to keep writes in order. Bypass dest reg pending to support this.
   $is_dest_condition = $dest_reg_valid && /instr$valid_decode;
   ?$is_dest_condition
      $dest_pending =
         m4_ifelse(m5_ISA['']_rf, ['RISCV'], ['($dest_reg == m5_REGS_INDEX_CNT'b0) ? 1'b0 :  // Read r0 as 0 (not pending). Not actually necessary, but it cuts off read of non-existent rs0, which might be an issue for formal verif tools.'])
         // Bypass stages.
         m4_ifexpr(m5_REG_BYPASS_STAGES >= 1, ['($bypass_avail1 && (>>1$dest_reg == $dest_reg)) ? /instr>>1$reg_wr_pending :'])
         m4_ifexpr(m5_REG_BYPASS_STAGES >= 2, ['($bypass_avail2 && (>>2$dest_reg == $dest_reg)) ? /instr>>2$reg_wr_pending :'])
         m4_ifexpr(m5_REG_BYPASS_STAGES >= 3, ['($bypass_avail3 && (>>3$dest_reg == $dest_reg)) ? /instr>>3$reg_wr_pending :'])
         m4_ifelse(m5_PENDING_ENABLED, 0, ['1'b0'], ['/regs[$dest_reg]>>m5_REG_BYPASS_STAGES$pending']);
   // Combine replay conditions for pending source or dest registers.
   $pending_replay = | /src[*]$replay || ($is_dest_condition && $dest_pending);




// Reg write logic for int or fp RF.
// Register file has no reset, so initial values are undefined, and can be written at random prior to and during reset.
// Controlling definitions:
//    m5_PENDING_ENABLED
//    m5_RF_STYLE
\TLV rf_wr(/_hier, _RANGE, $_we, $_waddr, $_wdata, $_wpending)
   /* verilator lint_save */
   /* verilator lint_on WIDTH */
   @m5_REG_WR_STAGE
      m4+ifelse(m5_RF_STYLE, STUBBED,
         \TLV
            // Exclude the register file.
            `BOGUS_USE($_we $_waddr $_wdata)
         ,
         \TLV
            // Reg Write (Floating Point Register)
            \SV_plus
               always @ (posedge clk) begin
                  if ($_we)
                     /_hier[$_waddr]<<0$$^value[m5_WORD_RANGE] <= $_wdata;
               end
         )
      m4+ifelse(m5_PENDING_ENABLED, 1,
         \TLV
            // Write $pending along with $value, but coded differently because it must be reset.
            /regs[_RANGE]
               <<1$pending = ! /instr$reset && (((#m4_strip_prefix(/_hier) == $_waddr) && $_we) ? $_wpending : $pending);
         )
   /* verilator lint_restore */

\TLV cnt10_makerchip_tb()
   |fetch
      /instr
         @m5_REG_WR_STAGE
            // Assert these to end simulation (before Makerchip cycle limit).
            $ReachedEnd <= $reset ? 1'b0 : $ReachedEnd || $Pc == {m5_PC_CNT{1'b1}};
            $Reg4Became45 <= $reset ? 1'b0 : $Reg4Became45 || ($ReachedEnd && /regs[4]$value == m5_WORD_CNT'd45);
            $passed = ! $reset && $ReachedEnd && $Reg4Became45;
            $failed = ! $reset && (*cyc_cnt > 500 || (*cyc_cnt > 5 && $commit && $illegal));

\TLV formal()
   
   // /=====================\
   // | Formal Verification |
   // \=====================/
   
   // Instructions are presented to RVFI in reg wr stage. Loads cannot be presented until their load
   // data returns, so it is the returning ld that is presented. The instruction to present to RVFI
   // is provided in /instr/original. RVFI inputs are generally connected from this context,
   // except for the returning ld data. Also signals which are not relevant to loads are pulled straight from
   // /instr to avoid unnecessary recirculation.
   |fetch
      /instr
         @m5_EXECUTE_STAGE
            // characterise non-speculatively in execute stage

            // RVFI interface for formal verification.
            $trap = $aborting_trap ||
                    $non_aborting_trap;
            $rvfi_trap        = ! $reset && >>m4_eval(-m5_MAX_REDIRECT_BUBBLES + 1)$next_rvfi_good_path_mask[m5_MAX_REDIRECT_BUBBLES] &&
                                $trap && ! $replay && ! $second_issue;  // Good-path trap, not aborted for other reasons.
            
            // Order for the instruction/trap for RVFI check. (For split instructions, this is associated with the 1st issue, not the 2nd issue.)
            $rvfi_order[63:0] = $reset                  ? 64'b0 :
                                ($commit || $rvfi_trap) ? >>1$rvfi_order + 64'b1 :
                                                          $RETAIN;
         @m5_REG_WR_STAGE
            // verify in register writeback stage

            // This scope is a copy of /orig_inst if $second_issue, else pull current instruction

            /original
               $ANY = /instr$second_issue ? /instr/orig_inst$ANY : /instr$ANY;
               /src[2:1]
                  $ANY = /instr$second_issue ? /instr/orig_inst/src$ANY : /instr/src$ANY;

            $would_reissue = ($ld || $div_mul);
            $retire = ($commit && !$would_reissue ) || $second_issue;
            // a load or div_mul instruction commits results in the second issue, hence the first issue is non-retiring
            // for the first issue of these instructions, $rvfi_valid is not asserted and hence the current outputs are 
            // not considered by riscv-formal

            $rvfi_valid       = ! |fetch/instr<<m4_eval(m5_REG_WR_STAGE - (m5_NEXT_PC_STAGE - 1))$reset &&    // Avoid asserting before $reset propagates to this stage.
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
               *rvfi_rs1_rdata   = /src[1]$is_reg ? /src[1]$reg_value : m5_WORD_CNT'b0;
               *rvfi_rs2_rdata   = /src[2]$is_reg ? /src[2]$reg_value : m5_WORD_CNT'b0;
               *rvfi_rd_addr     = (/instr$dest_reg_valid && ! $abort) ? $raw_rd : 5'b0;
               *rvfi_rd_wdata    = (| *rvfi_rd_addr) ? /instr$rslt : 32'b0;
            *rvfi_pc_rdata    = {/original$pc[31:2], 2'b00};
            *rvfi_pc_wdata    = {$reset          ? m5_PC_CNT'b0 :
                                 $second_issue   ? /orig_inst$pc + 1'b1 :
                                 $trap           ? $trap_target :
                                 $jump           ? $jump_target :
                                 $mispred_branch ? ($taken ? $branch_target[m5_PC_RANGE] : $pc + m5_PC_CNT'b1) :
                                 m4_ifelse(m5_BRANCH_PRED, ['fallthrough'], [''], ['$pred_taken_branch ? $branch_target[m5_PC_RANGE] :'])
                                 $indirect_jump  ? $indirect_jump_target :
                                 $pc[31:2] +1'b1, 2'b00};
            *rvfi_mem_addr    = (/original$ld || $valid_st) ? {/original$addr[m5_ADDR_MAX:2], 2'b0} : 0;
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
         // Stage numbering has @0 == |fetch@m5_EXECUTE_STAGE 
         @0
            $ANY = /_cpu|fetch/instr>>m5_EXECUTE_STAGE$ANY;  // (including $reset)
            $is_pkt_wr = $is_csr_write && ($is_csr_pktwr || $is_csr_pkttail);
            $vc[m5_VC_INDEX_RANGE] = $csr_pktwrvc[m5_VC_INDEX_RANGE];
            // This PKTWR write is blocked if the skid buffer blocked last cycle.
            $pkt_wr_blocked = $is_pkt_wr && |egress_in/skid_buffer>>1$push_blocked;
         @1
            $valid_pkt_wr = $is_pkt_wr && $commit;
            $valid_pkt_tail = $valid_pkt_wr && $is_csr_pkttail;
            $insert_header = |egress_in/skid_buffer$valid_pkt_wr && ! $InPacket;
            // Assert after inserting header up to insertion of tail.
            $InPacket <=  *reset ? 1'b0 : ($insert_header || ($InPacket && ! (|egress_in/skid_buffer$valid_pkt_tail && ! |egress_in/skid_buffer$push_blocked)));
      @1

         /skid_buffer
            $ANY = >>1$push_blocked ? >>1$ANY : |egress_in/instr$ANY;
            // Hold the write if blocked, including the write of the header in separate signals.
            // This give 1 cycle of slop so we have time to check validity and generate a replay if blocked.
            // Note that signals in this scope are captured versions reflecting the flit and its producing instruction.
            $push_blocked = *reset ? 1'b0 : $valid_pkt_wr && (/_cpu/vc[$vc]|egress_in$blocked || ! |egress_in/instr$InPacket);
            // Header
            // Construct header flit.
            $src[m5_CORE_INDEX_RANGE] = #m4_strip_prefix(/_cpu);
            $header_flit[31:0] = {{m5_FLIT_UNUSED_CNT{1'b0}},
                                  $vc,
                                  $src,
                                  $csr_pktdest[m4_echo(m5_CORE_INDEX_RANGE)]
                                 };
         /flit
             // TODO. ADD a WHEN condition.
            {$tail, $flit[m5_WORD_RANGE]} = |egress_in/instr$insert_header ? {1'b0, |egress_in/skid_buffer$header_flit} :
                                                                             {|egress_in/skid_buffer$valid_pkt_tail, |egress_in/skid_buffer$csr_wr_value};
   /vc[*]
      |egress_in
         @1
            $vc_trans_valid = /_cpu|egress_in/skid_buffer$valid_pkt_wr && (/_cpu|egress_in/skid_buffer$vc == #vc);
   m4+vc_flop_fifo_v2(/_cpu, |egress_in, @1, |egress_out, @1, #depth, /flit, m5_VC_RANGE, m5_PRIO_RANGE)
   
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
         // Data from VC_FIFO is made available by the end of |ingress_out@-1(arb/byp) == m5_EXECUTE_STAGE-1
         // reflecting prior-prior!-stage PKTRDVCS
         // so it can be captured in PKTRD and used by m5_EXECUTE_STAGE (== |ingress_out@0(out))
         @m5_EXECUTE_STAGE  // == |ingress_out@0
            // CSR PKTRD is written by hardware as the head of the ingress buffer.
            // Write if there is head data, else, CSR is invalid.
            $csr_pktrd_valid = /_cpu|ingress_out<<m5_EXECUTE_STAGE$trans_valid;
            ?$csr_pktrd_valid
               $csr_pktrd[m5_WORD_RANGE] = /_cpu|ingress_out/flit<<m5_EXECUTE_STAGE$flit;
            $non_spec_abort = $aborting_trap && $good_path;
         @m5_NEXT_PC_STAGE
            // Mark instructions that are replayed. These are non-speculative. We use this indication for CSR pkt reads,
            // which can only pull flits from ingress FIFOs non-speculatively (currently).
            $replayed = >>m4_eval(m5_TRAP_BUBBLES + 1)$non_spec_abort;
   |ingress_out
      @-1
         // Note that we access signals here that are produced in @m5_DECODE_STAGE, so @m5_DECODE_STAGE must not be the same physical stage as @m5_EXECUTE_STAGE.
         /instr
            $ANY = /_cpu|fetch/instr>>m5_EXECUTE_STAGE$ANY;
         $is_pktrd = /instr$is_csr_instr && /instr$is_csr_pktrd;
         // Detect a recent change to PKTRDVCS that could invalidate the use of a stale PKTRDVCS value and must avoid read (which will force a replay).
         $pktrdvcs_changed = /instr>>1$is_csr_write && /instr>>1$is_csr_pktrdvcs;
         $do_pktrd = $is_pktrd && ! $pktrdvcs_changed && /instr$replayed; // non-speculative do_pktrd

      @0
         // Replay for PKTRD with no data transaction.
         $pktrd_blocked = $is_pktrd && ! $trans_valid;

   /vc[*]
      |ingress_out
         @-1
            $has_credit = /_cpu|ingress_out/instr>>1$csr_pktrdvcs[#vc] &&
                          /_cpu|ingress_out$do_pktrd;
            $Prio[m5_PRIO_INDEX_RANGE] <= '0;
   m4+vc_flop_fifo_v2(/_cpu, |ingress_in, @0, |ingress_out, @0, #depth, /flit, m5_VC_RANGE, m5_PRIO_RANGE)



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
            $Prio[m5_PRIO_INDEX_RANGE] <= '0;
   |egress_out
      @-1
         $reset = *reset;
      @0
         // This is a body flit (includes invalid body flits and tail flit) if last cycle was a tail flit and 
         $body = $reset   ? 1'b0 :
                 >>1$body ? ! >>1$valid_tail :
                            >>1$valid_head;
         $body_vc[m5_VC_INDEX_RANGE] = >>1$valid_head ? /flit>>1$flit[m5_FLIT_VC_RANGE] : $RETAIN;
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
   m4_push(in_delay, m4_defaulted_arg(#_in_delay, 0))
   m4_push(hop_dist, m4_defaulted_arg(#_hop_dist, 1))
   m4_push(hop_name, m4_strip_prefix(/_hop))
   m4_push(HOP, ['m5_']m4_translit(m4_hop_name, ['a-z'], ['A-Z']))
   m4_push(prev_hop_index, (m4_hop_name + m4_echo(m5_HOP['_CNT']) - 1) % m4_echo(m5_HOP['_CNT']))
   
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
         $ANY = /_hop[(#m4_hop_name + m4_echo(m5_HOP['_CNT']) - 1) % m4_echo(m5_HOP['_CNT'])]|_name['']_leaving<>0$ANY;
         /_flit
            $ANY = /_hop[(#m4_hop_name + m4_echo(m5_HOP['_CNT']) - 1) % m4_echo(m5_HOP['_CNT'])]|_name['']_leaving/_flit<>0$ANY;
   |_name['']_leaving
      @0
         $blocked = /_hop[(#m4_hop_name + 1) % m4_echo(m5_HOP['_CNT'])]|_name['']_arriving<>0$blocked;
   // Fork off ring
   m4+fork(/_hop, |_name['']_arriving, @0, $head_out_inv, |_name['']_continuing, @0, $true, |_out, @_out, /_flit)
   
   // Fork from continuing to non_deflected or into FIFO
   m4+fork(/_hop, |_name['']_continuing, @0, $head_out, |_name['']_not_deflected, @0, $true, |_name['']_deflected, @0, /_flit)
   
   // Flop prior to FIFO.
   m4+stage(ff, /_hop, |_name['']_deflected, @0, |_name['']_deflected_st1, @1, /_flit)
   // Mux into FIFO. (Priority to deflected blocks node.)
   m4+arb2(/_hop, |_name['']_deflected_st1, @1, |_name['']_node_to_fifo, @0, |_name['']_fifo_in, @0, /_flit)
   // The insertion FIFO.
   m4+flop_fifo_v2(/_hop, |_name['']_fifo_in, @0, |_name['']_fifo_out, @0, #_depth, /_flit)
   // Block FIFO output until a full packet is ready (tail from node in FIFO)
   m4+connect(/_hop, |_name['']_fifo_out, @0, |_name['']_fifo_inj, @0, /_flit, [''], ['|| ! (/_hop|_name['']_fifo_in<>0$node_tail_flit_in_fifo)'])
   // Ring
   m4+arb3(/_hop, |_name['']_not_deflected, @0, |_name['']_fifo_inj, @0, |_name, @0, /_flit)


   // Decode arriving header flit.
   |_name['']_arriving
      @0
         // Characterize arriving flit (head/tail/body, header)
         {$vc[m5_VC_INDEX_RANGE], $dest[m4_echo(m5_HOP['_INDEX_RANGE'])]} =
            $reset  ? '0 :
            ! $body ? {/flit$flit[m5_FLIT_VC_RANGE], /flit$flit[m5_FLIT_DEST_RANGE]} :
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
         $head_out_inv = ! $head_out;
         $true = 1'b1; // (ok signal for fork along out path)
   |_name['']_continuing
      @0

         $head_out = ! /_hop|_name['']_not_deflected<>0$blocked;
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
              ((/_hop|_name['']_deflected_st1>>1$avail && /_hop|_name['']_deflected_st1>>1$accepted) || (/_hop|_name['']_node_to_fifo<>0$accepted && /_hop|_name['']_node_to_fifo/flit<>0$tail)) ? 1'b1 :
              $would_bypass ? 1'b0 :
                   $RETAIN;

   m4_pop(in_delay)
   m4_pop(hop_dist)
   m4_pop(hop_name)
   m4_pop(HOP)
   m4_pop(prev_hop_index)

\TLV arb3(/_top, |_in1, @_in1, |_in2, @_in2, |_out, @_out, /_trans, $_reset1)
   m4+flow_interface(/_top, [' |_in1, @_in1, |_in2, @_in2'], [' |_out, @_out'], $_reset1)
   m4_push(trans_ind, m4_ifelse(/_trans, [''], [''], ['   ']))
   // In1 is blocked if output is blocked.
   // In1 is blocked if output is blocked or in2 is available.
   |_in1
      @_in1
         $blocked = /_top|_out>>m4_align(@_out, @_in1)$blocked ||
                    (/_top|_in2>>m4_align(@_in2, @_out)$avail && /_top|_in2>>m4_align(@_in2 + 1, @_out)$accepted);
   // In2 is blocked if output is blocked or in1 is available.
   |_in2
      @_in2
         $blocked = /_top|_out>>m4_align(@_out, @_in2)$blocked ||
                    /_top|_in1>>m4_align(@_in1, @_in2)$avail;
   // Output comes from in1 if available, otherwise, in2.
   |_out
      @_out
         $reset = /_top|_in1>>m4_align(@_in1, @_out)$reset_in;
         // Output is available if either input is available.
         $avail = /_top|_in1>>m4_align(@_in1, @_out)$avail ||
                  /_top|_in2>>m4_align(@_in2, @_out)$avail;
         ?$avail
            /_trans
         m4_trans_ind   $ANY = /_top|_in1>>m4_align(@_in1, @_out)$avail ? /_top|_in1/_trans>>m4_align(@_in1, @_out)$ANY :
                                                                          /_top|_in2/_trans>>m4_align(@_in2, @_out)$ANY;
   m4_pop(trans_ind)
   
   
// Can be used to build for many-core without a NoC (during development).
\TLV dummy_noc(/_cpu)
   |fetch
      @m5_EXECUTE_STAGE
         /instr
            $csr_pktrd[31:0] = 32'b0;
   
// For building just the insertion ring in isolation.
// The diagram builds, but unfortunately it is messed up :(.
\TLV main_ring_only()
   /* verilator lint_on WIDTH */  // Let's be strict about bit widths.
   /m5_CORE_HIER
      |egress_out
         /flit
            @0
               $bogus_head = ((#core == 0) && | ((1 << (*cyc_cnt - 2)) & 10'b00000000100)) ||
                             ((#core == 1) && | ((1 << (*cyc_cnt - 2)) & 10'b00000000000));
               $tail       = ((#core == 0) && | ((1 << (*cyc_cnt - 2)) & 10'b00000001000)) ||
                             ((#core == 0) && | ((1 << (*cyc_cnt - 2)) & 10'b00000000000));
               $bogus_mid  = ((#core == 0) && | ((1 << (*cyc_cnt - 2)) & 10'b00000000000)) ||
                             ((#core == 1) && | ((1 << (*cyc_cnt - 2)) & 10'b00000000000));
               $bogus_src[m5_CORE_INDEX_RANGE] = #core;
               $bogus_dest[m5_CORE_INDEX_RANGE] = 1;
               $bogus_vc[m5_VC_INDEX_RANGE] = 0;
               $flit[m5_FLIT_RANGE] = $bogus_head ? {*cyc_cnt[m5_FLIT_UNUSED_CNT-3:0], 2'b01      , $bogus_vc, $bogus_src, $bogus_dest}
                                                  : {*cyc_cnt[m5_FLIT_UNUSED_CNT-3:0], $tail, 1'b0, m4_eval(m5_VC_INDEX_CNT + m5_CORE_INDEX_CNT * 2)'b1};
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
      @m5_VIZ_STAGE
         /instr
            // A type-independent immediate value, for debug. (For R-type, funct7 is used as immediate).
            $imm_value[m5_WORD_RANGE] =
                 ({m5_WORD_CNT{$is_i_type}} & $raw_i_imm) |
                 ({m5_WORD_CNT{$is_r_type}} & {25'b0, $raw_funct7}) |
                 ({m5_WORD_CNT{$is_s_type}} & $raw_s_imm) |
                 ({m5_WORD_CNT{$is_b_type}} & $raw_b_imm) |
                 ({m5_WORD_CNT{$is_u_type}} & $raw_u_imm) |
                 ({m5_WORD_CNT{$is_j_type}} & $raw_j_imm);
            $imm_valid = $is_i_type || $is_r_type || $is_s_type || $is_b_type || $is_u_type || $is_j_type;

\TLV dummy_viz_logic()
   // dummy
   
\TLV instruction_in_memory(|_top, _where_)
   /instr_mem[m4_eval(m5_NUM_INSTRS-1):0]
      \viz_js
          all: {
            box: {
               width: 670,
               height: 76 + 18 * m5_NUM_INSTRS,
               fill: "#208028",
               stroke: "white",
               strokeWidth: 0
            },
            init() {
               let imem_header = new fabric.Text("🗃️ Instr. Memory", {
                  top: 10,
                  left: 250,
                  fontSize: 20,
                  fontWeight: 800,
                  fontFamily: "monospace",
                  fill: "black"
               })
               return {imem_header}
            },
            render() {
               // Highlight instruction.
               let pc = '['']|_top/instr$pc'.asInt(-1)
                this.highlighted_addr = pc
                instance = this.getContext().children[pc]
                if (typeof instance !== "undefined") {
                   let color = '['']|_top/instr$commit'.asBool(false) ? "#b0ffff" : "#d0d0d0"
                   instance.initObjects.instr_binary_box.set({fill: color})
                   instance.initObjects.instr_asm_box.set({fill: color})
                }
                // Highlight 2nd issue instruction.
                let pc2 = '['']|_top/instr/orig_inst$pc'.asInt(-1)
                this.highlighted_addr2 = pc2
                instance2 = this.getContext().children[pc2]
                if ('['']|_top/instr$second_issue'.asBool(false) && typeof instance2 !== "undefined") {
                   let color = "#ffd0b0"
                   instance2.initObjects.instr_binary_box.set({fill: color})
                   instance2.initObjects.instr_asm_box.set({fill: color})
                }
            },
            unrender() {
               //debbuger
               // Unhighlight instruction.
               let instance = this.getContext().children[this.highlighted_addr]
                if (typeof instance != "undefined") {
                   instance.initObjects.instr_binary_box.set({fill: "white"})
                   instance.initObjects.instr_asm_box.set({fill: "white"})
                }
                // Unhighlight 2nd issue instruction.
                let instance2 = this.getContext().children[this.highlighted_addr2]
                if (typeof instance2 != "undefined") {
                   instance2.initObjects.instr_binary_box.set({fill: "white"})
                   instance2.initObjects.instr_asm_box.set({fill: "white"})
                }
            },
          },
          box: {strokeWidth: 0},
          where: {_where_},
          where0: {left: 30, top: 50},
          layout: {top: 18}, //scope's instance stacked vertically
          init() {
            let instr_str = new fabric.Text("" , {
               left: 10,
               fontSize: 14,
               fontFamily: "monospace"
            })
            let instr_asm_box = new fabric.Rect({
               left: 0,
               fill: "white",
               width: 280,
               height: 14
            })
            let instr_binary_box = new fabric.Rect({
               left: 330,
               fill: "white",
               width: 280,
               height: 14
            })
            return {instr_asm_box, instr_binary_box, instr_str}
          },
          m4_ifelse(m5_IMEM_STYLE, EXTERN, , ['
          render() {
             // Instruction memory is constant, so just create it once.
            m4_ifelse_block(m5_ISA, ['MINI'], ['
               let instr_str = '$instr'.goTo(0).asString("?")
            '], m5_ISA, ['RISCV'], ['
               let instr_str = '$instr'.asBinaryStr(NaN) + "      " + '$instr_str'.asString("?")
            '], m5_ISA, ['MIPSI'], ['
               let instr_str = '$instr'.asBinaryStr("?")
            '], ['
               let instr_str = '$instr'.goTo(0).asString("?")
            '])
            this.getObjects().instr_str.set({text: `${instr_str}`})
          },
          '])
          
   
\TLV registers(/_top, _name, _heading, _sig_prefix, _num_srcs, _where_)
   // /regs or /fpu_regs
   /src[*]
      // There is an issue (#406) with \viz code indexing causing signals to be packed, and if a packed value
      // has different fields on different clocks, Verilator throws warnings.
      // These are unconditioned versions of the problematic signals.
      $unconditioned_reg[m4_echo(['m5_']m4_to_upper(_sig_prefix)REGS_INDEX_RANGE)] = $reg;
      $unconditioned_is_reg = $is_reg;
      $unconditioned_reg_value[m5_WORD_RANGE] = $reg_value;
   /regs[m4_echo(['m5_']m4_to_upper(_sig_prefix)REGS_RANGE)]
      \viz_js
         all: {
            box: {
               fill: "#2028b0",
               width: 145,
               height: 650,
               stroke: "black",
               strokeWidth: 0
            },
            init() {
               let rf_header = new fabric.Text("📂 _heading", {
                  top: 10,
                  left: 10,
                  fontSize: 18,
                  fontWeight: 800,
                  fontFamily: "monospace",
                  fill: "white"
               })
               let rf_header2 = new fabric.Text("Integer (hex)", {
                  top: 40,
                  left: 20,
                  fontSize: 14,
                  fontFamily: "monospace",
                  fill: "white"
               })
               return {rf_header, rf_header2}
            },
         },
         where: {_where_},
         where0: {left: 10, top: 80},
         box: {
               fill: "white",
               width: 125,
               height: 14,
               strokeWidth: 0
            },
         layout: {top: 17}, //vertically
         init() {
            let reg = new fabric.Text("", {
               left: 10,
               fontSize: 14,
               fontFamily: "monospace"
            })
            return {reg}
         },
         render() {
            // TODO: This is inefficient as is the same for every entry.
            let mod = '/_top$valid_dest_reg_valid'.asBool(false) && ('/_top$dest_reg'.asInt(-1) == this.getIndex())
            let rs_valid = []
            let read_valid = false
            for (let i = 1; i <= _num_srcs; i++) {
               rs_valid[i] = '/_top/src[i]$unconditioned_is_reg'.asBool(false) && this.getIndex() === '/_top/src[i]$unconditioned_reg'.asInt(-1)
               read_valid |= rs_valid[i]
            }
            let pending = m4_ifelse(m5_PENDING_ENABLED, 1, [''<<1$pending'.asBool(false)'], ['false'])
            let reg = parseInt(this.getIndex())
            let regIdent = ("m5_ISA" == "MINI") ? String.fromCharCode("a".charCodeAt(0) + reg) : reg.toString()
            let oldValStr = mod ? `(${'$value'.asInt(NaN).toString(16)})` : ""
            this.getObjects().reg.set({text:
               regIdent + ": " +
               '$value'.step(1).asInt(NaN).toString(16) + oldValStr})
            this.getObjects().reg.set({fill: pending ? "darkorange" : mod ? "blue" : "black"})
            this.getBox().set({fill: mod ? ('/instr$second_issue'.asBool(false) ? "#ffd0b0" : "#b0ffff") : read_valid ? "#d0e8ff" : "white"})
         }

\TLV pipeline_control_viz(/_scope, _where)
   $first_issue = $valid_ld || $non_pipelined;
   /pipe_ctrl
      \viz_js
         box: {width: 110, height: 160, stroke: "green", strokeWidth: 1, fill: "#b0e0b0"},
         init() {
            return {title: new fabric.Text("Cycle-Level Behavior", {
               top: 10,
               left: 55,
               originX: "center", originY: "center",
               fill: "darkgreen",
               fontSize: 10,
               fontWeight: 800,
               fontFamily: "roboto"
            })}
         },
         where: {_where}
      /logic_diagram
         \viz_js
            box: {left: -5, top: -15, width: 110, height: 80, strokeWidth: 0},
            init() {
               ret = {}
               labels = {}  // virtual pipeline stage name labels, added to ret after stage backgrounds
               this.makeBullet = (signalName, bulletText, bulletColor) => {
                  return new fabric.Group([
                       new fabric.Circle({
                            fill: bulletColor, strokeWidth: 0, opacity: 0.8,
                            originX: "center", originY: "center",
                            left: 0, top: 0,
                            radius: 2}),
                       new fabric.Text(bulletText, {
                            fill: "black",
                            originX: "center", originY: "center",
                            left: 0, top: 0,
                            fontSize: 2, fontWeight: 800, fontFamily: "monospace"})
                  ], {originX: "center", originY: "center"})
               }
               
               this.color = function (stage) {
                  let i = (stage % 6) + 1
                  let ret = `rgb(${i % 8 >= 4 ? 60 :10}, ${i % 4 >= 2 ? 100 : 30}, ${i % 2 >= 1 ? 150 : 90})`
                  return ret
               }
               
               ret.title = new fabric.Text("Pipeline Reference", {
                  top: -5,
                  left: 50,
                  fill: "black",
                  originX: "center", originY: "center",
                  fontSize: 7,
                  fontWeight: 800,
                  fontFamily: "monospace"
               })
               
               let stages = []  // Eg: [0: {virtualStages: ["NEXT_PC", "FETCH"], left: 10, right: 25}, 2: ...}
               let stageCnt = 0
               let defineStage = function (name, stage, left, right) {
                  if (!stages[stage]) {
                     stages[stage] = {}
                  }
                  s = stages[stage]
                  s.virtualStages = []
                  if (!s.left || left < s.left) {s.left = left}
                  if (!s.right || right > s.right) {s.right = right}
                  s.virtualStages.push(name)
                  // Create label
                  labels[`${name}_label`] = new fabric.Text(name, {
                            fill: "white",
                            originX: "center", originY: "center",
                            left: (left + right) / 2, top: 57 + ((stageCnt % 2) ? 0 : 3),
                            fontSize: 2, fontWeight: 800, fontFamily: "roboto"
                  })
                  stageCnt++
               }
               m4_stages_js
               for (stage in stages) {
                  stage = parseInt(stage)
                  s = stages[stage]
                  ret[`stage${stage}`] = new fabric.Rect({
                       left: s.left, top: 0, width: s.right - s.left, height: 62,
                       fill: this.color(stage)
                  })
                  ret[`@${stage}`] = new fabric.Text(`@${stage}`, {
                       fill: "green",
                       originX: "center", originY: "center",
                       left: (s.left + s.right) / 2, top: 64,
                       fontSize: 2, fontWeight: 800, fontFamily: "mono"
                  })
               }
               // Layer in stage labels.
               Object.assign(ret, labels)
               
               redirect_cond = (signalName, bulletText, bulletColor, left, top) => {
                  let ret = new fabric.Group([
                       this.makeBullet(signalName, bulletText, bulletColor)
                            .set({left: left, top: top, width: 4, height: 4}),
                       new fabric.Text(signalName, {
                            fill: "black",
                            originY: "center",
                            left: left + 2, top: top,
                            fontSize: 2, fontWeight: 800, fontFamily: "monospace"})
                  ])
                  return ret
               }
               m4_redirect_viz
               // Add a bullet for 1st-issue instructions.
               ret.$first_issue = redirect_cond("$first_issue", "1st", "orange", 75, 31.5)
               ret.diagram =
                  // To update diagram, save from https://docs.google.com/presentation/d/1tFjekV06XHTYOXCSjd3er2kthiPEPaWrXlHKnS0yt5Q/edit?usp=sharing
                  // Open in Inkscape. Delete background rect. Edit > Resize Page to Selection. Drag into GitHub file editor. Copy URL. Cancel edit. Paste here.
                  this.newImageFromURL(
                      "m4_warpv_includes['']viz/pipeline_diagram.svg",
                      "",
                      {left: 0, top: 0, width: 100, height: 57},
                  )
               
               return ret
            },
            where: {left: 5, top: 17, width: 100, height: 73},
      /waterfall
         \viz_js
            box: {left: 0, top: 0, width: 100, strokeWidth: 0},
            init() {
               return {title: new fabric.Text("Waterfall Diagram", {
                  top: 9,
                  left: 50,
                  fill: "black",
                  originX: "center", originY: "center",
                  fontSize: 7,
                  fontWeight: 800,
                  fontFamily: "monospace"
               })}
            },
            where: {left: 5, top: 95, width: 100, height: 70}
         /pipe_ctrl_instr[m4_eval(m5_MAX_REDIRECT_BUBBLES * 2):0]  // Zero on the bottom. See this.getInstrIndex().
            \viz_js
               layout: {
                  left: function(i) {return -i * 10},
                  top: function(i) {return -i * 10},
               },
               box: {strokeWidth: 0},
               init() {
                  // /pipe_ctrl_instr indices are chosen such that they render bottom to top
                  // for proper overlapping of dependence arcs.
                  // This function provides indices where
                  // the current instruction has index 0, and negative are above.
                  this.getInstrIndex = () => {
                     return m5_MAX_REDIRECT_BUBBLES - this.getIndex()
                  }
                  return {instr: new fabric.Text("?", {
                             left: -100, top: 1,
                             fill: "darkgray",
                             fontSize: 7, fontWeight: 800, fontFamily: "monospace",
                         })}
               },
               renderFill() {
                  return (this.getInstrIndex() == 0) ? "#b0ffff" : "transparent"
               },
               render() {
                  let instr_text = this.getObjects().instr
                  let step = this.getInstrIndex()
                  try {
                     this.commit = '/instr$commit'      .step(step).asBool(false)
                     this.second = '/instr$second_issue'.step(step).asBool(false)
                     let color =
                        !this.commit ? "gray" :
                                       "blue"
                     let pc = '/instr$pc'.step(step).asInt()
                     let instr_str = m4_ifelse(m5_FORMAL, 1, "           " + '/instr$mnemonic', m5_IMEM_STYLE, EXTERN, "           " + '/instr$mnemonic', '|fetch/instr_mem[pc]$instr_str').step(step).asString("<UNKNOWN>")
                     this.getObjects().instr.set({
                        text: instr_str,
                        fill: color,
                     })
                  } catch(e) {
                     debugger
                     instr_text.set({text: "<NOT FOUND>", fill: "darkgray"})
                  }
                  return []
               },
               where: {left: 4, top: 15, width: 92, height: 51}
            /pipe_ctrl_stage[m5_MAX_REDIRECT_BUBBLES:0]
               \viz_js
                  box: {width: 10, height: 10, fill: "gray", strokeWidth: 0},
                  layout: "horizontal",
                  init() {
                  },
                  renderFill() {
                     // A step of 0 gives the $GoodPathMask in the middle, running up from bit 0.
                     // Positive steps are to the right (and shifting downward).
                     this.stage = this.getIndex()
                     this.instr = this.getScope("pipe_ctrl_instr").context.getInstrIndex()
                     this.step = this.stage + this.instr  // step amount for $GoodPathMask
                     let second = '/instr$second_issue'.step(this.instr).asBool(false)
                     this.goodPath = true
                     try {
                        mask = '/instr$GoodPathMask'.step(this.step).asInt(null)
                        this.goodPath = (mask === null) ? null : ((mask >> this.stage) & 1) != 0
                        return this.goodPath === null ? "transparent" :
                               this.goodPath ? this.getScope("pipe_ctrl").children.logic_diagram.context.color(this.getIndex()) :
                               second        ? "rgb(184,137,57)" :
                                               "gray"
                     } catch(e) {
                        return "darkgray"
                     }
                  },
                  render() {
                     let ret = []
                     if (this.goodPath === null) {
                     } else if (this.goodPath) {
                        let stage = this.stage + m5_NEXT_PC_STAGE;  // Absolute stage (not relative to NEXT_PC)
                        //
                        // Draw all register bypass arcs from this cell into REG_RD.
                        //
                        // TODO: Not implemented for FPU.
                        if (stage == m5_EXECUTE_STAGE + 1) {
                           for (bypassAmount = 1; bypassAmount <= m5_REG_BYPASS_STAGES; bypassAmount++) {
                              for (let rs = 1; rs <= 2; rs++) {
                                 try {
                                    let bypassSig = m4_ifexpr(m5_REG_BYPASS_STAGES >= 1, ['(bypassAmount == 1) ? '/instr$bypass_avail1' :'])
                                                    m4_ifexpr(m5_REG_BYPASS_STAGES >= 2, ['(bypassAmount == 2) ? '/instr$bypass_avail2' :'])
                                                    m4_ifexpr(m5_REG_BYPASS_STAGES >= 3, ['(bypassAmount == 3) ? '/instr$bypass_avail3' :'])
                                                                                                                 null
                                    let rd = '/instr$dest_reg'.step(this.instr).asInt(0)
                                    let bypass = bypassSig.step(bypassAmount + this.instr).asBool(false) &&
                                                 (rd === '/instr/src[rs]$unconditioned_reg'.step(bypassAmount + this.instr).asInt(0))
                                    if (bypass) {
                                       // To coords
                                       let rsLeft = -12 + bypassAmount * 10
                                       let rsTop = -1 + bypassAmount * 10 + 2 * rs
                                       // Line
                                       ret.push(new fabric.Line([-1, 7, -9 + 10 * bypassAmount, rsTop + 1], {
                                          strokeWidth: 0.5, stroke: "green", opacity: 0.8
                                       }))
                                       // From x#
                                       ret.push(new fabric.Rect({
                                          left: -4, top: 6, height: 2, width: 5,
                                          fill: bypass ? "darkgreen" : "gray",
                                          opacity: 0.8
                                       }))
                                       ret.push(new fabric.Text(`x${rd}`, {
                                          left: -4, top: 6, height: 2, width: 5,
                                          fill: "black",
                                          fontSize: 2,
                                          fontWeight: 800,
                                          fontFamily: "monospace"
                                       }))
                                       // To rs#
                                       ret.push(new fabric.Rect({
                                          left: rsLeft, top: rsTop, height: 2, width: 5,
                                          fill: bypass ? "green" : "gray",
                                          opacity: 0.8
                                       }))
                                       ret.push(new fabric.Text(`rs${rs}`, {
                                          left: rsLeft, top: rsTop, height: 2, width: 5,
                                          fill: "black",
                                          fontSize: 2,
                                          fontWeight: 800,
                                          fontFamily: "monospace",
                                          opacity: 0.8
                                       }))
                                    }
                                 } catch(e) {
                                    debugger
                                 }
                              }
                           }
                        }
                        //
                        // Draw all redirect arcs from this cell.
                        //
                        let redir_cnt = -1   // Increment for every redirect condition.
                        let render_redir = (sigName, $sig, bulletText, bulletColor, extraBubbleCycle) => {
                           let step = this.instr
                           $sig.step(step)
                           if ($sig.asBool()) {
                              let ret = []
                              redir_cnt++
                              let top = 4 + 2 * redir_cnt
                              let left = 8 - 8 * extraBubbleCycle
                              let bullet = this.getScope("pipe_ctrl").children.logic_diagram.context.makeBullet(sigName, bulletText, bulletColor)
                                   .set({left, top})
                              if (sigName !== "$first_issue") {
                                 ret.push(new fabric.Line(
                                    [left, top, 9.5, 10 * stage + 15],
                                    {strokeWidth: 0.5, stroke: bulletColor}
                                 ))
                              }
                              ret.push(bullet)
                              return ret
                           } else {
                              return []
                           }
                        }
                        try {
                           m4_redirect_cell_viz
                           // Add case for 1st issue.
                           if (stage == m5_MAX_REDIRECT_BUBBLES) {
                              ret = ret.concat(render_redir("$first_issue", '/instr$first_issue', "1st", "orange", 0))
                           }
                        } catch(e) {
                           debugger
                        }
                     }
                     return ret
                  },

\TLV register_csr(/_csr, _where)
   /_csr
      \viz_js
         box: {
            fill: "#2028b0",
            width: 220,
            height: 18 * m4_num_csrs + 52,
            stroke: "black",
            strokeWidth: 0
         },
         where: {_where},
         init() {
            let csr_header = new fabric.Text("📂 CSRs", {
                  top: 10,
                  left: 10,
                  fill: "white",
                  fontSize: 18,
                  fontWeight: 800,
                  fontFamily: "monospace"
               })
            let csr_objs = {}
            let csr_boxes = {}
            m4_csr_viz_init_each
            return {...csr_objs, ...csr_boxes, csr_header}
         },
         render() {
            m4_csr_viz_render_each
         }

\TLV instruction(_where)
   ?$valid_decode
      // For debug.
      $mnemonic[10*8-1:0] = m4_mnemonic_expr "ILLEGAL   ";
      `BOGUS_USE($mnemonic)
   \viz_js
      box: {left: 0, top: 0,
         strokeWidth: 0
      },
      init() {
         //debugger
         let decode_header = new fabric.Text("⚙️ Instruction", {
            top: 15,
            left: 103 + 605 + 20 -6,
            fill: "maroon",
            fontSize: 18,
            fontWeight: 800,
            fontFamily: "monospace"
         })
         let decode_box = new fabric.Rect({
            top: 10,
            left: 103 + 605 -6,
            fill: "#f8f0e8",
            width: 230,
            height: 160,
            stroke: "#ff8060"
         })
         return {decode_box, decode_header}
      },
      where: {_where},
      render() {
         //debugger
         objects = {}
         //
         // PC instr_mem pointer
         //
         let pc = '$Pc'.asInt(-1)
         let commit = '$commit'.asBool(false)
         let color = !commit                ? "gray" :
                                              "blue"
         objects.pc_pointer = new fabric.Text("👉", {
            top: 60 + 18 * pc,
            left: 335,
            fill: color,
            fontSize: 14,
            fontFamily: "monospace",
            opacity: commit ? 1 : 0.5
         })
         if ('$second_issue'.asBool(false)) {
            let second_issue_pc = '/orig_inst$pc'.asInt(-1)
            objects.second_issue_pointer = new fabric.Text("👉🏿", {
               top: 60 + 18 * pc,
               left: 335,
               fill: color,
               fontSize: 14,
               fontFamily: "monospace",
               opacity: 0.75
            })
         }
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
         //})
         
         //
         // Instruction with values.
         //
         m4_ifelse_block(m5_ISA, ['MINI'], ['
            let str = '$dest_char'.asString("?")
            str += "(" + ('$dest_valid'.asBool(false) ? '$rslt'.asInt(NaN) : "---") + ")\n ="
            str += '/src[1]$char'.asString("?")
            str += "(" + ('/src[1]$valid'.asBool(false) ? '/src[1]$value'.asInt(NaN) : "--") + ")\n   "
            str += '/op$char'.asString("-")
            str += '/src[2]$char'.asString("?")
            str += "(" + ('/src[2]$valid'.asBool(false) ? '/src[2]$value'.asInt(NaN) : "--") + ")"
         '], m5_ISA, ['RISCV'], ['
            let regStr = (type_char, valid, regNum, regValue) => {
               return type_char + (valid ? `${regNum} (${regValue})` : `X`)
            }
            let srcStr = (src) => {
               let ret = ""
               if ((src < 3) &&
                   '/src[src]$unconditioned_is_reg'.asBool(false)) {
                  ret += `\n      ${regStr("x", true, '/src[src]$unconditioned_reg'.asInt(NaN),     '/src[src]$unconditioned_reg_value'.asInt(NaN))}`
               }
               m4_ifelse_block(m5_EXT_F, 1, ['
               if ('/fpu/src[src]$unconditioned_is_reg'.asBool(false)) {
                  ret += `\n      ${regStr("f", true, '/fpu/src[src]$unconditioned_reg'.asInt(NaN), '/fpu/src[src]$unconditioned_reg_value'.asInt(NaN))}`
               }
               '])
               return ret
            }
            let dest_reg_valid = '$dest_reg_valid'.asBool(false)
            let str = `${regStr("x", dest_reg_valid, '$raw_rd'.asInt(NaN), '$rslt'.asInt(NaN))}\n`
            m4_ifelse_block(m5_EXT_F, 1, ['
            let dest_fpu_reg_valid = '/fpu$dest_reg_valid'.asBool(false)
            if (dest_fpu_reg_valid) {
               str = `${regStr("f", dest_fpu_reg_valid, '$raw_rd'.asInt(NaN), '$rslt'.asInt(NaN))}\n`
            }
            '])
            str += `  = ${'$mnemonic'.asString("?")}${srcStr(1)}${srcStr(2)}${srcStr(3)}`
            if ('$imm_valid'.asBool()) {
               str += `\n      i[${'$imm_value'.asInt(NaN)}]`
            }
         '], m5_ISA, ['MIPSI'], ['
            // TODO: Almost same as RISC-V. Avoid cut-n-paste.
            let regStr = (valid, regNum, regValue) => {
               return valid ? `x${regNum} (${regValue})` : `xX`
            }
            let srcStr = (src) => {
               return '/src[src]$unconditioned_is_reg'.asBool(false)
                          ? `\n      ${regStr(true, '/src[src]$unconditioned_reg'.asInt(NaN), '/src[src]$unconditioned_reg_value'.asInt(NaN))}`
                          : ""
            }
            let str = `${regStr(dest_reg_valid, '$dest_reg'.asInt(NaN), '$rslt'.asInt(NaN))}\n` +
                      `  = ${'$raw_opcode'.asInt()}${srcStr(1)}${srcStr(2)}\n` +
                      ('$imm_valid` ? `i[${'$imm_value'.asInt(NaN)}]` : ""
         '], ['
         '])
         // srcX Arrow function
         newSrcArrow = function(name, fp, addr, valid, pos) {
            if (valid) {
               objects[name + "_arrow"] = new fabric.Line([965 + (fp ? m5_VIZ_MEM_LEFT_ADJUST : 0), 17 * addr + 96, 830, 96 + 18 * pos], {
                  stroke: "#b0c8df",
                  strokeWidth: 2
               })
            }
         }
         objects.pc_arrow = new fabric.Line([10+620, 18 * pc + 66, 86+620, -8+66], {
            stroke: "#b0c8df",
            strokeWidth: 2
         })
         // Create rsX arrows for int and FP regs.
         let reg_addr1 = '$raw_rs1'.asInt()
         let reg_addr2 = '$raw_rs2'.asInt()
         let reg_addr3 = '$raw_rs3'.asInt()
         let rs1_valid = '/src[1]$unconditioned_is_reg'.asBool()
         let rs2_valid = '/src[2]$unconditioned_is_reg'.asBool()
         let rs3_valid = false
         let fpu_rs1_valid = false
         let fpu_rs2_valid = false
         let fpu_rs3_valid = false
         newSrcArrow("rs1", false, reg_addr1, rs1_valid, 1)
         newSrcArrow("rs2", false, reg_addr2, rs2_valid, 2)
         let src1_value = '/src[1]$unconditioned_reg_value'.asInt()
         let src2_value = '/src[2]$unconditioned_reg_value'.asInt()
         let src3_value = 0
         let dest_reg = '$dest_reg'.asInt(0)
         let valid_dest_reg_valid = '$valid_dest_reg_valid'.asBool(false)
         let valid_dest_fpu_reg_valid = false
         m4_ifelse_block(m5_EXT_F, 1, ['
         fpu_rs1_valid = '/fpu/src[1]$unconditioned_is_reg'.asBool()
         fpu_rs2_valid = '/fpu/src[2]$unconditioned_is_reg'.asBool()
         fpu_rs3_valid = '/fpu/src[3]$unconditioned_is_reg'.asBool()
         let dest_fpu_reg = '/fpu$dest_reg'.asInt(0)
         newSrcArrow("fp_rs1", true, reg_addr1, fpu_rs1_valid, 1)
         newSrcArrow("fp_rs2", true, reg_addr2, fpu_rs2_valid, 2)
         newSrcArrow("fp_rs3", true, reg_addr3, fpu_rs3_valid, 3)
         if (fpu_rs1_valid) {src1_value = '/fpu/src[1]$unconditioned_reg_value'.asInt()}
         if (fpu_rs2_valid) {src2_value = '/fpu/src[2]$unconditioned_reg_value'.asInt()}
         if (fpu_rs3_valid) {src3_value = '/fpu/src[3]$unconditioned_reg_value'.asInt()}
         valid_dest_fpu_reg_valid = '/fpu$valid_dest_reg_valid'.asBool(false)
         '])
         let the_dest_reg = valid_dest_fpu_reg_valid ? dest_fpu_reg : dest_reg
         // rd Arrow
         let second_issue = '$second_issue'.asBool()
         objects.rd_arrow = new fabric.Line([780, 76, (valid_dest_fpu_reg_valid ? 965 + m5_VIZ_MEM_LEFT_ADJUST : 965), 17 * the_dest_reg + 96], {
            stroke: '$second_issue'.asBool() ? "#c03050" : commit ? "#a0dfff" : "#d0d0d0",
            strokeWidth: 3,
            visible: valid_dest_reg_valid || valid_dest_fpu_reg_valid
         })
         // load arrow
         let ld_st_addr = ('$addr'.asInt() / 4)
         let ld_valid = '$valid_ld'.asBool(false)
         objects.ld_arrow = new fabric.Line([1165 + m5_VIZ_MEM_LEFT_ADJUST, (17 * ld_st_addr) + 96, 1080 + (valid_dest_fpu_reg_valid ? m5_VIZ_MEM_LEFT_ADJUST : 0), 96 + 17 * the_dest_reg], {
            stroke: "#c03050",
            strokeWidth: 3,
            visible: ld_valid
         })
         // store arrow
         let st_valid = '$valid_st'.asBool()
         objects.st_arrow = new fabric.Line(
            [830, 132, 1165 + m5_VIZ_MEM_LEFT_ADJUST, 17 * ld_st_addr + 96], {
            stroke: "#a0dfff",
            strokeWidth: 3,
            visible: st_valid
         })
         m4_ifelse_block(m5_FORMAL, 1, ,m5_IMEM_STYLE, EXTERN, , ['
         //
         let $instr_str = '|fetch/instr_mem[pc]$instr_str'  // pc could be invalid, so make sure this isn't null.
         let instr_string = $instr_str ? $instr_str.asString("?") : "?"
         objects.fetch_instr_viz = new fabric.Text(instr_string, {
                  top: 18 * pc + 60,
                  left: 361,
                  fill: color,
                  fontSize: 14,
                  fontFamily: "monospace"
         })
         //
         objects.fetch_instr_viz.animate({top: 50, left: 710}, {
              onChange: this.global.canvas.renderAll.bind(this.global.canvas),
              duration: 500
         })
         '])
         //
         objects.instr_with_values = new fabric.Text(str, {
            top: 70,
            left: 730,
            fill: color,
            fontSize: 14,
            fontFamily: "monospace"
         })
         //
         objects.src1_value_viz = new fabric.Text(src1_value.toString(), {
            fill: color,
            fontSize: 14,
            fontFamily: "monospace",
            fontWeight: 800,
            visible: false
         })
         if (rs1_valid || fpu_rs1_valid) {
            setTimeout(() => {
               objects.src1_value_viz.set({left: 965 + (rs1_valid ? 0 : m5_VIZ_MEM_LEFT_ADJUST),
                                           top: 17 * reg_addr1 + 96,
                                           visible: true})
               objects.src1_value_viz.animate({left: 830, top: 17 * 1 + 90}, {
                    onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                    duration: 500
               })
               setTimeout(() => {
                  objects.src1_value_viz.set({visible: false})
                  this.global.canvas.renderAll.bind(this.global.canvas)()
               }, 500)
            }, 500)
         }
         objects.src2_value_viz = new fabric.Text(src2_value.toString(), {
            fill: color,
            fontSize: 14,
            fontFamily: "monospace",
            fontWeight: 800,
            visible: false
         })
         let src2_being_stored = '$valid_decode'.asBool(false) && '$st'.asBool(false) && commit; // Animate src2 value being stored.
         if (rs2_valid || fpu_rs2_valid) {
               setTimeout(() => {
               objects.src2_value_viz.set({left: 965 + (rs2_valid ? 0 : m5_VIZ_MEM_LEFT_ADJUST),
                                           top: 17 * reg_addr2 + 96,
                                           visible: true})
               objects.src2_value_viz.set({visible: true})
               objects.src2_value_viz.animate({left: 830, top: 17 * 2 + 90}, {
                    onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                    duration: 500
               })
               setTimeout(() => {
                  if (src2_being_stored) {
                     // Animate src2 value being stored.
                     objects.src2_value_viz.animate({left: 1165 + m5_VIZ_MEM_LEFT_ADJUST, top: 17 * ld_st_addr + 96}, {
                        onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                        duration: 500
                     })
                     setTimeout(() => {
                        objects.src2_value_viz.set({visible: false})
                        this.global.canvas.renderAll.bind(this.global.canvas)()
                     }, 500)
                  } else {
                     // Hide src2 value.
                     objects.src2_value_viz.set({visible: false})
                     this.global.canvas.renderAll.bind(this.global.canvas)()
                  }
               }, 500)
            }, 500)
         }
         objects.src3_value_viz = new fabric.Text(src3_value.toString(), {
            fill: color,
            fontSize: 14,
            fontFamily: "monospace",
            fontWeight: 800,
            visible: false
         })
         if (fpu_rs3_valid) {
            setTimeout(() => {
               objects.src3_value_viz.set({left: 965 + (rs3_valid ? 0 : m5_VIZ_MEM_LEFT_ADJUST),
                                           top: 17 * reg_addr + 96,
                                           visible: true})
               objects.src3_value_viz.animate({left: 830, top: 17 * 3 + 90}, {
                    onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                    duration: 500
               })
               setTimeout(() => {
                  objects.src3_value_viz.set({visible: false})
                  this.global.canvas.renderAll.bind(this.global.canvas)()
               }, 500)
            }, 500)
         }
         let res_value = '$rslt'.asInt().toString(16)
         objects.result_viz = new fabric.Text(res_value, {
            top: 76,
            left: 780,
            fill: color,
            fontSize: 14,
            fontFamily: "monospace",
            fontWeight: 800,
            visible: false
         })
         if ((valid_dest_reg_valid || valid_dest_fpu_reg_valid) && commit) {
            setTimeout(() => {
               objects.result_viz.set({visible: true})
               objects.result_viz.animate({left: (valid_dest_fpu_reg_valid ? 965 + m5_VIZ_MEM_LEFT_ADJUST : 965), top: 17 * dest_reg + 90}, {
                 onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                 duration: 500
               })
               setTimeout(() => {
                  objects.result_viz.set({visible: false})
                  this.global.canvas.renderAll.bind(this.global.canvas)()
               }, 500)
            }, 1000)
         }
         return Object.values(objects)
      }
   

\TLV memory_viz(/_bank_size, /_mem_size, _where_)
   m4+ifelse(m5_DMEM_STYLE, ARRAY,
      \TLV
         /_mem_size
            \viz_js
               all: {
                  box: {
                     fill: "#208028",
                     width: 190,
                     height: 650,
                     stroke: "black",
                     strokeWidth: 0
                  },
                  init() {
                     let dmem_header = new fabric.Text("🗃️ DMem (hex)", {
                        top: 10,
                        left: 10, // Center aligned
                        fontSize: 20,
                        fontWeight: 800,
                        fontFamily: "monospace",
                        fill: "white"
                     })
                     return {dmem_header}
                  },
               },
               where: {_where_},
               where0: {left: 10, top: 80},
               box: {
                     fill: "white",
                     width: 40,
                     height: 14,
                     strokeWidth: 0
                  },
               layout: {top: 17}, //vertically
               init() {
                  let index =
                     new fabric.Text(parseInt(this.getIndex()).toString() + ":", {
                        left: 10,
                        fontSize: 14,
                        fontFamily: "monospace"
                     })
                  return {index}
               }
         /_bank_size
            \viz_js
               box: {strokeWidth: 0},
               all: {
                  box: {
                        width: 190,
                        height: 650,
                        stroke: "black",
                        strokeWidth: 0
                       },
                  init() {
                     let bankname = new fabric.Text("bank", {
                        top: 40,
                        left: 100,
                        fontSize: 14,
                        fontWeight: 800,
                        fontFamily: "monospace",
                        fill: "black"
                     })
                     return {bankname}
                  }
               },
               where: {_where_},
               where0: {left: 150, top: 60},
               init() {
                  let banknum = new fabric.Text(String(this.scopes.bank.index), {
                     top: -19,
                     left: 10,
                     fontSize: 14,
                     fontWeight: 800,
                     fontFamily: "monospace",
                     fill: "black"
                  })
                  return {banknum}
               },
               render() {
                  // Update write address highlighting.
                  // (We record and clear the old highlighting (in this.fromInit()) so we don't have to render each instruction individually.)
                  // Unhighlight
                  let unhighlight_addr = this.highlighted_addr
                  let unhighlight = typeof unhighlight_addr != "undefined"
                  let valid_ld = '/instr$valid_ld'.asBool(false)
                  let valid_st = '/instr$valid_st'.asBool(false)
                  let st_mask = '/instr$st_mask'.asInt(0)
                  let addr = '/instr$addr'.asInt(-1) >> 2 // (word-address)
                  let color = valid_st ? "#b0ffff" : "#b0ffff"
                  let highlight = (valid_ld || valid_st) && (addr >= m5_DATA_MEM_WORDS_MIN && addr <= m5_DATA_MEM_WORDS_MAX)
                  // Re-highlight index.
                  if (unhighlight) {
                     this.scopes.instr.children.mem.children[unhighlight_addr].initObjects.box.set({fill: "white"})
                  }
                  if (highlight) {
                     this.scopes.instr.children.mem.children[addr].initObjects.box.set({fill: color})
                  }
                  for (let i = 0; i < 4; i++) {
                     if (unhighlight) {
                        this.scopes.instr.children.bank.children[i].children.mem.children[unhighlight_addr].initObjects.box.set({fill: "white"})
                     }
                     if (highlight && ((st_mask >> i) & 1 != 0)) {
                        this.scopes.instr.children.bank.children[i].children.mem.children[addr].initObjects.box.set({fill: color})
                     }
                  }
                  this.highlighted_addr = highlight ? addr : undefined
               },
               layout: {left: -30},
            /_mem_size
               \viz_js
                  box: {
                        fill: "white",
                        width: 30,
                        height: 16,
                        stroke: "#208028",
                        strokeWidth: 0.75
                       },
                  layout: {top: 17},
                  init() {
                     let data = new fabric.Text("", {
                        top: 2,
                        left: 6,
                        fontSize: 14,
                        fontFamily: "monospace"
                     })
                     return {data}
                  },
                  render() {
                     let mod = ('/instr$valid_st'.asBool(false)) && ((('/instr$st_mask'.asInt(-1) >> this.scopes.bank.index) & 1) == 1) && ('/instr$addr'.asInt(-1) >> m5_SUB_WORD_BITS == this.getIndex()) // selects which bank to write on
                     //let oldValStr = mod ? `(${'$Value'.asInt(NaN).toString(16)})` : "" // old value for dmem
                     this.getInitObject("data").set({text: '$Value'.step(1).asInt(NaN).toString(16).padStart(2,"0")})
                     this.getInitObject("data").set({fill: mod ? "blue" : "black"})
                  }
      )

\TLV layout_viz(_where_, _fill_color) 
   \viz_js
      //Main layout
      box: {
            fill: _fill_color,
            strokeWidth: 0
           },
      where: {_where_},
         
//////// VIZUALIZING THE MAIN CPU //////////////
\TLV cpu_viz(/_des_pipe, _fill_color)
   /* CPU_VIZ HERE */
   m4_def(viz_logic_macro_name, m5_isa['_viz_logic'])
   m5_def(COREOFFSET, 750)
   m5_def(ALL_TOP, -1000)
   m5_def(ALL_LEFT, -500)
   m4+m4_viz_logic_macro_name()
   /_des_pipe
      @m5_VIZ_STAGE
         m4+layout_viz(['left: 0, top: 0, width: 451, height: 251'], _fill_color)
         
         m4_ifelse(m5_FORMAL, 1, , ['m4+instruction_in_memory(/_des_pipe, ['left: 10, top: 10'])'])
            
         /instr
            m4+instruction(['left: 10, top: 0'])
            m4+registers(/instr, int, Int RF, , 2, ['left: 350 + 605, top: 10'])
            m4+register_csr(/regcsr, ['left: 103 + 605, top: 190'])
            m4+pipeline_control_viz(/pipe_ctrl, ['left: 103 + 605, top: 265 + 18 * m4_num_csrs, width: 220, height: 330'])
            m4+ifelse(m5_EXT_F, 1,
               \TLV
                  /fpu
                     m4+registers(/fpu, fp, FP RF, fpu_, 3, ['left: 955 + m5_VIZ_MEM_LEFT_ADJUST, top: 10'])
               )
            m4+memory_viz(/bank[m4_eval(m5_ADDRS_PER_WORD-1):0] , /mem[m5_DATA_MEM_WORDS_RANGE], ['left: 10 + (550 + 605) -10 + m4_ifelse(m5_EXT_F, 1, ['m5_VIZ_MEM_LEFT_ADJUST'], 0), top: 10'])
   m4_ifelse_block(m5_FORMAL, 1, ['
   m4+riscv_formal_viz(['rvfi_testbench'], ['left: 450, top: 50, width: 150, height: 130'])
   '])
   
// Visualization for RISCV Formal.
// Params:
//   _root: The root path containing "checker_inst" and "wrapper".
\TLV riscv_formal_viz(_root, _where)
   /rvfi_viz
      \viz_js
         box: {left: 0, top: 0, width: 200, height: 43 + 10 * 20, strokeWidth: 0},
         init() {
            // Everything in render() because content is dynamic based on signals in the waveform.
         },
         render() {
            //debugger
            let ret = {}
            // Determine if any tests were run by looking for a unique signal for each test category.
            // This section could be in init(), except for this test for signals.
            testSig = (name) => {
               let sig = this.sigVal(`_root.checker_inst.${name}`, 0)
               return sig ? sig.exists() : false
            }
            let insn_test      = testSig("spec_rd_addr")
            let pc_test        = testSig("expect_pc")
            let reg_test       = testSig("register_shadow")
            let liveness_test  = testSig("found_next_insn")
            let causal_test    = testSig("found_non_causal")
            
            this.sigs = {
               order: {},
               halt: {},
               intr: {},
               insn: {},
               trap: {},
               mode: {},
               ixl: {},
               pc_rdata: {},
               pc_wdata: {},
               rd_addr: {},
               rd_wdata: {},
               rs1_addr: {},
               rs1_rdata: {},
               rs2_addr: {},
               rs2_rdata: {},
               mem_addr: {},
               mem_wdata: {},
               mem_wmask: {},
               mem_rdata: {},
               mem_rmask: {},
            }
            let rvfiLeft = 50
            let pos = 0
            for (sigName in this.sigs) {
               let top = 29 + 10 * pos
               let obj = new fabric.Group([
                  // Signal name.
                  new fabric.Text(sigName,
                       {left: rvfiLeft + 2, top: top,
                        fontSize: 6, fontWeight: 500, fontFamily: "roboto",
                        fill: "black",
                        originX: "left", originY: "center"}),
                  // Value
                  new fabric.Text("?",
                       {left: rvfiLeft - 3, top: top + 0.4,
                        fontSize: 3.5, fontWeight: 800, fontFamily: "monospace",
                        fill: "lightgray",
                        originX: "right", originY: "bottom"}),
                  // Expected
                  new fabric.Text("",
                       {left: rvfiLeft - 3, top: top + 0.7,
                        fontSize: 3.5, fontWeight: 800, fontFamily: "monospace",
                        fill: "red",
                        originX: "right", originY: "top"}),
                  new fabric.Line([rvfiLeft - 20, top, rvfiLeft, top], {stroke: "black"}),
               ])
               ret[sigName] = obj
               this.sigs[sigName].obj = obj
               pos++
            }
            ret.rvfiHeading = new fabric.Text("RVFI", {
                 left: rvfiLeft + 75, top: 15,
                 fontSize: 8, fontWeight: 800, fontFamily: "roboto",
                 fill: "black",
                 originX: "center"})
            ret.rvfiBox = new fabric.Rect({
                 fill: "#00000080",
                 stroke: "black", strokeWidth: 1,
                 left: rvfiLeft, top: 10, width: 150, height: 23 + Object.keys(this.sigs).length * 10,
            })
            
            // Render
            
            // Update RVFI inputs.
            let valid = false
            let check = false
            try {
               valid = this.sigVal(`_root.checker_inst.rvfi_valid`).asBool()
               check = this.sigVal(`_root.checker_inst.check`).asBool()
            } catch(e) {
               console.log("Signals not found.")
            }
            for (sigName in this.sigs) {
               let rvfi = this.sigVal(`_root.checker_inst.rvfi_${sigName}`)
               this.sigs[sigName].rvfi = rvfi
               let spec = this.sigVal(`_root.checker_inst.spec_${sigName}`)
               spec = !spec ? this.sigVal(`_root.checker_inst.expect_${sigName}`) : spec;
               rvfi = rvfi ? rvfi.asHexStr() : "?"
               this.sigs[sigName].hex = rvfi
               spec = spec ? spec.asHexStr() : "?"
               let mismatch = spec != rvfi
               let grp = ret[sigName].getObjects()
               // value
               grp[1].set({
                    text: rvfi,
                    fill: valid ? "blue" : "lightgray",
               })
               // expected
               if (mismatch) {
                  grp[2].set({
                       text: spec,
                       fill: "red",
                  })
               }
            }
            
            let rs1Color = "blue"
            let rs2Color = "blue"
            
            ret.rvfiBox.set({fill: check ? "transparent" : "#00000080"})
            if (insn_test) {
            }
            if (pc_test) {
               let check = this.sigVal(`_root.checker_inst.check`).asBool()
               let expect_pc_valid = this.sigVal(`_root.checker_inst.expect_pc_valid`).asBool()
               let expect_pc = this.sigVal(`_root.checker_inst.expect_pc`).asInt()
               let pc_rdata  = this.sigVal(`_root.checker_inst.pc_rdata`).asInt()
            }
            if (reg_test) {
               let register_written = this.sigVal(`_root.checker_inst.register_written`).asBool()
               let register_index = this.sigVal(`_root.checker_inst.register_index`).asInt()
               let register_shadow = this.sigVal(`_root.checker_inst.register_shadow`).asHexStr()
               let shadow_str = `Shadow x${register_index}: 32''h${register_shadow}`
               ret.reg_shadow = new fabric.Text(shadow_str, {
                 left: rvfiLeft + 37, top: 90,
                 fontSize: 9, fontWeight: 800, fontFamily: "roboto",
                 fill: register_written ? "black" :
                                          "gray",
               })
               if (register_written &&
                   register_index == this.sigs.rs1_addr.rvfi.asInt() &&
                   register_shadow != this.sigs.rs1_rdata.hex) {
                  rs1Color = "red"
               }
               if (register_written &&
                   register_index == this.sigs.rs2_addr.rvfi.asInt() &&
                   register_shadow != this.sigs.rs2_rdata.hex) {
                  rs2Color = "red"
               }
            }
            if (liveness_test) {
            }
            if (causal_test) {
               let check = this.sigVal(`_root.checker_inst.check`, 0).asBool()
            }
            
            // RVFI Instruction Representation
            let rd_addr = this.sigs.rd_addr.rvfi.asInt()
            rd_addr = rd_addr === null ? "<missing>" : rd_addr.toString()
            let rs1_addr = this.sigs.rs1_addr.rvfi.asInt()
            rs1_addr = rs1_addr === null ? "<missing>" : rs1_addr.toString()
            let rs2_addr = this.sigs.rs2_addr.rvfi.asInt()
            rs2_addr = rs2_addr === null ? "<missing>" : rs2_addr.toString()
            let rdStr = `rd: x${rd_addr} <= 32''h${this.sigs.rd_wdata.hex}`
            let rs1Str = `rs1: x${rs1_addr} = 32''h${this.sigs.rs1_rdata.hex}`
            let rs2Str = `rs2: x${rs2_addr} = 32''h${this.sigs.rs2_rdata.hex}`
            ret.rvfiRd = new fabric.Text(rdStr, {
                 left: rvfiLeft + 37, top: 120,
                 fontSize: 9, fontWeight: 800, fontFamily: "roboto",
                 fill: "blue",
            })
            ret.rvfiRs1 = new fabric.Text(rs1Str, {
                 left: rvfiLeft + 45, top: 128,
                 fontSize: 9, fontWeight: 800, fontFamily: "roboto",
                 fill: rs1Color,
            })
            ret.rvfiRs2 = new fabric.Text(rs2Str, {
                 left: rvfiLeft + 45, top: 136,
                 fontSize: 9, fontWeight: 800, fontFamily: "roboto",
                 fill: rs2Color,
            })
            
            return Object.values(ret)
         },
         where: {_where}
   
   
   
//////// VIZUALIZING THE INSERTION RING //////////////
\TLV ring_viz(/_name)
   m4_define(['m5_RINGVIZ_REF_TOP'],-100)
   m4_define(['m5_RINGVIZ_REF_LEFT'],700)
   m4_define(['m5_RINGVIZ_GLOBAL_TOP'], m5_ALL_TOP + m5_RINGVIZ_REF_TOP)
   m4_define(['m5_RINGVIZ_GLOBAL_LEFT'], m5_ALL_LEFT + m5_RINGVIZ_REF_LEFT)
   |egress_out
      @1
         /flit
            $src[1:0] = #core;
            $uid[31:0] = {$src, *cyc_cnt[29:0]};  // Attach Unique Identifier along with transaction which enters into the ring
   |ringviz
      @0
         // Bunch of define statements parameterizing the VIZ
         m4_define(['m5_NODES_RADIUS'],3)
         m4_define(['m5_NODES_COLOR'],"#208028")
         m4_define(['m5_AVAIL_COLOR'],"blue")
         m4_define(['m5_BLOCKED_COLOR'],"red")
         m4_define(['m5_INVAILD_COLOR'],"grey")
         m4_define(['m5_EGRESS_OUT_TOP'], 200 + m5_RINGVIZ_GLOBAL_TOP)
         m4_define(['m5_EGRESS_OUT_LEFT'],515 + m5_RINGVIZ_GLOBAL_LEFT)
         m4_define(['m5_FIFO_IN_TOP'],100 + m5_RINGVIZ_GLOBAL_TOP)
         m4_define(['m5_FIFO_IN_LEFT'],615 + m5_RINGVIZ_GLOBAL_LEFT)
         m4_define(['m5_FIFO_OUT_TOP'], 600 + m5_RINGVIZ_GLOBAL_TOP)
         m4_define(['m5_FIFO_OUT_LEFT'],615 + m5_RINGVIZ_GLOBAL_LEFT)
         m4_define(['m5_RG_TOP'],650 + m5_RINGVIZ_GLOBAL_TOP)
         m4_define(['m5_RG_LEFT'],765 + m5_RINGVIZ_GLOBAL_LEFT)
         m4_define(['m5_INGRESS_IN_TOP'],25 + m5_RINGVIZ_GLOBAL_TOP)
         m4_define(['m5_INGRESS_IN_LEFT'],515 + m5_RINGVIZ_GLOBAL_LEFT)
         m4_define(['m5_ARRIVING_TOP'],0 + m5_RINGVIZ_GLOBAL_TOP)
         m4_define(['m5_ARRIVING_LEFT'],765 + m5_RINGVIZ_GLOBAL_LEFT)
         m4_define(['m5_DEFLECTED_TOP'],75 + m5_RINGVIZ_GLOBAL_TOP)
         m4_define(['m5_DEFLECTED_LEFT'],665 + m5_RINGVIZ_GLOBAL_LEFT)
         m4_define(['m5_ENTRY_START_TOP'],150 + m5_RINGVIZ_GLOBAL_TOP)
         m4_define(['m5_ENTRY_START_LEFT'],615 + m5_RINGVIZ_GLOBAL_LEFT)
         m4_define(['m5_ENTRY_START_SPACE_TOP'],50)

         /skid1
            $egress_is_head = ! *reset && (/top/core|egress_out>>1$valid_head);
            $egress_is_tail = ! *reset && (/top/core|egress_out>>1$valid_tail);
            $egress_flit_size = $egress_is_head ? 1'b1 : >>1$egress_is_tail ? 1'b0 : $RETAIN;
            $egress_flit[31:0] = (! *reset) ? (/top/core|egress_out/flit>>1$flit) : '0;
            $vc[m5_VC_INDEX_RANGE] = $egress_is_head ? $egress_flit[m5_FLIT_VC_RANGE] : $RETAIN;
            //$valid = 1;
   \viz_alpha
      initEach() {
         this.global.transObj = {counting: 0}
         return {
            objects : {
            },
            transObj: {}
         }
      },
      renderEach() {
         for (const uid in this.fromInit().transObj) {
            const trans = this.fromInit().transObj[uid]
            //trans.wasVisible = trans.visible
            trans.visible = false
      }
      if (typeof this.getContext().preppedTrace === "undefined") {
         let $egress_flit_size = '/top/core|ringviz/skid1<>0$egress_flit_size'.goTo(-1)
         let $uid = '/top/core|egress_out/flit>>1$uid'
         let $data = '/top/core|ringviz/skid1<>0$egress_flit'
         let $is_head = '/top/core|ringviz/skid1<>0$egress_is_head'
         let $is_tail = '/top/core|ringviz/skid1<>0$egress_is_tail'
         let $vc = '/top/core|ringviz/skid1<>0$vc'
         while ($egress_flit_size.forwardToValue(1)) {
            let uid  = $uid .goTo($egress_flit_size.getCycle()).asInt()
            let data = $data.goTo($egress_flit_size.getCycle()).asInt()
            let is_head = $is_head.goTo($egress_flit_size.getCycle()).asBool()
            let is_tail = $is_tail.goTo($egress_flit_size.getCycle()).asBool()
            let vc = $vc.goTo($egress_flit_size.getCycle()).asBool()
            let ring_scope = this.getScope("name")
            let transRect = new fabric.Rect({
               width: 45,
               height: 20,
               fill: vc ? "blue" : "orange",
               left: 0,
               top: 0
            })
            let transText = new fabric.Text(`${data.toString(16)}`, {
               left: 1,
               top: 0,
               fontSize: 24,
               fill: "white"
            })
            let transCircle = new fabric.Circle({
               left: 10+20,
               top: 0,
               radius: 1,
               fill: is_head ? "pink" : is_tail ? "blue" : "#208028",
            })
            let transObj = new fabric.Group(
               [transRect,
                transText,
                transCircle
               ],
               {width: 45,
                height: 20,
                visible: false}
            )
            context.global.canvas.add(transObj)
            this.global.transObj[uid] = transObj
         }
         this.getContext().preppedTrace = true
      }
      }
   /skid1
      \viz_alpha
         initEach() {
            let egress_out = new fabric.Circle({
               top: m5_EGRESS_OUT_TOP + (this.getScope("core").index * m5_COREOFFSET),
               left: m5_EGRESS_OUT_LEFT,
               radius: m5_NODES_RADIUS,
               fill: m5_NODES_COLOR
            })
            let fifo_in = new fabric.Circle({
               top: m5_FIFO_IN_TOP + (this.getScope("core").index * m5_COREOFFSET),
               left: m5_FIFO_IN_LEFT,
               radius: m5_NODES_RADIUS,
               fill: m5_NODES_COLOR
            })
            return {objects : {egress_out, fifo_in}}
         },
         renderEach() {
            var arriving_ingress_avail = '/top/core|ingress_in<>0$avail'.asBool();
            var arriving_ingress_blocked = '/top/core|ingress_in<>0$blocked'.asBool();
            let arriving_ingress_arrow = new fabric.Line([m5_INGRESS_IN_LEFT, m5_INGRESS_IN_TOP + (this.getScope("core").index * m5_COREOFFSET), m5_ARRIVING_LEFT, m5_ARRIVING_TOP + (this.getScope("core").index * m5_COREOFFSET)], {
               stroke: arriving_ingress_blocked ? m5_BLOCKED_COLOR : arriving_ingress_avail ? m5_AVAIL_COLOR : m5_INVAILD_COLOR,
               strokeWidth: 2,
               visible: 1
            })
            var arriving_deflected_avail = '/top/core|rg_deflected<>0$avail'.asBool();
            var arriving_deflected_blocked = '/top/core|rg_deflected<>0$blocked'.asBool();
            let arriving_deflected_arrow = new fabric.Line([m5_DEFLECTED_LEFT, m5_DEFLECTED_TOP + (this.getScope("core").index * m5_COREOFFSET), m5_ARRIVING_LEFT, m5_ARRIVING_TOP + (this.getScope("core").index * m5_COREOFFSET)], {
               stroke: arriving_deflected_blocked ? m5_BLOCKED_COLOR : arriving_deflected_avail ? m5_AVAIL_COLOR : m5_INVAILD_COLOR,
               strokeWidth: 2,
               visible: 1
            })
            var arriving_rg_avail = '/top/core|rg_not_deflected<>0$avail'.asBool();
            var arriving_rg_blocked = '/top/core|rg_not_deflected<>0$blocked'.asBool();
            let arriving_rg_arrow = new fabric.Line([m5_RG_LEFT, m5_RG_TOP + (this.getScope("core").index * m5_COREOFFSET), m5_ARRIVING_LEFT, m5_ARRIVING_TOP + (this.getScope("core").index * m5_COREOFFSET)], {
               stroke: arriving_rg_blocked ? m5_BLOCKED_COLOR : arriving_rg_avail ? m5_AVAIL_COLOR : m5_INVAILD_COLOR,
               strokeWidth: 2,
               visible: 1
            })
            var deflected_fifoin_avail = '/top/core|rg_deflected_st1<>0$avail'.asBool();
            var deflected_fifoin_blocked = '/top/core|rg_deflected_st1>>1$blocked'.asBool();
            let deflected_fifoin_arrow = new fabric.Line([m5_FIFO_IN_LEFT, m5_FIFO_IN_TOP + (this.getScope("core").index * m5_COREOFFSET), m5_DEFLECTED_LEFT, m5_DEFLECTED_TOP + (this.getScope("core").index * m5_COREOFFSET)], {
               stroke: deflected_fifoin_blocked ? m5_BLOCKED_COLOR : deflected_fifoin_avail ? m5_AVAIL_COLOR : m5_INVAILD_COLOR,
               strokeWidth: 2,
               visible: 1
            })
            var egressout_fifoin_avail = '/top/core|rg_node_to_fifo<>0$avail'.asBool();
            var egressout_fifoin_blocked = '/top/core|rg_node_to_fifo<>0$blocked'.asBool();
            let egressout_fifoin_arrow = new fabric.Line([m5_FIFO_IN_LEFT, m5_FIFO_IN_TOP + (this.getScope("core").index * m5_COREOFFSET), m5_EGRESS_OUT_LEFT, m5_EGRESS_OUT_TOP + (this.getScope("core").index * m5_COREOFFSET)], {
               stroke: egressout_fifoin_blocked ? m5_BLOCKED_COLOR : egressout_fifoin_avail ? m5_AVAIL_COLOR : m5_INVAILD_COLOR,
               strokeWidth: 2,
               visible: 1
            })
            var rg_fifoout_avail = '/top/core|rg_fifo_inj<>0$avail'.asBool();
            var rg_fifoout_blocked = '/top/core|rg_fifo_inj<>0$blocked'.asBool();
            let rg_fifoout_arrow = new fabric.Line([m5_RG_LEFT, m5_RG_TOP + (this.getScope("core").index * m5_COREOFFSET), m5_FIFO_OUT_LEFT, m5_FIFO_OUT_TOP + (this.getScope("core").index * m5_COREOFFSET)], {
               stroke: rg_fifoout_blocked ? m5_BLOCKED_COLOR : rg_fifoout_avail ? m5_AVAIL_COLOR : m5_INVAILD_COLOR,
               strokeWidth: 2,
               visible: 1
            })
            let uid = '/top/core|egress_out/flit>>1$uid'.asInt()
            let trans = this.global.transObj[uid]
            if (trans) {
               /*trans.set("visible", true)
               if ('/top/core|rg_fifo_in<>0$accepted'.asBool()) {
                  let core = this.getScope("core").index;
                  trans.set("top", m5_EGRESS_OUT_TOP + (this.getScope("core").index * m5_COREOFFSET))
                  trans.set("left", m5_EGRESS_OUT_LEFT)
                  trans.set("opacity", 0)
                  trans.animate({top: m5_FIFO_IN_TOP + (core * m5_COREOFFSET), left: m5_FIFO_IN_LEFT, opacity: 1}, {
                              onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                              duration: 500})
               } else {
                  console.log(`Transaction ${uid} not found.`)
               }*/ 
            }
            return {objects: [arriving_ingress_arrow, arriving_deflected_arrow, arriving_rg_arrow, deflected_fifoin_arrow, egressout_fifoin_arrow, rg_fifoout_arrow]}
         }
   /skid2
      \viz_alpha
         initEach() {
            let deflected = new fabric.Circle({
               top: m5_DEFLECTED_TOP + (this.getScope("core").index * m5_COREOFFSET),
               left: m5_DEFLECTED_LEFT,
               radius: m5_NODES_RADIUS,
               fill: m5_NODES_COLOR
            })
            return {objects : {deflected}}
         },
         renderEach() {
            let uid = '/top/core|rg_deflected/flit>>1$uid'.asInt()
            let trans = this.global.transObj[uid]
            if (trans) {
               trans.set("visible", true)
               if ('/top/core|rg_fifo_in<>0$accepted'.asBool() && '/top/core|rg_deflected_st1>>1$accepted'.asBool()) {
                  let core = (m5_NUM_CORES > 1) ? this.getScope("core").index : 0;
                  trans.set("top", m5_DEFLECTED_TOP + (this.getScope("core").index * m5_COREOFFSET))
                  trans.set("left", m5_DEFLECTED_LEFT)
                  trans.set("opacity", 0)
                  trans.animate({top: m5_FIFO_IN_TOP + (core * m5_COREOFFSET), left: m5_FIFO_IN_LEFT, opacity: 1}, {
                              onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                              duration: 500})
               } else {
                  console.log(`Transaction ${uid} not found.`)
               }
            }
         }
   /fork1
      \viz_alpha
         initEach() {
            let ingress_in = new fabric.Circle({
               top: m5_INGRESS_IN_TOP + (this.getScope("core").index * m5_COREOFFSET),
               left: m5_INGRESS_IN_LEFT,
               radius: m5_NODES_RADIUS,
               fill: m5_NODES_COLOR
            })
            let arriving = new fabric.Circle({
               top: m5_ARRIVING_TOP + (this.getScope("core").index * m5_COREOFFSET),
               left: m5_ARRIVING_LEFT,
               radius: m5_NODES_RADIUS,
               fill: m5_NODES_COLOR
            })
            let deflected = new fabric.Circle({
               top: m5_DEFLECTED_TOP + (this.getScope("core").index * m5_COREOFFSET),
               left: m5_DEFLECTED_LEFT,
               radius: m5_NODES_RADIUS,
               fill: m5_NODES_COLOR
            })
            return {objects : {ingress_in, arriving, deflected}}
         },
         renderEach() {
            let uid = '/top/core|rg_arriving/flit<>0$uid'.asInt()
            let trans = this.global.transObj[uid]
            if (trans) {
               trans.set("visible", true)
               if ('/core|ingress_in<>0$trans_valid'.asBool()) {
                  let core = (m5_NUM_CORES > 1) ? this.getScope("core").index : 0;
                  trans.set("top", m5_ARRIVING_TOP + (this.getScope("core").index * m5_COREOFFSET))
                  trans.set("left", m5_ARRIVING_LEFT)
                  trans.set("opacity", 0)
                  trans.animate({top: m5_INGRESS_IN_TOP + (core * m5_COREOFFSET), left: m5_INGRESS_IN_LEFT, opacity: 1}, {
                                 onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                                 duration: 1000
                                 })
               }
               else if ('/top/core|rg_continuing<>0$accepted'.asBool() && '/top/core|rg_deflected<>0$accepted'.asBool()) {
                  let core = (m5_NUM_CORES > 1) ? this.getScope("core").index : 0;
                  trans.set("top", m5_ARRIVING_TOP + (this.getScope("core").index * m5_COREOFFSET))
                  trans.set("left", m5_ARRIVING_LEFT)
                  trans.set("opacity", 0)
                  trans.animate({top: m5_DEFLECTED_TOP + (core * m5_COREOFFSET), left: m5_DEFLECTED_LEFT, opacity: 1}, {
                                 onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                                 duration: 500
                                 })
               }
               else if ('/top/core|rg_continuing<>0$accepted'.asBool() && '/top/core|rg_not_deflected<>0$accepted'.asBool() && '/top/core|rg<>0$accepted'.asBool()) {
                  let core = (m5_NUM_CORES > 1) ? this.getScope("core").index : 0;
                  trans.set("top", m5_ARRIVING_TOP + (this.getScope("core").index * m5_COREOFFSET))
                  trans.set("left", m5_ARRIVING_LEFT)
                  trans.set("opacity", 0)
                  trans.animate({top: m5_RG_TOP + (core * m5_COREOFFSET), left: m5_RG_LEFT, opacity: 1}, {
                                 onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                                 duration: 500
                                 })
               } else {
                  console.log(`Transaction ${uid} not found.`)
               }
            }
         }
   /arb
      \viz_alpha
         initEach() {
            let fifo_out = new fabric.Circle({
               top: m5_FIFO_OUT_TOP + (this.getScope("core").index * m5_COREOFFSET),
               left: m5_FIFO_OUT_LEFT,
               radius: m5_NODES_RADIUS,
               fill: m5_NODES_COLOR
            })
            let rg = new fabric.Circle({
               top: m5_RG_TOP + (this.getScope("core").index * m5_COREOFFSET),
               left: m5_RG_LEFT,
               radius: m5_NODES_RADIUS,
               fill: m5_NODES_COLOR
            })
            return {objects : {fifo_out, rg}}
         },
         renderEach() {
               let uid = '/top/core|rg_fifo_out/flit<>0$uid'.asInt()
               let trans = this.global.transObj[uid]
               if (trans) {
                  trans.set("visible", true)
                  console.log(`uid  ${uid} .`)
                  if ('/top/core|rg<>0$accepted'.asBool() && '/top/core|rg_fifo_inj<>0$accepted'.asBool()) {
                     let core = (m5_NUM_CORES > 1) ? this.getScope("core").index : 0;
                     //trans.set("top", m5_FIFO_OUT_TOP + (this.getScope("core").index * m5_COREOFFSET))
                     //trans.set("left", m5_FIFO_OUT_LEFT)
                     //trans.set("opacity", 0)
                     trans.animate({top: m5_FIFO_OUT_TOP + (core * m5_COREOFFSET), left: m5_FIFO_OUT_LEFT, opacity: 1}, {
                                    onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                                    duration: 500,
                                    onComplete: () => {
                                       trans.animate({top: m5_RG_TOP + (core * m5_COREOFFSET), left: m5_RG_LEFT, opacity: 1}, {
                                       onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                                       duration: 500})
                                    }
                                    })
                  } else {
                  //debugger
                  console.log(`Transaction ${uid} not found.`)
               }
            }
         }
   /arbister
      \viz_alpha
         initEach() {
            let rg_st1 = new fabric.Circle({
               top: m5_RG_TOP + (this.getScope("core").index * m5_COREOFFSET) + 50,
               left: m5_RG_LEFT,
               radius: m5_NODES_RADIUS,
               fill: m5_NODES_COLOR
            })
            return {objects : {rg_st1}}
         },
         renderEach() {
               let uid = '/top/core|rg_st1/flit>>1$uid'.asInt()
               let trans = this.global.transObj[uid]
               if (trans) {
                  trans.set("visible", true)
                  console.log(`uid  ${uid} .`)
                  if ('/top/core|rg_st1>>1$accepted'.asBool()) {
                  let core = (m5_NUM_CORES > 1) ? this.getScope("core").index : 0;
                     if(core != 2) {
                     trans.animate({top: m5_RG_TOP + (core * m5_COREOFFSET) + 50, left: m5_RG_LEFT, opacity: 1}, {
                                    onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                                    duration: 500})
                       } else {
                       trans.animate({top: m5_RG_TOP + (core * m5_COREOFFSET) + 50, left: m5_RG_LEFT, opacity: 1}, {
                                    onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                                    duration: 500,
                                    onComplete: () => {
                                       trans.animate({top: m5_ARRIVING_TOP, left: m5_RG_LEFT, opacity: 1}, {
                                       onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                                       duration: 1500})
                                    }
                                    })
                       }
                  } else {
                  //debugger
                  console.log(`Transaction new ${uid} not found.`)
               }
            }
         }
   |rg_fifo_in
      @0
         /entry[*]
            \viz_alpha
               initEach() {
                  let entry_node = new fabric.Circle({
                     top: m5_ENTRY_START_TOP + (this.getScope("core").index * m5_COREOFFSET) + (this.getScope("entry").index * m5_ENTRY_START_SPACE_TOP ),
                     left: m5_ENTRY_START_LEFT,
                     radius: m5_NODES_RADIUS,
                     fill: "#208028"
                  })
                  return {objects : {entry_node}}
               },
               renderEach() {
                     let uid = '/flit$uid'.asInt()
                     let push = '$push'.asInt()
                     let header_point = '>>1$prev_entry_was_tail'.asInt()
                     let trans = this.global.transObj[uid]
                     if (trans) {
                        trans.set("visible", true)
                        console.log(`uid  ${uid} .`)
                        /*
                        if (push && header_point) {
                           let core = this.getScope("core").index;
                           let entry = this.getScope("entry").index;
                           trans.set("top", m5_EGRESS_OUT_TOP + (this.getScope("core").index * m5_COREOFFSET))
                           trans.set("left", m5_EGRESS_OUT_LEFT)
                           trans.set("opacity", 0)
                           this.global.transObj[counting] = entry;
                           trans.animate({top: m5_FIFO_IN_TOP + (core * m5_COREOFFSET), left: m5_FIFO_IN_LEFT, opacity: 1}, {
                                          onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                                          duration: 500, 
                                          onComplete: () => {
                                             trans.animate({top: m5_ENTRY_START_TOP + (core * m5_COREOFFSET) + ((8) * m5_ENTRY_START_SPACE_TOP ), left: m5_ENTRY_START_LEFT, opacity: 1}, {
                                             onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                                             duration: 500})
                                          }
                                          })
                        } else if (push) {
                           let core = this.getScope("core").index;
                           let entry = this.getScope("entry").index;
                           let left_att = m4_eval(m5_MAX_PACKET_SIZE) + 2 - this.global.transObj[counting] - entry;
                           trans.set("top", m5_EGRESS_OUT_TOP + (this.getScope("core").index * m5_COREOFFSET))
                           trans.set("left", m5_EGRESS_OUT_LEFT)
                           trans.set("opacity", 0)
                           trans.animate({top: m5_FIFO_IN_TOP + (core * m5_COREOFFSET), left: m5_FIFO_IN_LEFT, opacity: 1}, {
                                          onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                                          duration: 500, 
                                          onComplete: () => {
                                             trans.animate({top: m5_ENTRY_START_TOP + (core * m5_COREOFFSET) + ((left_att) * m5_ENTRY_START_SPACE_TOP ), left: m5_ENTRY_START_LEFT, opacity: 1}, {
                                             onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                                             duration: 500})
                                          }
                                          })
                        } */
                        if (push) {
                              let core = (m5_NUM_CORES > 1) ? this.getScope("core").index : 0;
                              let entry = this.getScope("entry").index;
                              trans.set("top", m5_EGRESS_OUT_TOP + (this.getScope("core").index * m5_COREOFFSET))
                              trans.set("left", m5_EGRESS_OUT_LEFT)
                              trans.set("opacity", 0)
                              trans.animate({top: m5_FIFO_IN_TOP + (core * m5_COREOFFSET), left: m5_FIFO_IN_LEFT, opacity: 1}, {
                                             onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                                             duration: 500, 
                                             onComplete: () => {
                                                trans.animate({top: m5_ENTRY_START_TOP + (core * m5_COREOFFSET) + ((8 - entry) * m5_ENTRY_START_SPACE_TOP ), left: m5_ENTRY_START_LEFT, opacity: 1}, {
                                                onChange: this.global.canvas.renderAll.bind(this.global.canvas),
                                                duration: 500})
                                             }
                                             })
                        } else {
                           //debugger
                           console.log(`Transaction ${uid} not found.`)
                        }
                     }
               }
// Hookup Makerchip *passed/*failed signals to CPU $passed/$failed.
// Args:
//   /_hier: Scope of core(s), e.g. [''] or ['/core[*]'].
\TLV makerchip_pass_fail(/_hier)
   |done
      @m5_MEM_WR_STAGE
         // Assert these to end simulation (before Makerchip cycle limit).
         *passed = & /top/_hier|fetch/instr>>m5_REG_WR_STAGE$passed;
         *failed = | /top/_hier|fetch/instr>>m5_REG_WR_STAGE$failed;


// Instantiate the chosen testbench, based on m5_isa, m5_PROG_NAME, and/or m5_TESTBENCH_NAME.
//   - m4+<m5_isa>_<m5_TESTBENCH_NAME>_makerchip_tb
//   - m4+<m5_TESTBENCH_NAME>_makerchip_tb
//   - m4+<m5_isa>_<m5_PROG_NAME>_makerchip_tb
//   - m4+<m5_PROG_NAME>_makerchip_tb
//   - m4+<m5_isa>_default_makerchip_tb
//   - m4+default_makerchip_tb
\TLV warpv_makerchip_tb()
   m5_default_def(TESTBENCH_NAME, m4_ifdef_tlv(m5_isa['_']m5_PROG_NAME['_makerchip_tb'], m5_PROG_NAME, m4_ifdef_tlv(m5_PROG_NAME['_makerchip_tb'], m5_PROG_NAME, ['default'])))
   m4_def(tb_macro_name, m4_ifdef_tlv(m5_isa['_']m5_TESTBENCH_NAME['_makerchip_tb'], m5_isa['_']m5_TESTBENCH_NAME['_makerchip_tb'], m5_TESTBENCH_NAME['_makerchip_tb']))
   m4+m4_tb_macro_name()

// A top-level macro supporting one core and no test-bench.
\TLV warpv()
   /* verilator lint_on WIDTH */  // Let's be strict about bit widths.
   m4+cpu(/top)
   m4_ifelse(m5_FORMAL, 1, ['m4+formal()'])

// A top-level macro for WARP-V.
\TLV warpv_top()
   /* verilator lint_on WIDTH */  // Let's be strict about bit widths.
   m4+ifelse(m4_eval(m5_NUM_CORES > 1), 1,
      \TLV
         // Multi-core
         /m5_CORE_HIER
            // TODO: Find a better place for this:
            // Block CPU |fetch pipeline if blocked.
            m4_def(cpu_blocked, m4_cpu_blocked || /core|egress_in/instr<<m5_EXECUTE_STAGE$pkt_wr_blocked || /core|ingress_out<<m5_EXECUTE_STAGE$pktrd_blocked)
            m4+cpu(/core)
            //m4+dummy_noc(/core)
            m4+noc_cpu_buffers(/core, m4_eval(m5_MAX_PACKET_SIZE + 1))
            m4+noc_insertion_ring(/core, m4_eval(m5_MAX_PACKET_SIZE + 1))
            m4+warpv_makerchip_tb()
         //m4+simple_ring(/core, |noc_in, @1, |noc_out, @1, /top<>0$reset, |rg, /flit)
         m4+makerchip_pass_fail(/core[*])
         /m5_CORE_HIER
            // TODO: This should be part of the \TLV cpu macro, but there is a bug that \viz_alpha must be the last definition of each hierarchy.
            m4_ifelse_block(m5_ISA, ['RISCV'], ['
            m4_ifelse_block(m5_VIZ, 1, ['
            m4+cpu_viz(|fetch, "#7AD7F0")
            m4+ring_viz(/name)
            '])
            '])
      ,
      \TLV
         // Single Core.
         
         // m4+warpv() (but inlined to reduce macro depth)
         m4+cpu(/top)
         m4_ifelse_block(m5_FORMAL, 1, ['
         m4+formal()
         '])
         m4_ifelse_block(M4_MAKERCHIP, 1, ['
         m4+warpv_makerchip_tb()
         m4+makerchip_pass_fail()
         '])
         m4_ifelse_block(m5_ISA, ['RISCV'], ['
         m4_ifelse(m5_VIZ, 1, ['m4+cpu_viz(|fetch, "#7AD7F0")'])
         '])
      )

m4+module_def()
\TLV //disabled_main()
   m4+warpv_top()
\SV
   endmodule
