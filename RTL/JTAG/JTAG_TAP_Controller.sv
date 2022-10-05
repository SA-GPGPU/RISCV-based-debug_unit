/////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////                                                         ////////////////////
////////////////////        Test Access Port Module of the DTM JTAG          //////////////////// 
////////////////////                                                         //////////////////// 
/////////////////////////////////////////////////////////////////////////////////////////////////

module dmi_jtag_tap #(

  parameter int unsigned IrLength = 5,                    // Length of the Instruction register

 
  parameter logic [31:0] IdcodeValue = 32'h00000001       // JTAG IDCODE Value
   /*
        There are different values with different sizes for the IDCode as following:

        // 0001                 -->     version
        // 0100100101010001     -->     part number (IQ)
        // 00011100001          -->     manufacturer id (flexatronics)
        // 1                    -->     required by standard

    */

) (

/////////////////////////////////////////////    
/////   Main TAP Controller Signals     /////
/////////////////////////////////////////////

            input  logic        tck_i,                              // JTAG Test Clock                                                                       (Mandatory) 
            input  logic        tms_i,                              // JTAG Test Mode Select which controles the TAP FSM transitions                         (Mandatory)
            input  logic        trst_ni,                            // JTAG Test Reset which restes the whole TAP controller and it is an active low reset   (Optional)
            input  logic        td_i,                               // JTAG Data in which is used to feed the data serially to the target
            output logic        td_o,                               // JTAG Data out which is used to collect the tested data from the target
            output logic        tdo_oe_o,                           // Data out output enable
            input  logic        testmode_i,                         // JTAG Testing Mode Input 
            
            output logic        tck_o,                              // JTAG is interested in writing the DTM CSR register

            // States Signals                    
            output logic        update_o,                           // Update  state ouput
            output logic        capture_o,                          // Capture State output
            output logic        shift_o,                            // Shift   state output


            output logic        tdi_o,                              // Fetching the td_i on the output 


            // DTM Related Signals 
            output logic        dtmcs_select_o,                     // Selector of the DTM
            input  logic        dtmcs_tdo_i,                        // Needed to read from the DTM CSR


            // DMI Related Signals 
            input  logic        dmi_tdo_i ,                         // we want to access DMI register
            output logic        dmi_clear_o,                        // Synchronous clear of the dmi module triggered by JTAG TAP
            output logic        dmi_select_o                        // Selector of the DMI
            
);


/////////////////////////////////////////////    
///// Definition of the TAP FSM states  /////
/////////////////////////////////////////////

  typedef enum logic [3:0] {
    TestLogicReset,   RunTestIdle,    
    SelectDrScan,     SelectIrScan,                                 // Select Scan State 
    CaptureDr,        CaptureIr,                                    // Capture     State 
    ShiftDr,          ShiftIr,                                      // Shift       State 
    Exit1Dr,          Exit1Ir,                                      // Exit 1      State
    PauseDr,          PauseIr,                                      // Pause       State 
    UpdateDr,         UpdateIr,                                     // Update      State 
    Exit2Dr,          Exit2Ir                                       // Exit 2      State 
  } tap_state_e;

  tap_state_e tap_state_q, tap_state_d;
  logic update_dr, shift_dr, capture_dr;



///////////////////////////////////////////////////////////////    
/////          Definition of the Register types           /////
///////////////////////////////////////////////////////////////
  typedef enum logic [IrLength-1:0] {
    BYPASS0   = 'h0,                                                // 0000
    IDCODE    = 'h1,                                                // 0001
    DTMCSR    = 'h10,                                               // 0010     
    DMIACCESS = 'h11,                                               // 0011
    BYPASS1   = 'h1f                                                // 1111 
  } ir_reg_e;



/////////////////////////////////////////////    
/////    Instruction Register Logic     /////
/////////////////////////////////////////////

  // shift register
  logic [IrLength-1:0]  jtag_ir_shift_d, jtag_ir_shift_q;

  // IR register -> this gets captured from shift register upon update_ir
  ir_reg_e              jtag_ir_d, jtag_ir_q;
  logic capture_ir, shift_ir, update_ir, test_logic_reset;          // pause_ir is not used 

  always_comb begin : p_jtag
    jtag_ir_shift_d = jtag_ir_shift_q;
    jtag_ir_d       = jtag_ir_q;


    // According to JTAG spec we have to reset the IR to IDCODE in test_logic_reset
    // We have to reset the IR to the IDCODE state when TRST is active --> actually this happens when we are in the TRST and TMS = 1
    if (test_logic_reset) begin
        jtag_ir_d = IDCODE;
      end
    end


    // IR shift register
    if (shift_ir) begin
      jtag_ir_shift_d = {td_i, jtag_ir_shift_q[IrLength-1:1]};
    end

    // capture IR register
    if (capture_ir) begin
      jtag_ir_shift_d =  IrLength'(4'b0101);                                        // This value is used because it makes it easy to detect the fault
    end

    // update IR register
    if (update_ir) begin
      jtag_ir_d = ir_reg_e'(jtag_ir_shift_q);
    end



/////////////////////////////////////////////    
/////   Instruction Register Behavior   /////
/////////////////////////////////////////////

  always_ff @(posedge tck_i, negedge trst_ni) begin : p_jtag_ir_reg
    
    if (!trst_ni) begin                                                           // Active low aynchronous reset which means whenever this signal is active the circuit will be resetted
        jtag_ir_shift_q <= '0;                                                    // reset the instruction shift register
        jtag_ir_q       <= IDCODE;                                                // state of the instruction register is IDCODE state
    end 
    
    else begin                                                                    // when reset is not active
      jtag_ir_shift_q <= jtag_ir_shift_d;                                         // fetch the value at the input of the ir shift reg to the output
      jtag_ir_q       <= jtag_ir_d;
    end
  end


/////////////////////////////////////////////    
/////           Data Register           /////
/////////////////////////////////////////////
  // - Bypass
  // - IDCODE
  // - DTM CS

  logic [31:0] idcode_d, idcode_q;                                                // 32 bits ID_code registers
  logic        idcode_select;                                                     // ID Code Selector
  logic        bypass_select;                                                     // Bypass Selector
  logic        bypass_d, bypass_q;                                                // This is a 1-bit register


//////////////////////////////////////
/////    Data Register Logic     /////
//////////////////////////////////////
  always_comb begin
    idcode_d = idcode_q;
    bypass_d = bypass_q;

    // Capture Register 
    if (capture_dr) begin
      if (idcode_select) idcode_d = IdcodeValue;                                  // Incase of IDCODE
      if (bypass_select) bypass_d = 1'b0;                                         // Incase of BYPASSS
    end

    // Shift Register
    if (shift_dr) begin
      if (idcode_select)  idcode_d = {td_i, 31'(idcode_q >> 1)};                  // Incase of IDCODE
      if (bypass_select)  bypass_d = td_i;                                        // Incase of BYPASS
    end
  end



/////////////////////////////////////////////
/////    Data Register Select Logic     /////
/////////////////////////////////////////////
  always_comb begin : p_data_reg_sel

  // Default values of all Selectors
    dmi_select_o   = 1'b0;
    dtmcs_select_o = 1'b0;
    idcode_select  = 1'b0;
    bypass_select  = 1'b0;

  // Check for every state to determine which selector will be active 
    unique case (jtag_ir_q)
      BYPASS0:   bypass_select  = 1'b1;                                           // Incase of Bypass  of the IR Register --> Select the Bypass_select
      IDCODE:    idcode_select  = 1'b1;                                           // Incase of ID_code of the IR Register --> Select the ID_code_select
      DTMCSR:    dtmcs_select_o = 1'b1;                                           // Incase of DTM_CSR of the IR Register --> Select the dtm_select
      DMIACCESS: dmi_select_o   = 1'b1;                                           // Incase of accessing the DMI          --> Select the dmi_select
      BYPASS1:   bypass_select  = 1'b1;
      default:   bypass_select  = 1'b1;                                           // Default state is to select the bypass_select
    endcase
  end


//////////////////////////////////////
/////    Output Select Logic     /////
//////////////////////////////////////
  logic tdo_mux;

  always_comb begin : p_out_sel

    // we are shifting out the IR register
    if (shift_ir) begin
      tdo_mux = jtag_ir_shift_q[0];

    // here we are shifting the DR register
    end else begin
      unique case (jtag_ir_q)
        IDCODE:         tdo_mux = idcode_q[0];                                    // Reading ID code
        DTMCSR:         tdo_mux = dtmcs_tdo_i;                                    // Read from DTMCS TDO
        DMIACCESS:      tdo_mux = dmi_tdo_i;                                      // Read from DMI TDO
        default:        tdo_mux = bypass_q;                                       // BYPASS instruction
      endcase
    end
  end

  logic tck_n, tck_ni;

  // TDO changes state at negative edge of TCK
  always_ff @(posedge tck_n, negedge trst_ni) begin : p_tdo_regs
    if (!trst_ni) begin
      td_o     <= 1'b0;
      tdo_oe_o <= 1'b0;
    end else begin
      td_o     <= tdo_mux;
      tdo_oe_o <= (shift_ir | shift_dr);
    end
  end


//////////////////////////////////////////////////////////////////////
//////////////////////////// TAP FSM  ////////////////////////////////
//////////////////////////////////////////////////////////////////////

  // Determination of next state; purely combinatorial
  always_comb begin : p_tap_fsm

    test_logic_reset   = 1'b0;

    capture_dr         = 1'b0;
    shift_dr           = 1'b0;
    update_dr          = 1'b0;

    capture_ir         = 1'b0;
    shift_ir           = 1'b0;
    // pause_ir           = 1'b0; unused
    update_ir          = 1'b0;

    unique case (tap_state_q)
      TestLogicReset: begin
        tap_state_d = (tms_i) ? TestLogicReset : RunTestIdle;
        test_logic_reset = 1'b1;
      end
      RunTestIdle: begin
        tap_state_d = (tms_i) ? SelectDrScan : RunTestIdle;
      end
      // DR Path
      SelectDrScan: begin
        tap_state_d = (tms_i) ? SelectIrScan : CaptureDr;
      end
      CaptureDr: begin
        capture_dr = 1'b1;
        tap_state_d = (tms_i) ? Exit1Dr : ShiftDr;
      end
      ShiftDr: begin
        shift_dr = 1'b1;
        tap_state_d = (tms_i) ? Exit1Dr : ShiftDr;
      end
      Exit1Dr: begin
        tap_state_d = (tms_i) ? UpdateDr : PauseDr;
      end
      PauseDr: begin
        tap_state_d = (tms_i) ? Exit2Dr : PauseDr;
      end
      Exit2Dr: begin
        tap_state_d = (tms_i) ? UpdateDr : ShiftDr;
      end
      UpdateDr: begin
        update_dr = 1'b1;
        tap_state_d = (tms_i) ? SelectDrScan : RunTestIdle;
      end
      // IR Path
      SelectIrScan: begin
        tap_state_d = (tms_i) ? TestLogicReset : CaptureIr;
      end
      // In this controller state, the shift register bank in the
      // Instruction Register parallel loads a pattern of fixed values on
      // the rising edge of TCK. The last two significant bits must always
      // be "01".
      CaptureIr: begin
        capture_ir = 1'b1;
        tap_state_d = (tms_i) ? Exit1Ir : ShiftIr;
      end
      // In this controller state, the instruction register gets connected
      // between TDI and TDO, and the captured pattern gets shifted on
      // each rising edge of TCK. The instruction available on the TDI
      // pin is also shifted in to the instruction register.
      ShiftIr: begin
        shift_ir = 1'b1;
        tap_state_d = (tms_i) ? Exit1Ir : ShiftIr;
      end
      Exit1Ir: begin
        tap_state_d = (tms_i) ? UpdateIr : PauseIr;
      end
      PauseIr: begin
        // pause_ir = 1'b1; // unused
        tap_state_d = (tms_i) ? Exit2Ir : PauseIr;
      end
      Exit2Ir: begin
        tap_state_d = (tms_i) ? UpdateIr : ShiftIr;
      end
      // In this controller state, the instruction in the instruction
      // shift register is latched to the latch bank of the Instruction
      // Register on every falling edge of TCK. This instruction becomes
      // the current instruction once it is latched.
      UpdateIr: begin
        update_ir = 1'b1;
        tap_state_d = (tms_i) ? SelectDrScan : RunTestIdle;
      end
      default: ; // can't actually happen since case is full
    endcase
  end

  always_ff @(posedge tck_i or negedge trst_ni) begin : p_regs
    if (!trst_ni) begin
      tap_state_q <= RunTestIdle;
      idcode_q    <= IdcodeValue;
      bypass_q    <= 1'b0;
    end else begin
      tap_state_q <= tap_state_d;
      idcode_q    <= idcode_d;
      bypass_q    <= bypass_d;
    end
  end

  // Pass through JTAG signals to debug custom DR logic.
  // In case of a single TAP those are just feed-through.
  assign tck_o = tck_i;
  assign tdi_o = td_i;
  assign update_o = update_dr;
  assign shift_o = shift_dr;
  assign capture_o = capture_dr;
  assign dmi_clear_o = test_logic_reset;


endmodule : dmi_jtag_tap


