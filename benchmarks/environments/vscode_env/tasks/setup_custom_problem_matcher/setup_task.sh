#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Custom Problem Matcher Task ==="

WORKSPACE_DIR="/home/ga/workspace/embedded_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"

# Create sample Verilog files with intentional errors at specific lines

# synthesis_engine.v (error at line 145)
cat > "$WORKSPACE_DIR/src/synthesis_engine.v" << 'EOF'
// Hardware Synthesis Engine
// Verilog HDL Module

module synthesis_engine (
    input wire clk,
    input wire reset,
    input wire [15:0] data_in,
    output reg [7:0] data_out
);

// Module implementation
reg [7:0] internal_reg;
reg [15:0] buffer;

always @(posedge clk or posedge reset) begin
    if (reset) begin
        internal_reg <= 8'b0;
        data_out <= 8'b0;
        buffer <= 16'b0;
    end else begin
        buffer <= data_in;
        // Data processing logic
        internal_reg <= buffer[7:0];
        data_out <= internal_reg;
    end
end

// Additional logic for demonstration
wire [3:0] status;
assign status = internal_reg[3:0];

// State machine
reg [2:0] state;
parameter IDLE = 3'd0;
parameter PROCESS = 3'd1;
parameter WAIT = 3'd2;
parameter DONE = 3'd3;

always @(posedge clk) begin
    case (state)
        IDLE: begin
            if (data_in != 0)
                state <= PROCESS;
        end
        PROCESS: begin
            state <= WAIT;
        end
        WAIT: begin
            state <= DONE;
        end
        DONE: begin
            state <= IDLE;
        end
        default: state <= IDLE;
    endcase
end

// More logic to reach line 145
wire enable_proc;
assign enable_proc = (state == PROCESS);

reg [7:0] counter;
always @(posedge clk) begin
    if (reset)
        counter <= 8'd0;
    else if (enable_proc)
        counter <= counter + 1;
end

// Pipeline registers
reg [7:0] stage1, stage2, stage3;
always @(posedge clk) begin
    stage1 <= internal_reg;
    stage2 <= stage1;
    stage3 <= stage2;
end

// Output multiplexer
reg [7:0] mux_out;
always @(*) begin
    case (state)
        IDLE: mux_out = 8'h00;
        PROCESS: mux_out = stage1;
        WAIT: mux_out = stage2;
        DONE: mux_out = stage3;
        default: mux_out = 8'hFF;
    endcase
end

// Control signals
wire start_processing;
wire processing_complete;
assign start_processing = (state == IDLE) && (data_in != 0);
assign processing_complete = (state == DONE);

// Status register
reg [7:0] status_reg;
always @(posedge clk) begin
    if (reset)
        status_reg <= 8'h00;
    else begin
        status_reg[0] <= start_processing;
        status_reg[1] <= processing_complete;
        status_reg[7:2] <= counter[5:0];
    end
end

// Data path multiplexer
reg [7:0] data_select;
always @(*) begin
    case (status_reg[1:0])
        2'b00: data_select = internal_reg;
        2'b01: data_select = mux_out;
        2'b10: data_select = counter;
        2'b11: data_select = stage3;
    endcase
end

// Final output assignment
// LINE 145: This is where the error occurs - signal width mismatch
assign data_out = data_in;  // ERROR: trying to assign 16-bit to 8-bit

endmodule
EOF

# clock_divider.v (warning at line 89)
cat > "$WORKSPACE_DIR/src/clock_divider.v" << 'EOF'
// Clock Divider Module
// Divides input clock by configurable factor

module clock_divider #(
    parameter DIV_FACTOR = 8
)(
    input wire clk_in,
    input wire reset,
    output reg clk_out
);

reg [15:0] counter;

always @(posedge clk_in or posedge reset) begin
    if (reset) begin
        counter <= 16'd0;
        clk_out <= 1'b0;
    end else begin
        if (counter >= (DIV_FACTOR - 1)) begin
            counter <= 16'd0;
            clk_out <= ~clk_out;
        end else begin
            counter <= counter + 1;
        end
    end
end

// Additional timing logic
reg [7:0] phase_counter;
always @(posedge clk_in) begin
    if (reset)
        phase_counter <= 8'd0;
    else
        phase_counter <= phase_counter + 1;
end

// Clock enable generator
reg clk_enable;
always @(posedge clk_in) begin
    clk_enable <= (counter == 0);
end

// Duty cycle control
parameter DUTY_CYCLE = 50;
reg duty_out;
always @(posedge clk_in) begin
    if (counter < (DIV_FACTOR * DUTY_CYCLE / 100))
        duty_out <= 1'b1;
    else
        duty_out <= 1'b0;
end

// Multiple clock outputs
reg clk_div2, clk_div4, clk_div8;
reg [2:0] div_counter;

always @(posedge clk_in or posedge reset) begin
    if (reset) begin
        div_counter <= 3'd0;
        clk_div2 <= 1'b0;
        clk_div4 <= 1'b0;
        clk_div8 <= 1'b0;
    end else begin
        div_counter <= div_counter + 1;
        if (div_counter[0])
            clk_div2 <= ~clk_div2;
        if (div_counter[1:0] == 2'b11)
            clk_div4 <= ~clk_div4;
        if (div_counter == 3'b111)
            clk_div8 <= ~clk_div8;
    end
end

// Output selection
reg [1:0] output_select;
reg selected_clk;

always @(*) begin
    case (output_select)
        2'b00: selected_clk = clk_div2;
        2'b01: selected_clk = clk_div4;
        2'b10: selected_clk = clk_div8;
        2'b11: selected_clk = clk_out;
    endcase
end

// LINE 89: Timing constraint warning occurs here
// This path may not meet timing at high frequencies
assign clk_out = (clk_enable && duty_out && selected_clk) ? clk_in : 1'b0;

endmodule
EOF

# memory_controller.v (error at line 234)
cat > "$WORKSPACE_DIR/src/memory_controller.v" << 'EOF'
// Memory Controller Module
// Handles read/write operations to external memory

module memory_controller #(
    parameter ADDR_WIDTH = 16,
    parameter DATA_WIDTH = 32
)(
    input wire clk,
    input wire reset,
    input wire read_enable,
    input wire write_enable,
    input wire [ADDR_WIDTH-1:0] address,
    input wire [DATA_WIDTH-1:0] write_data,
    output reg [DATA_WIDTH-1:0] read_data,
    output reg ready,
    output reg error
);

// State machine states
localparam IDLE = 3'd0;
localparam READ_REQUEST = 3'd1;
localparam READ_WAIT = 3'd2;
localparam READ_COMPLETE = 3'd3;
localparam WRITE_REQUEST = 3'd4;
localparam WRITE_WAIT = 3'd5;
localparam WRITE_COMPLETE = 3'd6;
localparam ERROR_STATE = 3'd7;

reg [2:0] state, next_state;

// Internal registers
reg [ADDR_WIDTH-1:0] addr_reg;
reg [DATA_WIDTH-1:0] data_reg;
reg [3:0] wait_counter;

// Memory interface signals
wire mem_ready;
wire mem_error;
reg mem_read_req;
reg mem_write_req;

// State register
always @(posedge clk or posedge reset) begin
    if (reset)
        state <= IDLE;
    else
        state <= next_state;
end

// Next state logic
always @(*) begin
    next_state = state;
    case (state)
        IDLE: begin
            if (read_enable)
                next_state = READ_REQUEST;
            else if (write_enable)
                next_state = WRITE_REQUEST;
        end
        READ_REQUEST: begin
            next_state = READ_WAIT;
        end
        READ_WAIT: begin
            if (mem_ready)
                next_state = READ_COMPLETE;
            else if (wait_counter > 10)
                next_state = ERROR_STATE;
        end
        READ_COMPLETE: begin
            next_state = IDLE;
        end
        WRITE_REQUEST: begin
            next_state = WRITE_WAIT;
        end
        WRITE_WAIT: begin
            if (mem_ready)
                next_state = WRITE_COMPLETE;
            else if (wait_counter > 10)
                next_state = ERROR_STATE;
        end
        WRITE_COMPLETE: begin
            next_state = IDLE;
        end
        ERROR_STATE: begin
            next_state = IDLE;
        end
    endcase
end

// Output logic
always @(posedge clk or posedge reset) begin
    if (reset) begin
        read_data <= {DATA_WIDTH{1'b0}};
        ready <= 1'b0;
        error <= 1'b0;
        addr_reg <= {ADDR_WIDTH{1'b0}};
        data_reg <= {DATA_WIDTH{1'b0}};
        wait_counter <= 4'd0;
        mem_read_req <= 1'b0;
        mem_write_req <= 1'b0;
    end else begin
        // Default values
        ready <= 1'b0;
        error <= 1'b0;
        mem_read_req <= 1'b0;
        mem_write_req <= 1'b0;
        
        case (state)
            IDLE: begin
                wait_counter <= 4'd0;
                if (read_enable)
                    addr_reg <= address;
                else if (write_enable) begin
                    addr_reg <= address;
                    data_reg <= write_data;
                end
            end
            READ_REQUEST: begin
                mem_read_req <= 1'b1;
            end
            READ_WAIT: begin
                wait_counter <= wait_counter + 1;
                if (mem_ready)
                    read_data <= data_reg;
            end
            READ_COMPLETE: begin
                ready <= 1'b1;
            end
            WRITE_REQUEST: begin
                mem_write_req <= 1'b1;
            end
            WRITE_WAIT: begin
                wait_counter <= wait_counter + 1;
            end
            WRITE_COMPLETE: begin
                ready <= 1'b1;
            end
            ERROR_STATE: begin
                error <= 1'b1;
            end
        endcase
    end
end

// Address decoder
reg [3:0] chip_select;
always @(*) begin
    case (address[ADDR_WIDTH-1:ADDR_WIDTH-4])
        4'h0: chip_select = 4'b0001;
        4'h1: chip_select = 4'b0010;
        4'h2: chip_select = 4'b0100;
        4'h3: chip_select = 4'b1000;
        default: chip_select = 4'b0000;
    endcase
end

// Bank controller
reg [1:0] active_bank;
always @(posedge clk) begin
    if (reset)
        active_bank <= 2'b00;
    else if (state == IDLE)
        active_bank <= address[15:14];
end

// Refresh counter
reg [7:0] refresh_counter;
reg refresh_req;
always @(posedge clk or posedge reset) begin
    if (reset) begin
        refresh_counter <= 8'd0;
        refresh_req <= 1'b0;
    end else begin
        refresh_counter <= refresh_counter + 1;
        refresh_req <= (refresh_counter == 8'd255);
    end
end

// Data path controller
reg [DATA_WIDTH-1:0] data_buffer;
always @(posedge clk) begin
    if (mem_ready)
        data_buffer <= read_data;
end

// Burst controller
reg [3:0] burst_counter;
reg burst_active;
always @(posedge clk or posedge reset) begin
    if (reset) begin
        burst_counter <= 4'd0;
        burst_active <= 1'b0;
    end else begin
        if (state == READ_REQUEST || state == WRITE_REQUEST) begin
            burst_active <= 1'b1;
            burst_counter <= 4'd0;
        end else if (burst_active) begin
            burst_counter <= burst_counter + 1;
            if (burst_counter == 4'd15)
                burst_active <= 1'b0;
        end
    end
end

// LINE 234: This is where the error occurs - undefined signal
assign mem_ready = (wait_counter < 5) && !addr_bus[0];  // ERROR: addr_bus is not defined

endmodule
EOF

# Create build.sh script that simulates hwc compiler
cat > "$WORKSPACE_DIR/build.sh" << 'EOF'
#!/bin/bash
# Simulates the proprietary hwc (hardware compiler) output
echo "[HWC-INFO] Hardware Compiler v3.2.1"
echo "[HWC-INFO] Starting compilation of Verilog sources..."
echo ""
echo "[HWC-ERROR] synthesis_engine.v:145:23 - Signal width mismatch: expected 8 bits, got 16"
echo "[HWC-WARN] clock_divider.v:89:5 - Timing constraint may not be met at frequencies above 100MHz"
echo "[HWC-ERROR] memory_controller.v:234:12 - Undefined signal reference: addr_bus"
echo ""
echo "[HWC-INFO] Compilation failed with 2 errors, 1 warning"
echo "[HWC-INFO] Total time: 1.23 seconds"
exit 1
EOF

chmod +x "$WORKSPACE_DIR/build.sh"

# Create README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Embedded Hardware Project

This project uses a proprietary hardware compiler called `hwc` for Verilog synthesis.

## Building

Run the build script: