/*
 
 * Debug-module package, contains common system definitions
 
 */

package dm;


   // SBA state
  typedef enum logic [2:0] {
    Idle,                // 000
    Read,                // 001
    Write,               // 010
    WaitRead,            // 011 
    WaitWrite            // 100
  } sba_state_e;




 



endpackage : dm
