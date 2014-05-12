
/* We will first fulfil the dcache, then the icache */

typedef struct packed {
	logic wr;
	logic[3:0] t;
	logic[7:0] priv;
} _tag_t;

`define TAG_PRIV_N 8'b00000000
`define TAG_PRIV_D 8'b00000010
`define TAG_PRIV_I 8'b00000100

module Arbiter(Sysbus bus,

	/* For instruction cache */
	input irequest,
	output ireqack,
	input[63:0] iaddr,
	output[64*8-1:0] idata,
	output idone,

	/* For data cache */
	input drequest,
	output dreqack,
	input dwrenable,
	input[63:0] daddr,
	output[64*8-1:0] drdata,
	input[64*8-1:0] dwdata,
	output ddone
);
	enum { bus_idle,
		bus_d_begin, bus_d_waiting, bus_d_active,
		bus_d_w_begin, bus_d_w_waiting, bus_d_w_active,
		bus_i_begin, bus_i_waiting, bus_i_active } bus_state;

	_tag_t reqtag;
	logic[64*8-1:0] bus_buf;
	logic[8:0] buf_idx; 

	/* XXX: will this work for writing? */
	assign bus.respack = bus.respcyc; // always able to accept response

	always_ff @ (posedge bus.clk) begin
		if (dreqack)
			dreqack <= 0;

		if (ireqack)
			ireqack <= 0;
	end

	always_ff @ (posedge bus.clk) begin
		if (bus.reset) begin
			bus_state <= bus_idle;
			idone <= 0;
			ddone <= 0;
		end else if (bus_state == bus_idle) begin
			bus.reqcyc <= 0;
			bus.req <= 0;
			bus.reqtag <= 0;
			ireqack <= 0;
			idone <= 0;
			idata <= 0;
			dreqack <= 0;
			ddone <= 0;
			drdata <= 0;
			buf_idx <= 0;

			/* start a new transfer */
			if (drequest == 1) begin
				if (dwrenable) begin
					bus_state <= bus_d_w_begin;
					reqtag.wr <= bus.WRITE;
				end else begin
					bus_state <= bus_d_begin;
					reqtag.wr <= bus.READ;
				end

				dreqack <= 1;
				reqtag.t <= bus.MEMORY;
				reqtag.priv <= `TAG_PRIV_D;
			end else if (irequest == 1) begin
				ireqack <= 1;
				bus_state <= bus_i_begin;
				reqtag.wr <= bus.READ;
				reqtag.t <= bus.MEMORY;
				reqtag.priv <= `TAG_PRIV_I;
			end

		end else if (bus_state == bus_d_w_active) begin
			if (buf_idx > 0) begin
				bus.reqcyc <= 1;
				bus.req <= dwdata[(8-buf_idx)*64+:64];
				buf_idx <= buf_idx-1;
			end else begin
				bus.reqcyc <= 0;
				bus.req <= 0;
				bus_state <= bus_idle;
				ddone <= 1;
			end
		end else begin
			if (bus_state == bus_d_begin || bus_state == bus_d_w_begin) begin
				bus.reqcyc <= 1;
				bus.req <= daddr;
				bus.reqtag <= reqtag;
			end else if (bus_state == bus_i_begin) begin
				bus.reqcyc <= 1;
				bus.req <= iaddr;
				bus.reqtag <= reqtag;
			end
			/* FIXME: do we need to reset reqcyc to 0 after beginning? */

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
					end else begin
						bus.req <= dwdata[buf_idx+:64];
					end

					buf_idx <= buf_idx + 64;
				end
			end else begin
				if (bus_state == bus_i_active) begin
					bus_state <= bus_idle;
					idone <= 1;
					idata <= bus_buf;
				end else if (bus_state == bus_d_active) begin
					drdata <= bus_buf;
					bus_state <= bus_idle;
					ddone <= 1;
				end else if (bus.reqack) begin
					assert(bus_state == bus_i_begin || bus_state == bus_d_begin || bus_state == bus_d_w_begin) else $fatal;
					if (bus_state == bus_i_begin) begin
						bus.reqcyc <= 0;
						bus_state <= bus_i_waiting;
					end else if (bus_state == bus_d_w_begin) begin
						/* XXX: for write, we need to keep reqcyc as 1 */
						bus.reqcyc <= 1;
						bus.req <= dwdata[0+:64];
						buf_idx <= 7;
						bus_state <= bus_d_w_active;
					end else begin
						bus.reqcyc <= 0;
						bus_state <= bus_d_waiting;
					end
				end
			end
		end
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
