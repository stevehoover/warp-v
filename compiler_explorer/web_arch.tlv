\m4_TLV_version 1d: tl-x.org
\SV

   m4_makerchip_module
\TLV comp_exp()
   /comp_exp
      /client
         $asm = /comp_exp/server/gcc$asm;
\TLV warpv(/_top)
   /sandpiper_saas
      $tlv = /_top/warpv/client$tlv_w_asm;
   /warpv
      /client
         $tlv = 1'b0;
         $sv = /_top/sandpiper_saas$tlv;
      
\TLV
   |all
      @1
         /today
            /comp_exp
               /client
                  $cpp = 1'b0;
               /server
                  /gcc
                     $asm = /comp_exp/client$cpp;
            m4+comp_exp()
            /warpv
               /client
                  $tlv_w_asm = $tlv + $asm;
            m4+warpv(/today)
         
         /abd_proposal
            /warpv
               /client
                  $cpp = 1'b0;
                  $tlv_w_asm = $tlv + /warpv/server$asm;
               /server
                  $asm = /abd_proposal/comp_exp/server/gcc$asm;
                  $cpp = /warpv/client$cpp;
            /comp_exp
               /server
                  /gcc
                     $asm = /abd_proposal/warpv/server$cpp;
            //m4+comp_exp()
            m4+warpv(/abd_proposal)

\SV
   endmodule
