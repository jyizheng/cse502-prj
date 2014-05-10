module Mem (input clk,
	input enable,

	input oprd_t oprd,
	input[127:0] alu_result,

	output[127:0] mem_result,

	output dcache_en,
	output dcache_wren,
	output[63:0] dcache_addr,
	input[63:0] dcache_rdata,
	output[63:0] dcache_wdata,
	input dcache_done
);

	enum { mem_idle, mem_waiting, mem_active } mem_state;

	always_ff @ (posedge clk) begin
		if (enable) begin
			$display("[MEM]");
			mem_result <= alu_result;
		end
	end

	always_comb begin
		
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
