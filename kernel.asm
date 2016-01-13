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
.DBG	defw 16384
	defs 74,0

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
	LD IY,PRTABLE
	LD B,MAXPR
	LD DE,PRSIZE
.INTP4	SET 0,(IY+3) ; set the 50Hz bit
	ADD IY,DE
	DJNZ INTP4
.STARTINT	LD IY,(CTABLE)
	LD (tmpsp),SP
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
	JR C,INTEND2
.INTP2	LD A,(IY+0)
	LD BC,$7FFD
	OUT (C),A ; set page used by this task
	LD (CTABLE),IY
	LD A,$7F
	AND A,(IY+4)
	LD (IY+4),A
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

.INTEND2	POP IY
	POP HL
	POP DE
	POP BC
	POP AF
	EI
	HALT

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
	AND A,(IY+4)
	AND A,$7F      ; Don't check the round-robin bit here
	JR Z,INTNFOUND
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
	AND H,$3F
	AND L,$FE
	AND A,$07
	OR A,$10
	LD BC,(CTABLE)
	LD (BC),A       ; store the currently used page in the current task entry
	LD BC,$7FFD
	OUT (C),A
	POP BC
	POP AF
	RET


; Creates a new task. Receives in HL the address where the code is.
; Returns C unset if all went fine; C set if there are no more tasks available
.NEWTASK	PUSH BC
	PUSH DE
	PUSH IY
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
	POP IY
	POP DE
	POP BC
	RET
.FND_FREE	XOR A
	LD (IY+0),A ; Page 0
	PUSH HL
	POP BC
	LD HL,PRSIZE-2
	PUSH IY
	POP DE
	ADD HL,DE
	LD (HL),C      ; "Push" the run address in the stack
	INC HL
	LD (HL),B
	LD HL,PRSIZE-REGISTERS
	PUSH IY
	POP DE
	ADD HL,DE
	LD (IY+1),L ; Stack address
	LD (IY+2),H
	LD A,$C0
	LD (IY+3),A
	LD (IY+4),A
	XOR A,A ; NO ERROR
	POP IY
	POP DE
	POP BC
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

	LD HL,CODE1
	CALL $BF05
	LD HL,CODE3
	CALL $BF05
	LD HL,CODE2
	CALL $BF05

	LD A,$BE
	LD I,A
	IM 2
	EI
.i2	JR i2

.CBTABLE	JP SETBANK
	JP NEWTASK
.CBTABLE2	defb 0

; three test tasks to see if this works fine

.CODE1	LD A,2
	CALL DEBUG8
	OUT (254),A
	LD A,R
	SET 7,A
	SET 6,A
	LD B,A
.CODE1LOOP	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	DJNZ CODE1LOOP
	CALL SWAPTASK
	JR CODE1

.CODE2	LD A,5
	CALL DEBUG8
	OUT (254),A
	HALT
	JR CODE2

.CODE3	LD A,6
	CALL DEBUG8
	OUT (254),A
	LD A,R
	SET 6,A
	LD B,A
.CODE3LOOP	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	NOP
	DJNZ CODE3LOOP
	CALL SWAPTASK
	JR CODE3


.NEXT2	RET

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
