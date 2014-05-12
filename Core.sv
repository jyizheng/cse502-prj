`include "global.svh"
`include "gpr.svh"
`include "instruction.svh"
`include "operand.svh"
`include "micro_op.svh"

//`define CORE_DEBUG 1

module Core (
	input[63:0] entry
,	/* verilator lint_off UNDRIVEN */ /* verilator lint_off UNUSED */ Sysbus bus /* verilator lint_on UNUSED */ /* verilator lint_on UNDRIVEN */
);
	import "DPI-C" function longint syscall_cse502(input longint rax, input longint rdi, input longint rsi, input longint rdx, input longint r10, input longint r8, input longint r9);


	/* XXX: verilator bug work around for passing bus.clk */
	logic clk;

	assign clk = bus.clk;

	function logic mtrr_is_mmio(logic[63:0] physaddr);
		mtrr_is_mmio = ((physaddr > 640*1024 && physaddr < 1024*1024));
	endfunction

	function logic opcode_inside(logic[7:0] value, low, high);
		opcode_inside = (value >= low && value <= high);
	endfunction

	/* Data defines */
	logic[63:0] regs[`GLB_REG_NUM:0];
	logic[32:0] reg_occupies;
	logic[63:0] rflags;

	/* Data initialization */
	always_ff @ (posedge bus.clk) begin
		if (bus.reset) begin
			for (int i = 0; i < `GLB_REG_NUM; i += 1)
				regs[i] <= 0;

			reg_occupies <= 0;

			/* initialize RSP to 0x7C00 */
			regs[`GPR_RSP] <= 64'h7C00;
		end
	end

	/* +++++++++++++++++++++++++++++++++++++++++++++++++++++++++ */
	/* Memory arbiter and cache */
	logic irequest;
	logic ireqack;
	logic[63:0] iaddr;
	logic[64*8-1:0] idata;
	logic idone;
	logic drequest;
	logic dreqack;
	logic dwrenable;
	logic[63:0] daddr;
	logic[64*8-1:0] drdata;
	logic[64*8-1:0] dwdata;
	logic ddone;

	Arbiter arbiter(bus,
		irequest, ireqack, iaddr, idata, idone,
		drequest, dreqack, dwrenable, daddr, drdata, dwdata, ddone);

	logic icache_enable;
	logic[63:0] icache_addr;
	logic[511:0] icache_rdata;
	logic icache_done;
	ICache icache(clk, icache_enable, icache_addr, icache_rdata, icache_done,
		irequest, ireqack, iaddr, idata, idone);

	logic dcache_enable;
	logic dcache_wenable;
	logic[63:0] dcache_addr;
	logic[63:0] dcache_rdata;
	logic[63:0] dcache_wdata;
	logic dcache_done;
	DCache dcache(clk,
		dcache_enable, dcache_wenable, dcache_addr, dcache_rdata, dcache_wdata, dcache_done,
		drequest, dreqack, dwrenable, daddr, drdata, dwdata, ddone);

	/* --------------------------------------------------------- */
	/* Instruction-Fetch stage */
	logic if_dc;
	logic dc_if;
	logic[0:15*8-1] decode_bytes;
	logic[63:0] decode_rip;
	logic[7:0] bytes_decoded;
	logic if_set_rip;
	logic[63:0] if_new_rip;
	INF inf(clk, if_set_rip, if_new_rip, icache_enable, icache_addr, icache_rdata, icache_done,
		decode_bytes, decode_rip, bytes_decoded, if_dc, dc_if);

	always_comb begin
		if (bus.reset) begin
			if_set_rip = 1;
			if_new_rip = entry;
		end else if (wb_branch) begin
			if_set_rip = 1;
			if_new_rip = wb_rip;
		end else if (exe_branch) begin
			if_set_rip = 1;
			if_new_rip = exe_rip;
		end else begin
			if_set_rip = 0;
			if_new_rip = 0;
		end
	end

	/* --------------------------------------------------------- */
	/* Decode stage */
	logic dc_taken = 0;
	logic dc_df = 0;
	logic dc_resume = 0;
	micro_op_t dc_uop;
	Decoder decoder(clk, if_dc, dc_resume, dc_if, decode_rip, decode_bytes, dc_taken,
		bytes_decoded, dc_uop, dc_df);

	always_ff @ (posedge bus.clk) begin
		if (wb_branch) begin
			dc_resume <= 1;
		end else if (exe_branch) begin
			dc_resume <= 1;
		end else
			dc_resume <= 0;
	end

	/* --------------------------------------------------------- */
	/* Data Fetch & Schedule stage */
	logic df_taken;
	assign dc_taken = df_taken;
	micro_op_t df_uop;
	micro_op_t df_uop_tmp;
	logic df_exe;
	logic mem_blocked;

	/* check register conflict */
	function logic df_reg_conflict(micro_op_t uop);
		if (uop.oprd1.t == `OPRD_T_REG || uop.oprd1.t == `OPRD_T_STACK)
			if (reg_occupies[uop.oprd1.r] != 0)
				return 1;

		if (uop.oprd2.t == `OPRD_T_REG || uop.oprd2.t == `OPRD_T_STACK)
			if (reg_occupies[uop.oprd2.r] != 0)
				return 1;

		if (uop.oprd3.t == `OPRD_T_REG)
			if (reg_occupies[uop.oprd3.r] != 0)
				return 1;

		return 0;
	endfunction

	/* This can only be called from alwasy_ff */
	function logic df_set_reg_conflict(oprd_t oprd);
		/* FIXME: here we assume oprd1 is the target, need to handle multi-target condition */
		if (oprd.t == `OPRD_T_REG || oprd.t == `OPRD_T_STACK)
			reg_occupies[oprd.r] <= 1;

		return 0;
	endfunction

	always_comb begin
		df_taken = 0;
		if (dc_df == 1 && !df_reg_conflict(dc_uop) && !mem_blocked) begin
			df_taken = 1;
			df_uop_tmp = dc_uop;

			/* Retrieve register values
			* TODO: might need special treatment for special registers */
			if (df_uop_tmp.oprd1.t == `OPRD_T_REG ||
				df_uop_tmp.oprd1.t == `OPRD_T_STACK) begin
				df_uop_tmp.oprd1.value = regs[df_uop_tmp.oprd1.r];
			end

			if (df_uop_tmp.oprd2.t == `OPRD_T_REG ||
				df_uop_tmp.oprd2.t == `OPRD_T_STACK) begin
				df_uop_tmp.oprd2.value = regs[df_uop_tmp.oprd2.r];
			end

			/* FIXME: need oprd3? */
			if (df_uop_tmp.oprd3.t == `OPRD_T_REG) begin
				df_uop_tmp.oprd3.value = regs[df_uop_tmp.oprd3.r];
			end
		end
	end

	always_ff @ (posedge bus.clk) begin
		if (dc_df == 1 && df_taken == 1 && !mem_blocked) begin
			/* we need to set occupation table in always_ff */
			df_set_reg_conflict(df_uop_tmp.oprd1);

			if (df_uop_tmp.oprd2.t == `OPRD_T_STACK)
				df_set_reg_conflict(df_uop_tmp.oprd2);

			df_uop <= df_uop_tmp;
			df_exe <= 1;
		end
		else begin
			df_uop <= 0;
			df_exe <= 0;
		end
	end

	/* --------------------------------------------------------- */
	/* EXE stage */
	logic exe_mem;
	logic[127:0] exe_result;
	logic[63:0] exe_rflags;
	micro_op_t exe_uop;

	logic exe_branch;
	logic exe_rip;

	ALU alu(clk, df_exe,
		df_uop.opcode, df_uop.oprd1.value, df_uop.oprd2.value, df_uop.oprd3.value, df_uop.next_rip,
		exe_result, exe_rflags, exe_mem, mem_blocked, exe_branch, exe_rip);

	always_ff @ (posedge bus.clk) begin
		if (df_exe && !mem_blocked) begin
			exe_uop <= df_uop;
`ifdef CORE_DEBUG
			$display("[CORE] REG1 = %d REG2 = %d", df_uop.oprd1.r, df_uop.oprd2.r);
`endif
		end else if (mem_blocked) begin
			/* Keep the previous value */
		end else begin
			exe_uop <= 0;
		end
	end

	/* --------------------------------------------------------- */
	/* MEM stage */
	logic mem_wb;
	logic[127:0] mem_result;
	logic[63:0] mem_rflags;
	micro_op_t mem_uop;

	Mem mem(clk, exe_mem, mem_blocked, mem_wb,
		exe_uop, exe_result, mem_result,
		dcache_enable, dcache_wenable, dcache_addr, dcache_rdata, dcache_wdata, dcache_done);

	always_ff @ (posedge bus.clk) begin
		if (exe_mem && !mem_blocked) begin
			mem_uop <= exe_uop;
			mem_rflags <= exe_rflags;
		end else if (mem_blocked) begin
			/* Keep the previous value */
		end else begin
			mem_uop <= 0;
			mem_rflags <= 0;
		end
	end

	/* --------------------------------------------------------- */
	/* WB stage */
	logic[63:0] wb_result;
	logic[63:0] wb_rflags;
	logic[4:0] reg_num;
	logic wb_branch;
	logic[63:0] wb_rip;

	always_ff @ (posedge bus.clk) begin
		if (mem_wb == 1) begin
			/* Special operations */
			if (mem_uop.opcode == 10'b01_0000_0101) begin
				/*  syscall */
				regs[`GPR_RAX] <= syscall_cse502(regs[`GPR_RAX], regs[`GPR_RDI],
					regs[`GPR_RSI], regs[`GPR_RDX], regs[`GPR_R10],
					regs[`GPR_R8], regs[`GPR_R9]);
			end

			/* Clear target reg occupation */
			if (mem_uop.oprd1.t == `OPRD_T_REG) begin
				regs[mem_uop.oprd1.r] <= mem_result[63:0];
				reg_occupies[mem_uop.oprd1.r] <= 0;
				reg_num <= mem_uop.oprd1.r;
			end else if (mem_uop.oprd1.t == `OPRD_T_STACK) begin
				regs[mem_uop.oprd1.r] <= regs[mem_uop.oprd1.r] - 8;
				reg_occupies[mem_uop.oprd1.r] <= 0;
			end else if (mem_uop.oprd2.t == `OPRD_T_STACK) begin
				regs[mem_uop.oprd2.r] <= regs[mem_uop.oprd2.r] + 8;
				reg_occupies[mem_uop.oprd1.r] <= 0;
			end

			/* Deal with call/ret */
			if (mem_uop.opcode == 10'b11_0001_0000) begin
				/* Call %reg */
				wb_branch <= 1;
				wb_rip <= mem_uop.oprd2.value;
			end else if (mem_uop.opcode == 10'b00_1100_0011) begin
				/* ret */
				wb_branch <= 1;
				wb_rip <= mem_result[63:0];
			end else if (mem_uop.opcode == 10'b01_0000_0101) begin
				/* syscall */
				wb_branch <= 1;
				wb_rip <= mem_uop.next_rip;
			end else begin
				wb_branch <= 0;
				wb_rip <= 0;
			end

`ifdef CORE_DEBUG
			$display("RAX = %x", regs[`GPR_RAX]);
			$display("RBX = %x", regs[`GPR_RBX]);
			$display("RCX = %x", regs[`GPR_RCX]);
			$display("RDX = %x", regs[`GPR_RDX]);
			$display("RSI = %x", regs[`GPR_RSI]);
			$display("RDI = %x", regs[`GPR_RDI]);
			$display("RBP = %x", regs[`GPR_RBP]);
			$display("RSP = %x", regs[`GPR_RSP]);
			$display("R8  = %x", regs[`GPR_R8]);
			$display("R9  = %x", regs[`GPR_R9]);
			$display("R10 = %x", regs[`GPR_R10]);
			$display("R11 = %x", regs[`GPR_R11]);
			$display("R12 = %x", regs[`GPR_R12]);
			$display("R13 = %x", regs[`GPR_R13]);
			$display("R14 = %x", regs[`GPR_R14]);
			$display("R15 = %x", regs[`GPR_R15]);
`endif

		end else begin
			wb_branch <= 0;
			wb_rip <= 0;
		end
	end

	always_comb begin
		if (if_dc) begin : decode_block
			// cse502 : following is an example of how to finish the simulation
			//if (decode_bytes == 0 && fetch_state == fetch_idle) $finish;
		end
	end

	//cse502 : Use the following as a guide to print the Register File contents.
	final begin
		$display("RFLAGS = %x", rflags);
		$display("RAX = %x", regs[`GPR_RAX]);
		$display("RBX = %x", regs[`GPR_RBX]);
		$display("RCX = %x", regs[`GPR_RCX]);
		$display("RDX = %x", regs[`GPR_RDX]);
		$display("RSI = %x", regs[`GPR_RSI]);
		$display("RDI = %x", regs[`GPR_RDI]);
		$display("RBP = %x", regs[`GPR_RBP]);
		$display("RSP = %x", regs[`GPR_RSP]);
		$display("R8  = %x", regs[`GPR_R8]);
		$display("R9  = %x", regs[`GPR_R9]);
		$display("R10 = %x", regs[`GPR_R10]);
		$display("R11 = %x", regs[`GPR_R11]);
		$display("R12 = %x", regs[`GPR_R12]);
		$display("R13 = %x", regs[`GPR_R13]);
		$display("R14 = %x", regs[`GPR_R14]);
		$display("R15 = %x", regs[`GPR_R15]);
	end
endmodule

/* vim: set ts=4 sw=0 tw=0 noet : */
