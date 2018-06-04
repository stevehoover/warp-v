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
		.cyc_cnt   (32'b0	),
		.passed    (passed	),
		.failed    (failed	),
		`RVFI_CONN
);


endmodule

