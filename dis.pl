#!/usr/bin/perl
# Copyright (C) 2014 Lyren Brown
use strict;
use warnings;
use Getopt::Long;

my $verbose = 0;
sub info { $verbose and warn @_; }

my @mn;
my @mode;
my @len;
my @illegal;

sub init {
    my ($illegal) = @_;
    my @lines = <DATA>;
    close DATA;
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

use constant {
    SEGNUM => 0,
    VALUE => 1,
    LEN => 2,
    CALLERS => 3,
    ACCESSORS => 4,
    TARGETS => 5,
    LABEL => 6,
};

sub state {
    return {
        #mem => [map [0], 0 .. 0x10000],
        segnum => 0,
    };
}

sub layer {
    my ($state, $start, $end, $data) = @_;
    my $segnum = $state->{segnum};
    length $data == $end - $start + 1 or
        die "ERROR: layer size doesn't match start, end: $start, $end\n";
    my @mem = map ord, split //, $data;
    for my $i ($start .. $end) {
        $state->{mem}[$i] = [$segnum, shift @mem];
    }
}

sub label {
    my ($state) = @_;
    my $segnum = $state->{segnum};
    for my $opt (qw(code data vector)) {
        my $labels = $state->{$opt}{$segnum} || next;
        $state->{mem}[$_][LABEL] = $labels->{$_} for keys %$labels;
    }
}

sub labels {
    my ($state, $opts) = @_;
    for my $opt (qw(code data vector)) {
        for my $value (@{$opts->{$opt} || []}) {
            if ($value =~ /(?:(\w+)=)?(?:(\d+):)?(\S+)/) {
                my $label = $1;
                my $segnum = $2 || 0;
                my $addr = hex($3);
                if (($addr & 0xFFFF) != $addr) {
                    warn sprintf "WARNING: Out of range $opt: %04X\n", $addr;
                    $addr &= 0xFFFF;
                }
                if (defined $state->{$opt}{$segnum}{$addr}) {
                    warn sprintf "WARNING: Duplicate $opt: %04X\n", $addr;
                }
                $state->{$opt}{$segnum}{$addr} = $label;
            }
        }
    }
    label($state);
}

sub copy {
    my ($state) = @_;
    my $copy = {%$state}; # Shallow copy state
    $copy->{mem} = [@{$state->{mem}}]; # Shallow copy mem
    return $copy;
}

sub byteat {
    my ($state, $i) = @_;
    return $state->{mem}[$i][VALUE];
}

sub wordat {
    my ($state, $i) = @_;
    return $state->{mem}[$i][VALUE] + ($state->{mem}[$i+1][VALUE]<<8);
}

sub rel {
    my ($i, $offset) = @_;
    return ($offset < 128 ? $i+$offset+2 : $i+$offset-256+2) & 0xFFFF;
}

sub addr {
    my ($lo, $hi) = @_;
    return $lo + ($hi<<8);
}

sub loc {
    my ($state, $i) = @_;
    if ($state->{segnum}) {
        return sprintf "%04X, segment $state->{segnum}", $i;
    }
    return sprintf "%04X", $i;
}

sub trace {
    my ($state, $entry, $callerid, $caller) = @_;
    #info(sprintf "; TRACING: %X\n", $entry);
    my $mem = $state->{mem};
    my $byte = $mem->[$entry] || return;
    if (defined $byte->[VALUE]) {
        my $pre = $byte->[SEGNUM] ? sprintf "s$byte->[SEGNUM]" : "";
        $byte->[LABEL] ||= $pre . sprintf "l%04X", $entry;
        push @{$mem->[$caller][TARGETS]}, $byte->[LABEL] if defined $caller;
        if ($callerid) {
            push @{$byte->[CALLERS]}, $callerid;
        } else {
            push @{$byte->[CALLERS]}, sprintf "%04X", $caller;
        }
    }
    for (my $i = $entry;;) {
        my $byte = $mem->[$i] || return; # Ignore undefined memory
        my ($code, $i1, $i2) = map $mem->[$_][VALUE], $i .. $i+2;
        return if not $code; # Ignore BRK
        return if $illegal[$code]; # Ignore illegal opcodes
        return if $state->{visited}{$i}++; # Skip if already visited
        $byte->[LEN] = $len[$code];
        for ($i .. $i+$len[$code]-1) {
            if (not defined $mem->[$_][VALUE]) {
                # Bail out if instruction goes out-of-bounds
                warn "WARNING: Instruction goes past end of state at ",
                    loc($state, $_), "\n";
                return;
            }
        }
        my $mode = $mode[$code];
        if ($mn[$code] eq "rts") {
            last;
        } elsif ($mn[$code] eq "rti") {
            last;
        } elsif ($mn[$code] eq "jmp") {
            my $targ;
            if ($mode[$code] eq "Indirect") {
                $targ = addr($i1, $i2);
                push @{$mem->[$targ][ACCESSORS]}, sprintf "%04X", $i;
                my ($lo, $hi) = map $mem->[$_][VALUE], $targ, $targ+1;
                if (not defined $lo or not defined $hi) {
                    warn "WARNING: Indirect JMP references undefined ",
                        "memory at ", loc($state, $i), "\n";
                }
                $targ = addr($lo, $hi);
            } else {
                $targ = addr($i1, $i2);
            }
            trace($state, $targ, $byte->[LABEL], $i);
            last;
        } elsif ($mn[$code] eq "jsr") {
            my $targ = addr($i1, $i2);
            trace($state, $targ, $byte->[LABEL], $i);
        } elsif ($mn[$code] =~ /^b(ne|eq|pl|mi|cc|cs|vs|vc)/) {
            my $targ = rel($i, $i1);
            trace($state, $targ, $byte->[LABEL], $i);
        } elsif ($mode =~ /Ind|Z-Page/) {
            my $tlabel = $mem->[$i1][LABEL];
            push @{$byte->[TARGETS]}, $tlabel if $tlabel;
            push @{$mem->[$i1][ACCESSORS]}, sprintf "%04X", $i;
        } elsif ($mode =~ /Absolute/) {
            my $addr = addr($i1, $i2);
            my $tlabel = $mem->[$addr][LABEL];
            push @{$byte->[TARGETS]}, $tlabel if $tlabel;
            push @{$mem->[$addr][ACCESSORS]}, sprintf "%04X", $i;
        }
        $i += $len[$code];
    }
}

sub dump_label {
    my ($opts, $label, $byte) = @_;
    return if not $opts->{labels};
    return if not $label;
    my $callers = $byte->[CALLERS];
    print $label;
    my $tabs = (3 - ((length $label) >> 3)) || 1;
    print (("\t") x $tabs);
    if ($callers and $opts->{call}) {
        print "; Callers:";
        print " $_" for @$callers;
    }
    print "\n";
}

sub dis {
    my ($state, $start, $end, $opts) = @_;
    my $mem = $state->{mem};
    for (my $i = $start; $i <= $end; ++$i) {
        my $byte = $mem->[$i];
        my $segnum = $byte->[SEGNUM];
        my $value = $byte->[VALUE];
        my $len = $byte->[LEN];
        my $targets = $byte->[TARGETS];
        my $label = $byte->[LABEL];
        my $accessors = $byte->[ACCESSORS];
        if ($len and $i + $len - 1 <= $end) {
            my ($code, $i1, $i2) = map $mem->[$_][VALUE], $i .. $i+2;
            dump_label($opts, $label, $byte);
            printf "    $mn[$code]";
            my $mode = $mode[$code];
            my $imm8 = $i1||0;
            my $imm16 = ($i1||0) + (($i2||0)<<8);
            my $rel = rel($i, $i1||0);
            my $ab = $i2 ? "" : "a:";
            if ($opts->{labels} && $targets && $mode ne "Indirect") {
                $imm8 = $imm16 = $rel = $targets->[-1];
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
            if ($opts->{comment}) {
                printf "\t\t; %04X:%s", $i, join "",
                    map { sprintf " %02X", $mem->[$_][VALUE] } $i .. ($i+$len-1);
                if ($accessors and $opts->{access}) {
                    print " Access:";
                    print " $_" for @$accessors;
                }
            }
            print "\n";
            for (my $a = $i+1; $a < $i+$len; ++$a) {
                if (my $label = $mem->[$a][LABEL]) {
                    my $off = $a-$i-$len;
                    dump_label($opts, "$label equ *$off", $mem->[$a]);
                }
            }
            $i += $len - 1;
        } else {
            dump_label($opts, $label, $byte);
            printf "    dta \$%X", $value;
            if ($opts->{comment}) {
                printf "\t\t; %04X: %02X", $i, $value;
                if ($accessors and $opts->{access}) {
                    print " Access:";
                    print " $_" for @$accessors;
                }
                print " <--- Data" if exists $state->{data}{$segnum}{$i};
            }
            print "\n";
        }
    }
}

sub word {
    my ($stream, $i) = @_;
    $i + 2 < length $stream or die "ERROR: File is corrupted\n";
    return unpack "v", substr $stream, $i, 2;
}

sub enter {
    my ($state) = @_;
    my $mem = $state->{mem};
    my $segnum = $state->{segnum};
    while (my ($data, $label) = each %{$state->{data}{$segnum}}) {
        $label = $label ? "$label=" : "";
        info(sprintf "DATA: $label%04X\n", $data);
        $state->{visited}{$data} = 1;
    }
    while (my ($code, $label) = each %{$state->{code}{$segnum}}) {
        $label = $label ? "$label=" : "";
        info(sprintf "CODE: $label%04X\n", $code);
        trace($state, $code, sprintf "-c %04X", $code);
    }
    while (my ($vector, $label) = each %{$state->{vector}{$segnum}}) {
        if (grep !defined $mem->[$_][VALUE], $vector, $vector+1) {
            warn "WARNING: Vector through undefined memory: ",
                loc($state, $vector), "\n";
            next;
        }
        $label = $label ? "$label=" : "";
        info(sprintf "VECTOR: $label%04X\n", $vector);
        my $targ = addr($mem->[$vector][VALUE], $mem->[$vector+1][VALUE]);
        trace($state, $targ, sprintf "-v %04X", $vector);
    }
}

sub xex {
    my ($stream, $opts) = @_;
    my $state = state();
    labels($state, $opts);
    my @segments;
    my $run;
    my $run_caller;
    for (my $i = 0; $i < length $stream;) {
        ++$state->{segnum};
        delete $state->{visited};
        my $start = word($stream, $i);
        $i += 2;
        my $ffff = $start == 0xFFFF;
        if ($ffff) {
            $start = word($stream, $i);
            $i += 2;
        }
        my $end = word($stream, $i);
        $i += 2;
        my $len = $end - $start + 1;
        info(sprintf "START: %X END: %X\n", $start, $end);
        die "ERROR: Segment length is negative: $i, $len\n" if $len < 0;
        die "ERROR: Segment is past EOF: $i, $len\n" if $i+$len > length $stream;
        my $data = substr $stream, $i, $len;
        $i += $len;
        layer($state, $start, $end, $data);
        label($state);
        enter($state);
        if ($start == 0x2E0) {
            $run = unpack "v", $data;
            info(sprintf "RUN: %X\n", $run);
            $run_caller = "run_segment$state->{segnum}";
        } elsif ($start == 0x2E2) {
            my $ini = unpack "v", $data;
            info(sprintf "INI: %X\n", $ini);
            trace($state, $ini, "ini_segment$state->{segnum}");
        }
        push @segments, [$start, $end, $data, copy($state), $ffff];
    }
    trace($state, $run, $run_caller) if defined $run;
    $state->{segnum} = 0;
    enter($state);
    for my $segment (@segments) {
        my ($start, $end, $data, $state, $ffff) = @$segment;
        if ($state->{segnum}) {
            print "    ;-------------------------\n";
            print "    ; Segment $state->{segnum}\n";
            print "    ;-------------------------\n";
        }
        my $header = sub {
            return unless $ffff and $state->{segnum} > 1;
            printf "    opt h-\n";
            printf "    dta a(\$FFFF)\t; Segment header\n";
            printf "    opt h+\n";
        };
        if ($start <= 0x2E0 and $end >= 0x2E1) {
            $header->();
            printf "    run \$%04X\n", wordat($state, 0x2E0);
        } elsif ($start <= 0x2E2 and $end >= 0x2E3) {
            $header->();
            printf "    ini \$%04X\n", wordat($state, 0x2E2);
        } else {
            my $f = $ffff ? "f:" : "";
            printf "    org $f\$%04X\t\t; end %04X\n", $start, $end;
            dis($state, $start, $end, $opts);
        }
    }
}

sub sap {
    my ($stream, $opts) = @_;
    $stream =~ /(SAP\x0D\x0A.*?)(\xFF\xFF.*)/s or
        die "ERROR: Not a SAP file\n";
    my $header = $1;
    my $binary = $2;
    my %attr;
    print "    opt h-\n";
    while ($header =~ /(.*?)(?: (.*?))?\x0D\x0A/gs) {
        my ($key, $value) = ($1, $2);
        if (defined $value) {
            $attr{$key} = $value;
            $value =~ s/'/',c"'",c'/g;
            print "    dta c'$key $value',13,10\n";
        } else {
            $attr{$key} = 1;
            print "    dta c'$key',13,10\n";
        }
    }
    print "    opt h+\n";
    if ($attr{TYPE} eq "C") {
        my $player = hex($attr{PLAYER}||0);
        push @{$opts->{code}}, sprintf "%X", $player+3;
        push @{$opts->{code}}, sprintf "%X", $player+6;
    } else {
        push @{$opts->{code}}, map "$_=$attr{$_}",
            grep defined $attr{$_}, qw(INIT PLAYER);
    }
    xex($binary, $opts);
}

sub prg {
    my ($stream, $opts) = @_;
    my $start = unpack "v", substr $stream, 0, 2;
    my $end = $start + (length $stream) - 3;
    if ($stream =~ /^......\x9E *(\d+)/s) {
        push @{$opts->{entry}}, sprintf "%X", $1;
    }
    printf "    opt h-\n";
    printf "    org \$%04X\n", $start-2;
    printf "    dta a(\$%04X)\t; PRG Header\n", $start;
    $opts->{org} = sprintf "%X", $start;
    my $state = state();
    layer($state, $start, $end, substr $stream, 2);
    labels($state, $opts);
    enter($state);
    dis($state, $start, $end, $opts);
}

sub raw {
    my ($stream, $opts) = @_;
    my $start = hex($opts->{org}||0);
    my $end = $start + (length $stream) - 1;
    printf "    opt h-\n";
    printf "    org \$%04X\n", $start;
    my $state = state();
    layer($state, $start, $end, $stream);
    labels($state, $opts);
    enter($state);
    dis($state, $start, $end, $opts);
}

sub arg {
    my ($opts, $args, $file) = @_;
    open my $fh, $file or die "ERROR: Cannot open $file: $!\n";
    my %args = map { /(\w+)/; my $a = $1; $a => [/=s/, /@/] } @$args;
    while (<$fh>) {
        s/;.*//;
        next if /^\s*$/;
        chomp;
        my ($arg, $value) = split " ", $_;
        $args{$arg} or die "ERROR: Unknown option $_ in $file\n";
        if ($args{$arg}[0] and not defined $value) {
            die "ERROR: $arg requires a parameter in $file\n";
        }
        if ($args{$arg}[1]) {
            push @{$opts->{$arg}}, $value;
        } else {
            $opts->{$arg} = $value;
        }
        arg($opts, $args, $value) if $arg eq "arg";
    }
}

sub dump_args {
    my ($opts, $args) = @_;
    for my $arg (@$args) {
        $arg =~ /(\w+)/ or next;
        my $opt = $1;
        next if $opt eq "dump";
        my $value = $opts->{$opt};
        if (ref $value) {
            print "$opt $_\n" for @$value;
        } elsif (defined $value) {
            print "$opt $value\n";
        }
    }
}

sub usage {
    die "Usage: dis [options] file...\n",
        "  -c L=XXXX  Code entry point(s)\n",
        "  -d L=XXXX  Data location(s) - Disallow tracing as code\n",
        "  -v L=XXXX  Vector(s), e.g. FFFA\n",
        "  -o L=XXXX  Origin for raw files\n",
        "  -l         Create labels\n",
        "  -i         Emit illegal opcodes\n",
        "  -t TYPE    Dissasseble as TYPE\n",
        "             xex - Atari executable (-x)\n",
        "             sap - Atari SAP file\n",
        "             prg - Commodore 64 executable (-p)\n",
        "             raw - raw memory\n",
        "  -comment   Emit comments\n",
        "  -call      Emit callers\n",
        "  -access    Emit accessors\n",
        "  -verbose   Print info to STDERR\n",
        "  -dump      Print options in format for -a\n",
        "  -a FILE    Read options from FILE. Lines are: OPTION VALUE\n",
        "\n",
        "  Addresses may include xex segment number, e.g. 3:1FAE\n",
        ;
}

sub main {
    my @args = qw{
        code|c=s@
        data|d=s@
        vector|v=s@
        org|o=s
        labels|l!
        illegal|i!
        help|h!
        type|t=s
        xex|x!
        prg|p!
        comment!
        call!
        access!
        verbose!
        dump!
        arg|a=s@
    };
    my %opts = (comment => 1, call => 1, access => 1);
    GetOptions(\%opts, @args) or usage();

    usage() if $opts{help};
    usage() if not @ARGV and -t STDOUT;
    usage() if @ARGV > 1;

    arg(\%opts, \@args, $_) for @{$opts{arg}||[]};

    if ($opts{dump}) {
        dump_args(\%opts, \@args);
        return;
    }

    init($opts{illegal});

    $verbose = $opts{verbose};

    $opts{type} = "xex" if $opts{xex};
    $opts{type} = "prg" if $opts{prg};
    $opts{type} ||= "raw";

    my $in = $ARGV[0] || \*STDIN;
    open my $fh, $in or die "ERROR: Cannot open $in: $!\n";
    binmode $fh;
    read $fh, my $stream, 1<<20;
    if (not eof $fh) {
        warn "WARNING: Truncating file at 1M\n";
    }

    if ($opts{type} eq "xex") {
        xex($stream, \%opts);
    } elsif ($opts{type} eq "prg") {
        prg($stream, \%opts);
    } elsif ($opts{type} eq "sap") {
        sap($stream, \%opts);
    } elsif ($opts{type} eq "raw") {
        raw($stream, \%opts);
    } else {
        die "ERROR: Unknown type $opts{type}\n";
    }
    info("DONE\n");
}

main();

__DATA__

# Opcode table taken from C= Hacking Issue 1
# http://www.ffd2.com/fridge/chacking/
# http://codebase64.org/doku.php?id=magazines:chacking1#opcodes_and_quasi-opcodes
# Changes:
# - Corrected opcode $46
# - Added missing opcode $5E
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
