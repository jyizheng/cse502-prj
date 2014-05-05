
module Arbiter(Sysbus bus,
	/* For instruction cache */
	input[bus.DATA_WIDTH-1:0] ireq,
	input[bus.TAG_WIDTH-1:0] ireqtag,
	output[bus.DATA_WIDTH-1:0] iresp,
	input[bus.TAG_WIDTH-1:0] iresptag,
	output ireqcyc,
	input irespcyc,
	input ireqack,
	output irespack,
	/* For data cache */
	input[bus.DATA_WIDTH-1:0] dreq,
	input[bus.TAG_WIDTH-1:0] dreqtag,
	output[bus.DATA_WIDTH-1:0] dresp,
	input[bus.TAG_WIDTH-1:0] dresptag,
	output dreqcyc,
	input drespcyc,
	input dreqack,
	output drespack
);
endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
