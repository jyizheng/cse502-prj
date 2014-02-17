/* Typedefs */
typedef struct packed {
	logic B;
	logic X;
	logic R;
	logic W;
} rex_t;

typedef struct packed {
	logic[1:0] mod;
	logic[2:0] reg_op;
	logic[2:0] rm;
} modrm_t;

typedef struct packed {
	logic [1:0] scale;
	logic[2:0] index;
	logic[2:0] base;
} sib_t;

typedef struct packed {
	logic escape1;
	logic escape2;
	logic[7:0] opcode;
	logic modrm;
} opcode_t;

module Core (
	input[63:0] entry
,	/* verilator lint_off UNDRIVEN */ /* verilator lint_off UNUSED */ Sysbus bus /* verilator lint_on UNUSED */ /* verilator lint_on UNDRIVEN */
);
	enum { fetch_idle, fetch_waiting, fetch_active } fetch_state;
	enum { ec_none, ec_invalid_op, ec_rex } error_code;
	logic[63:0] fetch_rip;
	logic[0:2*64*8-1] decode_buffer; // NOTE: buffer bits are left-to-right in increasing order
	logic[5:0] fetch_skip;
	logic[6:0] fetch_offset, decode_offset;

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
			send_fetch_req = (fetch_offset - decode_offset < 32);
		end
	end

	assign bus.respack = bus.respcyc; // always able to accept response

	always @ (posedge bus.clk)
		if (bus.reset) begin

			fetch_state <= fetch_idle;
			fetch_rip <= entry & ~63;
			fetch_skip <= entry[5:0];
			fetch_offset <= 0;

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
					$display("Fetch: [%d] %08x %08x", fetch_offset, bus.resp[63:32], bus.resp[31:0]);
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
	wire can_decode = (fetch_offset - decode_offset >= 15);

	function logic opcode_inside(logic[7:0] value, low, high);
		opcode_inside = (value >= low && value <= high);
	endfunction

	logic[3:0] bytes_decoded_this_cycle;
	always_comb begin
		if (can_decode) begin : decode_block
			rex_t rex = 4'b0000;
			modrm_t modrm = 8'h00;
			sib_t sib = 8'h00;
			opcode_t opcode = 0;
			logic[7:0] next_byte;

			//logic[255:0][1:0] opcodes;
			// cse502 : Decoder here
			// remove the following line. It is only here to allow successful compilation in the absence of your code.
			bytes_decoded_this_cycle = 0;
			error_code = ec_none;

			$display("decode_bytes [%x]", decode_bytes);
			/* Prefix */
			while (1) begin
				logic stage_finished = 0;
				next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];
				$display("next_byte [%x]", next_byte);
				casez (next_byte)
					8'h4?: rex = next_byte[3:0];
					default: stage_finished = 1;
				endcase

				if (stage_finished == 1)
					break;
				bytes_decoded_this_cycle += 1;
			end
			$display("REX: %x", rex);

			/* Opcode */
			assert(next_byte != 8'h0F)
			else
				$fatal("Escape not supported");
			casez (next_byte)
				8'h31:
					bytes_decoded_this_cycle += 1;
				default:
					error_code = ec_invalid_op;
			endcase

			if (error_code != ec_none)
				$finish;

			/* ModR/M / SIB */
			
			$display("Opcode: %x[%b]", opcode, opcode);
			$display("ModRM: %x[%b]", modrm, modrm);
			$display("SIB: %x[%b]", sib, sib);

			// cse502 : following is an example of how to finish the simulation
			if (decode_bytes == 0 && fetch_state == fetch_idle) $finish;
		end else begin
			bytes_decoded_this_cycle = 0;
		end
	end

	always @ (posedge bus.clk)
		if (bus.reset) begin

			decode_offset <= 0;
			decode_buffer <= 0;

		end else begin // !bus.reset

			decode_offset <= decode_offset + { 3'b0, bytes_decoded_this_cycle };

		end

endmodule
