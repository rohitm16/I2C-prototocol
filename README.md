
FPGA-based I²C Address Translator

This repository contains the Verilog source code and testbench for an FPGA-based I²C address translator. The module is designed to dynamically remap the I²C address of a target slave device, allowing it to coexist on a bus with other devices that may share the same default address.

This project was completed as a requirement for VICHARAK Recrutment Task [Nov 2025].

EDA Playground: 

Table of Contents

Key Features

Architecture Overview

File Structure

How to Simulate

Detailed Design Explanation

Design Challenges and Solutions

FPGA Resource Utilization

Key Features

Dynamic Address Remapping: Translates a pre-defined VIRTUAL_ADDR on the master bus to a REAL_ADDR on the slave bus.

Transparent Bridge: Acts as a full I²C slave on the master-facing bus and a full I²C master on the slave-facing bus.

Bidirectional Operation: Correctly handles both read and write transactions.

Clock Stretching: Implements clock stretching on the master bus to manage data flow and prevent race conditions.

Robust Verification: Includes a comprehensive testbench with multiple slave models to verify correct operation and isolation.

Synthesizable Logic: Written in Verilog using FPGA-friendly constructs (FSMs, counters, shift registers).

Architecture Overview

The translator acts as a "man-in-the-middle" device. It is composed of three main modules orchestrated by a central controller.

i2c_slave_core (The Ear): This module connects to the main system's I²C bus. It is configured to listen for the VIRTUAL_ADDR. When it detects this address, it notifies the central controller and manages the communication with the system master, including performing clock stretching to wait for the translator to be ready.

i2c_master (The Mouth): This module connects to the target slave device on a secondary I²C bus. It is a command-driven core that generates I²C waveforms to communicate with the target slave.

i2c_translator_top (The Brain): This is the top-level module containing the main FSM. It coordinates the entire process:

It waits for the i2c_slave_core to report an address match.

It then commands the i2c_master to initiate a new transaction on the secondary bus using the REAL_ADDR.

It enters a passthrough mode, shuttling data between the two buses for the duration of the transaction.

It mirrors the STOP condition to cleanly terminate the transaction on both buses.

Data Flow:
[System Master] <---(Master Bus)---> [Translator Slave Core] <---(Internal Logic)---> [Translator Master Core] <---(Slave Bus)---> [Target Slave]

File Structure
code
Code
download
content_copy
expand_less
.
├── rtl/                      
│   ├── i2c_defines.v         # Defines I2C master commands
│   ├── i2c_master.v          # Command-driven I2C Master module
│   ├── i2c_slave_core.v      # I2C Slave module with clock stretching
│   └── i2c_translator_top.v  # Top-level controller and FSM
│
├── sim/                      
│   ├── system_master_model.v # Behavioral model of the main I2C Master
│   ├── target_slave_model.v  # Behavioral model of I2C Slave devices
│   └── tb_i2c_translator.v   # Top-level testbench
│
├── reports/                  
│   ├── resource_utilization.txt # FPGA resource report
│   └── timing_summary.txt    # FPGA timing summary
│
└── README.md                 # This documentation file
How to Simulate

Prerequisites:

A Verilog simulator (e.g., Vivado XSim, ModelSim, Verilator, or any simulator on EDA Playground).

Running the Simulation:

Compile all Verilog files from the rtl/ and sim/ directories.

Set tb_i2c_translator as the top-level simulation module.

Run the simulation for at least 2 ms to observe all test scenarios.

Expected Outcome:
The testbench (tb_i2c_translator.v) executes three scenarios:

Scenario 1: Writes to a non-translated address (OTHER_ADDR). The translator should ignore this.

Scenario 2: Writes data to the VIRTUAL_ADDR. The data should be correctly passed through to the REAL_ADDR slave.

Scenario 3: Reads data from the VIRTUAL_ADDR. The data from the REAL_ADDR slave should be correctly read back.

A successful simulation will print the following messages to the console:

code
Code
download
content_copy
expand_less
SCENARIO 2 PASSED: Data 0xc0 written to target slave.
SCENARIO 3 PASSED: Read data 0xad from target slave.
Detailed Design Explanation

A comprehensive, beginner-friendly explanation of the entire codebase, module by module, is available in the DOCUMENTATION.md file.
