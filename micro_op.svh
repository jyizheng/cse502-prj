
`ifndef _MICRO_OP_SVH_
`define _MICRO_OP_SVH_

`include "operand.svh"

`define UOP_T_NONE	3'b00
`define UOP_T_NORM	3'b01
`define UOP_T_MEM	3'b10
`define UOP_T_BR	3'b11

typedef struct packed {
	logic[2:0] t;
	opcode_t opcode;
	oprd_t oprd1;
	oprd_t oprd2;
	oprd_t oprd3;
} micro_op_t;

`endif
