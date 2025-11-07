`timescale 1ns/1ps

module system_master_model (
    inout sda,
    inout scl
);

reg sda_out = 1'b1;
reg scl_out = 1'b1;

assign sda = sda_out ? 1'bz : 1'b0;
assign scl = scl_out ? 1'bz : 1'b0;

parameter PERIOD = 10000; // 10,000 ns = 100 kHz

task i2c_init;
begin
    sda_out = 1'b1;
    scl_out = 1'b1;
    #(PERIOD);
end
endtask

task i2c_start;
begin
    sda_out = 1'b1;
    scl_out = 1'b1;
    #(PERIOD/4);
    sda_out = 1'b0;
    #(PERIOD/4);
    scl_out = 1'b0;
    #(PERIOD/2);
end
endtask

task i2c_stop;
begin
    scl_out = 1'b0;
    sda_out = 1'b0;
    #(PERIOD/4);
    scl_out = 1'b1;
    #(PERIOD/4);
    sda_out = 1'b1;
    #(PERIOD/2);
end
endtask

task i2c_write_byte;
    input [7:0] data;
    output      ack;
    integer i;
begin
    for (i = 7; i >= 0; i = i - 1) begin
        scl_out = 1'b0;
        sda_out = data[i];
        #(PERIOD/2);
        scl_out = 1'b1;
        #(PERIOD/2);
    end
    
    scl_out = 1'b0;
    sda_out = 1'b1;
    #(PERIOD/2);
    scl_out = 1'b1;
    ack = sda;
    #(PERIOD/2);
    scl_out = 1'b0;
end
endtask

task i2c_read_byte;
    input send_ack; // 0 = send ACK, 1 = send NACK
    output [7:0] data;
    integer i;
begin
    sda_out = 1'b1;
    for (i = 7; i >= 0; i = i - 1) begin
        scl_out = 1'b0;
        #(PERIOD/2);
        scl_out = 1'b1;
        data[i] = sda;
        #(PERIOD/2);
    end
    
    scl_out = 1'b0;
    sda_out = send_ack;
    #(PERIOD/2);
    scl_out = 1'b1;
    #(PERIOD/2);
    scl_out = 1'b0;
    sda_out = 1'b1;
end
endtask

task task_write;
    input [6:0] addr;
    input [7:0] data_byte;
    reg ack;
begin
    $display("[%0t] TB MASTER: Writing 0x%h to 7-bit addr 0x%h", $time, data_byte, addr);
    i2c_start;
    i2c_write_byte({addr, 1'b0}, ack);
    if (ack) $display("ERROR: Address 0x%h NACK'd", addr);
    
    i2c_write_byte(data_byte, ack);
    if (ack) $display("ERROR: Data 0x%h NACK'd", data_byte);
    
    i2c_stop;
    #(PERIOD * 10);
end
endtask

task task_read;
    input [6:0] addr;
    output [7:0] data_read;
    reg ack;
    reg [7:0] data_temp;
begin
    $display("[%0t] TB MASTER: Reading from 7-bit addr 0x%h", $time, addr);
    i2c_start;
    i2c_write_byte({addr, 1'b1}, ack);
    if (ack) $display("ERROR: Address 0x%h NACK'd", addr);

    i2c_read_byte(1'b1, data_temp); // Read one byte and NACK it
    data_read = data_temp;
    
    i2c_stop;
    $display("[%0t] TB MASTER: Read data 0x%h", $time, data_read);
    #(PERIOD * 10);
end
endtask

endmodule