`include "instruction.svh"

module Core (
	input[63:0] entry
,	/* verilator lint_off UNDRIVEN */ /* verilator lint_off UNUSED */ Sysbus bus /* verilator lint_on UNUSED */ /* verilator lint_on UNDRIVEN */
);
	enum { fetch_idle, fetch_waiting, fetch_active } fetch_state;
	logic[63:0] fetch_rip;
	logic[0:2*64*8-1] decode_buffer; // NOTE: buffer bits are left-to-right in increasing order
	logic[5:0] fetch_skip;
	logic[6:0] fetch_offset, decode_offset;

	/* XXX: verilator bug work around for passing bus.clk */
	logic clk;

	assign clk = bus.clk;

	function logic mtrr_is_mmio(logic[63:0] physaddr);
		mtrr_is_mmio = ((physaddr > 640*1024 && physaddr < 1024*1024));
	endfunction

	logic send_fetch_req;
	always_comb begin
		if (fetch_state != fetch_idle) begin
			send_fetch_req = 0; // hack: in theory, we could try to send another request at this point
		end else if (bus.reqack) begin
			send_fetch_req = 0; // hack: still idle, but already got ack (in theory, we could try to send another request as early as this)
		end else begin
			send_fetch_req = (fetch_offset - decode_offset < 7'd32);
		end
	end

	assign bus.respack = bus.respcyc; // always able to accept response

	always @ (posedge bus.clk)
		if (bus.reset) begin

			fetch_state <= fetch_idle;
			fetch_rip <= entry & ~63;
			fetch_skip <= entry[5:0];
			fetch_offset <= 0;

			//regfile <= 0;

		end else begin // !bus.reset

			bus.reqcyc <= send_fetch_req;
			bus.req <= fetch_rip & ~63;
			bus.reqtag <= { bus.READ, bus.MEMORY, 8'b0 };

			if (bus.respcyc) begin
				assert(!send_fetch_req) else $fatal;
				fetch_state <= fetch_active;
				fetch_rip <= fetch_rip + 8;
				if (fetch_skip > 0) begin
					fetch_skip <= fetch_skip - 8;
				end else begin
					//$display("Fetch: [%d] %08x %08x", fetch_offset, bus.resp[63:32], bus.resp[31:0]);
					decode_buffer[fetch_offset*8 +: 64] <= bus.resp;
					//$display("fill at %d: %x [%x]", fetch_offset, bus.resp, decode_buffer);
					fetch_offset <= fetch_offset + 8;
				end
			end else begin
				if (fetch_state == fetch_active) begin
					fetch_state <= fetch_idle;
				end else if (bus.reqack) begin
					assert(fetch_state == fetch_idle) else $fatal;
					fetch_state <= fetch_waiting;
				end
			end

		end

	wire[0:(128+15)*8-1] decode_bytes_repeated = { decode_buffer, decode_buffer[0:15*8-1] }; // NOTE: buffer bits are left-to-right in increasing order
	wire[0:15*8-1] decode_bytes = decode_bytes_repeated[decode_offset*8 +: 15*8]; // NOTE: buffer bits are left-to-right in increasing order
	wire can_decode = (fetch_offset - decode_offset >= 7'd15);

	function logic opcode_inside(logic[7:0] value, low, high);
		opcode_inside = (value >= low && value <= high);
	endfunction

	logic[3:0] bytes_decoded_this_cycle;

	always @ (posedge bus.clk) begin
		if (bus.reset) begin

			decode_offset <= 0;
			decode_buffer <= 0;

		end else begin // !bus.reset

			decode_offset <= decode_offset + { 3'b0, bytes_decoded_this_cycle };

		end
	end

	/* Decode stage */
	logic dc_taken = 0;
	micro_op_t dc_uop;
	Decoder decoder(clk, can_decode, fetch_rip, decode_bytes, dc_taken, bytes_decoded_this_cycle, dc_uop);

	/* Data Fetch stage */

	/* EXE stage */

	/* MEM stage */

	/* WB stage */

	always_comb begin
		if (can_decode) begin : decode_block
			// cse502 : following is an example of how to finish the simulation
			if (decode_bytes == 0 && fetch_state == fetch_idle) $finish;
		end
	end

	// cse502 : Use the following as a guide to print the Register File contents.
	//final begin
		//$display("RAX = %x", regfile[0]);
		//$display("RBX = %x", regfile[3]);
		//$display("RCX = %x", regfile[1]);
		//$display("RDX = %x", regfile[2]);
		//$display("RSI = %x", regfile[6]);
		//$display("RDI = %x", regfile[7]);
		//$display("RBP = %x", regfile[5]);
		//$display("RSP = %x", regfile[4]);
		//$display("R8  = %x", regfile[8]);
		//$display("R9  = %x", regfile[9]);
		//$display("R10 = %x", regfile[10]);
		//$display("R11 = %x", regfile[11]);
		//$display("R12 = %x", regfile[12]);
		//$display("R13 = %x", regfile[13]);
		//$display("R14 = %x", regfile[14]);
		//$display("R15 = %x", regfile[15]);
	//end
endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
