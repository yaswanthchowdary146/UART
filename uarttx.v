//pipo

module tx_piso(input clk,rst,shift,load,
	input [7:0]din,
	output  tx_out);

reg [7:0]temp;

always @ (posedge clk or posedge rst) begin
	if (rst) 
		temp<=8'd0;

	else if(load)
		temp<=din;
	else if(shift)
		temp<={1'b0,temp[7:1]};

end
 assign tx_out=temp[0];
endmodule


//parity genrator

module tx_parity_gen(input clk,rst,parity_load,
	input [7:0]parity_din,
	output  reg parity_out);

always @(posedge clk or posedge rst) begin
	if (rst) 
		parity_out<=0;
	else if(parity_load)
		parity_out<=^(parity_din);

end

endmodule


//mux


module tx_mux(input [1:0]mux_select,
	input data_in,
	input parity_bit,
	output reg tx_out);

always @(*) begin
	case (mux_select)
		2'b00:tx_out=0;
		2'b01:tx_out=data_in;
		2'b10:tx_out=parity_bit;
		2'b11:tx_out=1;
	endcase
end
endmodule

//baud genrator

module baudgen #(parameter clk_freq=100_000_000,parameter baud=115200)( input clk,rst,output reg baud_tick);

 localparam baud_rate=clk_freq/baud;
 localparam width=$clog2(baud_rate);

 reg [width-1:0] count;
always @(posedge clk or posedge rst) begin
	if (rst) begin
		count<=0;
		baud_tick<=0;
	end
	else if (count==baud_rate-1) begin
		count<=0;
		baud_tick<=1;
	end
	else begin
		count<=count+1;

		baud_tick<=0;
	end
end
endmodule

//data path

module uart_datapath(input clk,rst,shift,load,
	input [1:0]mux_select,
	input [7:0]data_in,
	output tx_out);

wire piso_out_mux,parity_out_mux;

tx_piso inst_piso(.clk(clk),.rst(rst),.shift(shift),.load(load),.din(data_in),.tx_out(piso_out_mux));

tx_parity_gen inst_pgen(.clk(clk),.rst(rst),.parity_load(load),.parity_din(data_in),.parity_out(parity_out_mux));

tx_mux inst_mux(.mux_select(mux_select),.data_in(piso_out_mux),.parity_bit(parity_out_mux),.tx_out(tx_out));

endmodule

//control path FSM

module uart_controlpath( input clk,rst,baud_tick,tx_start,
	output reg load,shift,tx_busy,
	output reg[1:0]mux_select);

reg [3:0] bit_count;

parameter idle=3'b000,
	start=3'b001,
	data=3'b010,
	parity=3'b011,
	stop=3'b100;
reg[2:0] present_state,next_state;

always @(posedge clk or posedge rst) begin
	if (rst)
		present_state<=idle;
	else
		present_state<=next_state;
end


always @(*) begin
	case(present_state)
		idle:begin if(tx_start)
				next_state=start;
				else
					next_state=idle;
			end

		start:begin if(baud_tick)
				next_state=data;
				else
					next_state=start;
			end

		data:begin if (baud_tick && bit_count==7)
				next_state=parity;
				else
					next_state=data;
			end

		parity: begin if (baud_tick)
					next_state=stop;
					else
						next_state=parity;
				end
		stop: begin if(baud_tick)
				next_state=idle;
				else
					next_state=stop;
			end

			default:next_state=idle;
		endcase
	end

always @ (posedge clk or posedge rst) begin
	if(rst)
		bit_count<=0;
	else if(baud_tick && present_state==data && bit_count<7)
		bit_count<=bit_count+1;
	else if(present_state !=data)
		bit_count<=0;
end

//output logic

always @ (*) begin
	load=0;
	mux_select=2'b11;
	shift=0;
	tx_busy=0;

	case(present_state)
		idle: begin mux_select=2'b11;
				load=0;
				shift=0;
				tx_busy=0;
			end
		start: begin  mux_select=2'b00;
				load=baud_tick;
				shift=0;
				tx_busy=1;
			end

		data: begin  mux_select=2'b01;
				load=0;
				shift = baud_tick && (bit_count < 7);
				tx_busy=1;
			end
		parity: begin  mux_select=2'b10;
				load=0;
				shift=0;
				tx_busy=1;
			end
		stop: begin  mux_select=2'b11;
				load=0;
				shift=0;
				tx_busy=1;
			end
		endcase
	end
	endmodule

//uart transmiter top module

module uart_tx_top (
    input clk,
    input rst,
    input tx_start,
    input [7:0] tx_data_in,

    output tx_out,
    output tx_busy
);

wire baud_tick;
wire load;
wire shift;
wire [1:0] mux_select;

baudgen #(.clk_freq(100_000_000),.baud(115200)) u_baud (.clk(clk),.rst(rst),.baud_tick(baud_tick));

uart_controlpath u_ctrl ( .clk(clk),.rst(rst),.baud_tick(baud_tick), .tx_start(tx_start),.load(load),.shift(shift),.tx_busy(tx_busy),.mux_select(mux_select));

uart_datapath u_data (.clk(clk),.rst(rst), .shift(shift),.load(load),.mux_select(mux_select),.data_in(tx_data_in),.tx_out(tx_out));

endmodule
