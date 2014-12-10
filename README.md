dis - Statically Tracing 6502 Disassembler
==========================================

dis creates XASM/MADS-compatible assembly code from a memory dump. dis
statically traces from code entry points to mark which memory locations contain
code. All other memory is treated as data. dis traces through JMP, JSR and BXX
branch instructions. It stops at RTS, RTI and illegal instructions.

Usage
-----

    Usage: dis [-e XXXX]* [-d XXXX]* [-v XXXX]* [-o XXXX] -l -i file...
      -e XXXX   Entry point(s)
      -d XXXX   Data location(s) (Disallow tracing as code)
      -v XXXX   Vector(s), e.g. FFFA
      -o XXXX   Origin
      -l        Create labels
      -i        Emit illegal opcodes

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
