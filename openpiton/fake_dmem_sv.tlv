\m4_TLV_version 1d: tl-x.org
\SV
   m4_define_hier(['M4_DATA_MEM_WORDS'], 32)
   m4_define_vector(['M4_INSTR'], 32)
   m4_define_vector(['M4_ADDR'], 32)
   m4_define(['M4_BITS_PER_ADDR'], 8)  // 8 for byte addressing.
   m4_define_vector(['M4_WORD'], 32)
   // Default Makerchip TL-Verilog Code Template
   m4_define(['M4_ADDRS_PER_WORD'], m4_eval(M4_WORD_CNT / M4_BITS_PER_ADDR))
   m4_define(['M4_SUB_WORD_BITS'], m4_width(m4_eval(M4_ADDRS_PER_WORD - 1)))

	module twoport4(
      input logic clk,
      input logic rst,
      input logic [6:0] ra, wa,
      input logic write,
      input logic [31:0] d,
      output logic [31:0] q);
      
      logic [31:0] mem [0:127];
      
      integer i;
         
      always_ff @(posedge clk) begin
      if(rst) begin
         for(i=0;i<128;i=i+1)
           assign mem[i] = 0;
      end
      else begin
         if (write) mem[wa] <= d;
         q <= mem[ra];
      end
      end
      
   endmodule 
   // =========================================
   // Welcome!  Try the tutorials via the menu.
   // =========================================
   
   // Macro providing required top-level module definition, random
   // stimulus support, and Verilator config.
   m4_makerchip_module   // (Expanded in Nav-TLV pane.)

\TLV fake_dmem_sv(/_top, /_scope, $_clk, $_rst, $_ra, $_wa, $_write, $_d, $_q)
   /_scope
      \SV_plus
         twoport4 twoport4(.clk     (/_top$_clk),
                           .rst     (/_top$_rst),
                           .ra      (/_top$_ra),
                           .wa      (/_top$_wa),
                           .write   (/_top$_write),
                           .d       (/_top$_d), 
                           .q       (/_top$['']$_q[31:0]));

\TLV
   |mem
      @0
         $reset = *reset;
         $clk = *clk;
         $ra[6:0] =  (*cyc_cnt < 3) ? 6'h0 :
                     (*cyc_cnt < 4) ? 6'h1 :
                     (*cyc_cnt < 5) ? 6'h2 :
                     (*cyc_cnt < 6) ? 6'h3 :
                                      6'h4 ;

         $wa[6:0] =  (*cyc_cnt < 2) ? 6'h0 :
                     (*cyc_cnt < 3) ? 6'h1 :
                     (*cyc_cnt < 4) ? 6'h2 :
                     (*cyc_cnt < 5) ? 6'h3 :
                                      6'h10 ;
         //$wa[6:0] = 6'b0;
         $write = 1'b1;
         $d[31:0] =  (*cyc_cnt < 2) ? 32'hCAFE :
                     (*cyc_cnt < 3) ? 32'hBABE :
                     (*cyc_cnt < 4) ? 32'hDEAD :
                     (*cyc_cnt < 5) ? 32'h5555 :
                                      32'h1234 ;
      //|mem
         m4+fake_dmem_sv(|mem, /memscope, $clk, $reset, $ra, $wa, $write, $d, $q)

   // Assert these to end simulation (before Makerchip cycle limit).
   *passed = *cyc_cnt > 40;
   *failed = 1'b0;
\SV
   endmodule
