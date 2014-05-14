/* instruction cache */

`include "cache.svh"

module ICache(input clk,
	input enable,
	input[63:0] addr,
	output[511:0] rdata,
	output done,

	output irequest,
	input ireqack,
	output[63:0] iaddr,
	input[511:0] idata,
	input idone
);

	parameter 	ClWidth = 512,
				ClOffsetWidth = 6,	/* log_2 64 */
				IndexWidth = 9,
				WordSize = 64,
				TagWidth = 49; /* 64 - ClOffsetWidth - IndexWidth */

	enum { state_idle, state_s_wait, state_s_m_wait, state_m_wait } ic_state;

	logic[63:0] addr_buf;

	logic[IndexWidth-1:0] cl_index;
	logic[TagWidth-1:0] cl_tag;
/* verilator lint_off UNUSED */
	logic[ClOffsetWidth-1:0] cl_offset;
/* verilator lint_on UNUSED */

	logic[ClWidth-1:0] cl_rdata[1:0];
	logic[63:0] cl_racc[1:0];

	int acc_wait;
	int data_wait;

	assign cl_offset = addr_buf[0+:ClOffsetWidth];
	assign cl_index = addr_buf[ClOffsetWidth+:IndexWidth];
	assign cl_tag = addr_buf[(ClOffsetWidth+IndexWidth)+:TagWidth];

	logic[ClWidth-1:0] cl_wdata[1:0];
	logic[ClWidth/WordSize-1:0] cl_wdata_en[1:0];
	logic[63:0] cl_wacc[1:0];
	logic[0:0] cl_wacc_en[1:0];

	logic[1:0] cl_hit;

	logic[0:0] cl_way_rp_sel; /* replacement selector */

	logic[63:0] cl_acc_tmp;

	logic[63:0] cl_acc_neg_tmp[1:0]; /* Used for update Timing info */

	SRAM #(	.width(ClWidth),
			.logDepth(IndexWidth),
			.wordsize(WordSize),
			.ports(1)) sr_data0(clk, cl_index, cl_rdata[0], cl_index, cl_wdata[0], cl_wdata_en[0]);
	SRAM #(	.width(ClWidth),
			.logDepth(IndexWidth),
			.wordsize(WordSize),
			.ports(1)) sr_data1(clk, cl_index, cl_rdata[1], cl_index, cl_wdata[1], cl_wdata_en[1]);

	SRAM #(	.width(64),
			.logDepth(IndexWidth),
			.wordsize(WordSize),
			.ports(1)) sr_acc0(clk, cl_index, cl_racc[0], cl_index, cl_wacc[0], cl_wacc_en[0]);
	SRAM #(	.width(64),
			.logDepth(IndexWidth),
			.wordsize(WordSize),
			.ports(1)) sr_acc1(clk, cl_index, cl_racc[1], cl_index, cl_wacc[1], cl_wacc_en[1]);

	always_comb begin
		if (ic_state == state_idle && enable) begin
			addr_buf = addr;
		end

		if (ic_state == state_s_wait) begin
			if (acc_wait == 0) begin
				cl_hit[0] = (cl_racc[0][`CL_ACC_V] && cl_racc[0][`CL_ACC_T_MSB:`CL_ACC_T_LSB] == cl_tag);
				cl_hit[1] = (cl_racc[1][`CL_ACC_V] && cl_racc[1][`CL_ACC_T_MSB:`CL_ACC_T_LSB] == cl_tag);

				if (cl_racc[0][`CL_ACC_V] == 0)
					cl_way_rp_sel = 0;
				else if (cl_racc[1][`CL_ACC_V] == 0)
					cl_way_rp_sel = 1;
				else if (cl_racc[1][`CL_ACC_T] == 0)
					cl_way_rp_sel = 1;
				else if (cl_racc[0][`CL_ACC_T] == 0)
					cl_way_rp_sel = 0;
				else
					cl_way_rp_sel = 0;

				cl_acc_tmp = 0;
				cl_acc_tmp[`CL_ACC_T_MSB:`CL_ACC_T_LSB] = cl_tag;
				cl_acc_tmp[`CL_ACC_V] = 1;
				cl_acc_tmp[`CL_ACC_T] = 1;

				cl_acc_neg_tmp[0] = cl_racc[0];
				cl_acc_neg_tmp[0][`CL_ACC_T] = 0;

				cl_acc_neg_tmp[1] = cl_racc[1];
				cl_acc_neg_tmp[1][`CL_ACC_T] = 0;
			end
		end
	end

	always_ff @ (posedge clk) begin
		if (ic_state == state_idle) begin
			done <= 0;
			rdata <= 0;
			cl_wacc_en[0] <= 0;
			cl_wacc_en[1] <= 0;
			cl_wdata_en[0] <= 0;
			cl_wdata_en[1] <= 0;
			if (enable) begin
				assert((addr & 63) == 0) else $fatal;

				ic_state <= state_s_wait;
				acc_wait <= sr_acc0.delay;
				data_wait <= sr_data0.delay;
			end
		end else if (ic_state == state_s_wait) begin
			if (acc_wait == 0 && data_wait == 0) begin
				if (cl_hit[0]) begin
					ic_state <= state_idle;
					rdata <= cl_rdata[0];
					done <= 1;

					/* Update our timing info */
					cl_wacc[0] <= cl_acc_tmp;
					cl_wacc_en[0] <= 1;

					/* set the other ways' timing info */
					if (cl_racc[1][`CL_ACC_V]) begin
						cl_wacc[1] <= cl_acc_neg_tmp[1];
						cl_wacc_en[1] <= 1;
					end
				end else if (cl_hit[1]) begin
					ic_state <= state_idle;
					rdata <= cl_rdata[1];
					done <= 1;

					/* Update our timing info */
					cl_wacc[1] <= cl_acc_tmp;
					cl_wacc_en[1] <= 1;

					/* set the other ways' timing info */
					if (cl_racc[0][`CL_ACC_V]) begin
						cl_wacc[0] <= cl_acc_neg_tmp[0];
						cl_wacc_en[0] <= 1;
					end
				end else begin
					/* Cache miss */
					ic_state <= state_m_wait;
					irequest <= 1;
					iaddr <= addr;
				end
			end else begin
				if (acc_wait > 0)
					acc_wait <= acc_wait - 1;
				if (data_wait > 0)
					data_wait <= data_wait - 1;
			end
		end else if (ic_state == state_m_wait) begin
			if (ireqack)
				irequest <= 0;

			if (idone) begin
				ic_state <= state_idle;
				rdata <= idata;
				done <= 1;

				/* Allocate cache line */
				cl_wdata[cl_way_rp_sel] <= idata;
				cl_wdata_en[cl_way_rp_sel] <= `CL_WEN_ALL;
				cl_wacc[cl_way_rp_sel] <= cl_acc_tmp;
				cl_wacc_en[cl_way_rp_sel] <= 1;
			end
		end
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
