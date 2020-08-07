\m4_TLV_version 1d: tl-x.org
\SV
// m4_define_vector(['M4_INSTR'], 32)					// ISA dependent instr width
// m4_define_vector(['M4_ADDR'], 32)					// ISA dependent address width
   m4_define_hier(['M4_DATA_MEM_WORDS'], 32)		// number of dmem locations	
   m4_define(['M4_BITS_PER_ADDR'], 8)  				// 8 for byte addressing.
   m4_define_vector(['M4_WORD'], 32)					// machine width (RV32/64)
   m4_define(['M4_ADDRS_PER_WORD'], m4_eval(M4_WORD_CNT / M4_BITS_PER_ADDR))
   m4_define(['M4_SUB_WORD_BITS'], m4_width(m4_eval(M4_ADDRS_PER_WORD - 1)))
//	m4_define_hier(M4_DATA_MEM_ADDRS, m4_eval(M4_DATA_MEM_WORDS_HIGH * M4_ADDRS_PER_WORD))  // Addressable data memory locations, 
                                                                                            //	can be useful in future

	module dmem_ext #(parameter SIZE = 1024, ADDR_WIDTH = 10, COL_WIDTH = 8, NB_COL	= 4) (
      input   clk,
      input   [NB_COL-1:0]	        we,            // for enabling individual column accessible (for writes)
      input   [ADDR_WIDTH-1:0]	    addr,      
      input   [NB_COL*COL_WIDTH-1:0]  din,
      output  [NB_COL*COL_WIDTH-1:0]  dout
   );
        
      reg [NB_COL*COL_WIDTH-1:0] outputreg;   
      reg	[NB_COL*COL_WIDTH-1:0] RAM [SIZE-1:0];
      
      always @(posedge clk) begin
            outputreg <= RAM[addr];
      end

      assign dout = outputreg;

      generate
            genvar i;
            for (i = 0; i < NB_COL; i = i+1) begin
            always @(posedge clk) begin 
               if (we[i]) 
                  RAM[addr][(i+1)*COL_WIDTH-1:i*COL_WIDTH] <= din[(i+1)*COL_WIDTH-1:i*COL_WIDTH];
               end
            end
      endgenerate
         
   endmodule 
   
   m4_makerchip_module   // (Expanded in Nav-TLV pane.)

\TLV fake_dmem_sv(/_top, /_scope, $_clk, $_addr, $_write, $_din, $_dout)
   /_scope
      \SV_plus
         dmem_ext #(
               .SIZE(M4_DATA_MEM_WORDS_HIGH), 
               .ADDR_WIDTH(M4_DATA_MEM_WORDS_INDEX_HIGH), 
               .COL_WIDTH(M4_WORD_HIGH / M4_ADDRS_PER_WORD), 
               .NB_COL(M4_ADDRS_PER_WORD)
               )
         dmem_ext (
               .clk     (/_top$_clk),
               .addr    (/_top$_addr[M4_DATA_MEM_WORDS_INDEX_MAX + M4_SUB_WORD_BITS : M4_SUB_WORD_BITS]),
               .we      (/_top$_write),
               .din     (/_top$_din), 
               .dout    (/_top$['']$_dout[31:0])
               );

\TLV
   |mem
      @0
         $clk = *clk;
         $addr[6:0]  =  (!(*reset) && *cyc_cnt < 3)  ? 6'h0  :
                        (*cyc_cnt < 4)  ? 6'h1  :
                        (*cyc_cnt < 5)  ? 6'h2  :
                        (*cyc_cnt < 6)  ? 6'h3  :
                        (*cyc_cnt < 7)  ? 6'h10 :
                        (*cyc_cnt < 9)  ? 6'h0  :
                        (*cyc_cnt < 10) ? 6'h4  :
                        (*cyc_cnt < 11) ? 6'h8  :
                        (*cyc_cnt < 12) ? 6'hc  : 
                                          6'hXX ;

         $write[3:0] =  (!(*reset) && *cyc_cnt <3) ?  4'b0001 :
                        (*cyc_cnt <4) ?  4'b0010 :
                        (*cyc_cnt <5) ?  4'b0100 : 
                        (*cyc_cnt <6) ?  4'b1000 :  
                        (*cyc_cnt <7) ?  4'b1111 :
                                         4'b0;
    
         $din[31:0]  =  (!(*reset) && *cyc_cnt < 3) ?  32'hCA :
                        (*cyc_cnt < 4) ?  32'hBA << 8 :
                        (*cyc_cnt < 5) ?  32'hDE << 16 :
                        (*cyc_cnt < 6) ?  32'h55 << 24:
                                          32'h1234 ;

         m4+fake_dmem_sv(|mem, /memscope, $clk, $addr, $write, $din, $dout)
         `BOGUS_USE($dout)
   // Assert these to end simulation (before Makerchip cycle limit).
   *passed = *cyc_cnt > 40;
   *failed = 1'b0;
\SV
   endmodule
