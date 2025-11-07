// tb_i2c_translator.v
`timescale 1ns/1ps
`include "i2c_defines.v"

module tb_i2c_translator;

localparam VIRTUAL_ADDR = 7'h5A;
localparam REAL_ADDR    = 7'h3C;
localparam OTHER_ADDR   = 7'h1B;
localparam SYS_CLK_PERIOD = 20;

reg clk;
reg reset;
reg [7:0] read_data;

wire master_bus_scl;
wire master_bus_sda;
wire slave_bus_scl;
wire slave_bus_sda;

pullup(master_bus_scl);
pullup(master_bus_sda);
pullup(slave_bus_scl);
pullup(slave_bus_sda);

i2c_translator_top #(
    .VIRTUAL_ADDR(VIRTUAL_ADDR),
    .REAL_ADDR(REAL_ADDR),
    .SYS_CLK_FREQ(50_000_000),
    .I2C_FREQ(100_000)
) u_dut (
    .clk(clk),
    .reset(reset),
    .master_bus_sda(master_bus_sda),
    .master_bus_scl(master_bus_scl),
    .slave_bus_sda(slave_bus_sda),
    .slave_bus_scl(slave_bus_scl)
);

system_master_model u_system_master (
    .sda(master_bus_sda),
    .scl(master_bus_scl)
);

target_slave_model #(
    .MY_ADDR(REAL_ADDR)
) u_target_slave (
    .sda(slave_bus_sda),
    .scl(slave_bus_scl)
);

target_slave_model #(
    .MY_ADDR(OTHER_ADDR)
) u_other_slave (
    .sda(master_bus_sda),
    .scl(master_bus_scl)
);

initial begin
    clk = 0;
    forever #(SYS_CLK_PERIOD / 2) clk = ~clk;
end

initial begin
    reset = 1'b1;
    #200;
    reset = 1'b0;
end

initial begin
    @(negedge reset);
    $display("--------------- TEST START ---------------");
    u_system_master.i2c_init();

    $display("\n--- SCENARIO 1: Write to OTHER_ADDR (0x%h) ---", OTHER_ADDR);
    u_system_master.task_write(OTHER_ADDR, 8'hAA);
    u_system_master.task_write(OTHER_ADDR, 8'h12);
    
    $display("\n--- SCENARIO 2: Write to VIRTUAL_ADDR (0x%h) ---", VIRTUAL_ADDR);
    u_system_master.task_write(VIRTUAL_ADDR, 8'hAA);
    u_system_master.task_write(VIRTUAL_ADDR, 8'hC0);
    #(1000);
    if (u_target_slave.mem[8'hAA] == 8'hC0)
        $display("SCENARIO 2 PASSED: Data 0x%h written to target slave.", 8'hC0);
    else
        $display("SCENARIO 2 FAILED: Expected 0xc0, got 0x%h.", u_target_slave.mem[8'hAA]);

    $display("\n--- SCENARIO 3: Read from VIRTUAL_ADDR (0x%h) ---", VIRTUAL_ADDR);
    u_system_master.task_write(VIRTUAL_ADDR, 8'hAB);
    u_system_master.task_read(VIRTUAL_ADDR, read_data);
    
    if (read_data == 8'hAD)
        $display("SCENARIO 3 PASSED: Read data 0x%h from target slave.", read_data);
    else
        $display("SCENARIO 3 FAILED: Expected 0xad, got 0x%h.", read_data);
        
    $display("\n--------------- TEST END ---------------");
    $stop;
end

endmodule