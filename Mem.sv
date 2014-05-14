`include "micro_op.svh"

//`define MEM_DEBUG 1

module Mem (input clk,
	input enable,
	output mem_blocked,
	output mem_wb,

	input micro_op_t uop,
	input[127:0] alu_result,

	output[127:0] mem_result,

	output dcache_en,
	output dcache_wren,
	output dcache_flush,
	output[63:0] dcache_addr,
	input[63:0] dcache_rdata,
	output[63:0] dcache_wdata,
	input dcache_done
);

	enum { op_none, op_read, op_write, op_flush } mem_op;
	enum { mem_idle, mem_waiting, mem_active } mem_state;

	logic[63:0] rip;
	assign rip = uop.next_rip;

	logic[127:0] tmp_mem_result;

	logic[63:0] addr;
	logic[63:0] value;

	always_ff @ (posedge clk) begin
		if (dcache_en)
			dcache_en <= 0;
		if (dcache_wren)
			dcache_wren <= 0;
		if (dcache_flush)
			dcache_flush <= 0;
		if (mem_state == mem_idle) begin
			if (enable) begin
				if (mem_op == op_read) begin
`ifdef MEM_DEBUG
					$display("[MEM] reading from %x", addr);
`endif
					mem_state <= mem_waiting;
					dcache_en <= 1;
					dcache_wren <= 0;
					dcache_addr <= addr;
					mem_wb <= 0;
				end else if (mem_op == op_write) begin
`ifdef MEM_DEBUG
					$display("[MEM] writing %x into %x", value, addr);
`endif
					mem_state <= mem_waiting;
					dcache_en <= 1;
					dcache_wren <= 1;
					dcache_addr <= addr;
					dcache_wdata <= value;
					mem_wb <= 0;
				end else if (mem_op == op_flush) begin
`ifdef MEM_DEBUG
					$display("[MEM] flushing %x", addr);
`endif
					mem_state <= mem_waiting;
					dcache_en <= 1;
					dcache_flush <= 1;
					dcache_addr <= addr;
					mem_wb <= 0;
				end else begin
					/* No need to do memory ops */
					mem_result <= tmp_mem_result;
					mem_wb <= 1;
				end
			end else begin	/* !enable */
					mem_wb <= 0;
			end
		end else begin	/* !idle */
			if (dcache_done) begin
				dcache_en <= 0;
				dcache_wren <= 0;
				mem_state <= mem_idle;
				mem_result[63:0] <= dcache_rdata;
`ifdef MEM_DEBUG
				$display("[MEM] reading value %x", dcache_rdata);
`endif
				mem_wb <= 1;
			end else begin
				mem_wb <= 0;
			end
		end
	end

	always_comb begin
		mem_op = op_none;
		if (enable && mem_state == mem_idle) begin
			if (uop.opcode == 10'h08d) begin
				/* LEA */
				tmp_mem_result[63:0] = uop.oprd2.ext + uop.oprd2.value;
				mem_op = op_none;
				mem_blocked = 0;
			end else if (uop.opcode == 10'h1ae) begin
				/* CLFLUSH */
				mem_op = op_flush;
				addr = uop.oprd2.ext + uop.oprd2.value;
				mem_blocked = 1;
			end else if (uop.oprd1.t == `OPRD_T_MEM) begin
				/* XXX: block previous stages */
				mem_blocked = 1;
				mem_op = op_write;
				addr = uop.oprd1.ext + uop.oprd1.value;
				value = alu_result[63:0];
			end else if (uop.oprd2.t == `OPRD_T_MEM) begin
				/* XXX: block previous stages */
				mem_blocked = 1;
				mem_op = op_read;
				addr = uop.oprd2.ext + uop.oprd2.value;
			end else if (uop.oprd1.t == `OPRD_T_STACK) begin
				/* Writing into stack */
				mem_blocked = 1;
				mem_op = op_write;
				addr = uop.oprd1.ext - 8;
				value = alu_result[63:0];
			end else if (uop.oprd2.t == `OPRD_T_STACK) begin
				/* Reading from stack */
				mem_blocked = 1;
				mem_op = op_read;
				addr = uop.oprd2.ext;
				//$display("[MEM] oprd 2 %x %x %x %x", uop.oprd2.t, uop.oprd2.r, uop.oprd2.ext, uop.oprd2.value);
			end else begin
				/* No mem operation, unblock previous stages */
				tmp_mem_result = alu_result;
				mem_op = op_none;
				mem_blocked = 0;
			end
`ifdef MEM_DEBUG
				$display("[MEM] DEBUG (%x) %x %x (%x) [%x %x %x %x] [%x %x %x %x]", uop.next_rip, mem_blocked, mem_op, uop.opcode, uop.oprd1.t, uop.oprd1.r, uop.oprd1.ext, uop.oprd1.value, uop.oprd2.t, uop.oprd2.r, uop.oprd2.ext, uop.oprd2.value);
`endif
		end else if (mem_state == mem_waiting && dcache_done) begin
			/* XXX: unblock previous stages */
			mem_blocked = 0;
		end
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
