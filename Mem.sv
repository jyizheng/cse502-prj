`include "micro_op.svh"

`define MEM_DEBUG 1

module Mem (input clk,
	input enable,
	output mem_blocked,
	output mem_wb,

	input micro_op_t uop,
	input[127:0] alu_result,

	output[127:0] mem_result,

	output dcache_en,
	output dcache_wren,
	output[63:0] dcache_addr,
	input[63:0] dcache_rdata,
	output[63:0] dcache_wdata,
	input dcache_done
);

	enum { op_none, op_read, op_write } mem_op;
	enum { mem_idle, mem_waiting, mem_active } mem_state;

	logic[63:0] addr;
	logic[63:0] value;

	always_ff @ (posedge clk) begin
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
				end else begin
					/* No need to do memory ops */
					mem_result <= alu_result;
					mem_wb <= 1;
				end
			end else begin	/* !enable */
					mem_wb <= 0;
			end
		end else begin	/* !idle */
			if (dcache_done) begin
				mem_state <= mem_idle;
				mem_result[63:0] <= dcache_rdata;
				mem_wb <= 1;
			end else begin
				mem_wb <= 0;
			end
		end
	end

	always_comb begin
		mem_op = op_none;
		if (enable && mem_state == mem_idle) begin
			if (uop.oprd1.t == `OPRD_T_MEM) begin
				/* XXX: block previous stages */
				mem_blocked = 1;
				mem_op = op_write;
				addr = uop.oprd1.ext;
				value = alu_result[63:0];
			end else if (uop.oprd2.t == `OPRD_T_MEM) begin
				/* XXX: block previous stages */
				mem_blocked = 1;
				mem_op = op_read;
				addr = uop.oprd1.ext;
			end else begin
				/* No mem operation, unblock previous stages */
				mem_blocked = 0;
			end
		end else if (mem_state == mem_waiting && dcache_done) begin
			/* XXX: unblock previous stages */
			mem_blocked = 0;
		end
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
