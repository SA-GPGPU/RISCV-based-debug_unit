////////////////////////////////////////////////////////////////////////
///////////////////// Debug Module Interface ///////////////////////////
////////////////////////////////////////////////////////////////////////

// DMI Device additionally carries a clock signaal

interface dmi_if #(
    parameter  addr_width = 7,
    parameter  data_width = 32
) ( 
    input clk
);


typedef enum logic[1:0] { 

    NOP   = 2'h0,
    READ  = 2'h1,
    WRITE = 2'h2

} dtm_op_type;

// Request Channel
wire        [addr_width - 1 : 0] req_addr;
wire        [data_width - 1 : 0] req_data;
wire                             req_valid;
wire                             req_ready;
dtm_op_type                      req_op;

    

// Response Channel 
wire        [data_width - 1 : 0] res_data;
wire                             res_valid;
wire                             res_ready;
dtm_op_type                      res_op;



modport Device (
input  req_addr, 
input  req_data, 
input  req_op, 
input  req_valid, 
input  res_ready,
output req_ready, 
output res_valid, 
output res_op, 
output res_data
);

modport Host (
input  req_ready, 
input  res_valid, 
input  res_op, 
input  res_data,
output req_addr, 
output req_data, 
output req_op, 
output req_valid, 
output res_ready
);


endinterface //dmi_if