
/* We will first fulfil the dcache, then the icache */

typedef struct packed {
	logic wr;
	logic[3:0] t;
	logic[7:0] priv;
} _tag_t;

`define TAG_PRIV_N 8'b00000000
`define TAG_PRIV_D 8'b00000010
`define TAG_PRIV_I 8'b00000100

module Arbiter( /* verilator lint_off UNDRIVEN */ /* verilator lint_off UNUSED */ Sysbus bus,  /* verilator lint_on UNUSED */ /* verilator lint_on UNDRIVEN */

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

	logic[64*8-1:0] rev_idata;
	assign idata[0+:8] = rev_idata[56+:8]; assign idata[8+:8] = rev_idata[48+:8]; assign idata[16+:8] = rev_idata[40+:8]; assign idata[24+:8] = rev_idata[32+:8]; assign idata[32+:8] = rev_idata[24+:8]; assign idata[40+:8] = rev_idata[16+:8]; assign idata[48+:8] = rev_idata[8+:8]; assign idata[56+:8] = rev_idata[0+:8];
	assign idata[64+:8] = rev_idata[120+:8]; assign idata[72+:8] = rev_idata[112+:8]; assign idata[80+:8] = rev_idata[104+:8]; assign idata[88+:8] = rev_idata[96+:8]; assign idata[96+:8] = rev_idata[88+:8]; assign idata[104+:8] = rev_idata[80+:8]; assign idata[112+:8] = rev_idata[72+:8]; assign idata[120+:8] = rev_idata[64+:8];
	assign idata[128+:8] = rev_idata[184+:8]; assign idata[136+:8] = rev_idata[176+:8]; assign idata[144+:8] = rev_idata[168+:8]; assign idata[152+:8] = rev_idata[160+:8]; assign idata[160+:8] = rev_idata[152+:8]; assign idata[168+:8] = rev_idata[144+:8]; assign idata[176+:8] = rev_idata[136+:8]; assign idata[184+:8] = rev_idata[128+:8];
	assign idata[192+:8] = rev_idata[248+:8]; assign idata[200+:8] = rev_idata[240+:8]; assign idata[208+:8] = rev_idata[232+:8]; assign idata[216+:8] = rev_idata[224+:8]; assign idata[224+:8] = rev_idata[216+:8]; assign idata[232+:8] = rev_idata[208+:8]; assign idata[240+:8] = rev_idata[200+:8]; assign idata[248+:8] = rev_idata[192+:8];
	assign idata[256+:8] = rev_idata[312+:8]; assign idata[264+:8] = rev_idata[304+:8]; assign idata[272+:8] = rev_idata[296+:8]; assign idata[280+:8] = rev_idata[288+:8]; assign idata[288+:8] = rev_idata[280+:8]; assign idata[296+:8] = rev_idata[272+:8]; assign idata[304+:8] = rev_idata[264+:8]; assign idata[312+:8] = rev_idata[256+:8];
	assign idata[320+:8] = rev_idata[376+:8]; assign idata[328+:8] = rev_idata[368+:8]; assign idata[336+:8] = rev_idata[360+:8]; assign idata[344+:8] = rev_idata[352+:8]; assign idata[352+:8] = rev_idata[344+:8]; assign idata[360+:8] = rev_idata[336+:8]; assign idata[368+:8] = rev_idata[328+:8]; assign idata[376+:8] = rev_idata[320+:8];
	assign idata[384+:8] = rev_idata[440+:8]; assign idata[392+:8] = rev_idata[432+:8]; assign idata[400+:8] = rev_idata[424+:8]; assign idata[408+:8] = rev_idata[416+:8]; assign idata[416+:8] = rev_idata[408+:8]; assign idata[424+:8] = rev_idata[400+:8]; assign idata[432+:8] = rev_idata[392+:8]; assign idata[440+:8] = rev_idata[384+:8];
	assign idata[448+:8] = rev_idata[504+:8]; assign idata[456+:8] = rev_idata[496+:8]; assign idata[464+:8] = rev_idata[488+:8]; assign idata[472+:8] = rev_idata[480+:8]; assign idata[480+:8] = rev_idata[472+:8]; assign idata[488+:8] = rev_idata[464+:8]; assign idata[496+:8] = rev_idata[456+:8]; assign idata[504+:8] = rev_idata[448+:8];

	logic[64*8-1:0] rev_drdata;
	assign drdata[0+:8] = rev_drdata[56+:8]; assign drdata[8+:8] = rev_drdata[48+:8]; assign drdata[16+:8] = rev_drdata[40+:8]; assign drdata[24+:8] = rev_drdata[32+:8]; assign drdata[32+:8] = rev_drdata[24+:8]; assign drdata[40+:8] = rev_drdata[16+:8]; assign drdata[48+:8] = rev_drdata[8+:8]; assign drdata[56+:8] = rev_drdata[0+:8];
	assign drdata[64+:8] = rev_drdata[120+:8]; assign drdata[72+:8] = rev_drdata[112+:8]; assign drdata[80+:8] = rev_drdata[104+:8]; assign drdata[88+:8] = rev_drdata[96+:8]; assign drdata[96+:8] = rev_drdata[88+:8]; assign drdata[104+:8] = rev_drdata[80+:8]; assign drdata[112+:8] = rev_drdata[72+:8]; assign drdata[120+:8] = rev_drdata[64+:8];
	assign drdata[128+:8] = rev_drdata[184+:8]; assign drdata[136+:8] = rev_drdata[176+:8]; assign drdata[144+:8] = rev_drdata[168+:8]; assign drdata[152+:8] = rev_drdata[160+:8]; assign drdata[160+:8] = rev_drdata[152+:8]; assign drdata[168+:8] = rev_drdata[144+:8]; assign drdata[176+:8] = rev_drdata[136+:8]; assign drdata[184+:8] = rev_drdata[128+:8];
	assign drdata[192+:8] = rev_drdata[248+:8]; assign drdata[200+:8] = rev_drdata[240+:8]; assign drdata[208+:8] = rev_drdata[232+:8]; assign drdata[216+:8] = rev_drdata[224+:8]; assign drdata[224+:8] = rev_drdata[216+:8]; assign drdata[232+:8] = rev_drdata[208+:8]; assign drdata[240+:8] = rev_drdata[200+:8]; assign drdata[248+:8] = rev_drdata[192+:8];
	assign drdata[256+:8] = rev_drdata[312+:8]; assign drdata[264+:8] = rev_drdata[304+:8]; assign drdata[272+:8] = rev_drdata[296+:8]; assign drdata[280+:8] = rev_drdata[288+:8]; assign drdata[288+:8] = rev_drdata[280+:8]; assign drdata[296+:8] = rev_drdata[272+:8]; assign drdata[304+:8] = rev_drdata[264+:8]; assign drdata[312+:8] = rev_drdata[256+:8];
	assign drdata[320+:8] = rev_drdata[376+:8]; assign drdata[328+:8] = rev_drdata[368+:8]; assign drdata[336+:8] = rev_drdata[360+:8]; assign drdata[344+:8] = rev_drdata[352+:8]; assign drdata[352+:8] = rev_drdata[344+:8]; assign drdata[360+:8] = rev_drdata[336+:8]; assign drdata[368+:8] = rev_drdata[328+:8]; assign drdata[376+:8] = rev_drdata[320+:8];
	assign drdata[384+:8] = rev_drdata[440+:8]; assign drdata[392+:8] = rev_drdata[432+:8]; assign drdata[400+:8] = rev_drdata[424+:8]; assign drdata[408+:8] = rev_drdata[416+:8]; assign drdata[416+:8] = rev_drdata[408+:8]; assign drdata[424+:8] = rev_drdata[400+:8]; assign drdata[432+:8] = rev_drdata[392+:8]; assign drdata[440+:8] = rev_drdata[384+:8];
	assign drdata[448+:8] = rev_drdata[504+:8]; assign drdata[456+:8] = rev_drdata[496+:8]; assign drdata[464+:8] = rev_drdata[488+:8]; assign drdata[472+:8] = rev_drdata[480+:8]; assign drdata[480+:8] = rev_drdata[472+:8]; assign drdata[488+:8] = rev_drdata[464+:8]; assign drdata[496+:8] = rev_drdata[456+:8]; assign drdata[504+:8] = rev_drdata[448+:8];

	logic[64*8-1:0] rev_dwdata;
	assign rev_dwdata[0+:8] = dwdata[56+:8]; assign rev_dwdata[8+:8] = dwdata[48+:8]; assign rev_dwdata[16+:8] = dwdata[40+:8]; assign rev_dwdata[24+:8] = dwdata[32+:8]; assign rev_dwdata[32+:8] = dwdata[24+:8]; assign rev_dwdata[40+:8] = dwdata[16+:8]; assign rev_dwdata[48+:8] = dwdata[8+:8]; assign rev_dwdata[56+:8] = dwdata[0+:8];
	assign rev_dwdata[64+:8] = dwdata[120+:8]; assign rev_dwdata[72+:8] = dwdata[112+:8]; assign rev_dwdata[80+:8] = dwdata[104+:8]; assign rev_dwdata[88+:8] = dwdata[96+:8]; assign rev_dwdata[96+:8] = dwdata[88+:8]; assign rev_dwdata[104+:8] = dwdata[80+:8]; assign rev_dwdata[112+:8] = dwdata[72+:8]; assign rev_dwdata[120+:8] = dwdata[64+:8];
	assign rev_dwdata[128+:8] = dwdata[184+:8]; assign rev_dwdata[136+:8] = dwdata[176+:8]; assign rev_dwdata[144+:8] = dwdata[168+:8]; assign rev_dwdata[152+:8] = dwdata[160+:8]; assign rev_dwdata[160+:8] = dwdata[152+:8]; assign rev_dwdata[168+:8] = dwdata[144+:8]; assign rev_dwdata[176+:8] = dwdata[136+:8]; assign rev_dwdata[184+:8] = dwdata[128+:8];
	assign rev_dwdata[192+:8] = dwdata[248+:8]; assign rev_dwdata[200+:8] = dwdata[240+:8]; assign rev_dwdata[208+:8] = dwdata[232+:8]; assign rev_dwdata[216+:8] = dwdata[224+:8]; assign rev_dwdata[224+:8] = dwdata[216+:8]; assign rev_dwdata[232+:8] = dwdata[208+:8]; assign rev_dwdata[240+:8] = dwdata[200+:8]; assign rev_dwdata[248+:8] = dwdata[192+:8];
	assign rev_dwdata[256+:8] = dwdata[312+:8]; assign rev_dwdata[264+:8] = dwdata[304+:8]; assign rev_dwdata[272+:8] = dwdata[296+:8]; assign rev_dwdata[280+:8] = dwdata[288+:8]; assign rev_dwdata[288+:8] = dwdata[280+:8]; assign rev_dwdata[296+:8] = dwdata[272+:8]; assign rev_dwdata[304+:8] = dwdata[264+:8]; assign rev_dwdata[312+:8] = dwdata[256+:8];
	assign rev_dwdata[320+:8] = dwdata[376+:8]; assign rev_dwdata[328+:8] = dwdata[368+:8]; assign rev_dwdata[336+:8] = dwdata[360+:8]; assign rev_dwdata[344+:8] = dwdata[352+:8]; assign rev_dwdata[352+:8] = dwdata[344+:8]; assign rev_dwdata[360+:8] = dwdata[336+:8]; assign rev_dwdata[368+:8] = dwdata[328+:8]; assign rev_dwdata[376+:8] = dwdata[320+:8];
	assign rev_dwdata[384+:8] = dwdata[440+:8]; assign rev_dwdata[392+:8] = dwdata[432+:8]; assign rev_dwdata[400+:8] = dwdata[424+:8]; assign rev_dwdata[408+:8] = dwdata[416+:8]; assign rev_dwdata[416+:8] = dwdata[408+:8]; assign rev_dwdata[424+:8] = dwdata[400+:8]; assign rev_dwdata[432+:8] = dwdata[392+:8]; assign rev_dwdata[440+:8] = dwdata[384+:8];
	assign rev_dwdata[448+:8] = dwdata[504+:8]; assign rev_dwdata[456+:8] = dwdata[496+:8]; assign rev_dwdata[464+:8] = dwdata[488+:8]; assign rev_dwdata[472+:8] = dwdata[480+:8]; assign rev_dwdata[480+:8] = dwdata[472+:8]; assign rev_dwdata[488+:8] = dwdata[464+:8]; assign rev_dwdata[496+:8] = dwdata[456+:8]; assign rev_dwdata[504+:8] = dwdata[448+:8];

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
			rev_idata <= 0;
			dreqack <= 0;
			ddone <= 0;
			rev_drdata <= 0;
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
				bus.req <= rev_dwdata[(8-buf_idx)*64+:64];
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
						bus.req <= rev_dwdata[buf_idx+:64];
					end

					buf_idx <= buf_idx + 64;
				end
			end else begin
				if (bus_state == bus_i_active) begin
					bus_state <= bus_idle;
					idone <= 1;
					rev_idata <= bus_buf;
				end else if (bus_state == bus_d_active) begin
					rev_drdata <= bus_buf;
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
						bus.req <= rev_dwdata[0+:64];
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
