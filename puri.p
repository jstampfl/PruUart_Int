// pruri.p
//  Copyright - John T. Stampfl 2014, You may use under the terms of the GNU General Public License .
//  Reads data using Uart, notified by interrupt
// Use PRUSS uart to read data from ADAFRUIT Ultimate GPS
// reads data to nl, put in buffer and signal linux side.
// using interrupts. 
// Depends on C program derived from PRU_memAccessPRtaRam.c
// which uses the prussdrv library to initalize the interrupts.
// ref:  https://github.com/beagleboard/am335x_pru_package
//
//  NOTE1:
//      I am setting bit 0 of the IER Uart register, which should be
//      the Rx event, which according to the list of interrupts in the
//      AM335x PRU-ICSS Reference Guide should be Sys Event 4, but 
//      Sys Event 6 is signaling.
//      In section 8.2.8.1 may be the explaination, which means the
//      list of events is confusing.
//
//      
//  NOTE2:
//        Routine RSET calling routine ALLEVT, which means the return 
//        will be overwritten by the CALL to ALLEVT.  It must be saved and 
//        restored.
//
//  NOTE3:
//        A good helpful reference is some code by Rob van de Schepop, 
//        posted on the TI e2e forum.
//        e2e.ti.com/support/arm/sitara_arm/f/791/t/239121.aspx
//        Also on elinux.org  - elinux.org/Ti_AM33XX_PRUSSv2
//
.setcallreg r2.w0  //  Going to use r31 for interrupt
.origin 0
.entrypoint TB
TB:
       ldi r20,0
       ldi r21,0
       ldi r22,0
       mov r0,0
       sbbo r0,r20,r21,4
       zero &r0,64             //zero 16 registers
TB05:
       sbbo r0,r20,r21,64      //zero some of pru0 local memory
       add r21,r21,64          // for linux string functions
       add r22,r22,1
       qbgt TB05,r22,20

       jmp ISET                //this is the routine to setup
                               //interrupts

TB1:
// See section 8.2.1 in the AM335x PRU-ICSS Reference Guide
//    for formula to compute the Uart divisor
       ldi r3,4               //Uart divisor  =1250 = 0x04E2
       sbco r3,c7,0x24,4      // 9600 at 16x
       ldi r3,0xE2            //in DLL & DLH
       sbco r3,c7,0x20,4

       ldi r3,1
       sbco r3,c7,4,4        // turn on receiver interupts
       lbco r3,c7,8,4        //read IIR to clear

       ldi r3,0x3             //LCR = 3, 8 none & 1
       sbco r3,c7,0x0C,4      //

       mov r3,0x6001          //Power &
       sbco r3,c7,0x30,4      // = tx on, rx on & Free to enable
       mov r5,0xFFFFFF
       ldi r4,0
       
       ldi r4,0              //zero some registers
       ldi r5,0
       ldi r3,0
       ldi r20,0
       ldi r21,0
       mov r9,276
       ldi r11,0

       ldi r24,0
       call RSET             // routine to clear & enable interrupts
                             //  and  get a character.

TB2:
       qbbc TB2,r31.t30     // spin here for interrupt

       call RSET            // clear, enable & read

       sbbo r3,r5,r4,1        // and put in buffer
       add r4,r4,1

       qbne TB2,r3,0xA        // do until nl received
       sbbo r20,r5,r4,1       // put null to terminate
       ldi r4,0               // zero buffer pointer
       mov r31.b0,35          // signal linux
       jmp TB2

TB9:    // an exit point used in debugging.  Not used here
       ldi r18,332            // offset to write errno
       sbbo r23,r18,0,4       // used for debugging
       HALT

ISET: //  This section is to initialize the interrupts
       mov r19,336            //point to printf in mem
       lbco r13,c4,4,4        //enable OCP master port
       clr r13,r13,4
       sbco r13,c4,4,4

       lbco r13,c4,0x2C,4        //disable MII_RT Events
       ldi r13,0                 // MII_RT Register in Pru cfg
       sbco r13,c4,0x2C,4

       mov  r15,0x10            //Turn off global interrupts
       lbco r14,c0,r15,4
       clr r14,r14,0
       sbco r14,c0,r15,4

       mov r15,0x400            //set up Channel map
       mov r14,0x09090909       // first map all unused events to
       sbco r14,c0,r15,4        //  Channel 9
       mov r15,0x408
       sbco r14,c0,r15,4
       mov r15,0x40C            // skiping offsets 410 & 414, they
       sbco r14,c0,r15,4        // were set by the C program via prussdrv
       mov r18,0x43C
       mov r15,0x414
TB43:
       add r15,r15,4
       sbco r14,c0,r15,4
       qbgt TB43,r15,r18
       mov r14,0x00000909
       mov r15,0x400            // now do offset 400
       sbco r14,c0,r15,4        // only allow events 2 & 3
       mov r14,0x09000000
       mov r15,0x404            // now do 404, which has the
       sbco r14,c0,r15,4        // entries for 4,5,6 the Uart interrupts

       ldi r15, 0x24             //clear all events
       call ALLEVT

       mov  r15,0x10
       ldi r14,0x1
       sbco r14,c0,r15,4

       ldi r15,0x28              // enable all events
       call ALLEVT
       jmp TB1

RSET:  // Routine to clear & enalbe system events, also host interrupts
       //  and read IIR in the Uart registers to clear the interrupt from
       // the Uart.  Also gets the character from the Uart buffer.
       mov r24,r2           // Save return address
                            // so can call ALLEVT
       mov r15,0x24         //  to clear system event
       call ALLEVT
       mov r15,0x28         //  to enable system event
       call ALLEVT
       lbco r3,c7,8,4        //read IIR to clear
       lbco r3,c7,0,4         //data is ready, get from RBR
       ldi r17,1
       sbco r17,c7,4,4        // turn on receive interupts
       mov r15,0x34          //HIEISR  to enable host interrupt
       ldi r14,0
       sbco r14,c0,r15,4
       mov r15,0x34          //HIEISR  to enable host interrupt
       ldi r14,2
       sbco r14,c0,r15,4
       mov r15,0x34          //HIEISR  to enable host interrupt
       ldi r14,3
       sbco r14,c0,r15,4
       mov r2,r24            // restore return address
       ret
       
ALLEVT:  //Insert the system envent in the proper resiger
         // register r15 must have the register offset
         // will only work with registers that take the event number
         // if you want to handle multiple events, just add 
         //   ldi r14,"sys event no."
         //   sbco r14, c0 ,r15,4

       ldi r14,0x6
       sbco r14, c0 ,r15,4
       ret
