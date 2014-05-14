/* data cache */

`include "cache.svh"

module DCache(input clk,
	input enable,
	input wen,
	input clflush,
	input[63:0] addr,
	output[63:0] rdata,
	input[63:0] wdata,
	output done,

	output drequest,
	input dreqack,
	output dwrenable,
	output[63:0] daddr,
	input[64*8-1:0] drdata,
	output[64*8-1:0] dwdata,
	input ddone
);

	parameter 	ClWidth = 512,
				ClOffsetWidth = 6,	/* log_2 64 */
				IndexWidth = 9,
				WordSize = 64,
				TagWidth = 49; /* 64 - ClOffsetWidth - IndexWidth */

	enum { state_idle, state_r_s_wait, state_r_wb_wait, state_r_m_wait,
		state_w_s_wait, state_w_wb_wait, state_w_m_wait,
		state_wb_s_wait, state_wb_m_wait } dc_state;

	logic[IndexWidth-1:0] cl_index;
	logic[TagWidth-1:0] cl_tag;
	logic[ClOffsetWidth-1:0] cl_offset;

	assign cl_offset = addr_buf[0+:ClOffsetWidth];
	assign cl_index = addr_buf[ClOffsetWidth+:IndexWidth];
	assign cl_tag = addr_buf[(ClOffsetWidth+IndexWidth)+:TagWidth];

	logic[ClWidth-1:0] cl_rdata[1:0];
	logic[63:0] cl_racc[1:0];

	int acc_wait;
	int data_wait;

	logic[ClWidth-1:0] cl_wdata[1:0];
	logic[ClWidth/WordSize-1:0] cl_wdata_en[1:0];
	logic[63:0] cl_wacc[1:0];
	logic[0:0] cl_wacc_en[1:0];

	logic[1:0] cl_hit;

	logic[0:0] cl_way_rp_sel; /* replacement selector */

	logic cl_need_wb;

	logic[63:0] cl_acc_r_tmp_new;
	logic[63:0] cl_acc_w_tmp_new;
	logic[63:0] cl_acc_r_tmp_update[1:0];
	logic[63:0] cl_acc_w_tmp_update[1:0];

	logic[ClWidth/WordSize-1:0] cl_wdata_en_tmp;

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


	logic[63:0] addr_buf;
	logic[63:0] wdata_buf;
	//logic[64*8-1:0] dc_buf;
	//logic[7:0] buf_idx;

	always_comb begin
		if (dc_state == state_idle && enable) begin
			addr_buf = addr;
			wdata_buf = wdata;
		end

		if (dc_state == state_r_s_wait ||
			dc_state == state_w_s_wait ||
			dc_state == state_wb_s_wait) begin
			if (acc_wait == 0) begin
				cl_hit[0] = (cl_racc[0][`CL_ACC_V] && cl_racc[0][`CL_ACC_T_MSB:`CL_ACC_T_LSB] == cl_tag);
				cl_hit[1] = (cl_racc[1][`CL_ACC_V] && cl_racc[1][`CL_ACC_T_MSB:`CL_ACC_T_LSB] == cl_tag);

				if (cl_racc[0][`CL_ACC_V] == 0) begin
					cl_way_rp_sel = 0;
					cl_need_wb = 0;
				end else if (cl_racc[1][`CL_ACC_V] == 0) begin
					cl_way_rp_sel = 1;
					cl_need_wb = 0;
				end else if (cl_racc[1][`CL_ACC_T] == 0) begin
					cl_way_rp_sel = 1;
					cl_need_wb = cl_racc[1][`CL_ACC_D];
				end else if (cl_racc[0][`CL_ACC_T] == 0) begin
					cl_way_rp_sel = 0;
					cl_need_wb = cl_racc[0][`CL_ACC_D];
				end else begin
					cl_way_rp_sel = 0;
					cl_need_wb = cl_racc[0][`CL_ACC_D];
				end

				/* For read operation */
				cl_acc_r_tmp_new = 0;
				cl_acc_r_tmp_new[`CL_ACC_T_MSB:`CL_ACC_T_LSB] = cl_tag;
				cl_acc_r_tmp_new[`CL_ACC_V] = 1;
				cl_acc_r_tmp_new[`CL_ACC_T] = 1;
				cl_acc_r_tmp_new[`CL_ACC_D] = 0;

				cl_acc_r_tmp_update[0] = cl_racc[0];
				cl_acc_r_tmp_update[0][`CL_ACC_T] = 1;
				cl_acc_r_tmp_update[1] = cl_racc[1];
				cl_acc_r_tmp_update[1][`CL_ACC_T] = 1;

				/* For write operation */
				cl_acc_w_tmp_new = 0;
				cl_acc_w_tmp_new[`CL_ACC_T_MSB:`CL_ACC_T_LSB] = cl_tag;
				cl_acc_w_tmp_new[`CL_ACC_V] = 1;
				cl_acc_w_tmp_new[`CL_ACC_T] = 1;
				cl_acc_w_tmp_new[`CL_ACC_D] = 1;

				cl_acc_w_tmp_update[0] = cl_racc[0];
				cl_acc_w_tmp_update[0][`CL_ACC_T] = 1;
				cl_acc_w_tmp_update[0][`CL_ACC_D] = 1;
				cl_acc_w_tmp_update[1] = cl_racc[1];
				cl_acc_w_tmp_update[1][`CL_ACC_T] = 1;
				cl_acc_w_tmp_update[1][`CL_ACC_D] = 1;

				cl_wdata_en_tmp = 0;
				cl_wdata_en_tmp[cl_offset[5:3]] = 1;

				cl_acc_neg_tmp[0] = cl_racc[0];
				cl_acc_neg_tmp[0][`CL_ACC_T] = 0;
				cl_acc_neg_tmp[1] = cl_racc[1];
				cl_acc_neg_tmp[1][`CL_ACC_T] = 0;
			end
		end
	end

	always_ff @ (posedge clk) begin
		if (dc_state == state_idle) begin
			done <= 0;
			rdata <= 0;
			cl_wacc_en[0] <= 0;
			cl_wacc_en[1] <= 0;
			cl_wdata_en[0] <= 0;
			cl_wdata_en[1] <= 0;
			if (enable) begin
				assert(addr[5:0] == 0) else $fatal("[DCACHE] unaligned mem addr ");
				if (clflush)
					dc_state <= state_wb_s_wait;
				else if (wen)
					dc_state <= state_w_s_wait;
				else
					dc_state <= state_r_s_wait;

				acc_wait <= sr_acc0.delay;
				data_wait <= sr_data0.delay;
			end
		end else if (dc_state == state_r_s_wait) begin
			if (acc_wait == 0 && data_wait == 0) begin
				if (cl_hit[0]) begin
					dc_state <= state_idle;
					rdata <= cl_rdata[0][cl_offset*8+:64];
					done <= 1;

					/* Update our timing info */
					cl_wacc[0] <= cl_acc_r_tmp_update[0];
					cl_wacc_en[0] <= 1;

					/* set the other ways' timing info */
					if (cl_racc[1][`CL_ACC_V]) begin
						cl_wacc[1] <= cl_acc_neg_tmp[1];
						cl_wacc_en[1] <= 1;
					end
				end else if (cl_hit[1]) begin
					dc_state <= state_idle;
					rdata <= cl_rdata[1][cl_offset*8+:64];
					done <= 1;

					/* Update our timing info */
					cl_wacc[1] <= cl_acc_r_tmp_update[1];
					cl_wacc_en[1] <= 1;

					/* set the other ways' timing info */
					if (cl_racc[0][`CL_ACC_V]) begin
						cl_wacc[0] <= cl_acc_neg_tmp[0];
						cl_wacc_en[0] <= 1;
					end
				end else begin
					/* Cache miss */
					if (cl_need_wb) begin
						dc_state <= state_r_wb_wait;
						drequest <= 1;
						dwrenable <= 1;
						dwdata <= cl_rdata[cl_way_rp_sel];
						daddr <= {cl_racc[cl_way_rp_sel][`CL_ACC_T_MSB:`CL_ACC_T_LSB], cl_index, 6'b000000};
					end else begin
						dc_state <= state_r_m_wait;
						drequest <= 1;
						dwrenable <= 0;
						daddr <= {addr_buf[63:6], 6'b000000};
					end
				end
			end else begin
				if (acc_wait > 0)
					acc_wait <= acc_wait - 1;
				if (data_wait > 0)
					data_wait <= data_wait - 1;
			end
		end else if (dc_state == state_w_s_wait) begin
			if (acc_wait == 0 && data_wait == 0) begin
				if (cl_hit[0]) begin
					dc_state <= state_idle;
					cl_wdata[0][cl_offset*8+:64] <= wdata;
					cl_wdata_en[0] <= cl_wdata_en_tmp;
					done <= 1;

					/* Update our timing info */
					cl_wacc[0] <= cl_acc_w_tmp_update[0];
					cl_wacc_en[0] <= 1;

					/* set the other ways' timing info */
					if (cl_racc[1][`CL_ACC_V]) begin
						cl_wacc[1] <= cl_acc_neg_tmp[1];
						cl_wacc_en[1] <= 1;
					end
				end else if (cl_hit[1]) begin
					dc_state <= state_idle;
					cl_wdata[1][cl_offset*8+:64] <= wdata;
					cl_wdata_en[1] <= cl_wdata_en_tmp;
					done <= 1;

					/* Update our timing info */
					cl_wacc[1] <= cl_acc_w_tmp_update[1];
					cl_wacc_en[1] <= 1;

					/* set the other ways' timing info */
					if (cl_racc[0][`CL_ACC_V]) begin
						cl_wacc[0] <= cl_acc_neg_tmp[0];
						cl_wacc_en[0] <= 1;
					end
				end else begin
					/* Cache miss */
					if (cl_need_wb) begin
						dc_state <= state_w_wb_wait;
						drequest <= 1;
						dwrenable <= 1;
						dwdata <= cl_rdata[cl_way_rp_sel];
						daddr <= {cl_racc[cl_way_rp_sel][`CL_ACC_T_MSB:`CL_ACC_T_LSB], cl_index, 6'b000000};
					end else begin
						dc_state <= state_w_m_wait;
						drequest <= 1;
						dwrenable <= 0;
						daddr <= {addr_buf[63:6], 6'b000000};
					end
				end
			end else begin
				if (acc_wait > 0)
					acc_wait <= acc_wait - 1;
				if (data_wait > 0)
					data_wait <= data_wait - 1;
			end
		end else if (dc_state == state_wb_s_wait) begin
			if (acc_wait == 0 && data_wait == 0) begin
				if (cl_hit[0]) begin
					dc_state <= state_wb_m_wait;
					drequest <= 1;
					dwrenable <= 1;
					dwdata <= cl_rdata[0];
					daddr <= {cl_racc[0][`CL_ACC_T_MSB:`CL_ACC_T_LSB], cl_index, 6'b000000};
				end else if (cl_hit[1]) begin
					dc_state <= state_wb_m_wait;
					drequest <= 1;
					dwrenable <= 1;
					dwdata <= cl_rdata[1];
					daddr <= {cl_racc[1][`CL_ACC_T_MSB:`CL_ACC_T_LSB], cl_index, 6'b000000};
				end else begin
					/* Don't need to flush anything */
					dc_state <= state_idle;
					done <= 1;
				end
			end else begin
				if (acc_wait > 0)
					acc_wait <= acc_wait - 1;
				if (data_wait > 0)
					data_wait <= data_wait - 1;
			end
		end else if (dc_state == state_r_wb_wait) begin
			if (dreqack) begin
				drequest <= 0;
				dwrenable <= 0;
			end

			if (ddone) begin
				dc_state <= state_r_m_wait;
				daddr <= {addr_buf[63:6], 6'b000000};
				drequest <= 1;
				dwrenable <= 0;
			end
		end else if (dc_state == state_w_wb_wait) begin
			if (dreqack) begin
				drequest <= 0;
				dwrenable <= 0;
			end

			if (ddone) begin
				dc_state <= state_w_m_wait;
				daddr <= {addr_buf[63:6], 6'b000000};
				drequest <= 1;
				dwrenable <= 0;
			end
		end else if (dc_state == state_r_m_wait) begin
			if (dreqack) begin
				drequest <= 0;
				dwrenable <= 0;
			end

			if (ddone) begin
				dc_state <= state_idle;

				rdata <= drdata[cl_offset*8+:64];
				done <= 1;

				/* Allocate cache line */
				cl_wdata[cl_way_rp_sel] <= drdata;
				cl_wdata_en[cl_way_rp_sel] <= `CL_WEN_ALL;
				cl_wacc[cl_way_rp_sel] <= cl_acc_r_tmp_new;
				cl_wacc_en[cl_way_rp_sel] <= 1;
			end
		end else if (dc_state == state_w_m_wait) begin
			if (dreqack) begin
				drequest <= 0;
				dwrenable <= 0;
			end

			if (ddone) begin
				dc_state <= state_idle;

				done <= 1;

				/* Allocate cache line */
				cl_wdata[cl_way_rp_sel] <= drdata;
				cl_wdata_en[cl_way_rp_sel] <= `CL_WEN_ALL;
				cl_wacc[cl_way_rp_sel] <= cl_acc_w_tmp_new;
				cl_wacc_en[cl_way_rp_sel] <= 1;

				/* Write data into it */
				cl_wdata[cl_way_rp_sel][cl_offset*8+:64] <= wdata_buf;
			end

		end else if (dc_state == state_wb_m_wait) begin
			if (dreqack) begin
				drequest <= 0;
				dwrenable <= 0;
			end

			if (ddone) begin
				dc_state <= state_idle;
				done <= 1;
				if (cl_hit[0]) begin
					cl_wacc[0] <= 0;
					cl_wacc_en[0] <= 1;
				end
				if (cl_hit[1]) begin
					cl_wacc[1] <= 0;
					cl_wacc_en[1] <= 1;
				end
			end
		end
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
