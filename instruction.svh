/* Defines */

`ifndef _INSTRUCTION_SVH_
`define _INSTRUCTION_SVH_ 1
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

typedef struct packed {
	opcode_t opcode;
	modrm_t modrm;
	sib_t sib;
	disp_t disp;
	imme_t imme;
} micro_op_t;

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

`endif

/* vim: set ts=4 sw=0 tw=0 noet : */
