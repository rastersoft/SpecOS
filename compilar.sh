#!/bin/bash

z80asm -v -b kernel.asm && ./bin2z80 kernel.bin kernel.z80 23296 23553 && fbzx kernel.z80
