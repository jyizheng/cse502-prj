/* Instruction-Fetch */
module INF(input clk,
	input set_rip,
	input[63:0] new_rip,

	output ic_enable,
	output[63:0] iaddr,
	input[511:0] idata,
	input ic_done,

	output[0:15*8-1] decode_bytes,
	output[63:0] decode_rip,
	input[7:0] bytes_decoded,

	output if_dc,
	input dc_if
);

	logic initialized;

	initial begin
		initialized = 0;
	end

	enum { fetch_idle, fetch_waiting, fetch_active } fetch_state;
	logic[63:0] fetch_rip;
	logic[5:0] fetch_skip;
	logic[6:0] fetch_offset, decode_offset;

	logic[0:2*64*8-1] decode_buffer; // NOTE: buffer bits are left-to-right in increasing order

	logic send_fetch_req;

	always_comb begin
		if (fetch_state != fetch_idle) begin
			send_fetch_req = 0; // hack: in theory, we could try to send another request at this point
		end else if (initialized) begin
			send_fetch_req = (fetch_offset - decode_offset < 7'd32);
		end
	end

	always @ (posedge clk) begin
		if (set_rip) begin
			initialized <= 1;
			fetch_state <= fetch_idle;
			decode_rip <= new_rip;
			fetch_rip <= new_rip & ~63;
			fetch_skip <= new_rip[5:0];
			fetch_offset <= 0;

			decode_offset <= 0;
			decode_buffer <= 0;
		end else begin
			if (fetch_state == fetch_waiting) begin
				ic_enable <= 0;
				if (ic_done == 1) begin
					fetch_rip <= fetch_rip + 64;
					for (int i = fetch_skip; i < 64; i += 8) begin
						decode_buffer[(fetch_offset+i-fetch_skip)*8+:64] <= idata[i*8+:64];
					end
					fetch_offset <= fetch_offset + (64 - fetch_skip);
					fetch_skip <= 0;
					iaddr <= 0;
					fetch_state <= fetch_idle;
				end
			end else if (send_fetch_req) begin // !fetch_waiting
				ic_enable <= 1;
				iaddr <= fetch_rip & ~63;
				fetch_state <= fetch_waiting;
			end

			decode_offset <= decode_offset + { bytes_decoded };
			decode_rip <= decode_rip + bytes_decoded;
		end
	end

	wire[0:(128+15)*8-1] decode_bytes_repeated = { decode_buffer, decode_buffer[0:15*8-1] }; // NOTE: buffer bits are left-to-right in increasing order
	wire[0:15*8-1] decode_bytes = decode_bytes_repeated[decode_offset*8 +: 15*8]; // NOTE: buffer bits are left-to-right in increasing order
	assign if_dc = (fetch_offset - decode_offset >= 7'd15);

//	assign bus.respack = bus.respcyc; // always able to accept response
//
//	always @ (posedge bus.clk)
//		if (bus.reset) begin
//
//			fetch_state <= fetch_idle;
//			fetch_rip <= entry & ~63;
//			fetch_skip <= entry[5:0];
//			fetch_offset <= 0;
//
//		end else begin // !bus.reset
//
//			bus.reqcyc <= send_fetch_req;
//			bus.req <= fetch_rip & ~63;
//			bus.reqtag <= { bus.READ, bus.MEMORY, 8'b0 };
//
//			if (bus.respcyc) begin
//				assert(!send_fetch_req) else $fatal;
//				fetch_state <= fetch_active;
//				fetch_rip <= fetch_rip + 8;
//				if (fetch_skip > 0) begin
//					fetch_skip <= fetch_skip - 8;
//				end else begin
//					//$display("Fetch: [%d] %08x %08x", fetch_offset, bus.resp[63:32], bus.resp[31:0]);
//					decode_buffer[fetch_offset*8 +: 64] <= bus.resp;
//					//$display("fill at %d: %x [%x]", fetch_offset, bus.resp, decode_buffer);
//					fetch_offset <= fetch_offset + 8;
//				end
//			end else begin
//				if (fetch_state == fetch_active) begin
//					fetch_state <= fetch_idle;
//				end else if (bus.reqack) begin
//					assert(fetch_state == fetch_idle) else $fatal;
//					fetch_state <= fetch_waiting;
//				end
//			end
//
//		end


endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
