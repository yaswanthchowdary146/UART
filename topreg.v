`include"rxreg.v"
`include"txreg.v"
`include"uartfull.v"

module top_128bit_uart (
    input  wire         clk_tx,
    input  wire         clk_rx,
    input  wire         rst,

    // user side
    input  wire [127:0] tx_data_in,      // 128-bit data to send
    input  wire         send_start,      // user pulses this to start TX

    output wire [127:0] rx_data_out,     // 128-bit received data
    output wire         rx_128_done,     // 128-bit word fully received
    output wire         tx_128_done,     // 128-bit word fully transmitted

    // pass-through error signals
    output wire         parity_error,
    output wire         stop_bit_error
);

    //--------------------------------------------------
    // internal wires
    //--------------------------------------------------

    // TX shift reg <-> UART
    wire [7:0]  tx_byte;
    wire        tx_valid;
    wire        tx_sr_done;

    // RX shift reg <-> UART
    wire [7:0]  rx_byte;
    wire        data_ready;
    wire        rx_busy;

    // UART control
    wire        tx_busy;
    reg         tx_start;

    // FSM derived signals
    reg         load;
    reg         shift;

    // tx_busy edge detection (to detect tx_done = tx_busy falling edge)
    reg         tx_busy_prev;
    wire        tx_done;   // single cycle pulse when byte finishes sending

    //--------------------------------------------------
    // tx_busy falling edge detector → tx_done
    //--------------------------------------------------
    always @(posedge clk_tx or posedge rst) begin
        if (rst)
            tx_busy_prev <= 1'b0;
        else
            tx_busy_prev <= tx_busy;
    end

    assign tx_done = (tx_busy_prev == 1'b1) && (tx_busy == 1'b0);

    //--------------------------------------------------
    // TX FSM
    //--------------------------------------------------
    localparam TX_IDLE    = 2'd0;
    localparam TX_LOAD    = 2'd1;
    localparam TX_SEND    = 2'd2;
    localparam TX_WAIT    = 2'd3;

    reg [1:0] tx_state;

    always @(posedge clk_tx or posedge rst) begin
        if (rst) begin
            tx_state  <= TX_IDLE;
            load      <= 1'b0;
            shift     <= 1'b0;
            tx_start  <= 1'b0;
        end

        else begin
            // default pulse signals to 0 every cycle
            load     <= 1'b0;
            shift    <= 1'b0;
            tx_start <= 1'b0;

            case (tx_state)

                // wait for user to request a transfer
                TX_IDLE: begin
                    if (send_start) begin
                        load     <= 1'b1;   // latch 128-bit data into shift reg
                        tx_state <= TX_LOAD;
                    end
                end

                // one cycle for shift reg to load and present first byte
                TX_LOAD: begin
                    tx_start <= 1'b1;       // tell UART to send first byte
                    tx_state <= TX_WAIT;
                end

                // wait for UART to finish sending current byte
                TX_WAIT: begin
                    if (tx_done) begin
                        if (tx_sr_done) begin
                            // all 16 bytes sent
                            tx_state <= TX_IDLE;
                        end
                        else begin
                            shift    <= 1'b1;   // shift reg moves to next byte
                            tx_state <= TX_SEND;
                        end
                    end
                end

                // one cycle for shift reg to present next byte, then start UART
                TX_SEND: begin
                    tx_start <= 1'b1;       // send next byte
                    tx_state <= TX_WAIT;
                end

            endcase
        end
    end

    assign tx_128_done = (tx_state == TX_WAIT) && tx_done && tx_sr_done;

    //--------------------------------------------------
    // TX Shift Register instance
    //--------------------------------------------------
    tx_shift_reg u_tx_sr (
        .clk      (clk_tx),
        .rst      (rst),
        .load     (load),
        .shift    (shift),
        .data_in  (tx_data_in),
        .tx_byte  (tx_byte),
        .tx_valid (tx_valid),
        .done     (tx_sr_done)
    );

    //--------------------------------------------------
    // RX Shift Register instance
    //--------------------------------------------------
    rx_shift_reg u_rx_sr (
        .clk      (clk_rx),
        .rst      (rst),
        .rx_valid (data_ready),   // data_ready from UART = byte received
        .rx_byte  (rx_byte),
        .data_out (rx_data_out),
        .done     (rx_128_done)
    );

    //--------------------------------------------------
    // UART instance
    //--------------------------------------------------
    uart u_uart (
        .clk_tx        (clk_tx),
        .clk_rx        (clk_rx),
        .rst           (rst),
        .tx_start      (tx_start),
        .tx_data_in    (tx_byte),        // always fed from shift register
        .tx_busy       (tx_busy),
        .rx_busy       (rx_busy),
        .data_ready    (data_ready),
        .parity_error  (parity_error),
        .stop_bit_error(stop_bit_error),
        .rx_data_out   (rx_byte)
    );

endmodule
