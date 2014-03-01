
module RegFile (
	input clk,
	input[63:0] regIn,
	output[63:0] regOutA,
	output[63:0] regOutB
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

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
