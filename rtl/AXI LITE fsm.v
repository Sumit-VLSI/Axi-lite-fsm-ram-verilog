`timescale 1ns / 1ps // Sets the time scale for simulation: 1 unit = 1ns, precision = 1ps

// ===========================================================================
// MODULE 1: Write Address Channel (AW) & Write FSM Controller
// ===========================================================================
// This module handles the address handshake (Master -> Slave) and acts as the
// central controller for the entire Write operation state machine.
module axi_aw_channel #(
    parameter addr_width = 4 // Parameter for address width (default 4 bits)
)(
    input  wire aclk,       // System Clock
    input  wire aresetn,    // Active-low Reset
    
    // --- AXI Interface Signals ---
    input  wire [addr_width-1:0] s_axi_awaddr, // Write Address from Master
    input  wire s_axi_awvalid,                 // Master indicates Address is Valid
    output reg  s_axi_awready,                 // Slave indicates it is Ready for Address

    // --- Coordination Signals (Inputs from other modules) ---
    input  wire w_handshake_done, // Signal from W Channel: "Data received"
    input  wire b_handshake_done, // Signal from B Channel: "Response sent"

    // --- Outputs to other modules ---
    output reg [addr_width-1:0] write_addr_reg, // The captured address to send to RAM
    output reg [1:0] write_state                // Current state of the Write FSM
);

    // State definitions for the Finite State Machine (FSM)
    localparam IDLE  = 2'b00; // Waiting for a write request
    localparam WRITE = 2'b01; // Processing write data
    localparam RESP  = 2'b11; // Sending write response

    // Main FSM Logic
    always @(posedge aclk) begin
        if (!aresetn) begin
            // --- Reset Condition ---
            s_axi_awready   <= 1'b0;               // Not ready during reset
            write_addr_reg  <= {addr_width{1'b0}}; // Clear address register
            write_state     <= IDLE;               // Reset state to IDLE
        end else begin
            case (write_state)
                IDLE: begin
                    s_axi_awready <= 1'b1; // Assert Ready: We are ready to accept a new address
                    
                    // Check if Master sent Valid Address AND we are Ready
                    if (s_axi_awvalid && s_axi_awready) begin
                        write_addr_reg <= s_axi_awaddr; // Capture the address from the bus
                        s_axi_awready  <= 1'b0;         // Deassert Ready (block new addresses)
                        write_state    <= WRITE;        // Transition to Data Phase (WRITE state)
                    end
                end

                WRITE: begin
                    // Wait for the Write Data Channel (Module 2) to complete its handshake
                    if (w_handshake_done)
                        write_state <= RESP; // Transition to Response Phase
                end

                RESP: begin
                    // Wait for the Write Response Channel (Module 3) to complete its handshake
                    if (b_handshake_done)
                        write_state <= IDLE; // Transaction complete, return to IDLE
                end

                default: write_state <= IDLE; // Failsafe: Go to IDLE
            endcase
        end
    end
endmodule

// ===========================================================================
// MODULE 2: Write Data Channel (W)
// ===========================================================================
// This module handles capturing the data from the Master and triggering the RAM write.
module axi_w_channel #(
    parameter data_width = 32 // Parameter for data width (default 32 bits)
)(
    input  wire aclk,    // System Clock
    input  wire aresetn, // Active-low Reset
    
    // --- AXI Interface Signals ---
    input  wire [data_width-1:0] s_axi_wdata, // Write Data from Master
    input  wire s_axi_wvalid,                 // Master indicates Data is Valid
    output reg  s_axi_wready,                 // Slave indicates it is Ready for Data

    // --- Inputs from Control (AW Channel) ---
    input  wire [1:0] write_state, // Current state of the Write FSM

    // --- Outputs to RAM and Control ---
    output reg [data_width-1:0] ram_write_data, // Data to be written into RAM
    output reg ram_write_enable,                // Signal to enable writing in RAM
    output wire w_handshake_done                // Signal to AW Channel: "Handshake done"
);
    localparam WRITE = 2'b01; // The state where we expect data

    // Helper logic: Handshake is done when Valid (Master) and Ready (Slave) are both 1
    assign w_handshake_done = s_axi_wvalid && s_axi_wready;

    always @(posedge aclk) begin
        if (!aresetn) begin
            // --- Reset Condition ---
            s_axi_wready     <= 1'b0;               // Not ready
            ram_write_enable <= 1'b0;               // Disable RAM write
            ram_write_data   <= {data_width{1'b0}}; // Clear internal data register
        end else begin
            // Logic only runs when the Main FSM is in 'WRITE' state
            if (write_state == WRITE) begin
                s_axi_wready     <= 1'b1;        // Assert Ready: We can accept data
                ram_write_data   <= s_axi_wdata; // Pass the AXI data to the RAM input
                ram_write_enable <= 1'b1;        // Enable the RAM write signal
            end else begin
                // If not in WRITE state, disable everything
                s_axi_wready     <= 1'b0;
                ram_write_enable <= 1'b0;
            end
        end
    end
endmodule

// ===========================================================================
// MODULE 3: Write Response Channel (B)
// ===========================================================================
// This module handles sending the success/failure status back to the Master.
module axi_b_channel(
    input  wire aclk,    // System Clock
    input  wire aresetn, // Active-low Reset

    // --- AXI Interface Signals ---
    output reg [1:0] s_axi_bresp, // Response Code (00=OK, 10=Error)
    output reg s_axi_bvalid,      // Slave indicates Response is Valid
    input  wire s_axi_bready,     // Master indicates it is Ready for Response

    // --- Inputs from Control (AW Channel) ---
    input  wire [1:0] write_state, // Current state of the Write FSM

    // --- Output to Control ---
    output wire b_handshake_done   // Signal to AW Channel: "Handshake done"
);
    localparam RESP_OKAY = 2'b00; // AXI Code for "Okay"
    localparam RESP      = 2'b11; // The state where we send response

    // Helper logic: Handshake is done when Valid (Slave) and Ready (Master) are both 1
    assign b_handshake_done = s_axi_bvalid && s_axi_bready;

    always @(posedge aclk) begin
        if (!aresetn) begin
            // --- Reset Condition ---
            s_axi_bvalid <= 1'b0;      // Not valid
            s_axi_bresp  <= RESP_OKAY; // Default to OKAY
        end else begin
            // Only active during the RESP state defined by the AW module
            if (write_state == RESP) begin
                s_axi_bvalid <= 1'b1;      // Assert Valid: Response is on the bus
                s_axi_bresp  <= RESP_OKAY; // Send "OKAY" status
            end 
            // If handshake completes, turn off Valid
            else if (b_handshake_done) begin
                s_axi_bvalid <= 1'b0;      // Deassert Valid
            end
        end
    end
endmodule

// ===========================================================================
// MODULE 4: Read Address Channel (AR) & Read FSM Controller
// ===========================================================================
// This module handles the read address handshake and controls the Read FSM.
module axi_ar_channel #(
    parameter addr_width = 4 // Parameter for address width
)(
    input  wire aclk,    // System Clock
    input  wire aresetn, // Active-low Reset

    // --- AXI Interface Signals ---
    input  wire [addr_width-1:0] s_axi_araddr, // Read Address from Master
    input  wire s_axi_arvalid,                 // Master indicates Address is Valid
    output reg  s_axi_arready,                 // Slave indicates it is Ready for Address

    // --- Coordination Signals ---
    input  wire r_handshake_done, // Signal from R Channel: "Data sent"

    // --- Outputs ---
    output reg [addr_width-1:0] read_addr_reg, // Captured address for RAM
    output reg [1:0] read_state                // Current state of Read FSM
);

    // State definitions
    localparam IDLE = 2'b00; // Waiting for read request
    localparam READ = 2'b10; // Accessing RAM
    localparam RESP = 2'b11; // Sending data back

    always @(posedge aclk) begin
        if (!aresetn) begin
            // --- Reset Condition ---
            s_axi_arready   <= 1'b0;               // Not ready
            read_addr_reg   <= {addr_width{1'b0}}; // Clear address register
            read_state      <= IDLE;               // Reset state
        end else begin
            case (read_state)
                IDLE: begin
                    s_axi_arready <= 1'b1; // Assert Ready: We can accept an address
                    
                    // Check if Master sent Valid Address AND we are Ready
                    if (s_axi_arvalid && s_axi_arready) begin
                        read_addr_reg <= s_axi_araddr; // Capture the address
                        s_axi_arready <= 1'b0;         // Deassert Ready
                        read_state    <= READ;         // Transition to READ state
                    end
                end

                READ: begin
                    // We wait 1 cycle here to allow RAM to output data
                    read_state <= RESP; // Move to Response/Data Transfer state
                end

                RESP: begin
                    // Wait for the Read Data Channel (Module 5) to finish sending data
                    if (r_handshake_done)
                        read_state <= IDLE; // Transaction done, return to IDLE
                end

                default: read_state <= IDLE; // Failsafe
            endcase
        end
    end
endmodule

// ===========================================================================
// MODULE 5: Read Data Channel (R)
// ===========================================================================
// This module handles sending the data retrieved from RAM back to the Master.
module axi_r_channel #(
    parameter data_width = 32 // Parameter for data width
)(
    input  wire aclk,    // System Clock
    input  wire aresetn, // Active-low Reset

    // --- AXI Interface Signals ---
    output reg [data_width-1:0] s_axi_rdata, // Read Data sent to Master
    output reg [1:0] s_axi_rresp,            // Response status (OKAY)
    output reg s_axi_rvalid,                 // Slave indicates Data is Valid
    input  wire s_axi_rready,                // Master indicates it is Ready for Data

    // --- Inputs ---
    input  wire [1:0] read_state,           // Current state of Read FSM
    input  wire [data_width-1:0] ram_rdata, // Data coming out of the RAM module

    // --- Output ---
    output wire r_handshake_done // Signal to AR Channel: "Handshake done"
);
    localparam RESP_OKAY = 2'b00; // AXI Code for "Okay"
    localparam READ      = 2'b10; // State where RAM data is valid

    // Helper logic: Handshake is done when Valid (Slave) and Ready (Master) are both 1
    assign r_handshake_done = s_axi_rvalid && s_axi_rready;

    always @(posedge aclk) begin
        if (!aresetn) begin
            // --- Reset Condition ---
            s_axi_rvalid <= 1'b0;               // Not valid
            s_axi_rdata  <= {data_width{1'b0}}; // Clear data
            s_axi_rresp  <= RESP_OKAY;          // Default response
        end else begin
            // If the FSM is in READ state, the data from RAM is ready to be sent
            if (read_state == READ) begin
                s_axi_rdata  <= ram_rdata;  // Put RAM data onto AXI bus
                s_axi_rvalid <= 1'b1;       // Assert Valid
                s_axi_rresp  <= RESP_OKAY;  // Status OKAY
            end 
            // If handshake completes, turn off Valid
            else if (r_handshake_done) begin
                s_axi_rvalid <= 1'b0;       // Deassert Valid
            end
        end
    end
endmodule

// ===========================================================================
// MODULE 6: RAM Design
// ===========================================================================
// This is the actual memory storage.
module ram_design #(
    parameter addr_width = 4, // 4 bits = 16 locations
    parameter data_width = 32, // 32 bits per location
    parameter depth = 16       // Total depth
)(
    input clk,                    // Clock
    input rst_n,                  // Reset
    input wr_enb,                 // Write Enable
    input [addr_width-1:0] addr,  // Address
    input [data_width-1:0] wdata, // Write Data
    output reg [data_width-1:0] rdata // Read Data
);
    reg [data_width-1:0] mem [0:depth-1]; // The memory array
    integer i; // Variable for loop

    always @(*) begin
        if (!rst_n) begin
            // --- Reset Logic ---
            rdata = 0; // Clear output
            // Loop to initialize all memory locations to 0
            for (i = 0; i < depth; i = i + 1) begin
                mem[i] = 0; 
            end
        end else begin
            // --- Normal Operation ---
            if (wr_enb)
                mem[addr] = wdata; // Write data to memory
            else
                rdata = mem[addr]; // Read data from memory
        end
    end
endmodule

// ===========================================================================
// TOP MODULE: AXI TOP (Wiring everything together)
// ===========================================================================
// This module instantiates all the sub-modules and connects them.
module axi_top #(
    parameter addr_width = 4,
    parameter data_width = 32,
    parameter depth = 16
)(
    input aclk,    // System Clock
    input aresetn, // System Reset
    
    // --- Write Address Channel Ports ---
    input [addr_width-1:0] s_axi_awaddr,
    input s_axi_awvalid,
    output s_axi_awready,
    
    // --- Write Data Channel Ports ---
    input [data_width-1:0] s_axi_wdata,
    input s_axi_wvalid,
    output s_axi_wready,
    
    // --- Write Response Channel Ports ---
    output [1:0] s_axi_bresp,
    output s_axi_bvalid,
    input s_axi_bready,
    
    // --- Read Data Channel Ports ---
    output [data_width-1:0] s_axi_rdata,
    output [1:0] s_axi_rresp,
    output s_axi_rvalid,
    input s_axi_rready,
    
    // --- Read Address Channel Ports ---
    input [addr_width-1:0] s_axi_araddr,
    input s_axi_arvalid,
    output s_axi_arready
);

    // --- Internal Wires for Inter-Module Communication ---
    
    // Write Channel Logic Interconnects
    wire [1:0] write_state;             // State passed from AW to W and B channels
    wire [addr_width-1:0] write_addr_reg; // Address passed from AW to RAM Mux
    wire w_handshake_done;              // Signal from W to AW
    wire b_handshake_done;              // Signal from B to AW
    
    // Read Channel Logic Interconnects
    wire [1:0] read_state;              // State passed from AR to R channel
    wire [addr_width-1:0] read_addr_reg; // Address passed from AR to RAM Mux
    wire r_handshake_done;              // Signal from R to AR
    
    // RAM Signals
    wire ram_write_enable;              // Control signal for RAM
    wire [data_width-1:0] ram_write_data; // Data path to RAM
    wire [data_width-1:0] ram_read_data;  // Data path from RAM
    wire [addr_width-1:0] ram_addr;       // Address path to RAM

    localparam WRITE = 2'b01; // Constant for Write State

    // --- Address Mux (Combinational Logic) ---
    // This decides which address goes to the RAM.
    // IF we are writing (write_state == WRITE), use Write Address.
    // ELSE, use Read Address.
    assign ram_addr = (write_state == WRITE) ? write_addr_reg : read_addr_reg;

    // -----------------------------------------------------------------
    // 1. INSTANTIATE WRITE ADDRESS CHANNEL (MASTER CONTROLLER FOR WRITE)
    // -----------------------------------------------------------------
    axi_aw_channel #(.addr_width(addr_width)) u_aw_channel (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .w_handshake_done(w_handshake_done), // Connect input from W Channel
        .b_handshake_done(b_handshake_done), // Connect input from B Channel
        .write_addr_reg(write_addr_reg),     // Connect output to internal wire
        .write_state(write_state)            // Connect output to internal wire
    );

    // -----------------------------------------------------------------
    // 2. INSTANTIATE WRITE DATA CHANNEL
    // -----------------------------------------------------------------
    axi_w_channel #(.data_width(data_width)) u_w_channel (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .write_state(write_state),           // Connect input from AW Channel wire
        .ram_write_data(ram_write_data),     // Connect output to RAM wire
        .ram_write_enable(ram_write_enable), // Connect output to RAM control wire
        .w_handshake_done(w_handshake_done)  // Connect output to internal wire
    );

    // -----------------------------------------------------------------
    // 3. INSTANTIATE WRITE RESPONSE CHANNEL
    // -----------------------------------------------------------------
    axi_b_channel u_b_channel (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .write_state(write_state),           // Connect input from AW Channel wire
        .b_handshake_done(b_handshake_done)  // Connect output to internal wire
    );

    // -----------------------------------------------------------------
    // 4. INSTANTIATE READ ADDRESS CHANNEL (MASTER CONTROLLER FOR READ)
    // -----------------------------------------------------------------
    axi_ar_channel #(.addr_width(addr_width)) u_ar_channel (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .r_handshake_done(r_handshake_done), // Connect input from R Channel
        .read_addr_reg(read_addr_reg),       // Connect output to internal wire
        .read_state(read_state)              // Connect output to internal wire
    );

    // -----------------------------------------------------------------
    // 5. INSTANTIATE READ DATA CHANNEL
    // -----------------------------------------------------------------
    axi_r_channel #(.data_width(data_width)) u_r_channel (
        .aclk(aclk),
        .aresetn(aresetn),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .read_state(read_state),             // Connect input from AR Channel wire
        .ram_rdata(ram_read_data),           // Connect input from RAM wire
        .r_handshake_done(r_handshake_done)  // Connect output to internal wire
    );

    // -----------------------------------------------------------------
    // 6. INSTANTIATE RAM
    // -----------------------------------------------------------------
    ram_design #(.addr_width(addr_width), .data_width(data_width), .depth(depth)) u_ram (
        .clk(aclk),
        .rst_n(aresetn),
        .wr_enb(ram_write_enable),
        .addr(ram_addr),          // Connected to the Mux Logic above
        .wdata(ram_write_data),   // Connected to W Channel output
        .rdata(ram_read_data)     // Connected to R Channel input
    );

endmodule
