`ifndef _OPERAND_SVH_
`define _OPERAND_SVH_ 1

`define OPRD_T_NONE	0
`define OPRD_T_REG	1
`define OPRD_T_MEM	2
`define OPRD_T_IMME	3

typedef struct packed {
	logic[3:0] type;
	logic[31:0] priv;	/* private data: reg no. for REG, disp for MEM */
	logic[63:0] value;
} oprd_t;

`endif

/* vim: set ts=4 sw=0 tw=0 noet : */
