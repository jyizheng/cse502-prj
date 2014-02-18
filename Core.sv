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
	logic[7:0] opcode;
	logic[1:0] escape;
	logic modrm;
	logic sib;
} opcode_t;

typedef struct packed {
	logic[31:0] value;
	logic[2:0] size;
} disp_t;

typedef struct packed {
	logic[63:0] value;
	logic[3:0] size;
} imme_t;

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
	wire can_decode = (fetch_offset - decode_offset >= 7'd15);

	function logic opcode_inside(logic[7:0] value, low, high);
		opcode_inside = (value >= low && value <= high);
	endfunction

	function logic[2:0] opcode_imme_size(logic[7:0] opcode);
		logic[0:255][2:0] onebyte_has_imme = {
			/*       0    1    2    3    4    5    6    7    8    9    a    b    c    d    e    f        */
			/*       -------------------------------        */
			/* 00 */ 3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0, /* 00 */
			/* 10 */ 3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0, /* 10 */
			/* 20 */ 3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0, /* 20 */
			/* 30 */ 3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0, /* 30 */
			/* 40 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 40 */
			/* 50 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 50 */
			/* 60 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h4,3'h4,3'h1,3'h1,3'h0,3'h0,3'h0,3'h0, /* 60 */
			/* 70 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 70 */
			/* 80 */ 3'h1,3'h4,3'h1,3'h1,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 80 */
			/* 90 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 90 */
			/* a0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* a0 */
			/* b0 */ 3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5, /* b0 */
			/* c0 */ 3'h1,3'h1,3'h2,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h2,3'h0,3'h0,3'h0,3'h1,3'h0,3'h0, /* c0 */
			/* d0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* d0 */
			/* e0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* e0 */
			/* f0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0  /* f0 */
			/*       -------------------------------        */
			/*       0    1    2    3    4    5    6    7    8    9    a    b    c    d    e    f        */
		};
		logic[255:0][2:0] test_array = {
			/*       0    1    2    3    4    5    6    7    8    9    a    b    c    d    e    f        */
			/*       -------------------------------        */
			/* 00 */ 3'h1,3'h2,3'h3,3'h4,3'h5,3'h6,3'h7,3'h6,3'h5,3'h4,3'h3,3'h2,3'h1,3'h4,3'h0,3'h0, /* 00 */
			/* 10 */ 3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0, /* 10 */
			/* 20 */ 3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0, /* 20 */
			/* 30 */ 3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0, /* 30 */
			/* 40 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 40 */
			/* 50 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 50 */
			/* 60 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h4,3'h4,3'h1,3'h1,3'h0,3'h0,3'h0,3'h0, /* 60 */
			/* 70 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 70 */
			/* 80 */ 3'h1,3'h4,3'h1,3'h1,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 80 */
			/* 90 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* 90 */
			/* a0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* a0 */
			/* b0 */ 3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h1,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5,3'h5, /* b0 */
			/* c0 */ 3'h1,3'h1,3'h2,3'h0,3'h0,3'h0,3'h1,3'h4,3'h0,3'h2,3'h0,3'h0,3'h0,3'h1,3'h0,3'h0, /* c0 */
			/* d0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* d0 */
			/* e0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0, /* e0 */
			/* f0 */ 3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0,3'h0  /* f0 */
			/*       -------------------------------        */
			/*       0    1    2    3    4    5    6    7    8    9    a    b    c    d    e    f        */
		};
		const logic[2:0] test_array1[0:3] = '{ 3'h1, 3'h2, 3'h3, 3'h4 };

		for (logic[2:0] i = 0; i < 4; i += 1)
			$display("TEST1 %x %x", i, test_array1[i[1:0]]);

		for (logic[8:0] i = 0; i < 256; i += 1)
			$display("TEST %x %x", i, test_array[i]);

		$display("DEBUG %x:%x", opcode, onebyte_has_imme[opcode]);
		opcode_imme_size = onebyte_has_imme[opcode];
	endfunction

	function logic opcode_has_modrm(logic[7:0] opcode);
		logic[0:255] onebyte_has_modrm = {
			/*       0    1    2    3    4    5    6    7    8    9    a    b    c    d    e    f        */
			/*       -------------------------------        */
			/* 00 */ 1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0, /* 00 */
			/* 10 */ 1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0, /* 10 */
			/* 20 */ 1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0, /* 20 */
			/* 30 */ 1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0, /* 30 */
			/* 40 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* 40 */
			/* 50 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* 50 */
			/* 60 */ 1'b0,1'b0,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,1'b0,1'b1,1'b0,1'b0,1'b0,1'b0, /* 60 */
			/* 70 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* 70 */
			/* 80 */ 1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1, /* 80 */
			/* 90 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* 90 */
			/* a0 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* a0 */
			/* b0 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* b0 */
			/* c0 */ 1'b1,1'b1,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* c0 */
			/* d0 */ 1'b1,1'b1,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1,1'b1, /* d0 */
			/* e0 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0, /* e0 */
			/* f0 */ 1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1,1'b0,1'b0,1'b0,1'b0,1'b0,1'b0,1'b1,1'b1  /* f0 */
			/*       -------------------------------        */
			/*       0    1    2    3    4    5    6    7    8    9    a    b    c    d    e    f        */
		};
		opcode_has_modrm = onebyte_has_modrm[opcode];
	endfunction

	logic[3:0] bytes_decoded_this_cycle;
	always_comb begin
		if (can_decode) begin : decode_block
			rex_t rex = 4'b0000;
			opcode_t opcode = 0;
			modrm_t modrm = 8'h00;
			sib_t sib = 8'h00;
			disp_t disp = 0;
			imme_t imme = 0;

			logic[7:0] next_byte;

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

			/* Opcode */
			$display("next_byte [%x]", next_byte);
			assert(next_byte != 8'h0F)
			else
				$fatal("Escape not supported");
			casez (next_byte)
				/* TODO: two/three bytes opcode */
				/* TODO: unsupported opcode */
				default: begin
					opcode.opcode = next_byte;
					bytes_decoded_this_cycle += 1;
					next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];
					opcode.modrm = opcode_has_modrm(opcode.opcode);
				end
			endcase

			if (error_code != ec_none)
				$finish;

			/* ModR/M */
			if (opcode.modrm == 1) begin
				modrm = next_byte;
				bytes_decoded_this_cycle += 1;
				next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];
			end

			/* SIB */
			if (modrm.mod != 2'b11 && modrm.rm == 3'b100) begin
				opcode.sib = 1'b1;
				sib = next_byte;
				bytes_decoded_this_cycle += 1;
				next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];
			end

			/* Displacement */
			if (modrm.mod == 2'b01)
				disp.size = 1;
			else if (modrm.mod == 2'b10)
				disp.size = 4;
			else if (modrm.mod == 2'b00 && modrm.rm == 3'b101)
				disp.size = 4;

			for (logic[2:0] i = 0; i < disp.size; i += 1) begin
				disp.value[{2'b00,i}*8 +: 8] = next_byte;
				bytes_decoded_this_cycle += 1;
				next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];
			end

			/* Immediate */
			imme.size[2:0] = opcode_imme_size(opcode.opcode);
			if (imme.size == 5) begin
				imme.size = (rex.W == 1) ? 8 : 4;
			end

			for (logic[3:0] i = 0; i < imme.size; i += 1) begin
				imme.value[{2'b00,i}*8 +: 8] = next_byte;
				bytes_decoded_this_cycle += 1;
				next_byte = decode_bytes[{3'b000, bytes_decoded_this_cycle} * 8 +: 8];
			end

			$display("Length: %d", bytes_decoded_this_cycle);
			$display("REX: %x[%b]", rex, rex);
			$display("Opcode: %x[%b]", opcode, opcode);
			$display("ModRM: %x[%b]", modrm, modrm);
			$display("SIB: %x[%b]", sib, sib);
			$display("DISP: %x[%b]", disp, disp);
			$display("IMME: %x[%b]", imme, imme);

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
