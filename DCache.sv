/* data cache */
module DCache(input clk,
	input enable,
	input wen,
	input[63:0] addr,
	output[63:0] rdata,
	input[63:0] wdata,
	output done);

	always_ff @ (posedge clk) begin
		done <= 0;
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
