\m4_TLV_version 1d -p verilog: tl-x.org
m4+definitions
   m4_define(['M4_ISA'], ['RISCV'])
   // Configure for formal verification.
   m4_define(['M4_FORMAL'], 1)
   m4_define(['M4_OPENPITON'], 0)
   m4_define(['M4_RISCV_FORMAL_ALTOPS'], 1)
   m4_define(['M4_VIZ'], 0)
   m4_define(['M4_STANDARD_CONFIG'], ['1-stage'])

\SV
   // Include WARP-V.
   m4_include_lib(['./warp-v.tlv'])
   module dmem_ext #(parameter SIZE = 1024, ADDR_WIDTH = 10, COL_WIDTH = 8, NB_COL	= 4) (
      input    clk,
      input    mem_valid,
      input    mem_instr,
      //output   mem_ready,
      input    mem_ready,
      input    [NB_COL*COL_WIDTH-1:0]  mem_addr,
      input    [NB_COL*COL_WIDTH-1:0]  mem_wdata,
      input    [NB_COL-1:0]            mem_wstrb,
      output   [NB_COL*COL_WIDTH-1:0]  mem_rdata
   );
      //
      //assign mem_ready = 1'b1;
      reg [31:0] counter;
      always @(posedge clk) begin
         //if(reset)
   //               counter <= 0;
   //            else
            counter <= counter + 1'b1;
      end
      /* verilator lint_off WIDTH */
      //assign mem_ready = (counter % 2 == 0);
      /* verilator lint_on WIDTH */
      reg [NB_COL*COL_WIDTH-1:0] outputreg;   
      reg [NB_COL*COL_WIDTH-1:0] RAM [SIZE-1:0];
      //
      always @(posedge clk) begin
         if(mem_ready) begin      //checking wstrb might be optional here
            outputreg <= RAM[mem_addr];
         end
      end
      //
      assign mem_rdata = outputreg;
      //
      wire valid_write_locn;
      assign valid_write_locn =  (mem_wstrb == 4'b1111) ||
                                 (mem_wstrb == 4'b1100) ||
                                 (mem_wstrb == 4'b0011) ||
                                 (mem_wstrb == 4'b1000) ||
                                 (mem_wstrb == 4'b0100) ||
                                 (mem_wstrb == 4'b0010) ||
                                 (mem_wstrb == 4'b0001) ;
      //
      generate
            genvar i;
            for (i = 0; i < NB_COL; i = i+1) begin
            always @(posedge clk) begin 
               if (mem_valid && mem_wstrb[i] && valid_write_locn) 
                  RAM[mem_addr][(i+1)*COL_WIDTH-1:i*COL_WIDTH] <= mem_wdata[(i+1)*COL_WIDTH-1:i*COL_WIDTH];
               end
            end
      endgenerate        
   endmodule
m4+module_def
\TLV
   m4+warpv()
\SV
   endmodule
