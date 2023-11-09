module byte_rotation(input logic clk, reset_n, start,
                     input logic [15:0] message_addr, size, output_addr,
                    output logic done, mem_clk, mem_we,
                    output logic [15:0] mem_addr,
                    output logic [31:0] mem_write_data,
                     input logic [31:0] mem_read_data);

  function logic [31:0] byte_rotate(input logic [31:0] value); 
    byte_rotate = {value[23:16], value[15:8], value[7:0], value[31:24]}; 
  endfunction

  logic [31:0] value;
  logic [15:0] count;
  assign mem_clk = clk;
						
  enum logic [3:0] {
	 IDLE = 4'b0000,
	 S1 = 4'b0001,
    S2 = 4'b0010,
    S3 = 4'b0011,
	 S4 = 4'b0100
  } state;							
							
  always_ff @(posedge clk, negedge reset_n) begin
    if (!reset_n) begin
	   state <= IDLE;
		done <= 0;
		count <= 0;
	 end else
	   case (state)
		  IDLE: 
		  if (start) begin
			 state <= S1;
			 count <= 0;
			 done <= 0;
		  end

        S1: begin // Read as order.
		  mem_we <= 0;
		  mem_addr <= message_addr + count;
		  state <= S2;
		  end

		  S2: 
		  state <= S3;

        S3: begin
		  value <= mem_read_data;
		  state <= S4;
		  end
		  
        S4: begin // Write as order.
		  mem_we <= 1;
		  mem_addr <= output_addr + count;
		  mem_write_data <= byte_rotate(value);
		  
		  count <= count + 1;
		  if (count==size) begin // Continue or stop.
		    state <= IDLE;
			 done <= 1;
		  end else begin
		    state <= S1;
		  end
		  end
		  
		endcase
  end										
endmodule