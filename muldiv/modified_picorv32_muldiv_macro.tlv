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
                  .pcpi_wr       ($$mul_pcpi_wr),
                  .pcpi_rd       ($$mul_pcpi_rd[31:0]),
                  .pcpi_wait     ($$mul_pcpi_wait),
                  .pcpi_ready    ($$mul_pcpi_ready)
            );
   $_wr           =   /_name$mul_pcpi_wr;
   $_wait         =   /_name$mul_pcpi_wait;
   $_ready        =   /_name$mul_pcpi_ready;
   $_rslt[31:0]   =   /_name$mul_pcpi_rd;           
   
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
                  .pcpi_rd       ($$div_pcpi_rd[31:0]),
                  .pcpi_wait     ($$div_pcpi_wait),
                  .pcpi_wr       ($$div_pcpi_wr),
                  .pcpi_ready    ($$div_pcpi_ready)
               );
   $_ready       =   /_name$div_pcpi_ready;
   $_wait        =   /_name$div_pcpi_wait;
   $_wr          =   /_name$div_pcpi_wr;
   $_rslt[31:0]  =   /_name$div_pcpi_rd;
\TLV 
   
   |muldiv
      @1
         $instr_type_mul[3:0] = (1 << 0);
         /* lshift by
            0 - mul
            1 - mulh
            2 - mulhsu
            3 - mulhu
        */

         $instr_type_div[3:0] = (1 << 0);
         /* lshift by
            0 - div
            1 - divu
            2 - rem
            3 - remu
         */
         $reset = !(*reset);
         $clk = *clk;
         $muldiv_valid = 1'b1;
         $op_a[31:0] = 32'hCAFE;
         $op_b[31:0] = 32'h1234;
         /orig_instr
            m4+warpv_mul(|muldiv, /mul1, $rsltm, $wrm, $waitm, $readym, $clk, $reset, $op_a, $op_b, $instr_type_mul, $muldiv_valid)
            m4+warpv_div(|muldiv, /div1, $rsltd, $wrd, $waitd, $readyd, $clk, $reset, $op_a, $op_b, $instr_type_div, $muldiv_valid)
   // Assert these to end simulation (before Makerchip cycle limit).
   *passed = *cyc_cnt > 50;
   *failed = 1'b0;
\SV
   endmodule
