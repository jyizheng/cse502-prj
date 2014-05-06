
/* We will first fulfil the dcache, then the icache */

typedef struct packed {
	logic wr,
	logic[3:0] t,
	logic[7:0] priv
} _tag_t;

`define TAG_PRIV_N 8'b00000000
`define TAG_PRIV_D 8'b00000010
`define TAG_PRIV_I 8'b00000100

module Arbiter(Sysbus bus,

	/* For instruction cache */
	input irequest,
	input[63:0] iaddr,
	output[64*8-1:0] idata,
	output idone,

	/* For data cache */
	input drequest,
	input dwrenable,
	input[63:0] daddr,
	output[64*8-1:0] drdata,
	input[64*8-1:0] dwdata,
	output ddone
);
	enum { bus_idle,
		bus_d_begin, bus_d_waiting, bus_d_active,
		bus_i_begin, bus_i_waiting, bus_i_active } bus_state;

	_tag_t reqtag;
	logic[64*8-1:0] bus_buf;
	logic[8:0] buf_idx; 

	/* XXX: will this work for writing? */
	assign bus.respack = bus.respcyc; // always able to accept response

	always_ff @ (posedge bus.clk) begin
		if (bus.reset) begin
			bus_state <= bus_idle;
			idone <= 0;
			ddone <= 0;
		end else if (bus_state == bus_idle) begin
			bus.reqcyc <= 0;
			bus.req <= 0;
			bus.reqtag <= 0;
			bus.respack <= 0;
			bus.idone <= 0;
			idone <= 0;
			ddone <= 0;
			buf_idx <= 0;
		end else
			if (bus_state == bus_d_begin) begin
				bus.reqcyc <= 1;
				bus.req <= daddr;
				bus.reqtag <= reqtag;
			end else if (bus_state == bus_i_begin) begin
				bus.reqcyc <= 1;
				bus.req <= iaddr;
				bus.reqtag <= reqtag;
			end

			/* received respcyc from sysbus */
			if (bus.respcyc) begin
				assert(bus_state != bus_idle) else $fatal;

				if (bus_state == bus_i_waiting || bus_state == bus_i_active) begin
					assert(buf_idx < 511) else $fatal;
					bus_state <= bus_i_active;
					bus_buf[buf_idx+:64] <= bus.resp;
					buf_idx <= buf_idx + 64;

				end else if (bus_state == bus_d_waiting || bus_state == bus_d_active) begin
					assert(buf_idx < 511) else $fatal;
					bus_state <= bus_d_active;

					if (bus.resptag[12] == bus.READ) begin
						bus_buf[buf_idx+:64] <= bus.resp;
					end else
						bus.req <= dwdata[buf_idx+:64];
					end

					buf_idx <= buf_idx + 64;
				end
			end else begin
				if (bus_state == bus_i_active) begin
					bus_state <= bus_idle;
					idone <= 1;
				end else if (bus_state == bus_d_active) begin
					bus_state <= bus_idle;
					ddone <= 1;
				end else if (bus.reqack) begin
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
			if (drequest == 1) begin
				bus_state = bus_d_begin;
				if (dwrenable)
					reqtag.wr = bus.WRITE;
				else
					reqtag.wr = bus.READ;

				reqtag.t = bus.MEMORY;
				reqtag.priv = `TAG_PRIV_D;
			end else if (irequest == 1) begin
				bus_state = bus_i_begin;
				reqtag.wr = bus.READ;
				reqtag.t = bus.MEMORY;
				reqtag.priv = `TAG_PRIV_I;
			end
		end
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
