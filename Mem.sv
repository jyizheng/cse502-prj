module Mem (Sysbus bus);

	enum { mem_idle, mem_waiting, mem_active } mem_state;

	always_ff @ (posedge bus.clk) begin
		$display("[MEM]");
	end

	always_comb begin
		
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
