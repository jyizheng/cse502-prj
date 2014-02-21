/* Defines */
`define DECODER_OUTPUT 1

/* Typedefs */
typedef struct packed {
	logic[3:0][7:0] grp;
} gene_pref_t;

typedef struct packed {
	logic W;
	logic R;
	logic X;
	logic B;
} rex_t;

typedef struct packed {
	logic[1:0] mod;
	logic[2:0] reg_op;
	logic[2:0] rm;
} _modrm_t;

typedef struct packed {
	logic exist;
	_modrm_t v;
} modrm_t;

typedef struct packed {
	logic [1:0] scale;
	logic[2:0] index;
	logic[2:0] base;
} _sib_t;

typedef struct packed {
	logic exist;
	_sib_t v;
} sib_t;

typedef struct packed {
	logic[5:0] main;
	logic D;
	logic L;
} _opcode_t;

/* escape must be the MSB */
typedef struct packed {
	logic[1:0] escape;
	_opcode_t opcode;
	/* 2'b00: no escape;
	 * 2'b01: 0F escape;
	 * 2'b10: 0F 38 escape
	 * 2'b11: 0F 3A escape */
} opcode_t;

typedef struct packed {
	logic[31:0] value;
	logic[2:0] size;
} disp_t;

typedef struct packed {
	logic[63:0] value;
	logic[3:0] size;
} imme_t;

`define OPRD_T_NONE 5'h00
`define OPRD_T_E 5'h01
`define OPRD_T_G 5'h02
`define OPRD_T_I 5'h03
`define OPRD_T_J 5'h04
`define OPRD_T_F 5'h05
`define OPRD_T_M 5'h06
`define OPRD_T_X 5'h07
`define OPRD_T_Y 5'h08
`define OPRD_T_DX 5'h1D
`define OPRD_T_rAX 5'h1E /* AX, EAX, RAX */
`define OPRD_T_OP 5'h1F /* encoded in opcode[2:0] */

`define OPRD_SZ_0 3'h0
`define OPRD_SZ_B 3'h1	/* BYTE */
`define OPRD_SZ_W 3'h2	/* WORD */
`define OPRD_SZ_D 3'h3	/* DWORD */
`define OPRD_SZ_Q 3'h4	/* QWORD */
`define OPRD_SZ_Z 3'h5
`define OPRD_SZ_V 3'h6
`define OPRD_SZ_AV 3'h7	/* Ev for address */

typedef struct packed {
	/*
	 * 3'h1: b
	 * 3'h2: w
	 * 3'h5: z
	 * 3'h6: v
	 */
	logic[2:0] size;
	logic[4:0] t;
} oprd_desc_t;

module Core (
	input[63:0] entry
,	/* verilator lint_off UNDRIVEN */ /* verilator lint_off UNUSED */ Sysbus bus /* verilator lint_on UNUSED */ /* verilator lint_on UNDRIVEN */
);
	enum { fetch_idle, fetch_waiting, fetch_active } fetch_state;
	enum { ec_none, ec_invalid_op, ec_rex } error_code;
	logic[63:0] fetch_rip;
	logic[0:2*64*8-1] decode_buffer; // NOTE: buffer bits are left-to-right in increasing order
	logic[5:0] fetch_skip;
	logic[6:0] fetch_offset, decode_offset;

	function logic mtrr_is_mmio(logic[63:0] physaddr);
		mtrr_is_mmio = ((physaddr > 640*1024 && physaddr < 1024*1024));
	endfunction

	logic send_fetch_req;
	always_comb begin
		if (fetch_state != fetch_idle) begin
			send_fetch_req = 0; // hack: in theory, we could try to send another request at this point
		end else if (bus.reqack) begin
			send_fetch_req = 0; // hack: still idle, but already got ack (in theory, we could try to send another request as early as this)
		end else begin
			send_fetch_req = (fetch_offset - decode_offset < 7'd32);
		end
	end

	assign bus.respack = bus.respcyc; // always able to accept response

	always @ (posedge bus.clk)
		if (bus.reset) begin

			fetch_state <= fetch_idle;
			fetch_rip <= entry & ~63;
			fetch_skip <= entry[5:0];
			fetch_offset <= 0;

		end else begin // !bus.reset

			bus.reqcyc <= send_fetch_req;
			bus.req <= fetch_rip & ~63;
			bus.reqtag <= { bus.READ, bus.MEMORY, 8'b0 };

			if (bus.respcyc) begin
				assert(!send_fetch_req) else $fatal;
				fetch_state <= fetch_active;
				fetch_rip <= fetch_rip + 8;
				if (fetch_skip > 0) begin
					fetch_skip <= fetch_skip - 8;
				end else begin
					//$display("Fetch: [%d] %08x %08x", fetch_offset, bus.resp[63:32], bus.resp[31:0]);
					decode_buffer[fetch_offset*8 +: 64] <= bus.resp;
					//$display("fill at %d: %x [%x]", fetch_offset, bus.resp, decode_buffer);
					fetch_offset <= fetch_offset + 8;
				end
			end else begin
				if (fetch_state == fetch_active) begin
					fetch_state <= fetch_idle;
				end else if (bus.reqack) begin
					assert(fetch_state == fetch_idle) else $fatal;
					fetch_state <= fetch_waiting;
				end
			end

		end

	wire[0:(128+15)*8-1] decode_bytes_repeated = { decode_buffer, decode_buffer[0:15*8-1] }; // NOTE: buffer bits are left-to-right in increasing order
	wire[0:15*8-1] decode_bytes = decode_bytes_repeated[decode_offset*8 +: 15*8]; // NOTE: buffer bits are left-to-right in increasing order
	wire can_decode = (fetch_offset - decode_offset >= 7'd15);

	function logic opcode_inside(logic[7:0] value, low, high);
		opcode_inside = (value >= low && value <= high);
	endfunction

	function logic[2:0] opcode_imme_size(opcode_t opcode);
		/*
		 * 3'h0: no imme
		 * 3'h1: b
		 * 3'h2: w
		 * 3'h5: z
		 * 3'h6: v
		 */
		logic[0:255][2:0] onebyte_has_imme = {
			/*       f    e    d    c    b    a    9    8    7    6    5    4    3    2    1    0        */
			/*       -------------------------------        */
			/* f0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* f0 */
			/* e0 */ 3'h0,3'h0,3'h0,3'h0,3'h1,3'h0,3'h5,3'h5,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1, /* e0 */
			/* d0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* d0 */
			/* c0 */ 3'h0,3'h0,3'h1,3'h0,3'h0,3'h2,3'h0,3'h0,3'h5,3'h1,3'h0,3'h0,3'h0,3'h2,3'h1,3'h1, /* c0 */
			/* b0 */ 3'h6,3'h6,3'h6,3'h6,3'h6,3'h6,3'h6,3'h6,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1, /* b0 */
			/* a0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h5,3'h1,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* a0 */
			/* 90 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 90 */
			/* 80 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h1,3'h0,3'h5,3'h1, /* 80 */
			/* 70 */ 3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1, /* 70 */
			/* 60 */ 3'h0,3'h0,3'h0,3'h0,3'h1,3'h1,3'h5,3'h5,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 60 */
			/* 50 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 50 */
			/* 40 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 40 */
			/* 30 */ 3'h0,3'h0,3'h5,3'h1,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h5,3'h1,3'h0,3'h0,3'h0,3'h0, /* 30 */
			/* 20 */ 3'h0,3'h0,3'h5,3'h1,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h5,3'h1,3'h0,3'h0,3'h0,3'h0, /* 20 */
			/* 10 */ 3'h0,3'h0,3'h5,3'h1,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h5,3'h1,3'h0,3'h0,3'h0,3'h0, /* 10 */
			/* 00 */ 3'h0,3'h0,3'h5,3'h1,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h5,3'h1,3'h0,3'h0,3'h0,3'h0  /* 00 */
			/*       -------------------------------        */
			/*       f    e    d    c    b    a    9    8    7    6    5    4    3    2    1    0        */
		};
		logic[0:255][2:0] twobyte_has_imme = {
			/*       f    e    d    c    b    a    9    8    7    6    5    4    3    2    1    0        */
			/*       -------------------------------        */
			/* f0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* f0 */
			/* e0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* e0 */
			/* d0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* d0 */
			/* c0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* c0 */
			/* b0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h1,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* b0 */
			/* a0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* a0 */
			/* 90 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 90 */
			/* 80 */ 3'h5,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5, /* 80 */
			/* 70 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 70 */
			/* 60 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 60 */
			/* 50 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 50 */
			/* 40 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 40 */
			/* 30 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 30 */
			/* 20 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 20 */
			/* 10 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 10 */
			/* 00 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0  /* 00 */
			/*       -------------------------------        */
			/*       f    e    d    c    b    a    9    8    7    6    5    4    3    2    1    0        */
		};
		casez (opcode.escape)
			2'b00:
				opcode_imme_size = onebyte_has_imme[opcode.opcode];
			2'b01:
				opcode_imme_size = twobyte_has_imme[opcode.opcode];
			2'b1?:
				opcode_imme_size = 0;
		endcase
	endfunction

	function logic opcode_has_modrm(opcode_t opcode);
		logic[0:255] onebyte_has_modrm = {
			/*       0    1    2    3    4    5    6    7    8    9    a    b    c    d    e    f        */
			/*       -------------------------------        */
			/* 00 */ 1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0, /* 00 */
			/* 10 */ 1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0, /* 10 */
			/* 20 */ 1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0, /* 20 */
			/* 30 */ 1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0, /* 30 */
			/* 40 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* 40 */
			/* 50 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* 50 */
			/* 60 */ 1'b0,1'b0,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,1'b0,1'b1,1'b0,1'b0,1'b0,1'b0, /* 60 */
			/* 70 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* 70 */
			/* 80 */ 1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1, /* 80 */
			/* 90 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* 90 */
			/* a0 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* a0 */
			/* b0 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* b0 */
			/* c0 */ 1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* c0 */
			/* d0 */ 1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1, /* d0 */
			/* e0 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* e0 */
			/* f0 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1  /* f0 */
			/*       -------------------------------        */
			/*       0    1    2    3    4    5    6    7    8    9    a    b    c    d    e    f        */
		};
		logic[0:255] twobyte_has_modrm = {
			/*       0    1    2    3    4    5    6    7    8    9    a    b    c    d    e    f        */
			/*       -------------------------------        */
			/* 00 */ 1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,1'b0,1'b1, /* 0f */
			/* 10 */ 1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1, /* 1f */
			/* 20 */ 1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b0,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1, /* 2f */
			/* 30 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,1'b0,1'b1,1'b0,1'b0,1'b0,1'b0,1'b0, /* 3f */
			/* 40 */ 1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1, /* 4f */
			/* 50 */ 1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1, /* 5f */
			/* 60 */ 1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1, /* 6f */
			/* 70 */ 1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b0,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1, /* 7f */
			/* 80 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* 8f */
			/* 90 */ 1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1, /* 9f */
			/* a0 */ 1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b1, /* af */
			/* b0 */ 1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b0,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1, /* bf */
			/* c0 */ 1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* cf */
			/* d0 */ 1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1, /* df */
			/* e0 */ 1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1, /* ef */
			/* f0 */ 1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b0  /* ff */
			/*       -------------------------------        */
			/*       0    1    2    3    4    5    6    7    8    9    a    b    c    d    e    f        */
		};
		casez (opcode.escape)
			2'b00:
				opcode_has_modrm = onebyte_has_modrm[opcode.opcode];
			2'b01:
				opcode_has_modrm = twobyte_has_modrm[opcode.opcode];
			2'b1?:
				opcode_has_modrm = 0;
		endcase
	endfunction

	function oprd_desc_t get_operand2_desc(opcode_t opcode, modrm_t modrm);
		oprd_desc_t[255:0] operand2_desc = {
			/* 100 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* F8 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* F0 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_B, `OPRD_T_J }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_J }, { `OPRD_SZ_Z, `OPRD_T_J },
			/* E8 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_B, `OPRD_T_J }, { `OPRD_SZ_B, `OPRD_T_J },
			{ `OPRD_SZ_B, `OPRD_T_J }, { `OPRD_SZ_B, `OPRD_T_J },
			/* E0 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* D8 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* D0 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* C8 */
			{ `OPRD_SZ_Z, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_B, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			/* C0 */
			{ `OPRD_SZ_V, `OPRD_T_I }, { `OPRD_SZ_V, `OPRD_T_I },
			{ `OPRD_SZ_V, `OPRD_T_I }, { `OPRD_SZ_V, `OPRD_T_I },
			{ `OPRD_SZ_V, `OPRD_T_I }, { `OPRD_SZ_V, `OPRD_T_I },
			{ `OPRD_SZ_V, `OPRD_T_I }, { `OPRD_SZ_V, `OPRD_T_I },
			/* B8 */
			{ `OPRD_SZ_B, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			{ `OPRD_SZ_B, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			{ `OPRD_SZ_B, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			{ `OPRD_SZ_B, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			/* B0 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			/* A8 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* A0 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* 98 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* 90 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_M }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			/* 88 */
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			{ `OPRD_SZ_B, `OPRD_T_I }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			/* 80 */
			{ `OPRD_SZ_B, `OPRD_T_J }, { `OPRD_SZ_B, `OPRD_T_J },
			{ `OPRD_SZ_B, `OPRD_T_J }, { `OPRD_SZ_B, `OPRD_T_J },
			{ `OPRD_SZ_B, `OPRD_T_J }, { `OPRD_SZ_B, `OPRD_T_J },
			{ `OPRD_SZ_B, `OPRD_T_J }, { `OPRD_SZ_B, `OPRD_T_J },
			/* 78 */
			{ `OPRD_SZ_B, `OPRD_T_J }, { `OPRD_SZ_B, `OPRD_T_J },
			{ `OPRD_SZ_B, `OPRD_T_J }, { `OPRD_SZ_B, `OPRD_T_J },
			{ `OPRD_SZ_B, `OPRD_T_J }, { `OPRD_SZ_B, `OPRD_T_J },
			{ `OPRD_SZ_B, `OPRD_T_J }, { `OPRD_SZ_B, `OPRD_T_J },
			/* 70 */
			{ `OPRD_SZ_Z, `OPRD_T_X }, { `OPRD_SZ_B, `OPRD_T_X },
			{ `OPRD_SZ_W, `OPRD_T_DX }, { `OPRD_SZ_W, `OPRD_T_DX },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_B, `OPRD_T_I },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_Z, `OPRD_T_I },
			/* 68 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* 60 */
			{ `OPRD_SZ_V, `OPRD_T_OP }, { `OPRD_SZ_V, `OPRD_T_OP },
			{ `OPRD_SZ_V, `OPRD_T_OP }, { `OPRD_SZ_V, `OPRD_T_OP },
			{ `OPRD_SZ_V, `OPRD_T_OP }, { `OPRD_SZ_V, `OPRD_T_OP },
			{ `OPRD_SZ_V, `OPRD_T_OP }, { `OPRD_SZ_V, `OPRD_T_OP },
			/* 58 */
			{ `OPRD_SZ_V, `OPRD_T_OP }, { `OPRD_SZ_V, `OPRD_T_OP },
			{ `OPRD_SZ_V, `OPRD_T_OP }, { `OPRD_SZ_V, `OPRD_T_OP },
			{ `OPRD_SZ_V, `OPRD_T_OP }, { `OPRD_SZ_V, `OPRD_T_OP },
			{ `OPRD_SZ_V, `OPRD_T_OP }, { `OPRD_SZ_V, `OPRD_T_OP },
			/* 50 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* 48 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* 40 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			/* 38 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			/* 30 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			/* 28 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			/* 20 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			/* 18 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			/* 10 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			/* 08 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_I }, { `OPRD_SZ_B, `OPRD_T_I },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G }
			/* 00 */
		};

		get_operand2_desc = 0;
		if (opcode.escape == 0)
			case (opcode.opcode)
				8'hFF: begin
					if (modrm.exist == 0)
						$write("ERROR no modrm.op (%x : %x)", opcode, modrm.v.reg_op);
					else if (modrm.v.reg_op == 3'b010)
						get_operand2_desc = { `OPRD_SZ_AV, `OPRD_T_E };
					else
						$write("ERROR unsupported modrm.op (%x : %x)", opcode, modrm.v.reg_op);
				end
				default: get_operand2_desc = operand2_desc[opcode];
			endcase
		else if (opcode.escape == 1) begin
			casez (opcode.opcode)
				8'h05: get_operand2_desc = { `OPRD_SZ_0, `OPRD_T_NONE };
				default: begin
					$write("ERROR, unsupported 2-byte opcode");
					get_operand2_desc = 0;
				end
			endcase
		end
		else
			$write("ERROR, unsupported escape");
	endfunction


	function oprd_desc_t get_operand1_desc(opcode_t opcode, modrm_t modrm);
		oprd_desc_t[255:0] operand1_desc = {
			/* 100 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* F8 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* F0 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* E8 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* E0 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* D8 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* D0 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* C8 */
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			/* C0 */
			{ `OPRD_SZ_V, `OPRD_T_OP }, { `OPRD_SZ_V, `OPRD_T_OP },
			{ `OPRD_SZ_V, `OPRD_T_OP }, { `OPRD_SZ_V, `OPRD_T_OP },
			{ `OPRD_SZ_V, `OPRD_T_OP }, { `OPRD_SZ_V, `OPRD_T_OP },
			{ `OPRD_SZ_V, `OPRD_T_OP }, { `OPRD_SZ_V, `OPRD_T_OP },
			/* B8 */
			{ `OPRD_SZ_B, `OPRD_T_OP }, { `OPRD_SZ_B, `OPRD_T_OP },
			{ `OPRD_SZ_B, `OPRD_T_OP }, { `OPRD_SZ_B, `OPRD_T_OP },
			{ `OPRD_SZ_B, `OPRD_T_OP }, { `OPRD_SZ_B, `OPRD_T_OP },
			{ `OPRD_SZ_B, `OPRD_T_OP }, { `OPRD_SZ_B, `OPRD_T_OP },
			/* B0 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_rAX }, { `OPRD_SZ_B, `OPRD_T_rAX },
			/* A8 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* A0 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* 98 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* 90 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			/* 88 */
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_V, `OPRD_T_E },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			/* 80 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* 78 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* 70 */
			{ `OPRD_SZ_W, `OPRD_T_DX }, { `OPRD_SZ_W, `OPRD_T_DX },
			{ `OPRD_SZ_Z, `OPRD_T_Y }, { `OPRD_SZ_B, `OPRD_T_Y },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* 68 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* 60 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* 58 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* 50 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* 48 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			/* 40 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_rAX }, { `OPRD_SZ_B, `OPRD_T_rAX },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			/* 38 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_rAX }, { `OPRD_SZ_B, `OPRD_T_rAX },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			/* 30 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_rAX }, { `OPRD_SZ_B, `OPRD_T_rAX },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			/* 28 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_rAX }, { `OPRD_SZ_B, `OPRD_T_rAX },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			/* 20 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_rAX }, { `OPRD_SZ_B, `OPRD_T_rAX },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			/* 18 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_rAX }, { `OPRD_SZ_B, `OPRD_T_rAX },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			/* 10 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_rAX }, { `OPRD_SZ_B, `OPRD_T_rAX },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E },
			/* 08 */
			{ `OPRD_SZ_0, `OPRD_T_NONE }, { `OPRD_SZ_0, `OPRD_T_NONE },
			{ `OPRD_SZ_Z, `OPRD_T_rAX }, { `OPRD_SZ_B, `OPRD_T_rAX },
			{ `OPRD_SZ_V, `OPRD_T_G }, { `OPRD_SZ_B, `OPRD_T_G },
			{ `OPRD_SZ_V, `OPRD_T_E }, { `OPRD_SZ_B, `OPRD_T_E }
			/* 00 */
		};

		get_operand1_desc = 0;
		if (opcode.escape == 0)
			case (opcode.opcode)
				8'hFF: begin
					if (modrm.exist == 0)
						$write("ERROR no modrm.op (%x : %x)", opcode, modrm.v.reg_op);
					else if (modrm.v.reg_op == 3'b010)
						get_operand1_desc = { `OPRD_SZ_0, `OPRD_T_NONE };
					else
						$write("ERROR unsupported modrm.op (%x : %x)", opcode, modrm.v.reg_op);
				end
				default: get_operand1_desc = operand1_desc[opcode];
			endcase
		else if (opcode.escape == 1) begin
			casez (opcode.opcode)
				8'h05: get_operand1_desc = { `OPRD_SZ_0, `OPRD_T_NONE };
				default: begin
					$write("ERROR, unsupported 2-byte opcode %x", opcode.opcode);
					get_operand1_desc = 0;
				end
			endcase
		end
		else
			$write("ERROR, unsupported escape");
	endfunction

`ifdef DECODER_OUTPUT
	/* FIXME: remove this */
	/* verilator lint_off UNUSED */

	/* set rex to non-zero to force 64-bit regs */
	function logic output_GPR(logic[3:0] reg_no, rex_t rex, int size);
		casez (reg_no)
			4'h0: $write("%%%s", (size == 64) ? "rax" :
				((size == 32) ? "eax" : ((size == 16) ? "ax" : "al")));
			4'h1: $write("%%%s", (size == 64) ? "rcx" :
				((size == 32) ? "ecx" : ((size == 16) ? "cx" : "cl")));
			4'h2: $write("%%%s", (size == 64) ? "rdx" :
				((size == 32) ? "edx" : ((size == 16) ? "dx" : "dl")));
			4'h3: $write("%%%s", (size == 64) ? "rbx" :
				((size == 32) ? "ebx" : ((size == 16) ? "bx" : "bl")));
			4'b01??: begin
				if (rex == 0) begin
					case (reg_no[1:0])
						2'h0: $write("%%%s", (size == 64) ? "ERR" :
						    ((size == 32) ? "esp" : ((size == 16) ? "sp" : "ah")));
						2'h1: $write("%%%s", (size == 64) ? "ERR" :
						    ((size == 32) ? "ebp" : ((size == 16) ? "bp" : "ch")));
						2'h2: $write("%%%s", (size == 64) ? "ERR" :
						    ((size == 32) ? "esi" : ((size == 16) ? "si" : "dh")));
						2'h3: $write("%%%s", (size == 64) ? "ERR" :
							((size == 32) ? "edi" : ((size == 16) ? "di" : "bh")));
					endcase
				end
				else begin
					case (reg_no[1:0])
						2'h0: $write("%%%s", (size == 64) ? "rsp" :
						    ((size == 32) ? "esp" : ((size == 16) ? "sp" : "spl")));
						2'h1: $write("%%%s", (size == 64) ? "rbp" :
						    ((size == 32) ? "ebp" : ((size == 16) ? "bp" : "bpl")));
						2'h2: $write("%%%s", (size == 64) ? "rsi" :
						    ((size == 32) ? "esi" : ((size == 16) ? "si" : "sil")));
						2'h3: $write("%%%s", (size == 64) ? "rdi" :
							((size == 32) ? "edi" : ((size == 16) ? "di" : "dil")));
					endcase
				end
			end
			4'h8: $write("%%%s", (size == 64) ? "r8" :
				((size == 32) ? "r8d" : ((size == 16) ? "r8w" : "r8l")));
			4'h9: $write("%%%s", (size == 64) ? "r9" :
				((size == 32) ? "r9d" : ((size == 16) ? "r9w" : "r9l")));
			4'hA: $write("%%%s", (size == 64) ? "r10" :
				((size == 32) ? "r10d" : ((size == 16) ? "r10w" : "r10l")));
			4'hB: $write("%%%s", (size == 64) ? "r11" :
				((size == 32) ? "r11d" : ((size == 16) ? "r11w" : "r11l")));
			4'hC: $write("%%%s", (size == 64) ? "r12" :
				((size == 32) ? "r12d" : ((size == 16) ? "r12w" : "r12l")));
			4'hD: $write("%%%s", (size == 64) ? "r13" :
				((size == 32) ? "r13d" : ((size == 16) ? "r13w" : "r13l")));
			4'hE: $write("%%%s", (size == 64) ? "r14" :
				((size == 32) ? "r14d" : ((size == 16) ? "r14w" : "r14l")));
			4'hF: $write("%%%s", (size == 64) ? "r15" :
				((size == 32) ? "r15d" : ((size == 16) ? "r15w" : "r15l")));
			default: $write("ERROR: unknown reg no (%x)", reg_no);
		endcase
		output_GPR = 0;
	endfunction

	/* For immediate, we need to extend to effective operand size */
	function logic output_operand_I(imme_t imme, int efct_size);
		int imme_size = 0;
		imme_size[3:0] = imme.size;
		imme_size = imme_size * 8;

		if (efct_size == 64) begin
			if (imme_size == efct_size)
				$write("$0x%x", imme.value);
			else if (imme_size < efct_size) begin
				logic[63:0] imme_value;
				imme_value = imme.value[63:0];
				for (int i = imme_size; i < efct_size; i += 1)
					imme_value[i] = imme.value[imme_size-1];
				$write("$0x%x", imme_value);
			end
			else if (imme_size > efct_size)
				$write("Immediate size larger than effective?? (%x > %x)", imme_size, efct_size);
		end
		else if (efct_size == 32) begin
			if (imme_size == efct_size)
				$write("$0x%x", imme.value[31:0]);
			else if (imme_size < efct_size) begin
				logic[31:0] imme_value;
				imme_value = imme.value[31:0];
				for (int i = imme_size; i < efct_size; i += 1)
					imme_value[i] = imme.value[imme_size-1];
				$write("$0x%x", imme_value);
			end
			else if (imme_size > efct_size)
				$write("Immediate size larger than effective?? (%x > %x)", imme_size, efct_size);
		end
		else if (efct_size == 16) begin
			if (imme_size == efct_size)
				$write("$0x%x", imme.value[15:0]);
			else if (imme_size < efct_size) begin
				logic[15:0] imme_value;
				imme_value = imme.value[15:0];
				for (int i = imme_size; i < efct_size; i += 1)
					imme_value[i] = imme.value[imme_size-1];
				$write("$0x%x", imme_value);
			end
			else if (imme_size > efct_size)
				$write("Immediate size larger than effective?? (%x > %x)", imme_size, efct_size);
		end
		else
			$write("ERROR: unsupported effective size");

		output_operand_I = 0;
	endfunction

	/* For immediate, we need to extend to effective operand size */
	function logic output_operand_J(imme_t imme, int efct_size);
//		int imme_size = 0;
//		imme_size[3:0] = imme.size;
//		imme_size = imme_size * 8;
//
//		if (efct_size == 64) begin
//			if (imme_size == efct_size)
//				$write("$0x%x", imme.value);
//			else if (imme_size < efct_size) begin
//				logic[63:0] imme_value;
//				imme_value = imme.value[63:0];
//				for (int i = imme_size; i < efct_size; i += 1)
//					imme_value[i] = imme.value[imme_size-1];
//				$write("$0x%x", imme_value);
//			end
//			else if (imme_size > efct_size)
//				$write("Immediate size larger than effective?? (%x > %x)", imme_size, efct_size);
//		end
//		else if (efct_size == 32) begin
//			if (imme_size == efct_size)
//				$write("$0x%x", imme.value[31:0]);
//			else if (imme_size < efct_size) begin
//				logic[31:0] imme_value;
//				imme_value = imme.value[31:0];
//				for (int i = imme_size; i < efct_size; i += 1)
//					imme_value[i] = imme.value[imme_size-1];
//				$write("$0x%x", imme_value);
//			end
//			else if (imme_size > efct_size)
//				$write("Immediate size larger than effective?? (%x > %x)", imme_size, efct_size);
//		end
//		else
//			$write("ERROR: unsupported effective size");

		logic[7:0] rel_addr_size = imme.size * 8;

		/* XXX: Assume all relative-address are signed numbers */
		if (imme.value[rel_addr_size-1] == 1) begin
			case (rel_addr_size)
				8: begin
					logic[7:0] new_rel_addr = ~(imme.value[7:0] - 1);
					$write("-0x%x", new_rel_addr);
				end
				16: begin
					logic[15:0] new_rel_addr = ~(imme.value[15:0] - 1);
					$write("-0x%x", new_rel_addr);
				end
				32: begin
					logic[31:0] new_rel_addr = ~(imme.value[31:0] - 1);
					$write("-0x%x", new_rel_addr);
				end
				64: begin
					logic[63:0] new_rel_addr = ~(imme.value[63:0] - 1);
					$write("-0x%x", new_rel_addr);
				end
				default:
					$write("ERR: Invalid Relative address size %x", rel_addr_size);
			endcase
		end
		else 
			$write("0x%x", imme.value);

		output_operand_J = 0;
	endfunction

	/* For displacement, we don't extend to effective operand size */
	function logic output_disp(disp_t disp, int efct_size);
		logic[7:0] disp_size = disp.size * 8;

		/* XXX: Assume all displacement are signed numbers */
		if (disp.value[disp_size-1] == 1) begin
			case (disp_size)
				8: begin
					logic[7:0] new_disp = ~(disp.value[7:0] - 1);
					$write("-0x%x", new_disp);
				end
				32: begin
					logic[31:0] new_disp = ~(disp.value[31:0] - 1);
					$write("-0x%x", new_disp);
				end
				default:
					$write("ERR: Invalid displacement size %x", disp_size);
			endcase
		end
		else begin
			$write("0x%x", disp.value);
		end

		output_disp = 0;
	endfunction

	function logic output_operand_E(oprd_desc_t oprd, gene_pref_t prefix, rex_t rex, modrm_t modrm,
		sib_t sib, disp_t disp, int efct_size);
		int actual_size = 0;
		int addr_size = (prefix.grp[3] != 8'h67) ? 64 : 32;
		rex_t rex_override = rex;

		case (oprd.size)
			`OPRD_SZ_B: actual_size = 8;
			`OPRD_SZ_W: actual_size = 16;
			`OPRD_SZ_Z: actual_size = (rex.W == 1) ? 32 :
				((efct_size == 32) ? 32 : 16);
			`OPRD_SZ_V: actual_size = (rex.W == 1) ? 64 :
				((efct_size == 32) ? 32 : 16);
			`OPRD_SZ_AV: if (addr_size == 64 && rex_override == 0) begin
				rex_override.W = 1;
				actual_size = addr_size;
			end
			default: $write("Invalid oprd2 size %x", oprd.size);
		endcase

		if (modrm.v.mod == 2'b11) begin
			/* Reg */
			output_GPR({rex.B, modrm.v.rm}, rex_override, actual_size);
		end
		else if (modrm.v.rm == 3'b100) begin
			/* SIB */
			/* TODO */
			$write("SIB note implemented");
		end
		else begin
			case (modrm.v.mod)
				2'b00: begin
					if (modrm.v.rm == 3'b101) begin
						output_disp(disp, efct_size);
					end
					else begin
						$write("(");
						/* here we need to pretend rex is not 0 to force 64-bit mode */
						output_GPR({rex.B, modrm.v.rm}, (addr_size == 64) ? 1 : 0, addr_size);
						$write(")");
					end
				end
				2'b01: begin
					output_disp(disp, efct_size);
					$write("(");
					output_GPR({rex.B, modrm.v.rm}, (addr_size == 64) ? 1 : 0, addr_size);
					$write(")");
				end
				2'b10: begin
					output_disp(disp, efct_size);
					$write("(");
					output_GPR({rex.B, modrm.v.rm}, (addr_size == 64) ? 1 : 0, addr_size);
					$write(")");
				end
				default: $write("Invalid ModR/M.mod (%x)", modrm.v.mod);
			endcase
		end
		output_operand_E = 0;
	endfunction

	function logic output_operand_op(oprd_desc_t oprd, gene_pref_t prefix, rex_t rex, modrm_t modrm,
		sib_t sib, disp_t disp, int efct_size);
		output_operand_op = 0;
	endfunction

	function logic output_operand_G(oprd_desc_t oprd, rex_t rex, modrm_t modrm, int efct_size);
		int reg_size = 0;
		case (oprd.size)
			`OPRD_SZ_B: reg_size = 8;
			`OPRD_SZ_W: reg_size = 16;
			`OPRD_SZ_Z: reg_size = (rex.W == 1) ? 32 :
				((efct_size == 32) ? 32 : 16);
			`OPRD_SZ_V: reg_size = (rex.W == 1) ? 64 :
				((efct_size == 32) ? 32 : 16);
			default: $write("Invalid oprd1 size %x", oprd.size);
		endcase
		output_GPR({rex.R, modrm.v.reg_op}, rex, reg_size);
		output_operand_G = 0;
	endfunction

	function logic output_operand_OP(oprd_desc_t oprd, gene_pref_t prefix, rex_t rex, opcode_t opcode, modrm_t modrm);
		int reg_size = 0;
		rex_t rex_override = rex;

		/* push/pop instruction */
		if (opcode.escape == 0 && opcode.opcode[7:4] == 4'h5) begin
			if (rex.W == 1 || prefix.grp[2] != 8'h66)
				rex_override.W = 1;
		end

		case (oprd.size)
			`OPRD_SZ_B: reg_size = 8;
			`OPRD_SZ_W: reg_size = 16;
			`OPRD_SZ_Z: reg_size = (rex_override.W == 1) ? 32 :
				((prefix.grp[2] != 8'h66) ? 32 : 16);
			`OPRD_SZ_V: reg_size = (rex_override.W == 1) ? 64 :
				((prefix.grp[2] != 8'h66) ? 32 : 16);
			default: $write("Invalid oprd1 size %x", oprd.size);
		endcase
		output_GPR({rex.B, opcode.opcode[2:0]}, rex_override, reg_size);
		output_operand_OP = 0;
	endfunction

	function logic decode_modrm_opcode_output(opcode_t opcode, modrm_t modrm);
		assert(modrm.exist == 1)
		else $error("Expecting ModRM for opcode %x", opcode);
		casez (opcode)
			/* Group 1: 80 - 83 */
			10'b00_1000_00??:
				case (modrm.v.reg_op)
					3'b000: $write(" add");
					3'b001: $write(" or");
					3'b010: $write(" adc");
					3'b011: $write(" sbb");
					3'b100: $write(" and");
					3'b101: $write(" sub");
					3'b110: $write(" xor");
					3'b111: $write(" cmp");
				endcase
			/* Group 2: C0 - C1, D0 - D3 */
			10'h0C1:
				case (modrm.v.reg_op)
					3'b000: $write(" rol");
					3'b001: $write(" ror");
					3'b010: $write(" rcl");
					3'b011: $write(" rcr");
					3'b100: $write(" shl/sal");
					3'b101: $write(" shr");
					3'b110: $write(" Invalid ModRM opcode extension for %x", opcode);
					3'b111: $write(" sar");
				endcase
			/* Group 5: FF */
			10'h0FF:
				case (modrm.v.reg_op)
					3'b000: $write(" inc");
					3'b001: $write(" dec");
					3'b010: $write(" NEAR call");
					3'b011: $write(" FAR call");
					3'b100: $write(" NEAR jmp");
					3'b101: $write(" FAR jmp");
					3'b110: $write(" push");
					3'b111: $write(" Invalid ModRM opcode extension for %x", opcode);
				endcase
			default: $write(" Invalid ModRM opcode extension for %x", opcode);
		endcase
		decode_modrm_opcode_output = 0;
	endfunction

	function logic output_condition(logic[3:0] code);
		case (code)
			4'h0: $write("o");
			4'h1: $write("no");
			4'h2: $write("b");
			4'h3: $write("ae");
			4'h4: $write("z");
			4'h5: $write("nz");
			4'h6: $write("be");
			4'h7: $write("a");
			4'h8: $write("s");
			4'h9: $write("ns");
			4'hA: $write("p");
			4'hB: $write("np");
			4'hC: $write("l");
			4'hD: $write("ge");
			4'hE: $write("le");
			4'hF: $write("g");
		endcase
		output_condition = 0;
	endfunction

	function logic decode_output(gene_pref_t prefix, rex_t rex,
		opcode_t opcode, modrm_t modrm, sib_t sib, disp_t disp, imme_t imme);

		int effect_oprd_size = 0;
		int effect_addr_size = 0;
		oprd_desc_t oprd1;
		oprd_desc_t oprd2;
		oprd_desc_t oprd3;

		effect_oprd_size = (rex.W == 1) ? 64 :
			((prefix.grp[2] == 0) ? 32 : 16);
		effect_addr_size = (prefix.grp[3] == 0) ? 64 : 32;

		/* Opcode */
		casez (opcode)
			/* one-byte opcodes */
			/* 00 - 07 */
			10'b00_0000_0???: $write(" add");

			/* 20 - 27 */
			10'b00_0010_0???: $write(" and");

			/* 28 - 2D */
			10'b00_0010_1???: $write(" sub");

			/* 30 - 37 */
			10'b00_0011_0???: $write(" xor");

			/* 38 - 3D */
			10'b00_0011_1???: $write(" cmp");

			/* 50 - 57 */
			10'b00_0101_0???: $write(" push");

			/* 58 - 5f */
			10'b00_0101_1???: $write(" pop");

			10'h06C: $write(" insb/ins");
			10'h06F: $write(" outs/outsw/outsd");

			/* 70 - 7F */
			10'h07?: begin
				$write(" j");
				output_condition(opcode.opcode[3:0]);
			end

			/* 84 - 85 */
			10'b00_1000_010?: $write(" test");

			10'h089: $write(" mov");
			10'h08B: $write(" mov");
			10'h08D: $write(" lea");
			10'h090: $write(" nop");
			10'h0B?: $write(" movabs");
			10'h0C3: $write(" NEAR ret");
			10'h0E8: $write(" NEAR call");
			10'h0E9: $write(" NEAR jmp");
			10'h0EB: $write(" SHORT jmp");

			/* two-byte opcodes */
			10'h105: $write(" syscall");
			10'h11f: $write(" nop");
			10'h18?: begin
				$write(" j");
				output_condition(opcode.opcode[3:0]);
			end
			10'h1af: $write(" imul");

			/* --- Special group w/ ModR/M opcode --- */
			/* Group 1 */
			10'h081: decode_modrm_opcode_output(opcode, modrm);
			10'h083: decode_modrm_opcode_output(opcode, modrm);
			/* Group 2 */
			10'h0C1: decode_modrm_opcode_output(opcode, modrm);
			/* Group 5 */
			10'h0FF: decode_modrm_opcode_output(opcode, modrm);
			/* Group 11, XXX assume we only use mov of them */
			10'h0C6: $write(" mov");
			10'h0C7: $write(" mov");
			default: $write("Unknown opcode[%x]", opcode);
		endcase

		/* Operand, display 2nd operand first */
		oprd2 = get_operand2_desc(opcode, modrm);
		if (oprd2 != 0) begin
			$write("\t");
			case (oprd2.t)
				`OPRD_T_E: output_operand_E(oprd2, prefix, rex, modrm, sib, disp, effect_oprd_size);
				`OPRD_T_G: output_operand_G(oprd2, rex, modrm, effect_oprd_size);
				`OPRD_T_I: output_operand_I(imme, effect_oprd_size);
				`OPRD_T_J: output_operand_J(imme, effect_addr_size);
				`OPRD_T_X: $write("%%ds(%%rsi)");
				`OPRD_T_DX: $write("(%%dx)");
				`OPRD_T_OP: output_operand_OP(oprd2, prefix, rex, opcode, modrm);
				default: $write("Unknown operand type (%x)", oprd2.t);
			endcase
		end

		oprd1 = get_operand1_desc(opcode, modrm);

		if (oprd1 != 0) begin
			$write(", ");
			case (oprd1.t)
				`OPRD_T_E: output_operand_E(oprd1, prefix, rex, modrm, sib, disp, effect_oprd_size);
				`OPRD_T_G: output_operand_G(oprd1, rex, modrm, effect_oprd_size);
				`OPRD_T_Y: $write("%%es(%%rdi)");
				`OPRD_T_DX: $write("(%%dx)");
				`OPRD_T_OP: output_operand_OP(oprd1, prefix, rex, opcode, modrm);
				default: $write("Unknown operand type (%x)", oprd1.t);
			endcase
		end
		$write("\n");
		decode_output = 0;
	endfunction
	/* verilator lint_on UNUSED */
`endif

	/* FIXME: remove this */
	/* verilator lint_off UNUSED */
	function logic decode_one(gene_pref_t prefix, rex_t rex,
		opcode_t opcode, modrm_t modrm, sib_t sib, disp_t disp, imme_t imme);
		//$display("%x %x %x %x %x %x %x", prefix, rex, opcode, modrm, sib, disp, imme);
		decode_one = 0;

	endfunction
	/* verilator lint_on UNUSED */

	logic[3:0] bytes_decoded_this_cycle;
	always_comb begin
		if (can_decode) begin : decode_block
			gene_pref_t prefix = 32'h0000_0000;
			rex_t rex = 4'b0000;
			opcode_t opcode = 0;
			modrm_t modrm = 9'h00;
			sib_t sib = 9'h00;
			disp_t disp = 0;
			imme_t imme = 0;

			logic[7:0] next_byte;

			// cse502 : Decoder here
			// remove the following line. It is only here to allow successful compilation in the absence of your code.
			//$display("decode_bytes [%x]", decode_bytes);
			bytes_decoded_this_cycle = 0;
			next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];
			error_code = ec_none;

			/* Prefix */
			while (1) begin
				logic stage_finished = 0;
				casez (next_byte)
					/* Group 1 */
					8'hF0: prefix.grp[0] = next_byte;
					8'hF2: prefix.grp[0] = next_byte;
					8'hF3: prefix.grp[0] = next_byte;
					/* Group 2 */
					8'h26: prefix.grp[1] = next_byte;
					8'h2E: prefix.grp[1] = next_byte;
					8'h36: prefix.grp[1] = next_byte;
					8'h3E: prefix.grp[1] = next_byte;
					8'h64: prefix.grp[1] = next_byte;
					8'h65: prefix.grp[1] = next_byte;
					/* Group 3 */
					8'h66: prefix.grp[2] = next_byte;
					/* Group 4 */
					8'h67: prefix.grp[3] = next_byte;
					/* REX */
					8'h4?: rex = next_byte[3:0];
					default: stage_finished = 1;
				endcase

				if (stage_finished == 1)
					break;
				bytes_decoded_this_cycle += 1;
				next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];
			end

			/* Opcode */
			if (next_byte == 8'h0F) begin
				bytes_decoded_this_cycle += 1;
				next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];

				/* 0F 38 escape */
				if (next_byte == 8'h38) begin
					opcode.escape = 2'h10;
					bytes_decoded_this_cycle += 1;
					next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];
				end
				/* 0F 3A escape */
				else if (next_byte == 8'h3A) begin
					opcode.escape = 2'h11;
					bytes_decoded_this_cycle += 1;
					next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];
				end
				/* 0F escape */
				else
					opcode.escape = 2'h01;
			end
			/* TODO: unsupported opcode */
			opcode.opcode = next_byte;
			bytes_decoded_this_cycle += 1;
			next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];
			modrm.exist = opcode_has_modrm(opcode);

			if (error_code != ec_none)
				$finish;

			/* ModR/M */
			if (modrm.exist == 1) begin
				modrm.v = next_byte;
				bytes_decoded_this_cycle += 1;
				next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];
			end

			/* SIB */
			if (modrm.v.mod != 2'b11 && modrm.v.rm == 3'b100) begin
				sib.exist = 1'b1;
				sib[7:0] = next_byte;
				bytes_decoded_this_cycle += 1;
				next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];
			end

			/* Displacement */
			if (modrm.v.mod == 2'b01)
				disp.size = 1;
			else if (modrm.v.mod == 2'b10)
				disp.size = 4;
			else if (modrm.v.mod == 2'b00 && modrm.v.rm == 3'b101)
				disp.size = 4;

			for (logic[2:0] i = 0; i < disp.size; i += 1) begin
				disp.value[{2'b00,i}*8 +: 8] = next_byte;
				bytes_decoded_this_cycle += 1;
				next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];
			end

			/* Immediate */
			imme.size[2:0] = opcode_imme_size(opcode);
			if (imme.size[2:0] == 5) begin
				imme.size = (rex.W == 1) ? 4 :
					((prefix.grp[2] == 0) ? 4 : 2);
			end
			else if (imme.size[2:0] == 6) begin
				imme.size = (rex.W == 1) ? 8 :
					((prefix.grp[2] == 0) ? 4 : 2);
			end

			for (logic[3:0] i = 0; i < imme.size; i += 1) begin
				imme.value[{2'b00,i}*8 +: 8] = next_byte;
				bytes_decoded_this_cycle += 1;
				next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];
			end

			/* output */
			$write("%d:", bytes_decoded_this_cycle);
			for (int i = 0; i[3:0] < bytes_decoded_this_cycle; i += 1) begin
				$write(" %x", decode_bytes[i * 8 +: 8]);
			end
			$write("\n\t");
			decode_output(prefix, rex, opcode, modrm, sib, disp, imme);
			decode_one(prefix, rex, opcode, modrm, sib, disp, imme);

			/* decoding */

			/* finish decode cycle */
			//$display("Prefix: %d[%b]", prefix, prefix);
			//$display("REX: %x[%b]", rex, rex);
			//$display("Opcode: %x[%b]", opcode, opcode);
			//$display("ModRM: %x[%b]", modrm, modrm);
			//$display("SIB: %x[%b]", sib, sib);
			//$display("DISP: %x[%b]", disp, disp);
			//$display("IMME: %x[%b]", imme, imme);

			// cse502 : following is an example of how to finish the simulation
			if (decode_bytes == 0 && fetch_state == fetch_idle) $finish;
		end else begin
			bytes_decoded_this_cycle = 0;
		end
	end

	always @ (posedge bus.clk)
		if (bus.reset) begin

			decode_offset <= 0;
			decode_buffer <= 0;

		end else begin // !bus.reset

			decode_offset <= decode_offset + { 3'b0, bytes_decoded_this_cycle };

		end

endmodule
