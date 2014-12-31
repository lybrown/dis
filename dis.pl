#!/usr/bin/perl
# Copyright (C) 2014 Lyren Brown
use strict;
use warnings;
use Getopt::Long;
use open IN => ':raw'; # binary mode

# Opcode table taken from C= Hacking Issue 1
# http://www.ffd2.com/fridge/chacking/
# http://codebase64.org/doku.php?id=magazines:chacking1#opcodes_and_quasi-opcodes
# Changes:
# - Corrected opcode $46
# - Added missing opcode $5E
my $spec = q{
Std Mnemonic Hex Value Description                Addressing Mode  Bytes/Time 
*   BRK      $00       Stack <- PC, PC <- ($fffe) (Immediate)      1/7
*   ORA      $01       A <- (A) V M               (Ind,X)          6/2
    JAM      $02       [locks up machine]         (Implied)        1/-
    SLO      $03       M <- (M >> 1) + A + C      (Ind,X)          2/8
    NOP      $04       [no operation]             (Z-Page)         2/3
*   ORA      $05       A <- (A) V M               (Z-Page)         2/3
*   ASL      $06       C <- A7, A <- (A) << 1     (Z-Page)         2/5
    SLO      $07       M <- (M >> 1) + A + C      (Z-Page)         2/5
*   PHP      $08       Stack <- (P)               (Implied)        1/3
*   ORA      $09       A <- (A) V M               (Immediate)      2/2
*   ASL      $0A       C <- A7, A <- (A) << 1     (Accumulator)    1/2
    ANC      $0B       A <- A /\ M, C=~A7         (Immediate)      1/2
    NOP      $0C       [no operation]             (Absolute)       3/4
*   ORA      $0D       A <- (A) V M               (Absolute)       3/4
*   ASL      $0E       C <- A7, A <- (A) << 1     (Absolute)       3/6
    SLO      $0F       M <- (M >> 1) + A + C      (Absolute)       3/6
*   BPL      $10       if N=0, PC = PC + offset   (Relative)       2/2'2
*   ORA      $11       A <- (A) V M               ((Ind),Y)        2/5'1
    JAM      $12       [locks up machine]         (Implied)        1/-
    SLO      $13       M <- (M >. 1) + A + C      ((Ind),Y)        2/8'5
    NOP      $14       [no operation]             (Z-Page,X)       2/4
*   ORA      $15       A <- (A) V M               (Z-Page,X)       2/4
*   ASL      $16       C <- A7, A <- (A) << 1     (Z-Page,X)       2/6
    SLO      $17       M <- (M >> 1) + A + C      (Z-Page,X)       2/6
*   CLC      $18       C <- 0                     (Implied)        1/2
*   ORA      $19       A <- (A) V M               (Absolute,Y)     3/4'1
    NOP      $1A       [no operation]             (Implied)        1/2
    SLO      $1B       M <- (M >> 1) + A + C      (Absolute,Y)     3/7
    NOP      $1C       [no operation]             (Absolute,X)     2/4'1
*   ORA      $1D       A <- (A) V M               (Absolute,X)     3/4'1
*   ASL      $1E       C <- A7, A <- (A) << 1     (Absolute,X)     3/7
    SLO      $1F       M <- (M >> 1) + A + C      (Absolute,X)     3/7
*   JSR      $20       Stack <- PC, PC <- Address (Absolute)       3/6
*   AND      $21       A <- (A) /\ M              (Ind,X)          2/6
    JAM      $22       [locks up machine]         (Implied)        1/-
    RLA      $23       M <- (M << 1) /\ (A)       (Ind,X)          2/8
*   BIT      $24       Z <- ~(A /\ M) N<-M7 V<-M6 (Z-Page)         2/3 
*   AND      $25       A <- (A) /\ M              (Z-Page)         2/3
*   ROL      $26       C <- A7 & A <- A << 1 + C  (Z-Page)         2/5
    RLA      $27       M <- (M << 1) /\ (A)       (Z-Page)         2/5'5
*   PLP      $28       A <- (Stack)               (Implied)        1/4
*   AND      $29       A <- (A) /\ M              (Immediate)      2/2
*   ROL      $2A       C <- A7 & A <- A << 1 + C  (Accumulator)    1/2
    ANC      $2B       A <- A /\ M, C <- ~A7      (Immediate)      1/2     
*   BIT      $2C       Z <- ~(A /\ M) N<-M7 V<-M6 (Absolute)       3/4
*   AND      $2D       A <- (A) /\ M              (Absolute)       3/4
*   ROL      $2E       C <- A7 & A <- A << 1 + C  (Absolute)       3/6
    RLA      $2F       M <- (M << 1) /\ (A)       (Absolute)       3/6'5
*   BMI      $30       if N=1, PC = PC + offset   (Relative)       2/2'2
*   AND      $31       A <- (A) /\ M              ((Ind),Y)        2/5'1
    JAM      $32       [locks up machine]         (Implied)        1/-
    RLA      $33       M <- (M << 1) /\ (A)       ((Ind),Y)        2/8'5
    NOP      $34       [no operation]             (Z-Page,X)       2/4
*   AND      $35       A <- (A) /\ M              (Z-Page,X)       2/4
*   ROL      $36       C <- A7 & A <- A << 1 + C  (Z-Page,X)       2/6
    RLA      $37       M <- (M << 1) /\ (A)       (Z-Page,X)       2/6'5
*   SEC      $38       C <- 1                     (Implied)        1/2
*   AND      $39       A <- (A) /\ M              (Absolute,Y)     3/4'1
    NOP      $3A       [no operation]             (Implied)        1/2
    RLA      $3B       M <- (M << 1) /\ (A)       (Absolute,Y)     3/7'5
    NOP      $3C       [no operation]             (Absolute,X)     3/4'1
*   AND      $3D       A <- (A) /\ M              (Absolute,X)     3/4'1
*   ROL      $3E       C <- A7 & A <- A << 1 + C  (Absolute,X)     3/7
    RLA      $3F       M <- (M << 1) /\ (A)       (Absolute,X)     3/7'5
*   RTI      $40       P <- (Stack), PC <-(Stack) (Implied)        1/6
*   EOR      $41       A <- (A) \-/ M             (Ind,X)          2/6
    JAM      $42       [locks up machine]         (Implied)        1/-
    SRE      $43       M <- (M >> 1) \-/ A        (Ind,X)          2/8  
    NOP      $44       [no operation]             (Z-Page)         2/3
*   EOR      $45       A <- (A) \-/ M             (Z-Page)         2/3
*   LSR      $46       C <- A0, A <- (A) >> 1     (Z-Page)         2/5
    SRE      $47       M <- (M >> 1) \-/ A        (Z-Page)         2/5
*   PHA      $48       Stack <- (A)               (Implied)        1/3
*   EOR      $49       A <- (A) \-/ M             (Immediate)      2/2
*   LSR      $4A       C <- A0, A <- (A) >> 1     (Accumulator)    1/2
    ASR      $4B       A <- [(A /\ M) >> 1]       (Immediate)      1/2
*   JMP      $4C       PC <- Address              (Absolute)       3/3
*   EOR      $4D       A <- (A) \-/ M             (Absolute)       3/4
*   LSR      $4E       C <- A0, A <- (A) >> 1     (Absolute)       3/6
    SRE      $4F       M <- (M >> 1) \-/ A        (Absolute)       3/6
*   BVC      $50       if V=0, PC = PC + offset   (Relative)       2/2'2
*   EOR      $51       A <- (A) \-/ M             ((Ind),Y)        2/5'1
    JAM      $52       [locks up machine]         (Implied)        1/-
    SRE      $53       M <- (M >> 1) \-/ A        ((Ind),Y)        2/8
    NOP      $54       [no operation]             (Z-Page,X)       2/4
*   EOR      $55       A <- (A) \-/ M             (Z-Page,X)       2/4
*   LSR      $56       C <- A0, A <- (A) >> 1     (Z-Page,X)       2/6
    SRE      $57       M <- (M >> 1) \-/ A        (Z-Page,X)       2/6
*   CLI      $58       I <- 0                     (Implied)        1/2
*   EOR      $59       A <- (A) \-/ M             (Absolute,Y)     3/4'1
    NOP      $5A       [no operation]             (Implied)        1/2 
    SRE      $5B       M <- (M >> 1) \-/ A        (Absolute,Y)     3/7
    NOP      $5C       [no operation]             (Absolute,X)     3/4'1
*   EOR      $5D       A <- (A) \-/ M             (Absolute,X)     3/4'1
*   LSR      $5E       C <- A0, A <- (A) >> 1     (Absolute,X)     3/7
    SRE      $5F       M <- (M >> 1) \-/ A        (Absolute,X)     3/7
*   RTS      $60       PC <- (Stack)              (Implied)        1/6
*   ADC      $61       A <- (A) + M + C           (Ind,X)          2/6
    JAM      $62       [locks up machine]         (Implied)        1/-
    RRA      $63       M <- (M >> 1) + (A) + C    (Ind,X)          2/8'5
    NOP      $64       [no operation]             (Z-Page)         2/3
*   ADC      $65       A <- (A) + M + C           (Z-Page)         2/3
*   ROR      $66       C<-A0 & A<- (A7=C + A>>1)  (Z-Page)         2/5
    RRA      $67       M <- (M >> 1) + (A) + C    (Z-Page)         2/5'5
*   PLA      $68       A <- (Stack)               (Implied)        1/4
*   ADC      $69       A <- (A) + M + C           (Immediate)      2/2
*   ROR      $6A       C<-A0 & A<- (A7=C + A>>1)  (Accumulator)    1/2
    ARR      $6B       A <- [(A /\ M) >> 1]       (Immediate)      1/2'5
*   JMP      $6C       PC <- Address              (Indirect)       3/5
*   ADC      $6D       A <- (A) + M + C           (Absolute)       3/4
*   ROR      $6E       C<-A0 & A<- (A7=C + A>>1)  (Absolute)       3/6 
    RRA      $6F       M <- (M >> 1) + (A) + C    (Absolute)       3/6'5
*   BVS      $70       if V=1, PC = PC + offset   (Relative)       2/2'2
*   ADC      $71       A <- (A) + M + C           ((Ind),Y)        2/5'1
    JAM      $72       [locks up machine]         (Implied)        1/-
    RRA      $73       M <- (M >> 1) + (A) + C    ((Ind),Y)        2/8'5
    NOP      $74       [no operation]             (Z-Page,X)       2/4
*   ADC      $75       A <- (A) + M + C           (Z-Page,X)       2/4
*   ROR      $76       C<-A0 & A<- (A7=C + A>>1)  (Z-Page,X)       2/6
    RRA      $77       M <- (M >> 1) + (A) + C    (Z-Page,X)       2/6'5
*   SEI      $78       I <- 1                     (Implied)        1/2
*   ADC      $79       A <- (A) + M + C           (Absolute,Y)     3/4'1
    NOP      $7A       [no operation]             (Implied)        1/2
    RRA      $7B       M <- (M >> 1) + (A) + C    (Absolute,Y)     3/7'5
    NOP      $7C       [no operation]             (Absolute,X)     3/4'1
*   ADC      $7D       A <- (A) + M + C           (Absolute,X)     3/4'1
*   ROR      $7E       C<-A0 & A<- (A7=C + A>>1)  (Absolute,X)     3/7
    RRA      $7F       M <- (M >> 1) + (A) + C    (Absolute,X)     3/7'5 
    NOP      $80       [no operation]             (Immediate)      2/2
*   STA      $81       M <- (A)                   (Ind,X)          2/6
    NOP      $82       [no operation]             (Immediate)      2/2
    SAX      $83       M <- (A) /\ (X)            (Ind,X)          2/6
*   STY      $84       M <- (Y)                   (Z-Page)         2/3
*   STA      $85       M <- (A)                   (Z-Page)         2/3
*   STX      $86       M <- (X)                   (Z-Page)         2/3
    SAX      $87       M <- (A) /\ (X)            (Z-Page)         2/3 
*   DEY      $88       Y <- (Y) - 1               (Implied)        1/2
    NOP      $89       [no operation]             (Immediate)      2/2
*   TXA      $8A       A <- (X)                   (Implied)        1/2
    ANE      $8B       M <-[(A)\/$EE] /\ (X)/\(M) (Immediate)      2/2^4
*   STY      $8C       M <- (Y)                   (Absolute)       3/4
*   STA      $8D       M <- (A)                   (Absolute)       3/4
*   STX      $8E       M <- (X)                   (Absolute)       3/4 
    SAX      $8F       M <- (A) /\ (X)            (Absolute)       3/4
*   BCC      $90       if C=0, PC = PC + offset   (Relative)       2/2'2
*   STA      $91       M <- (A)                   ((Ind),Y)        2/6
    JAM      $92       [locks up machine]         (Implied)        1/-
    SHA      $93       M <- (A) /\ (X) /\ (PCH+1) (Absolute,X)     3/6'3
*   STY      $94       M <- (Y)                   (Z-Page,X)       2/4
*   STA      $95       M <- (A)                   (Z-Page,X)       2/4
    SAX      $97       M <- (A) /\ (X)            (Z-Page,Y)       2/4
*   STX      $96       M <- (X)                   (Z-Page,Y)       2/4
*   TYA      $98       A <- (Y)                   (Implied)        1/2
*   STA      $99       M <- (A)                   (Absolute,Y)     3/5
*   TXS      $9A       S <- (X)                   (Implied)        1/2
    SHS      $9B       X <- (A) /\ (X), S <- (X)  (Absolute,Y)     3/5
                       M <- (X) /\ (PCH+1)      
    SHY      $9C       M <- (Y) /\ (PCH+1)        (Absolute,Y)     3/5'3
*   STA      $9D       M <- (A)                   (Absolute,X)     3/5
    SHX      $9E       M <- (X) /\ (PCH+1)        (Absolute,X)     3/5'3
    SHA      $9F       M <- (A) /\ (X) /\ (PCH+1) (Absolute,Y)     3/5'3
*   LDY      $A0       Y <- M                     (Immediate)      2/2
*   LDA      $A1       A <- M                     (Ind,X)          2/6
*   LDX      $A2       X <- M                     (Immediate)      2/2
    LAX      $A3       A <- M, X <- M             (Ind,X)          2/6
*   LDY      $A4       Y <- M                     (Z-Page)         2/3
*   LDA      $A5       A <- M                     (Z-Page)         2/3
*   LDX      $A6       X <- M                     (Z-Page)         2/3
    LAX      $A7       A <- M, X <- M             (Z-Page)         2/3
*   TAY      $A8       Y <- (A)                   (Implied)        1/2
*   LDA      $A9       A <- M                     (Immediate)      2/2
*   TAX      $AA       X <- (A)                   (Implied)        1/2
    LXA      $AB       X04 <- (X04) /\ M04        (Immediate)      1/2
                       A04 <- (A04) /\ M04
*   LDY      $AC       Y <- M                     (Absolute)       3/4
*   LDA      $AD       A <- M                     (Absolute)       3/4
*   LDX      $AE       X <- M                     (Absolute)       3/4
    LAX      $AF       A <- M, X <- M             (Absolute)       3/4
*   BCS      $B0       if C=1, PC = PC + offset   (Relative)       2/2'2
*   LDA      $B1       A <- M                     ((Ind),Y)        2/5'1
    JAM      $B2       [locks up machine]         (Implied)        1/-
    LAX      $B3       A <- M, X <- M             ((Ind),Y)        2/5'1
*   LDY      $B4       Y <- M                     (Z-Page,X)       2/4
*   LDA      $B5       A <- M                     (Z-Page,X)       2/4
*   LDX      $B6       X <- M                     (Z-Page,Y)       2/4
    LAX      $B7       A <- M, X <- M             (Z-Page,Y)       2/4
*   CLV      $B8       V <- 0                     (Implied)        1/2
*   LDA      $B9       A <- M                     (Absolute,Y)     3/4'1
*   TSX      $BA       X <- (S)                   (Implied)        1/2
    LAE      $BB       X,S,A <- (S /\ M)          (Absolute,Y)     3/4'1
*   LDY      $BC       Y <- M                     (Absolute,X)     3/4'1
*   LDA      $BD       A <- M                     (Absolute,X)     3/4'1
*   LDX      $BE       X <- M                     (Absolute,Y)     3/4'1
    LAX      $BF       A <- M, X <- M             (Absolute,Y)     3/4'1
*   CPY      $C0       (Y - M) -> NZC             (Immediate)      2/2
*   CMP      $C1       (A - M) -> NZC             (Ind,X)          2/6
    NOP      $C2       [no operation]             (Immediate)      2/2
    DCP      $C3       M <- (M)-1, (A-M) -> NZC   (Ind,X)          2/8
*   CPY      $C4       (Y - M) -> NZC             (Z-Page)         2/3
*   CMP      $C5       (A - M) -> NZC             (Z-Page)         2/3
*   DEC      $C6       M <- (M) - 1               (Z-Page)         2/5
    DCP      $C7       M <- (M)-1, (A-M) -> NZC   (Z-Page)         2/5
*   INY      $C8       Y <- (Y) + 1               (Implied)        1/2
*   CMP      $C9       (A - M) -> NZC             (Immediate)      2/2
*   DEX      $CA       X <- (X) - 1               (Implied)        1/2
    SBX      $CB       X <- (X)/\(A) - M          (Immediate)      2/2
*   CPY      $CC       (Y - M) -> NZC             (Absolute)       3/4
*   CMP      $CD       (A - M) -> NZC             (Absolute)       3/4
*   DEC      $CE       M <- (M) - 1               (Absolute)       3/6
    DCP      $CF       M <- (M)-1, (A-M) -> NZC   (Absolute)       3/6
*   BNE      $D0       if Z=0, PC = PC + offset   (Relative)       2/2'2
*   CMP      $D1       (A - M) -> NZC             ((Ind),Y)        2/5'1
    JAM      $D2       [locks up machine]         (Implied)        1/-
    DCP      $D3       M <- (M)-1, (A-M) -> NZC   ((Ind),Y)        2/8
    NOP      $D4       [no operation]             (Z-Page,X)       2/4
*   CMP      $D5       (A - M) -> NZC             (Z-Page,X)       2/4
*   DEC      $D6       M <- (M) - 1               (Z-Page,X)       2/6
    DCP      $D7       M <- (M)-1, (A-M) -> NZC   (Z-Page,X)       2/6
*   CLD      $D8       D <- 0                     (Implied)        1/2
*   CMP      $D9       (A - M) -> NZC             (Absolute,Y)     3/4'1
    NOP      $DA       [no operation]             (Implied)        1/2 
    DCP      $DB       M <- (M)-1, (A-M) -> NZC   (Absolute,Y)     3/7
    NOP      $DC       [no operation]             (Absolute,X)     3/4'1
*   CMP      $DD       (A - M) -> NZC             (Absolute,X)     3/4'1
*   DEC      $DE       M <- (M) - 1               (Absolute,X)     3/7
    DCP      $DF       M <- (M)-1, (A-M) -> NZC   (Absolute,X)     3/7
*   CPX      $E0       (X - M) -> NZC             (Immediate)      2/2
*   SBC      $E1       A <- (A) - M - ~C          (Ind,X)          2/6
    NOP      $E2       [no operation]             (Immediate)      2/2
    ISB      $E3       M <- (M) - 1,A <- (A)-M-~C (Ind,X)          3/8'1
*   CPX      $E4       (X - M) -> NZC             (Z-Page)         2/3
*   SBC      $E5       A <- (A) - M - ~C          (Z-Page)         2/3
*   INC      $E6       M <- (M) + 1               (Z-Page)         2/5
    ISB      $E7       M <- (M) - 1,A <- (A)-M-~C (Z-Page)         2/5  
*   INX      $E8       X <- (X) +1                (Implied)        1/2
*   SBC      $E9       A <- (A) - M - ~C          (Immediate)      2/2
*   NOP      $EA       [no operation]             (Implied)        1/2
    SBC      $EB       A <- (A) - M - ~C          (Immediate)      1/2
*   SBC      $ED       A <- (A) - M - ~C          (Absolute)       3/4
*   CPX      $EC       (X - M) -> NZC             (Absolute)       3/4
*   INC      $EE       M <- (M) + 1               (Absolute)       3/6
    ISB      $EF       M <- (M) - 1,A <- (A)-M-~C (Absolute)       3/6
*   BEQ      $F0       if Z=1, PC = PC + offset   (Relative)       2/2'2
*   SBC      $F1       A <- (A) - M - ~C          ((Ind),Y)        2/5'1
    JAM      $F2       [locks up machine]         (Implied)        1/-
    ISB      $F3       M <- (M) - 1,A <- (A)-M-~C ((Ind),Y)        2/8
    NOP      $F4       [no operation]             (Z-Page,X)       2/4
*   SBC      $F5       A <- (A) - M - ~C          (Z-Page,X)       2/4
*   INC      $F6       M <- (M) + 1               (Z-Page,X)       2/6
    ISB      $F7       M <- (M) - 1,A <- (A)-M-~C (Z-Page,X)       2/6
*   SED      $F8       D <- 1                     (Implied)        1/2
*   SBC      $F9       A <- (A) - M - ~C          (Absolute,Y)     3/4'1
    NOP      $FA       [no operation]             (Implied)        1/2
    ISB      $FB       M <- (M) - 1,A <- (A)-M-~C (Absolute,Y)     3/7
    NOP      $FC       [no operation]             (Absolute,X)     3/4'1
*   SBC      $FD       A <- (A) - M - ~C          (Absolute,X)     3/4'1
*   INC      $FE       M <- (M) + 1               (Absolute,X)     3/7
    ISB      $FF       M <- (M) - 1,A <- (A)-M-~C (Absolute,X)     3/7

'1 - Add one if address crosses a page boundry.
'2 - Add 1 if branch succeeds, or 2 if into another page.
'3 - If page boundry crossed then PCH+1 is just PCH
'4 - Sources disputed on exact operation, or sometimes does not work.
'5 - Full eight bit rotation (with carry)

Sources:
  Programming the 6502, Rodney Zaks, (c) 1983 Sybex
  Paul Ojala, Post to Comp.Sys.Cbm (po87553@cs.tut.fi / albert@cc.tut.fi)
  D John Mckenna, Post to Comp.Sys.Cbm (gudjm@uniwa.uwa.oz.au)

Compiled by Craig Taylor (duck@pembvax1.pembroke.edu)
};

my $verbose = 0;
sub info { $verbose and warn @_; }

my @mn;
my @mode;
my @len;
my @illegal;

sub init {
    my ($illegal) = @_;
    my @lines = split /\n/, $spec;
    for (@lines) {
        /(.) {3}(\w{3}) {6}\$(..) {7}(.{27})\((.*)\) *(\d)\/(.*)/ or next;
        my ($std, $mn, $hex, $oper, $mode, $len, $cycles) =
            ($1,$2,$3,$4,$5,$6,$7);
        my $code = hex($hex);
        $illegal[$code] = $std eq "*" ? 0 : 1 if not $illegal;
        $mn[$code] = lc $mn;
        $mode[$code] = $mode;
        $len[$code] = $len;
    }
}

sub rel {
    my ($mem, $i) = @_;
    my $imm8 = $mem->[$i+1][0];
    my $rel = ($imm8 < 128 ? $i+$imm8+2 : $i+$imm8-256+2) & 0xFFFF;
    return $rel;
}

sub trace {
    my ($mem, $entry, $segnum, $caller) = @_;
    #info(sprintf "TRACING: %X\n", $entry);
    if (exists $mem->[$entry]) {
        my $pre = $segnum ? sprintf "s%X", $segnum : "";
        $mem->[$entry][2] = $pre . sprintf "l%04X", $entry;
        if (defined $caller) {
            $mem->[$caller][3] = $mem->[$entry][2];
            push @{$mem->[$entry][4]}, $caller;
        }
    }
    for (my $i = $entry;;) {
        return if not exists $mem->[$i];
        return if not $mem->[$i][0]; # Ignore BRK
        return if $illegal[$mem->[$i][0]]; # Ignore illegal opcodes
        return if defined $mem->[$i][1];
        my $code = $mem->[$i][0];
        $mem->[$i][1] = $len[$code];
        if ($mn[$code] eq "rts") {
            last;
        } elsif ($mn[$code] eq "rti") {
            last;
        } elsif ($mn[$code] eq "jmp") {
            my $targ;
            if ($mode[$code] eq "Indirect") {
                $targ = $mem->[$i+1][0] + ($mem->[$i+2][0]<<8);
                $targ = $mem->[$targ][0] + ($mem->[$targ+1][0]<<8);
            } else {
                $targ = $mem->[$i+1][0] + ($mem->[$i+2][0]<<8);
            }
            trace($mem, $targ, $segnum, $i);
            last;
        } elsif ($mn[$code] eq "jsr") {
            my $sub = $mem->[$i+1][0] + ($mem->[$i+2][0]<<8);
            trace($mem, $sub, $segnum, $i);
        } elsif ($mn[$code] =~ /^b(ne|eq|pl|mi|cc|cs|vs|vc)/) {
            my $rel = rel($mem, $i);
            trace($mem, $rel, $segnum, $i);
        }
        $i += $len[$code];
    }
}

sub uniq { my %seen; grep !$seen{$_}++, @_; }

sub showmodes {
    my @uniq = uniq(@mode);
    die map "$_\n", sort @uniq;
}

sub dis {
    my ($mem, $opts) = @_;
    my @mem = map [ord $_], split //, $mem;
    my $org = hex($opts->{org}||0);
    unshift @mem, ([0,0])x$org if $org;
    my $end = scalar @mem;
    push @mem, ([0,0])x(0x10002-$end) if $end < 0x10002;
    my %data;
    for my $data (@{$opts->{data}}) {
        $data = hex($data);
        info(sprintf "DATA: %X\n", $data);
        $mem[$data][1] = 0;
        $data{$data} = 1;
    }
    for my $entry (@{$opts->{entry}}) {
        trace(\@mem, hex($entry), $opts->{segnum});
    }
    my %vectors;
    for my $vector (@{$opts->{vector}}) {
        $vector = hex($vector);
        if (exists $mem[$vector] and exists $mem[$vector+1]) {
            info(sprintf "VECTOR: %04X\n", $vector);
            my $targ = $mem[$vector][0] + ($mem[$vector+1][0]<<8);
            $vectors{$targ} = $vector;
            trace(\@mem, $targ, $opts->{segnum});
        }
    }
    my %entries = map { hex($_) => 1 } @{$opts->{entry}};
    for (my $i = $org; $i < $end; ++$i) {
        if ($opts->{labels} and $mem[$i][2]) {
            print "$mem[$i][2]";
            if ($mem[$i][4]) {
                print "\t\t\t; Callers:";
                printf " %04X", $_ for @{$mem[$i][4]};
            }
            print "\n";
        }
        my $len = $mem[$i][1];
        if ($len and $i + $len - 1 < $end) {
            printf "    $mn[$mem[$i][0]]";
            my $mode = $mode[$mem[$i][0]];
            my $imm8 = $mem[$i+1][0];
            my $imm16 = $imm8 + ($mem[$i+2][0]<<8);
            my $ab = $imm16>>8 ? "" : "a:";
            my $rel = rel(\@mem, $i);
            my $uselabel = $opts->{labels} && defined $mem[$i][3]
                && ($mode eq "Relative" and $rel >= $org && $rel < $end
                    or $mode eq "Absolute" and $imm16 > $org && $imm16 < $end);
            if ($uselabel) {
                $imm16 = $rel = $mem[$i][3];
            } else {
                $_ = sprintf "\$%02X", $_ for $imm8;
                $_ = sprintf "\$%04X", $_ for $imm16, $rel;
            }
            print " @" if $mode eq "Accumulator";
            print " #$imm8" if $mode eq "Immediate";
            print " ($imm8),y" if $mode eq "(Ind),Y";
            print " ($imm8,x)" if $mode eq "Ind,X";
            print " $imm8" if $mode eq "Z-Page";
            print " $imm8,x" if $mode eq "Z-Page,X";
            print " $imm8,y" if $mode eq "Z-Page,Y";
            print " $ab$imm16" if $mode eq "Absolute";
            print " $ab$imm16,x" if $mode eq "Absolute,X";
            print " $ab$imm16,y" if $mode eq "Absolute,Y";
            print " ($imm16)" if $mode eq "Indirect";
            print " $rel" if $mode eq "Relative";
            print "    " if $mode eq "Implied";
            printf "\t\t; %04X:%s", $i, join "",
                map { sprintf " %02X", $mem[$_][0] } $i .. ($i+$len-1);
            print " <--- Entry" if $entries{$i};
            printf " <--- Vector %X", $vectors{$i} if defined $vectors{$i};
            print "\n";
            for (my $a = $i+1; $a < $i+$len; ++$a) {
                if ($opts->{labels} and $mem[$a][2]) {
                    print "$mem[$a][2] equ *", ($a-$i-$len);
                    if ($mem[$a][4]) {
                        print "\t\t; Callers:";
                        printf " %04X", $_ for @{$mem[$a][4]};
                    }
                    print "\n";
                }
            }
            $i += $len - 1;
        } else {
            printf "    dta \$%X\t\t; %04X: %02X",
                $mem[$i][0], $i, $mem[$i][0];
            print " <--- Data" if $data{$i};
            print "\n";
        }
    }
}

sub usage {
    die "Usage: dis [options] file...\n",
        "  -e XXXX   Entry point(s)\n",
        "  -d XXXX   Data location(s) - Disallow tracing as code\n",
        "  -v XXXX   Vector(s), e.g. FFFA\n",
        "  -o XXXX   Origin\n",
        "  -l        Create labels\n",
        "  -i        Emit illegal opcodes\n",
        "  -x        Disassemble as Atari XEX file\n",
        "  -p        Disassemble as Commodore 64 PRG file\n",
        "  -verbose  Print info to STDERR\n",
        ;
}

sub word {
    my ($mem, $i) = @_;
    $i + 2 < length $mem or die "ERROR: File is corrupted\n";
    return unpack "v", substr $mem, $i, 2;
}

sub runini($$$) {
    my ($cmd, $data, $ffff) = @_;
    if ($ffff) {
        printf "    opt h-\n";
        printf "    dta a(\$FFFF)\t; Segment header\n";
        printf "    opt h+\n";
    }
    printf "    %s \$%04X\n", $cmd, unpack "v", $data;
}

sub xex {
    my ($mem, $opts) = @_;
    my @segments;
    my $run;
    for (my $i = 0; $i < length $mem;) {
        my $start = word($mem, $i);
        $i += 2;
        my $ffff = $start == 0xFFFF;
        if ($ffff) {
            $start = word($mem, $i);
            $i += 2;
        }
        my $end = word($mem, $i);
        $i += 2;
        my $len = $end - $start + 1;
        info(sprintf "START: %X END: %X\n", $start, $end);
        die "ERROR: Segment length is negative: $i, $len\n" if $len < 0;
        die "ERROR: Segment is past EOF: $i, $len\n" if $len >= length $mem;
        my $data = substr $mem, $i, $len;
        $i += $len;
        if ($start == 0x2E0) {
            $run = unpack "v", $data;
        } elsif ($start == 0x2E2) {
            my $ini = unpack "v", $data;
            for my $segment (@segments) {
                if ($ini >= $segment->[0] and $ini <= $segment->[1]) {
                    info(sprintf "INI: %X\n", $ini);
                    push @{$segment->[3]}, sprintf "%X", $ini;
                    last;
                }
            }
        }
        unshift @segments, [$start, $end, $data, [], $ffff];
    }
    if (defined $run) {
        for my $segment (@segments) {
            if ($run >= $segment->[0] and $run <= $segment->[1]) {
                info(sprintf "RUN: %X\n", $run);
                push @{$segment->[3]}, sprintf "%X", $run;
                last;
            }
        }
    }
    my $global = $opts->{entry};
    my $segnum = 1;
    for my $segment (reverse @segments) {
        my ($start, $end, $data, $entries, $ffff) = @$segment;
        $ffff = 0 if $segnum == 1;
        if ($start == 0x2E0 and $end == 0x2E1) {
            runini("run", $data, $ffff);
        } elsif ($start == 0x2E2 and $end == 0x2E3) {
            runini("ini", $data, $ffff);
        } else {
            printf "    org %s\$%04X\t\t; end %04X\n", $ffff ? "f:" : "", $start, $end;
            delete $opts->{entry};
            $opts->{entry} = [@{$global||[]}, @{$entries||[]}];
            $opts->{org} = sprintf "%X", $start;
            $opts->{segnum} = $segnum++;
            dis($data, $opts);
            $opts->{entry} = $global;
        }
    }
}

sub prg {
    my ($mem, $opts) = @_;
    my $start = unpack "v", substr $mem, 0, 2;
    if ($mem =~ /^......\x9E *(\d+)/s) {
        push @{$opts->{entry}}, sprintf "%X", $1;
    }
    printf "    opt h-\n";
    printf "    org \$%04X\n", $start-2;
    printf "    dta a(\$%04X)\t; PRG Header\n", $start;
    $opts->{org} = sprintf "%X", $start;
    dis(substr($mem, 2), $opts);
}

sub main {
    my %opts;
    GetOptions(\%opts, qw{
        entry|e=s@
        data|d=s@
        vector|v=s@
        org|o=s
        labels|l!
        illegal|i!
        modes!
        help|h!
        xex|x!
        prg|p!
        verbose!
    }) or usage();

    usage() if $opts{help};
    usage() if not @ARGV and -t STDOUT;

    init($opts{illegal});
    showmodes() if $opts{modes};

    $verbose = $opts{verbose};
    my $mem;
    {
        local $/; # slurp whole files
        $mem = join "", <>;
    }

    if ($opts{xex}) {
        xex($mem, \%opts);
    } elsif ($opts{prg}) {
        prg($mem, \%opts);
    } else {
        printf "    opt h-\n";
        printf "    org \$%04X\n", hex($opts{org}||0);
        dis($mem, \%opts);
    }
    info("DONE\n");
}

main();
