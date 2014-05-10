`include "instruction.svh"

`define ALU_DEBUG 1

module ALU (
	input clk,
	input enable,
	output exe_df,
	input opcode_t opcode,
	input[63:0] oprd1,
	input[63:0] oprd2,
	input[63:0] oprd3,
	output[127:0] result,
	output[63:0] flags,
	output exe_mem,
	input mem_exe
);
	logic[127:0] tmp_result;

	always_comb begin
		if (enable) begin
			casez (opcode)
				/* 0x00 ~ 0x05 */
				10'b0000000???: begin
`ifdef ALU_DEBUG
					$display("[ALU] DBG ADD %x + %x = %x", oprd1, oprd2, oprd1+oprd2);
`endif
					tmp_result = oprd1 + oprd2;
				end

				/* 0x08 ~ 0x0F */
				10'b0000001???: begin
`ifdef ALU_DEBUG
					$display("[ALU] DBG OR %x | %x = %x", oprd1, oprd2, oprd1 | oprd2);
`endif
					tmp_result = oprd1 | oprd2;
				end

				/* 0x88 ~ 0x8B */
				10'b00100010??: begin
`ifdef ALU_DEBUG
					$display("[ALU] DBG MOV %x = %x", oprd1, oprd2);
`endif
					tmp_result = oprd2;
				end

				/* 0xB8 ~ 0xBF */
				10'b0010111???: begin
`ifdef ALU_DEBUG
					$display("[ALU] DBG MOV %x = %x", oprd1, oprd2);
`endif
					tmp_result = oprd2;
				end

				/* Extensions */
				/* 0x83 001 */
				10'b1100000001: begin
`ifdef ALU_DEBUG
					$display("[ALU] DBG OR %x | %x = %x", oprd1, oprd2, oprd1 | oprd2);
`endif
					tmp_result = oprd1 | oprd2;
				end

				default:
					$display("[ALU] Unsupported operation %x", opcode);
			endcase
		end
	end

	always @ (posedge clk) begin
		/* TODO: deal with flags */

		if (enable == 1) begin
			result <= tmp_result;
			exe_mem <= 1;
		end
		else begin
			exe_mem <= 0;
		end
	end


endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
