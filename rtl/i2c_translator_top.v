`timescale 1ns/1ps
`include "i2c_defines.v"

module i2c_translator_top #(
    parameter VIRTUAL_ADDR = 7'h5A, 
    parameter REAL_ADDR    = 7'h3C, 
    
    parameter SYS_CLK_FREQ = 50_000_000,  // System clock - 50 MHz
    parameter I2C_FREQ     = 100_000      // I2C clock - 100 kHz
)(
    input  clk,
    input  reset,
    
    inout  master_bus_sda,
    inout  master_bus_scl,
    
    inout  slave_bus_sda,
    output slave_bus_scl
);

// FSM States 
localparam T_IDLE             = 4'd0;
localparam T_START_MASTER     = 4'd1;
localparam T_SEND_REAL_ADDR   = 4'd2;
localparam T_PASSTHRU_WRITE   = 4'd3;
localparam T_PASSTHRU_READ    = 4'd4;
localparam T_STOP_MASTER      = 4'd5;

reg [3:0] state_reg, state_next;

// Wires connecting to i2c_slave_core 
wire        slave_addr_match;
wire [7:0]  slave_rx_data;
wire        slave_rx_valid;
wire        slave_read_req;
wire        slave_stop_detected;
wire        slave_rw_bit_out;

wire        slave_scl_drive;

reg  [7:0]  slave_tx_data;
reg         slave_tx_valid;
reg         slave_send_ack_data;

reg         rw_bit_latched;

// Wires connecting to i2c_master 
reg  [7:0]  master_din;
reg  [2:0]  master_cmd;
reg         master_wr_i2c;

wire        master_ready;
wire        master_done_tick;
wire        master_ack;
wire [7:0]  master_dout;

localparam I2C_DVSR = (SYS_CLK_FREQ / I2C_FREQ) / 4;

assign master_bus_scl = (slave_scl_drive) ? 1'b0 : 1'bz;


i2c_slave_core u_slave (
    .clk(clk), 
    .reset(reset),
    .scl_in(master_bus_scl),
    .sda_io(master_bus_sda),
    .my_addr(VIRTUAL_ADDR),
    
    .addr_match(slave_addr_match),
    .rw_bit_out(slave_rw_bit_out),
    .data_byte_received(slave_rx_data),
    .rx_valid(slave_rx_valid),
    .read_request(slave_read_req),
    .stop_detected(slave_stop_detected),
    
    .scl_drive_out(slave_scl_drive),
    
    .data_byte_to_send(slave_tx_data),
    .tx_valid(slave_tx_valid),
    .send_ack_data(slave_send_ack_data)
);

i2c_master u_master (
    .clk(clk), 
    .reset(reset),
    .din(master_din),
    .dvsr(I2C_DVSR),
    .cmd(master_cmd),
    .wr_i2c(master_wr_i2c),
    
    .scl(slave_bus_scl),
    .sda(slave_bus_sda),
    
    .ready(master_ready),
    .done_tick(master_done_tick),
    .ack(master_ack),
    .dout(master_dout)
);


// translator FSM
always @(posedge clk or posedge reset) begin
    if (reset) begin
        state_reg <= T_IDLE;
        rw_bit_latched <= 1'b0;
    end
    else begin
        state_reg <= state_next;
        if (state_reg == T_IDLE && slave_addr_match) begin
            rw_bit_latched <= slave_rw_bit_out;
        end
    end
end


//  for control signal
always @(*) begin
    state_next          = state_reg;
    master_cmd          = `I2C_CMD_START; 
    master_din          = 8'b0;
    master_wr_i2c       = 1'b0;        
    slave_tx_data       = 8'b0;
    slave_tx_valid      = 1'b0;
    
    slave_send_ack_data = 1'b0; 

    case (state_reg)
        
        T_IDLE: begin
           if (slave_addr_match) begin
                state_next = T_START_MASTER;
            end
        end
        
        T_START_MASTER: begin
            if (master_ready) begin
                master_cmd    = `I2C_CMD_START;
                master_wr_i2c = 1'b1;
                state_next    = T_SEND_REAL_ADDR;
            end
        end
        
        T_SEND_REAL_ADDR: begin
            if (master_ready) begin
                master_din    = {REAL_ADDR, rw_bit_latched};
                master_cmd    = `I2C_CMD_WR;
                master_wr_i2c = 1'b1;
                
               if (rw_bit_latched == 1'b0) begin // Write operation
                    state_next = T_PASSTHRU_WRITE;
                end else begin // Read operation
                    state_next = T_PASSTHRU_READ;
                end
            end
        end
        
        T_PASSTHRU_WRITE: begin
            slave_send_ack_data = 1'b1;

            if (slave_rx_valid && master_ready) begin
                master_din          = slave_rx_data;
                master_cmd          = `I2C_CMD_WR;
                master_wr_i2c       = 1'b1;
            end

            if (slave_stop_detected) begin
                state_next = T_STOP_MASTER;
            end
        end
        
        T_PASSTHRU_READ: begin
            slave_send_ack_data = 1'b1;
            if (slave_read_req && master_ready) begin
                master_din    = 8'h00; 
                master_cmd    = `I2C_CMD_RD;
                master_wr_i2c = 1'b1;
            end
            
            if (master_done_tick) begin
                 slave_tx_data  = master_dout;
                slave_tx_valid = 1'b1;
            end

             if (slave_stop_detected) begin
                state_next = T_STOP_MASTER;
            end
        end
        
        T_STOP_MASTER: begin
             if (master_ready) begin
                master_cmd    = `I2C_CMD_STOP;
                master_wr_i2c = 1'b1;
                state_next    = T_IDLE; // Return to idle
            end
        end
        
    endcase
end

endmodule