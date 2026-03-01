`include"uarttx.v"
`include"uartrx.v"

module uart(
    input clk_tx, clk_rx, rst, tx_start,
    input [7:0] tx_data_in,
    output tx_busy, rx_busy, data_ready, parity_error, stop_bit_error,
    output [7:0] rx_data_out
);

    // serial connection between TX and RX
    wire serial_line;

    // UART Transmitter
    uart_tx_top inst_tx (
        .clk(clk_tx),
        .rst(rst),
        .tx_start(tx_start),
        .tx_data_in(tx_data_in),
        .tx_out(serial_line),
        .tx_busy(tx_busy)
    );

    // UART Receiver
    uart_rx inst_rx (
        .clk(clk_rx),
        .rst(rst),
        .rx_in(serial_line),
        .rx_data(rx_data_out),
        .rx_busy(rx_busy),
        .data_ready(data_ready),
        .parity_error(parity_error),
        .stop_bit_error(stop_bit_error)
    );

endmodule
