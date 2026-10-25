`timescale 1ns / 1ps // Defines simulation time steps: 1 unit = 1ns, precision = 1ps

module tb_axi_top;

    // ----------------------------------------------------------------
    // Configuration Parameters
    // ----------------------------------------------------------------
    // These must match the parameters in your design (axi_top)
    parameter addr_width = 4;   // Address bus width (4 bits = 16 locations)
    parameter data_width = 32;  // Data bus width (32 bits)
    parameter depth = 16;       // Memory depth

    // ----------------------------------------------------------------
    // Signal Declarations
    // ----------------------------------------------------------------
    // Inputs to the DUT (Design Under Test) are declared as 'reg' because 
    // we drive them from inside initial/always blocks.
    reg aclk;
    reg aresetn;

    // Write Address Channel Signals
    reg [addr_width-1:0] s_axi_awaddr; // Master sends Write Address
    reg s_axi_awvalid;                 // Master says Address is Valid
    wire s_axi_awready;                // Slave (DUT) says it is Ready

    // Write Data Channel Signals
    reg [data_width-1:0] s_axi_wdata;  // Master sends Write Data
    reg s_axi_wvalid;                  // Master says Data is Valid
    wire s_axi_wready;                 // Slave says it is Ready

    // Write Response Channel Signals
    // Outputs from DUT are 'wire' because the DUT drives them.
    wire [1:0] s_axi_bresp;            // Slave sends Response status
    wire s_axi_bvalid;                 // Slave says Response is Valid
    reg s_axi_bready;                  // Master (TB) says Ready to receive response

    // Read Data Channel Signals
    wire [data_width-1:0] s_axi_rdata; // Slave sends Read Data
    wire [1:0] s_axi_rresp;            // Slave sends Response status
    wire s_axi_rvalid;                 // Slave says Data is Valid
    reg s_axi_rready;                  // Master (TB) says Ready to receive data

    // Read Address Channel Signals
    reg [addr_width-1:0] s_axi_araddr; // Master sends Read Address
    reg s_axi_arvalid;                 // Master says Address is Valid
    wire s_axi_arready;                // Slave says it is Ready

    // ----------------------------------------------------------------
    // Module Instantiation (UUT - Unit Under Test)
    // ----------------------------------------------------------------
    axi_top #(
        .addr_width(addr_width),
        .data_width(data_width),
        .depth(depth)
    ) uut (
        // Connecting Testbench signals to the Module ports
        .aclk(aclk),
        .aresetn(aresetn),
        
        // Write Address Channel
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        
        // Write Data Channel
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        
        // Write Response Channel
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        
        // Read Data Channel
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        
        // Read Address Channel
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready)
    );

    // ----------------------------------------------------------------
    // Clock Generation
    // ----------------------------------------------------------------
    // Invert clock every 5ns. Period = 10ns (100 MHz frequency)
    always #5 aclk = ~aclk;

    // ----------------------------------------------------------------
    // Main Test Sequence
    // ----------------------------------------------------------------
    initial begin
        // 1. Initialize all inputs to known states (0)
        aclk = 0;
        aresetn = 0;          // Assert Reset (Active Low)
        s_axi_awaddr = 0;
        s_axi_awvalid = 0;
        s_axi_wdata = 0;
        s_axi_wvalid = 0;
        s_axi_bready = 0;
        s_axi_araddr = 0;
        s_axi_arvalid = 0;
        s_axi_rready = 0;

        // 2. Apply Reset
        #20 aresetn = 1;      // Release Reset after 20ns
        #10;                  // Wait a bit before starting transactions

        $display("---------------------------------------------------");
        $display("STARTING TESTBENCH");
        $display("---------------------------------------------------");

        // --- TEST CASE 1: Write Operation ---
        // Write the value 0xDEADBEEF into Memory Address 3
        axi_write(4'd3, 32'hDEADBEEF);

        // --- TEST CASE 2: Write Operation ---
        // Write the value 0x12345678 into Memory Address 7
        axi_write(4'd7, 32'h12345678);

        // --- TEST CASE 3: Read Operation (Verify Write 1) ---
        // Read from Address 3. We expect to see 0xDEADBEEF.
        axi_read(4'd3, 32'hDEADBEEF);

        // --- TEST CASE 4: Read Operation (Verify Write 2) ---
        // Read from Address 7. We expect to see 0x12345678.
        axi_read(4'd7, 32'h12345678);

        // --- TEST CASE 5: Read Operation (Verify Default/Clear) ---
        // Read from Address 2 (which we never wrote to).
        // Since we initialized memory to 0 in the RAM design, we expect 0x00000000.
        axi_read(4'd2, 32'h00000000);

        $display("---------------------------------------------------");
        $display("TESTBENCH COMPLETE");
        $display("---------------------------------------------------");
        $finish; // Stop the simulation
    end

    // ----------------------------------------------------------------
    // TASK: AXI WRITE
    // This task simulates the AXI Master behavior for a Write Transaction
    // ----------------------------------------------------------------
    task axi_write;
        input [addr_width-1:0] addr; // Argument: Address to write to
        input [data_width-1:0] data; // Argument: Data to write
        begin
            $display("WRITE START: Addr=0x%h Data=0x%h", addr, data);
            
            // Sync with clock edge to drive signals
            @(posedge aclk);
            
            // --- Address Phase ---
            s_axi_awaddr <= addr; // Put address on bus
            s_axi_awvalid <= 1;   // Assert Address Valid (tell slave address is ready)
            
            // --- Data Phase ---
            // (Simultaneously driving data phase for simplicity)
            s_axi_wdata <= data;  // Put data on bus
            s_axi_wvalid <= 1;    // Assert Data Valid (tell slave data is ready)
            
            // Wait for Slave to be ready for Address (Handshake)
            wait(s_axi_awready);
            @(posedge aclk);      // Move to next clock cycle
            s_axi_awvalid <= 0;   // Deassert Address Valid (Address phase done)
            
            // Wait for Slave to be ready for Data (Handshake)
            wait(s_axi_wready);
            @(posedge aclk);      // Move to next clock cycle
            s_axi_wvalid <= 0;    // Deassert Data Valid (Data phase done)
            
            // --- Response Phase ---
            s_axi_bready <= 1;    // Master says: "I am ready to receive write confirmation"

            // Wait for Slave to send valid response
            wait(s_axi_bvalid);
            @(posedge aclk);
            s_axi_bready <= 0;    // Deassert ready (Transaction complete)

            // Check if the response was "OKAY" (2'b00)
            if (s_axi_bresp == 2'b00)
                $display("WRITE DONE : Response OKAY");
            else
                $display("WRITE FAIL : Response Error");
        end
    endtask

    // ----------------------------------------------------------------
    // TASK: AXI READ
    // This task simulates the AXI Master behavior for a Read Transaction
    // ----------------------------------------------------------------
    task axi_read;
        input [addr_width-1:0] addr;      // Argument: Address to read from
        input [data_width-1:0] exp_data;  // Argument: Expected data (for verification)
        begin
            $display("READ START : Addr=0x%h", addr);
            
            // Sync with clock
            @(posedge aclk);
            
            // --- Address Phase ---
            s_axi_araddr <= addr; // Put read address on bus
            s_axi_arvalid <= 1;   // Assert Read Address Valid
            s_axi_rready <= 1;    // Assert Read Ready (Master is ready to receive data)

            // Wait for Slave to accept Address
            wait(s_axi_arready);
            @(posedge aclk);
            s_axi_arvalid <= 0;   // Deassert Address Valid (Address phase done)

            // --- Data Phase ---
            // Wait for Slave to put valid data on the bus
            wait(s_axi_rvalid);
            @(posedge aclk); // Sample data at the clock edge
            
            // --- Verification ---
            // Check if the data received (s_axi_rdata) matches expected (exp_data)
            // '===' checks for exact match, including X (unknown) or Z (high-Z) states
            if (s_axi_rdata === exp_data) begin
                $display("PASS       : Read 0x%h (Expected 0x%h)", s_axi_rdata, exp_data);
            end else begin
                $display("ERROR      : Read 0x%h (Expected 0x%h)", s_axi_rdata, exp_data);
            end
            
            s_axi_rready <= 0; // Deassert Ready (Transaction complete)
        end
    endtask

endmodule