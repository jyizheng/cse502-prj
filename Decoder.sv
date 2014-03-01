`include "instruction.svh"
`include "gpr.svh"

`define DECODER_OUTPUT 1

`define GPR_RAX	4'd0

module Decoder (
	input clk,
	input can_decode,
	input[63:0] rip,
	input[0:15*8-1] decode_bytes,
	output[3:0] bytes_decoded
);

	rex_t rex = 4'b0000;
	imme_t imme = 0;
	enum { ec_none, ec_invalid_op, ec_rex } error_code;
	int effect_oprd_size = 0;
	int effect_addr_size = 0;
	logic[63:0] regfile[16];
	logic[63:0] result;
	logic[3:0] wb_reg;

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
			{ `OPRD_SZ_V, `OPRD_T_M }, { `OPRD_SZ_0, `OPRD_T_NONE },
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
				8'h8?: get_operand2_desc = { `OPRD_SZ_Z, `OPRD_T_J };
				8'haf: get_operand2_desc = { `OPRD_SZ_V, `OPRD_T_E };
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
				8'h8?: get_operand1_desc = { `OPRD_SZ_0, `OPRD_T_NONE };
				8'haf: get_operand1_desc = { `OPRD_SZ_V, `OPRD_T_G };
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
	function logic output_GPR(logic[3:0] reg_no, rex_t rex_override, int size);
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
				if (rex_override == 0) begin
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
	function logic output_operand_I(int efct_size);
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
				$write("Immediate size larger than effective?? (%d > %d)", imme_size, efct_size);
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
	function logic output_operand_J(int efct_size);
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

	function logic output_operand_E(oprd_desc_t oprd, gene_pref_t prefix, modrm_t modrm,
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
			$write("ERR SIB note implemented");
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

	function logic output_operand_G(oprd_desc_t oprd, modrm_t modrm, int efct_size);
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

	function logic output_operand_OP(oprd_desc_t oprd, gene_pref_t prefix, opcode_t opcode, modrm_t modrm);
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

	function logic output_operand_rAX();
		if (effect_oprd_size == 64)
			$write("%%rax");
		else if (effect_oprd_size == 32)
			$write("%%eax");
		else if (effect_oprd_size == 16)
			$write("%% ax");
		else if (effect_oprd_size == 8)
			$write("%% al");
		else
			$write("Unknown size of rAX (%d)", effect_oprd_size);
		output_operand_rAX = 0;
	endfunction

	function logic decode_modrm_opcode_output(opcode_t opcode, modrm_t modrm);
		assert(modrm.exist == 1)
		else $error("Expecting ModRM for opcode %x", opcode);
		casez (opcode)
			/* Group 1: 80 - 83 */
			10'b00_1000_00?0:	/* 80, 82 */
				case (modrm.v.reg_op)
					3'b000: $write(" add");
					3'b001: begin
						$write(" or");
					end
					3'b010: $write(" adc");
					3'b011: $write(" sbb");
					3'b100: $write(" and");
					3'b101: $write(" sub");
					3'b110: $write(" xor");
					3'b111: $write(" cmp");
				endcase
			10'b00_1000_0001:	/* 81 */
				case (modrm.v.reg_op)
					3'b000: $write(" add");
					3'b001: begin
						$write(" [C]or");
						if (effect_oprd_size == 64)
							result = regfile[{rex.B,modrm.v.rm}] | {32'b0,imme.value[31:0]};
						else
							$write("ERR unsupported op size");
						wb_reg = { rex.B, modrm.v.rm };
					end
					3'b010: $write(" adc");
					3'b011: $write(" sbb");
					3'b100: $write(" and");
					3'b101: $write(" sub");
					3'b110: $write(" xor");
					3'b111: $write(" cmp");
				endcase
			10'b00_1000_0011:	/* 83 */
				case (modrm.v.reg_op)
					3'b000: $write(" add");
					3'b001: begin
						$write(" [C]or");
						if (effect_oprd_size == 64)
							result = regfile[{rex.B,modrm.v.rm}] | {56'b0,imme.value[7:0]};
						else
							$write("ERR unsupported op size");
						wb_reg = { rex.B, modrm.v.rm };
					end
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

	always_ff @(posedge clk) begin
		regfile[wb_reg] <= result;
	end

	function logic decode_output(gene_pref_t prefix,
		opcode_t opcode, modrm_t modrm, sib_t sib, disp_t disp);

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

			/* XXX: W2 */
			10'h09: begin
				$write(" [C]or");
				if (effect_oprd_size == 64)
					result = regfile[{rex.R,modrm.v.reg_op}] | regfile[{rex.B,modrm.v.rm}];
				else
					$write("ERR unsupported size (%d)", effect_oprd_size);
				wb_reg = {rex.B,modrm.v.rm};
			end

			/* XXX: W2 */
			10'h0D: begin
				$write(" [C]or");
				if (effect_oprd_size == 64)
					result = regfile[0] | imme.value;
				else if (effect_oprd_size == 32)
					result[31:0] = regfile[0][31:0] | imme.value[31:0];
				else if (effect_oprd_size == 16)
					result[15:0] = regfile[0][15:0] | imme.value[15:0];
				else
					$write("ERR unsupported size (%d)", effect_oprd_size);
				wb_reg = 0;
			end

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
			/* XXX: W2 */
			10'h0B?: begin
				$write(" [C]movabs");
				if (effect_oprd_size == 64)
					result = imme.value;
				else
					$write(" ERR unsupported size");
				wb_reg = { rex.B, opcode.opcode[2:0] };
			end
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
				`OPRD_T_E: output_operand_E(oprd2, prefix, modrm, sib, disp, effect_oprd_size);
				`OPRD_T_G: output_operand_G(oprd2, modrm, effect_oprd_size);
				`OPRD_T_I: output_operand_I(effect_oprd_size);
				`OPRD_T_J: output_operand_J(effect_addr_size);
				`OPRD_T_M: output_operand_E(oprd2, prefix, modrm, sib, disp, effect_oprd_size);
				`OPRD_T_X: $write("%%ds(%%rsi)");
				`OPRD_T_DX: $write("(%%dx)");
				`OPRD_T_OP: output_operand_OP(oprd2, prefix, opcode, modrm);
				`OPRD_T_rAX: output_operand_rAX();
				default: $write("Unknown operand type (%x)", oprd2.t);
			endcase
		end

		oprd1 = get_operand1_desc(opcode, modrm);

		if (oprd1 != 0) begin
			$write(", ");
			case (oprd1.t)
				`OPRD_T_E: output_operand_E(oprd1, prefix, modrm, sib, disp, effect_oprd_size);
				`OPRD_T_G: output_operand_G(oprd1, modrm, effect_oprd_size);
				`OPRD_T_Y: $write("%%es(%%rdi)");
				`OPRD_T_DX: $write("(%%dx)");
				`OPRD_T_OP: output_operand_OP(oprd1, prefix, opcode, modrm);
				`OPRD_T_rAX: output_operand_rAX();
				default: $write("Unknown operand type (%x)", oprd1.t);
			endcase
		end
		$write("\n");
		decode_output = 0;
	endfunction
	/* verilator lint_on UNUSED */
`endif /* DECODER_OUTPUT */

	/* FIXME: remove this */
	/* verilator lint_off UNUSED */
	function logic decode_one(gene_pref_t prefix,
		opcode_t opcode, modrm_t modrm, sib_t sib, disp_t disp);
		//$display("%x %x %x %x %x %x %x", prefix, rex, opcode, modrm, sib, disp, imme);
		decode_one = 0;

	endfunction
	/* verilator lint_on UNUSED */

	always_comb begin
		if (can_decode) begin : decoder
			gene_pref_t prefix = 32'h0000_0000;
			opcode_t opcode = 0;
			modrm_t modrm = 9'h00;
			sib_t sib = 9'h00;
			disp_t disp = 0;

			logic[7:0] next_byte;
			logic rex_met = 1'b0;

			rex = 0;
			imme = 0;

			// cse502 : Decoder here
			// remove the following line. It is only here to allow successful compilation in the absence of your code.
			//$display("decode_bytes [%x]", decode_bytes);
			bytes_decoded = 0;
			next_byte = decode_bytes[{3'b000, bytes_decoded} * 8 +: 8];
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

				if (rex_met == 1) begin
					error_code = ec_rex;
					bytes_decoded += 1;
					next_byte = decode_bytes[{3'b000, bytes_decoded} * 8 +: 8];
					break;
				end

				if (rex != 0)
					rex_met = 1;

				bytes_decoded += 1;
				next_byte = decode_bytes[{3'b000, bytes_decoded} * 8 +: 8];
			end

			if (error_code == ec_rex) begin
				$write("(len %d):", bytes_decoded);
				for (int i = 0; i[3:0] < bytes_decoded; i += 1) begin
					$write(" %x", decode_bytes[i * 8 +: 8]);
				end
				$write("\n\t[Ignored invalid prefix(es).]\n");
			end
			else begin
				/* Opcode */
				if (next_byte == 8'h0F) begin
					bytes_decoded += 1;
					next_byte = decode_bytes[{3'b000, bytes_decoded} * 8 +: 8];

					/* 0F 38 escape */
					if (next_byte == 8'h38) begin
						opcode.escape = 2'h10;
						bytes_decoded += 1;
						next_byte = decode_bytes[{3'b000, bytes_decoded} * 8 +: 8];
					end
					/* 0F 3A escape */
					else if (next_byte == 8'h3A) begin
						opcode.escape = 2'h11;
						bytes_decoded += 1;
						next_byte = decode_bytes[{3'b000, bytes_decoded} * 8 +: 8];
					end
					/* 0F escape */
					else
						opcode.escape = 2'h01;
				end
				/* TODO: unsupported opcode */
				opcode.opcode = next_byte;
				bytes_decoded += 1;
				next_byte = decode_bytes[{3'b000, bytes_decoded} * 8 +: 8];
				modrm.exist = opcode_has_modrm(opcode);

				if (error_code != ec_none)
					$finish;

				/* ModR/M */
				if (modrm.exist == 1) begin
					modrm.v = next_byte;
					bytes_decoded += 1;
					next_byte = decode_bytes[{3'b000, bytes_decoded} * 8 +: 8];
				end

				/* SIB */
				if (modrm.v.mod != 2'b11 && modrm.v.rm == 3'b100) begin
					sib.exist = 1'b1;
					sib[7:0] = next_byte;
					bytes_decoded += 1;
					next_byte = decode_bytes[{3'b000, bytes_decoded} * 8 +: 8];
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
					bytes_decoded += 1;
					next_byte = decode_bytes[{3'b000, bytes_decoded} * 8 +: 8];
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
					bytes_decoded += 1;
					next_byte = decode_bytes[{3'b000, bytes_decoded} * 8 +: 8];
				end

				`ifdef DECODER_OUTPUT
				/* output */
				$write("(rip %x [%d]):", rip, bytes_decoded);
				for (int i = 0; i[3:0] < bytes_decoded; i += 1) begin
					$write(" %x", decode_bytes[i * 8 +: 8]);
				end
				$write("\n\t");
				decode_output(prefix, opcode, modrm, sib, disp);
				`endif
				decode_one(prefix, opcode, modrm, sib, disp);

				/* decoding */
			end /* error_code != ec_rex */

			/* finish decode cycle */
			//$display("Prefix: %d[%b]", prefix, prefix);
			//$display("REX: %x[%b]", rex, rex);
			//$display("Opcode: %x[%b]", opcode, opcode);
			//$display("ModRM: %x[%b]", modrm, modrm);
			//$display("SIB: %x[%b]", sib, sib);
			//$display("DISP: %x[%b]", disp, disp);
			//$display("IMME: %x[%b]", imme, imme);
		end
		else begin
			bytes_decoded = 0;
		end
	end

	final begin
		$display("RAX = %x", regfile[0]);
		$display("RBX = %x", regfile[3]);
		$display("RCX = %x", regfile[1]);
		$display("RDX = %x", regfile[2]);
		$display("RSI = %x", regfile[6]);
		$display("RDI = %x", regfile[7]);
		$display("RBP = %x", regfile[5]);
		$display("RSP = %x", regfile[4]);
		$display("R8  = %x", regfile[8]);
		$display("R9  = %x", regfile[9]);
		$display("R10 = %x", regfile[10]);
		$display("R11 = %x", regfile[11]);
		$display("R12 = %x", regfile[12]);
		$display("R13 = %x", regfile[13]);
		$display("R14 = %x", regfile[14]);
		$display("R15 = %x", regfile[15]);
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
