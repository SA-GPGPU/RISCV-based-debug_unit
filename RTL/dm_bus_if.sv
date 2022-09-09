////////////////////////////////////////////////////////////////////////
///////////////////// Debug Module Bus Interface ///////////////////////
////////////////////////////////////////////////////////////////////////


parameter BusWidth = 32;                // Default --> could be 64 if needed 

interface dm_bus_if (); 
    
    logic                       req; 
    logic                       we;
    logic                       gnt;
    logic                       r_valid;
    logic                       r_err;
    logic                       r_other_err;                 // Has higher priority than r_err
    logic   [BusWidth/8-1 : 0]  be;
    logic   [BusWidth - 1 : 0]  addr;
    logic   [BusWidth - 1 : 0]  wdata;
    logic   [BusWidth - 1 : 0]  rdata;

    modport host (
    
    // inputs to the host side 
    input   gnt,
    input   r_valid,
    input   rdata,  
    input   r_err,
    input   r_other_err, 
    
    // outputs from the host side 
    output  req,
    output  we,
    output  addr,
    output  wdata,
    output  be
    );



    modport device (

    // inputs to the device side     
    input   req,
    input   we,
    input   addr,
    input   be,
    input   wdata,
    
    // outputs from the device side  
    output  rdata
    );

endinterface // dm_bus_if