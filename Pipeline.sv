`include "instruction.svh"
`include "gpr.svh"

module Pipeline (
	input clk,

	/* For IF */

	/* For DC */
	input dc_instr dc_result,
	output taken
	
	/* For DF */

	/* For EXE */

	/* For WB */
);
	enum { stage_if, stage_id, stage_ex, stage_mem, stage_wb } stage;

	logic[31:0] regs_occupied;

	initial begin
		for (int i = 0; i < 31; i++)
			regs_occupied[i] = 0;
	end

	always_ff @(posedge clk) begin
		taken <= 1;
	end
endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
