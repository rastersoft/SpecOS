	defc prsize=32 ; size for each process table entry
	defc maxpr=5 ; maximum number of processes
	defc prtable=$BF00-(PRSIZE*MAXPR) ; address of the process table
	defc REGISTERS = 12 ; number of bytes used to store the registers when entering the task manager

	org $5B00
	JP main_start
; call address: 5B04
	JP callback
.jobs	defb 0
.ctable	defw 0  ; pointer to the current process table
.tmpsp	defw 0  ; to temporary store an SP register
.dbg	defw 16384
	defs 70,0

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
;    7 Wait_next_loop     // used to implement round-robin calling scheme; must be 1 here


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

.main_start	DI
	LD HL,$BF00
	LD DE,$BF01
	LD BC,$100
	LD A,$5B
	LD (HL),A
	LDIR
	LD HL,prtable
	LD DE,prtable+1
	LD BC,prsize*maxpr-1
	LD (HL),$FF
	LDIR ; Set process table contents to $FF
	LD HL,TMPDATA
	LD DE,PRTABLE
	LD BC,PRSIZE*2
	LDIR
	LD A,$BF
	LD I,A
	IM 2
	EI
.i2	JR i2

.tmpdata	DEFB 0
	DEFW PRTABLE+PRSIZE-REGISTERS
	DEFB $40
	DEFB $C0
	DEFS PRSIZE-7,0
	DEFW CODE1
	DEFB 0
	DEFW PRTABLE+2*PRSIZE-REGISTERS
	DEFB $40
	DEFB $C0
	DEFS PRSIZE-7,0
	DEFW CODE2

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


; System calls
; A: function to execute
; RETURN: C flag set if error; A: error code

.callback      CP A,0 ; pointer to address. Receives in HL a pointer, sets the bank and returns in HL the pointer address
	JR NZ,NEXT1
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
	PUSH BC
	LD BC,(CTABLE)
	LD (BC),A
	LD BC,$7FFD
	OUT (C),A
	POP BC
	RET

.NEXT1	CP A,1 ; creates a new process. Receives in DE the address where the code is
	JR NZ,NEXT2
	PUSH HL
	PUSH BC
	PUSH DE
	LD HL,PRTABLE ; process table address
	LD B,MAXPR ; search process table for an empty entry
	LD DE,PRSIZE
.NPRLOOP	LD A,(HL)
	CP A,$FF
	JR Z,FND_FREE
	ADD HL,DE
	DJNZ NPRLOOP
	SCF
	LD A,1 ; No more free tasks
	RET
.FND_FREE	POP DE
	PUSH HL
	XOR A
	LD (HL),A ; Page 0
	LD BC,PRSIZE-2
	ADD HL,BC
	PUSH HL
	LD (HL),E ; "Push" the run address in the stack
	INC HL
	LD (HL),D
	POP DE
	POP HL
	INC HL
	LD (HL),E ; Stack address
	INC HL
	LD (HL),D
	INC HL
	LD (HL),1
	INC HL
	LD (HL),1
	OR A,A
	RET
.NEXT2	RET

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
