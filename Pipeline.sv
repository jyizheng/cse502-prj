module Pipeline (
	input clk
);
	enum { stage_if, stage_id, stage_ex, stage_mem, stage_wb } stage;

	always_ff @(posedge clk) begin
	end
endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
