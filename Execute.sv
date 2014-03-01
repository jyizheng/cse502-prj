`include "instruction.svh"

module Execute (
	input clk,
	input enable,
	input[63:0] valA,
	input[63:0] valB,
	input[$bit(opcode_t)-1:0] opcode,
	input[$bit(modrm_t)-1:0] modrm,
	output[63:0] result,
	output finish
);
	logic[63:0] result_comb;
	always_ff @(posedge clk) begin
		if (enable)
			result <= result_comb;
	end

	always_comb begin
		if (enable) begin
			result_comb = 0;
		end
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
