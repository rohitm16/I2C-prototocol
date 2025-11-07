
`timescale 1ns/1ps

module i2c_slave_core (
    input           clk,
    input           reset,
  
    input           scl_in,
    inout           sda_io,   
    input  [6:0]    my_addr,   
    // Outputs to Translator FSM
    output          addr_match,
    output          rw_bit_out,
    output [7:0]    data_byte_received,
    output          rx_valid,
    output          read_request,
    output          stop_detected,  
    output          scl_drive_out,   
    // Inputs from Translator FSM
    input  [7:0]    data_byte_to_send,
    input           tx_valid,
    input           send_ack_data
);

// FSM States
localparam S_IDLE      = 4'd0;
localparam S_ADDR      = 4'd2;
localparam S_RW_BIT    = 4'd3;
localparam S_ADDR_ACK  = 4'd4;
localparam S_IGNORE    = 4'd5;
localparam S_RX_DATA   = 4'd6;
localparam S_RX_WAIT   = 4'd7; 
localparam S_RX_ACK    = 4'd8;
localparam S_TX_LOAD   = 4'd9;
localparam S_TX_DATA   = 4'd10;
localparam S_TX_ACK    = 4'd11;

reg [3:0] state_reg, state_next;

reg  scl_sync1, scl_sync2, scl_sync;
reg  sda_sync1, sda_sync2, sda_sync;

// for Edge Detection
reg  scl_prev;
wire scl_rise = scl_sync & ~scl_prev;
wire scl_fall = ~scl_sync & scl_prev;

// for START/STOP Condition Detection
reg  sda_prev;
wire start_cond = scl_sync & (~sda_sync & sda_prev); // SCL is high, SDA falls
wire stop_cond  = scl_sync & (sda_sync & ~sda_prev);  // SCL is high, SDA rises

// Shift Registers & Counters
reg [6:0] addr_shift_reg;
reg [7:0] data_shift_reg;
reg [3:0] bit_count;
reg [3:0] bit_count_next;
reg rw_bit_reg, rw_bit_next;

// Output Control
reg sda_drive_low;
reg scl_drive_low;
assign sda_io = (sda_drive_low) ? 1'b0 : 1'bz;
assign scl_drive_out = scl_drive_low;

// Internal Output Registers
reg addr_match_reg, addr_match_next;
reg rx_valid_reg, rx_valid_next;
reg read_request_reg, read_request_next;
reg stop_detected_reg, stop_detected_next;

// next state transition
always @(posedge clk or posedge reset) begin
    if (reset) begin
        scl_sync1 <= 1'b1;
        scl_sync2 <= 1'b1;
        scl_sync  <= 1'b1;
        scl_prev  <= 1'b1;
        
        sda_sync1 <= 1'b1;
        sda_sync2 <= 1'b1;
        sda_sync  <= 1'b1;
        sda_prev  <= 1'b1;
    end
    else begin
        scl_sync1 <= scl_in;
        scl_sync2 <= scl_sync1;
        scl_sync  <= scl_sync2;
        
        sda_sync1 <= sda_io;
        sda_sync2 <= sda_sync1;
        sda_sync  <= sda_sync2;
        
        scl_prev <= scl_sync;
        sda_prev <= sda_sync;
    end
end


// our FSM
always @(posedge clk or posedge reset) begin
    if (reset) begin
        state_reg         <= S_IDLE;
        rw_bit_reg        <= 1'b0;
        addr_match_reg    <= 1'b0;
        rx_valid_reg      <= 1'b0;
        read_request_reg  <= 1'b0;
        stop_detected_reg <= 1'b0;
        bit_count         <= 0;
        addr_shift_reg    <= 0;
        data_shift_reg    <= 0;
    end
    else begin
        state_reg         <= state_next;
        rw_bit_reg        <= rw_bit_next;
        addr_match_reg    <= addr_match_next;
        rx_valid_reg      <= rx_valid_next;
        read_request_reg  <= read_request_next;
        stop_detected_reg <= stop_detected_next;
        bit_count         <= bit_count_next;
        
        if (scl_rise) begin
            if (state_reg == S_ADDR) begin
                addr_shift_reg <= {addr_shift_reg[5:0], sda_sync};
            end
            if (state_reg == S_RX_DATA) begin
                data_shift_reg <= {data_shift_reg[6:0], sda_sync};
            end
        end
        
        if (state_reg == S_TX_LOAD && tx_valid) begin
            data_shift_reg <= data_byte_to_send;
        end
        
        if (scl_fall) begin
            if (state_reg == S_TX_DATA) begin
                data_shift_reg <= {data_shift_reg[6:0], 1'b1};
            end
        end
    end
end

// FSM next-state logic 
always @(*) begin
    state_next         = state_reg;
    bit_count_next     = bit_count;
    rw_bit_next        = rw_bit_reg;
    sda_drive_low      = 1'b0;
    scl_drive_low      = 1'b0; 
    
    addr_match_next    = 1'b0;
    rx_valid_next      = 1'b0;
    read_request_next  = 1'b0;
    stop_detected_next = 1'b0;

    // global reset to set back to IDLE
    if (stop_cond) begin
        stop_detected_next = 1'b1;
        state_next         = S_IDLE;
    end
    else begin
        case (state_reg)
            
            S_IDLE: begin
                if (start_cond) begin
                    state_next     = S_ADDR;
                    bit_count_next = 7;                   
                end
            end
            
            S_ADDR: begin
                if (scl_rise) begin
                    if (bit_count == 1) begin
                        state_next = S_RW_BIT;
                    end else begin
                        bit_count_next = bit_count - 1;
                    end
                end
            end
            
            S_RW_BIT: begin
                if (scl_rise) begin
                    rw_bit_next = sda_sync;
                    state_next  = S_ADDR_ACK;
                end
            end

            S_ADDR_ACK: begin
                if (addr_shift_reg == my_addr) begin
                    sda_drive_low = 1'b1;
                    if (scl_rise) begin
                        addr_match_next = 1'b1;
                        if (rw_bit_reg) begin
                            state_next = S_TX_LOAD;
                        end else begin
                            state_next     = S_RX_DATA;
                            bit_count_next = 8;
                        end
                    end
                end
                else begin
                    if (scl_rise) begin
                        state_next = S_IGNORE;
                    end
                end
            end
            
            S_IGNORE: begin
                
            end

            S_RX_DATA: begin
                if (scl_rise) begin
                    if (bit_count == 1) begin
                        state_next = S_RX_WAIT;
                    end else begin
                        bit_count_next = bit_count - 1;
                    end
                end
            end
            
            S_RX_WAIT: begin
                rx_valid_next = 1'b1;                
                if (send_ack_data) begin
                    state_next = S_RX_ACK;
                end else begin
                    scl_drive_low = 1'b1;
                    state_next = S_RX_WAIT;
                end
            end
            
            S_RX_ACK: begin
                rx_valid_next = 1'b1;
                if (send_ack_data) begin
                    sda_drive_low = 1'b1;
                end                
                if (scl_rise) begin
                    state_next     = S_RX_DATA;
                    bit_count_next = 8;
                end
            end
            
            S_TX_LOAD: begin
                read_request_next = 1'b1;
                if (tx_valid) begin
                    state_next     = S_TX_DATA;
                    bit_count_next = 8;
                end
                sda_drive_low = ~data_byte_to_send[7]; 
            end
            
            S_TX_DATA: begin
                sda_drive_low = ~data_shift_reg[7]; 
                if (scl_rise) begin
                    if (bit_count == 1) begin
                        state_next = S_TX_ACK;
                    end else begin
                        bit_count_next = bit_count - 1;
                    end
                end
            end
            
            S_TX_ACK: begin
                sda_drive_low = 1'b0;
                if (scl_rise) begin
                    if (sda_sync) begin 
                        state_next = S_IDLE; 
                    end else begin 
                        state_next = S_TX_LOAD; 
                    end
                end
            end

            default: begin
                state_next = S_IDLE;
            end

        endcase
    end
end

// outputs 
assign addr_match         = addr_match_reg;
assign rw_bit_out         = rw_bit_reg;
assign data_byte_received = data_shift_reg;
assign rx_valid           = rx_valid_reg;
assign read_request       = read_request_reg;
assign stop_detected      = stop_detected_reg;

endmodule