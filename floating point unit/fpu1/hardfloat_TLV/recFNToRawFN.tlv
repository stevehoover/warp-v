\m4_TLV_version 1d: tl-x.org
\SV

   // =========================================
   // Welcome!  Try the tutorials via the menu.
   // =========================================

   // Default Makerchip TL-Verilog Code Template
   
   // Macro providing required top-level module definition, random
   // stimulus support, and Verilator config.
   m4_makerchip_module   // (Expanded in Nav-TLV pane.)

\TLV
   $reset = *reset;

   m4_define(['EXPWIDTH'],['8'])
   m4_define(['SIGWIDTH'],['24'])
   //m4_define(['NORMDISTWIDTH'],\$clog(SIGWIDTH))
   
   |pipe
      @1
         `BOGUS_USE($in[32:0])

         { $sign,$exp[EXPWIDTH:0],$fract[(SIGWIDTH - 2):0] } = $in;
         
         $isSpecial = (($exp >> (EXPWIDTH - 1)) == 2'b11);

         $isNaN = $isSpecial && $exp[EXPWIDTH - 2];
         $isInf = $isSpecial && (! $exp[EXPWIDTH - 2]);
         $isZero = (($exp >> (EXPWIDTH - 2)) == 3'b000);
         $sexp[(EXPWIDTH + 1 ):0] = $exp;

         $sig[SIGWIDTH : 0] = {1'b0, {! $isZero}, $fract};


   // Assert these to end simulation (before Makerchip cycle limit).
   *passed = *cyc_cnt > 40;
   *failed = 1'b0;
\SV
   endmodule
