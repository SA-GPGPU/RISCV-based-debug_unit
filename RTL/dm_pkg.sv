/*
 
 * Debug-module package, contains common system definitions
 
 */

package dm;

 /////////////////////////////////////////////////////////////////////////
 ////////////////////////// System Bus Access ////////////////////////////
 /////////////////////////////////////////////////////////////////////////

  // SBA Different States
  typedef enum logic [2:0] {
    Idle,                // 000
    Read,                // 001
    Write,               // 010
    WaitRead,            // 011 
    WaitWrite            // 100
  } sba_state_e;

 
 
 /////////////////////////////////////////////////////////////////////////
 ///////////////////////// Debug Module Interface ////////////////////////
 /////////////////////////////////////////////////////////////////////////
 
 // DMI Request channel variables
 typedef enum logic [1:0] {
  DTM_NOP   = 2'h0,
  DTM_READ  = 2'h1,
  DTM_WRITE = 2'h2
} dtm_op_e;

typedef struct packed {
  logic      [6:0]  addr;
  logic      [31:0] data;
  dtm_op_e          op;
  
} dmi_req_t;
 
 
 // DMI Responce channel variable
 typedef struct packed  {
  logic [31:0] data;
  logic [1:0]  resp;
} dmi_resp_t;



 



endpackage : dm
