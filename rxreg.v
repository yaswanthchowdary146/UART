module rx_shift_reg (
    input  wire        clk,
    input  wire        rst,
    input  wire        rx_valid,      // pulse when UART has received a byte (rx_done)
    input  wire [7:0]  rx_byte,       // received byte from UART
    output reg [127:0] data_out,      // assembled 128-bit data
    output reg         done           // all 16 bytes received
);

    reg [3:0] byte_count;             // 0 to 15

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out   <= 128'd0;
            done       <= 1'b0;
            byte_count <= 4'd0;
        end

        else if (rx_valid) begin
            // place received byte into correct position (LSB first)
            data_out[byte_count*8 +: 8] <= rx_byte;

            if (byte_count == 4'd15) begin
                done       <= 1'b1;
                byte_count <= 4'd0;
            end
            else begin
                done       <= 1'b0;
                byte_count <= byte_count + 1;
            end
        end

        else begin
            done <= 1'b0;
        end
    end

endmodule
