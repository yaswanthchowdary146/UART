`include"topreg.v"

module tb_top_128bit_uart;

    reg         clk;
    reg         rst;
    reg         send_start;
    reg [127:0] tx_data_in;

    wire [127:0] rx_data_out;
    wire         tx_128_done;
    wire         rx_128_done;
    wire         parity_error;
    wire         stop_bit_error;

    // 100 MHz clock → period = 10ns
    always #5 clk = ~clk;

    // instantiate DUT
    top_128bit_uart dut (
        .clk_tx        (clk),
        .clk_rx        (clk),
        .rst           (rst),
        .send_start    (send_start),
        .tx_data_in    (tx_data_in),
        .rx_data_out   (rx_data_out),
        .rx_128_done   (rx_128_done),
        .tx_128_done   (tx_128_done),
        .parity_error  (parity_error),
        .stop_bit_error(stop_bit_error)
    );

    // timeout limit
    // 100MHz clock, typical UART 115200 baud
    // one bit = 100_000_000/115200 = ~868 cycles
    // one frame = 10 bits * 868 = ~8680 cycles
    // 16 frames = 16 * 8680 = ~138880 cycles
    // give 2x margin
    localparam TIMEOUT_LIMIT = 300000;

    integer timeout_count;

    initial begin
        // initialise
        clk           = 0;
        rst           = 1;
        send_start    = 0;
        tx_data_in    = 128'h0;
        timeout_count = 0;

        // hold reset for 10 cycles
        repeat(10) @(posedge clk);
        rst = 0;

        // wait 2 cycles then load data and pulse send_start
        repeat(2) @(posedge clk);
        tx_data_in = 128'hDEADBEEF_CAFEBABE_12345678_AABBCCDD;
        send_start = 1;
        @(posedge clk);
        send_start = 0;

        $display("TB [%0t]: send_start pulsed, data = %h", $time, tx_data_in);
        $display("TB [%0t]: waiting for completion...", $time);

        // safe wait loop with timeout
        while (timeout_count < TIMEOUT_LIMIT) begin
            @(posedge clk);
            timeout_count = timeout_count + 1;

            if (tx_128_done)
                $display("TB [%0t]: tx_128_done asserted", $time);

            if (rx_128_done) begin
                $display("TB [%0t]: rx_128_done asserted", $time);
                $display("------------------------------------------");
                $display("TX data : %h", tx_data_in);
                $display("RX data : %h", rx_data_out);

                if (rx_data_out === tx_data_in)
                    $display("RESULT  : PASS - data matched!");
                else
                    $display("RESULT  : FAIL - mismatch!");

                $display("------------------------------------------");

                if (parity_error)   $display("WARNING : parity error!");
                if (stop_bit_error) $display("WARNING : stop bit error!");

                timeout_count = TIMEOUT_LIMIT; // force exit
            end
        end

        if (!rx_128_done)
            $display("TB [%0t]: TIMEOUT - rx_128_done never received!", $time);

        $finish;
    end

    // waveform dump
    initial begin
        $dumpfile("tb_uart128.vcd");
        $dumpvars(0, tb_top_128bit_uart);
    end

endmodule
