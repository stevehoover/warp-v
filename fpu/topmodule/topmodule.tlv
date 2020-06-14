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
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/HardFloat_consts.vi'])
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/HardFloat_localFuncs.vi'])
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/HardFloat_primitives.v'])
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/HardFloat_rawFN.v'])             
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/HardFloat_specialize.v'])
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/HardFloat_specialize.vi'])                   
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/addRecFN.v'])                  
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/compareRecFN.v'])                  
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/divSqrtRecFN_small.v'])                  
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/fNToRecFN.v'])                  
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/iNToRecFN.v'])    
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/isSigNaNRecFN.v'])   
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/mulAddRecFN.v'])            
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/mulRecFN.v'])                  
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/recFNToFN.v'])   
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/recFNToIN.v'])                    
m4_sv_include_url(['https://raw.githubusercontent.com/vineetjain07/warp-v/master/fpu/recFNToRecFN.v'])                                     
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
   
