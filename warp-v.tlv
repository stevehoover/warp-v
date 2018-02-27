\m4_TLV_version 1d: tl-x.org
\SV
   // -----------------------------------------------------------------------------
   // Copyright (c) 2017, Steven F. Hoover
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

m4+makerchip_header(['

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
   //   o This code makes heavy use of macro preprocessing with M4 (https://www.gnu.org/software/m4/manual/m4.html),
   //     as well as "m4+" macros supported by Perl preprocessing. Neither of these are
   //     currently documented or supported for general use. This design is shared to illustrate
   //     the potential, not with the expectation that folks will evolve the design on their own.
   //     (If you are interested in doing so, please contact me at steve.hoover@redwoodeda.com,
   //     and I would be happy to provide assistance.)
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
   // Replays:
   //
   // The PC is redirected, and inflight instructions are squashed (their results are
   // not committed) for:
   //   o jumps, which go to an absolute jump target address
   //   o unconditioned and true-conditioned branches, which go to branch target
   //   o instructions that consume a pending register, which replay instruction immediately
   //     (See "Loads", below.)
   //   o loads that write to a pending register, which replay instruction immediately
   //     (See "Loads", below.)
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
   
   m4_include(['pipeflow_tlv.m4'])



   // =============
   // Configuration
   // =============
   
   // This is where you configure the CPU.

   m4_define(['M4_ISA'], MINI) // MINI, RISCV, DUMMY, etc.
   
   m4_define(['M4_TB'], 1)  // 0 to disable testbench and instrumentation code.

   // Adjust the parameters below to define the pipeline depth and staging.
   // Define the following:
   //   Stages:
   //     M4_PC_MUX_STAGE: Determining fetch PC.
   //     M4_FETCH_STAGE: Instruction fetch.
   //     M4_DECODE_STAGE: Instruction decode.
   //     M4_REG_RD_STAGE: Register file read.
   //     M4_EXECUTE_STAGE: Operation execution.
   //     M4_RESULT_STAGE: Select execution result.
   //     M4_BRANCH_TARGET_CALC_STAGE: Calculate branch target (generally EXECUTE, but some designs
   //                                  might produce offset from EXECUTE, then compute target).
   //     M4_MEM_WR_STAGE: Memory write.
   //     M4_REG_WR_STAGE: Register file write.
   //   Latencies:
   //     M4_EXTRA_JUMP_BUBBLE: 0 or 1. 0 aligns PC_MUX with EXECUTE for jumps.
   //     M4_EXTRA_BRANCH_BUBBLE: 0 aligns PC_MUX with BRANCH_TARGET_CALC for branches. May use 1 to
   //                             add a bubble only if BRANCH_TARGET_CALC == EXECUTE, and must if JUMP_BUBBLE.
   //     M4_EXTRA_REPLAY_BUBBLE: 0 or 1. 0 aligns PC_MUX with EXECUTE for replays.
   //     M4_LD_RETURN_ALIGN: Alignment of load return pseudo-instruction into |mem pipeline.
   //                         If |mem stages reflect nominal alignment w/ load instruction, this is the
   //                         nominal load latency.
   //     M4_DATA_MEM_WORDS: Number of data memory locations.
   m4_case(['1-stage'],
      ['5-stage'], ['
         // A reasonable 5-stage pipeline.
         m4_defines(
            (M4_PC_MUX_STAGE, -1),
            (M4_FETCH_STAGE, 0),
            (M4_DECODE_STAGE, 1),
            (M4_REG_RD_STAGE, 1),
            (M4_EXECUTE_STAGE, 2),
            (M4_RESULT_STAGE, 2),
            (M4_BRANCH_TARGET_CALC_STAGE, 3),
            (M4_MEM_WR_STAGE, 3),
            (M4_REG_WR_STAGE, 3),
            (M4_EXTRA_JUMP_BUBBLE, 0),
            (M4_EXTRA_BRANCH_BUBBLE, 0),
            (M4_EXTRA_REPLAY_BUBBLE, 0),
            (M4_LD_RETURN_ALIGN, 4))
         m4_define_hier(M4_DATA_MEM_WORDS, 32)
      '],
      ['1-stage'], ['
         // No pipeline
         m4_defines(
            (M4_PC_MUX_STAGE, -1),
            (M4_FETCH_STAGE, 0),
            (M4_DECODE_STAGE, 0),
            (M4_REG_RD_STAGE, 0),
            (M4_EXECUTE_STAGE, 0),
            (M4_RESULT_STAGE, 0),
            (M4_BRANCH_TARGET_CALC_STAGE, 0),
            (M4_MEM_WR_STAGE, 0),
            (M4_REG_WR_STAGE, 0),
            (M4_EXTRA_JUMP_BUBBLE, 0),
            (M4_EXTRA_BRANCH_BUBBLE, 0),
            (M4_EXTRA_REPLAY_BUBBLE, 0),
            (M4_LD_RETURN_ALIGN, 1))
         m4_define_hier(M4_DATA_MEM_WORDS, 32)
      '],
      ['
         // Deep pipeline
         m4_defines(
            (M4_PC_MUX_STAGE, 0),
            (M4_FETCH_STAGE, 1),
            (M4_DECODE_STAGE, 3),
            (M4_REG_RD_STAGE, 4),
            (M4_EXECUTE_STAGE, 5),
            (M4_RESULT_STAGE, 5),
            (M4_BRANCH_TARGET_CALC_STAGE, 5),
            (M4_MEM_WR_STAGE, 5),
            (M4_REG_WR_STAGE, 6),
            (M4_EXTRA_JUMP_BUBBLE, 0),
            (M4_EXTRA_BRANCH_BUBBLE, 0),
            (M4_EXTRA_REPLAY_BUBBLE, 0),
            (M4_LD_RETURN_ALIGN, 7))
         m4_define_hier(M4_DATA_MEM_WORDS, 32)
      ']
   )


   // --------------------------
   // ISA-Specific Configuration
   // --------------------------
   
   m4_case(M4_ISA, ['MINI'], ['
      // Mini-CPU Configuration:
      
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
   '])
   
   // =====Done Configuration=====
   
   
   
   // Latencies, calculated from latency parameters:
   m4_define(M4_REG_BYPASS_STAGES, m4_eval(M4_REG_WR_STAGE - M4_REG_RD_STAGE))
   m4_define(M4_JUMP_BUBBLES, m4_eval(M4_EXECUTE_STAGE - M4_PC_MUX_STAGE + M4_EXTRA_JUMP_BUBBLE))
   m4_define(M4_BRANCH_BUBBLES, m4_eval(M4_BRANCH_TARGET_CALC_STAGE - M4_PC_MUX_STAGE + M4_EXTRA_BRANCH_BUBBLE))
   m4_define(M4_REPLAY_LATENCY, m4_eval(M4_EXECUTE_STAGE - M4_PC_MUX_STAGE + 1))

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
         m4_define_vector(['M4_ADDR'], 30)
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
         m4_define_hier(M4_REGS, 2)

         m4_define(M4_NUM_INSTRS, 2)  // (Must match program exactly.)

      '])
   
   
   
   
   // Computed ISA uarch Parameters (based on ISA-specific parameters).

   m4_define(['M4_ADDRS_PER_WORD'], m4_eval(M4_WORD_CNT / M4_BITS_PER_ADDR))
   m4_define(['M4_ADDRS_PER_INSTR'], m4_eval(M4_INSTR_CNT / M4_BITS_PER_ADDR))
   m4_define_vector(['M4_PC'], M4_ADDR_HIGH, m4_width(m4_eval(M4_ADDRS_PER_INSTR - 1)))
   m4_define_hier(M4_DATA_MEM_ADDRS, m4_eval(M4_DATA_MEM_WORDS_HIGH * M4_ADDRS_PER_WORD))  // Addressable data memory locations.

   
   
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
      // Creates "assign $$is_x_type = INSTR_TYPE_X_MASK[$raw_opcode[6:2]];" for each type.
      m4_define(['m4_types_decode'],
                ['m4_ifelse(['$1'], [''], [''],
                            ['['assign $$is_']m4_translit(['$1'], ['A-Z'], ['a-z'])['_type = INSTR_TYPE_$1_MASK[$raw_opcode[6:2]]; ']m4_types_decode(m4_shift($@))'])'])
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
                ['m4_instr_decode_expr($5, $3, $4)[' localparam [2:0] $5_INSTR_FUNCT3 = 3'b']$4;'])
      m4_define(['m4_instr_no_func'],
                ['m4_instr_decode_expr($4, $3, ['xxx'])'])
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
              m4_dquote(m4_decode_expr['$is_']m4_translit($1, ['A-Z'], ['a-z'])['_instr = ($op5_funct3 ==? 8'b$2_$3);m4_plus_new_line   ']))
           m4_define(
              ['m4_rslt_mux_expr'],
              m4_dquote(m4_rslt_mux_expr[' |']['m4_plus_new_line       ({']M4_WORD_CNT['{$is_']m4_translit($1, ['A-Z'], ['a-z'])['_instr}} & $']m4_translit($1, ['A-Z'], ['a-z'])['_rslt)']))
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
      m4_define(['m4_instrS'], ['m4_instr_func($@)m4_define(['m4_asm_$5'], ['m4_asm_instr_str(S, ['$5'], $']['@){m4_asm_imm_field(']m4_arg(3)[', 12, 11, 5), m4_asm_reg(']m4_arg(2)['), m4_asm_reg(']m4_arg(1)['), $5_INSTR_FUNCT3, m4_asm_imm_field(']m4_arg(3)[', 12, 4, 0), $5_INSTR_OPCODE}'])'])
      m4_define(['m4_instrB'], ['m4_instr_func($@)m4_define(['m4_asm_$5'], ['m4_asm_instr_str(B, ['$5'], $']['@){m4_asm_imm_field(']m4_arg(3)[', 13, 12, 12), m4_asm_imm_field(']m4_arg(3)[', 13, 10, 5), m4_asm_reg(']m4_arg(2)['), m4_asm_reg(']m4_arg(1)['), $5_INSTR_FUNCT3, m4_asm_imm_field(']m4_arg(3)[', 13, 4, 1), m4_asm_imm_field(']m4_arg(3)[', 13, 11, 11), $5_INSTR_OPCODE}'])'])
      m4_define(['m4_instrJ'], ['m4_instr_no_func($@)'])
      m4_define(['m4_instrU'], ['m4_instr_no_func($@)'])
      m4_define(['m4_instr_'], ['m4_instr_no_func($@)'])

      // For each instruction type.
      // Declare localparam[31:0] INSTR_TYPE_X_MASK, initialized to 0 that will be given a 1 bit for each op5 value of its type.
      m4_define(['m4_instr_types_args'], ['I, R, RI, R4, S, B, J, U, _'])
      m4_instr_types(m4_instr_types_args)


      // Instruction fields (User ISA Manual 2.2, Fig. 2.2)
      m4_define_fields(['M4_INSTR'], 32, FUNCT7, 25, RS2, 20, RS1, 15, FUNCT3, 12, RD, 7, OPCODE, 0)


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
      // Store incremental results in memory locations 0..9. (1, 3, 6, 10, ...)
      //
      // Regs:
      // b: cnt
      // c: ten
      // d: out
      // e: tmp
      // f: offset
      // g: store addr
      
      assign instrs = '{
         "g=0~0", //     store_addr = 0
         "b=0~1", //     cnt = 1
         "c=1~2", //     ten = 10
         "d=0~0", //     out = 0
         "f=0-6", //     offset = -6
         "d=d+b", //  -> out += cnt
         "0=d}g", //     store out at store_addr
         "b=b+1", //     cnt ++
         "g=g+1", //     store_addr++
         "e=c-b", //     tmp = 10 - cnt
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
   $dest_reg[2:0] = $returning_ld ? $returning_ld_dest_reg : $fetch_instr_dest_reg[2:0];
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
      $valid_exe = $valid_decode; // Execute if we decoded.
      
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
      ?$valid_ld_st
         $addr[M4_ADDR_RANGE] = $ld ? (/src[1]$value + /src[2]$value) : /src[2]$value;
      // Always predict taken; mispredict if jump or unconditioned branch or
      //   conditioned branch with positive condition.
      ?$valid_branch
         $taken = $rslt != 12'b0;
   @_rslt_stage
      ?$dest_valid
         $rslt[11:0] =
            $returning_ld ? $returning_ld_data :
            $st ? /src[1]$value :
            $op_full ? $op_full_rslt :
            $op_compare ? {12{$compare_rslt}} :
                  12'b0;
         
      // Jump (Dest = "P") and Branch (Dest = "p") Targets.
      ?$valid_jump
         $jump_target[M4_PC_RANGE] = $rslt[M4_PC_RANGE];
   @M4_BRANCH_TARGET_CALC_STAGE
      ?$valid_branch
         $branch_target[M4_PC_RANGE] = $Pc + M4_PC_CNT'b1 + $rslt[M4_PC_RANGE];
         








//============================//
//                            //
//          RISC-V            //
//                            //
//============================//

\TLV riscv_cnt10_prog()
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
         m4_asm_LW(r4, r6, 0),         //     load the final value into tmp
         m4_asm_BGE(r1, r2, 1111111010100) //     TERMINATE by branching to -1
      };
      
      assign instr_strs = '{m4_asm_mem_expr "END                                     "};

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
       $returning_ld ? $returning_ld_data :
       M4_WORD_CNT'b0['']m4_echo(m4_rslt_mux_expr);

\TLV riscv_decode()
   ?$valid_decode

      // =================================

      // Extract fields of $raw (instruction) into $raw_<field>[x:0].
      m4_into_fields(['M4_INSTR'], ['$raw'])
      `BOGUS_USE($raw_funct7)  // Delete once its used.
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
      $op5_funct3[7:0] = {$raw[6:2], $raw_funct3};
      m4+riscv_decode_expr()

      $illegal = 1'b1['']m4_illegal_instr_expr;
      $jump = $is_jalr_instr;  // "Jump" in this code means absolute. "Jump" in RISC-V means unconditional.
      $conditional_branch = $is_b_type;
      $branch = $is_b_type || $is_j_type;
      $ld = $raw[6:3] == 4'b0;
      $st = $is_s_type;
      `BOGUS_USE($is___type $is_u_type)

      // Output signals.
      /src[2:1]
         // Reg valid for this source, based on instruction type.
         $is_reg = /instr$is_r_type || /instr$is_r4_type || (/instr$is_i_type && (#src == 1)) || /instr$is_ri_type || /instr$is_s_type || /instr$is_b_type;
         $reg[M4_REGS_INDEX_RANGE] = (#src == 1) ? /instr$raw_rs1 : /instr$raw_rs2;
           
      // For debug.
      $mnemonic[10*8-1:0] = m4_mnemonic_expr "ILLEGAL   ";
   $dest_reg[M4_REGS_INDEX_RANGE] = $returning_ld ? $returning_ld_dest_reg : $raw_rd;
   $dest_reg_valid = (($valid_decode && ! $is_s_type && ! $is_b_type) || $returning_ld) &&
                     | $dest_reg;   // r0 not valid.
   // Actually load.
   $spec_ld = $valid_decode && $ld;
   
\TLV riscv_exe(@_exe_stage, @_rslt_stage)
   
   @_exe_stage
      // Execution.
      $valid_exe = $valid_decode; // Execute if we decoded.
      
      // Compute results for each instruction, independent of decode (power-hungry, but fast).
      ?$valid_exe
         $equal = /src[1]$reg_value == /src[2]$reg_value;
      ?$valid_branch
         $taken =
            $is_j_type ||
            ($is_beq_instr && $equal) ||
            ($is_bne_instr && ! $equal) ||
            (($is_blt_instr || $is_bltu_instr || $is_bge_instr || $is_bgeu_instr) &&
             (($is_bge_instr || $is_bgeu_instr) ^
              ({($is_blt_instr ^ /src[1]$reg_value[M4_WORD_MAX]), /src[1]$reg_value[M4_WORD_MAX-1:0]} <
               {($is_blt_instr ^ /src[2]$reg_value[M4_WORD_MAX]), /src[2]$reg_value[M4_WORD_MAX-1:0]}
              )
             )
            );
         $branch_target[M4_PC_RANGE] = $Pc + $raw_b_imm[M4_PC_RANGE];
         // TODO: Deal with misaligned address.
      ?$valid_jump
         $jump_target[M4_PC_RANGE] = /src[1]$reg_value[M4_PC_RANGE] + $raw_i_imm[M4_PC_RANGE];
         // TODO: This assumes aligned addresses. Must deal with zeroing of byte bit and misaligned address.
      ?$valid_exe
         // Compute each individual instruction result, combined per-instruction by a macro.
         
         $lui_rslt[M4_WORD_RANGE] = 32'b0;
         $auipc_rslt[M4_WORD_RANGE] = 32'b0;
         $jal_rslt[M4_WORD_RANGE] = 32'b0;
         $jalr_rslt[M4_WORD_RANGE] = 32'b0;
         $beq_rslt[M4_WORD_RANGE] = 32'b0;
         $bne_rslt[M4_WORD_RANGE] = 32'b0;
         $blt_rslt[M4_WORD_RANGE] = 32'b0;
         $bge_rslt[M4_WORD_RANGE] = 32'b0;
         $bltu_rslt[M4_WORD_RANGE] = 32'b0;
         $bgeu_rslt[M4_WORD_RANGE] = 32'b0;
         $lb_rslt[M4_WORD_RANGE] = 32'b0;
         $lh_rslt[M4_WORD_RANGE] = 32'b0;
         $lw_rslt[M4_WORD_RANGE] = $returning_ld_data;
         $lbu_rslt[M4_WORD_RANGE] = 32'b0;
         $lhu_rslt[M4_WORD_RANGE] = 32'b0;
         $sb_rslt[M4_WORD_RANGE] = 32'b0;
         $sh_rslt[M4_WORD_RANGE] = 32'b0;
         $sw_rslt[M4_WORD_RANGE] = 32'b0;
         $addi_rslt[M4_WORD_RANGE] = /src[1]$reg_value + $raw_i_imm;  // Note: this has its own adder; could share w/ add/sub.
         $slti_rslt[M4_WORD_RANGE] = 32'b0;
         $sltiu_rslt[M4_WORD_RANGE] = 32'b0;
         $xori_rslt[M4_WORD_RANGE] = 32'b0;
         $ori_rslt[M4_WORD_RANGE] = /src[1]$reg_value | $raw_i_imm;
         $andi_rslt[M4_WORD_RANGE] = 32'b0;
         $slli_rslt[M4_WORD_RANGE] = 32'b0;
         $srli_srai_rslt[M4_WORD_RANGE] = 32'b0;
         $add_sub_rslt[M4_WORD_RANGE] = /src[1]$reg_value + /src[2]$reg_value;
         $sll_rslt[M4_WORD_RANGE] = 32'b0;
         $slt_rslt[M4_WORD_RANGE] = 32'b0;
         $sltu_rslt[M4_WORD_RANGE] = 32'b0;
         $xor_rslt[M4_WORD_RANGE] = 32'b0;
         $srl_sra_rslt[M4_WORD_RANGE] = 32'b0;
         $or_rslt[M4_WORD_RANGE] = 32'b0;
         $and_rslt[M4_WORD_RANGE] = 32'b0;
   @_exe_stage
      ?$valid_ld_st
         {$addr[M4_ADDR_RANGE], $misaligned_addr_bits[1:0]} = /src[1]$reg_value + ($ld ? $raw_i_imm : $raw_s_imm);
         `BOGUS_USE($misaligned_addr_bits)
         // TODO: This assumes word-aligned addresses and doesn't treat lower bits properly.
      ?$valid_st
         $st_value[M4_WORD_RANGE] = /src[2]$reg_value;

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
      $reg[M4_REGS_INDEX_RANGE] = 1'b1;
      $value[M4_WORD_RANGE] = 2'b1;
   $dest_reg_valid = 1'b1;
   $dest_reg[M4_REGS_INDEX_RANGE] = $returning_ld ? $returning_ld_dest_reg : 1'b0;
   $ld = 1'b0;
   $spec_ld = $ld;
   $st = 1'b0;
   $illegal = 1'b0;
   $branch = 1'b0;
   $jump = 1'b0;
   $conditional_branch = $branch;

// Execution unit logic for RISC-V.
// Context: pipeline
\TLV dummy_exe(@_exe_stage, @_rslt_stage)
   @M4_REG_RD_STAGE
      $exe_rslt[M4_WORD_RANGE] = 2'b1;
   // Note that some result muxing is performed in @_exe_stage, and the rest in @_rslt_stage.
   @_exe_stage
      $valid_exe = $valid_decode;
      $st_value[M4_WORD_RANGE] = /src[1]$reg_value;
      $addr[M4_ADDR_RANGE] = /src[2]$reg_value;
      $taken = $rslt != 2'b0;
   @_rslt_stage
      $rslt[M4_WORD_RANGE] =
         $returning_ld ? $returning_ld_data :
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

// A memory component provides a word-wide memory with an asynchronous out-of-order protocol, accepting
// a read or write (load or store) each cycle, where stores are visible to loads on the following cycle.
// Relative to |fetch/instr:
// On $valid_st, stores the word $st_value at $addr.
// On $spec_ld, loads the word at $addr as $ld_rslt.
// $ld_rslt and $ld are available as outputs in /cpu|mem/data$ANY (along w/ everything else in the
// input instruction), with the provided <<M4_ALIGNMENT_VALUE (which must be non-negative).


// A fake memory with fixed latency.
// The memory is placed in the fetch pipeline.
// TODO: (/_cpu, @_mem, @_align)
\TLV fixed_latency_fake_memory(/cpu, M4_ALIGNMENT_VALUE)
   |fetch
      /instr
         // ====
         // Load
         // ====
         
         /mem[M4_DATA_MEM_WORDS_RANGE]
         ?$spec_ld
            @M4_MEM_WR_STAGE
               $ld_rslt[M4_WORD_RANGE] = /mem[$addr[M4_DATA_MEM_WORDS_INDEX_RANGE]]$Word;
         
         // Array writes are not currently permitted to use assignment
         // syntax, so \always_comb is used, and this must be outside of
         // when conditions, so we need to use if. <<1 because no <= support
         // in this context. (This limitation will be lifted.)

         @M4_MEM_WR_STAGE
            // =====
            // Store
            // =====

            \always_comb
               if ($valid_st)
                  /mem[$addr[M4_DATA_MEM_WORDS_INDEX_RANGE]]<<1$$Word[M4_WORD_RANGE] = $st_value;

   // Return loads in |mem pipeline. We just hook up the |mem pipeline to the |fetch pipeline w/ the
   // right alignment.
   |mem
      /data
         @m4_eval(m4_strip_prefix(['@M4_MEM_WR_STAGE']) - M4_ALIGNMENT_VALUE)
            $ANY = /cpu|fetch/instr>>M4_ALIGNMENT_VALUE$ANY;




//=========================//
//                         //
//        THE CPU          //
//       (All ISAs)        //
//                         //
//=========================//

\TLV cpu()
   
   // Generated logic
   m4+indirect(M4_isa['_gen'])

   // The program in an instruction memory.
   \SV_plus
      logic [M4_INSTR_RANGE] instrs [0:M4_NUM_INSTRS-1];
   m4+indirect(M4_isa['_cnt10_prog'])


   // /=========\
   // | The CPU |
   // \=========/
   
   $reset = *reset;

   |fetch
      /instr
         @M4_FETCH_STAGE
            $reset = /top<>0$reset;
         
            $fetch = 1'b1;  // always fetch
            ?$fetch

               // =====
               // Fetch
               // =====

               $raw[M4_INSTR_RANGE] = *instrs\[$Pc[m4_eval(M4_PC_MIN + m4_width(M4_NUM_INSTRS-1) - 1):M4_PC_MIN]\];
            
         @m4_eval(M4_PC_MUX_STAGE + 1)
            // A returning load clobbers the instruction.
            // (Could do this with lower latency. Right now it goes through memory pipeline $ANY, and
            //  it is non-speculative. Both could easily be fixed.)
            $returning_ld = /top|mem/data>>M4_LD_RETURN_ALIGN$valid_ld;
            
            // =======
            // Next PC
            // =======
            
            $Pc[M4_PC_RANGE] <=
               $reset ? M4_PC_CNT'b0 :
               >>M4_BRANCH_BUBBLES$valid_mispred_branch ? >>M4_BRANCH_BUBBLES$branch_target :
               >>M4_JUMP_BUBBLES$valid_jump ? >>M4_JUMP_BUBBLES$jump_target :
               >>m4_eval(M4_REPLAY_LATENCY-1)$replay ? >>m4_eval(M4_REPLAY_LATENCY-1)$Pc :
               $returning_ld ? $RETAIN :  // Returning load, so next PC is the previous next PC (unless there was a branch that wasn't visible yet)
                        $Pc + M4_PC_CNT'b1;
            
         @M4_DECODE_STAGE

            // ======
            // DECODE
            // ======

            // Decode of the fetched instruction
            $valid_decode = $fetch;  // Always decode if we fetch.
            m4+indirect(M4_isa['_decode'])
            
            // Returning load doesn't decode the instruction. Provide value to force for dest reg. 
            $returning_ld_dest_reg[M4_REGS_INDEX_RANGE] = /top|mem/data>>M4_LD_RETURN_ALIGN$dest_reg;
            
         @M4_REG_RD_STAGE
            // ======
            // Reg Rd
            // ======
            
            /M4_REGS_HIER
            /src[2:1]
               $is_reg_condition = $is_reg && /instr$valid_decode;
               ?$is_reg_condition
                  $reg_value[M4_WORD_RANGE] =
                     m4_ifelse(m4_isa, ['riscv'], ['($reg == M4_REGS_INDEX_CNT'b0) ? M4_WORD_CNT'b0 :  // Read r0 as 0.'])
                     // Bypass stages:
                     m4_ifexpr(M4_REG_BYPASS_STAGES >= 1, ['(/instr>>1$dest_reg_valid && (/instr>>1$dest_reg == $reg)) ? /instr>>1$rslt :'])
                     m4_ifexpr(M4_REG_BYPASS_STAGES >= 2, ['(/instr>>2$dest_reg_valid && (/instr>>2$dest_reg == $reg)) ? /instr>>2$rslt :'])
                     m4_ifexpr(M4_REG_BYPASS_STAGES >= 3, ['(/instr>>3$dest_reg_valid && (/instr>>3$dest_reg == $reg)) ? /instr>>3$rslt :'])
                     /instr/regs[$reg]>>M4_REG_BYPASS_STAGES$Value;
               $replay = $is_reg_condition && /instr/regs[$reg]>>1$next_pending;
            $replay = | /src[*]$replay || ($dest_reg_valid && /regs[$dest_reg]>>1$next_pending);
         
         
         // =======
         // Execute
         // =======
         m4+indirect(M4_isa['_exe'], @M4_EXECUTE_STAGE)
               
         @M4_EXECUTE_STAGE
            $valid_ld_st = $valid_ld || $valid_st;

            // =========
            // Target PC
            // =========
            
            $mispred_branch = $branch && ! ($conditional_branch && ! $taken);
            $valid_jump = $jump && ! $squash;
            $valid_branch = $branch && ! $squash;
            $valid_mispred_branch = $mispred_branch && ~$squash;
            $valid_ld = $ld && ! $squash;
            $valid_st = $st && ! $squash;
            $valid_illegal = $illegal && ! $squash;
            `BOGUS_USE($valid_illegal)
            // Squash. Keep a count of the number of cycles remaining in the shadow of a mispredict.
            // Also, squash on ! $valid_exe not valid.
            $squash = ! $valid_exe || (| $SquashCnt) || $returning_ld || $replay;
            $SquashCnt[2:0] <=
               $reset                ? 3'b0 :
               $valid_mispred_branch ? M4_BRANCH_BUBBLES :
               $valid_jump           ? M4_JUMP_BUBBLES :
               $replay               ? M4_REPLAY_LATENCY - 3'b1:
               $SquashCnt == 3'b0    ? 3'b0 :
                                       $SquashCnt - 3'b1;
                                       
            $returning_ld_data[M4_WORD_RANGE] = /top|mem/data>>M4_LD_RETURN_ALIGN$ld_rslt;
   m4+fixed_latency_fake_memory(/top, 0)
   |fetch
      /instr
         @M4_REG_WR_STAGE
            // =========
            // Reg Write
            // =========

            $reg_write = $reset ? 1'b0 : ($dest_reg_valid && ! $squash) || $returning_ld;
            \always_comb
               if ($reg_write)
                  /regs[$dest_reg]<<1$$Value[M4_WORD_RANGE] = $rslt;
         
         // There's no bypass on pending, so we must write the same cycle we read.
         @M4_EXECUTE_STAGE
            /regs[*]
               $reg_match = /instr$dest_reg == #regs;
               $next_pending =  // Should be state, but need to consume prior to flop, which SandPiper doesn't support, yet.
                  /instr$reset ? 1'b0 :
                  // set for loads
                  /instr$valid_ld && $reg_match   ? 1'b1 :
                  // clear when load returns
                  /instr$returning_ld && $reg_match ? 1'b0 :
                               $RETAIN;
   




\TLV
   // =================
   //
   //    THE MODEL
   //
   // =================
   
   m4+cpu()

   
   // Assert these to end simulation (before Makerchip cycle limit).
!  *passed = ! *reset['']m4_ifexpr(M4_TB, [' && |fetch/instr>>5$Pc == {M4_PC_CNT{1'b1}}']);
!  *failed = ! *reset['']m4_ifexpr(M4_TB, [' && (*cyc_cnt > 1000 || (! |fetch/instr>>3$reset && |fetch/instr>>6$valid_illegal))']);
\SV
   endmodule
