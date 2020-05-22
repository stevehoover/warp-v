\m4_TLV_version 1d: tl-x.org
\SV

   // =========================================
   // Welcome!  Try the tutorials via the menu.
   // =========================================

   // Default Makerchip TL-Verilog Code Template
   /* verilator lint_off WIDTH */
   /* verilator lint_off CASEINCOMPLETE */
   module picorv32_pcpi_div (
	input clk, resetn,
	input             pcpi_valid,
	input      [31:0] pcpi_insn,
	input      [31:0] pcpi_rs1,
	input      [31:0] pcpi_rs2,
	output reg        pcpi_wr,
	output reg [31:0] pcpi_rd,
	output reg        pcpi_wait,
	output reg        pcpi_ready
);
	reg instr_div, instr_divu, instr_rem, instr_remu;
	wire instr_any_div_rem = |{instr_div, instr_divu, instr_rem, instr_remu};

	reg pcpi_wait_q;
	wire start = pcpi_wait && !pcpi_wait_q;

	always @(posedge clk) begin
		instr_div <= 0;
		instr_divu <= 0;
		instr_rem <= 0;
		instr_remu <= 0;

		if (resetn && pcpi_valid && !pcpi_ready && pcpi_insn[6:0] == 7'b0110011 && pcpi_insn[31:25] == 7'b0000001) begin
			case (pcpi_insn[14:12])
				3'b100: instr_div <= 1;
				3'b101: instr_divu <= 1;
				3'b110: instr_rem <= 1;
				3'b111: instr_remu <= 1;
			endcase
		end

		pcpi_wait <= instr_any_div_rem && resetn;
		pcpi_wait_q <= pcpi_wait && resetn;
	end

	reg [31:0] dividend;
	reg [62:0] divisor;
	reg [31:0] quotient;
	reg [31:0] quotient_msk;
	reg running;
	reg outsign;

	always @(posedge clk) begin
		pcpi_ready <= 0;
		pcpi_wr <= 0;
		pcpi_rd <= 0;

		if (!resetn) begin
			running <= 0;
		end else
		if (start) begin
			running <= 1;
			dividend <= (instr_div || instr_rem) && pcpi_rs1[31] ? -pcpi_rs1 : pcpi_rs1;
			divisor <= ((instr_div || instr_rem) && pcpi_rs2[31] ? -pcpi_rs2 : pcpi_rs2) << 31;
			outsign <= (instr_div && (pcpi_rs1[31] != pcpi_rs2[31]) && |pcpi_rs2) || (instr_rem && pcpi_rs1[31]);
			quotient <= 0;
			quotient_msk <= (1 << 31);
		end else
		if ((quotient_msk==0) && running) begin
         running <= 0;
			pcpi_ready <= 1;
			pcpi_wr <= 1;
			if (instr_div || instr_divu)
				pcpi_rd <= outsign ? -quotient : quotient;
			else
				pcpi_rd <= outsign ? -dividend : dividend;
		end else begin
			if (divisor <= dividend) begin
				dividend <= dividend - divisor;
				quotient <= quotient | quotient_msk;
			end
			divisor <= (divisor >> 1);
			quotient_msk <= quotient_msk >> 1;
		end
	end
endmodule
   // Macro providing required top-level module definition, random
   // stimulus support, and Verilator config.
   /* verilator lint_off WIDTH */
   m4_makerchip_module   // (Expanded in Nav-TLV pane.)
   
\TLV
   $reset = *reset;
   
   $pcpi_insn[31:0] = {7'b0000001,10'b0011000101,3'b100, 5'b00101,7'b0110011}; //change 3 part for DIV, DIVU..
   $pcpi_rs1[31:0] = 32'h12345678;
   $pcpi_rs2[31:0] = 32'h5678;
   $pcpi_valid = 1'b1;
   
   \SV_plus
      picorv32_pcpi_div div(
         .clk(clk), 
         .resetn(!reset),
         .pcpi_valid($pcpi_valid),
         .pcpi_insn($pcpi_insn),
         .pcpi_rs1($pcpi_rs1),
         .pcpi_rs2($pcpi_rs2),
         .pcpi_wr($$pcpi_wr),
         .pcpi_rd($$pcpi_rd[31:0]),
         .pcpi_wait($$pcpi_wait),
         .pcpi_ready($$pcpi_ready)
         );

   // Assert these to end simulation (before Makerchip cycle limit).
   *passed = *cyc_cnt > 50;
   *failed = 1'b0;
\SV
   endmodule
