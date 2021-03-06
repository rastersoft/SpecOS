	defc PRSIZE  = 32 ; size for each process table entry
	defc MAXPR   = 8 ; maximum number of processes
	defc PRTABLE = $BE00-(PRSIZE*MAXPR) ; address of the process table

	defc REGISTERS = 10 ; number of bytes used to store the registers
	                    ; when entering the task manager.
	                    ; Currently AF, BC, DE, HL and the return address

	org $5B00
	JP MAIN_START
.IDLETASK	defb 0      ; this is a false entry for an idle task, called when no task is ready
	defw IDLESP
	defb 0
	defb 0
	defb 0              ; PID is 0
	defw 0              ; 16 bytes for stack
	defw 0
	defw 0
.IDLESP	defw 0
	defw 0
	defw 0
	defw 0
	defw IDLECODE

.SPIN	defb 0              ; Counter for spinlocks and spinunlocks
.DBG	defw 16384
	defs 45,0

.IDLECODE	LD A,7
	OUT (254),A         ; A red border will show the current load of the processor
	HALT
	JR IDLECODE         ; just wait for an interrupt forever

; Data stored in each entry in the process table
; Memory page   (1 byte)  // last value sent to 7FFD; FF means this entry is empty
; Stack Pointer (2 bytes)
; Wakeup Bits   (1 byte)  // each bit is put to 1 when that condition is received, and compared with the Wakeup Mask
;    6 Run/Pause          // 0 if the process is paused, and 1 if it should run (but can be waiting for another signal if the Mask bit 6 is 0)
;    7 Wait_next_loop     // used to implement round-robin calling scheme; must be 1 by default
; Wakeup Mask   (1 byte)
;    0 Interrupt 50Hz     // if 1, wait for 50Hz interrupt
;    1 Message received   // if 1, wait for a message arriving
;    2 Key pressed        // if 1, wait for a keypress
;    6 Run/Wait Signal    // if 0, the process is waiting a signal, must not be run unless another signal enables it; if 1, should run
;    7 High priority      // if 1, will not honor the round-robin bit, being run as soon as possible
; PID
; Stack         (up to the end)

; pauses the current task and jumps to the next one
.SWAPTASK	DI
	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	LD A,2
	OUT (254),A
	JR STARTINT
; interrupt routine; do not relocate (must be at 5B5B)
; IY is reserved for pointing to the current task entry. Must not be modified in the tasks
.INTINIT	PUSH AF
	PUSH BC
	PUSH DE
	PUSH HL
	LD A,2
	OUT (254),A         ; set border to RED color during workload. The IDLE task will put it to WHITE, showing the CPU usage
	PUSH IX
	LD IX,PRTABLE
	LD B,MAXPR
	LD DE,PRSIZE
.INTP4	BIT 0,(IX+4)
	JR Z,INTP5
	SET 0,(IX+3)        ; set the 50Hz bit only if this task is waiting for it
.INTP5	ADD IX,DE
	DJNZ INTP4
	POP IX
.STARTINT	LD HL,0
	ADD HL,SP      ; Get SP at HL
	LD (IY+1),L
	LD (IY+2),H
.STARTINT2	CALL FINDNEXT
	JP NC,INTP2
	LD IY,PRTABLE
	LD B,MAXPR
	LD DE,PRSIZE
.INTP3	SET 7,(IY+3)        ; enable the round-robin bit
	ADD IY,DE
	DJNZ INTP3
	CALL FINDNEXT
	JR NC,INTP2
	LD IY,IDLETASK
.INTP2	LD A,(IY+0)
	LD BC,$7FFD
	OUT (C),A           ; set page used by this task
	RES 7,(IY+3)        ; reset the round-robin bit (this task has run this round)
	LD L,(IY+1)
	LD H,(IY+2)
	LD SP,HL
.INTEND	POP HL
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
	JP Z,INTNFOUND      ; If it is FF, its an empty entry
	BIT 6,(IY+3)
	JR Z,INTNFOUND      ; If bit 0 is 0, this process is paused and should not run
	BIT 7,(IY+4)
	JR NZ,INTLOOP2      ; If it is high priority, don't check round robin
	BIT 7,(IY+3)
	JR Z,INTNFOUND      ; If round-robin bit is 0, this process has run this loop
.INTLOOP2	LD A,(IY+3)
	AND (IY+4)
	AND $7F             ; Don't check the round-robin bit here
	JR Z,INTNFOUND
	LD A,$C0
	LD (IY+3),A
	LD A,(IY+4)
	AND $C0
	SET 6,A
	LD (IY+4),A
	RET
.INTNFOUND	LD DE,PRSIZE
	ADD IY,DE
	DJNZ INTLOOP1
	SCF
	RET

; Sets a memory bank from a memory pointer.
; Receives a memory pointer in HL; sets the memory bank and returns in HL the memory address
; Pointer format:   bcxxxxxx xxxxxxxa
; being **abc** three bits defining the RAM page where the pointer is located, and **11xxxxxxxxxxxxx1** the pointer itself.
.SETBANK	PUSH AF
	PUSH BC
	PUSH HL
	LD A,L
	RLC H
	RLA
	RLC H
	RLA
	AND $07
	OR $10
	LD (IY+0),A         ; store the currently used page in the current task entry
	LD BC,$7FFD
	OUT (C),A
	POP HL
	SET 6,H
	SET 7,H
	SET 0,L             ; a pointer is always odd, and have the bits 14 and 15 to 1 (is located at segment 4)
	POP BC
	POP AF
	RET


; Creates a new task. Receives in HL the address where the code is.
; The task will receive the values for AF, BC and DE passed when calling this function
; Returns C unset if all went fine; C set if there are no more tasks available
.NEWTASK	CALL SPINLOCK
	PUSH IX
	PUSH BC
	PUSH DE
	PUSH AF
	LD IX,PRTABLE       ; process table address
	LD B,MAXPR          ; search process table for an empty entry
	LD DE,PRSIZE
.NPRLOOP	LD A,(IX+0)
	CP A,$FF
	JR Z,FND_FREE
	ADD IX,DE
	DJNZ NPRLOOP
	SCF
	POP AF
	LD A,1              ; No more free tasks
	POP DE
	POP BC
	POP IX
	CALL SPINUNLOCK
	RET
.FND_FREE	LD A,$10
	LD (IX+0),A         ; Page 0
	PUSH HL
	POP BC
	LD HL,PRSIZE-1
	PUSH IX
	POP DE
	ADD HL,DE
	LD (HL),B           ; "Push" the run address in the stack
	DEC HL
	LD (HL),C
	DEC HL
	POP DE              ; Original value of AF
	LD (HL),D           ; "Push" AF
	DEC HL
	LD (HL),E
	DEC HL
	POP DE
	POP BC
	PUSH BC
	PUSH DE             ; Recover values for BC and DE
	LD (HL),B           ; "Push" BC
	DEC HL
	LD (HL),C
	DEC HL
	LD (HL),D           ; "Push" DE
	DEC HL
	LD (HL),E
	LD HL,PRSIZE-REGISTERS
	PUSH IX
	POP DE
	ADD HL,DE
	LD (IX+1),L         ; Stack address
	LD (IX+2),H
	LD A,$C0            ; Round-robin and run bits enabled
	LD (IX+3),A
	LD A,$40            ; Low priority
	LD (IX+4),A
	XOR A               ; No error
	POP DE
	POP BC
	POP IX
	CALL SPINUNLOCK
	RET

; ends the task specified in register A (or the current one if A=0), freeing all its resources
.ENDTASK	CALL SPINLOCK
	PUSH IX
	PUSH DE
	PUSH BC
	CP (IY+5)           ; Check if the task's PID being killed is the currently one active
	JR Z,ENDCURRENT
	CP 0                ; Check if the specified PID is 0, which means "kill me"
	JR NZ,ENDNOTCURRENT
.ENDCURRENT	PUSH IY
	POP IX
	CALL FREETASK
	JP STARTINT2        ; Jump to the next available task
.ENDNOTCURRENT	CP MAXPR
	JP NC,ENDRET        ; Return if value in A is too big
	LD IX,PRTABLE-PRSIZE
	LD B,A
	LD DE,PRSIZE
.ENDLOOP	ADD IX,DE
	DJNZ ENDLOOP
	CALL FREETASK
.ENDRET	POP BC
	POP DE
	POP IX
	CALL SPINUNLOCK
	RET
	
; frees the resources for the task pointed by IX
.FREETASK	PUSH AF
	LD A,$FF
	LD (IX+0),A
	POP AF
	RET

; waits for an event. The event mask is passed in A
; It presumes that there are no spinlocks remaining to be freed
.WAITEVENT	DI
	PUSH AF
	AND $3F             ; Pause the process
	BIT 7,(IY+4)        ; Keep the high-priority bit
	JR Z,WAITEVENT2
	SET 7,A
.WAITEVENT2	LD (IY+4),A
	POP AF
	JP SWAPTASK

; Allocates a block of memory and returns a pointer to it in HL
; The desired size must be passed in DE, and must be smaller than 16381
; If there is not enough free memory, will return with carry flag set
.MALLOC	CALL SPINLOCK
	PUSH BC
	PUSH DE
	PUSH IX
	SET 0,E             ; Ensure that it is an odd size
	INC DE
	INC DE
	INC DE              ; Take into account the extra three bytes needed
	LD A,$10
	CALL CHECK_FREE
	JR NC,DO_MALLOC
	LD A,$11
	CALL CHECK_FREE
	JR NC,DO_MALLOC
	LD A,$13
	CALL CHECK_FREE
	JR NC,DO_MALLOC
	LD A,$14
	CALL CHECK_FREE
	JR NC,DO_MALLOC
	LD A,$16
	CALL CHECK_FREE
	JR NC,DO_MALLOC
	LD A,$17
	CALL CHECK_FREE
	JR C,MALLOC_ERROR
.DO_MALLOC	PUSH AF
	LD A,(IY+5)         ; Get PID
	LD (IX+0),A
	LD L,(IX+1)
	LD H,(IX+2)         ; Get current block size in HL
	PUSH DE
	DEC DE
	DEC DE
	DEC DE              ; Store the true size
	LD (IX+1),E
	LD (IX+2),D         ; Block size to the desired malloc size
	POP DE
	PUSH IX
	ADD IX,DE           ; Jump to "next block"
	XOR A
	SBC HL,DE           ; Substract to the original block size the size taken
	LD (IX+0),A         ; Free block
	LD (IX+1),L
	LD (IX+2),H         ; New size for the free block
	POP HL
	INC HL
	INC HL
	INC HL              ; Now HL points to the memory block. This adress has 11xxxxxxxxxxxxx1 format
	POP AF
	BIT 0,A
	JR NZ,MALLOC1
	RES 6,H
.MALLOC1	BIT 1,A
	JR NZ,MALLOC2
	RES 7,H
.MALLOC2	BIT 2,A
	JR NZ,MALLOC_RET
	RES 0,L
	JR MALLOC_RET
.MALLOC_ERROR	SCF
.MALLOC_RET	LD A,(IY+0)         ; restore the memory page in the current task
	LD BC,$7FFD
	OUT (C),A
	POP IX
	POP DE
	POP BC
	CALL SPINUNLOCK
	RET

; Frees a memory block allocated with malloc
; Receives in HL a pointer to the block
.FREE	CALL SPINLOCK
	PUSH HL
	PUSH AF
	CALL SETBANK
	DEC HL
	DEC HL
	DEC HL              ; HL now points to the start block
	XOR A
	LD (HL),A           ; Free block
	CALL JOIN_BLOCKS    ; Join free blocks
	POP AF
	POP HL
	CALL SPINUNLOCK
	RET

; Joins in a single block all free, contiguous memory blocks in the current page
.JOIN_BLOCKS	PUSH AF
	PUSH DE
	PUSH HL
	PUSH IX
	LD IX,$C000
.JOIN1	LD A,(IX+0)
	CP $FF              ; End of list?
	JR Z,JOIN_END
.JOIN3	LD E,(IX+1)
	LD D,(IX+2)
	CP 0                ; Free block?
	JR Z,JOIN2
	ADD IX,DE
	INC IX
	INC IX
	INC IX              ; Next block
	JR JOIN1
.JOIN2	PUSH IX
	ADD IX,DE
	INC IX
	INC IX
	INC IX              ; Next block
	LD A,(IX+0)
	LD L,(IX+1)
	LD H,(IX+2)
	CP 0	     ; Next block is free?
	JR NZ,JOIN4
	POP IX
	ADD HL,DE           ; Add both sizes
	INC HL
	INC HL
	INC HL              ; Add the second block's header size
	LD (IX+1),L
	LD (IX+2),H         ; Grow the first free block
	JR JOIN3            ; Continue checking if there are more free blocks
.JOIN4	POP HL              ; Remove the value in the stack and continue with the next block
	JR JOIN1
.JOIN_END	POP IX
	POP HL
	POP DE
	POP AF
	RET

; Checks the page passed in A if there is free space enough to fulfill DE bytes
; If true, returns at IX the block address; if not, will return with carry
; flag set
.CHECK_FREE	PUSH HL
	PUSH AF
	LD BC,$7FFD
	OUT (C),A           ; set the desired memory page
	LD IX,$C000
.CHECK_FREE1	LD A,(IX+0)
	CP $FF
	JR Z,CHECK_FREE4    ; End of list
	LD C,(IX+1)
	LD B,(IX+2)
	CP A,0              ; Free block?
	JR NZ,CHECK_FREE2
	PUSH BC
	POP HL
	AND A               ; Unset carry flag
	SBC HL,DE           ; Check if in this free block is bigger enough
	JR NC,CHECK_FREE3   ; If DE is bigger than the block size, try next; if not, this is the block
.CHECK_FREE2	ADD IX,BC           ; Next block
	INC IX
	INC IX
	INC IX
	JR CHECK_FREE1
.CHECK_FREE4	SCF
.CHECK_FREE3	POP BC
	LD A,B              ; Recover the memory page without altering the carry flag
	POP HL
	RET

.SPINLOCK	DI
	PUSH AF
	LD A,(SPIN)
	INC A
	LD (SPIN),A
	POP AF
	RET

.SPINUNLOCK	PUSH AF
	LD A,(SPIN)
	AND A
	JR Z,SPINEND
	DEC A
	LD (SPIN),A
	JR NZ,SPINEND2
.SPINEND	EI
.SPINEND2	POP AF
	RET

; Initalizates the blocks in each memory page
; Each block contains, at the start, a table:

;    1 byte  : owner's PID (or 0 for a free block, or FF for last entry in list)
;    2 bytes : block size

; Blocks are arranged as a linked list, and ends with an FF byte
.INIT_MEMORY	LD BC,$7FFD
	OUT (C),A
	XOR A
	LD ($C000),A
	LD BC,$3FFC
	LD ($C001),BC
	LD A,$FF
	LD ($FFFF),A
	RET
	

; Initializates everything
.MAIN_START	DI

	LD HL,IDLECODE      ; Set the stack in FREEZONE to allow to change
	LD SP,HL            ; the page at $C000-FFFF

	LD HL,$BE00
	LD DE,$BE01
	LD BC,$100
	LD (HL),$5B
	LDIR                ; Create a table with 257 "$5B" values

	LD HL,PRTABLE
	LD DE,PRTABLE+1
	LD BC,PRSIZE*MAXPR-1
	LD (HL),$FF
	LDIR                ; Set process table contents to $FF
	LD IX,PRTABLE
	LD DE,PRSIZE
	LD B,MAXPR
	LD A,1              ; First PID will be 1
.PIDLOOP	LD (IX+5),A         ; Set the PID (which will be associated with the possition in the task table)
	INC A
	ADD IX,DE
	DJNZ PIDLOOP

	LD HL,CBTABLE
	LD DE,$BF02
	LD BC,CBTABLE2-CBTABLE
	LDIR                ; Copy the callback table

	LD A,$10
	CALL INIT_MEMORY
	LD A,$11
	CALL INIT_MEMORY
	LD A,$13
	CALL INIT_MEMORY
	LD A,$14
	CALL INIT_MEMORY
	LD A,$16
	CALL INIT_MEMORY
	LD A,$17
	CALL INIT_MEMORY    ; Pages 2 and 5 aren't initializated because
	                    ; they are paged in other zones

	LD HL,TESTTASK2
	LD DE,$0505
	LD C,0
	CALL $BF05          ; Tests high priority tasks

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

	LD DE,$0C09
	LD C,2
	LD HL,TESTTASK
	CALL $BF05

	LD DE,$090B
	LD C,0
	LD HL,TESTTASK
	CALL $BF05

	LD DE,$0C12
	LD C,1
	LD HL,TESTTASK
	CALL $BF05

	LD DE,$150F
	LD C,3
	LD HL,TESTTASK
	CALL $BF05

.I3	LD A,$BE
	LD I,A
	IM 2
	EI
.I2	JR I2

.CBTABLE	JP SETBANK
	JP NEWTASK
	JP ENDTASK
	JP WAITEVENT
	JP MALLOC
	JP FREE
	JP SPINLOCK
	JP SPINUNLOCK
.CBTABLE2	defb 0


.TESTTASK2	SET 7,(IY+4)        ; This will be a high-priority task
.TESTTASK2B	LD A,$06
	LD BC,$FFFE
	OUT (C),A
	LD B,255
.TT2	NOP
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
	DJNZ TT2
	LD A,1
	CALL $BF0B
	JR TESTTASK2B

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
	CP 2
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
	HALT
	JR TESTLOOP
	LD B,3
	LD A,1
.TEST7	CALL $BF0B
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
