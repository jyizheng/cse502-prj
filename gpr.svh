
`ifndef _GPR_SVH_
`define _GPR_SVH_ 1

`define GPR_RAX	4'd0
`define GPR_RCX	4'd1
`define GPR_RDX	4'd2
`define GPR_RBX	4'd3
`define GPR_RSP	4'd4
`define GPR_RBP	4'd5
`define GPR_RSI	4'd6
`define GPR_RDI	4'd7
`define GPR_R8	4'd8
`define GPR_R9	4'd9
`define GPR_R10	4'd10
`define GPR_R11	4'd11
`define GPR_R12	4'd12
`define GPR_R13	4'd13
`define GPR_R14	4'd14
`define GPR_R15	4'd15

/* Register types are used to indicate the size/bit-fields of GPRs */
`define GPR_T_64	3'h1
`define GPR_T_32L	3'h2
`define GPR_T_16L	3'h3
`define GPR_T_8L	3'h4
`define GPR_T_8H	3'h5


`endif
