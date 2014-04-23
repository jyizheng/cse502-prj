`include "instruction.svh"

module ALU (
	input clk,
	input opcode_t opcode,
	input[63:0] operand1,
	input[63,0] operand2,
	output[63,0] result,
	output[63,0] flags
);
	logic[127:0] tmp_result;

	always_comb begin
		case (opcode)
			default:
				$display("[ALU] Unsupported operation %x", opcode);
		endcase
	end

	always @ (posedge clk) begin
		result <= tmp_result[63:0];
		/* TODO: deal with flags */
	end


endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
