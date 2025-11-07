`timescale 1ns/1ps
`include "i2c_defines.v"

module i2c_master (
    // Inputs
    clk, 
    reset,
    din,
    dvsr,  
    cmd, 
    wr_i2c,
    scl,
    ready, 
    done_tick, 
    ack,
    dout,
    sda
);

input           clk;
input           reset;
input  [7:0]    din;
input  [15:0]   dvsr;  
input  [2:0]    cmd; 
input           wr_i2c;

output          scl;
output          ready;
output          done_tick;
output          ack;
output [7:0]    dout;

inout           sda;

// FSM state parameters
localparam S_IDLE     = 4'd0;
localparam S_HOLD     = 4'd1;
localparam S_START1   = 4'd2;
localparam S_START2   = 4'd3;
localparam S_DATA1    = 4'd4;
localparam S_DATA2    = 4'd5;
localparam S_DATA3    = 4'd6;
localparam S_DATA4    = 4'd7;
localparam S_DATA_END = 4'd8;
localparam S_RESTART  = 4'd9;
localparam S_STOP1    = 4'd10;
localparam S_STOP2    = 4'd11;


reg [3:0]  state_reg, state_next;
reg [15:0] c_reg, c_next;
reg [8:0]  tx_reg, tx_next;
reg [8:0]  rx_reg, rx_next;
reg [2:0]  cmd_reg, cmd_next;
reg [3:0]  bit_reg, bit_next;
reg        sda_out, scl_out, sda_reg, scl_reg, data_phase;
reg        done_tick_i, ready_i;


wire [15:0] qutr, half;
wire        into, nack;

// output sda,scl transition
always @(posedge clk or posedge reset) begin
    if (reset) begin
        sda_reg <= 1'b1;
        scl_reg <= 1'b1;
    end
    else begin
        sda_reg <= sda_out;
        scl_reg <= scl_out;
    end
end

// only master drives scl line  
assign scl = (scl_reg) ? 1'bz : 1'b0;

assign into = (data_phase && cmd_reg == `I2C_CMD_RD && bit_reg < 8) ||  
              (data_phase && cmd_reg == `I2C_CMD_WR && bit_reg == 8); 
assign sda = (into || sda_reg) ? 1'bz : 1'b0;

// output
assign dout = rx_reg[8:1];
assign ack = rx_reg[0];
assign nack = din[0];

// fsm
always @(posedge clk or posedge reset) begin
    if (reset) begin
        state_reg <= S_IDLE;
        c_reg     <= 0;
        bit_reg   <= 0;
        cmd_reg   <= 0;
        tx_reg    <= 0;
        rx_reg    <= 0;
    end
    else begin
        state_reg <= state_next;
        c_reg     <= c_next;
        bit_reg   <= bit_next;
        cmd_reg   <= cmd_next;
        tx_reg    <= tx_next;
        rx_reg    <= rx_next;
    end
end

assign qutr = dvsr;
assign half = {qutr[14:0], 1'b0}; // half = 2Xqutr

// next-state logic
always @(*) begin
    state_next = state_reg;
    c_next = c_reg + 1;
    bit_next = bit_reg;
    tx_next = tx_reg;
    rx_next = rx_reg;
    cmd_next = cmd_reg;
    done_tick_i = 1'b0;
    ready_i = 1'b0;
    scl_out = 1'b1;
    sda_out = 1'b1;
    data_phase = 1'b0;
    
    case (state_reg)
        S_IDLE: begin
            ready_i = 1'b1;
            if (wr_i2c && cmd == `I2C_CMD_START) begin
                state_next = S_START1;
                c_next = 0;
            end
        end  
        S_START1: begin
            sda_out = 1'b0;
            if (c_reg == half) begin
                c_next = 0;
                state_next = S_START2;
            end
        end  
        S_START2: begin
            sda_out = 1'b0;
            scl_out = 1'b0;
            if (c_reg == qutr) begin
                c_next = 0;
                state_next = S_HOLD;
            end
        end  
        S_HOLD: begin
            ready_i = 1'b1;
            sda_out = 1'b0;
            scl_out = 1'b0;
            if (wr_i2c) begin
                cmd_next = cmd;
                c_next = 0;
                case (cmd) 
                    `I2C_CMD_RESTART, `I2C_CMD_START:
                        state_next = S_RESTART;
                    `I2C_CMD_STOP:
                        state_next = S_STOP1;
                    default: begin
                        bit_next   = 0;
                        state_next = S_DATA1;
                        tx_next = {din, nack};
                    end 
                endcase
            end
        end
        S_DATA1: begin
            sda_out = tx_reg[8];
            scl_out = 1'b0;
            data_phase = 1'b1;
            if (c_reg == qutr) begin
                c_next     = 0;
                state_next = S_DATA2;
            end 
        end
        S_DATA2: begin
            sda_out = tx_reg[8];
            data_phase = 1'b1;
            if (c_reg == qutr) begin
                c_next = 0;
                state_next = S_DATA3;
                rx_next = {rx_reg[7:0], sda};
            end
        end
        S_DATA3: begin
            sda_out = tx_reg[8];
            data_phase = 1'b1;
            if (c_reg == qutr) begin
                c_next     = 0;
                state_next = S_DATA4;
            end
        end
        S_DATA4: begin
            sda_out = tx_reg[8];
            scl_out = 1'b0;
            data_phase = 1'b1;
            if (c_reg == qutr) begin
                c_next = 0;
                if (bit_reg == 8) begin
                    state_next = S_DATA_END;
                    done_tick_i = 1'b1;
                end 
                else begin
                    tx_next = {tx_reg[7:0], 1'b0};
                    bit_next = bit_reg + 1;
                    state_next = S_DATA1;
                end
            end
        end
        S_DATA_END: begin
            sda_out = 1'b0;
            scl_out = 1'b0;
            if (c_reg == qutr) begin
                c_next = 0;
                state_next = S_HOLD;
            end
        end
        S_RESTART: begin
            if (c_reg == half) begin
                c_next = 0;
                state_next = S_START1;
            end
        end
        S_STOP1: begin
            sda_out = 1'b0;
            if (c_reg == half) begin
                c_next = 0;
                state_next = S_STOP2;
            end
        end
        default: begin // S_STOP2
            if (c_reg == half) 
                state_next = S_IDLE;
        end
    endcase
end

assign done_tick = done_tick_i;
assign ready = ready_i;

endmodule