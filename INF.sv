/* Instruction-Fetch */
module INF(input clk,

	output ic_enable,
	output[63:0] iaddr,
	input[511:0] idata,
	input ic_done,

	input dc_if,
	output if_dc);

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
