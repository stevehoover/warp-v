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
   |pipe
      @0
         /* FPU Module
         input		clk;
         input	[1:0]	rmode;
         input	[2:0]	fpu_op;
         input	[31:0]	opa, opb;
         output	[31:0]	out;
         output		inf, snan, qnan;
         output		ine;
         output		overflow, underflow;
         output		zero;
         output		div_by_zero;
         */
         /* rmode[1:0] 
            0 Round to nearest even
            1 Round to Zero
            2 Round to +INF (UP)
            3 Round to -INF (DOWN)
         */
         /* fpu_op[2:0]
            0 Add
            1 Subtract
            2 Multiply
            3 Divide
            4 //(Int to float conversion)  
            5 //(Float to int conversion)
            6 //(Remainder (Future Function))
            7 //(RESERVED)
         */

        
         $rmode[1:0] = 2'b00; //Input
         $fpu_op = 3'b000; // Input
         $op1[31:0] = 32'b01000011000001110010011100111000; //Input
         $op2[31:0] = 32'b01000010000101011011110110010100; //Input

         $opa_nan = 0;
         $opb_nan = 0;
         $add = 1;
         $opcode[2:0] = 3'b000;
         $add_d = ($opcode == 3'b000) ? 1'b1 : 1'b0 ;
         $sub_d = ($opcode == 3'b001) ? 1'b1 : 1'b0 ;
         // pre normalizing of floating point unit
         
         
         
         $signa = $op1[31];
         $signb = $op2[31];
         $expa[7:0] = $op1[30:23];
         $expb[7:0] = $op2[30:23];
         $fracta[22:0] = $op1[22:0];
         $fractb[22:0] = $op2[22:0];
         
         $expa_gt_expb = ($expa > $expb) ? 1'b1 : 1'b0;
         $expa_dn = !(| $expa);
         $expb_dn = !(| $expb);
         $exp_diff1[7:0] = ($expa_gt_expb == 1'b1) ? ($expa - $expb) : ($expb - $expa);
         $exp_diff[7:0] = ($expa_dn & $expb_dn) ? 8'h0 : ($expa_dn | $expb_dn) ? ($exp_diff1 - 1) : $exp_diff1;
         //If numbers are same is should return zero else return larger number
         $exp_dn_out[7:0] = (! $add_d & ($expa == $expb) & ($fracta == $fractb)) ? 8'h0 : ($expa_gt_expb == 1'b1) ? $expa : $expb;
         
         //checking if smaller fraction is denormalized
         $op_dn = $expa_gt_expb ? $expb_dn : $expa_dn;
         $adj_op[22:0] = $expa_gt_expb ? $fractb : $fracta;
         $adj_op_tmp[26:0] = {! $op_dn, $adj_op, 3'b0};
         
         $exp_diff_sft[4:0] = ($exp_diff > 27) ? 4'd27 : $exp_diff[4:0];
         $adj_op_out_sft[26:0] = $adj_op_tmp >> $exp_diff_sft;
         
         //copy of adj_op_tmp
         //$cpy_adj_op_temp[26:0] = $adj_op_tmp;
         $sticky = ($exp_diff_sft == 0) ? 1'h0 : (| ($adj_op_out_sft << (32 - $exp_diff_sft)));
         $adj_op_out[26:0] = {$adj_op_out_sft[26:1], $sticky };
         //Selecting operands for ADD/SUB
         $fracta_n[26:0] = $expa_gt_expb ? {! $expa_dn, $fracta, 3'b0} : $adj_op_out;
         $fractb_n[26:0] = $expa_gt_expb ? $adj_op_out : {! $expb_dn, $fractb, 3'b0};
         // Sorting operands (only for SUB)
         $fractb_gt_fracta = $fractb_n > $fracta_n;
         $fracta_lt_fractb = $fracta < $fractb;
         $fracta_eq_fractb = $fracta == $fractb;
         
         $fracta_s[26:0] = $fractb_gt_fracta ? $fractb_n : $fracta_n;
         $fractb_s[26:0] = $fractb_gt_fracta ? $fracta_n : $fractb_n;
         $fracta_out[26:0] = $fracta_s;
         $fractb_out[26:0] = $fractb_s;
         // Determine sign for the output [sign: 0=Positive Number; 1=Negative Number]
         $sign_temp1[2:0] = {$signa,$signb,$add};
         $sign_d = //ADD Case
                   ($sign_temp1 == 3'b001) ? 1'b0 : 
                   ($sign_temp1 == 3'b011) ? $fractb_gt_fracta : 
                   ($sign_temp1 == 3'b101) ? !$fractb_gt_fracta : 
                   ($sign_temp1 == 3'b111) ? 1'b1 : 
                   //SUB Case
                   ($sign_temp1 == 3'b000) ? $fractb_gt_fracta : 
                   ($sign_temp1 == 3'b010) ? 1'b0 : 
                   ($sign_temp1 == 3'b100) ? 1'b1 : !$fractb_gt_fracta;
         
         $sign = $sign_d;
         //Fix sign for Zero result
         $result_zero_sign = ( $add &  $signa &  $signb) | (!$add &  $signa & !$signb) | ( $add & ($signa |  $signb) & ($rmode==3)) | (!$add & ($signa == $signb) & ($rmode==3));
         //Fix sign for NAN result
         $nan_sign1 = $fracta_eq_fractb ? ($signa & $signb) : $fracta_lt_fractb ? $signb : $signa;
         $nan_sign =  ($opa_nan & $opb_nan) ? $nan_sign1 : $opb_nan ? $signb : $signa;
         
         // Decode add/sub operation
         // add: 1=Add; 0=Subtract
         $add_dd =  ($sign_temp1 == 3'b001 ) ? 1'b1 :
                   ($sign_temp1 == 3'b011) ? 1'b0 :
                   ($sign_temp1 == 3'b101) ? 1'b0 :
                   ($sign_temp1 == 3'b111) ? 1'b1 :
                   //Sub
                   ($sign_temp1 == 3'b000) ? 1'b0 :
                   ($sign_temp1 == 3'b010) ? 1'b1 :
                   ($sign_temp1 == 3'b100) ? 1'b1 : 1'b0;
         $fasu_op = $add_dd;
         $ieeeans1[35:0] = {$signa,$exp_dn_out,$fracta_out};
         $ieeeans2[35:0] = {$signb,$exp_dn_out,$fractb_out};
         
         // Add/SUB Happens Here......
         {$co, $sum[26:0]} = $add ? ($fracta_out + $fractb_out) : ($fracta_out - $fractb_out);
         //
         // In FPU Unit
         $fract_out_d[26:0] = $sum;
         $fract_out_q[26:0] = {$co, $fract_out_d};
         $exp_r[7:0] = $exp_dn_out;
         
         $sign_fasu = $sign;

         //
         // In Post_normalize
         $fract_denorm[47:0] = {$fract_out_q, 20'h0};
         $exp_in[7:0] = $exp_r;

         $fract_in[47:0] = $fract_denorm;
         $fract_in_tempclz[63:0] = $fract_in;
         
         m4+clz_final(64,0,1,$fract_in_tempclz, $res1,|pipe, /clz_count1)
         $fi_ldz[5:0] = $res1 + 1 - 16 ;

         $exp_in_ff = (& $exp_in);
         $exp_in_00 = !(| $exp_in);
         $exp_in_80 = ($exp_in[7] & !(| $exp_in[6:0]));

         $fract_in_00  = !(| $fract_in);
         
         $rmode_00 = ($rmode == 2'b00);
         $rmode_01 = ($rmode == 2'b01);
         $rmode_10 = ($rmode == 2'b10);
         $rmode_11 = ($rmode == 2'b11);
         
         $fi_ldz_mi1[5:0] = $fi_ldz - 1;
         $fi_ldz_mi22[5:0] = $fi_ldz - 22;
         $exp_in_pl1[8:0]    = $exp_in  + 1;// 9 bits - includes carry out
         $exp_in_mi1[8:0]    = $exp_in  - 1;// 9 bits - includes carry out
         $exp_next_mi[8:0]  = $exp_in_pl1 - $fi_ldz_mi1;// 9 bits - includes carry out

         $dn = ($exp_in_00 | ($exp_next_mi[8] & (! $fract_in[47])) );
         
         {$exp_out1_co, $exp_out1[7:0]} = $fract_in[47] ? $exp_in_pl1 : $exp_next_mi;
         $exp_out[7:0] =  $dn ? {6'h0, $fract_in[47:46]} : $exp_out1[7:0];

         $exp_out_pl1[7:0]   = $exp_out + 1;
         $exp_out_mi1[7:0]   = $exp_out - 1;
         $exp_out1_mi1[7:0]  = $exp_out1 - 1;
         $exp_out_ff = &$exp_out;
         $exp_out_00 = !(|$exp_out);
         $exp_out_fe = (& $exp_out[7:1]) & (! $exp_out[0]);
         $exp_out_final_ff = & $exp_out_final;

         $fasu_shift[7:0]  = ($dn | $exp_out_00) ? ($exp_in_00 ? 8'h2 : $exp_in_pl1[7:0]) : {2'h0, $fi_ldz};

         $shift_left[7:0]  = $fasu_shift;

         $fract_in_shftl[47:0] = $fract_in << $shift_left[5:0];

         {$fract_out[22:0],$fract_trunc[24:0]} = $fract_in_shftl;
         $fract_out_7fffff = & $fract_out;
         $fract_out_00 = !(| $fract_out);
         $fract_out_pl1[23:0] = $fract_out + 1;

         //Rounding
         $gg = $fract_out[0];
         $rr = $fract_trunc[24];
         //Rounding to nearest even
         $round = ($gg & $rr);
         {$exp_rnd_adj0, $fract_out_rnd0[22:0]} = $round ? $fract_out_pl1 : {1'b0, $fract_out};
         $exp_out_rnd0[7:0] =  $exp_rnd_adj0 ? $exp_out_pl1 : $exp_out;
         $ovf0 = $exp_out_final_ff & (! $rmode_01);
         // round to zero
         $fract_out_rnd1[22:0] = ($exp_out_ff & !$dn) ? 23'h7fffff : $fract_out;
         $exp_out_rnd1   = ($gg & $rr & $exp_in_ff) ? $exp_next_mi[7:0] : $exp_out_ff ? $exp_in : $exp_out;
         $ovf1 = $exp_out_ff & !$dn;
         // round to +inf (UP) and -inf (DOWN)
         $r_sign = $sign;
         $round2a = !$exp_out_fe | !$fract_out_7fffff | ($exp_out_fe & $fract_out_7fffff);
         $round2_fasu = (($rr) & !$r_sign) & (!$exp_out[7] | ($exp_out[7] & $round2a));
         $round2 = $round2_fasu;

         {$exp_rnd_adj2a, $fract_out_rnd2a[22:0]} = $round2 ? $fract_out_pl1 : {1'b0, $fract_out};
         $exp_out_rnd2a[7:0]  = $exp_rnd_adj2a ? ($exp_out_pl1) : $exp_out;
         $fract_out_rnd2[22:0] = ($r_sign & $exp_out_ff & (! $dn) ) ? 23'h7fffff : $fract_out_rnd2a;
         $exp_out_rnd2[7:0]   = ($r_sign & $exp_out_ff) ? 8'hfe : $exp_out_rnd2a;
         
         // Choose rounding mode
         $exp_out_rnd[7:0] = ($rmode == 2'b00) ? $exp_out_rnd0 :
                             ($rmode == 2'b01) ? $exp_out_rnd1 :
                             (($rmode == 2'b10) | ($rmode == 2'b11)) ? $exp_out_rnd2 : $exp_out_rnd0;

         $fract_out_rnd[22:0] = ($rmode == 2'b00) ? $fract_out_rnd0 :
                                ($rmode == 2'b01) ? $fract_out_rnd1 :
                                (($rmode == 2'b10) | ($rmode == 2'b11)) ? $fract_out_rnd2 : $fract_out_rnd0;

         $exp_out_final[7:0] = $exp_out_rnd;
         $fract_out_final[22:0] = $fract_out_rnd;
         $out[31:0] = {$r_sign,$exp_out_final, $fract_out_final};
   

   // Assert these to end simulation (before Makerchip cycle limit).
   *passed = *cyc_cnt > 40;
   *failed = 1'b0;
\SV
   endmodule