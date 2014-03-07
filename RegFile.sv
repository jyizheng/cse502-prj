
module RegFile (
	input clk,
	input[3:0] regOutIdx1,
	input[3:0] regOutIdx2,
	input[3:0] regInIdx,
	input[2:0] regInType,	/* GPR_T_XX */
	input	regWrEn,
	output[63:0] regOutVal1,
	output[63:0] regOutVal2
	input[63:0] regInVal,
);
	logic[63:0] regfile[16];

	// cse502 : Use the following as a guide to print the Register File contents.
	final begin
		$display("RAX = %x", regfile[0]);
		$display("RBX = %x", regfile[3]);
		$display("RCX = %x", regfile[1]);
		$display("RDX = %x", regfile[2]);
		$display("RSI = %x", regfile[6]);
		$display("RDI = %x", regfile[7]);
		$display("RBP = %x", regfile[5]);
		$display("RSP = %x", regfile[4]);
		$display("R8  = %x", regfile[8]);
		$display("R9  = %x", regfile[9]);
		$display("R10 = %x", regfile[10]);
		$display("R11 = %x", regfile[11]);
		$display("R12 = %x", regfile[12]);
		$display("R13 = %x", regfile[13]);
		$display("R14 = %x", regfile[14]);
		$display("R15 = %x", regfile[15]);
	end

	always_ff @(posedge clk) begin
		if (regWrEn == 1'b1) begin
			case (regInType)
				`GPR_T_64:
					regfile[regInIdx] <= regInVal;
				`GPR_T_32L:
					regfile[regInIdx][31:0] <= regInVal[31:0];
				`GPR_T_16L:
					regfile[regInIdx][15:0] <= regInVal[15:0];
				`GPR_T_8L:
					regfile[regInIdx][7:0] <= regInVal[7:0];
				`GPR_T_8H:
					if (regInIdx[3:2] == 2'b01)
						regfile[regInIdx][15:8] <= regInVal[7:0];
					else
						$write("ERR: Unindexable higher 8 bit reg (%d)", regInIdx);
				default:
					$write("ERR: unknown GPR_T (%x)", regInType);
			endcase
		end
	end

	always_comb begin

	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
