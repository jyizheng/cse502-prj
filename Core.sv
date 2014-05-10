`include "global.svh"
`include "gpr.svh"
`include "instruction.svh"
`include "operand.svh"
`include "micro_op.svh"

`define CORE_DEBUG 1

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

	/* Data initialization */
	initial begin
		for (int i = 0; i < `GLB_REG_NUM; i += 1)
			regs[i] = 0;
		reg_occupies = 0;
	end

	/* +++++++++++++++++++++++++++++++++++++++++++++++++++++++++ */
	/* Memory arbiter and cache */
	logic irequest;
	logic[63:0] iaddr;
	logic[64*8-1:0] idata;
	logic idone;
	logic drequest;
	logic dwrenable;
	logic[63:0] daddr;
	logic[64*8-1:0] drdata;
	logic[64*8-1:0] dwdata;
	logic ddone;

	Arbiter arbiter(bus,
		irequest, iaddr, idata, idone,
		drequest, dwrenable, daddr, drdata, dwdata, ddone);

	logic icache_enable;
	logic[63:0] icache_addr;
	logic[511:0] icache_rdata;
	logic icache_done;
	ICache icache(clk, icache_enable, icache_addr, icache_rdata, icache_done,
		irequest, iaddr, idata, idone);

	logic dcache_enable;
	logic dcache_wenable;
	logic[63:0] dcache_addr;
	logic[63:0] dcache_rdata;
	logic[63:0] dcache_wdata;
	logic dcache_done;
	DCache dcache(clk,
		dcache_enable, dcache_wenable, dcache_addr, dcache_rdata, dcache_wdata, dcache_done,
		drequest, dwrenable, daddr, drdata, dwdata, ddone);

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

	always_ff @ (posedge bus.clk) begin
		if (bus.reset) begin
			if_set_rip <= 1;
			if_new_rip <= entry;
		end else if (if_set_rip == 1) begin
			if_set_rip <= 0;
			if_new_rip <= 0;
		end
	end

	/* --------------------------------------------------------- */
	/* Decode stage */
	logic dc_taken = 0;
	logic dc_df = 0;
	micro_op_t dc_uop;
	Decoder decoder(clk, if_dc, decode_rip, decode_bytes, dc_taken,
		bytes_decoded, dc_uop, dc_df);

	/* --------------------------------------------------------- */
	/* Data Fetch & Schedule stage */
	logic df_taken;
	assign dc_taken = df_taken;
	micro_op_t df_uop;
	micro_op_t df_uop_tmp;
	logic df_exe;

	/* check register conflict */
	function logic df_reg_conflict(micro_op_t uop);
		if (uop.oprd1.t == `OPRD_T_REG)
			if (reg_occupies[uop.oprd1.r] != 0)
				return 1;

		if (uop.oprd2.t == `OPRD_T_REG)
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
		if (oprd.t == `OPRD_T_REG)
			reg_occupies[oprd.r] <= 1;
		return 0;
	endfunction

	always_comb begin
		df_taken = 0;
		if (dc_df == 1 && !df_reg_conflict(dc_uop)) begin
			df_taken = 1;
			df_uop_tmp = dc_uop;

			/* Retrieve register values
			* TODO: might need special treatment for special registers */
			if (df_uop_tmp.oprd1.t == `OPRD_T_REG) begin
				df_uop_tmp.oprd1.value = regs[df_uop_tmp.oprd1.r];
			end

			if (df_uop_tmp.oprd2.t == `OPRD_T_REG) begin
				df_uop_tmp.oprd2.value = regs[df_uop_tmp.oprd2.r];
			end

			/* FIXME: need oprd3? */
			if (df_uop_tmp.oprd3.t == `OPRD_T_REG) begin
				df_uop_tmp.oprd3.value = regs[df_uop_tmp.oprd3.r];
			end
		end
	end

	always_ff @ (posedge bus.clk) begin
		if (dc_df == 1 && df_taken == 1) begin
			/* we need to set occupation table in always_ff */
			df_set_reg_conflict(df_uop_tmp.oprd1);
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
	logic[63:0] exe_flags;
	logic[63:0] exe_flags_tmp;
	micro_op_t exe_uop;

	ALU alu(clk, df_exe,
		df_uop.opcode, df_uop.oprd1.value, df_uop.oprd2.value, df_uop.oprd3.value,
		exe_result, exe_flags_tmp, exe_mem);

	always_ff @ (posedge bus.clk) begin
		if (df_exe == 1) begin
			exe_uop <= df_uop;
`ifdef CORE_DEBUG
			$display("[CORE] REG1 = %d REG2 = %d", df_uop.oprd1.r, df_uop.oprd2.r);
`endif
		end
		else begin
			exe_uop <= 0;
		end
	end

	/* --------------------------------------------------------- */
	/* MEM stage */
	logic mem_wb;
	logic[127:0] mem_result;
	logic[63:0] mem_flags;
	micro_op_t mem_uop;

	Mem mem(clk, exe_mem,
		exe_uop.oprd1, exe_result, mem_result,
		dcache_enable, dcache_wenable, dcache_addr, dcache_rdata, dcache_wdata, dcache_done);

	always_ff @ (posedge bus.clk) begin
		if (exe_mem == 1) begin
			mem_wb <= 1;
			mem_uop <= exe_uop;
			mem_flags <= exe_flags;
		end
		else begin
			mem_wb <= 0;
			mem_uop <= 0;
			mem_flags <= 0;
		end
	end

	/* --------------------------------------------------------- */
	/* WB stage */
	logic[127:0] wb_result;
	logic[63:0] wb_flags;
	micro_op_t wb_uop;
	logic[4:0] reg_num;

	always_ff @ (posedge bus.clk) begin
		if (mem_wb == 1) begin
			if (mem_uop.oprd1.t == `OPRD_T_REG) begin
				regs[mem_uop.oprd1.r] <= mem_result[63:0];
				reg_occupies[mem_uop.oprd1.r] <= 0;
				reg_num <= mem_uop.oprd1.r;
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
