module fibonacci_calculator (input logic clk, reset_n,
                             input logic [4:0] input_s,
                             input logic begin_fibo,
                            output logic [15:0] fibo_out,
                            output logic done);

//  1. 尝试写两状态的数列计算器状态机。
//  2. 状态机需要定义状态并且设定状态转变条件。
//  3. 该状态机使用Flip-Flop触发器构建。
//  4. 另外一种写法是只使用count作为是否计算的判断符，更简洁。
//  5. 不用ff的方法是先计算大量该数列的值然后按顺序填写到输出中。

  logic  [4:0] count;
  logic [15:0] R0, R1;
  logic [1:0] compute;
  
  assign done = (count == 1);
  assign fibo_out = R0;

  always_ff @(posedge clk, negedge reset_n) // 检测clk和reset_n的上升沿，然后进行对应操作。
  begin
    if (!reset_n) begin
		count <= 0;
		R0 <= 1;
		R1 <= 0;
		compute <= 2'b00;
    end else
			if (begin_fibo) begin
            count <= input_s;
            R0 <= 1;
            R1 <= 0; 
				compute <= 1;
    end else begin
			if (compute==1) begin
				if (count > 1) begin
					count <= count - 1; // 状态机只进行有限次计算。
					R0 <= R0 + R1;
					R1 <= R0;
					$display("count = %3d, R0 = %4d, R1 = %4d", count, R0, R1);
				end else begin
					compute <= 0;
				end
			end
    end
  end 									 
						 
									 
  /* 
  1. 尝试写两状态的数列计算器状态机。
  2. 状态机需要定义状态并且设定状态转变条件。
  3. 该状态机使用Flip-Flop触发器构建。

  enum logic [1:0] {IDLE=2'b00, COMPUTE=2'b01} state; // 状态定义

  logic  [4:0] count;
  logic [15:0] R0, R1;
  
  assign done = (count == 1);
  assign fibo_out = R0;

  always_ff @(posedge clk, negedge reset_n) // 检测clk和reset_n的上升沿，然后进行对应操作。
  begin
    if (!reset_n) begin
      state <= IDLE;
		count <= 0;
    end else
      case (state)
		  IDLE:
          if (begin_fibo) begin
            count <= input_s;
            R0 <= 1;
            R1 <= 0; 
            state <= COMPUTE; // 状态机从IDLE转到COMPUTE。
          end
        COMPUTE:
          if (count > 1) begin
            count <= count - 1; // 状态机只进行有限次计算。
            R0 <= R0 + R1;
            R1 <= R0; // 该计算与一般的赋值不一样。
            $display("state = %s, count = %3d, R0 = %4d, R1 = %4d", state, count, R0, R1);
          end else begin
				state <= IDLE; // 状态机从COMPUTE转到IDLE。
          end
      endcase
  end 
  */
  
  /*
  1. 三状态的数列计算器状态机。
  2. 状态机需要定义状态并且设定状态转变条件。
  3. 该状态机使用Flip-Flop触发器构建。
 
  enum logic [1:0] {IDLE=2'b00, COMPUTE=2'b01, DONE=2'b10} state;

  logic  [4:0] count;
  logic [15:0] R0, R1;

  always_ff @(posedge clk, negedge reset_n)
  begin
    if (!reset_n) begin
      state <= IDLE;
      done <= 0;
    end else
      case (state)
        IDLE:
          if (begin_fibo) begin
            count <= input_s;
            R0 <= 1;
            R1 <= 0;
            state <= COMPUTE;
          end
        COMPUTE:
          if (count > 1) begin
            count <= count - 1;
            R0 <= R0 + R1;
            R1 <= R0;
            $display("state = %s, count = %3d, R0 = %4d, R1 = %4d", state, count, R0, R1);
          end else begin
            state <= DONE;
            done <= 1;
            fibo_out <= R0;
          end
        DONE:
          state <= IDLE;
      endcase
  end
  */
endmodule