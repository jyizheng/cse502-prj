`include "instruction.svh"
`include "gpr.svh"

`define ALU_DEBUG 1

module ALU (
	input clk,
	input enable,
	input opcode_t opcode,
	input[63:0] oprd1,
	input[63:0] oprd2,
	input[63:0] oprd3,
	input[63:0] next_rip,
	output[127:0] result,
	output[63:0] rflags,
	output exe_mem,
	input mem_blocked,

	/* For branch */
	output branch,
	output[63:0] branch_rip
);
	logic[127:0] tmp_result;
	logic[63:0] tmp_rflags;

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

		if (enable == 1 && !mem_blocked) begin
			result <= tmp_result;
			rflags <= tmp_rflags;
			exe_mem <= 1;
		end
		else begin
			exe_mem <= 0;
		end
	end

	function logic condition_true(logic[7:0] cond);
		case (cond)
			8'h00: return rflags[`RF_OF];
			8'h01: return !rflags[`RF_OF];
			8'h02: return rflags[`RF_CF];
			8'h03: return !rflags[`RF_CF];
			8'h04: return rflags[`RF_ZF];
			8'h05: return !rflags[`RF_ZF];
			8'h06: return (rflags[`RF_ZF] | rflags[`RF_CF]);
			8'h07: return !(rflags[`RF_ZF] | rflags[`RF_CF]);
			8'h08: return rflags[`RF_SF];
			8'h09: return !rflags[`RF_SF];
			8'h0A: return rflags[`RF_PF];
			8'h0B: return !rflags[`RF_PF];
			8'h0C: return (rflags[`RF_SF] != rflags[`RF_OF]);
			8'h0D: return (rflags[`RF_SF] == rflags[`RF_OF]);
			8'h0E: return (rflags[`RF_ZF] | (rflags[`RF_SF] != rflags[`RF_OF]));
			8'h0F: return !(rflags[`RF_ZF] | (rflags[`RF_SF] != rflags[`RF_OF]));
			default: $display("[ALU] ERR unknown condition [%x]", cond);
		endcase
	endfunction

	/* Branched, we don't deal with call/retq here */
	always @ (posedge clk) begin
		if (enable == 1) begin
			casez (opcode)
				/* 0x70 ~ 0x7F Jcc */
				10'b00_0111_????: begin
					branch <= 1;
					if (condition_true({4'b0,opcode.opcode[3:0]})) begin
					end
				end
				/* 0xEB JMP */
				10'b00_1110_1011: begin
					branch <= 1;
				end
				/* 0x180 ~ 0x18F Jcc long */
				10'b01_1000_????: begin
					branch <= 1;
					if (condition_true({4'b0,opcode.opcode[3:0]})) begin
					end
				end
				default: begin
					branch <= 0;
				end
			endcase
		end
	end


endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
