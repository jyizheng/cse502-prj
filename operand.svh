`ifndef _OPERAND_SVH_
`define _OPERAND_SVH_ 1

`define OPRD_T_NONE	0
`define OPRD_T_REG	1
`define OPRD_T_MEM	2
`define OPRD_T_IMME	3

`define OPRD_R_NONE	5'h1F

typedef struct packed {
	logic[3:0] t;		/* Type */
	logic[4:0] r;		/* Register No. */
	logic[63:0] ext;	/* extension data: disp for MEM */
	logic[63:0] value;
} oprd_t;

`endif

/* vim: set ts=4 sw=0 tw=0 noet : */
