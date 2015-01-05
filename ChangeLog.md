0.4
---

- Renamed dis.pl to dis
- Renamed -e to -c
- Added -C to define constants
- Added -comment/-nocomment to control whether comments are emitted
- Added -call/-nocall to control whether callers are emitted
- Added -access/-noaccess to control whether accessors are emitted
- Added -extern/-noextern to emit/omit equates for out-of-range labels
- Added -t TYPE where TYPE can be raw, xex, prg or sap
- Added support for SAP files
- Added tracing between XEX segments
- Added user-defined labels, e.g. -c start=2000
- Added address ranges, e.g. -d screen=9000+3BF
- Added XEX segment identifiers, e.g. -c intro=1:2000 -c game=3:2000
- Added -dump to dump command-line options to option file
- Added -a to read options from an option file:

        ; Example dis option file
        type xex
        comment 1
        call 1
        access 1
        extern 1
        code start=2000
        data VCOUNT=D40B
        data screen=9000+3BF
        vector NMIVEC=FFFE
        arg sys.dop ; recursively read sys.dop
        arg hardware.dop

- Added example option files:

        hardware.dop - Atari hardware registers
        sys.dop - Atari system equates
        vid.dop - C64 VIC registers
        sid.dop - C64 SID registers
        cia.dop - C64 CIA registers
        6510.dop - C64 6510 registers
    
- Added detection of BIT jump, i.e. $2C:

            cmp #$20            ; 1155: C9 20
            bcc l115E           ; 1157: 90 05
            beq l114F           ; 1159: F0 F4
            lda #$01            ; 115B: A9 01
            dta $2C             ; 115D: 2C <--- Bit Jump
        l115E                   ; Callers: 1157
            lda #$00            ; 115E: A9 00
            sta $1166           ; 1160: 8D 66 11

0.3
---

- Fixed: Use f: instead of opt h-/dta a($FFFF)/opt h+ when possible
- Fixed: read files as binary to avoid problems with Windows CR/LF
- Fixed: Read whole files rather than line-by-line

0.2
---

- Added support for Atari XEX and Commodore 64 PRG file formats
- Added automatic determination of code entry points for XEX and PRG files

0.1
---

- Statically traces code from entry points that you provide in order to
  distinguish code from data
- Automatically generates labels if desired
- Emits XASM/MADS syntax
- Emits "a:" as needed when absolute addressing is used for zero page addresses
- Can generate labels for addresses in the middle of instructions, e.g. "l1234
  equ *-2". This occurs when BIT is used to skip an instruction, for example.
- Callers are annotated in a comment at every label so you can see who calls an
  address
- The current address and the raw data is annotated in a comment for every
  instruction
- Based on C= Hacking [opcode
  table](http://codebase64.org/doku.php?id=magazines:chacking1#opcodes_and_quasi-opcodes)
