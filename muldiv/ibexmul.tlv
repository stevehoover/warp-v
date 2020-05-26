\m4_TLV_version 1d: tl-x.org
\SV

   // =========================================
   // Welcome!  Try the tutorials via the menu.
   // =========================================

   // Default Makerchip TL-Verilog Code Template
   /* verilator lint_off PINMISSING */

   m4_sv_include_url(['https:/']['/raw.githubusercontent.com/lowRISC/ibex/master/shared/rtl/prim_assert.sv'])
   m4_sv_include_url(['https:/']['/raw.githubusercontent.com/lowRISC/ibex/master/rtl/ibex_pkg.sv'])                  
   m4_sv_include_url(['https:/']['/raw.githubusercontent.com/lowRISC/ibex/master/rtl/ibex_alu.sv'])
   m4_sv_include_url(['https:/']['/raw.githubusercontent.com/lowRISC/ibex/master/rtl/ibex_multdiv_fast.sv'])
   // Macro providing required top-level module definition, random
   // stimulus support, and Verilator config.
   
   

   m4_makerchip_module()    // (Expanded in Nav-TLV pane.)

\TLV
   //$reset = *reset;
   
   |muldiv
      @1
         //common
         $reset = (*cyc_cnt <= 32'h1) ? 1'b1 : 1'b0;
         
         //multdiv
         $mult_en_i = 1'b0;
         $div_en_i = 1'b1;
         $mult_sel_i = 1'b0;
         $div_sel_i = 1'b1;
         $multdiv_operand_a_i[31:0] = 32'hFDEAD;
         $multdiv_operand_b_i[31:0] = 32'hCAFE;
         $multdiv_signed_mode_i[1:0] = 2'b00;
         $multdiv_ready_id_i = 1'b0;
         //$alu_is_equal_result = 1'b0;
         
         //alu
         
         
         \SV_plus
            //ibex_pkg::md_op_e multdiv_operator_i;
            typedef enum logic [1:0] {
              // Multiplier/divider
              MD_OP_MULL,
              MD_OP_MULH,
              MD_OP_DIV,
              MD_OP_REM
            } md_op_e;
            md_op_e multdiv_operator_i;
            assign multdiv_operator_i = MD_OP_DIV;
            typedef enum logic [5:0] {
            // Arithmetics
              ALU_ADD,
              ALU_SUB,
               // Logics
              ALU_XOR,
              ALU_OR,
              ALU_AND,
              // RV32B
              ALU_XNOR,
              ALU_ORN,
              ALU_ANDN,
               //   Shifts
              ALU_SRA,
              ALU_SRL,
              ALU_SLL,
              // RV32B
              ALU_SRO,
              ALU_SLO,
              ALU_ROR,
              ALU_ROL,
              ALU_GREV,
              ALU_GORC,
              ALU_SHFL,
              ALU_UNSHFL,
               // Comparisons
              ALU_LT,
              ALU_LTU,
              ALU_GE,
              ALU_GEU,
              ALU_EQ,
              ALU_NE,
              // RV32B
              ALU_MIN,
              ALU_MINU,
              ALU_MAX,
              ALU_MAXU,
               // Pack
              // RV32B
              ALU_PACK,
              ALU_PACKU,
              ALU_PACKH,
               // Sign-Extend
              // RV32B
              ALU_SEXTB,
              ALU_SEXTH,
               // Bitcounting
              // RV32B
              ALU_CLZ,
              ALU_CTZ,
              ALU_PCNT,
               // Set lower than
              ALU_SLT,
              ALU_SLTU,
               // Ternary Bitmanip Operations
              // RV32B
              ALU_CMOV,
              ALU_CMIX,
              ALU_FSL,
              ALU_FSR,
               // Single-Bit Operations
              // RV32B
              ALU_SBSET,
              ALU_SBCLR,
              ALU_SBINV,
              ALU_SBEXT,
               // Bit Extract / Deposit
              // RV32B
              ALU_BEXT,
              ALU_BDEP,
               // Bit Field Place
              // RV32B
              ALU_BFP
            } alu_op_e;
            //alu_op_e alu_operator_i = 5'b0;
            
            
            logic [33:0] imd_val_q_i;
            logic [33:0] multdiv_imd_val_d;
            logic multdiv_imd_val_we;
            logic alu_imd_val_we;
            logic [31:0] alu_imd_val_d;
            logic [31:0] alu_operand_a_i, alu_operand_b_i;
            assign alu_operand_a_i = 32'h0000;
            assign alu_operand_b_i = 32'h0000;
         
         
         ibex_alu #(.RV32B(0)) ibex_alu (
            .operand_a_i           ( 32'b0),
            .operand_b_i           ( 32'b0),
            .instr_first_cycle_i   ( 1'b0 ),
            .imd_val_q_i           ( imd_val_q_i[31:0]),
            .imd_val_we_o          ( alu_imd_val_we),
            .imd_val_d_o           ( alu_imd_val_d),
            .multdiv_operand_a_i   ( $multdiv_alu_operand_a ),
            .multdiv_operand_b_i   ( $multdiv_alu_operand_b ),
            .multdiv_sel_i         ( 1'b1),
            .adder_result_o        ( $$alu_adder_result_ex_o[31:0]),
            .adder_result_ext_o    ( $$alu_adder_result_ext[33:0]),
            .result_o              ( $$alu_result[31:0]),
            .comparison_result_o   ( $$alu_cmp_result  ),
            .is_equal_result_o     ( $$alu_is_equal_result)
          );
         
         
         ibex_multdiv_fast #(.SingleCycleMultiply(1)) multdiv_i (
            .clk_i                 ( clk                 ),
            .rst_ni                ( !reset                ),
            .mult_en_i             ( $mult_en_i             ),
            .div_en_i              ( $div_en_i              ),
            .mult_sel_i            ( $mult_sel_i            ),
            .div_sel_i             ( $div_sel_i             ),
            .operator_i            ( multdiv_operator_i    ),
            .signed_mode_i         ( $multdiv_signed_mode_i[1:0] ),
            .op_a_i                ( $multdiv_operand_a_i[31:0]   ),
            .op_b_i                ( $multdiv_operand_b_i [31:0]  ),
            .alu_operand_a_o       ( $$multdiv_alu_operand_a[32:0] ),
            .alu_operand_b_o       ( $$multdiv_alu_operand_b[32:0] ),
            .alu_adder_ext_i       ( $alu_adder_result_ext[33:0]  ),
            .alu_adder_i           ( $alu_adder_result_ex_o[31:0] ),
            .equal_to_zero_i       ( $alu_is_equal_result   ),
            .data_ind_timing_i     ( 1'b0 ),
            .imd_val_q_i           ( imd_val_q_i           ),
            .imd_val_d_o           ( multdiv_imd_val_d     ),
            .imd_val_we_o          ( multdiv_imd_val_we    ),
            .multdiv_ready_id_i    ( $multdiv_ready_id_i    ),
            .valid_o               ( $$multdiv_valid         ),
            .multdiv_result_o      ( $$multdiv_result[31:0]        )
          );
          
   *passed = *cyc_cnt > 80;
   *failed = 1'b0;
\SV
   endmodule
