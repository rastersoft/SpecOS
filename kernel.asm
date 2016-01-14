	defc PRSIZE=32 ; size for each process table entry
	defc MAXPR=5 ; maximum number of processes
	defc PRTABLE=$BE00-(PRSIZE*MAXPR) ; address of the process table

	defc REGISTERS = 12 ; number of bytes used to store the registers
	                    ; when entering the task manager.
	                    ; Currently AF, BC, DE, HL, IY and the return address

	org $5B00
	JP MAIN_START
.CTABLE	defw 0     ; pointer to the current process table
.TMPSP	defw 0     ; to temporary store an SP register, since there is only LD (nn),SP instruction

.IDLETASK	defb 0     ; this is a false entry for an idle task, called when no task is ready
	defw IDLESP
	defb 0
	defb 0
	defw 0  ; 16 bytes for stack
	defw 0
.IDLESP	defw 0
	defw 0
	defw 0
	defw 0
	defw 0
	defw IDLECODE

.DBG	defw 16384
	defs 45,0

.IDLECODE	LD A,7
	OUT (254),A ; A red border will show the current load of the processor
	HALT
	JR IDLECODE ; just wait for an interrupt forever

; Data stored in each entry in the process table
; Memory page   (1 byte)  // last value sent to 7FFD; FF means this entry is empty
; Stack Pointer (2 bytes)
; Wakeup Bits   (1 byte)  // each bit is put to 1 when that condition is received, and compared with the Wakeup Mask
;    6 Run/Pause          // 0 if the process is paused, and 1 if it should run (but can be waiting for another signal if the Mask bit 6 is 0)
; Wakeup Mask   (1 byte)
;    0 Interrupt 50Hz     // if 1, wait for 50Hz interrupt
;    1 Message received   // if 1, wait for a message arriving
;    2 Key pressed        // if 1, wait for a keypress
;    6 Run/Wait Signal    // if 0, the process is waiting a signal, must not be run unless another signal enables it; if 1, should run
;    7 Wait_next_loop     // used to implement round-robin calling scheme; must be 1 by default
; Stack         (up to the end)

.SWAPTASK	DI
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IY
	JR STARTINT
; interrupt routine; do not relocate (must be at 5B5B)
.INTINIT	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	PUSH IY
	LD A,2
	OUT (254),A  ; set border to RED color during workload. The IDLE task will put it to WHITE, showing the CPU usage
	LD IY,PRTABLE
	LD B,MAXPR
	LD DE,PRSIZE
.INTP4	BIT 0,(IY+4)
	JR Z,INTP5
	SET 0,(IY+3) ; set the 50Hz bit only if this task is waiting for it
.INTP5	ADD IY,DE
	DJNZ INTP4
.STARTINT	LD IY,(CTABLE)
	LD (TMPSP),SP
	LD BC,(TMPSP)
	LD (IY+1),C
	LD (IY+2),B
	CALL FINDNEXT
	JP NC,INTP2
	LD IY,PRTABLE
	LD B,MAXPR
	LD DE,PRSIZE
.INTP3	SET 7,(IY+4) ; reset the round-robin bit
	ADD IY,DE
	DJNZ INTP3
	CALL FINDNEXT
	JR NC,INTP2
	LD IY,IDLETASK
.INTP2	LD A,(IY+0)
	LD BC,$7FFD
	OUT (C),A ; set page used by this task
	LD (CTABLE),IY
	RES 7,(IY+4)
	LD L,(IY+1)
	LD H,(IY+2)
	LD SP,HL
.INTEND	POP IY
	POP HL
	POP DE
	POP BC
	POP AF
	EI
	RET

; Returns in IY the next table entry of the next task to run. If there is no task, sets CF
.FINDNEXT	LD IY,PRTABLE
	LD B,MAXPR
.INTLOOP1	LD A,(IY+0)
	CP A,$FF
	JP Z,INTNFOUND ; If it is FF, its an empty entry
	BIT 6,(IY+3)
	JR Z,INTNFOUND ; If bit 0 is 0, this process is paused and should not run
	BIT 7,(IY+4)
	JR Z,INTNFOUND ; If round-robin bit is 0, this process has run this loop
	LD A,(IY+3)
	AND (IY+4)
	AND $7F        ; Don't check the round-robin bit here
	JR Z,INTNFOUND
	LD A,$C0
	LD (IY+3),A
	LD (IY+4),A    ; Remove the mask conditions and the signals
	RET
.INTNFOUND	LD DE,PRSIZE
	ADD IY,DE
	DJNZ INTLOOP1
	SCF
	RET

; Sets a memory bank from a memory pointer.
; Receives a memory pointer in HL; sets the memory bank and returns in HL the memory address
; Pointer format:   bcxxxxxx xxxxxxxa
; being abc three bits defining the RAM page where the pointer is located, and xxxxxxxxxxxxxxx0 the pointer itself.
.SETBANK	PUSH AF
	PUSH BC
	LD A,L
	RLC H
	RLA
	RLC H
	RLA
	RRC H
	RRC H
	PUSH AF
	LD A,H
	AND $3F
	LD H,A
	LD A,L
	AND $FE
	LD L,A
	POP AF
	AND $07
	OR $10
	LD BC,(CTABLE)
	LD (BC),A       ; store the currently used page in the current task entry
	LD BC,$7FFD
	OUT (C),A
	POP BC
	POP AF
	RET


; Creates a new task. Receives in HL the address where the code is.
; The task will receive the values for AF, BC and DE passed when calling this function
; Returns C unset if all went fine; C set if there are no more tasks available
.NEWTASK	PUSH IY
	PUSH BC
	PUSH DE
	PUSH AF
	LD IY,PRTABLE  ; process table address
	LD B,MAXPR     ; search process table for an empty entry
	LD DE,PRSIZE
.NPRLOOP	LD A,(IY+0)
	CP A,$FF
	JR Z,FND_FREE
	ADD IY,DE
	DJNZ NPRLOOP
	SCF
	LD A,1         ; No more free tasks
	POP AF
	POP DE
	POP BC
	POP IY
	RET
.FND_FREE	XOR A
	LD (IY+0),A    ; Page 0
	PUSH HL
	POP BC
	LD HL,PRSIZE-1
	PUSH IY
	POP DE
	ADD HL,DE
	LD (HL),B      ; "Push" the run address in the stack
	DEC HL
	LD (HL),C
	DEC HL
	POP DE         ; Original value of AF
	LD (HL),D      ; "Push" AF
	DEC HL
	LD (HL),E
	DEC HL
	POP DE
	POP BC
	PUSH BC
	PUSH DE        ; Recover values for BC and DE
	LD (HL),B      ; "Push" BC
	DEC HL
	LD (HL),C
	DEC HL
	LD (HL),D      ; "Push" DE
	DEC HL
	LD (HL),E
	LD HL,PRSIZE-REGISTERS
	PUSH IY
	POP DE
	ADD HL,DE
	LD (IY+1),L    ; Stack address
	LD (IY+2),H
	LD A,$C0       ; Round-robin and run bits enabled
	LD (IY+3),A
	LD (IY+4),A
	XOR A          ; NO ERROR
	POP DE
	POP BC
	POP IY
	RET


.MAIN_START	DI

	LD HL,$BE00
	LD DE,$BE01
	LD BC,$100
	LD (HL),$5B
	LDIR              ; Create a table with 257 "$5B" values

	LD HL,PRTABLE
	LD DE,PRTABLE+1
	LD BC,PRSIZE*MAXPR-1
	LD (HL),$FF
	LDIR              ; Set process table contents to $FF

	LD HL,CBTABLE
	LD DE,$BF02
	LD BC,CBTABLE2-CBTABLE
	LDIR              ; Copy the callback table

	LD HL,TESTTASK
	LD DE,$0505
	LD C,0
	CALL $BF05
	LD DE,$1007
	LD C,1
	LD HL,TESTTASK
	CALL $BF05
	LD DE,$0515
	LD C,2
	LD HL,TESTTASK
	CALL $BF05
	LD DE,$0802
	LD C,3
	LD HL,TESTTASK
	CALL $BF05

	LD A,$BE
	LD I,A
	IM 2
	EI
.I2	JR I2

.CBTABLE	JP SETBANK
	JP NEWTASK
.CBTABLE2	defb 0


; BOUNCES A BALL
.TESTTASK	PUSH DE
	POP HL
.TESTLOOP	CALL DELBALL
	BIT 0,C
	JR Z,TEST1
	INC H
	LD A,H
	CP 23
	JR NZ,TEST3
	RES 0,C
	JR TEST3
.TEST1	DEC H
	LD A,H
	CP 0
	JR NZ,TEST3
	SET 0,C
.TEST3	BIT 1,C
	JR Z,TEST4
	INC L
	LD A,L
	CP 31
	JR NZ,TEST6
	RES 1,C
	JR TEST6
.TEST4	DEC L
	LD A,L
	CP 0
	JR NZ,TEST6
	SET 1,C
.TEST6	CALL PRINTBALL
	LD B,3
.TEST7	DI
	LD IY,(CTABLE)
	SET 0,(IY+4) ; Wait for the 50Hz signal
	RES 6,(IY+4) ; Pause it
	CALL SWAPTASK
	DJNZ TEST7
	JR TESTLOOP



; paints a ball at H,L coordinates
.PRINTBALL	PUSH AF
	PUSH HL
	CALL GETBALL
	LD (HL),$3C
	INC H
	LD (HL),$7E
	INC H
	LD (HL),$FF
	INC H
	LD (HL),$FF
	INC H
	LD (HL),$FF
	INC H
	LD (HL),$FF
	INC H
	LD (HL),$7E
	INC H
	LD (HL),$3C
	POP HL
	POP AF
	RET

.DELBALL	PUSH AF
	PUSH BC
	PUSH HL
	CALL GETBALL
	LD B,8
.DELBALL1	LD (HL),0
	INC H
	DJNZ DELBALL1
	POP HL
	POP BC
	POP AF
	RET

.GETBALL	LD A,L
	AND $1F
	LD L,A
	LD A,H
	RRCA
	RRCA
	RRCA
	AND $E0
	OR L
	LD L,A
	LD A,H
	AND $18
	OR $40
	BIT 5,A
	JR Z,GETBALL2
	RES 4,A
.GETBALL2	LD H,A
	RET

; these functions allow to debug the code, by printing the content of register A or BC in screen (in binary form)
.DEBUG8	PUSH HL
	PUSH AF
	LD A,170
	LD HL,(DBG)
	LD (HL),A
	INC H
	POP AF
	LD (HL),A
	LD HL,(DBG)
	INC L
	INC L
	LD (DBG),HL
	POP HL
	RET

.DEBUG16	PUSH HL
	PUSH AF
	LD A,170
	LD HL,(DBG)
	LD (HL),A
	INC L
	LD (HL),A
	DEC L
	INC H
	LD A,B
	LD (HL),A
	INC L
	LD A,C
	LD (HL),A
	LD HL,(DBG)
	INC L
	INC L
	INC L
	LD (DBG),HL
	POP AF
	POP HL
	RET
