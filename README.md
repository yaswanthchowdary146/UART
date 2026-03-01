# UART
# UART – 8-bit UART with 128-bit Shift Register (Verilog)

A synthesisable Verilog implementation of a full-duplex **8-bit UART** paired with **128-bit TX/RX shift registers**, allowing an entire 128-bit word to be streamed serially as 16 consecutive bytes. Designed for FPGA targets (default: 100 MHz clock, 115200 baud).

---

## Features

- Full-duplex UART with separate TX and RX clock inputs
- **Odd/Even parity generation (TX) and checking (RX)**
- Start bit, 8 data bits, 1 parity bit, 1 stop bit per frame
- Configurable baud rate via `baudgen` parameters (`clk_freq`, `baud`)
- 128-bit TX shift register: loads a 128-bit word and feeds it byte-by-byte to the UART
- 128-bit RX shift register: assembles incoming bytes back into a 128-bit word
- FSM-controlled sequencing in both TX top-level and 128-bit wrapper
- Error flags: `parity_error`, `stop_bit_error`
- Done flags: `tx_128_done`, `rx_128_done`

---

## Repository Structure

```
uart/
├── uarttx.v        # UART Transmitter (PISO shift reg, parity gen, baud gen, FSM)
├── uartrx.v        # UART Receiver (SIPO shift reg, parity check, FSM)
├── uartfull.v      # UART top-level: connects TX and RX on a shared serial line
├── txreg.v         # 128-bit TX shift register (parallel-load, byte-serial-out)
├── rxreg.v         # 128-bit RX shift register (byte-serial-in, parallel-out)
├── topreg.v        # Top-level: 128-bit UART system integrating all modules
└── regtb.v         # Testbench for the 128-bit UART system
```

---

## Architecture

```
         ┌─────────────┐    8-bit    ┌──────────────┐   serial   ┌──────────────┐   8-bit   ┌─────────────┐
128-bit  │  TX Shift   │──────────▶ │  uart_tx_top │──────────▶ │  uart_rx     │──────────▶│  RX Shift   │  128-bit
data_in ▶│  Register   │            │  (FSM+PISO   │            │  (FSM+SIPO  │           │  Register   │▶ data_out
         │  (txreg.v)  │            │  +baudgen)   │            │  +checker)  │           │  (rxreg.v)  │
         └─────────────┘            └──────────────┘            └──────────────┘           └─────────────┘
              ▲                            ▲
              │  load / shift              │ tx_start / tx_done
              └──────────── Top FSM (topreg.v) ───────────────────────────────────────────
```

The top-level `top_128bit_uart` contains a small 4-state FSM (`TX_IDLE → TX_LOAD → TX_WAIT → TX_SEND`) that orchestrates loading the shift register and triggering the UART for each of the 16 bytes.

---

## Frame Format

Each byte is transmitted as an 11-bit serial frame:

```
[ START (0) | D0 D1 D2 D3 D4 D5 D6 D7 | PARITY | STOP (1) ]
```

Parity is computed as the XOR reduction of all 8 data bits (even parity by default).

---

## Port Reference

### `top_128bit_uart` (topreg.v) — Top-Level

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk_tx` | input | 1 | TX clock |
| `clk_rx` | input | 1 | RX clock |
| `rst` | input | 1 | Active-high synchronous reset |
| `tx_data_in` | input | 128 | 128-bit data word to transmit |
| `send_start` | input | 1 | Pulse high for one cycle to begin transmission |
| `rx_data_out` | output | 128 | 128-bit assembled received data |
| `rx_128_done` | output | 1 | High when all 16 bytes have been received |
| `tx_128_done` | output | 1 | High when all 16 bytes have been transmitted |
| `parity_error` | output | 1 | Parity mismatch detected on received byte |
| `stop_bit_error` | output | 1 | Invalid stop bit detected |

### `uart` (uartfull.v) — UART Core

| Port | Direction | Width | Description |
|---|---|---|---|
| `clk_tx` / `clk_rx` | input | 1 | Separate clocks for TX and RX |
| `rst` | input | 1 | Reset |
| `tx_start` | input | 1 | Trigger to send `tx_data_in` |
| `tx_data_in` | input | 8 | Byte to transmit |
| `tx_busy` | output | 1 | High while transmitting |
| `rx_busy` | output | 1 | High while receiving |
| `data_ready` | output | 1 | High for one cycle when a byte is received |
| `parity_error` | output | 1 | Parity error flag |
| `stop_bit_error` | output | 1 | Stop bit error flag |
| `rx_data_out` | output | 8 | Received byte |

---

## Configuration

Baud rate and clock frequency are set as parameters in the `baudgen` module inside `uarttx.v`:

```verilog
baudgen #(.clk_freq(100_000_000), .baud(115200)) u_baud ( ... );
```

Change `clk_freq` to match your target clock and `baud` to your desired baud rate. Common values: `9600`, `19200`, `57600`, `115200`.

---

## Simulation

The testbench `regtb.v` instantiates `top_128bit_uart` and drives a 128-bit test vector. Run with any Verilog simulator, for example:

```bash
# Icarus Verilog
iverilog -o sim regtb.v topreg.v uartfull.v uarttx.v uartrx.v txreg.v rxreg.v
vvp sim
```

Or with ModelSim/Questa/Vivado Simulator, add all source files to the project and set `regtb` as the top module.

---

## How It Works — Transmitting 128 bits

1. User places 128-bit data on `tx_data_in` and pulses `send_start`.
2. The top FSM asserts `load`, latching the data into the TX shift register.
3. The FSM asserts `tx_start` to begin sending **byte 0** (bits [7:0]) via the UART.
4. When the UART completes the byte (`tx_busy` falls), the FSM asserts `shift` to advance the register by one byte and then triggers the UART again.
5. Steps 3–4 repeat for all 16 bytes. `tx_128_done` pulses when the last byte finishes.

## How It Works — Receiving 128 bits

1. Each time the UART asserts `data_ready`, the RX shift register captures the received byte and shifts it in.
2. After 16 bytes, `rx_128_done` is asserted and `rx_data_out` holds the complete 128-bit word.

---

## License

This project is open-source. Feel free to use and modify it for personal or academic purposes.
