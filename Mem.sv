module Mem (Sysbus bus);

	always_ff @ (posedge bus.clk) begin
		$display("[MEM]");
	end

endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
