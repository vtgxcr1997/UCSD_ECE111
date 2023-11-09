module byte_rotation(input logic clk, reset_n, start,
                     input logic [15:0] message_addr, size, output_addr,
                    output logic done, mem_clk, mem_we,
                    output logic [15:0] mem_addr,
                    output logic [31:0] mem_write_data,
                     input logic [31:0] mem_read_data);
							
	function logic [31:0] byte_rotate(input logic [31:0] value); 
		byte_rotate = {value[23:16], value[15:8], value[7:0], value[31:24]}; 
	endfunction			
	
	assign mem_clk = clk;
	
	localparam READ_IDLE   = 4'b0000;
	localparam READ_S1     = 4'b0001;
	localparam READ_S2     = 4'b0010;
	localparam READ_S3     = 4'b0011;
	localparam READ_S4     = 4'b0100;
	localparam READ_OUTPUT = 4'b0101;
	localparam READ_DONE   = 4'b0110;

	// 定义状态寄存器read_state，端口，端口连接。	
	logic [3:0] read_state_d, read_state_q;
	logic read_state_en;
	assign read_state_en = 1;
	d_ff #(4) read_state (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(read_state_en), 
		.d_ff_d(read_state_d),
		.d_ff_q(read_state_q)
	);
	
	// 定义读数据计数器寄存器rdc，端口，端口连接。
	logic [15:0] rdc_d, rdc_q; // 读数据计数器寄存器rdc,定义端口信号。
	logic rdc_en;
	assign rdc_d = rdc_q + 1;
	assign rdc_en = ((read_state_q == READ_S1) || (read_state_q == READ_S2)) ? 1 : 0;
	d_ff #(16) rdc (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(rdc_en), 
		.d_ff_d(rdc_d), 
		.d_ff_q(rdc_q)
	);

	// 定义写数据计数器寄存器wtc，端口，端口连接。
	logic [15:0] wtc_d, wtc_q; // 写数据计数器寄存器wtc,定义端口信号。
	logic wtc_en; // 定义使能信号。
	assign wtc_d = wtc_q + 1;
	assign wtc_en = ((read_state_q == READ_S3) || (read_state_q == READ_S4)) ? 1 : 0;
	d_ff #(16) wtc (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(wtc_en), 
		.d_ff_d(wtc_d), 
		.d_ff_q(wtc_q)
	);

	// 定义输出数据计数器寄存器otc，端口，端口连接，我们将数据一次性输出。
	logic [15:0] otc_d, otc_q; // 写输出计数器寄存器otc,定义端口信号。
	logic otc_en; // 定义使能信号。
	assign otc_d = otc_q + 1;
	assign otc_en = (read_state_q == (READ_OUTPUT)) ? 1 : 0;
	d_ff #(16) otc (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(otc_en), 
		.d_ff_d(otc_d), 
		.d_ff_q(otc_q)
	);

	// 定义mem_read_data数据寄存器，端口，端口连接。	
	logic [511:0] message_d, message_q; // message寄存器暂时存储所有读入数据,定义端口信号。	
	logic message_en; // 定义使能信号。
    // 部分更新 message_d
    always_comb begin
        message_d = message_q;  // 默认情况下，保持数据不变
        message_d[wtc_q*32 +: 32] = mem_read_data;  // 更新特定的32位块
    end
	assign message_en = ((read_state_q == READ_S3)||(read_state_q == READ_S4)) ? 1 : 0;
	d_ff #(512) message (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(message_en), 
		.d_ff_d(message_d), 
		.d_ff_q(message_q)
	);					

	// 定义地址寄存器maddr，端口，端口连接，我们地址及时更新。
	logic [15:0] maddr_d; // 地址寄存器maddr,定义端口信号。
	assign maddr_d = (read_state_q == READ_OUTPUT) ? output_addr + otc_q : message_addr + rdc_q;
	assign maddr_en = ((read_state_q == READ_S1)||(read_state_q == READ_S2)||(read_state_q == READ_OUTPUT)) ? 1 : 0;
	d_ff #(16) maddr (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(maddr_en), 
		.d_ff_d(maddr_d), 
		.d_ff_q(mem_addr)
	);	

	// 定义mem_write_data输出数据寄存器，端口，端口连接。output_addr是0010。
	logic [31:0] ot_data_d, ot_data_q;
	logic ot_data_en; // 定义使能信号。
	assign ot_data_d = message_q[otc_q*32 +: 32];  // 更新特定的32位块
	assign ot_data_en = (read_state_q == READ_OUTPUT) ? 1 : 0;
	d_ff #(32) ot_data (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(ot_data_en), 
		.d_ff_d(ot_data_d), 
		.d_ff_q(ot_data_q)
	);				
	assign mem_write_data = byte_rotate(ot_data_q);

	// 其他信号设置。
	assign mem_we = (read_state_q == READ_OUTPUT) ? 1 : 0;
	assign done = (read_state_q == READ_DONE) ? 1 : 0;
	
	always_comb begin
		case (read_state_q) // 用当前状态（寄存器的保存值）决定应该做什么。
			READ_IDLE: begin
			read_state_d = (start == 1) ? READ_S1 :READ_IDLE;
			end
		
			READ_S1: begin // 读一。
			read_state_d = READ_S2;
			end
		
			READ_S2: begin // 读二
			read_state_d = READ_S3;
			end
		
			READ_S3: begin // 写一。
			read_state_d = ((wtc_q + 1) < size) ? READ_S4:READ_OUTPUT;
			end
		
			READ_S4: begin // 写二。
			read_state_d = ((wtc_q + 1) < size) ? READ_S1:READ_OUTPUT;
			end
			
			READ_OUTPUT: begin // 输出。
			read_state_d = (otc_q < size) ? READ_OUTPUT:READ_DONE;
			end
		
			READ_DONE: begin // 一次性输出所有数据。
			// 当当前状态为READ_DONE，地址d端和数据d端才会就绪。下个上升沿，输出q端才会正式变化。
			read_state_d = READ_DONE;
			end
			
			default: begin
			read_state_d = READ_IDLE;
			end
		endcase
	end

	always_ff @(posedge clk) begin
		if (read_state_q !== READ_OUTPUT) begin
			$display("state_q %01d, state_d %01d", read_state_q, read_state_d);
			$display("rdc_q %02d, rdc_d %02d", rdc_q, rdc_d);
			$display("wtc_q %02d, wtc_d %02d", wtc_q, wtc_d);
			$display("addr %08h, get data %08h, wt data %08h", mem_addr, mem_read_data, message_q);
			$display("--------------------------");
		end else if (read_state_q == READ_OUTPUT) begin
			$display("maddr_q %08h, maddr_d %08h", mem_addr, maddr_d );
			$display("otc_q %02d, ot_data_q %08h, ot_data_d %08h", otc_q, mem_write_data, ot_data_d);
			$display("--------------------------");
		end
	end

endmodule