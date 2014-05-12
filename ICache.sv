/* instruction cache */
module ICache(input clk,
	input enable,
	input[63:0] addr,
	output[511:0] rdata,
	output done,

	output irequest,
	input ireqack,
	output[63:0] iaddr,
	input[511:0] idata,
	input idone
);

	enum { state_idle, state_wait } state;

	always_ff @ (posedge clk) begin
		if (state == state_idle) begin
			done <= 0;
			rdata <= 0;
			if (enable == 1) begin
				assert((addr & 63) == 0) else $fatal;

				state <= state_wait;
				irequest <= 1;
				iaddr <= addr;
			end
		end else begin // !state_idle
			if (ireqack)
				irequest <= 0;

			if (idone) begin
				state <= state_idle;
				rdata <= idata;
				done <= 1;
			end
		end
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
