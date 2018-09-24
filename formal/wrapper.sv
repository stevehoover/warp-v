module rvfi_wrapper (
	input         clock,
	input         reset,
	`RVFI_OUTPUTS
);

(* keep *) wire passed;
(* keep *) wire failed;

	warpv uut (
		.clk       (clock   ),
		.reset     (reset   ),
		`RVFI_CONN
);


endmodule

