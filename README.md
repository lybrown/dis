dis - Statically Tracing 6502 Disassembler
==========================================

dis creates XASM/MADS-compatible assembly code from a memory dump or an
executable. dis statically traces execution paths starting from code entry
points to mark which memory locations contain code. All other memory is treated
as data. dis traces through JMP, JSR and BXX branch instructions. It stops at
RTS, RTI and illegal instructions.

dis automatically determines code entry points when disassembling Atari XEX and
Commodore 64 PRG files.

Usage
-----

    Usage: dis [options] file...
      -e XXXX   Entry point(s)
      -d XXXX   Data location(s) - Disallow tracing as code
      -v XXXX   Vector(s), e.g. FFFA
      -o XXXX   Origin
      -l        Create labels
      -i        Emit illegal opcodes
      -x        Disassemble as Atari XEX file
      -p        Disassemble as Commodore 64 PRG file
      -verbose  Print info to STDERR

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

Disassemble Atari XEX file with labels:

    dis -x -l game.xex > game.asm

Disassemble Commodore 64 PRG file with labels and an additional entry point:

    dis -p -l -e 1000 game.prg > game.asm
