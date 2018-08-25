dis - Statically Tracing 6502 Disassembler
==========================================

dis creates XASM/MADS-compatible assembly code from a memory dump or an
executable. dis statically traces execution paths starting from code entry
points to mark which memory locations contain code. All other memory is treated
as data. dis traces through JMP, JSR and BXX branch instructions. It stops at
RTS, RTI and illegal instructions.

dis automatically determines common code entry points when disassembling Atari
XEX/SAP files and Commodore 64 PRG files.

Usage
-----

    Usage: dis [options] file...
      -c L=XXXX  Code entry point(s)
      -d L=XXXX  Data location(s) - Disallow tracing as code
      -C L=XXXX  Constant value(s)
      -v L=XXXX  Vector(s), e.g. FFFA
      -A L=XXXX  Data address(es)
      -P L=XXXX  Code address(es) - Trace target as code
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
      -extern    Emit labels for out-of-range addresses
      -rangelabels Emit labels for ranges instead of base+offset
      -verbose   Print info to STDERR
      -dump      Print options in format for -a
      -dumpequ   Print equ statements for all labels
      -headers   Print opt h- if disabled with -noheaders
      -a FILE    Read options from FILE. Lines are: OPTION VALUE
    
      Addresses may include a range, e.g. table=$300+F
      Addresses may include xex segment number, e.g. 3:1FAE
      Addresses for -A and -P may be given as HIGH_LOW, e.g. 3C64_3C62

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

Disassemble Atari SAP file with option files:

    dis -t sap -l -a hardware.dop -a sys.dop A_Type.sap > A_Type.asm

Disassemble XEX and trace through a code vector located in non-consecutive
hi/lo bytes (for example in LDX/LDY immediate instructions):

    dis -P vbiptr=3C64_3C62 game.xex > game.asm

Indirect Addresses
------------------

The -A option can be used to tell dis to treat bytes in the binary as an
address or list of addresses. Use the range "+" syntax to indicate a list.  dis
assumes that addresses in a list are organized as low/high/low/high. For
example, -A levelname\_tbl=3F5F+15 might produce the following:

    levelname_tbl
        dta <l5EA0          ; 3F5F: A0 Access: 3F0F <--- Data
        dta >l5EA0          ; 3F60: 5E Access: 3F14 <--- Data
        dta <l5ED0          ; 3F61: D0 <--- Data
        dta >l5ED0          ; 3F62: 5E <--- Data
        dta <l5F00          ; 3F63: 00 <--- Data
        dta >l5F00          ; 3F64: 5F <--- Data
    ...

The -C option is similar to -A but is used for code addresses. The target
addresses found in the specified bytes are then automatically traced as code.

Both the -A and -C options can accept two addresses separated by an underscore.
This indicates non-consecutive addresses for the high and low bytes of the
target address, e.g. vbiadr=3C64\_3C62. This can be combined with the range
syntax to specify a list of addresses where the high and low bytes are in
separate tables, e.g. jumptbl=3130\_3140+F.

Both data and code target addresses will be emitted using "<" and ">" as
appropriate. For example:

    setvbi                  ; Callers: -c 3C61 3B62
        ldy <vbi            ; 3C61: A0 6B
        ldx >vbi            ; 3C63: A2 3C
        lda #$07            ; 3C65: A9 07
        jsr SETVBV          ; 3C67: 20 5C E4

Option Files
------------

Option files can be used to store multiple command-line options, one option per
line. Multiple option files can be passed to dis by repeating the -a option.
Each one-character command-line option has a corresponding directive for use in
an option file:

    A  address
    a  arg
    c  code
    C  constant
    d  data
    h  help
    i  illegal
    l  labels
    o  org
    P  codeptr
    p  prg
    t  type
    v  vector
    x  xex

The option file directive is the same as the command-line option name for other
options.

Here is an excerpt from an example option file used for disassembling Twilight
World on the Atari XL/XE:

    ; Comments start with a semicolon
    code initquest=3BDF
    code resethero=3BFF
    code resetanimations=3C27
    data initframecounts=3C3B+12
    data initanimcounts=3C4E+12
    code setvbi=3C61
    code vbi=3C6B
    code vbidone=3C97
    code dogamephase=3C9A
    code dophase3=3CB3
    code dophase2=3CDC
    codeptr vbiptr=3C64_3C62
    data waitframecount_tbl=3F59+5
    address levelname_tbl=3F5F+15

AtariAge Thread
---------------

[Statically Tracing 6502 Disassembler](http://atariage.com/forums/topic/232658-statically-tracing-6502-disassembler/)
