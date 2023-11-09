// 状态寄存器模块
module d_ff # (
	parameter WIDTH = 32
)(
	input logic clk,
	input logic reset_n,
	input logic en,
	input logic [WIDTH-1 : 0] d_ff_d,         
	output logic [WIDTH-1 : 0] d_ff_q
);
	always @(posedge clk or negedge reset_n) begin
		if (!reset_n) begin
			d_ff_q <= {WIDTH{32'b0}};
		end else if (en) begin
			d_ff_q <= d_ff_d;
		end
	end
endmodule


