# RISCV-based-debug_unit
This module is an implementation of a debug unit compliant with the [RISC-V debug specification 0.13.2]


# Implementation
We use an execution-based technique, also described in the specification, where
the core is running in a "park loop". Depending on the request made to the debug
unit via JTAG over the Debug Transport Module (DTM), the code that is being
executed is changed dynamically. This approach simplifies the implementation
side of the core, but means that the core is in fact always busy looping while
debugging.

# Features
The following features are currently supported

* Parametrizable buswidth for `XLEN=32` `XLEN=64` cores
* Accessing registers over abstract command
* Program buffer
* System bus access (only `XLEN`)
* DTM with JTAG interface
