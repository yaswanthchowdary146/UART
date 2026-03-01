module tx_shift_reg (
    input  wire         clk,
    input  wire         rst,
    input  wire         load,          // pulse to load 128-bit data
    input  wire         shift,         // pulse after each byte sent (tx_done)
    input  wire [127:0] data_in,       // 128-bit parallel data
    output reg  [7:0]   tx_byte,       // current byte to send to UART
    output reg          tx_valid,      // byte is ready to send
    output reg          done           // all 16 bytes shifted out
);

    reg [127:0] shift_reg;
    reg [3:0]   byte_count;            // 0 to 15

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            shift_reg  <= 128'd0;
            tx_byte    <= 8'd0;
            tx_valid   <= 1'b0;
            done       <= 1'b0;
            byte_count <= 4'd0;
        end

        else if (load) begin
            shift_reg  <= data_in;
            byte_count <= 4'd0;
            tx_valid   <= 1'b1;
            done       <= 1'b0;
            tx_byte    <= data_in[7:0];   // pre-load first byte immediately
        end

        else if (shift && tx_valid) begin
            if (byte_count == 4'd15) begin
                // all 16 bytes done
                tx_valid   <= 1'b0;
                done       <= 1'b1;
                byte_count <= 4'd0;
            end
            else begin
                shift_reg  <= shift_reg >> 8;
                byte_count <= byte_count + 1;
                tx_byte    <= shift_reg[15:8];  // next byte after shift
                done       <= 1'b0;
            end
        end

        else begin
            done <= 1'b0;   // done is a single cycle pulse
        end
    end

endmodule
