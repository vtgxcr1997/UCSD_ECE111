/*
优化：
无依赖的逻辑，实现并行
有依赖的逻辑，实现流水线
维持运行周期不变，提高主频,减少总运行时间
*/
module simplified_sha256 (input logic clk, reset_n, start,
								input logic [15:0] message_addr, output_addr,
								output logic done, mem_clk, mem_we,
								output logic [15:0] mem_addr,
								output logic [31:0] mem_write_data,
								input logic [31:0] mem_read_data);
								
/*
------------------------------------------------------------
函数模块
------------------------------------------------------------
*/								
	// right rotation
	function logic [31:0] rrot(input logic [31:0] x,
										input logic [7:0] r);
		rrot = (x>>r) | (x<<(32-r));
	endfunction		
	
	// Calculate new w
	function logic [31:0] wtnew(input logic [511:0] w_a_q);
		logic [31:0] w0, w1, w9, w14;
		logic [31:0] s0, s1;
		
		w0 = w_a_q[0*32+:32];
		w1 = w_a_q[1*32+:32];
		w9 = w_a_q[9*32+:32];
		w14 = w_a_q[14*32+:32];     
		
		s0 = rrot(w1, 7) ^ rrot(w1, 18) ^ (w1 >> 3);
		s1 = rrot(w14, 17) ^ rrot(w14, 19) ^ (w14 >> 10);
		wtnew = w0 + s0 + w9 + s1;
	endfunction	

	// Calculate A-H every t.
	function logic [255:0] sha256_op(input logic [255:0] AH_q,
												input logic [31:0] hkw);
		logic [31:0] G, F, E, D, C, B, A;
		logic [31:0] S1, S0, ch, maj, t1, t2; // internal signals
	begin
		G = AH_q[6*32+:32];
		F = AH_q[5*32+:32];
		E = AH_q[4*32+:32];
		D = AH_q[3*32+:32];
		C = AH_q[2*32+:32];
		B = AH_q[1*32+:32];
		A = AH_q[0*32+:32];
	
		S1 = rrot(E, 6) ^ rrot(E, 11) ^ rrot(E, 25); 
		ch = (E & F) ^ ((~E) & G); 
		t1 = ch + S1 + hkw; 
		S0 = rrot(A, 2) ^ rrot(A, 13) ^ rrot(A, 22); 
		maj = (A & B) ^ (A & C) ^ (B & C); 
		t2 = maj + S0; 
		sha256_op = {G, F, E, D + t1, C, B, A, t1 + t2}; // {H,...,A}		
	end
	endfunction
	
	// Add h, k, w.
	function logic [31:0] hkw_op(input logic [31:0] h, k, w);
	begin
		hkw_op = h + k + w;
	end
	endfunction
	
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
	localparam OUTPUT = 4'b0100;
	localparam DONE = 4'b0101;
	
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
3. 处理数据模块
------------------------------------------------------------
*/	

	parameter int k[0:63] = '{
	32'h428a2f98,32'h71374491,32'hb5c0fbcf,32'he9b5dba5,32'h3956c25b,32'h59f111f1,32'h923f82a4,32'hab1c5ed5,
	32'hd807aa98,32'h12835b01,32'h243185be,32'h550c7dc3,32'h72be5d74,32'h80deb1fe,32'h9bdc06a7,32'hc19bf174,
	32'he49b69c1,32'hefbe4786,32'h0fc19dc6,32'h240ca1cc,32'h2de92c6f,32'h4a7484aa,32'h5cb0a9dc,32'h76f988da,
	32'h983e5152,32'ha831c66d,32'hb00327c8,32'hbf597fc7,32'hc6e00bf3,32'hd5a79147,32'h06ca6351,32'h14292967,
	32'h27b70a85,32'h2e1b2138,32'h4d2c6dfc,32'h53380d13,32'h650a7354,32'h766a0abb,32'h81c2c92e,32'h92722c85,
	32'ha2bfe8a1,32'ha81a664b,32'hc24b8b70,32'hc76c51a3,32'hd192e819,32'hd6990624,32'hf40e3585,32'h106aa070,
	32'h19a4c116,32'h1e376c08,32'h2748774c,32'h34b0bcb5,32'h391c0cb3,32'h4ed8aa4a,32'h5b9cca4f,32'h682e6ff3,
	32'h748f82ee,32'h78a5636f,32'h84c87814,32'h8cc70208,32'h90befffa,32'ha4506ceb,32'hbef9a3f7,32'hc67178f2
};

	/* 
	注意，我们在代码里面计算A-H时，A视为最高位，H视为最低位，即{A,B,..,H}。
	对于H0-H7而言，H0是A，H7是H，注意区分。
	对于数组，array[7]是最高位，array[0]是最低位。
	*/
	parameter H0_ori = 32'h6a09e667; // A
	parameter H1_ori = 32'hbb67ae85; // B
	parameter H2_ori = 32'h3c6ef372; // C
	parameter H3_ori = 32'ha54ff53a; // D
	parameter H4_ori = 32'h510e527f; // E
	parameter H5_ori = 32'h9b05688c; // F
	parameter H6_ori = 32'h1f83d9ab; // G
	parameter H7_ori = 32'h5be0cd19; // H
	
	//---------------------------------------------------------------------	

	// 定义COMPUTE模块轮次计数器寄存器t，用于每轮更新t。
	logic [15:0] t_d, t_q;
	logic t_en;
	
	// 定义COMPUTE模块进入次数计数器寄存器comp_c，用于计算进入了几次COMPUTE模块。在处理中，此寄存器不需要归零。
	/* 
	每次t_q等于66,说明已经进行了一次处理，此时，对于某些寄存器需要重置。
	当t_q等于66时，我们设置dffre_d的值为0，下一个周期，t_q就会等于0。
	*/		
	logic [15:0] comp_c_d, comp_c_q;
	logic comp_c_en;	
	
	//---------------------------------------------------------------------	
	
	// 定义COMPUTE模块w数组寄存器w_a，用于每轮更新w数组。
	logic [31:0] wt;
	logic [511:0] w_a_d, w_a_q;
	logic w_a_en;	
	
	/* 
	定义COMPUTE模块wt延迟输出寄存器wt_delay。
	当前t_q的wt值会延迟一个t_q输出到wt_delay_q，用于计算hkw的和。
	*/
	logic [31:0] wt_delay_d;
	logic [31:0] wt_delay_q;
	logic wt_delay_en;	
	
	//---------------------------------------------------------------------
	
	/* 
	定义COMPUTE模块hkw求和寄存器hkw_sum。
	在当前t_q，我们计算hkw的和并且输入hkw_sum寄存器的d端。
	下一个周期，在hkw_sum_q可以接收上个周期的hkw的和并且直接使用。
	*/
	logic [31:0] hkw_sum_d, hkw_sum_q;
	logic hkw_sum_en;	
	
	//---------------------------------------------------------------------
	
	// 定义COMPUTE模块A-H寄存器AH，用于每轮更新A-H。
	logic [255:0] AH_d, AH_q; // H最高位，A最低位。{H,..,A}。
	logic AH_en;	

	/*
	定义COMPUTE模块F延迟两轮寄存器F_delay2。
	和AH处在同一轮次的AH_d_logic中的F需要延迟两轮从F_delay2_q输出到hkw_sum_d。
	*/
	logic [63:0] F_delay2_d; // 直接传递长数据。
	logic [63:0] F_delay2_q; // 使用F_delay2_q[31:0]作为输出。
	logic F_delay2_en;	
	
	//---------------------------------------------------------------------
	
	// 定义COMPUTE模块阶段性输出寄存器H0_H7，用于输出新的H0-H7。在处理中，此寄存器不需要归零。
	logic [255:0] H0_H7_q; // {H,...,A}最高位是H，最低位是A。
	logic [255:0] H0_H7_d; 
	logic H0_H7_en;	

	// 定义COMPUTE模块轮次计数器寄存器t，用于每轮更新t。
	assign t_d = (t_q == 66) ? 0 : t_q + 1; // t_q等于66时，下一轮次t_q会等于0.
	assign t_en = (state_q == COMPUTE) ? 1 : 0;
	dffre #(16) t (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(t_en), 
		.d(t_d), 
		.q(t_q)
	);	

	// 定义COMPUTE模块进入次数计数器寄存器comp_c，用于计算进入了几次COMPUTE模块。在处理中，此寄存器不需要归零。
	/* 
	每次t_q等于66,说明已经进行了一次处理，此时，对于某些寄存器需要重置。
	当t_q等于66时，我们设置dffre_d的值为0，下一个周期，t_q就会等于0。
	*/		
	assign comp_c_d = comp_c_q + 1;
	assign comp_c_en = (t_q == 66) ? 1 : 0; // 每次处理完一部分数据comp_c_q就加一。
	dffre #(16) comp_c (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(comp_c_en), 
		.d(comp_c_d), 
		.q(comp_c_q)
	);		

	//---------------------------------------------------------------------
	
	// 定义COMPUTE模块w数组寄存器w_a，用于每轮更新w数组。
	always_comb begin
		if (comp_c_q == 0) begin
			wt = (t_q < 16) ? block1[t_q*32+:32] : wtnew(w_a_q); // w_a_q更新时就更新wt，wt用于后续计算。
		end else begin
			wt = (t_q < 16) ? block2[t_q*32+:32] : wtnew(w_a_q); // w_a_q更新时就更新wt，wt用于后续计算。
		end
	end

	//定义COMPUTE模块wt延迟输出寄存器wt_delay。
	//当前t_q的wt值会延迟一个t_q输出到wt_delay_q，用于计算hkw的和。
	assign wt_delay_d = wt;
	assign wt_delay_en = ((state_q == COMPUTE) && (t_q < 65)) ? 1 : 0;
	dffre #(32) wt_delay (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(wt_delay_en), 
		.d(wt_delay_d), 
		.q(wt_delay_q)
	);	

	always_comb begin
		w_a_d = w_a_q;
		if (t_q < 16) begin
			w_a_d[t_q*32+:32] = wt;
		end else if ((t_q > 15) && (t_q < 64)) begin
			w_a_d = {wt, w_a_q[511:32]}; // 数据移位拼接。
		end else begin
			w_a_d = 0;
		end
	end
	assign w_a_en = (state_q == COMPUTE) ? 1 : 0;
	dffre #(512) w_a (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(w_a_en), 
		.d(w_a_d), 
		.q(w_a_q)
	);		

	//---------------------------------------------------------------------
	
	/* 
	定义COMPUTE模块hkw求和寄存器hkw_sum。
	在当前t_q，我们计算hkw的和并且输入hkw_sum寄存器的d端。
	下一个周期，在hkw_sum_q可以接收上个周期的hkw的和并且直接使用。
	*/	
	always_comb begin
		if (t_q == 1) begin
			if (comp_c_q == 0) begin
				hkw_sum_d = hkw_op(H7_ori, k[t_q-1], wt_delay_q); // h[0]
			end else begin
				hkw_sum_d = hkw_op(H0_H7_q[7*32+:32], k[t_q-1], wt_delay_q); // h[0]
			end
		end else if (t_q == 2) begin
			if (comp_c_q == 0) begin
				hkw_sum_d = hkw_op(H6_ori, k[t_q-1], wt_delay_q); // g[0]
			end else begin
				hkw_sum_d = hkw_op(H0_H7_q[6*32+:32], k[t_q-1], wt_delay_q); // g[0]
			end
		end else begin
			// 本轮使用H等效于上一轮的G也等效于再上一轮的F。
			hkw_sum_d = hkw_op(F_delay2_q[31:0], k[t_q-1], wt_delay_q);
		end
	end
	// t_q为1时，我们计算hkw的值并且赋值给hkw_sum_d，然后在下一个周期使用hkw_sum_q来计算A-H。
	assign hkw_sum_en = (t_q > 0) ? 1 : 0;
	dffre #(32) hkw_sum (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(hkw_sum_en), 
		.d(hkw_sum_d), 
		.q(hkw_sum_q)
	);			

	//---------------------------------------------------------------------
	
	// 定义COMPUTE模块A-H寄存器AH，用于每轮更新A-H。{H,...,A}最高位是H，最低位是A。
	always_comb begin 
		// 上一轮次的hkw是赋值给hkw_sum_d，本轮次可以使用hkw_sum_q来计算A-H。
		// 我们计算AH_d，A-H的值会在下一轮次的AH_q更新，这个更新值F可以用来计算下一轮次的hkw_sum。
		if (t_q == 1) begin 
			if (comp_c_q == 0) begin
				// block1的第0轮结果{H,..,A}。
				AH_d = { H7_ori, H6_ori, H5_ori, H4_ori, 
									H3_ori, H2_ori, H1_ori, H0_ori}; 		
			end else begin
				// block2的第0轮结果{H,..,A}。
				AH_d = { H0_H7_q[7*32+:32], H0_H7_q[6*32+:32], H0_H7_q[5*32+:32], H0_H7_q[4*32+:32], 
							H0_H7_q[3*32+:32], H0_H7_q[2*32+:32], H0_H7_q[1*32+:32], H0_H7_q[0*32+:32]}; 	
			end
		end else begin
			// 参考sha256_op(AH_q, hkw)
			AH_d = sha256_op(AH_q, hkw_sum_q); // 从第1轮开始的结果{H,..,A}。	
		end
	end
	assign AH_en = ((t_q > 0) && (t_q < 66)) ? 1 : 0; // 当t_q等于1时，AH_d应该输入初始值。下个周期才会用初始值和hkw计算新A-H。
	dffre #(256) AH (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(AH_en), 
		.d(AH_d), 
		.q(AH_q)
	);		
	
	/*
	定义COMPUTE模块F延迟两轮寄存器F_delay2。
	和AH处在同一轮次的AH_d中的F需要延迟两轮从F_delay2_q输出到hkw_sum_d。
	*/	
	assign F_delay2_d = {AH_d[5*32+:32], F_delay2_q[63:32]}; // 类似w，高位进入，低位输出。
	assign F_delay2_en = (t_q > 0) ? 1 : 0;
	dffre #(64) F_delay2 (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(F_delay2_en), 
		.d(F_delay2_d), 
		.q(F_delay2_q)
	);			
	
	//---------------------------------------------------------------------

	// 定义COMPUTE模块阶段性输出寄存器H0_H7，用于输出新的H0-H7。在处理中，此寄存器不需要归零。
	always_comb begin
		if (comp_c_q == 0) begin 
			// H0_H7_d最高位是H。最低位是A。
			H0_H7_d[7*32+:32] = H7_ori + AH_q[7*32+:32]; // H
			H0_H7_d[6*32+:32] = H6_ori + AH_q[6*32+:32]; // G
			H0_H7_d[5*32+:32] = H5_ori + AH_q[5*32+:32]; // F
			H0_H7_d[4*32+:32] = H4_ori + AH_q[4*32+:32]; // E
			H0_H7_d[3*32+:32] = H3_ori + AH_q[3*32+:32]; // D
			H0_H7_d[2*32+:32] = H2_ori + AH_q[2*32+:32]; // C
			H0_H7_d[1*32+:32] = H1_ori + AH_q[1*32+:32]; // B
			H0_H7_d[0*32+:32] = H0_ori + AH_q[0*32+:32]; // A
			
		end else begin
			// H0_H7_d最高位是H。最低位是A。
			H0_H7_d[7*32+:32] = H0_H7_q[7*32+:32] + AH_q[7*32+:32]; // H
			H0_H7_d[6*32+:32] = H0_H7_q[6*32+:32] + AH_q[6*32+:32]; // G
			H0_H7_d[5*32+:32] = H0_H7_q[5*32+:32] + AH_q[5*32+:32]; // F
			H0_H7_d[4*32+:32] = H0_H7_q[4*32+:32] + AH_q[4*32+:32]; // E
			H0_H7_d[3*32+:32] = H0_H7_q[3*32+:32] + AH_q[3*32+:32]; // D
			H0_H7_d[2*32+:32] = H0_H7_q[2*32+:32] + AH_q[2*32+:32]; // C
			H0_H7_d[1*32+:32] = H0_H7_q[1*32+:32] + AH_q[1*32+:32]; // B
			H0_H7_d[0*32+:32] = H0_H7_q[0*32+:32] + AH_q[0*32+:32]; // A
		end
	end
	assign H0_H7_en = (t_q == 66) ? 1 : 0; // 当t_q等于66时，AH_q已经产生最终结果。
	dffre #(256) H0_H7 (
		.clk(clk), 
		.reset_n(reset_n), 
		.en(H0_H7_en), 
		.d(H0_H7_d), 
		.q(H0_H7_q)
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
	// H0_H7_q[7]是A/H0，H0_H7_q[0]是H/H7。
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
	logic output_done;
	
	assign read_done = (wrtc_q > 18) ? 1 : 0;
	assign pad_done = 1;
	assign compute_done = (comp_c_q == 2) ? 1 : 0;
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
				state_d = (compute_done == 1) ? OUTPUT : COMPUTE;
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
/*
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

				$display(" %d", t_q);
				$display(" A %h", AH_q[0*32+:32]);
				$display("---------------------------------------------------");

				//$display("t_q %d, wt %h", t_q, wt);
				//$display("%h",AH_q);
				//$display("H/F %h",F_delay2_q[31:0]);
				//$display("%h", H0_H7_q);
				//$display("---------------------------------------------------");

			end
			
			OUTPUT: begin

				$display("H0_H7_q %h", H0_H7_q);

				$display("%d, addr_q %h, data_q %h", ot_c_q, mem_addr, mem_write_data);

			end
			
			DONE: begin
				$display("DONE, %0d", done);
			end
			
			default: begin
				$display("default");
			end
		endcase
	end
*/
endmodule