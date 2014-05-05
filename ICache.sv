/* instruction cache */
module ICache(input clk,
	input enable,
	input[63:0] addr,
	output[511:0] rdata,
	output done);

	always_ff @ (posedge clk) begin
		done <= 0;
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
