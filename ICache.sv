/* instruction cache */
module ICache(input clk,
	input enable,
	input[63:0] addr,
	output[511:0] rdata,
	output done,

	output irequest,
	output[63:0] iaddr,
	input[511:0] idata,
	input idone
);

	always_ff @ (posedge clk) begin
		if (enable == 0) begin
			done <= 0;
		end
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
