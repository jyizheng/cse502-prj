module Mem (input clk,
	input enable);

	enum { mem_idle, mem_waiting, mem_active } mem_state;

	always_ff @ (posedge clk) begin
		if (enable)
			$display("[MEM]");
	end

	always_comb begin
		
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
