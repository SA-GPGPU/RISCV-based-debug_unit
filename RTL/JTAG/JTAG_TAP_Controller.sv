/////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////                                                         ////////////////////
////////////////////        Test Access Port Module of the DTM JTAG          //////////////////// 
////////////////////                                                         //////////////////// 
/////////////////////////////////////////////////////////////////////////////////////////////////



module DTM_JTAG_TAP #(
    parameter [31:0] IDCode_Value = 32'h00000001,             // Required by the standard 
    /*
        There are different values with different sizes for the IDCode as following:

        // 0001                 -->     version
        // 0100100101010001     -->     part number (IQ)
        // 00011100001          -->     manufacturer id (flextronics)
        // 1                    -->     required by standard

    */
    parameter        IR_Length   = 5,                        // Length of the Instruction register
    parameter        width       = 4
) (


/////////////////////////////////////////////    
/////   Main TAP Controller Signals     /////
/////////////////////////////////////////////

    input  logic         TCK_i,                       // Test Clock to registers                                                         (Mandatory) 
    input  logic         TMS_i,                       // Test Mode Select which controlles the TAP FSM transitions                       (Mandatory)
    input  logic         TRST_ni,                     // Test Reset which restes the whole TAP controller and it is an active low reset  (Optional)
    input  logic         TDI_i,                       // Test Data in which is used to feed the data serially to the target
    output logic         TDO_o,                       // Test Data out which is used to collect the tested data from the target 
    output logic         TDO_En_o,                    // Test Data out enable
    

    // States Signals
    output logic        capture_o,                    // Capture State output 
    output logic        shift_o,                      // Shift   state output 
    output logic        update_o,                     // Update  state ouput 


    // DTM Related Signals    
    input  logic        DTM_CS_TDO_i,                 // Needed to read from the DTM CSR
    output logic        DTM_Select_o,                 // Selector of the DTM
    
    
    // DMI Related Signals 
    input  logic        DMI_TDO_i                     // We want to access DMI Register
    output logic        DMI_clear_o,                  // Synchronous reset of the dmi module triggered by JTAG TAP
    output logic        DMI_select_o,                 // Selector of the DMI   
    

    output logic        TCK_o,                        // JTAG is interested in writing the DTM CSR register using this clk                 
    output logic        TDI_o,                        // Connected to the TDI of sub-modules

);



/////////////////////////////////////////////    
///// Definition of the TAP FSM states  /////
/////////////////////////////////////////////
typedef enum logic [width - 1 : 0] { 
    TestLogicReset,     IDLE_run_test,                 
    scan_select_DR,     scan_select_IR,               // Scan / Select  state 
    CAPTUREDR,          CAPTUREIR,                    // Capture        state 
    SHIFTDR,            SHIFTIR,                      // Shift          state 
    Exit_1_DR,          Exit_1_IR,                    // Exit-1         state
    Exit_2_DR,          Exit_2_IR,                    // Exit-2         state
    UPDATEDR,           UPDATEIR,                     // Update         state 
    PAUSEDR,            PAUSEIR                       // Pause          state     
} TAP_FSM_state;

TAP_FSM_state FSM_state_d, FSM_state_q;




///////////////////////////////////////////////////////////////    
/////          Definition of the Register types           /////
///////////////////////////////////////////////////////////////

typedef enum logic [IR_Length - 1 : 0] {
Bypass0     = 'h0,                                  // 0000
Bypass1     = 'hf,                                  // 1111
ID_code     = 'h1,                                  // 0001
DTM_CSR     = 'h10,                                 // 0010
DMI_access  = 'h11                                  // 0011
} IR_reg;




/////////////////////////////////////////////    
/////    Instruction Register Logic     /////
/////////////////////////////////////////////

reg     [IR_Length - 1 : 0] ir_shift_q , ir_shift_d;
IR_reg                      tap_ir_d, tap_ir_q;                          // IR register -> this gets captured from shift register upon update_ir
logic                       capture_IR, shift_IR, update_IR, test_logic_rst;


always_comb begin : IR_LOGIC
    
    ir_shift_d = ir_shift_q;
    tap_ir_d   = tap_ir_q;


    // We have to reset the IR to the IDCODE state when TRST is active --> actually this happens when we are in the TRST and TMS = 1
    if (test_logic_rst) begin
        tap_ir_d = ID_code;
    end

    // Capture Register
    if (capture_IR) begin
        ir_shift_d = 'h0101;                                            // This value is used because it makes it easy to detect the fault
    end

    // Shift Register
    if (shift_IR) begin
        ir_shift_d = {TDI_i, ir_shift_q[IR_Length - 1 : 1]};            // Shift the value of the IR shift register right by 1 bit of the input TDI
    end

    // Update Register Logic
    if (update_IR) begin
        tap_ir_d = IR_reg'(ir_shift_q);                                 // Update the value of the ir by the new value 
    end

end



/////////////////////////////////////////////    
/////   Instruction Register Behavior   /////
/////////////////////////////////////////////

always_ff @( posedge TCK_i or negedge TRST_ni ) begin : IR_behavior
    
 

    if (!TRST_ni) begin                                                 // Active low aynchronous reset which means whenever this signal is active the circuit will be resetted
        ir_shift_q <= 'h0;                                              // reset the instruction shift register 
        tap_ir_q   <= ID_code;                                          // state of the instruction register is IDCODE state
    end

    else begin                                                          // when reset is not active
        ir_shift_q <= ir_shift_d;                                       // fetch the value at the input of the ir shift reg to the output  
        tap_ir_q   <= tap_ir_d  ;                          
    end
end



/////////////////////////////////////////////    
/////           Data Register           /////
/////////////////////////////////////////////

logic [31:0] ID_code_d, ID_code_q;                                      // 32 bits ID_code registers
logic        Bypass_d, Bypass_q;                                        // 1 bit bypasss register
logic        ID_code_sel, Bypass_sel;                                   // Selector of the ID_code and Bypass states
logic        capture_dr, shift_dr, update_dr;                           



//////////////////////////////////////
/////    Data Register Logic     /////
//////////////////////////////////////

always_comb begin : DR_logic
    
    // Capture Register 
    if (capture_dr) begin                                               
        
        if (ID_code_sel) begin                                          // Incase of IDCODE
            ID_code_d = IDCode_Value;
        end
        
        if (Bypass_sel) begin                                           // Incase of Bypass
            Bypass_d = 1'b0;
        end
    end


    // Shift Register 
    if (shift_dr) begin

        if (ID_code_sel) begin
            ID_code_d = {TDI_i, 31'(ID_code_q>>1)};
        end
        
        if (Bypass_sel) begin
            Bypass_d = TDI_i;
        end
    end

end


///////////////////////////////
/////    Select Logic     /////
///////////////////////////////

always_comb begin : Select_Logic
    
    // Default values of all Selectors
    ID_code_sel  = 1'b0;
    Bypass_sel   = 1'b0;
    DMI_select_o = 1'b0;
    DTM_Select_o = 1'b0;

    // Check for every state to determine which selector will be active 
    unique case(IR_reg)

        ID_code    : ID_code_sel  = 1'b1;                       // Incase of ID_code of the IR Register --> Select the ID_code_select
        Bypass0    : Bypass_sel   = 1'b1;                       // Incase of Bypass  of the IR Register --> Select the ID_code_select
        Bypass1    : Bypass_sel   = 1'b1;       
        DTM_CSR    : DTM_Select_o = 1'b1;                       // Incase of DTM_CSR of the IR Register --> Select the ID_code_select
        DMI_access : DMI_select_o = 1'b1;                       // Incase of accessing the DMI          --> Select the ID_code_select
        default    : Bypass_sel   = 1'b1;
    endcase
end


//////////////////////////////////////
/////    Output Select Logic     /////
//////////////////////////////////////

logic TDO_MUX;
 
always_comb begin : OUT_select
    
    if (shift_IR) begin
    TDO_MUX = ir_shift_q[0];                                        // Read from the IR shift register 
    end 
 
    else begin
    
        unique case(IR_reg)
            
            ID_code    : TDO_MUX = ID_code_q[0];                    // Read the LSB of the ID Code 
            DMI_access : TDO_MUX = DMI_TDO_i;                       // Read from DMI TDO
            DTM_CSR    : TDO_MUX = DTM_CS_TDO_i;                    // Read from DTM_CS TDO
            default: TDO_MUX = Bypass_q;                            // Read from Bypass register
        endcase
    end

end 
 
//////////////////////////////////////////////////////////////////////
//////////////////////////// TAP FSM  ////////////////////////////////
//////////////////////////////////////////////////////////////////////


  always_comb begin : tap_fsm

    capture_IR      = 1'b0;
    shift_IR        = 1'b0;
    update_IR       = 1'b0;
    
    capture_dr      = 1'b0;
    shift_dr        = 1'b0;
    update_dr       = 1'b0;
    
    test_logic_rst  = 1'b0;


    unique case (TAP_FSM_state)
      TestLogicReset: begin
        FSM_state_d = (TMS_i) ? TestLogicReset : IDLE_run_test;
        test_logic_rst = 1'b1;
      end
      IDLE_run_test: begin
        FSM_state_d = (TMS_i) ? scan_select_DR : IDLE_run_test;
      end
      // DR Path
      scan_select_DR: begin
        FSM_state_d = (TMS_i) ? scan_select_IR : CAPTUREDR;
      end
      CAPTUREDR: begin
        capture_dr = 1'b1;
        FSM_state_d = (TMS_i) ? Exit_1_DR : SHIFTDR;
      end
      SHIFTDR: begin
        shift_dr = 1'b1;
        FSM_state_d = (TMS_i) ? Exit_1_DR : SHIFTDR;
      end
      Exit_1_DR: begin
        FSM_state_d = (TMS_i) ? UPDATEDR : PAUSEDR;
      end
      PAUSEDR: begin
        FSM_state_d = (TMS_i) ? Exit_2_DR : PAUSEDR;
      end
      Exit_2_DR: begin
        FSM_state_d = (TMS_i) ? UPDATEDR : SHIFTDR;
      end
      UPDATEDR: begin
        update_dr = 1'b1;
        FSM_state_d = (TMS_i) ? scan_select_DR : IDLE_run_test;
      end
      // IR Path
      scan_select_IR: begin
        FSM_state_d = (TMS_i) ? TestLogicReset : CAPTUREIR;
      end
      // In this controller state, the shift register bank in the
      // Instruction Register parallel loads a pattern of fixed values on
      // the rising edge of TCK. The last two significant bits must always
      // be "01".
      CAPTUREIR: begin
        capture_ir = 1'b1;
        FSM_state_d = (TMS_i) ? Exit_1_IR : SHIFTIR;
      end
      // In this controller state, the instruction register gets connected
      // between TDI and TDO, and the captured pattern gets shifted on
      // each rising edge of TCK. The instruction available on the TDI
      // pin is also shifted in to the instruction register.
      SHIFTIR: begin
        shift_ir = 1'b1;
        FSM_state_d = (TMS_i) ? Exit_1_IR : SHIFTIR;
      end
      Exit_1_IR: begin
        FSM_state_d = (TMS_i) ? UPDATEIR : PAUSEIR;
      end
      PAUSEIR: begin
        // pause_ir = 1'b1; // unused
        FSM_state_d = (TMS_i) ? Exit_2_IR : PAUSEIR;
      end
      Exit_2_IR: begin
        FSM_state_d = (TMS_i) ? UPDATEIR : SHIFTIR;
      end
      // In this controller state, the instruction in the instruction
      // shift register is latched to the latch bank of the Instruction
      // Register on every falling edge of TCK. This instruction becomes
      // the current instruction once it is latched.
      UPDATEIR: begin
        update_ir = 1'b1;
        FSM_state_d = (TMS_i) ? scan_select_DR : IDLE_run_test;
      end
      default: ; // can't actually happen since case is full
    endcase
  end

  always_ff @(posedge TCK_i or negedge TRST_ni) begin 
    if (!TRST_ni) begin
      FSM_state_q <= IDLE_run_test;
      ID_code_q    <= IdcodeValue;
      Bypass_q    <= 1'b0;
    end else begin
      FSM_state_q  <= FSM_state_d;
      ID_code_q    <= ID_code_d;
      Bypass_q     <= Bypass_d;
    end
  end

  // Pass through JTAG signals to debug custom DR logic.
  // In case of a single TAP those are just feed-through.

  assign update_o    = update_dr;
  assign shift_o     = shift_dr;
  assign capture_o   = capture_dr;
  assign DMI_clear_o = test_logic_rst;

 
endmodule
