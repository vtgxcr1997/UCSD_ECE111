module SystemVerilog1(input logic clk, reset_n, start,
                     input logic [15:0] message_addr, size, output_addr,
                    output logic done, mem_clk, mem_we,
                    output logic [15:0] mem_addr,
                    output logic [31:0] mem_write_data,
                     input logic [31:0] mem_read_data);
logic [31:0] array_d[15:0];
logic [31:0] array_q[15:0];
logic [511:0] data_d;
logic [511:0] data_q;
logic [31:0] data_add;
logic en;
d_ff #(512) d_ff_wt (
	.clk(clk),
	.reset_n(reset_n),
	.en(en),
	.d_ff_d({<<{array_d}}),
	.d_ff_q({<<{array_q}}) // 内部使用数据形式传递。
	);
endmodule


