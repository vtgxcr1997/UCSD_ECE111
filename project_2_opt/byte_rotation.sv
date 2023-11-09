module byte_rotation(input logic clk, reset_n, start,
                     input logic [15:0] message_addr, size, output_addr,
                    output logic done, mem_clk, mem_we,
                    output logic [15:0] mem_addr,
                    output logic [31:0] mem_write_data,
                     input logic [31:0] mem_read_data);

  function logic [31:0] byte_rotate(input logic [31:0] value); 
    byte_rotate = {value[23:16], value[15:8], value[7:0], value[31:24]}; 
  endfunction

  logic [31:0] rc, wc; // size = 16 and count from 1.

  assign mem_clk = clk;
						
  enum logic [3:0] {
	 IDLE = 4'b0000,
	 S1 = 4'b0001,
    S2 = 4'b0010,
    S3 = 4'b0011,
	 S4 = 4'b0100,
	 DONE = 4'b0101
  } state;							
							
  always_ff @(posedge clk, negedge reset_n) begin
    if (!reset_n) begin
		rc <= 0;
		wc <= 0;
	   state <= IDLE;
		done <= 0;
	 end else
	   case (state)
		  IDLE: begin
		  if (start) begin
			 state <= S1;
			 rc <= 0;
			 wc <= 0;
			 done <= 0;
		  end
		  end

        S1: begin // 读一。
		  mem_we <= 0;
		  mem_addr <= message_addr + rc;
		  rc <= rc + 1;
		  state <= S2;
		  end

		  S2: begin
		  mem_we <= 0; // 读二
		  mem_addr <= message_addr + rc;
		  rc <= rc + 1;
		  state <= S3;
		  end

        S3: begin // 写一。
		  mem_we <= 1;
		  mem_addr <= output_addr + wc;
		  wc <= wc + 1;
		  
		  mem_write_data <= byte_rotate(mem_read_data);
		  if ((wc+1) == size) begin // (wc+1)是从1开始算，一共传了多少次数据。
		    state <= DONE;
		  end else begin
		    state <= S4;
		  end		  
		  end
		  
        S4: begin // 写二。
		  mem_we <= 1;
		  mem_addr <= output_addr + wc;
		  wc <= wc + 1;
		  
		  mem_write_data <= byte_rotate(mem_read_data);
		  if ((wc+1) == size) begin // (wc+1)是从1开始算，一共传了多少次数据。
		    state <= DONE;
		  end else begin
		    state <= S1;
		  end		
		  end
		  
		  DONE: begin
		  done <= 1;
		  state <= IDLE;
		  end
		  
		  default: begin
		  state <= IDLE;
		  end
		  
		endcase
  end										
endmodule