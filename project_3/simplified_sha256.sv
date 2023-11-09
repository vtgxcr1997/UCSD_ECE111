module simplified_sha256 (input logic clk, reset_n, start,
                     input logic [15:0] message_addr, output_addr,
                    output logic done, mem_clk, mem_we,
                    output logic [15:0] mem_addr,
                    output logic [31:0] mem_write_data,
                     input logic [31:0] mem_read_data);
  // right rotation
  function logic [31:0] rightrotate(input logic [31:0] x, 
												input logic [ 7:0] r); 
		rightrotate = (x >> r) | (x << (32-r)); 
  endfunction
  
  function logic [31:0] wt_calc(input logic [31:0] wt[64], 
										  input logic [31:0] block[0:15],
										  input logic [31:0] t); 
		logic [31:0] s0,s1;
		if (t < 16) begin
			wt_calc = block[t];
		end else begin
			s0 = rightrotate(wt[t-15],7)^rightrotate(wt[t-15],18)^(wt[t-15]>>3);
			s1 = rightrotate(wt[t-2],17)^rightrotate(wt[t-2],19)^(wt[t-2]>>10);
			wt_calc = wt[t-16] + s0 + wt[t-7] + s1;
		end
  endfunction
  
  assign mem_clk = clk;

  logic [31:0] block1 [0:15]; // b1数组包含16个元素，每个元素是32位的,总计512位。
  logic [31:0] block2 [0:15]; // b2数组包含16个元素，每个元素是32位的,总计512位。
  logic [639:0] message; // message的大小是20字，即640比特。
  
  logic [15:0] read_count, output_count;
  logic [31:0] expand_count, proc_count, t;
  
  logic [31:0] H_b [8]; 

  logic [31:0] A, B, C, D, E, F, G, H;
  logic [31:0] A_new, B_new, C_new, D_new, E_new, F_new, G_new, H_new;
  logic [31:0] S0, maj, t2, S1, ch, t1;
  
  logic [31:0] wt [64]; // wt数组包含64个元素，对应64轮计算。每个元素32位。
  
  // SHA256 K constants
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

  enum logic [3:0] {
	 IDLE = 4'b0000,
	 STEP1 = 4'b0001,
    STEP2 = 4'b0010,
    STEP3 = 4'b0011,
	 STEP4 = 4'b0100,
	 STEP5 = 4'b0101,
	 STEP6 = 4'b0110,
	 STEP7 = 4'B0111,
	 STEP8 = 4'B1000,
	 STEP9 = 4'B1001
  } state;							

  always_comb begin
  		S0 = rightrotate(A, 2)^rightrotate(A, 13)^rightrotate(A, 22);
		maj = (A&B) ^ (A&C) ^ (B&C);
		t2 = S0 + maj;
		S1 = rightrotate(E, 6)^rightrotate(E, 11)^rightrotate(E, 25);
		ch = (E&F) ^ ((~E)&G);
		t1 = H + S1 + ch + k[t] + wt[t];
				
		A_new = t1 + t2;
		B_new = A;
		C_new = B;
		D_new = C;
		E_new = D + t1;
		F_new = E;
		G_new = F;
		H_new = G;
  end

  always_ff @(posedge clk, negedge reset_n) begin
    if (!reset_n) begin
	   state <= IDLE;
	 end else begin
	   case (state)
		  IDLE: 
		  if (start) begin
			 H_b[0] <= 32'h6a09e667; 
			 H_b[1] <= 32'hbb67ae85;
			 H_b[2] <= 32'h3c6ef372;
			 H_b[3] <= 32'ha54ff53a;
			 H_b[4] <= 32'h510e527f;
			 H_b[5] <= 32'h9b05688c;
			 H_b[6] <= 32'h1f83d9ab;
			 H_b[7] <= 32'h5be0cd19;		  
  
			 read_count <= 0; // 读入数据分组计数标志。
			 expand_count <= 0; // 分组数据分组计数标志。
			 proc_count <= 0; // 数据处理计数标志。
			 output_count <= 0; // 输出数据计数标志。
			 t <= 0;
			 done <= 0;
			 
			 state <= STEP1;
		  end

        STEP1: begin // 发出接收数据的信号。
		  mem_we <= 0;
		  mem_addr <= message_addr + read_count;
		  state <= STEP2;
		  end

		  STEP2: begin // 等待接收输入信号。
		  state <= STEP3;
		  end

        STEP3: begin // 接收输入信号，并且循环接收20个32位的数据然后放置在message里面。
		  if (read_count < 20) begin
				message[read_count*32+:32] <= mem_read_data;
				read_count <= read_count + 1;
				state <= STEP1;
		  end else begin
				state <= STEP4; 
		  end
		  end
		  
		  STEP4: begin
		  if (expand_count < 16) begin
				block1[expand_count] <= message[expand_count*32+:32];
				block2[expand_count] <= 32'h0;
				expand_count <= expand_count + 1;
		  end else if ((expand_count > 15)&&(expand_count < 20)) begin
				block2[expand_count-16] <= message[expand_count*32+:32];
				expand_count <= expand_count + 1;
		  end else if (expand_count > 19) begin
				block2[4] <= 32'h80000000;
				block2[15] <= 32'd640;

				state <= STEP5;
		  end
		  end

		  STEP5: begin // 第一模块初步处理。
		  if (t < 64) begin 
				wt[t] <= wt_calc(wt,block1,t);
				t <= t + 1;
		  end else if (t == 64) begin						
				t <= 0;
				proc_count <= 0;
				state <= STEP6;
		  end
		  end
		  
		  STEP6: begin // 第二模块二次处理。
		  if (proc_count < 64) begin
				if (proc_count == 0) begin // t是输入值，应该是0,1,2....,63。
					A <= H_b[0];
					B <= H_b[1];
					C <= H_b[2];
					D <= H_b[3];
					E <= H_b[4];
					F <= H_b[5];
					G <= H_b[6];
					H <= H_b[7];
					t <= proc_count;
				end else begin
					A <= A_new;
					B <= B_new;
					C <= C_new;
					D <= D_new;
					E <= E_new;
					F <= F_new;
					G <= G_new;
					H <= H_new;
					t <= proc_count;
				end
				proc_count <= proc_count + 1;		  
		  end else begin
				H_b[0] <= H_b[0] + A_new;
				H_b[1] <= H_b[1] + B_new;
				H_b[2] <= H_b[2] + C_new;
				H_b[3] <= H_b[3] + D_new;
				H_b[4] <= H_b[4] + E_new;
				H_b[5] <= H_b[5] + F_new;
				H_b[6] <= H_b[6] + G_new;
				H_b[7] <= H_b[7] + H_new;
				
				t <= 0;
				state <= STEP7;	  
		  end
		  end

		  STEP7: begin // 第二模块初步处理。
		  if (t < 64) begin 
				wt[t] <= wt_calc(wt,block2,t);
				t <= t + 1;
		  end else if (t == 64) begin						
				t <= 0;
				proc_count <= 0;
				state <= STEP8;
		  end
		  end
		  
		  STEP8: begin
		  if (proc_count < 64) begin // 第二模块二次处理。
				if (proc_count == 0) begin // t是输入值，应该是0,1,2....,63。
					A <= H_b[0];
					B <= H_b[1];
					C <= H_b[2];
					D <= H_b[3];
					E <= H_b[4];
					F <= H_b[5];
					G <= H_b[6];
					H <= H_b[7];
					t <= proc_count;
				end else begin
					A <= A_new;
					B <= B_new;
					C <= C_new;
					D <= D_new;
					E <= E_new;
					F <= F_new;
					G <= G_new;
					H <= H_new;
					t <= proc_count;
				end
				proc_count <= proc_count + 1;		  
		  end else begin
				H_b[0] <= H_b[0] + A_new;
				H_b[1] <= H_b[1] + B_new;
				H_b[2] <= H_b[2] + C_new;
				H_b[3] <= H_b[3] + D_new;
				H_b[4] <= H_b[4] + E_new;
				H_b[5] <= H_b[5] + F_new;
				H_b[6] <= H_b[6] + G_new;
				H_b[7] <= H_b[7] + H_new;
				
				t <= 0;
				state <= STEP9;			
		  end
		  end		  

		  STEP9: begin
		  if (output_count < 8) begin
				mem_we <= 1;
				mem_addr <= output_addr + output_count;
				mem_write_data <= H_b[output_count];
				output_count <= output_count + 1;
		  end else begin	
				mem_we <= 0;
				done <= 1;
				state <= IDLE;
		  end
		  end

		  default: begin
				state <= IDLE;
		  end
		endcase
	end
	end							
endmodule