\m4_TLV_version 1d: tl-x.org
\SV

   // =========================================
   // Welcome!  Try the tutorials via the menu.
   // =========================================

   // Default Makerchip TL-Verilog Code Template
   
   // Macro providing required top-level module definition, random
   // stimulus support, and Verilator config.
   m4_makerchip_module   // (Expanded in Nav-TLV pane.)
//CLZ(count leading zeros) 
// eg. m4+clz_final(32,0,1,$reg_value, $resultq,|pipe, /clz_count1)

\TLV clz_final(#_varbits,#_stage,#_stageinc,$_data_value,$resultq,|pipe,/clz_stage)
   m4_pushdef(['m4_clz_stage'], m4_strip_prefix(/clz_stage))
   m4_ifelse_block(m4_eval(#_stage == 0 ), 1, ['
   /clz_stage['']#_stageinc[''][((#_varbits / 2) - 1) : 0]
      $clz_stage['']#_stageinc[['']#_stageinc : 0] = (|pipe$_data_value[((2*(#m4_clz_stage['']#_stageinc)) + 1) : (2*(#m4_clz_stage['']#_stageinc))] == 2'b00) ? 2'b10 :
                          (|pipe$_data_value[((2*(#m4_clz_stage['']#_stageinc)) + 1) : (2*(#m4_clz_stage['']#_stageinc))] == 2'b01) ? 2'b01 : 2'b00;
   m4+clz_final(m4_eval(#_varbits / 2), m4_eval(#_stage + 1),m4_eval(#_stageinc + 1), $clz_stage['']#_stageinc, $resultq, |pipe, /clz_stage)
   '],['
   /clz_stage['']#_stageinc[''][((#_varbits / 2) - 1) : 0]
      $clz_stage['']#_stageinc[['']#_stageinc : 0] = (|pipe/clz_stage['']#_stage[(2*(#m4_clz_stage['']#_stageinc)) + 1]$_data_value[#_stage] == 1'b1  && |pipe/clz_stage['']#_stage[2*(#m4_clz_stage['']#_stageinc)]$_data_value[#_stage] == 1'b1 ) ? {1'b1,#_stageinc'b0} :
                           (|pipe/clz_stage['']#_stage[(2*(#m4_clz_stage['']#_stageinc)) + 1]$_data_value[#_stage] == 1'b0) ? {1'b0,|pipe/clz_stage['']#_stage[(2*(#m4_clz_stage['']#_stageinc)) + 1]$_data_value[#_stage : 0]} : {2'b01,|pipe/clz_stage['']#_stage[(2*(#m4_clz_stage['']#_stageinc)) ]$_data_value[#_stage - 1 : 0]};
   m4_ifelse_block(m4_eval(#_varbits > 2), 1, ['
   m4+clz_final(m4_eval(#_varbits / 2), m4_eval(#_stage + 1),m4_eval(#_stageinc + 1), $clz_stage['']#_stageinc, $resultq, |pipe, /clz_stage)
   '], ['
   $resultq[['']#_stageinc : 0] = |pipe/clz_stage['']#_stageinc[0]$clz_stage['']#_stageinc[['']#_stageinc : 0];
   '])
   '])
   m4_popdef(['m4_clz_stage'])


\TLV
   $reset = *reset;

   m4_define(['EXPWIDTH'],['8'])
   m4_define(['SIGWIDTH'],['24'])
   m4_define(['NORMDISTWIDTH'],\$clog2(SIGWIDTH))
   
   |pipe
      @1
         `BOGUS_USE($in[31:0])

         {$sign,$expIn[7:0],$fracIn[22:0]} = $in;
         $isZeroExpIn = ($expIn == 0);
         $isZeroFractIn = ($fractIn == 0);
         
         $fractemp1[31:0] = {$fracIn[22:0], 9'b0} ;
         m4+clz_final(32,0,1,$fractemp1,$normDist,|pipe, /clz_count1)
         $subnormFract[SIGWIDTH - 2 : 0] = ($fracIn << $normDist) << 1;
         $adjustedExp[EXPWIDTH:0] = $isZeroExpIn ? ( {$normDist} ^ ((1 << (EXPWIDTH) + 1) - 1) ) : $expIn
                                     + ((1 << (EXPWIDTH - 1)) | ($isZeroExpIn ? 2'b10 : 1'b1));
         $isZero = $isZeroExpIn && $isZeroFractIn;
         $isSpecial = ($adjustedExp[EXPWIDTH : (EXPWIDTH - 1)] == 2'b11);

         $exp1[EXPWIDTH : (EXPWIDTH - 2)] = $isSpecial ? {2'b11, !$isZeroFractIn} : $isZero ? 3'b000 : $adjustedExp[EXPWIDTH : (EXPWIDTH - 2)];
         $exp2[(EXPWIDTH - 3) : 0] = $adjustedExp;
         $exp[EXPWIDTH : 0] = {$exp1 , $exp2};

         $out[(EXPWIDTH + SIGWIDTH) : 0] = {$sign, $exp, ($isZeroExpIn ? $subnormFract : $fracIn)};


   // Assert these to end simulation (before Makerchip cycle limit).
   *passed = *cyc_cnt > 40;
   *failed = 1'b0;
\SV
   endmodule
