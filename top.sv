module top #(DATA_WIDTH = 64, TAG_WIDTH = 13) (
	input[63:0] entry
,	input reset
,	input clk
,	output[DATA_WIDTH-1:0] req
,	output[TAG_WIDTH-1:0] reqtag
,	input[DATA_WIDTH-1:0] resp
,	input[TAG_WIDTH-1:0] resptag
,	output reqcyc
,	input respcyc
,	input reqack
,	output respack
);
	/* verilator lint_off UNDRIVEN */
	/* verilator lint_off UNUSED */
	Sysbus #(DATA_WIDTH, TAG_WIDTH) uncore_bus(reset, clk);
	SysbusBottom #(DATA_WIDTH, TAG_WIDTH) dummy(uncore_bus.Bottom, req, reqtag, resp, resptag, reqcyc, respcyc, reqack, respack);
	wire can_decode;
	wire[63:0] rip;
	wire[0:15*8-1] decode_bytes;
	wire[3:0] bytes_decoded;
	Core core(entry, uncore_bus.Top, bytes_decoded, can_decode, rip, decode_bytes);
	Decoder docoder(can_decode, rip, decode_bytes, bytes_decoded);
	/* verilator lint_on UNUSED */
	/* verilator lint_on UNDRIVEN */

	initial begin
		$display("Initializing top, entry point = %x", entry);
	end
endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
