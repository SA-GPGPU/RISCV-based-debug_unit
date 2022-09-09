//////////////////////////////////////////////////////////////
///////////////////////// DM System Interface ////////////////
//////////////////////////////////////////////////////////////



interface dm_system_if ();

logic               clk_i;                          
logic               rst_ni;
logic               testmode_i;
logic               ndmreset_o; 
logic               dmactive_o;


modport DM (
    
        input  logic                  clk_i,
        input  logic                  rst_ni,
        input  logic                  testmode_i,

        output logic                  ndmreset_o,
        output logic                  dmactive_o
    );

endinterface //dm_system_if