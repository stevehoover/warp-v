\m4_TLV_version 1d: tl-x.org
\SV

   // =========================================
   // Welcome!  Try the tutorials via the menu.
   // =========================================

   // Default Makerchip TL-Verilog Code Template
   /* verilator lint_off WIDTH */
   /* verilator lint_off CASEINCOMPLETE */
   m4_sv_include_url(['https:/']['/raw.githubusercontent.com/shivampotdar/warp-v/muldiv/muldiv/picorv32_pcpi_div.sv'])
   m4_sv_include_url(['https:/']['/raw.githubusercontent.com/shivampotdar/warp-v/muldiv/muldiv/picorv32_pcpi_fast_mul.sv'])
   // Macro providing required top-level module definition, random
   // stimulus support, and Verilator config.
   m4_makerchip_module()   // (Expanded in Nav-TLV pane.)

\TLV warpv_muldiv(/_top, /_name, $_rslt, $_wr, $_wait, $_ready,  $_clk, $_reset, $_op_a, $_op_b, $_instr_type, $_muldiv_valid)
   /_name
      
      // instr type is one hot encoding of the required M type instruction
      // the idea is to concatenate is_*_instr from WARP-V and pass on to this module
         
      $opcode[2:0] = (/_top$_instr_type == 8'b00000001 ) ? 3'b000 : // mull 
                     (/_top$_instr_type == 8'b00000010 ) ? 3'b001 : // mulh
                     (/_top$_instr_type == 8'b00000100 ) ? 3'b010 : // mulhsu
                     (/_top$_instr_type == 8'b00001000 ) ? 3'b011 : // mulhu
                     (/_top$_instr_type == 8'b00010000 ) ? 3'b100 : // div
                     (/_top$_instr_type == 8'b00100000 ) ? 3'b101 : // divu
                     (/_top$_instr_type == 8'b01000000 ) ? 3'b110 : // rem
                     (/_top$_instr_type == 8'b10000000 ) ? 3'b111 : // remu
                                                           3'b000 ; // default to mul, but this case 
                                                                    // should not be encountered ideally

      $muldiv_insn[31:0] = {7'b0000001,10'b0011000101,$opcode,5'b00101,7'b0110011};
                        // {  funct7  ,{rs2, rs1} (X), funct3, rd (X),  opcode  }   
      $mul_block = ($opcode <= 3'b011) ? 1'b1 : 1'b0;
       
      \SV_plus
            picorv32_pcpi_fast_mul mul(
                  .clk           (/_top$_clk), 
                  .resetn        (/_top$_reset),
                  .pcpi_valid    (/_top$_muldiv_valid),  // if 1 , multiplication
                  .pcpi_insn     ($muldiv_insn),
                  .pcpi_rs1      (/_top$_op_a),
                  .pcpi_rs2      (/_top$_op_b),
                  .pcpi_wr       ($$mul_pcpi_wr),
                  .pcpi_rd       ($$mul_pcpi_rd[31:0]),
                  .pcpi_wait     ($$mul_pcpi_wait),
                  .pcpi_ready    ($$mul_pcpi_ready)
            );   
            picorv32_pcpi_div div(
                  .clk           (/_top$_clk), 
                  .resetn        (/_top$_reset),
                  .pcpi_valid    (/_top$_muldiv_valid),  // if 0,  division
                  .pcpi_insn     ($muldiv_insn),
                  .pcpi_wr       ($$div_pcpi_wr),
                  .pcpi_rs1      (/_top$_op_a),
                  .pcpi_rs2      (/_top$_op_b),
                  .pcpi_rd       ($$div_pcpi_rd[31:0]),
                  .pcpi_wait     ($$div_pcpi_wait),
                  .pcpi_ready    ($$div_pcpi_ready)
               );
         
   $_rslt[31:0] = /_name$mul_block ? /_name$mul_pcpi_rd    : /_name$div_pcpi_rd;
   $_ready      = /_name$mul_block ? /_name$mul_pcpi_ready : /_name$div_pcpi_ready;
   $_wr         = /_name$mul_block ? /_name$mul_pcpi_wr    : /_name$div_pcpi_wr;
   $_wait       = /_name$mul_block ? /_name$mul_pcpi_wait  : /_name$div_pcpi_wait;
   
   
\TLV 
   
   |muldiv
      @1
         $instr_type[7:0] = (1 << 5);
         /* lshift by
            0 - mul
            1 - mulh
            2 - mulhsu
            3 - mulhu
            4 - div
            5 - divu
            6 - rem
            7 - remu
         */
         $reset = !(*reset);
         $clk = *clk;
         $mul_valid = 1'b1;
         $op_a[31:0] = 32'hCAFE;
         $op_b[31:0] = 32'h1234;
         m4+warpv_muldiv(|muldiv, /muldiv1, $rslt, $wr, $wait, $ready, $clk, $reset, $op_a, $op_b, $instr_type, $mul_valid)
   // Assert these to end simulation (before Makerchip cycle limit).
   *passed = *cyc_cnt > 50;
   *failed = 1'b0;
\SV
   endmodule
