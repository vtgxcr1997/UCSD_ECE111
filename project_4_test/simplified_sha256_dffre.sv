// 触发器模块
module dffre # (
	parameter WIDTH = 32
)(
	input logic clk,
	input logic reset_n,
	input logic en,
	input logic [WIDTH-1 : 0] d,         
	output logic [WIDTH-1 : 0] q
);
	always @(posedge clk or negedge reset_n) begin
		if (!reset_n) begin
			q <= {WIDTH{32'b0}};
		end else if (en) begin
			q <= d;
		end
	end
endmodule


