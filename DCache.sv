/* data cache */
module DCache(input clk,
	input enable,
	input wen,
	input[63:0] addr,
	output[63:0] rdata,
	input[63:0] wdata,
	output done,

	output drequest,
	output dwrenable,
	output[63:0] daddr,
	input[64*8-1:0] drdata,
	output[64*8-1:0] dwdata,
	input ddone
);
	logic[64*8-1:0] dc_buf;
	logic[7:0] buf_idx;

	enum { state_idle, state_r_wait, state_w_r_wait, state_w_wait } state;

	always_ff @ (posedge clk) begin
		if (state == state_idle) begin
			if (enable) begin
				assert(addr[5:0] == 0) else $fatal("[DCACHE] unaligned mem addr ");
				/* First we all need to read data */
				if (wen)
					state <= state_w_r_wait;
				else
					state <= state_r_wait;
				drequest <= 1;
				dwrenable <= 0;
				daddr <= { addr[63:6], 6'b000000 };
				dwdata <= 0;
			end else begin
				rdata <= 0;
				done <= 0;

				drequest <= 0;
				dwrenable <= 0;
				daddr <= 0;
				dwdata <= 0;
			end
		end else if (state == state_r_wait) begin
			drequest <= 0;
			dwrenable <= 0;
			if (ddone) begin
				state <= state_idle;
				rdata <= drdata;
				done <= 1;
			end
		end else if (state == state_w_r_wait) begin
			drequest <= 0;
			dwrenable <= 0;

			if (ddone) begin
				state <= state_w_wait;
				drequest <= 1;
				dwrenable <= 1;
				daddr <= { addr[63:6], 6'b000000 };
				dwdata <= dc_buf;
				done <= 0;
			end

		end else if (state == state_w_wait) begin
			drequest <= 0;
			dwrenable <= 0;

			if (ddone) begin
				state <= state_idle;
				daddr <= 0;
				dwdata <= 0;
				rdata <= 0;
				done <= 1;
			end
		end
	end

	always_comb begin
		if (wen && (state == state_r_wait) && ddone) begin
			logic[8:0] offset = { 3'b00, addr[5:0] };
			dc_buf = drdata;
			dc_buf[offset*8+:64] = wdata;
		end
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
