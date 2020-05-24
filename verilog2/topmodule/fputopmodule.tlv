\m4_TLV_version 1d: tl-x.org
\SV
/*
Copyright (c) 2018, Steve Hoover
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice, this
  list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the copyright holder nor the names of its
  contributors may be used to endorse or promote products derived from
  this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// Include BaseJump STL FIFO files.
/* verilator lint_off CMPCONST */
/* verilator lint_off WIDTH */
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/HardFloat_consts.vi'])
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/HardFloat_localFuncs.vi'])
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/HardFloat_primitives.v'])
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/HardFloat_rawFN.v'])             
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/HardFloat_specialize.v'])
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/HardFloat_specialize.vi'])                   
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/addRecFN.v'])                  
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/compareRecFN.v'])                  
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/divSqrtRecFN_small.v'])                  
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/fNToRecFN.v'])                  
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/iNToRecFN.v'])    
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/isSigNaNRecFN.v'])   
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/mulAddRecFN.v'])            
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/mulRecFN.v'])                  
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/recFNToFN.v'])   
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/recFNToIN.v'])                    
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/floating-point/verilog2/recFNToRecFN.v'])                                     
/* verilator lint_on CMPCONST */

\TLV fpu_define(#_expwidth, #_sigwidth, #_intwidth)
    m4_define(['EXPWIDTH'], #_expwidth)
    m4_define(['SIGWIDTH'], #_sigwidth)
    m4_define(['INTWIDTH'], #_intwidth)


\TLV fn_to_rec(#_number, #_expwidth, #_sigwidth, $_input, $_output)   
   \SV_plus
       fNToRecFN#(#_expwidth, #_sigwidth)
       fNToRecFN#_number($_input[(#_expwidth + #_sigwidth) - 1 :0] , $['']$_output[(#_expwidth + #_sigwidth):0]);

\TLV add_sub_recfn(#_number, #_expwidth, #_sigwidth, $_control, $_subop, $_input1, $_input2, $_roundingmode, $_output, $_exceptionflags)
   \SV_plus
        addRecFN#(#_expwidth, #_sigwidth)
        addRecFN#_number($_control,$_subop,$_input1[(#_expwidth + #_sigwidth):0],$_input2[(#_expwidth + #_sigwidth):0],$_roundingmode[2:0],$['']$_output[(#_expwidth + #_sigwidth):0],$['']$_exceptionflags[4:0]);

\TLV mul_recfn(#_number, #_expwidth, #_sigwidth, $_control, $_input1, $_input2, $_roundingmode, $_output, $_exceptionflags)
   \SV_plus
        mulRecFN#(#_expwidth, #_sigwidth)
        mulRecFN#_number($_control,$_input1[(#_expwidth + #_sigwidth):0],$_input2[(#_expwidth + #_sigwidth):0],$_roundingmode[2:0],$['']$_output[(#_expwidth + #_sigwidth):0],$['']$_exceptionflags[4:0]);

\TLV div_sqrt_recfn_small(#_number, #_expwidth, #_sigwidth, $_nreset, $_clock, $_control, $_in_ready, $_in_valid, $_div_sqrt_op, $_input1, $_input2, $_roundingmode, $_out_valid, $_sqrtresult, $_output, $_exceptionflags)
   \SV_plus
        divSqrtRecFN_small#(#_expwidth, #_sigwidth)
        divSqrtRecFN_small#_number($_nreset,$_clock,$_control,$['']$_in_ready,$_in_valid,$_div_sqrt_op,$_input1[(#_expwidth + #_sigwidth):0],$_input2[(#_expwidth + #_sigwidth):0],$_roundingmode[2:0],$['']$_out_valid,$['']$_sqrtresult,$['']$_output[(#_expwidth+ #_sigwidth):0],$['']$_exceptionflags[4:0]);

\TLV compare_recfn(#_number, #_expwidth, #_sigwidth, $_input1, $_input2, $_signaling_compare, $_lt_compare, $_eq_compare, $_gt_compare, $_unordered, $_exceptionflags)
   \SV_plus
        compareRecFN#(#_expwidth, #_sigwidth)
        compareRecFN#_number($_input1[(#_expwidth + #_sigwidth):0],$_input2[(#_expwidth + #_sigwidth):0],$_signaling_compare,$['']$_lt_compare,$['']$_eq_compare,$['']$_gt_compare,$['']$_unordered ,$['']$_exceptionflags[4:0]);

\TLV mul_add_recfn(#_number, #_expwidth, #_sigwidth, $_control, $_op_mul_add, $_input1, $_input2, $_input3, $_roundingmode, $_output, $_exceptionflags)
   \SV_plus
        mulAddRecFN#(#_expwidth, #_sigwidth)
        mulAddRecFN#_number($_control,$_op_mul_add[1:0],$_input1[(#_expwidth + #_sigwidth):0],$_input2[(#_expwidth + #_sigwidth):0],$_input3[(#_expwidth + #_sigwidth):0],$_roundingmode[2:0],$['']$_output[(#_expwidth + #_sigwidth):0] ,$['']$_exceptionflags[4:0]);

\TLV rec_to_fn(#_number, #_expwidth, #_sigwidth, $_input, $_output)   
   \SV_plus
       recFNToFN#(#_expwidth, #_sigwidth)
       recFNToFN#_number($_input[(#_expwidth + #_sigwidth):0] , $['']$_output[(#_expwidth + #_sigwidth) - 1:0]);

\TLV int_to_recfn(#_number, #_expwidth, #_sigwidth, #_intwidth, $_control, $_signedin, $_input1, $_roundingmode, $_output, $_exceptionflags)
   \SV_plus
      iNToRecFN#(#_intwidth, #_expwidth, #_sigwidth)
      iNToRecFN#_number($_control,$_signedin,$_input1[(#_intwidth - 1):0],$_roundingmode[2:0],$['']$_output[(#_expwidth + #_sigwidth):0],$['']$_exceptionflags[4:0]);

\TLV recfn_to_int(#_number, #_expwidth, #_sigwidth, #_intwidth, $_control, $_signedout, $_input1, $_roundingmode, $_output, $_exceptionflags)
   \SV_plus
      recFNToIN#(#_expwidth, #_sigwidth, #_intwidth)
      recFNToIN#_number($_control,$_input1[(#_expwidth + #_sigwidth):0],$_roundingmode[2:0],$_signedout,$['']$_output[(#_intwidth - 1):0],$['']$_exceptionflags[2:0]);

\TLV sgn_mv_injn(#_expwidth, #_sigwidth, $_input1, $_input2, $_output)
   $_output[(#_expwidth + #_sigwidth) - 1 : 0] = { $_input2[(#_expwidth + #_sigwidth) - 1] , $_input1[(#_expwidth + #_sigwidth) - 2 : 0]};

\TLV sgn_neg_injn(#_expwidth, #_sigwidth, $_input1, $_input2, $_output)
   $_output[(#_expwidth + #_sigwidth) - 1 : 0] = { ! {$_input2[(#_expwidth + #_sigwidth) - 1]} , { { ((#_expwidth + #_sigwidth) - 1){1'b1} } ^ $_input1[(#_expwidth + #_sigwidth) - 2 : 0]} };

\TLV sgn_abs_injn(#_expwidth, #_sigwidth, $_input1, $_input2, $_output)
   $_output[(#_expwidth + #_sigwidth) - 1 : 0] = { {$_input1[(#_expwidth + #_sigwidth) - 1] ^ $_input2[(#_expwidth + #_sigwidth) - 1]} , $_input1[(#_expwidth + #_sigwidth) - 2 : 0]};

\TLV is_sig_nan(#_number, #_expwidth, #_sigwidth, $_input1, $_issignan)
   \SV_plus
      isSigNaNRecFN#(#_expwidth, #_sigwidth) 
      isSigNaNRecFN#_number($_input1[(#_expwidth + #_sigwidth):0],$['']$_issignan);
   
\TLV fpu_exe(/_name, /_top, #_expwidth, #_sigwidth, #_intwidth, $_input1, $_input2, $_input3, $_int_input, $_int_output, $_operation, $_roundingmode, $_nreset, $_clock, $_input_valid, $_outvalid, $_lt_compare, $_eq_compare, $_gt_compare, $_unordered, $_output, $_output_class, $_exception_invaild_output, $_exception_infinite_output, $_exception_overflow_output, $_exception_underflow_output, $_exception_inexact_output, $_divide_by_zero) 
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
      
      m4+fn_to_rec(1, #_expwidth, #_sigwidth, /_top['']$_input1, $fnToRec_a) 
      m4+fn_to_rec(2, #_expwidth, #_sigwidth, /_top['']$_input2, $fnToRec_b) 
      m4+fn_to_rec(3, #_expwidth, #_sigwidth, /_top['']$_input3, $fnToRec_c) 
      
      $is_operation_int_to_recfn = (/_top['']$_operation == 5'h17  ||  /_top['']$_operation == 5'h18);
      ?$is_operation_int_to_recfn
         $signedin = (/_top['']$_operation == 5'h17) ? 1'b1 : 1'b0 ;
         m4+int_to_recfn(1, #_expwidth, #_sigwidth, #_intwidth, $control, $signedin, /_top['']$_int_input, /_top['']$_roundingmode, $output_int_to_recfn, $exceptionFlags_int_to_recfn)
         
      
      $is_operation_class = (/_top['']$_operation == 5'h16);
      ?$is_operation_class
         m4+is_sig_nan(1, #_expwidth, #_sigwidth, $fnToRec_a, $issignan)
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
         m4+add_sub_recfn(1, #_expwidth, #_sigwidth, $control, $subOp, $fnToRec_a, $fnToRec_b, /_top['']$_roundingmode, $output_add_sub, $exceptionFlags_add_sub)
         
      $is_operation_mul = (/_top['']$_operation == 5'h8);
      ?$is_operation_mul
         m4+mul_recfn(1, #_expwidth, #_sigwidth, $control, $fnToRec_a, $fnToRec_b, /_top['']$_roundingmode, $output_mul, $exceptionFlags_mul)
         
      $is_operation_div_sqrt = (/_top['']$_operation == 5'h9 || /_top['']$_operation == 5'ha);
      ?$is_operation_div_sqrt
         $div_sqrt_Op = (/_top['']$_operation == 5'h9) ? 1'b0 : 1'b1;
         //<Currently it's just one time>
         
         $get_valid = /_top['']$_input_valid;
         
         $operand_div_sqrt_a[(#_expwidth + #_sigwidth):0] = ($get_valid) ? $fnToRec_a[(#_expwidth + #_sigwidth):0] : $RETAIN;
         $operand_div_sqrt_b[(#_expwidth + #_sigwidth):0] = ($get_valid) ? $fnToRec_b[(#_expwidth + #_sigwidth):0] : $RETAIN;
         
         m4+div_sqrt_recfn_small(1, #_expwidth, #_sigwidth, /_top['']$_nreset, /_top['']$_clock, $control, $in_ready, /_top['']$_input_valid, $div_sqrt_Op, $operand_div_sqrt_a, $operand_div_sqrt_b, /_top['']$_roundingmode, $_outvalid, $sqrtresult, $output_div_sqrt, $exceptionFlags_div_sqrt)
         $result_div_sqrt_temp[(#_expwidth + #_sigwidth):0] = ($_outvalid == 1) ? $output_div_sqrt : $RETAIN;
         
      $is_operation_compare = (/_top['']$_operation == 5'he || /_top['']$_operation == 5'hf || /_top['']$_operation == 5'h13 || /_top['']$_operation == 5'h14 || /_top['']$_operation == 5'h15);
      ?$is_operation_compare
         $signaling_compare =  ($fnToRec_a == $fnToRec_b) ? 1'b0 : 1'b1;
         m4+compare_recfn(1, #_expwidth, #_sigwidth, $fnToRec_a, $fnToRec_b, $signaling_compare, $_lt_compare, $_eq_compare, $_gt_compare, $_unordered, $exceptionFlags_compare)
         $output_min[(#_expwidth + #_sigwidth):0] = ($_gt_compare == 1'b1) ? $fnToRec_b : $fnToRec_a;
         $output_max[(#_expwidth + #_sigwidth):0] = ($_gt_compare == 1'b1) ? $fnToRec_a : $fnToRec_b;
         
      $is_operation_mul_add = (/_top['']$_operation == 5'h2 || /_top['']$_operation == 5'h3 || /_top['']$_operation == 5'h4 || /_top['']$_operation == 5'h5);
      ?$is_operation_mul_add
         $op_mul_add[1:0] = (/_top['']$_operation == 5'h2) ? 2'b00 :
                     (/_top['']$_operation == 5'h3) ? 2'b01 :
                     (/_top['']$_operation == 5'h4) ? 2'b10 :
                     (/_top['']$_operation == 5'h5) ? 2'b11 : 2'hx;
         m4+mul_add_recfn(1, #_expwidth, #_sigwidth, $control, $op_mul_add, $fnToRec_a, $fnToRec_b, $fnToRec_c, /_top['']$_roundingmode, $output_mul_add, $exceptionFlags_mul_add)
         
      $final_output_module[(#_expwidth + #_sigwidth):0] = (/_top['']$_operation == 5'h2 || /_top['']$_operation == 5'h3 || /_top['']$_operation == 5'h4 || /_top['']$_operation == 5'h5) ? $output_mul_add :
                                                      (/_top['']$_operation == 5'h6 || /_top['']$_operation == 5'h7) ? $output_add_sub :
                                                      (/_top['']$_operation == 5'h8) ? $output_mul :
                                                      (/_top['']$_operation == 5'h9 || /_top['']$_operation == 5'ha) ? $output_div_sqrt :
                                                      (/_top['']$_operation == 5'he) ? $output_min :
                                                      (/_top['']$_operation == 5'hf) ? $output_max :
                                                      (/_top['']$_operation == 5'h17  ||  /_top['']$_operation == 5'h18) ? $output_int_to_recfn : 0;
      
      $is_operation_recfn_to_int = (/_top['']$_operation == 5'h10  ||  /_top['']$_operation == 5'h11);
      ?$is_operation_recfn_to_int
         $signedout = (/_top['']$_operation == 5'h10) ? 1'b1 : 1'b0 ;
         m4+recfn_to_int(1, #_expwidth, #_sigwidth, #_intwidth, $control, $signedout, $fnToRec_a, /_top['']$_roundingmode, $_int_output, $exceptionFlags_recfn_to_int)
         
      m4+rec_to_fn(1, #_expwidth, #_sigwidth, $final_output_module, $result_fn)
      
      $_output[(#_expwidth + #_sigwidth) - 1:0] = $result_fn;
      
      $exceptionFlags_all[4:0] =    ({5{$is_operation_add_sub}} & $exceptionFlags_add_sub) |
                                   ({5{$is_operation_mul}} & $exceptionFlags_mul) |
                              ({5{$is_operation_div_sqrt}} & $exceptionFlags_div_sqrt) |
                               ({5{$is_operation_compare}} & $exceptionFlags_compare) |
                               ({5{$is_operation_mul_add}} & $exceptionFlags_mul_add) |
                          ({5{$is_operation_int_to_recfn}} & $exceptionFlags_int_to_recfn) |
                          ({5{$is_operation_recfn_to_int}} & $exceptionFlags_recfn_to_int);
      {$_exception_invaild_output, $_exception_infinite_output, $_exception_overflow_output, $_exception_underflow_output, $_exception_inexact_output} = $exceptionFlags_all[4:0];
      $_divide_by_zero = (/_top['']$operation == 4'h3 || /_top['']$operation == 4'h4) ? $exceptionFlags_div_sqrt[3] : 1'b0;
