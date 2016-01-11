#!/bin/bash

z80asm -v -b kernel.asm && ./bin2z80 kernel.bin kernel.z80 23296 23296 && fbzx kernel.z80
cat kernel.err
