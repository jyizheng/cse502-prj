`include "instruction.svh"

module ALU (
	input clk,
	input enable,
	input opcode_t opcode,
	input[63:0] oprd1,
	input[63:0] oprd2,
	input[63:0] oprd3,
	output[127:0] result,
	output[63:0] flags,
	output exe_mem
);
	logic[127:0] tmp_result;

	always_comb begin
		if (enable) begin
			case (opcode)
				default:
					$display("[ALU] Unsupported operation %x", opcode);
			endcase
		end
	end

	always @ (posedge clk) begin
		result <= tmp_result[63:0];
		/* TODO: deal with flags */

		if (enable == 1) begin
			exe_mem <= 1;
		end
		else begin
			exe_mem <= 0;
		end
	end


endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
