module simplified_sha256 (input logic clk, reset_n, start,
								input logic [15:0] message_addr, output_addr,
								output logic done, mem_clk, mem_we,
								output logic [15:0] mem_addr,
								output logic [31:0] mem_write_data,
								input logic [31:0] mem_read_data);
	
/*
------------------------------------------------------------
时钟模块
------------------------------------------------------------
*/				
				
	assign mem_clk = clk;

/*
------------------------------------------------------------
状态机模块
------------------------------------------------------------
*/

	localparam IDLE = 4'b0000;
	localparam READ = 4'b0001;
	localparam PAD = 4'b0010;
	localparam COMPUTE = 4'b0011;
	localparam RST_COMP = 4'b0100;
	localparam OUTPUT = 4'b0101;
	localparam DONE = 4'b0110;
	
	// 定义状态寄存器state控制状态变换。	
	logic [3:0] state_d, state_q;
	logic state_en; // 使能信号，一直为1。
	assign state_en = 1;
	dffre #(4) state (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(state_en), 
		.d(state_d),
		.q(state_q)
	);
	
/*
------------------------------------------------------------
1. 读数据模块
------------------------------------------------------------
*/

	// 定义READ模块读数据计数器寄存器rdc，用于输出的内存地址计数。
	logic [15:0] rdc_d, rdc_q;
	logic rdc_en;
	assign rdc_d = rdc_q + 1;
	assign rdc_en = (state_q == READ) ? 1 : 0;
	dffre #(16) rdc (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(rdc_en), 
		.d(rdc_d), 
		.q(rdc_q)
	);
	
	// 定义READ模块地址寄存器rd_addr，用于输出连续的内存地址。
	logic [15:0] addr_d;
	logic [15:0] addr_q;
	assign addr_d = (state_q == READ) ? message_addr + rdc_q : 0;
	assign addr_en = (state_q == READ) ? 1 : 0;
	dffre #(16) rd_addr (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(addr_en), 
		.d(addr_d), 
		.q(addr_q) // 内存地址接口
	);	

	// 定义READ模块写数据计数器寄存器wtc，用于接收信号写入message时的计数。
	logic [15:0] wrtc_d, wrtc_q;
	logic wrtc_en; // 定义使能信号。
	assign wrtc_d = wrtc_q + 1;
	assign wrtc_en = ((state_q == READ) && (rdc_q > 1)) ? 1 : 0; // 慢一拍接受数据。
	dffre #(16) wrtc (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(wrtc_en), 
		.d(wrtc_d), 
		.q(wrtc_q)
	);	
	
	// 定义READ模块接收数据寄存器message_en，将数据写到message_en里面。	
	logic [639:0] message_d, message_q;	
	logic message_en; 
    // 部分更新 msg_d
    always_comb begin
        message_d = message_q;  // 默认情况下，保持数据不变
        message_d[wrtc_q*32 +: 32] = mem_read_data;  // 更新特定的32位块
    end
	assign message_en = (state_q == READ) ? 1 : 0;
	dffre #(640) message (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(message_en), 
		.d(message_d), 
		.q(message_q)
	);			

/*
------------------------------------------------------------
2. 扩展数据模块
------------------------------------------------------------
*/

	logic [511:0] block1;
	logic [511:0] block2;
	
	always_comb begin
		for (int i = 0; i < 16; i = i + 1) begin
			block1[i*32+:32] = message_q[i*32+:32]; // message = 0, 1, 2,..., 15
		end
		for (int i = 0; i < 4; i = i + 1) begin
			block2[i*32+:32] = message_q[(i+16)*32+:32]; // message = 16, 17, 18, 19
		end
		block2[4*32+:32] = 32'h80000000;
		for (int i = 5; i < 15; i = i + 1) begin
			block2[i*32+:32] = 0;
		end
		block2[15*32+:32] = 32'd640;
	end	

/*
------------------------------------------------------------
3. 计算模块
------------------------------------------------------------
*/	
	parameter H0_ori = 32'h6a09e667; // A
	parameter H1_ori = 32'hbb67ae85; // B
	parameter H2_ori = 32'h3c6ef372; // C
	parameter H3_ori = 32'ha54ff53a; // D
	parameter H4_ori = 32'h510e527f; // E
	parameter H5_ori = 32'h9b05688c; // F
	parameter H6_ori = 32'h1f83d9ab; // G
	parameter H7_ori = 32'h5be0cd19; // H
	
	
	logic start_comp;
	logic done_comp;
	logic [511:0] block_comp;
	logic [255:0] H0_H7_0;
	logic [255:0] H0_H7_q;
	
	// 定义输出接收寄存器，将输出数据保存到H0_H7_t里面。	
	logic [255:0] H0_H7_t_d;	
	logic H0_H7_t_en; 	
	
	// 定义数据处理计数器寄存器cal_c，用于计数处理了多少次。
	logic [15:0] comp_c_d, comp_c_q;
	logic comp_c_en;	
	
	// 定义计算模块输入。
	assign start_comp = (state_q == COMPUTE) ? 1 : 0;
	assign block_comp = (comp_c_q == 0) ? block1 : block2;
	assign H0_H7_0 = (comp_c_q == 0) ? {H7_ori,H6_ori,H5_ori,H4_ori,H3_ori,H2_ori,H1_ori,H0_ori} : H0_H7_q;
	/*
	1. 输入start给1，子状态机进入COMPUTE状态，开始计算。
	2. t_q超过65，子状态机进入DONE状态，产生输出并且done给1。
	3. 输入start给0，子状态机进入IDLE状态，done和t_q和输出归零。
	*/
	simplified_sha256_H0H7cal H0H7_cal ( 
													.clk(clk), 
													.reset_n(reset_n),
													.start(start_comp),
													.block(block_comp),
													.H0_H7_0(H0_H7_0), // 原初H0_H7。
													.done(done_comp),
													.H0_H7_q(H0_H7_t_d) // 经过计算以后需要输出的H0_H7。
													);			
	
	//---------------------------------------------------------------------	
	
	// 定义输出接收寄存器，将输出数据保存到H0_H7_t里面。
	// 当计算完成后，done_comp拉高。
	assign H0_H7_t_en = (done_comp == 1) ? 1 : 0;
	dffre #(256) H0_H7_t (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(H0_H7_t_en), 
		.d(H0_H7_t_d), 
		.q(H0_H7_q)
	);	

/*
------------------------------------------------------------
4.重设计算模块
------------------------------------------------------------
*/					

	// 定义数据处理计数器寄存器comp_c，用于计数处理了多少次。
	assign comp_c_d = comp_c_q + 1;
	// 当前状态是RST_COMP时，计数器启动一次。下一个状态是COMPUTE或者OUTPUT因此只会加一次。
	assign comp_c_en = (state_q == RST_COMP) ? 1 : 0;
	dffre #(16) comp_c (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(comp_c_en), 
		.d(comp_c_d), 
		.q(comp_c_q)
	);			

/*
------------------------------------------------------------
4.输出模块
------------------------------------------------------------
*/
	
	assign mem_we = (state_q == OUTPUT) ? 1 : 0;
	
	// 定义OUTPUT模块输出计数器寄存器ot_c。
	logic [15:0] ot_c_d;
	logic [15:0] ot_c_q;
	logic ot_c_en;
	assign ot_c_d = ot_c_q + 1;
	assign ot_c_en = (state_q == OUTPUT) ? 1 : 0;
	dffre #(16) ot_c (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(ot_c_en), 
		.d(ot_c_d), 
		.q(ot_c_q)
	);		

	// 定义OUTPUT模块地址寄存器ot_addr。
	logic [15:0] ot_addr_d;
	logic [15:0] ot_addr_q;
	logic ot_addr_en;
	assign ot_addr_d = output_addr + ot_c_q;
	assign ot_addr_en = ((state_q == OUTPUT)&&(ot_c_q < 8)) ? 1 : 0;
	dffre #(16) ot_addr (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(ot_addr_en), 
		.d(ot_addr_d), 
		.q(ot_addr_q)
	);		
	
	// 定义OUTPUT模块数据寄存器ot_data。
	logic [31:0] ot_data_d;
	logic ot_data_en;
	// H0_H7_q最低位是A/H0，最高位是H/H7。
	assign ot_data_d = H0_H7_q[ot_c_q*32+:32];
	assign ot_data_en = ((state_q == OUTPUT)&&(ot_c_q < 8)) ? 1 : 0;
	dffre #(32) ot_data (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(ot_data_en), 
		.d(ot_data_d), 
		.q(mem_write_data)
	);			

/*
------------------------------------------------------------
状态机模块
------------------------------------------------------------
*/
	
	logic read_done;
	logic pad_done;
	logic compute_done;
	logic rst_comp_done;
	logic output_done;
	
	assign read_done = (wrtc_q > 18) ? 1 : 0;
	assign pad_done = 1;
	assign compute_done = (done_comp == 1) ? 1 : 0; // 计算完成后，state_d/下一个state_q是RST_COMP。
	assign rst_comp_done = (comp_c_d == 2) ? 1 : 0; // 计算两次后可以输出。
	assign output_done = (ot_c_q == 8) ? 1 : 0;
	
	assign mem_addr = (state_q == READ) ? addr_q : ot_addr_q;
	assign done = (state_q == DONE) ? 1 : 0;
	
	always_comb begin
		case (state_q) // 用当前状态（寄存器的保存值）决定应该做什么。
			IDLE: begin
				state_d = (start == 1) ? READ : IDLE;
			end
		
			READ: begin
				state_d = (read_done == 1) ? PAD : READ;
			end
		
			PAD: begin
				state_d = (pad_done == 1) ? COMPUTE : PAD;
			end
		
			COMPUTE: begin
				state_d = (compute_done == 1) ? RST_COMP : COMPUTE;
			end
			
			RST_COMP: begin
				state_d = (rst_comp_done == 1) ? OUTPUT : COMPUTE;
			end
		
			OUTPUT: begin
				state_d = (output_done == 1) ? DONE : OUTPUT;
			end
		
			DONE: begin
				state_d = DONE;
			end
			
			default: begin
				state_d = IDLE;
			end
		endcase
	end
	
/*
------------------------------------------------------------
检验模块
------------------------------------------------------------
*/

	always_ff @(posedge clk) begin
		case(state_q)
			IDLE: begin
			end
			
			READ: begin
		
				//$display("rdc_q, %0d, addr %h", rdc_q, addr_q);
				//$display("wrtc_q, %0d", wrtc_q);
				//$display("data, %0h", mem_read_data);
				//$display("message %h", msg_q);
				//$display("---------------------------");
			
			end
			
			PAD: begin
				//$display("%h", message_q);
			end
			
			COMPUTE: begin
		
				//$display("block1---------------------");
				//for (int a = 0; a < 16; a++) begin	
					//$display("%d, %h", a, block1[a]);
				//end
				//$display("block2---------------------");
				//for (int b = 0; b < 16; b++) begin
					//$display("%d, %h", b, block2[b]);
				//end
				
				//$display("%d, %h", t_q, wt);
				//$display("w_a_q %h", w_a_q); // 算了wt，数组还未左移。

				//$display(" %d", t_q);
				//$display(" A %h", AH_q[0*32+:32]);
				//$display("---------------------------------------------------");

				//$display("t_q %d, wt %h", t_q, wt);
				//$display("%h",AH_q);
				//$display("H/F %h",F_delay2_q[31:0]);
				//$display("%h", H0_H7_q);
				//$display("---------------------------------------------------");

			end
			
			OUTPUT: begin
				$display("H0 %h, H1 %h", H0_H7_q[0*32+:32], H0_H7_q[1*32+:32]);
				$display("H2 %h, H3 %h", H0_H7_q[2*32+:32], H0_H7_q[3*32+:32]);
				$display("H4 %h, H5 %h", H0_H7_q[4*32+:32], H0_H7_q[5*32+:32]);
				$display("H6 %h, H7 %h", H0_H7_q[6*32+:32], H0_H7_q[7*32+:32]);
				$display("---------------------------------------------------");
				//$display("%d, addr_q %h, data_q %h", ot_c_q, mem_addr, mem_write_data);

			end
			
			DONE: begin
			end
			
			default: begin
				$display("default");
			end
		endcase
	end

endmodule