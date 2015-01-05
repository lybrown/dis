dis - Statically Tracing 6502 Disassembler
==========================================

dis creates XASM/MADS-compatible assembly code from a memory dump or an
executable. dis statically traces execution paths starting from code entry
points to mark which memory locations contain code. All other memory is treated
as data. dis traces through JMP, JSR and BXX branch instructions. It stops at
RTS, RTI and illegal instructions.

dis automatically determines code entry points when disassembling Atari XEX/SAP
files and Commodore 64 PRG files.

Usage
-----

    Usage: dis [options] file...
      -c L=XXXX  Code entry point(s)
      -d L=XXXX  Data location(s) - Disallow tracing as code
      -C L=XXXX  Constant value(s)
      -v L=XXXX  Vector(s), e.g. FFFA
      -o L=XXXX  Origin for raw files
      -l         Create labels
      -i         Emit illegal opcodes
      -t TYPE    Dissasseble as TYPE
                 xex - Atari executable (-x)
                 sap - Atari SAP file
                 prg - Commodore 64 executable (-p)
                 raw - raw memory
      -comment   Emit comments
      -call      Emit callers
      -access    Emit accessors
      -verbose   Print info to STDERR
      -dump      Print options in format for -a
      -a FILE    Read options from FILE. Lines are: OPTION VALUE
    
      Addresses may include xex segment number, e.g. 3:1FAE

Examples
--------

Disassemble as pure data:

    dis data.mem > data.asm

Disassemble 64K memory dump. Trace code starting at hex $1000:

    dis -e 1000 game.mem > game.asm

Disassamble 64K memory dump. Trace code starting at $1000 and $9006. Trace code
that is vectored from $FFFE. Mark $9101 as data, e.g. data after an
always-taken branch:

    dis -e 1000 -e 9006 -v FFFE -d 9101 game.mem > game.asm

Disassemble partial memory dump as if it started at $1000:

    dis -o 1000 -e 1000 game.mem > game.asm

Disassemble Atari XEX file with segment-specific user-defined labels:

    dis -x -l -c intro=1:2000 -c game=3:2000 game.xex > game.asm

Disassemble Commodore 64 PRG file with labels and an additional entry point:

    dis -p -l -e 1000 game.prg > game.asm

Disassemble Atari SAP file with option file:

    dis -t sap -l -a hardware.dop A-Type.sap > A_Type.asm

AtariAge Thread
---------------

[Statically Tracing 6502 Disassembler](http://atariage.com/forums/topic/232658-statically-tracing-6502-disassembler/)
