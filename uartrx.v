// ============================================================
// UART Receiver (16x oversampling)
// ============================================================

// Start Bit Detector (16x oversampled)
// Looks for a falling edge then confirms low at mid-bit (count=7)
module start_detector_16x (
    input      clk,
    input      rst,
    input      baud_tick,
    input      rx_in,
    output reg start_valid
);

    reg        busy;
    reg        rx_d;
    reg [3:0]  sample_cnt;

    wire falling_edge = rx_d & ~rx_in;

    // Delayed rx for edge detect (only sample on baud_tick)
    always @(posedge clk or posedge rst) begin
        if (rst)
            rx_d <= 1'b1;
        else if (baud_tick)
            rx_d <= rx_in;
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sample_cnt  <= 0;
            start_valid <= 0;
            busy        <= 0;
        end
        else if (baud_tick) begin
            start_valid <= 0;

            if (!busy) begin
                if (falling_edge) begin
                    busy       <= 1;
                    sample_cnt <= 0;
                end
            end
            else begin
                sample_cnt <= sample_cnt + 1;

                // Mid-bit sample at count 7: confirm still low
                if (sample_cnt == 7) begin
                    if (rx_in == 0) begin
                        start_valid <= 1;
                        busy <= 0;   // release immediately so next frame isn't blocked
                    end else
                        busy <= 0;   // glitch, abort
                end

                // Safety fallback
                if (sample_cnt == 15)
                    busy <= 0;
            end
        end
    end

endmodule


// SIPO Shift Register (LSB first, 8-bit)
module sipo (
    input  wire       clk,
    input  wire       rst,
    input  wire       rx_in,
    input  wire       shift,
    input  wire       sample_done,
    output reg        data_ready,
    output reg [7:0]  sipo_out
);

    reg [2:0] bit_count;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sipo_out   <= 8'b0;
            bit_count  <= 3'b0;
            data_ready <= 1'b0;
        end
        else begin
            data_ready <= 1'b0;

            if (shift && sample_done) begin
                // Shift in LSB first: new bit goes to MSB, shift right
                sipo_out  <= {rx_in, sipo_out[7:1]};

                if (bit_count == 3'd7) begin
                    data_ready <= 1'b1;
                    bit_count  <= 3'b0;
                end
                else begin
                    bit_count <= bit_count + 1'b1;
                end
            end
        end
    end

endmodule


// Parity Checker (even parity)
// FIX: use a wire for computed parity to avoid 1-cycle stale bug
module parity_checker (
    input        clk, rst, load, rx_in,
    input  [7:0] data,
    output reg   parity_error
);

    wire pgen = ^data;  // combinational — always current

    always @(posedge clk or posedge rst) begin
        if (rst)
            parity_error <= 0;
        else if (load)
            parity_error <= (rx_in ^ pgen);  // rx_in is parity bit received
        else
            parity_error <= 0;
    end

endmodule


// Stop Bit Checker
module stop_bit (
    input      clk, rst, check_stop, rx_in,
    output reg stop_bit_error
);

    always @(posedge clk or posedge rst) begin
        if (rst)
            stop_bit_error <= 0;
        else if (check_stop)
            stop_bit_error <= ~rx_in;  // error if stop bit is not 1
        else
            stop_bit_error <= 0;
    end

endmodule


// 16x Baud Rate Generator
module baudgen16 #(parameter clk_freq = 100_000_000, parameter baud = 115200)(
    input clk, rst,
    output reg baud_tick);

    localparam divisor = clk_freq / (16 * baud);
    localparam width   = $clog2(divisor);

    reg [width-1:0] count;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count     <= 0;
            baud_tick <= 0;
        end
        else if (count == divisor - 1) begin
            count     <= 0;
            baud_tick <= 1;
        end
        else begin
            count     <= count + 1;
            baud_tick <= 0;
        end
    end

endmodule


// RX Datapath
module uart_rx_datapath (
    input        clk,
    input        rst,
    input        rx_in,
    input        baud_tick,

    // control signals from FSM
    input        shift,
    input        sample_done,
    input        parity_load,
    input        check_stop,

    // outputs
    output       start_valid,
    output       data_ready,
    output       parity_error,
    output       stop_bit_error,
    output [7:0] data_out
);

    wire [7:0] sipo_data;

    start_detector_16x u_start (
        .clk(clk), .rst(rst), .baud_tick(baud_tick),
        .rx_in(rx_in), .start_valid(start_valid));

    sipo u_sipo (
        .clk(clk), .rst(rst), .rx_in(rx_in),
        .shift(shift), .sample_done(sample_done),
        .data_ready(data_ready), .sipo_out(sipo_data));

    parity_checker u_parity (
        .clk(clk), .rst(rst), .load(parity_load),
        .rx_in(rx_in), .data(sipo_data),
        .parity_error(parity_error));

    stop_bit u_stop (
        .clk(clk), .rst(rst), .check_stop(check_stop),
        .rx_in(rx_in), .stop_bit_error(stop_bit_error));

    assign data_out = sipo_data;

endmodule


// RX Control FSM
module uart_rx_fsm (
    input      clk,
    input      rst,
    input      baud_tick,
    input      start_valid,
    input      data_ready,

    output reg shift,
    output reg sample_done,
    output reg parity_load,
    output reg check_stop,
    output reg rx_busy
);

    parameter IDLE   = 3'b000;
    parameter START  = 3'b001;
    parameter DATA   = 3'b010;
    parameter PARITY = 3'b011;
    parameter STOP   = 3'b100;

    reg [2:0] state, next_state;

    reg [3:0] sample_cnt;   // 0-15: 16x oversampling counter
    reg [2:0] bit_cnt;      // 0-7:  data bit counter

    // --------------------------------------------------------
    // State Register
    // --------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) state <= IDLE;
        else     state <= next_state;
    end

    // --------------------------------------------------------
    // 16x Sample Counter
    // Resets on baud_tick when start_valid fires so that
    // the NEXT sample_done (count==7, 16 ticks later) lands
    // exactly at mid-bit of the FIRST data bit.
    // Must be gated by baud_tick — not raw start_valid —
    // otherwise the counter is held at 0 for ~54 clocks.
    // --------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst)
            sample_cnt <= 0;
        else if (baud_tick) begin
            if (start_valid)
                sample_cnt <= 0;        // re-align on the baud_tick that carries start_valid
            else if (sample_cnt == 15)
                sample_cnt <= 0;
            else
                sample_cnt <= sample_cnt + 1;
        end
    end

    // --------------------------------------------------------
    // Mid-Bit Sample Pulse — combinational to avoid 1-cycle lag
    // A registered version caused shift/parity_load to fire one
    // cycle after the correct sample point.
    // --------------------------------------------------------
    always @(*) begin
        sample_done = baud_tick && (sample_cnt == 7);
    end

    // --------------------------------------------------------
    // Bit Counter (increments only in DATA state)
    // --------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst)
            bit_cnt <= 0;
        else if (state == DATA && sample_done) begin
            if (bit_cnt == 7)
                bit_cnt <= 0;
            else
                bit_cnt <= bit_cnt + 1;
        end
        else if (state == IDLE)
            bit_cnt <= 0;
    end

    // --------------------------------------------------------
    // Next State Logic
    // START state removed — start_detector already confirmed
    // mid-bit of start; go straight to DATA on start_valid.
    // This avoids a one-cycle pipeline gap that shifted the
    // sampling window for the first data bit.
    // --------------------------------------------------------
    always @(*) begin
        case (state)
            IDLE:   next_state = start_valid                    ? DATA   : IDLE;
            DATA:   next_state = (sample_done && bit_cnt == 7)  ? PARITY : DATA;
            PARITY: next_state = sample_done                    ? STOP   : PARITY;
            STOP:   next_state = sample_done                    ? IDLE   : STOP;
            default: next_state = IDLE;
        endcase
    end

    // --------------------------------------------------------
    // Output Logic
    // --------------------------------------------------------
    always @(*) begin
        shift       = 0;
        parity_load = 0;
        check_stop  = 0;
        rx_busy     = 1;

        case (state)
            IDLE: begin
                rx_busy = 0;
            end

            DATA: begin
                if (sample_done)
                    shift = 1;   // all 8 bits, bit_cnt 0-7
            end

            PARITY: begin
                if (sample_done)
                    parity_load = 1;
            end

            STOP: begin
                if (sample_done)
                    check_stop = 1;
            end
        endcase
    end

endmodule


// UART RX Top Module
module uart_rx (
    input        clk,
    input        rst,
    input        rx_in,
    output [7:0] rx_data,
    output       rx_busy,
    output       data_ready,
    output       parity_error,
    output       stop_bit_error
);

    wire baud_tick;
    wire start_valid;
    wire shift, sample_done, parity_load, check_stop;

    baudgen16 #(.clk_freq(100_000_000), .baud(115200)) u_baud (
        .clk(clk), .rst(rst), .baud_tick(baud_tick));

    uart_rx_fsm u_fsm (
        .clk(clk), .rst(rst), .baud_tick(baud_tick),
        .start_valid(start_valid), .data_ready(data_ready),
        .shift(shift), .sample_done(sample_done),
        .parity_load(parity_load), .check_stop(check_stop),
        .rx_busy(rx_busy));

    uart_rx_datapath u_data (
        .clk(clk), .rst(rst), .rx_in(rx_in), .baud_tick(baud_tick),
        .shift(shift), .sample_done(sample_done),
        .parity_load(parity_load), .check_stop(check_stop),
        .start_valid(start_valid), .data_ready(data_ready),
        .parity_error(parity_error), .stop_bit_error(stop_bit_error),
        .data_out(rx_data));

endmodule
