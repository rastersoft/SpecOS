# PREEMPTIVE MICROKERNEL FOR SINCLAIR SPECTRUM

This project is just a toy microkernel for the Sinclair Spectrum. The idea is
to create a simple multithread system for the Z80 processor.

## Architecture

The system is designed to work in 128K mode, but it doesn't need the +2A/+3
specific paging modes.

The microkernel is stored just after the screen memory, and sets the interrupt
system in IM2 mode. There is a table with 257 values used to ensure that the
interrupt servicing routine is called, no matter which value is available in the
bus when the interrupt occurs. Ideally it is 255, but some hardware can insert
spurious values, so the safest way is to fill this table with a single value
(currently it is 5B), and put the servicing routine at the address composed by
that byte (currently at 5B5B).

The maximum number of tasks and the stack size are fixed, but both can be easily
changed during compilation.

The tasks list is stored at the end of the third quarter of the memory, in the
page 2. The code can be stored in the page 2 and the page 5 (second and third
quarters of the memory). The fourth quarter is reserved for data, because is
where the paging mechanism allows to put any of the available pages. This model
presumes that there is much more data than code in the programs.

    +----------+
    |  Data    |
    |          |
    |          | Page 0 to 7
    |          |
    |C000-FFFF |
    +----------+
    |Tasks list|
    |and stacks|
    |          | Page 2
    |Tasks code|
    |8000-BFFF |
    +----------+
    |Tasks code|
    |Kernel    |
    |          | Page 5
    | Screen   |
    |4000-7FFF |
    +----------+
    |  ROM     |
    |          |
    |          |
    |          |
    |0000-3FFF |
    +----------+

## The tasks list

This list contains all the data needed to manage the tasks. Each entry has this
format:

     1 byte:  memory page at C000-FFFF for this task ($FF if this entry is empty)
     2 bytes: stack point address
     1 byte:  signal bits. Every time a task receives a signal, the corresponding
              signal bit is set here. The bit 6 has an special meaning: if it is
              0, this task is paused and won't run (even if it receives a signal).
              If it is 1, it can run, depending on bit 6 of the signal mask.
     1 byte:  signal mask. This task will be wake up only when it receives a
              signal which is marked in this mask
              bit 0: 50Hz signal
              bit 1: message received
              bit 2: key pressed
              bit 6: run/wait signal. If it is 1, this task will run whenever it
                     can; if it is 0, it will run only if it receives a signal
                     which is enabled in this mask
              bit 7: wait_next_loop. This is used to implement Round-Robin
     X bytes: task's stack

The location of this list is set in the source code with the PRTABLE definition.
The number of entries is defined in MAXPR, and the size for each entry is
defined in PRSIZE.

## Kernel functions

There are several functions available for the processes. There are entry points
located from address $BF02, with each one using 3 bytes. Calling the corresponding
entry point will call the function.

Before calling these functions it is mandatory to disable interrupts, and enable
them after.

The current functions are the follow ones:

  $BF02 : Set a memory bank from a memory pointer.
          Receives a memory pointer in HL; sets the memory bank at C000 and
          returns in HL the memory address

          Pointer format:   bcxxxxxx xxxxxxxa
          being abc three bits defining the RAM page where the pointer is
          located, and xxxxxxxxxxxxxxx0 the pointer itself.

  $BF05 : Launches a new task. Receives in HL the address where the code is.
          The task will receive in its registers the values contained in AF, BC and DE
          when calling this function.
          Returns C unset if all went fine; C set if there are no more tasks available


## TODO

 * Functions for waiting for an specific event
 * Memory management (malloc et al.)
 * Add a messaging system to allow IPC comunication
 * Read keyboard and mouse
 * C library
