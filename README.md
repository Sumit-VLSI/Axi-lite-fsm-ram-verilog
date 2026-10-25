# FSM-Based AXI4-Lite RAM Controller (Verilog)

A simplified **AXI4-Lite slave that reads and writes a small RAM**, built around two **finite state machines**: one for the write path and one for the read path. The five AXI channels (AW, W, B, AR, R) are separate Verilog modules that coordinate through the FSM state and handshake-done signals. A task-based testbench plays the role of the AXI master.

Simulated and verified in **Xilinx Vivado**.

> This is the FSM-based version of my AXI4-Lite RAM wrapper. The other version uses handshake flags and supports byte-strobe writes: [axi-lite-ram-wrapper-verilog](https://github.com/YOUR-USERNAME/axi-lite-ram-wrapper-verilog).

---

## Features

- AXI4-Lite slave with all five channels: AW, W, B, AR, R
- **Write FSM** in `axi_aw_channel` (IDLE, WRITE, RESP) and **Read FSM** in `axi_ar_channel` (IDLE, READ, RESP)
- Standard VALID/READY handshakes, with registered READY signals
- Address mux selects the write address while a write is in progress, otherwise the read address
- Parameterized address width, data width, and RAM depth
- Task-based testbench (`axi_write`, `axi_read`) that checks every read against its expected value

| Parameter | Default | Description |
|-----------|---------|-------------|
| `addr_width` | 4 | Address width in bits |
| `data_width` | 32 | Data width in bits |
| `depth` | 16 | Number of RAM words (should equal 2^`addr_width`) |

---

## Architecture

<img width="2250" height="1350" alt="axi_fsm_architecture" src="https://github.com/user-attachments/assets/d5123b50-3d64-4d02-a109-e26b793c4c01" />


### Module hierarchy

```
axi_top                    (top level + address mux)
├── axi_aw_channel         AW handshake + WRITE FSM controller
├── axi_w_channel          W handshake, drives RAM write data and enable
├── axi_b_channel          B response (OKAY)
├── axi_ar_channel         AR handshake + READ FSM controller
├── axi_r_channel          R data and response (OKAY)
└── ram_design             16 x 32-bit single-port RAM
```

| Module | Role |
|--------|------|
| `axi_aw_channel` | Accepts the write address, owns `write_state`, moves the FSM forward when W and B handshakes finish |
| `axi_w_channel` | Asserts `WREADY` in the WRITE state, passes data to the RAM and raises `ram_write_enable` |
| `axi_b_channel` | Asserts `BVALID` in the RESP state, always with `BRESP = OKAY` |
| `axi_ar_channel` | Accepts the read address, owns `read_state`, returns to IDLE when the R handshake finishes |
| `axi_r_channel` | Captures RAM data in the READ state and holds `RVALID` until `RREADY` |
| `ram_design` | Single-port memory: one address input shared by reads and writes |

---

## State Machines

<img width="2250" height="900" alt="axi_fsm_states" src="https://github.com/user-attachments/assets/158bfa70-b6dd-4bca-b17c-76477b66be75" />


**Write FSM** (state encodings from the RTL)

| State | Code | What happens | Next state |
|-------|------|--------------|------------|
| IDLE | `2'b00` | `AWREADY = 1`, waits for `AWVALID` | WRITE on `AWVALID & AWREADY` (address is latched) |
| WRITE | `2'b01` | W channel asserts `WREADY` and `ram_write_enable` | RESP on `w_handshake_done` |
| RESP | `2'b11` | B channel asserts `BVALID` | IDLE on `b_handshake_done` |

**Read FSM**

| State | Code | What happens | Next state |
|-------|------|--------------|------------|
| IDLE | `2'b00` | `ARREADY = 1`, waits for `ARVALID` | READ on `ARVALID & ARREADY` (address is latched) |
| READ | `2'b10` | R channel captures RAM data and asserts `RVALID` | RESP after one cycle |
| RESP | `2'b11` | `RVALID` held until the master is ready | IDLE on `r_handshake_done` |

---

## Port Description

| Channel | Signal | Dir | Width |
|---------|--------|-----|-------|
| Global | `aclk`, `aresetn` (active low) | in | 1 |
| AW | `s_axi_awaddr` | in | `addr_width` |
| AW | `s_axi_awvalid` / `s_axi_awready` | in / out | 1 |
| W | `s_axi_wdata` | in | `data_width` |
| W | `s_axi_wvalid` / `s_axi_wready` | in / out | 1 |
| B | `s_axi_bresp` | out | 2 |
| B | `s_axi_bvalid` / `s_axi_bready` | out / in | 1 |
| AR | `s_axi_araddr` | in | `addr_width` |
| AR | `s_axi_arvalid` / `s_axi_arready` | in / out | 1 |
| R | `s_axi_rdata` | out | `data_width` |
| R | `s_axi_rresp` | out | 2 |
| R | `s_axi_rvalid` / `s_axi_rready` | out / in | 1 |

---

## Repository Structure

```
axi-lite-fsm-ram-verilog/
├── rtl/
│   └── axi_top.v                # top + channel modules + RAM
├── tb/
│   └── tb_axi_top.v             # self-checking testbench (AXI master)
├── docs/
│   ├── axi_fsm_architecture.png
│   ├── axi_fsm_states.png
│   ├── simulation_output.png
│   ├── waveform.png
│   └── schematic.png
└── README.md
```

---

## Verification

The testbench drives the master side of the interface. `axi_write` raises the address and data valids, waits for each READY, then waits for the write response and checks `BRESP`. `axi_read` issues the address, waits for `RVALID`, and compares `RDATA` with the expected value using `===`.



Clock: 100 MHz (10 ns period).

### Console output

<img width="522" height="323" alt="Screenshot 2026-10-26 004105" src="https://github.com/user-attachments/assets/0e285eca-c59e-4fd6-b1b4-7ebf849e099d" />


```
---------------------------------------------------
STARTING TESTBENCH
---------------------------------------------------
WRITE START: Addr=0x3 Data=0xdeadbeef
WRITE DONE : Response OKAY
WRITE START: Addr=0x7 Data=0x12345678
WRITE DONE : Response OKAY
READ START : Addr=0x3
PASS       : Read 0xdeadbeef (Expected 0xdeadbeef)
READ START : Addr=0x7
PASS       : Read 0x12345678 (Expected 0x12345678)
READ START : Addr=0x2
PASS       : Read 0x00000000 (Expected 0x00000000)

```

### Simulation waveform
<img width="1912" height="1015" alt="Screenshot 2026-10-26 004052" src="https://github.com/user-attachments/assets/fa1d9f04-df68-4b6f-80e2-4c11ae0634a9" />


### RTL schematic (Vivado)
<img width="1570" height="666" alt="Screenshot 2026-10-26 004202" src="https://github.com/user-attachments/assets/6fd57228-18ff-49dc-b348-972e3ecd60f4" />


---

## How to Run (Vivado)

1. Create a new RTL project in Vivado
2. Add `rtl/axi_top.v` as a **design source** (top module: `axi_top`)
3. Add `tb/tb_axi_top.v` as a **simulation source** and set `tb_axi_top` as the simulation top
4. Click **Run Simulation → Run Behavioral Simulation**
5. Run for about 1 µs and read the Tcl console for the `PASS` messages

---

## Tools Used

- Verilog HDL
- Xilinx Vivado (behavioral simulation, elaborated schematic)

---

## Limitations and Future Work

This version trades features for simplicity. Known limitations:

- **No `WSTRB`:** only full 32-bit word writes. The [handshake-flag version](https://github.com/YOUR-USERNAME/axi-lite-ram-wrapper-verilog) supports byte strobes.
- **One transaction at a time**, and the address phase must complete before data is accepted.
- **Single-port RAM:** reads and writes share one address bus, so a read and a write must not overlap.
- The address is used as a **word index** (4 bits select one of 16 words), not a byte address.
- `BRESP` and `RRESP` are always OKAY; there is no error response. `AWPROT` / `ARPROT` are not implemented.
- The RAM is a simple behavioral model (clocked write, combinational read) and has not been synthesized yet.
- Testbench is directed and has no final PASS/FAIL counter.

Possible next steps: add `WSTRB`, add a dual-port RAM so reads and writes can overlap, randomize `BREADY` / `RREADY` delays, add protocol assertions, and run FPGA synthesis.

---

## Author

**Sumit**
RTL Design | Verilog | AXI | FPGA
## References

- Arm, *AMBA AXI and ACE Protocol Specification* (AXI4-Lite section)
