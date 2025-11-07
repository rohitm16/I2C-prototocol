`timescale 1ns/1ps

module target_slave_model #(
    parameter MY_ADDR = 7'h3C
)(
    inout sda,
    input scl
);

reg [7:0] mem [0:255];
reg [7:0] addr_ptr;
reg sda_drive_low;
assign sda = (sda_drive_low) ? 1'b0 : 1'bz;

reg [3:0] state;
reg [3:0] bit_count;
reg [7:0] shift_reg;
reg       rw_bit;
reg       addr_match;

localparam S_IDLE        = 4'd0;
localparam S_ADDR        = 4'd1;
localparam S_ACK_ADDR    = 4'd2;
localparam S_GET_REG     = 4'd3;
localparam S_ACK_REG     = 4'd4;
localparam S_RX_DATA     = 4'd5;
localparam S_ACK_RX      = 4'd6;
localparam S_TX_DATA     = 4'd7;
localparam S_WAIT_ACK_TX = 4'd8;

initial begin
    mem[8'hAA] = 8'hDE;
    mem[8'hAB] = 8'hAD;
    mem[8'hAC] = 8'hBE;
    mem[8'hAD] = 8'hEF;
    addr_ptr = 8'h00;
    state = S_IDLE;
    sda_drive_low = 1'b0;
    addr_match = 1'b0;
    bit_count = 0;
end

always @(negedge sda) begin
    if (scl) begin
        $display("[%0t] SLAVE (0x%h): START detected.", $time, MY_ADDR);
        state <= S_ADDR;
        bit_count <= 8;
    end
end

always @(posedge sda) begin
    if (scl) begin
        $display("[%0t] SLAVE (0x%h): STOP detected.", $time, MY_ADDR);
        state <= S_IDLE;
        addr_match <= 1'b0;
    end
end

always @(posedge scl) begin
    if (state == S_ADDR) begin
        shift_reg <= {shift_reg[6:0], sda};
        bit_count <= bit_count - 1;
        if (bit_count == 1) begin
            if (shift_reg[6:0] == MY_ADDR) begin
                $display("[%0t] SLAVE (0x%h): Address match.", $time, MY_ADDR);
                addr_match <= 1'b1;
                rw_bit <= sda;
                state <= S_ACK_ADDR;
            end else begin
                state <= S_IDLE;
            end
        end
    end
    else if (state == S_ACK_ADDR) begin
        if (rw_bit == 1'b0) begin
            state <= S_GET_REG;
            bit_count <= 8;
        end else begin
            state <= S_TX_DATA;
            shift_reg <= mem[addr_ptr];
            bit_count <= 8;
        end
    end
    else if (state == S_GET_REG) begin
        shift_reg <= {shift_reg[6:0], sda};
        bit_count <= bit_count - 1;
        if (bit_count == 1) begin
            addr_ptr <= {shift_reg[6:0], sda};
            $display("[%0t] SLAVE (0x%h): Setting internal addr to 0x%h", $time, MY_ADDR, {shift_reg[6:0], sda});
            state <= S_ACK_REG;
        end
    end
    else if (state == S_ACK_REG) begin
        state <= S_RX_DATA;
        bit_count <= 8;
    end
    else if (state == S_RX_DATA) begin
        shift_reg <= {shift_reg[6:0], sda};
        bit_count <= bit_count - 1;
        if (bit_count == 1) begin
            mem[addr_ptr] <= {shift_reg[6:0], sda};
            $display("[%0t] SLAVE (0x%h): Received data 0x%h at 0x%h", $time, MY_ADDR, {shift_reg[6:0], sda}, addr_ptr);
            addr_ptr <= addr_ptr + 1;
            state <= S_ACK_RX;
        end
    end
    else if (state == S_ACK_RX) begin
        state <= S_RX_DATA;
        bit_count <= 8;
    end
    else if (state == S_TX_DATA) begin
        if (bit_count == 0) begin
            state <= S_WAIT_ACK_TX;
        end
    end
    else if (state == S_WAIT_ACK_TX) begin
        if (sda) begin
            state <= S_IDLE;
        end else begin
            state <= S_TX_DATA;
            shift_reg <= mem[addr_ptr];
            addr_ptr <= addr_ptr + 1;
            bit_count <= 8;
        end
    end
end

always @(negedge scl) begin
    if (state == S_ACK_ADDR && addr_match) begin
        sda_drive_low <= 1'b1;
    end
    else if (state == S_ACK_REG) begin
        sda_drive_low <= 1'b1;
    end
    else if (state == S_ACK_RX) begin
        sda_drive_low <= 1'b1;
    end
    else if (state == S_TX_DATA) begin
        if (bit_count > 0) begin
            sda_drive_low <= ~shift_reg[7];
            shift_reg <= {shift_reg[6:0], 1'b1};
            bit_count <= bit_count - 1;
        end else begin
            sda_drive_low <= 1'b0;
        end
    end
    else begin
        sda_drive_low <= 1'b0;
    end
end

endmodule