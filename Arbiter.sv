
/* We will first fulfil the dcache, then the icache */

module Arbiter(Sysbus bus,

	/* For instruction cache */
	input[bus.DATA_WIDTH-1:0] ireq,
	input[bus.TAG_WIDTH-1:0] ireqtag,
	output[bus.DATA_WIDTH-1:0] iresp,
	output[bus.TAG_WIDTH-1:0] iresptag,
	input ireqcyc,
	output irespcyc,
	output ireqack,
	input irespack,

	/* For data cache */
	input[bus.DATA_WIDTH-1:0] dreq,
	input[bus.TAG_WIDTH-1:0] dreqtag,
	output[bus.DATA_WIDTH-1:0] dresp,
	output[bus.TAG_WIDTH-1:0] dresptag,
	input dreqcyc,
	output drespcyc,
	output dreqack,
	input drespack
);

	enum { bus_idle,
		bus_d_begin, bus_d_waiting, bus_d_active,
		bus_i_begin, bus_i_waiting, bus_i_active } bus_state;

	//assign bus.respack = bus.respcyc; // always able to accept response

	always_ff @ (posedge bus.clk) begin
		if (bus.reset) begin
			bus_state <= bus_idle;
		end else if (bus_state == bus_idle) begin
			bus.reqcyc <= 0;
			bus.req <= 0;
			bus.reqtag <= 0;
			bus.respack <= 0;
		end else
			if (bus_state == bus_d_begin) begin
				bus.reqcyc <= dreqcyc;
				bus.req <= dreq;
				bus.reqtag <= dreqtag;
			end else if (bus_state == bus_i_begin) begin
				bus.reqcyc <= ireqcyc;
				bus.req <= ireq;
				bus.reqtag <= ireqtag;
			end

			/* received respcyc from sysbus */
			if (bus.respcyc) begin
				assert(bus_state != bus_idle) else $fatal;

				if (bus_state == bus_i_waiting || bus_state == bus_i_active) begin
			end else begin
				if (bus_state == bus_i_active || bus_state == bus_d_active)
					bus_state <= bus_idle;
				else if (bus.reqack) begin
					assert(bus_state == bus_i_begin || bus_state == bus_d_begin) else $fatal;
					if (bus_state == bus_i_begin)
						bus_state <= bus_i_waiting;
					else
						bus_state <= bus_d_waiting;
				end
			end
		end
	end

	always_comb begin
		/* We are ready for next transfer */
		if (bus_state == bus_idle) begin
			if (dreqcyc == 1) begin
				bus_state = bus_d_begin;
			end else if (ireqcyc == 1) begin
				bus_state = bus_i_begin;
			end
		end
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
