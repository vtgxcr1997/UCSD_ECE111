// 串行处理。
module bitcoin_hash (input logic clk, reset_n, start,
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
	
	localparam PAD1 = 4'b0010;
	localparam COMP_P1 = 4'b0011;
	
	localparam PAD2 = 4'b0100;
	localparam COMP_P2 = 4'b0101;
	
	localparam PAD3 = 4'b0110;
	localparam COMP_P3 = 4'b0111;
	
	localparam OUTPUT = 4'b1000;
	localparam DONE = 4'b1001;
	
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
1. 读数据模块READ
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
	logic [15:0] rd_addr_d;
	logic [15:0] rd_addr_q;
	assign rd_addr_d = (state_q == READ) ? message_addr + rdc_q : 0;
	assign rd_addr_en = (state_q == READ) ? 1 : 0;
	dffre #(16) rd_addr (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(rd_addr_en), 
		.d(rd_addr_d), 
		.q(rd_addr_q) // 内存地址接口
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
	logic [607:0] message_d, message_q;	
	logic message_en; 
    // 部分更新 msg_d
    always_comb begin
        message_d = message_q;  // 默认情况下，保持数据不变
        message_d[wrtc_q*32 +: 32] = mem_read_data;  // 更新特定的32位块
    end
	assign message_en = (state_q == READ) ? 1 : 0;
	dffre #(608) message (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(message_en), 
		.d(message_d), 
		.q(message_q)
	);			

	
//信号定义集合---------------------------------------------------------------------	

	logic [511:0] p1_block1;
	logic [511:0] p2_block2;
	logic [511:0] p3_block1;
	
	//---------------------------------------------------------------------	
	
	parameter H0_ori = 32'h6a09e667; // A
	parameter H1_ori = 32'hbb67ae85; // B
	parameter H2_ori = 32'h3c6ef372; // C
	parameter H3_ori = 32'ha54ff53a; // D
	parameter H4_ori = 32'h510e527f; // E
	parameter H5_ori = 32'h9b05688c; // F
	parameter H6_ori = 32'h1f83d9ab; // G
	parameter H7_ori = 32'h5be0cd19; // H
	
	// 定义COMP模块输入。
	logic start_comp;
	logic [511:0] block_comp;
	logic [255:0] H0_H7_d;
	// 定义COMP模块输出。
	logic done_comp;
	logic [255:0] H0_H7_q;	
	// 1. 输入start给1，子状态机进入COMPUTE状态，开始计算。
	// 2. t_q超过65，子状态机进入DONE状态，产生输出并且done给1。
	// 3. 输入start给0，子状态机进入IDLE状态，done和t_q和输出归零。
	bitcoin_hash_H0H7cal H0H7_cal ( 
													.clk(clk), 
													.reset_n(reset_n),
													.start(start_comp),
													.block(block_comp),
													.H0_H7_0(H0_H7_d), // 原初H0_H7。
													.done(done_comp),
													.H0_H7_q(H0_H7_q) // 经过计算以后需要输出的H0_H7。
													);			
					
	// 定义输出接收寄存器，将输出数据保存到H_temp_q里面。
	// 当计算完成后，done_comp拉高。
	logic [255:0] H_temp1_d, H_temp1_q;	
	logic H_temp1_en; 
	assign H_temp1_d = H0_H7_q;
	// 只保留COMP_P1状态的p1_block1计算结果，用于后续16次计算。
	assign H_temp1_en = ((state_q == COMP_P1) && (done_comp == 1)) ? 1 : 0;
	dffre #(256) H_temp1 (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(H_temp1_en), 
		.d(H_temp1_d), 
		.q(H_temp1_q)
	);														
	// 定义输出接收寄存器，将输出数据保存到H_temp_q里面。
	// 当计算完成后，done_comp拉高。
	logic [255:0] H_temp_d, H_temp_q;	
	logic H_temp_en; 
	assign H_temp_d = H0_H7_q;
	assign H_temp_en = (done_comp == 1) ? 1 : 0;
	dffre #(256) H_temp (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(H_temp_en), 
		.d(H_temp_d), 
		.q(H_temp_q)
	);	
	
	//---------------------------------------------------------------------	
	
	// 定义OUTPUT模块输出计数器寄存器ot_c。
	logic [15:0] ot_c_d;
	logic [15:0] ot_c_q;
	logic ot_c_en;	
	
	// 定义OUTPUT模块地址寄存器ot_addr。
	logic [15:0] ot_addr_d;
	logic [15:0] ot_addr_q;
	logic ot_addr_en;	
	
	// 定义OUTPUT模块数据寄存器ot_data。
	logic [31:0] ot_data_d;
	logic ot_data_en;	
	
//信号定义集合---------------------------------------------------------------------		
	
/*
------------------------------------------------------------
2. 计算模块COMP_P1/COMP_P2/COMP_P3
------------------------------------------------------------
*/	

	// 定义COMP模块输入。
	always_comb begin
		case (state_q) // 用当前状态（寄存器的保存值）决定应该做什么。
			IDLE: begin
				start_comp = 0;
				block_comp = 0;
				H0_H7_d = 0;
			end
			READ: begin
				start_comp = 0;
				block_comp = 0;
				H0_H7_d = 0;
			end
		
			PAD1: begin
				start_comp = 0;
				block_comp = 0;
				H0_H7_d = 0;
			end
			COMP_P1: begin
				start_comp = 1;
				block_comp = p1_block1;
				H0_H7_d = {H7_ori,H6_ori,H5_ori,H4_ori,H3_ori,H2_ori,H1_ori,H0_ori};
			end
			
			PAD2: begin
				start_comp = 0;
				block_comp = 0;
				H0_H7_d = 0;
			end
			COMP_P2: begin
				start_comp = 1;
				block_comp = p2_block2;
				H0_H7_d = H_temp1_q;
			end

			PAD3: begin
				start_comp = 0;
				block_comp = 0;
				H0_H7_d = 0;
			end
			COMP_P3: begin
				start_comp = 1;
				block_comp = p3_block1;
				H0_H7_d = {H7_ori,H6_ori,H5_ori,H4_ori,H3_ori,H2_ori,H1_ori,H0_ori};
			end
		
			OUTPUT: begin
				start_comp = 0;
				block_comp = 0;
				H0_H7_d = 0;
			end
		
			DONE: begin
				start_comp = 0;
				block_comp = 0;
				H0_H7_d = 0;
			end
			
			default: begin
				start_comp = 0;
				block_comp = 0;
				H0_H7_d = 0;
			end
		endcase
	end
	
/*
------------------------------------------------------------
3. 扩展数据模块PAD1
------------------------------------------------------------
*/

	assign p1_block1 = message_q[511:0];

/*
------------------------------------------------------------
4. 扩展数据模块PAD2
------------------------------------------------------------
*/

	always_comb begin
		p2_block2[0*32+:32] = message_q[16*32+:32];
		p2_block2[1*32+:32] = message_q[17*32+:32];
		p2_block2[2*32+:32] = message_q[18*32+:32];
		p2_block2[3*32+:32] = ot_c_q; // nonce
		p2_block2[4*32+:32] = 32'h80000000;
		for(int i = 5; i < 15; i = i + 1) begin
			p2_block2[i*32+:32] = 0;
		end		
		p2_block2[15*32+:32] = 32'd640;
	end
	
/*
------------------------------------------------------------
5. 扩展数据模块PAD3
------------------------------------------------------------
*/	

	always_comb begin
		for(int i = 0; i < 8; i = i + 1) begin
			p3_block1[i*32+:32] = H_temp_q[i*32+:32];
		end		
		p3_block1[8*32+:32] = 32'h80000000;
		for(int i = 9; i < 15; i = i + 1) begin
			p3_block1[i*32+:32] = 0;
		end				
		p3_block1[15*32+:32] = 32'd256;
	end

/*
------------------------------------------------------------
6. 输出和计数模块OUTPUT
------------------------------------------------------------
*/		

	assign mem_we = (state_q == OUTPUT) ? 1 : 0;
	
	// 定义OUTPUT模块输出计数器寄存器ot_c。
	assign ot_c_d = ot_c_q + 1;
	// d端值已经在OUTPUT前一个状态准备好，OUTPUT状态会输出q端值。
	assign ot_c_en = ((state_q == COMP_P3)&&(done_comp == 1)) ? 1 : 0;
	dffre #(16) ot_c (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(ot_c_en), 
		.d(ot_c_d), 
		.q(ot_c_q)
	);		
	
	// 定义OUTPUT模块地址寄存器ot_addr。
	assign ot_addr_d = output_addr + ot_c_q;
	// d端值已经在OUTPUT前一个状态准备好，OUTPUT状态可以直接查看q端值。 
	assign ot_addr_en = ((state_q == COMP_P3)&&(done_comp == 1)) ? 1 : 0;
	dffre #(16) ot_addr (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(ot_addr_en), 
		.d(ot_addr_d), 
		.q(ot_addr_q)
	);		
	
	// 定义OUTPUT模块数据寄存器ot_data。
	// H0_H7_q最低位是A/H0，最高位是H/H7。
	assign ot_data_d = H0_H7_q[0*32+:32];
	// d端值已经在OUTPUT前一个状态准备好，OUTPUT状态可以直接查看q端值。
	assign ot_data_en = ((state_q == COMP_P3) && (done_comp == 1)) ? 1 : 0;
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
	// 读取数据，19个word，即0-17。
	logic read_done;
	// 第一次sha256，计算block1。
	logic comp_p1_done;
	// 第一次sha256，计算block2。
	logic comp_p2_done;
	// 第二次sha256，计算block1。
	logic comp_p3_done;
	// 输出单次结果。
	logic output_done;

	assign read_done = (wrtc_q > 17) ? 1 : 0;
	assign comp_p1_done = (done_comp == 1) ? 1 : 0;
	assign comp_p2_done = (done_comp == 1) ? 1 : 0;
	assign comp_p3_done = (done_comp == 1) ? 1 : 0;
	assign output_done = (ot_c_q == 16) ? 1 : 0; // 控制输出多少个结果。
	
//---------------------------------------------------------------------	

	assign mem_addr = (state_q == READ) ? rd_addr_q : ot_addr_q;
	assign done = (state_q == DONE) ? 1 : 0;

	always_comb begin
		case (state_q) // 用当前状态（寄存器的保存值）决定应该做什么。
			IDLE: begin
				state_d = (start == 1) ? READ : IDLE;
			end
		
			READ: begin
				state_d = (read_done == 1) ? PAD1 : READ;
			end
		
			PAD1: begin
				state_d = COMP_P1;
			end
			COMP_P1: begin
				state_d = (comp_p1_done == 1) ? PAD2 : COMP_P1;
			end
			
			PAD2: begin
				state_d = COMP_P2;
			end
			COMP_P2: begin
				state_d = (comp_p2_done == 1) ? PAD3 : COMP_P2;
			end

			PAD3: begin
				state_d = COMP_P3;
			end
			COMP_P3: begin
				state_d = (comp_p3_done == 1) ? OUTPUT : COMP_P3;
			end
		
			OUTPUT: begin
				state_d = (output_done == 1) ? DONE : PAD2;
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
/*
	always_ff @(posedge clk) begin
		case(state_q)
			IDLE: begin
			end
			READ: begin
			end
			
			PAD1: begin
			end
			
			COMP_P1: begin
				//检测模块是否正常输出。
				if (done_comp == 1) begin
					$display("COMP_P1");
					for(int i = 0; i < 8; i = i + 1) begin
						$display("H0_H7_q %d, %h", i, H0_H7_q[i*32+:32]);
					end
					$display("----------------------------------");		
				end
			end
			
			PAD2: begin
				//检测输出是否正常保存。
				$display("PAD2");
				for(int i = 0; i < 8; i = i + 1) begin
					$display("H_temp_q %d, %h", i, H_temp_q[i*32+:32]);
				end
				$display("----------------------------------");				
			end
			
			COMP_P2: begin	
				//检测模块是否正常输出。
				if (done_comp == 1) begin
					$display("COMP_P2");
					for(int i = 0; i < 8; i = i + 1) begin
						$display("H0_H7_q %d, %h", i, H0_H7_q[i*32+:32]);
					end
					$display("----------------------------------");		
				end
			end
			
			PAD3: begin
				//检测输出是否正常保存。
				$display("PAD3");
				for(int i = 0; i < 8; i = i + 1) begin
					$display("H_temp_q %d, %h", i, H_temp_q[i*32+:32]);
				end
				$display("----------------------------------");	
			end
			
			COMP_P3: begin
			end			

			OUTPUT: begin
				//检测输出是否正常保存。
				$display("OUTPUT");
				$display("mem_we %d", mem_we);
				$display("ot_addr_q %h", ot_addr_q);
				$display("mem_write_data %h", mem_write_data);
				$display("----------------------------------");				
			end
			
			DONE: begin
			end
			
			default: begin
				$display("default");
			end
		endcase
	end
*/
endmodule