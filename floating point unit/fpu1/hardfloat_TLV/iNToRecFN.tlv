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

   m4_define(['INTWIDTH'],['32'])
   m4_define(['EXPWIDTH'], ['\$clog2(INTWIDTH) + 1'])
   m4_define(['EXTINTWIDTH'], ['1 << (EXPWIDTH - 1)'])

   
   |pipe
      @1
         //`BOGUS_USE($in[32:0])
         $in[(INTWIDTH - 1):0] = 32'ha5464eb1;
         
         $sign = $signedIn && $in[INTWIDTH - 1];
         $absIn[(INTWIDTH - 1):0] = $sign ? -$in : $in;
         $extAbsIn[(EXTINTWIDTH):0] = $absIn;
         //$adjustedNormDist[(EXPWIDTH -2):0];
         m4+clz_final(32,0,1,$extAbsIn, $adjustedNormDist,|pipe, /clz_count1)

         $sig[INTWIDTH:0] = ($extAbsIn << $adjustedNormDist) >> (EXTINTWIDTH - INTWIDTH);
         $isZero = !$sig[INTWIDTH - 1];
         $sexp[(EXPWIDTH + 1):0] = {2'b10, ! $adjustedNormDist};




   // Assert these to end simulation (before Makerchip cycle limit).
   *passed = *cyc_cnt > 40;
   *failed = 1'b0;
\SV
   endmodule
