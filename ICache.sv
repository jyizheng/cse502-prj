/* instruction cache */
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

	enum { state_idle, state_s_wait, state_m_wait } ic_state;

	logic[63:0] addr_buf;

	logic[IndexWidth-1:0] cl_index;
	logic[TagWidth-1:0] cl_tag;
	logic[ClOffsetWidth-1:0] cl_offset;

	logic[ClWidth-1:0] cl_rdata[1:0];
	logic[63:0] cl_racc[1:0];

	int wait_delay;

	assign cl_offset = addr_buf[0+:ClOffsetWidth];
	assign cl_index = addr_buf[ClOffsetWidth+:IndexWidth];
	assign cl_tag = addr_buf[(ClOffsetWidth+IndexWidth)+:TagWidth];

	logic[ClWidth-1:0] cl_wdata[1:0];
	logic[ClWidth/WordSize-1:0] cl_wdata_en[1:0];
	logic[63:0] cl_wacc[1:0];
	logic[0:0] cl_wacc_en[1:0];

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

	always_ff @ (posedge clk) begin
		if (ic_state == state_idle) begin
			done <= 0;
			rdata <= 0;
			if (enable == 1) begin
				assert((addr & 63) == 0) else $fatal;

				ic_state <= state_m_wait;
				irequest <= 1;
				iaddr <= addr;
			end
		end else begin // !state_idle
			if (ireqack)
				irequest <= 0;

			if (idone) begin
				ic_state <= state_idle;
				rdata <= idata;
				done <= 1;
			end
		end
	end

	always_comb begin
		if (ic_state == state_idle && enable) begin
			addr_buf = addr;
		end
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
