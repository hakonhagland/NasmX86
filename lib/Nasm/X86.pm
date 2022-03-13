#!/usr/bin/perl -I/home/phil/perl/cpan/DataTableText/lib/ -I. -I/home/phil/perl/cpan/AsmC/lib/
#-------------------------------------------------------------------------------
# Generate X86 assembler code using Perl as a macro pre-processor.
# Philip R Brenan at appaapps dot com, Appa Apps Ltd Inc., 2021
#-------------------------------------------------------------------------------
# podDocumentation
# tree::print - speed up decision as to whether we are on a tree or not
# Replace empty in boolean arithmetic with boolean and then check it in If to confirm that we are testing a boolean value
# 0x401000 from sde-mix-out addresses to get offsets in z.txt
# Replace registerSize(rax) with $variable->width
# Make hash accept parameters at: #THash
# if (0) in tests from subroutine conversion
# Call - validate that all parameter keys have a definition
# Have K and possibly V accept a flat hash of variable names and expressions
# Document that V > 0 is required to create a boolean test
# Optimize putBwdqIntoMm with vpbroadcast
# WHat is the differenfe between variable clone and variable copy?
# Standardize w1 = r8, w2 = r9 so we do need to pass them around - rdi, rsi are always general purpose except in system calls
# Make sure that we are using bts and bzhi as much as possible in mask situations
package Nasm::X86;
our $VERSION = "20211204";
use warnings FATAL => qw(all);
use strict;
use Carp qw(confess cluck);
use Data::Dump qw(dump);
use Data::Table::Text qw(:all);
use Time::HiRes qw(time);
use feature qw(say current_sub);
use utf8;

makeDieConfess;

my %rodata;                                                                     # Read only data already written
my %rodatas;                                                                    # Read only string already written
my %subroutines;                                                                # Subroutines generated
my @rodata;                                                                     # Read only data
my @data;                                                                       # Data
my @bss;                                                                        # Block started by symbol
my @text;                                                                       # Code
my @extern;                                                                     # External symbols imports for linking with C libraries
my @link;                                                                       # Specify libraries which to link against in the final assembly stage
my $interpreter = q(-I /usr/lib64/ld-linux-x86-64.so.2);                        # The ld command needs an interpreter if we are linking with C.
my $develop     = -e q(/home/phil/);                                            # Developing
my $sdeMixOut   = q(sde-mix-out.txt);                                           # Emulator output file

our $stdin  = 0;                                                                # File descriptor for standard input
our $stdout = 1;                                                                # File descriptor for standard output
our $stderr = 2;                                                                # File descriptor for standard error

my %Registers;                                                                  # The names of all the registers
my %RegisterContaining;                                                         # The largest register containing a register
my @GeneralPurposeRegisters = (qw(rax rbx rcx rdx rsi rdi), map {"r$_"} 8..15); # General purpose registers
my $bitsInByte;                                                                 # The number of bits in a byte

BEGIN{
  $bitsInByte  = 8;                                                             # The number of bits in a byte
  my %r = (    map {$_=>[ 8,  '8'  ]}  qw(al bl cl dl r8b r9b r10b r11b r12b r13b r14b r15b r8l r9l r10l r11l r12l r13l r14l r15l sil dil spl bpl ah bh ch dh));
     %r = (%r, map {$_=>[16,  's'  ]}  qw(cs ds es fs gs ss));
     %r = (%r, map {$_=>[16,  '16' ]}  qw(ax bx cx dx r8w r9w r10w r11w r12w r13w r14w r15w si di sp bp));
     %r = (%r, map {$_=>[32,  '32a']}  qw(eax  ebx ecx edx esi edi esp ebp));
     %r = (%r, map {$_=>[32,  '32b']}  qw(r8d r9d r10d r11d r12d r13d r14d r15d));
     %r = (%r, map {$_=>[80,  'f'  ]}  qw(st0 st1 st2 st3 st4 st5 st6 st7));
     %r = (%r, map {$_=>[64,  '64' ]}  qw(rax rbx rcx rdx r8 r9 r10 r11 r12 r13 r14 r15 rsi rdi rsp rbp rip rflags));
     %r = (%r, map {$_=>[64,  '64m']}  qw(mm0 mm1 mm2 mm3 mm4 mm5 mm6 mm7));
     %r = (%r, map {$_=>[128, '128']}  qw(xmm0 xmm1 xmm2 xmm3 xmm4 xmm5 xmm6 xmm7 xmm8 xmm9 xmm10 xmm11 xmm12 xmm13 xmm14 xmm15 xmm16 xmm17 xmm18 xmm19 xmm20 xmm21 xmm22 xmm23 xmm24 xmm25 xmm26 xmm27 xmm28 xmm29 xmm30 xmm31));
     %r = (%r, map {$_=>[256, '256']}  qw(ymm0 ymm1 ymm2 ymm3 ymm4 ymm5 ymm6 ymm7 ymm8 ymm9 ymm10 ymm11 ymm12 ymm13 ymm14 ymm15 ymm16 ymm17 ymm18 ymm19 ymm20 ymm21 ymm22 ymm23 ymm24 ymm25 ymm26 ymm27 ymm28 ymm29 ymm30 ymm31));
     %r = (%r, map {$_=>[512, '512']}  qw(zmm0 zmm1 zmm2 zmm3 zmm4 zmm5 zmm6 zmm7 zmm8 zmm9 zmm10 zmm11 zmm12 zmm13 zmm14 zmm15 zmm16 zmm17 zmm18 zmm19 zmm20 zmm21 zmm22 zmm23 zmm24 zmm25 zmm26 zmm27 zmm28 zmm29 zmm30 zmm31));
     %r = (%r, map {$_=>[64,  'm'  ]}  qw(k0 k1 k2 k3 k4 k5 k6 k7));

  %Registers = %r;                                                              # Register names

  my sub registerContaining($@)
   {my ($r, @r) = @_;                                                           # Register, contents
    $RegisterContaining{$r} = $r;                                               # A register contains itself
    $RegisterContaining{$_} = $r for @r;                                        # Registers contained by a register
   }

  registerContaining("k$_")                                            for 0..7;
  registerContaining("zmm$_",   "ymm$_", "xmm$_")                      for 0..31;
  registerContaining("r${_}x", "e${_}x", "${_}x",  "${_}l",  "${_}h")  for qw(a b c d);
  registerContaining("r${_}",  "r${_}l", "r${_}w", "r${_}b", "r${_}d") for 8..15;
  registerContaining("r${_}p", "e${_}p", "${_}p",  "${_}pl")           for qw(s b);
  registerContaining("r${_}i", "e${_}i", "${_}i", "${_}il")            for qw(s d);
  my @i0 = qw(cpuid lahf leave popfq pushfq rdtsc ret syscall);                 # Zero operand instructions

  my @i1 = split /\s+/, <<END;                                                  # Single operand instructions
align bswap call dec div idiv  inc jmp ja jae jb jbe jc jcxz je jecxz jg jge jl jle
jna jnae jnb jnbe jnc jne jng jnge jnl jnle jno jnp jns jnz jo jp jpe jpo jrcxz
js jz loop neg not seta setae setb setbe setc sete setg setge setl setle setna setnae
setnb setnbe setnc setne setng setnge setnl setno setnp setns setnz seto setp
setpe setpo sets setz pop push
END

  my @i2 =  split /\s+/, <<END;                                                 # Double operand instructions
add and bt btc btr bts
cmova cmovae cmovb cmovbe cmovc cmove cmovg cmovge cmovl cmovle
cmovna cmovnae cmovnb cmp
enter
imul
kmov knot kortest ktest lea lzcnt mov movdqa
or popcnt sal sar shl shr sub test tzcnt
vcvtudq2pd vcvtuqq2pd vcvtudq2ps vmovdqu vmovdqu32 vmovdqu64 vmovdqu8
vpcompressd vpcompressq vpexpandd vpexpandq xchg xor
vmovd vmovq
mulpd
pslldq psrldq
vpmovb2m vpmovw2m Vpmovd2m vpmovq2m

vsqrtpd
vmovdqa32 vmovdqa64
END
# print STDERR join ' ', sort @i2; exit;

  my @i2qdwb =  split /\s+/, <<END;                                             # Double operand instructions which have qdwb versions
vpmovm2
vpbroadcast
END

  my @i3 =  split /\s+/, <<END;                                                 # Triple operand instructions
andn
bzhi
imul3
kadd kand kandn kor kshiftl kshiftr kunpck kxnor kxor

vdpps
vprolq
vgetmantps
vaddd
vmulpd vaddpd
END

  my @i3qdwb =  split /\s+/, <<END;                                             # Triple operand instructions which have qdwb versions
pinsr pextr valign vpand vpandn vpcmpeq vpor vpxor vptest vporvpcmpeq vpinsr vpextr vpadd vpsub vpmull
END

  my @i4 =  split /\s+/, <<END;                                                 # Quadruple operand instructions
END

  my @i4qdwb =  split /\s+/, <<END;                                             # Quadruple operand instructions which have qdwb versions
vpcmpu
END

  if (1)                                                                        # Add variants to mask instructions
   {my @k2  = grep {m/\Ak/} @i2; @i2  = grep {!m/\Ak/} @i2;
    my @k3  = grep {m/\Ak/} @i3; @i3  = grep {!m/\Ak/} @i3;
    for my $s(qw(b w d q))
     {push @i2, $_.$s for grep {m/\Ak/} @k2;
      push @i3, $_.$s for grep {m/\Ak/} @k3;
     }
   }

  if (1)                                                                        # Add qdwb versions of instructions
   {for my $o(@i2qdwb)
     {push @i2, $o.$_ for qw(b w d q);
     }
    for my $o(@i3qdwb)
     {push @i3, $o.$_ for qw(b w d q);
     }
    for my $o(@i4qdwb)
     {push @i4, $o.$_ for qw(b w d q);
     }
   }

  for my $r(sort keys %r)                                                       # Create register definitions
   {if (1)
     {my $s = "sub $r\{q($r)\}";
      eval $s;
      confess "$s$@ "if $@;
     }
    if (1)
     {my $b = $r{$r}[0] / $bitsInByte;
      my $s = "sub ${r}Size\{$b}";
      eval $s;
      confess "$s$@ "if $@;
     }
   }

  my %v = map {$$_[1]=>1} values %r;
  for my $v(sort keys %v)                                                       # Types of register
   {my @r = grep {$r{$_}[1] eq $v} sort keys %r;
    my $s = "sub registers_$v\{".dump(\@r)."}";
    eval $s;
    confess "$s$@" if $@;
   }

  if (1)                                                                        # Instructions that take zero operands
   {my $s = '';
    for my $i(@i0)
      {my $I = ucfirst $i;
       $s .= <<END;
       sub $I()
        {\@_ == 0 or confess "No arguments allowed";
         my \$s = '  ' x scalar(my \@d = caller);
         push \@text, qq(\${s}$i\\n);
        }
END
     }
    eval $s;
    confess "$s$@" if $@;
   }

  if (1)                                                                        # Instructions that take one operand
   {my $s = '';
    for my $i(@i1)
      {my $I = ucfirst $i;
       $s .= <<END;
       sub $I
        {my (\$target) = \@_;
         \@_ == 1 or confess "One argument required, not ".scalar(\@_);
         my \$s = '  ' x scalar(my \@d = caller);
         push \@text, qq(\${s}$i \$target\\n);
        }
END
     }
    eval $s;
    confess "$s$@" if $@;
   }

  if (1)                                                                        # Instructions that take two operands
   {my $s = '';
    for my $i(@i2)
      {my $I = ucfirst $i;
       $s .= <<END;
       sub $I(\@)
        {my (\$target, \$source) = \@_;
         \@_ == 2 or confess "Two arguments required, not ".scalar(\@_);
#TEST         Keep(\$target)    if "$i" =~ m(\\Amov\\Z) and \$Registers{\$target};
#TEST         KeepSet(\$source) if "$i" =~ m(\\Amov\\Z) and \$Registers{\$source};
         my \$s = '  ' x scalar(my \@d = caller);
         push \@text, qq(\${s}$i \$target, \$source\\n);
        }
END
     }
    eval $s;
    confess "$s$@" if $@;
   }

  if (1)                                                                        # Instructions that take three operands
   {my $s = '';
    for my $i(@i3)
      {my $I = ucfirst $i;
       my $j = $i =~ s(\d\Z) ()r;                                               # Remove number of parameters designated
       $s .= <<END;
       sub $I(\@)
        {my (\$target, \$source, \$bits) = \@_;
         \@_ == 3 or confess "Three arguments required, not ".scalar(\@_);
         my \$s = '  ' x scalar(my \@d = caller);
         push \@text, qq(\${s}$j \$target, \$source, \$bits\\n);
        }
END
     }
    eval "$s$@";
    confess $@ if $@;
   }

  if (1)                                                                        # Instructions that take four operands
   {my $s = '';
    for my $i(@i4)
      {my $I = ucfirst $i;
       $s .= <<END;
       sub $I(\@)
        {my (\$target, \$source, \$bits, \$zero) = \@_;
         \@_ == 4 or confess "Four arguments required, not ".scalar(\@_);
         my \$s = '  ' x scalar(my \@d = caller);
         push \@text, qq(\${s}$i \$target, \$source, \$bits, \$zero\\n);
        }
END
     }
    eval "$s$@";
    confess $@ if $@;
   }
 }

sub byteRegister($)                                                             # The byte register corresponding to a full size register
 {my ($r) = @_;                                                                 # Full size register
  if ($r =~ m(\Ar([abcd])x\Z)) {return $1."l"};
  return dil if $r eq rdi;
  return sil if $r eq rsi;
  $r."b"
 }

sub wordRegister($)                                                             # The word register corresponding to a full size register
 {my ($r) = @_;                                                                 # Full size register
  if ($r =~ m(\Ar([abcd])x\Z)) {return $1."x"};
  return di if $r eq rdi;
  return si if $r eq rsi;
  $r."w"
 }

sub dWordRegister($)                                                            # The double word register corresponding to a full size register
 {my ($r) = @_;                                                                 # Full size register
  if ($r =~ m(\Ar([abcd])x\Z)) {return "e".$1."x"};
  return edi if $r eq rdi;
  return esi if $r eq rsi;
  $r."d"
 }

sub CheckIfMaskRegisterNumber($);                                               # Check that we have a mask register
sub CheckMaskRegisterNumber($);                                                 # Check that we have a mask register and confess if we do not
sub ClearRegisters(@);                                                          # Clear registers by setting them to zero.
sub Comment(@);                                                                 # Insert a comment into the assembly code.
sub DComment(@);                                                                # Insert a comment into the data section.
sub PeekR($);                                                                   # Peek at the register on top of the stack.
sub PopR(@);                                                                    # Pop a list of registers off the stack.
sub PopRR(@);                                                                   # Pop a list of registers off the stack without tracking.
sub PrintErrRegisterInHex(@);                                                   # Print a register on stderr
sub PrintErrStringNL(@);                                                        # Print a constant string followed by a new line to stderr.
sub PrintOutMemory;                                                             # Print the memory addressed by rax for a length of rdi.
sub PrintOutRegisterInHex(@);                                                   # Print any register as a hex string.
sub PrintOutStringNL(@);                                                        # Print a constant string to stdout followed by new line.
sub PrintString($@);                                                            # Print a constant string to the specified channel.
sub PushR(@);                                                                   # Push a list of registers onto the stack.
sub PushRR(@);                                                                  # Push a list of registers onto the stack without tracking.
sub RComment(@);                                                                # Insert a comment into the read only data section.
sub StringLength($);                                                            # Length of a zero terminated string.
sub Subroutine2(&%);                                                            # Create a subroutine that can be called in assembler code.
sub Syscall();                                                                  # System call in linux 64 format.

#D1 Data                                                                        # Layout data

my $Labels = 0;

sub Label(;$)                                                                   #P Create a unique label or reuse the one supplied.
 {return "l".++$Labels unless @_;                                               # Generate a label
  $_[0];                                                                        # Use supplied label
 }

sub SetLabel(;$)                                                                # Create (if necessary) and set a label in the code section returning the label so set.
 {my ($l) = @_;                                                                 # Label
  $l //= Label;
  push @text, <<END;                                                            # Define bytes
  $l:
END
  $l                                                                            # Return label name
 }

sub Ds(@)                                                                       # Layout bytes in memory and return their label.
 {my (@d) = @_;                                                                 # Data to be laid out
  my $d = join '', @_;
     $d =~ s(') (\')gs;
  my $l = Label;
  push @data, <<END;                                                            # Define bytes
  $l: db  '$d';
END
  $l                                                                            # Return label
 }

sub Rs(@)                                                                       # Layout bytes in read only memory and return their label.
 {my (@d) = @_;                                                                 # Data to be laid out
  my $d = join '', @_;
  my @e;
  for my $e(split //, $d)
   {if ($e !~ m([A-Z0-9])i) {push @e, sprintf("0x%x", ord($e))} else {push @e, qq('$e')}
   }
  my $e = join ', ', @e;
  my $L = $rodatas{$e};
  return $L if defined $L;                                                      # Data already exists so return it
  my $l = Label;                                                                # New label for new data
  $rodatas{$e} = $l;                                                            # Record label
  push @rodata, <<END;                                                          # Define bytes
  $l: db  $e, 0;
END
  $l                                                                            # Return label
 }

sub Rutf8(@)                                                                    # Layout a utf8 encoded string as bytes in read only memory and return their label.
 {my (@d) = @_;                                                                 # Data to be laid out
  confess unless @_;
  my $d = join '', @_; ## No need to join and split
  my @e;
  for my $e(split //, $d)
   {my $o  = ord $e;                                                            # Effectively the utf32 encoding of each character
    my $u  = convertUtf32ToUtf8($o);
    my $x  = sprintf("%08x", $u);
    my $o1 = substr($x, 0, 2);
    my $o2 = substr($x, 2, 2);
    my $o3 = substr($x, 4, 2);
    my $o4 = substr($x, 6, 2);
    if    ($o <= (1 << 7))  {push @e,                $o4}
    elsif ($o <= (1 << 11)) {push @e,           $o3, $o4}
    elsif ($o <= (1 << 16)) {push @e,      $o2, $o3, $o4}
    else                    {push @e, $o1, $o2, $o3, $o4}
   }

  my $e = join ', ',map {"0x$_"}  @e;
  my $L = $rodatas{$e};
  return $L if defined $L;                                                      # Data already exists so return it
  my $l = Label;                                                                # New label for new data
  $rodatas{$e} = $l;                                                            # Record label
  push @rodata, <<END;                                                          # Define bytes
  $l: db  $e, 0;
END
  $l                                                                            # Return label
 }

sub Dbwdq($@)                                                                   #P Layout data.
 {my ($s, @d) = @_;                                                             # Element size, data to be laid out
  my $d = join ', ', @d;
  my $l = Label;
  push @data, <<END;
  $l: d$s $d
END
  $l                                                                            # Return label
 }

sub Db(@)                                                                       # Layout bytes in the data segment and return their label.
 {my (@bytes) = @_;                                                             # Bytes to layout
  Dbwdq 'b', @_;
 }
sub Dw(@)                                                                       # Layout words in the data segment and return their label.
 {my (@words) = @_;                                                             # Words to layout
  Dbwdq 'w', @_;
 }
sub Dd(@)                                                                       # Layout double words in the data segment and return their label.
 {my (@dwords) = @_;                                                            # Double words to layout
  Dbwdq 'd', @_;
 }
sub Dq(@)                                                                       # Layout quad words in the data segment and return their label.
 {my (@qwords) = @_;                                                            # Quad words to layout
  Dbwdq 'q', @_;
 }

sub Rbwdq($@)                                                                   #P Layout data.
 {my ($s, @d) = @_;                                                             # Element size, data to be laid out
  my $d = join ', ', map {$_ =~ m(\A\d+\Z) ? sprintf "0x%x", $_ : $_} @d;       # Data to be laid out
  if (my $c = $rodata{$s}{$d})                                                  # Data already exists so return it
   {return $c
   }
  my $l = Label;                                                                # New data - create a label
  push @rodata, <<END;                                                          # Save in read only data
  $l: d$s $d
END
  $rodata{$s}{$d} = $l;                                                         # Record label
  $l                                                                            # Return label
 }

sub Rb(@)                                                                       # Layout bytes in the data segment and return their label.
 {my (@bytes) = @_;                                                             # Bytes to layout
  Rbwdq 'b', @_;
 }
sub Rw(@)                                                                       # Layout words in the data segment and return their label.
 {my (@words) = @_;                                                             # Words to layout
  Rbwdq 'w', @_;
 }
sub Rd(@)                                                                       # Layout double words in the data segment and return their label.
 {my (@dwords) = @_;                                                            # Double words to layout
  Rbwdq 'd', @_;
 }
sub Rq(@)                                                                       # Layout quad words in the data segment and return their label.
 {my (@qwords) = @_;                                                            # Quad words to layout
  Rbwdq 'q', @_;
 }

my $Pi = "3.141592653589793238462";

sub Pi32 {Rd("__float32__($Pi)")}                                               #P Pi as a 32 bit float.
sub Pi64 {Rq("__float32__($Pi)")}                                               #P Pi as a 64 bit float.

#D1 Registers                                                                   # Operations on registers

#D2 General                                                                     # Actions specific to general purpose registers

sub registerNameFromNumber($)                                                   # Register name from number where possible
 {my ($r) = @_;                                                                 # Register number
  return "zmm$r" if $r =~ m(\A(16|17|18|19|20|21|22|23|24|25|26|27|28|29|30|31)\Z);
  return   "r$r" if $r =~ m(\A(8|9|10|11|12|13|14|15)\Z);
  return   "k$r" if $r =~ m(\A(0|1|2|3|4|5|6|7)\Z);
  $r
 }

sub ChooseRegisters($@)                                                         # Choose the specified numbers of registers excluding those on the specified list.
 {my ($number, @registers) = @_;                                                # Number of registers needed, Registers not to choose
  my %r = (map {$_=>1} map {"r$_"} 8..15);
  delete $r{$_} for @registers;
  $number <= keys %r or confess "Not enough registers available";
  sort keys %r
 }

sub CheckGeneralPurposeRegister($)                                              # Check that a register is in fact a general purpose register.
 {my ($reg) = @_;                                                               # Register to check
  @_ == 1 or confess "One parameter";
  $Registers{$reg} && $reg =~ m(\Ar) or
    confess "Not a general purpose register: $reg";
 }

sub ChooseZmmRegisterNotIn(@)                                                   # Choose a zmm register different from any in the list.
 {my (@zmm) = @_;                                                               # Zmm number to exclude
  my %z = map {$_=>1} 0..31;
  delete $z{$_} for @zmm;
  my ($z) = sort {$a <=> $b}  keys %z;
  $z
 }

sub CheckNumberedGeneralPurposeRegister($)                                      # Check that a register is in fact a numbered general purpose register.
 {my ($reg) = @_;                                                               # Register to check
  @_ == 1 or confess "One parameter";
  $Registers{$reg} && $reg =~ m(\Ar\d{1,2}\Z);
 }

sub InsertZeroIntoRegisterAtPoint($$)                                           # Insert a zero into the specified register at the point indicated by another general purpose or mask register moving the higher bits one position to the left.
 {my ($point, $in) = @_;                                                        # Register with a single 1 at the insertion point, register to be inserted into.

  ref($point) and confess "Point must be a register";

  PushR my ($mask, $low, $high) = ChooseRegisters(3, $in, $point);              # Choose three work registers and push them
  if (&CheckMaskRegister($point))                                               # Mask register showing point
   {Kmovq $mask, $point;
   }
  else                                                                          # General purpose register showing point
   {Mov  $mask, $point;
   }

  Dec  $mask;                                                                   # Fill mask to the right of point with ones
  Andn $high, $mask, $in;                                                       # Part of in be shifted
  Shl  $high, 1;                                                                # Shift high part
  And  $in,  $mask;                                                             # Clear high part of target
  Or   $in,  $high;                                                             # Or in new shifted high part
  PopR;                                                                         # Restore stack
 }

sub InsertOneIntoRegisterAtPoint($$)                                            # Insert a one into the specified register at the point indicated by another register.
 {my ($point, $in) = @_;                                                        # Register with a single 1 at the insertion point, register to be inserted into.
  InsertZeroIntoRegisterAtPoint($point, $in);                                   # Insert a zero
  if (CheckIfMaskRegisterNumber $point)                                         # Mask register showing point
   {my ($r) = ChooseRegisters(1, $in);                                          # Choose a general purpose register to place the mask in
    PushR $r;
    Kmovq $r, $point;
    Or   $in, $r;                                                               # Make the zero a one
    PopR;
   }
  else                                                                          # General purpose register showing point
   {Or $in, $point;                                                             # Make the zero a one
   }
 }

#D3 Save and Restore                                                            # Saving and restoring registers via the stack

my @syscallSequence = qw(rax rdi rsi rdx r10 r8 r9);                            # The parameter list sequence for system calls

sub SaveFirstFour(@)                                                            # Save the first 4 parameter registers making any parameter registers read only.
 {my (@keep) = @_;                                                              # Registers to mark as read only
  my $N = 4;
  PushRR $_ for @syscallSequence[0..$N-1];
  $N * &RegisterSize(rax);                                                      # Space occupied by push
 }

sub RestoreFirstFour()                                                          # Restore the first 4 parameter registers.
 {my $N = 4;
  PopRR $_ for reverse @syscallSequence[0..$N-1];
 }

sub RestoreFirstFourExceptRax()                                                 # Restore the first 4 parameter registers except rax so it can return its value.
 {my $N = 4;
  PopRR $_ for reverse @syscallSequence[1..$N-1];
  Add rsp, 1*RegisterSize(rax);
 }

sub RestoreFirstFourExceptRaxAndRdi()                                           # Restore the first 4 parameter registers except rax  and rdi so we can return a pair of values.
 {my $N = 4;
  PopRR $_ for reverse @syscallSequence[2..$N-1];
  Add rsp, 2*RegisterSize(rax);
 }

sub SaveFirstSeven()                                                            # Save the first 7 parameter registers.
 {my $N = 7;
  PushRR $_ for @syscallSequence[0..$N-1];
  $N * 1*RegisterSize(rax);                                                     # Space occupied by push
 }

sub RestoreFirstSeven()                                                         # Restore the first 7 parameter registers.
 {my $N = 7;
  PopRR $_ for reverse @syscallSequence[0..$N-1];
 }

sub RestoreFirstSevenExceptRax()                                                # Restore the first 7 parameter registers except rax which is being used to return the result.
 {my $N = 7;
  PopRR $_ for reverse @syscallSequence[1..$N-1];
  Add rsp, 1*RegisterSize(rax);
 }

sub RestoreFirstSevenExceptRaxAndRdi()                                          # Restore the first 7 parameter registers except rax and rdi which are being used to return the results.
 {my $N = 7;
  PopRR $_ for reverse @syscallSequence[2..$N-1];
  Add rsp, 2*RegisterSize(rax);                                                 # Skip rdi and rax
 }

sub ReorderSyscallRegisters(@)                                                  # Map the list of registers provided to the 64 bit system call sequence.
 {my (@registers) = @_;                                                         # Registers
  PushRR @syscallSequence[0..$#registers];
  PushRR @registers;
  PopRR  @syscallSequence[0..$#registers];
 }

sub UnReorderSyscallRegisters(@)                                                # Recover the initial values in registers that were reordered.
 {my (@registers) = @_;                                                         # Registers
  PopRR  @syscallSequence[0..$#registers];
 }

sub RegisterSize($)                                                             # Return the size of a register.
 {my ($r) = @_;                                                                 # Register
  $r = registerNameFromNumber $r;
  defined($r) or confess;
  defined($Registers{$r}) or confess "No such registers as: $r";
  eval "${r}Size()";
 }

sub ClearRegisters(@)                                                           # Clear registers by setting them to zero.
 {my (@registers) = @_;                                                         # Registers
  my $w = RegisterSize rax;
  for my $r(map{registerNameFromNumber $_} @registers)                          # Each register
   {my $size = RegisterSize $r;
    Xor    $r, $r     if $size == $w and $r !~ m(\Ak);
    Kxorq  $r, $r, $r if $size == $w and $r =~ m(\Ak);
    Vpxorq $r, $r, $r if $size  > $w;
   }
 }

sub SetZF()                                                                     # Set the zero flag.
 {Cmp rax, rax;
 }

sub ClearZF()                                                                   # Clear the zero flag.
 {PushR rax;
  Mov rax, 1;
  Cmp rax, 0;
  PopR rax;
 }

#D2 x, y, zmm                                                                   # Actions specific to mm registers

sub xmm(@)                                                                      # Add xmm to the front of a list of register expressions.
 {my (@r) = @_;                                                                 # Register numbers
  map {"xmm$_"} @_;
 }

sub ymm(@)                                                                      # Add ymm to the front of a list of register expressions.
 {my (@r) = @_;                                                                 # Register numbers
  map {"ymm$_"} @_;
 }

sub zmm(@)                                                                      # Add zmm to the front of a list of register expressions.
 {my (@r) = @_;                                                                 # Register numbers
  map {"zmm$_"} @_;
 }

sub zmmM($$)                                                                    # Add zmm to the front of a register number and a mask after it
 {my ($z, $m) = @_;                                                             # Zmm number, mask register
  "zmm$z\{k$m}"
 }

sub zmmMZ($$)                                                                   # Add zmm to the front of a register number and mask and zero after it
 {my ($z, $m) = @_;                                                             # Zmm number, mask register number
  "zmm$z\{k$m}\{z}"
 }

sub LoadZmm($@)                                                                 # Load a numbered zmm with the specified bytes.
 {my ($zmm, @bytes) = @_;                                                       # Numbered zmm, bytes
  my $b = Rb(@bytes);
  Vmovdqu8 "zmm$zmm", "[$b]";
 }

sub checkZmmRegister($)                                                         # Check that a register is a zmm register
 {my ($z) = @_;                                                              # Parameters
  $z =~ m(\A(0|1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|17|18|19|20|21|22|23|24|25|26|27|28|29|30|31)\Z) or confess "$z is not the number of a zmm register";
 }

#D2 Mask                                                                        # Operations on mask registers

sub CheckMaskRegister($)                                                        # Check that a register is in fact a numbered mask register
 {my ($reg) = @_;                                                               # Register to check
  @_ == 1 or confess "One parameter";
  $Registers{$reg} && $reg =~ m(\Ak[0-7]\Z)
 }

sub CheckIfMaskRegisterNumber($)                                                # Check that a register is in fact a mask register.
 {my ($mask) = @_;                                                              # Mask register to check
  @_ == 1 or confess "One parameter";
  $mask =~ m(\Ak?[0-7]\Z)
 }

sub CheckMaskRegisterNumber($)                                                  # Check that a register is in fact a mask register and confess if it is not.
 {my ($mask) = @_;                                                              # Mask register to check
  @_ == 1 or confess "One parameter";
  $mask =~ m(\Ak?[0-7]\Z) or confess "Not the number of a mask register: $mask";
 }

sub SetMaskRegister($$$)                                                        # Set the mask register to ones starting at the specified position for the specified length and zeroes elsewhere.
 {my ($mask, $start, $length) = @_;                                             # Number of mask register to set, register containing start position or 0 for position 0, register containing end position
  @_ == 3 or confess "Three parameters";
  CheckMaskRegisterNumber($mask);

  PushR (r15, r14);
  Mov r15, -1;
  if ($start)                                                                   # Non zero start
   {Mov  r14, $start;
    Bzhi r15, r15, r14;
    Not  r15;
    Add  r14, $length;
   }
  else                                                                          # Starting at zero
   {Mov r14, $length;
   }
  Bzhi r15, r15, r14;
  Kmovq "k$mask", r15;
  PopR;
 }

sub LoadConstantIntoMaskRegister($$)                                            # Set a mask register equal to a constant.
 {my ($mask, $value) = @_;                                                      # Number of mask register to load, constant to load
  @_ == 2 or confess "Two parameters";
  CheckMaskRegisterNumber $mask;
  $mask     = registerNameFromNumber $mask;
  Mov rdi, $value;                                                              # Load mask into a general purpose register
  Kmovq $mask, rdi;                                                             # Load mask register from general purpose register
 }

sub createBitNumberFromAlternatingPattern($@)                                   # Create a number from a bit pattern.
 {my ($prefix, @values) = @_;                                                   # Prefix bits, +n 1 bits -n 0 bits
  @_ > 1 or confess "Four or more parameters required";                         # Must have some values

  $prefix =~ m(\A[01]*\Z) or confess "Prefix must be binary";                   # Prefix must be binary
  grep {$_ == 0} @values and confess "Values must not be zero";                 # No value may be zero

  for my $i(0..$#values-1)                                                      # Check values alternate
   {($values[$i] > 0 && $values[$i+1] > 0  or
     $values[$i] < 0 && $values[$i+1] < 0) and confess "Signs must alternate";
   }

  my $b = "0b$prefix";
  for my $v(@values)                                                            # String representation of bit string
   {$b .= '1' x +$v if $v > 0;
    $b .= '0' x -$v if $v < 0;
   }

  my $n = eval $b;
  confess $@ if $@;
  $n
 }

sub LoadBitsIntoMaskRegister($$@)                                               # Load a bit string specification into a mask register in two clocks.
 {my ($mask, $prefix, @values) = @_;                                            # Number of mask register to load, prefix bits, +n 1 bits -n 0 bits
  @_ > 2 or confess "Three or more parameters required";                        # Must have some values

  LoadConstantIntoMaskRegister                                                  # Load the specified binary constant into a mask register
    ($mask, createBitNumberFromAlternatingPattern $prefix, @values)
 }

#D1 Comparison codes                                                            # The codes used to specify what sort of comparison to perform

my $Vpcmp = genHash("NasmX86::CompareCodes",                                    # Compare codes for "Vpcmp"
  eq=>0,                                                                        # Equal
  lt=>1,                                                                        # Less than
  le=>2,                                                                        # Less than or equals
  ne=>4,                                                                        # Not equals
  ge=>5,                                                                        # Greater than or equal
  gt=>6,                                                                        # Greater than
 );

#D1 Structured Programming                                                      # Structured programming constructs

sub If($$;$)                                                                    # If statement.
 {my ($jump, $then, $else) = @_;                                                # Jump op code of variable, then - required , else - optional
  @_ >= 2 && @_ <= 3 or confess;

  ref($jump) or $jump =~ m(\AJ(c|e|g|ge|gt|h|l|le|nc|ne|ns|nz|s|z)\Z)
             or confess "Invalid jump: $jump";

  if (ref($jump))                                                               # Variable expression,  if it is non zero perform the then block else the else block
   { __SUB__->(q(Jnz), $then, $else);
   }
  elsif (!$else)                                                                # No else
   {my $end = Label;
    push @text, <<END;
    $jump $end;
END
    &$then;
    SetLabel $end;
   }
  else                                                                          # With else
   {my $endIf     = Label;
    my $startElse = Label;
    push @text, <<END;
    $jump $startElse
END
    &$then;
    Jmp $endIf;
    SetLabel $startElse;
    &$else;
    SetLabel  $endIf;
   }
 }

sub Then(&)                                                                     # Then block for an If statement.
 {my ($block) = @_;                                                             # Then block
  $block;
 }

sub Else(&)                                                                     # Else block for an If statement.
 {my ($block) = @_;                                                             # Else block
  $block;
 }

sub Ef(&$;$)                                                                    # Else if block for an If statement.
 {my ($condition, $then, $else) = @_;                                           # Condition, then block, else block
  sub
  {If (&$condition, $then, $else);
  }
 }

sub IfEq($;$)                                                                   # If equal execute the then block else the else block.
 {my ($then, $else) = @_;                                                       # Then - required , else - optional
  If(q(Jne), $then, $else);                                                     # Opposite code
 }

sub IfNe($;$)                                                                   # If not equal execute the then block else the else block.
 {my ($then, $else) = @_;                                                       # Then - required , else - optional
  If(q(Je), $then, $else);                                                      # Opposite code
 }

sub IfNz($;$)                                                                   # If the zero flag is not set then execute the then block else the else block.
 {my ($then, $else) = @_;                                                       # Then - required , else - optional
  If(q(Jz), $then, $else);                                                      # Opposite code
 }

sub IfZ($;$)                                                                    # If the zero flag is set then execute the then block else the else block.
 {my ($then, $else) = @_;                                                       # Then - required , else - optional
  If(q(Jnz), $then, $else);                                                     # Opposite code
 }

sub IfC($;$)                                                                    # If the carry flag is set then execute the then block else the else block.
 {my ($then, $else) = @_;                                                       # Then - required , else - optional
  If(q(Jnc), $then, $else);                                                     # Opposite code
 }

sub IfNc($;$)                                                                   # If the carry flag is not set then execute the then block else the else block.
 {my ($then, $else) = @_;                                                       # Then - required , else - optional
  If(q(Jc), $then, $else);                                                      # Opposite code
 }

sub IfLt($;$)                                                                   # If less than execute the then block else the else block.
 {my ($then, $else) = @_;                                                       # Then - required , else - optional
  If(q(Jge), $then, $else);                                                     # Opposite code
 }

sub IfLe($;$)                                                                   # If less than or equal execute the then block else the else block.
 {my ($then, $else) = @_;                                                       # Then - required , else - optional
  If(q(Jg), $then, $else);                                                      # Opposite code
 }

sub IfGt($;$)                                                                   # If greater than execute the then block else the else block.
 {my ($then, $else) = @_;                                                       # Then - required , else - optional
  If(q(Jle), $then, $else);                                                     # Opposite code
 }

sub IfGe($;$)                                                                   # If greater than or equal execute the then block else the else block.
 {my ($then, $else) = @_;                                                       # Then - required , else - optional
  If(q(Jl), $then, $else);                                                      # Opposite code
 }

sub IfS($;$)                                                                    # If signed greater than or equal execute the then block else the else block.
 {my ($then, $else) = @_;                                                       # Then - required , else - optional
  If(q(Jns), $then, $else);                                                     # Opposite code
 }

sub IfNs($;$)                                                                   # If signed less than execute the then block else the else block.
 {my ($then, $else) = @_;                                                       # Then - required , else - optional
  If(q(Js), $then, $else);                                                      # Opposite code
 }

sub Pass(&)                                                                     # Pass block for an L<OrBlock>.
 {my ($block) = @_;                                                             # Block
  $block;
 }

sub Fail(&)                                                                     # Fail block for an L<AndBlock>.
 {my ($block) = @_;                                                             # Block
  $block;
 }

sub Block(&)                                                                    # Execute a block of code with labels supplied for the start and end of this code
 {my ($code) = @_;                                                              # Block of code
  @_ == 1 or confess "One parameter";
  SetLabel(my $start = Label);                                                  # Start of block
  my $end  = Label;                                                             # End of block
  &$code($end, $start);                                                         # Code with labels supplied
  SetLabel $end;                                                                # End of block
 }

sub AndBlock(&;$)                                                               # Short circuit B<and>: execute a block of code to test conditions which, if all of them pass, allows the first block to continue successfully else if one of the conditions fails we execute the optional fail block.
 {my ($test, $fail) = @_;                                                       # Block, optional failure block
  @_ == 1 or @_ == 2 or confess "One or two parameters";
  SetLabel(my $start = Label);                                                  # Start of test block
  my $Fail = @_ == 2 ? Label : undef;                                           # Start of fail block
  my $end  = Label;                                                             # End of both blocks
  &$test(($Fail // $end), $end, $start);                                        # Test code plus success code
  if ($fail)
   {Jmp $end;                                                                   # Skip the fail block if we succeed in reaching the end of the test block which is the expected behavior for short circuited B<and>.
    SetLabel $Fail;
    &$fail($end, $Fail, $start);                                                # Execute when true
   }
  SetLabel $end;                                                                # Exit block
 }

sub OrBlock(&;$)                                                                # Short circuit B<or>: execute a block of code to test conditions which, if one of them is met, leads on to the execution of the pass block, if all of the tests fail we continue withe the test block.
 {my ($test, $pass) = @_;                                                       # Tests, optional block to execute on success
  @_ == 1 or @_ == 2 or confess "One or two parameters";
  SetLabel(my $start = Label);                                                  # Start of test block
  my $Pass = @_ == 2 ? Label : undef;                                           # Start of pass block
  my $end  = Label;                                                             # End of both blocks
  &$test(($Pass // $end), $end, $start);                                        # Test code plus fail code
  if ($pass)
   {Jmp $end;                                                                   # Skip the pass block if we succeed in reaching the end of the test block which is the expected behavior for short circuited B<or>.
    SetLabel $Pass;
    &$pass($end, $Pass, $start);                                                # Execute when true
   }
  SetLabel $end;                                                                # Exit block
 }

sub For(&$$;$)                                                                  # For - iterate the block as long as register is less than limit incrementing by increment each time. Nota Bene: The register is not explicitly set to zero as you might want to start at some other number.
 {my ($block, $register, $limit, $increment) = @_;                              # Block, register, limit on loop, increment on each iteration
  @_ == 3 or @_ == 4 or confess;
  $increment //= 1;                                                             # Default increment
  my $next = Label;                                                             # Next iteration
  Comment "For $register $limit";
  my $start = Label;
  my $end   = Label;
  SetLabel $start;
  Cmp $register, $limit;
  Jge $end;

  &$block($start, $end, $next);                                                 # Start, end and next labels

  SetLabel $next;                                                               # Next iteration starting with after incrementing
  if ($increment == 1)
   {Inc $register;
   }
  else
   {Add $register, $increment;
   }
  Jmp $start;                                                                   # Restart loop
  SetLabel $end;                                                                # Exit loop
 }

sub ForIn(&$$$$)                                                                # For - iterate the full block as long as register plus increment is less than than limit incrementing by increment each time then increment the last block for the last non full block.
 {my ($full, $last, $register, $limitRegister, $increment) = @_;                # Block for full block, block for last block , register, register containing upper limit of loop, increment on each iteration
  @_ == 5 or confess;
  my $start = Label;
  my $end   = Label;

  SetLabel $start;                                                              # Start of loop
  PushR $register;                                                              # Save the register so we can test that there is still room
  Add   $register, $increment;                                                  # Add increment
  Cmp   $register, $limitRegister;                                              # Test that we have room for increment
  PopR  $register;                                                              # Remove increment
  Jge   $end;

  &$full;

  Add $register, $increment;                                                    # Increment for real
  Jmp $start;
  SetLabel $end;

  Sub $limitRegister, $register;                                                # Size of remainder
  IfNz                                                                          # Non remainder
  Then
   {&$last;                                                                     # Process remainder
   }
 }

sub ForEver(&)                                                                  # Iterate for ever.
 {my ($block) = @_;                                                             # Block to iterate
  @_ == 1 or confess "One parameter";
  Comment "ForEver";
  my $start = Label;                                                            # Start label
  my $end   = Label;                                                            # End label

  SetLabel $start;                                                              # Start of loop

  &$block($start, $end);                                                        # End of loop

  Jmp $start;                                                                   # Restart loop
  SetLabel $end;                                                                # End of loop
 }

#D2 Call                                                                        # Call a subroutine

my @VariableStack = (1);                                                        # Counts the number of parameters and variables on the stack in each invocation of L<Subroutine>.  There is at least one variable - the first holds the traceback.

sub SubroutineStartStack()                                                      # Initialize a new stack frame.  The first quad of each frame has the address of the name of the sub in the low dword, and the parameter count in the upper byte of the quad.  This field is all zeroes in the initial frame.
 {push @VariableStack, 1;                                                       # Counts the number of variables on the stack in each invocation of L<Subroutine>.  The first quad provides the traceback.
 }

sub Subroutine(&$%)                                                             # Create a subroutine that can be called in assembler code.
 {my ($block, $parameters, %options) = @_;                                      # Block, [parameters  names], options.
  @_ >= 2 or confess;
  !$parameters or ref($parameters) =~ m(array)i or
    confess "Reference to array of parameter names required";

  if (1)                                                                        # Check for duplicate parameters
   {my %c;
    $c{$_}++ && confess "Duplicate parameter $_" for @$parameters;
    if (my $with = $options{with})                                              # Copy the argument list of the caller if requested
     {for my $p($with->parameters->@*)
       {$c{$p}++ and confess "Duplicate copied parameter $p";
       }
      @$parameters = sort keys %c;
     }
   }

  my $name    = $options{name};                                                 # Subroutine name
  $name or confess "Name required for subroutine, use [], name=>";

  if ($name and my $n = $subroutines{$name}) {return $n}                        # Return the label of a pre-existing copy of the code. Make sure that the name is different for different subs as otherwise the unexpected results occur.

  SubroutineStartStack;                                                         # Open new stack layout with references to parameters
  my %p; $p{$_} = R($_) for @$parameters;                                       # Create a reference each parameter.

  my %structureVariables;                                                       # Variables needed by structures provided as parameters
  if (my $structures = $options{structures})
   {
   }

  my $end   =    Label; Jmp $end;                                               # End label.  Subroutines are only ever called - they are not executed in-line so we jump over the implementation of the subroutine.  This can cause several forward jumps in a row if a number of subroutines are defined together.
  my $start = SetLabel;                                                         # Start label

  my $s = $subroutines{$name} = genHash(__PACKAGE__."::Sub",                    # Subroutine definition
    start      => $start,                                                       # Start label for this subroutine which includes the enter instruction used to create a new stack frame
    end        => $start,                                                       # End label for this subroutine
    name       => $name,                                                        # Name of the subroutine from which the entry label is located
    args       => {map {$_=>1} @$parameters},                                   # Hash of {argument name, argument variable}
    variables  => {%p},                                                         # Argument variables which show up as the first parameter in the called sub so that it knows what its parameters are.
    options    => \%options,                                                    # Options used by the author of the subroutine
    parameters => $parameters,                                                  # Parameters definitions supplied by the author of the subroutine which get mapped in to parameter variables.
    vars       => $VariableStack[-1],                                           # Number of variables in subroutine
    nameString => Rs($name),                                                    # Name of the sub as a string constant in read only storage
   );

  my $E = @text;                                                                # Code entry that will contain the Enter instruction
  Enter 0, 0;                                                                   # The Enter instruction is 4 bytes long
  &$block({%p}, $s);                                                            # Code with parameters

  my $V = pop @VariableStack;                                                   # Number of variables
  my $P = @$parameters;                                                         # Number of parameters supplied
  my $N = $P + $V;                                                              # Size of stack frame

  Leave if $N;                                                                  # Remove frame if there was one
  Ret;                                                                          # Return from the sub
  SetLabel $end;                                                                # The end point of the sub where we return to normal code
  my $w = RegisterSize rax;
  $text[$E] = $N ? <<END : '';                                                  # Rewrite enter instruction now that we know how much stack space we need
  Enter $N*$w, 0
END

  $s                                                                            # Subroutine definition
 }

sub Nasm::X86::Sub::callTo($$$@)                                                #P Call a sub passing it some parameters.
 {my ($sub, $mode, $label, @parameters) = @_;                                   # Subroutine descriptor, mode 0 - direct call or 1 - indirect call, label of sub, parameter variables

  my %p;
  while(@parameters)                                                            # Copy parameters supplied by the caller
   {my $p = shift @parameters;                                                  # Check parameters provided by caller
    my $n = ref($p) ? $p->name : $p;
    defined($n) or confess "No name or variable";
    my $v = ref($p) ? $p       : shift @parameters;                             # Each actual parameter is a variable or an expression that can loaded into a register
    unless ($sub->args->{$n})                                                   # Describe valid parameters using a table
     {my @t;
      push @t, map {[$_]} keys $sub->args->%*;
      my $t = formatTable([@t], [qw(Name)]);
      confess "Invalid parameter: '$n'\n$t";
     }
    $p{$n} = ref($v) ? $v : V($n, $v);
   }

  my %with = ($sub->options->{with}{variables}//{})->%*;                        # The list of arguments the containing subroutine was called with

  if (1)                                                                        # Check for missing arguments
   {my %m = $sub->args->%*;                                                     # Formal arguments
    delete $m{$_} for sort keys %p;                                             # Remove actual arguments
    delete $m{$_} for sort keys %with;                                          # Remove arguments from calling environment if supplied
    keys %m and confess "Missing arguments ".dump([sort keys %m]);              # Print missing parameter names
   }

  if (1)                                                                        # Check for misnamed arguments
   {my %m = %p;                                                                 # Actual arguments
    delete $m{$_} for sort keys($sub->args->%*), sort keys(%with);              # Remove formal arguments
    keys %m and confess "Invalid arguments ".dump([sort keys %m]);              # Print misnamed arguments
   }

  my $w = RegisterSize r15;
  PushR r15;                                                                    # Use this register to transfer between the current frame and the next frame
  Mov "dword[rsp  -$w*3]", $sub->nameString;                                    # Point to name
  Mov "byte [rsp-1-$w*2]", scalar $sub->parameters->@*;                         # Number of parameters to enable traceback with parameters

  if (1)                                                                        # Transfer parameters by copying them to the base of the stack frame
   {my %a = (%with, %p);                                                        # The consolidated argument list
    for my $a(sort keys %a)                                                     # Transfer parameters from current frame to next frame
     {my $label = $a{$a}->label;                                                # Source in current frame
      if ($a{$a}->reference)                                                    # Source is a reference
       {Mov r15, "[$label]";
       }
      else                                                                      # Source is not a reference
       {Lea r15, "[$label]";
       }
      my $q = $sub->variables->{$a}->label;
         $q =~ s(rbp) (rsp);                                                    # Labels are based off the stack frame but we are building a new stack frame here so we must rename the stack pointer.
      Mov "[$q-$w*2]", r15;                                                     # Step over subroutine name pointer and previous frame pointer.
     }
   }

  if ($mode)                                                                    # Dereference and call subroutine
   {Mov r15, $label;
    Mov r15, "[r15]";
    Call r15;
   }
  else                                                                          # Call via label
   {Call $label;
   }
  PopR;
 }

sub Nasm::X86::Sub::call($@)                                                    # Call a sub passing it some parameters.
 {my ($sub, @parameters) = @_;                                                  # Subroutine descriptor, parameter variables
  $sub->callTo(0, $sub->start, @parameters);                                    # Call the subroutine
 }

sub Nasm::X86::Sub::via($$@)                                                    # Call a sub by reference passing it some parameters.
 {my ($sub, $ref, @parameters) = @_;                                            # Subroutine descriptor, variable containing a reference to the sub, parameter variables
  PushR r14, r15;
  if ($ref->reference)                                                          # Dereference address of subroutine.
   {Mov r14, "[$$ref{label}]";                                                  # Reference
   }
  else
   {Lea r14, "[$$ref{label}]";                                                  # Direct
   }
  $sub->callTo(1, r14, @parameters);                                            # Call the subroutine
  PopR;
 }

sub Nasm::X86::Sub::V($)                                                        # Put the address of a subroutine into a stack variable so that it can be passed as a parameter.
 {my ($sub) = @_;                                                               # Subroutine descriptor
  V('call', $sub->start);                                                       # Address subroutine via a stack variable
 }

sub Nasm::X86::Sub::dispatch($)                                                 # Jump into the specified subroutine so that code of the target subroutine is executed instead of the code of the current subroutine allowing the target subroutine to be dispatched to process the parameter list of the current subroutine.  When the target subroutine returns it returns to the caller of the current sub, not to the current subroutine.
 {my ($sub) = @_;                                                               # Subroutine descriptor of target subroutine
  @_ == 1 or confess "One parameter";
  $sub->V()->setReg(rdi);                                                       # Start of sub routine
  Add rdi, 4;                                                                   # Skip initial enter as to prevent a new stack from being created
  Jmp rdi;                                                                      # Start h specified sub - when it exits it will return to the code that called us.
 }

sub Nasm::X86::Sub::dispatchV($)                                                # L<Dispatch|/Nasm::X86::Sub::dispatch> the variable subroutine using the specified register.
 {my ($sub, $reference) = @_;                                                   # Subroutine descriptor, variable referring to the target subroutine
  @_ == 2 or confess "Two parameters";
  $reference->setReg(rdi);                                                      # Start of sub routine
  Add rdi, 4;                                                                   # Skip initial enter as to prevent a new stack from being created
  Jmp rdi;                                                                      # Start h specified sub - when it exits it will return to the code that called us.
 }

sub PrintTraceBack($)                                                           # Trace the call stack.
 {my ($channel) = @_;                                                           # Channel to write on

  Subroutine2
   {PushR my @save = (rax, rdi, r9, r10, r8, r12, r13, r14, r15);
    my $stack     = r15;
    my $count     = r14;
    my $index     = r13;
    my $parameter = r12;                                                        # Number of parameters
    my $maxCount  = r8;                                                         # Maximum number of parameters - should be r11 when we have found out why r11 does not print correctly.
    my $depth     = r10;                                                        # Depth of trace back
    ClearRegisters @save;

    Mov $stack, rbp;                                                            # Current stack frame
    AndBlock                                                                    # Each level
     {my ($fail, $end, $start) = @_;                                            # Fail block, end of fail block, start of test block
      Mov $stack, "[$stack]";                                                   # Up one level
      Mov rax, "[$stack-8]";
      Mov $count, rax;
      Shr $count, 56;                                                           # Top byte contains the parameter count
      Cmp $count, $maxCount;                                                    # Compare this count with maximum so far
      Cmovg $maxCount, $count;                                                  # Update count if greater
      Shl rax, 8; Shr rax, 8;                                                   # Remove parameter count
      Je $end;                                                                  # Reached top of stack if rax is zero
      Inc $depth;                                                               # Depth of trace back
      Jmp $start;                                                               # Next level
     };

    Mov $stack, rbp;                                                            # Current stack frame
    &PrintNL($channel);                                                         # Print title
    &PrintString($channel, "Subroutine trace back, depth: ");
    PushR rax;
    Mov rax, $depth;
    &PrintRaxRightInDec(V(width=>2), $channel);
    PopR rax;
    &PrintNL($channel);

    AndBlock                                                                    # Each level
     {my ($fail, $end, $start) = @_;                                            # Fail block, end of fail block, start of test block
      Mov $stack, "[$stack]";                                                   # Up one level
      Mov rax, "[$stack-8]";
      Mov $count, rax;
      Shr $count, 56;                                                           # Top byte contains the parameter count
      Shl rax, 8; Shr rax, 8;                                                   # Remove parameter count
      Je $end;                                                                  # Reached top of stack
      Cmp $count, 0;                                                            # Check for parameters
      IfGt
      Then                                                                      # One or more parameters
       {Mov $index, 0;
        For
         {my ($start, $end, $next) = @_;
          Mov $parameter, $index;
          Add $parameter, 2;                                                    # Skip traceback
          Shl $parameter, 3;                                                    # Each parameter is a quad
          Neg $parameter;                                                       # Offset from stack
          Add $parameter, $stack;                                               # Position on stack
          Mov $parameter, "[$parameter]";                                       # Parameter reference to variable
          Push rax;
          Mov rax, "[$parameter]";                                              # Variable content
          &PrintRaxInHex($channel);
          Pop rax;
          &PrintSpace($channel, 4);
         } $index, $count;
        For                                                                     # Vertically align subroutine names
         {my ($start, $end, $next) = @_;
          &PrintSpace($channel, 23);
         } $index, $maxCount;
       };

      StringLength(&V(string => rax))->setReg(rdi);                             # Length of name of subroutine
      &PrintMemoryNL($channel);                                                 # Print name of subroutine
      Jmp $start;                                                               # Next level
     };
    &PrintNL($channel);
    PopR;
   } name => "SubroutineTraceBack_$channel", call=>1;
 }

sub PrintErrTraceBack($)                                                        # Print sub routine track back on stderr and then exit with a message.
 {my ($message) = @_;                                                           # Reason why we are printing the trace back and then stopping
  PrintErrStringNL $message;
  PrintTraceBack($stderr);
  Exit(1);
 }

sub PrintOutTraceBack($)                                                        # Print sub routine track back on stdout and then exit with a message.
 {my ($message) = @_;                                                           # Reason why we are printing the trace back and then stopping
  PrintOutStringNL $message;
  PrintTraceBack($stdout);
  Exit(1);
 }

sub OnSegv()                                                                    # Request a trace back followed by exit on a B<segv> signal.
 {my $s = Subroutine                                                            # Subroutine that will cause an error to occur to force a trace back to be printed
   {my $end = Label;
    Jmp $end;                                                                   # Jump over subroutine definition
    my $start = SetLabel;
    Enter 0, 0;                                                                 # Inline code of signal handler
    Mov r15, rbp;                                                               # Preserve the new stack frame
    Mov rbp, "[rbp]";                                                           # Restore our last stack frame
    PrintOutTraceBack 'Segmentation error';                                     # Print our trace back
    Mov rbp, r15;                                                               # Restore supplied stack frame
    Exit(0);                                                                    # Exit so we do not trampoline. Exit with code zero to show that the program is functioning correctly, else L<Assemble> will report an error.
    Leave;
    Ret;
    SetLabel $end;

    Mov r15, 0;                                                                 # Push sufficient zeros onto the stack to make a structure B<sigaction> as described in: https://www.man7.org/linux/man-pages/man2/sigaction.2.html
    Push r15 for 1..16;

    Mov r15, $start;                                                            # Actual signal handler
    Mov "[rsp]", r15;                                                           # Show as signal handler
    Mov "[rsp+0x10]", r15;                                                      # Add as trampoline as well - which is fine because we exit in the handler so this will never be called
    Mov r15, 0x4000000;                                                         # Mask to show we have a trampoline which is, apparently, required on x86
    Mov "[rsp+0x8]", r15;                                                       # Confirm we have a trampoline

    Mov rax, 13;                                                                # B<Sigaction> from B<kill -l>
    Mov rdi, 11;                                                                # Confirmed B<SIGSEGV = 11> from B<kill -l> and tracing with B<sde64>
    Mov rsi, rsp;                                                               # Structure B<sigaction> structure on stack
    Mov rdx, 0;                                                                 # Confirmed by trace
    Mov r10, 8;                                                                 # Found by tracing B<signal.c> with B<sde64> it is the width of the signal set and mask. B<signal.c> is reproduced below.
    Syscall;
    Add rsp, 128;
   } [], name=>"on segv";

  $s->call;
 }

sub cr(&@)                                                                      # Call a subroutine with a reordering of the registers.
 {my ($block, @registers) = @_;                                                 # Code to execute with reordered registers, registers to reorder
  ReorderSyscallRegisters   @registers;
  &$block;
  UnReorderSyscallRegisters @registers;
 }

# Second subroutine version

sub copyStructureMinusVariables($)                                              # Copy a non recursive structure ignoring variables
 {my ($s) = @_;                                                                 # Structure to copy

  my %s = %$s;
  for my $k(sort keys %s)                                                       # Look for sub structures
   {if (my $r = ref($s{$k}))
     {$s{$k} = __SUB__->($s{$k}) unless $r =~ m(\AVariable\Z);                  # We do not want to copy the variables yet because we are going to make them into references.
     }
   }

  bless \%s, ref $s;                                                            # Return a copy of the structure
 }

sub Subroutine2(&%)                                                             # Create a subroutine that can be called in assembler code.
 {my ($block, %options) = @_;                                                   # Block of code as a sub, options
  @_ >= 1 or confess "Subroutine requires at least a block";

  if (1)                                                                        # Validate options
   {my %o = %options;
    delete $o{$_} for qw(parameters structures name call);
    if (my @i = sort keys %o)
     {confess "Invalid parameters: ".join(', ',@i);
     }
   }

  my $run = sub                                                                 # We can call and run the sub immediately if it has just structure parameter (which can be single variables) and no other parameters
   {my ($s) = @_;                                                               # Parameters
    if ($s->options->{call})                                                    # Call and run the existing copy of the subroutine if it only requires structure arguments which can include just variables.
     {if (!$s->options->{parameters})                                           # Cannot run -as the subroutine requires parameters as well as structures.
       {$s->call(structures=>$s->options->{structures});                        # Call the subroutine
        return $s                                                               # Return the label of a pre-existing copy of the code. Make sure that the name is different for different subs as otherwise the unexpected results occur.
       }
      else                                                                      # Cannot call and run the subroutine as it requires parameters which we do not have yet.  However, we can use strucutures which can be just variables.
       {confess "Cannot run subroutine as it has parameters, uses structures instead";
       }
     }
    else                                                                        # Run not requested
     {return $s                                                                 # Return the label of a pre-existing copy of the code. Make sure that the name is different for different subs as otherwise the unexpected results occur.
     }
   };

  my $name = $options{name};                                                    # Subroutine name
  $name or confess "Name required for subroutine, use name=>";
  if ($name and my $s = $subroutines{$name})                                    # Return the label of a pre-existing copy of the code possibly after running the subroutine. Make sure that the subroutine name is different for different subs as otherwise the unexpected results occur.
   {return &$run($s);
   }

  my $parameters = $options{parameters};                                        # Optional parameters block
  if (1)                                                                        # Check for duplicate parameters
   {my %c;
    $c{$_}++ && confess "Duplicate parameter $_" for @$parameters;
   }

  SubroutineStartStack;                                                         # Open new stack layout with references to parameters
  my %parameters = map {$_ => R($_)} @$parameters;                              # Create a reference for each parameter.

  my %structureCopies;                                                          # Copies of the structures being passed that can be use inside the subroutine to access their variables in the stack frame of the subroutine
  if (my $structures = $options{structures})                                    # Structure provided in the parameter list
   {for my $name(sort keys %$structures)                                        # Each structure passed
     {$structureCopies{$name} = copyStructureMinusVariables($$structures{$name})# A new copy of the structure with its variables left in place
     }
   }

  my $end   =    Label; Jmp $end;                                               # End label.  Subroutines are only ever called - they are not executed in-line so we jump over the implementation of the subroutine.  This can cause several forward jumps in a row if a number of subroutines are defined together.
  my $start = SetLabel;                                                         # Start label

  my $s = $subroutines{$name} = genHash(__PACKAGE__."::Subroutine",             # Subroutine definition
    start              => $start,                                               # Start label for this subroutine which includes the enter instruction used to create a new stack frame
    end                => $end,                                                 # End label for this subroutine
    name               => $name,                                                # Name of the subroutine from which the entry label is located
    variables          => {%parameters},                                        # Map parameters to references at known positions in the sub
    structureCopies    => \%structureCopies,                                    # Copies of the structures passed to this subroutine with their variables replaced with references
    structureVariables => {},                                                   # Map structure variables to references at known positions in the sub
    options            => \%options,                                            # Options used by the author of the subroutine
    parameters         => $parameters,                                          # Parameters definitions supplied by the author of the subroutine which get mapped in to parameter variables.
    vars               => $VariableStack[-1],                                   # Number of variables in subroutine
    nameString         => Rs($name),                                            # Name of the sub as a string constant in read only storage
   );

  if (my $structures = $options{structures})                                    # Map structures
   {$s->mapStructureVariables(\%structureCopies);
   }

  my $E = @text;                                                                # Code entry that will contain the Enter instruction
  Enter 0, 0;                                                                   # The Enter instruction is 4 bytes long
  &$block({%parameters}, {%structureCopies}, $s);                               # Code with parameters and structures

  my $V = pop @VariableStack;                                                   # Number of variables in subroutine stack frame. As parameters and structures are mapped into variables in the subroutine stack frame these variables will be included in the count as well.

  Leave if $V;                                                                  # Remove frame if there was one
  Ret;                                                                          # Return from the sub
  SetLabel $end;                                                                # The end point of the sub where we return to normal code
  my $w = RegisterSize rax;
  $text[$E] = $V ? <<END : '';                                                  # Rewrite enter instruction now that we know how much stack space we need
  Enter $V*$w, 0
END

  &$run($s)                                                                     # Run subroutine if requested and return its definition definition
 }

sub Nasm::X86::Subroutine::mapStructureVariables($$$@)                          # Find the paths to variables in the copies of the structures passed as parameters and replace those variables with references so that in the subroutine we can refer to these variables regardless of where they are actually defined
 {my ($sub, $S, @P) = @_;                                                       # Sub definition, copies of source structures, path through copies of source structures to a variable that becomes a reference
  for my $s(sort keys %$S)                                                      # Source keys
   {my $e = $$S{$s};
    my $r = ref $e;
    next unless $r;

    if ($r =~ m(Variable)i)                                                     # Replace a variable with a reference in the copy of a structure passed in as a parameter
     {push @P, $s;
      my $R = $sub->structureVariables->{dump([@P])} = $$S{$s} = R($e->name);   # Path to a reference in the copy of a structure passed as as a parameter
      pop @P;
     }
    else                                                                        # A reference to something else - for the moment we assume that structures are built from non recursive hash references
     {push @P, $s;                                                              # Extend path
      $sub->mapStructureVariables($e, @P);                                      # Map structure variable
      pop @P;
     }
   }
 }

sub Nasm::X86::Subroutine::uploadStructureVariablesToNewStackFrame($$@)         # Create references to variables in parameter structures from variables in the stack frame of the subroutine.
 {my ($sub, $S, @P) = @_;                                                       # Sub definition, Source tree of input structures, path through sourtce structures tree

  for my $s(sort keys %$S)                                                      # Source keys
   {my $e = $$S{$s};
    my $r = ref $e;
    next unless $r;                                                             # Element in structure is not a variable or another hash describing a sub structure
    if ($r =~ m(Variable)i)                                                     # Variable located
     {push @P, $s;                                                              # Extend path
      my $p = dump([@P]);                                                       # Path as string
      my $R = $sub->structureVariables->{$p};                                   # Reference
      if (defined($R))
       {$sub->uploadToNewStackFrame($e, $R);                                    # Reference to structure variable from subroutine stack frame
       }
      else                                                                      # Unable to locate the corresponding reference
       {confess "No entry for $p in structure variables";
       }
      pop @P;
     }
    else                                                                        # A hash that is not a variable and is therefore assumed to be a non recursive substructure
     {push @P, $s;
      $sub->uploadStructureVariablesToNewStackFrame($e, @P);
      pop @P;
     }
   }
 }

sub Nasm::X86::Subroutine::uploadToNewStackFrame($$$)                           #P Map a variable in the current stack into a reference in the next stack frame being the one that will be used by this sub
 {my ($sub, $source, $target) = @_;                                             # Subroutine descriptor, source variable in the current stack frame, the reference in the new stack frame
  my $label = $source->label;                                                   # Source in current frame

  if ($source->reference)                                                       # Source is a reference
   {Mov r15, "[$label]";
   }
  else                                                                          # Source is not a reference
   {Lea r15, "[$label]";
   }

  my $q = $target->label;
     $q =~ s(rbp) (rsp);                                                        # Labels are based off the stack frame but we are building a new stack frame here so we must rename the stack pointer.
  my $w = RegisterSize r15;
  Mov "[$q-$w*2]", r15;                                                         # Step over subroutine name pointer and previous frame pointer.
 }

sub Nasm::X86::Subroutine::call($%)                                             #P Call a sub optionally passing it parameters.
 {my ($sub, %options) = @_;                                                     # Subroutine descriptor, options

  if (1)                                                                        # Validate options
   {my %o = %options;
    delete $o{$_} for qw(parameters structures);
    if (my @i = sort keys %o)
     {confess "Invalid parameters: ".join(', ',@i);
     }
   }

  my $parameters = $options{parameters};                                        # Parameters hash
  !$parameters or ref($parameters) =~ m(hash)i or confess
    "Parameters must be formatted as a hash";

  my $structures = $options{structures};                                        # Structures hash
  !$structures or ref($structures) =~ m(hash)i or confess
    "Structures must be formatted as a hash";

  if ($parameters)                                                              # Check for invalid or missing parameters
   {my %p = map {$_=>1} $sub->parameters->@*;
    my @m;
    for my $p(sort keys %$parameters)
     {push @m, "Invalid parameter: '$p'" unless $p{$p};
     }
    for my $p(sort keys %p)
     {push @m, "Missing parameter: '$p'" unless defined $$parameters{$p};
     }
    if (@m)
     {push @m, "Valid parameters : ";
           $m[-1] .= join ", ", map {"'$_'"} sort $sub->parameters->@*;
      confess join '', map {"$_\n"} @m;
     }
   }

  if ($structures)                                                              # Check for invalid or missing structures
   {my %s = $sub->options->{structures}->%*;
    my @m;
    for my $s(sort keys %$structures)
     {push @m, "Invalid structure: '$s'" unless $s{$s};
     }
    for my $s(sort keys %s)
     {push @m, "Missing structure: '$s'" unless $$structures{$s};
     }
    if (@m)
     {push @m, "Valid structures : ";
           $m[-1] .= join ", ", map {"'$_'"} sort keys %s;
      confess join '', map {"$_\n"} @m;
     }
   }

  my $w = RegisterSize r15;
  PushR r15;                                                                    # Use this register to transfer between the current frame and the next frame
  Mov "dword[rsp  -$w*3]", $sub->nameString;                                    # Point to subroutine name
  Mov "byte [rsp-1-$w*2]", $sub->vars;                                          # Number of parameters to enable trace back with parameters

  for my $name(sort keys $parameters->%*)                                       # Upload the variables referenced by the parameters to the new stack frame
   {my $s = $$parameters{$name};
    my $t = $sub->variables->{$name};
    $sub->uploadToNewStackFrame($s, $t);
   }

  if ($structures)                                                              # Upload the variables of each referenced structure to the new stack frame
   {$sub->uploadStructureVariablesToNewStackFrame($structures);
   }

  my $mode = 0;   # Assume call by address for the moment
  if ($mode)                                                                    # Dereference and call subroutine
   {Mov r15, $sub->start;
    Mov r15, "[r15]";
    Call r15;
   }
  else                                                                          # Call via label
   {Call $sub->start;
   }
  PopR;
 }

#D1 Comments                                                                    # Inserts comments into the generated assember code.

sub CommentWithTraceBack(@)                                                     # Insert a comment into the assembly code with a traceback showing how it was generated.
 {my (@comment) = @_;                                                           # Text of comment
  my $c = join "", @comment;
#  eval {confess};
#  my $p = dump($@);
  my $p = &subNameTraceBack =~ s(Nasm::X86::) ()gsr;
  push @text, <<END;
; $c  $p
END
 }

sub Comment(@)                                                                  # Insert a comment into the assembly code.
 {my (@comment) = @_;                                                           # Text of comment
  my $c = join "", @comment;
  my ($p, $f, $l) = caller;
  push @text, <<END;
; $c at $f line $l
END
 }

sub DComment(@)                                                                 # Insert a comment into the data segment.
 {my (@comment) = @_;                                                           # Text of comment
  my $c = join "", @comment;
  push @data, <<END;
; $c
END
 }

sub RComment(@)                                                                 # Insert a comment into the read only data segment.
 {my (@comment) = @_;                                                           # Text of comment
  my $c = join "", @comment;
  push @data, <<END;
; $c
END
 }

#D1 Print                                                                       # Print

sub PrintNL($)                                                                  # Print a new line to stdout  or stderr.
 {my ($channel) = @_;                                                           # Channel to write on
  @_ == 1 or confess "One parameter";

  Subroutine2
   {SaveFirstFour;
    Mov rax, 1;
    Mov rdi, $channel;                                                          # Write below stack
    my $w = RegisterSize rax;
    Lea  rsi, "[rsp-$w]";
    Mov "QWORD[rsi]", 10;
    Mov rdx, 1;
    Syscall;
    RestoreFirstFour()
   } name => qq(PrintNL_$channel), call=>1;
 }

sub PrintErrNL()                                                                # Print a new line to stderr.
 {@_ == 0 or confess;
  PrintNL($stderr);
 }

sub PrintOutNL()                                                                # Print a new line to stderr.
 {@_ == 0 or confess;
  PrintNL($stdout);
 }

sub PrintString($@)                                                             # Print a constant string to the specified channel.
 {my ($channel, @string) = @_;                                                  # Channel, Strings
  @_ >= 2 or confess "Two or more parameters";

  my $c = join ' ', @string;
  my $l = length($c);
  my $a = Rs($c);

  Subroutine2
   {SaveFirstFour;
    Mov rax, 1;
    Mov rdi, $channel;
    Lea rsi, "[$a]";
    Mov rdx, $l;
    Syscall;
    RestoreFirstFour();
   } name => "PrintString_${channel}_${c}", call=>1;
 }

sub PrintStringNL($@)                                                           # Print a constant string to the specified channel followed by a new line.
 {my ($channel, @string) = @_;                                                  # Channel, Strings
  PrintString($channel, @string);
  PrintNL    ($channel);
 }

sub PrintErrString(@)                                                           # Print a constant string to stderr.
 {my (@string) = @_;                                                            # String
  PrintString($stderr, @string);
 }

sub PrintErrStringNL(@)                                                         # Print a constant string to stderr followed by a new line.
 {my (@string) = @_;                                                            # String
  PrintErrString(@string);
  PrintErrNL;
 }

sub PrintOutString(@)                                                           # Print a constant string to stdout.
 {my (@string) = @_;                                                            # String
  PrintString($stdout, @string);
 }

sub PrintOutStringNL(@)                                                         # Print a constant string to stdout followed by a new line.
 {my (@string) = @_;                                                            # String
  PrintOutString(@string);
  PrintOutNL;
 }

sub PrintCString($$)                                                            # Print a zero terminated C style string addressed by a variable on the specified channel.
 {my ($channel, $string) = @_;                                                  # Channel, String

  PushR rax, rdi;
  my $length = StringLength $string;                                            # Length of string
  $string->setReg(rax);
  $length->setReg(rdi);
  &PrintOutMemory();                                                            # Print string
  PopR;
 }

sub PrintCStringNL($$)                                                          # Print a zero terminated C style string addressed by a variable on the specified channel followed by a new line.
 {my ($channel, $string) = @_;                                                  # Channel, Strings
  PrintCString($channel, $string);
  PrintNL     ($channel);
 }

sub PrintSpace($;$)                                                             # Print a constant number of spaces to the specified channel.
 {my ($channel, $spaces) = @_;                                                  # Channel, number of spaces if not one.
  PrintString($channel, ' ' x ($spaces // 1));
 }

sub PrintErrSpace(;$)                                                           # Print  a constant number of spaces to stderr.
 {my ($spaces) = @_;                                                            # Number of spaces if not one.
  PrintErrString(' ', $spaces);
 }

sub PrintOutSpace(;$)                                                           # Print a constant number of spaces to stdout.
 {my ($spaces) = @_;                                                            # Number of spaces if not one.
  PrintOutString(' ' x $spaces);
 }

sub hexTranslateTable                                                           #P Create/address a hex translate table and return its label.
 {my $h = '0123456789ABCDEF';
  my @t;
  for   my $i(split //, $h)
   {for my $j(split //, $h)
     {push @t, "$i$j";
     }
   }
   Rs @t                                                                        # Constant strings are only saved if they are unique, else a read only copy is returned.
 }

sub PrintRaxInHex($;$)                                                          # Write the content of register rax in hexadecimal in big endian notation to the specified channel.
 {my ($channel, $end) = @_;                                                     # Channel, optional end byte
  @_ == 1 or @_ == 2 or confess "One or two parameters";
  my $hexTranslateTable = hexTranslateTable;
  $end //= 7;                                                                   # Default end byte

  Subroutine2
   {SaveFirstFour rax;                                                          # Rax is a parameter
    Mov rdx, rax;                                                               # Content to be printed
    Mov rdi, 2;                                                                 # Length of a byte in hex

    for my $i((7-$end)..7)                                                      # Each byte
     {my $s = $bitsInByte*$i;
      Mov rax, rdx;
      Shl rax, $s;                                                              # Push selected byte high
      Shr rax, (RegisterSize(rax) - 1) * $bitsInByte;                           # Push select byte low
      Shl rax, 1;                                                               # Multiply by two because each entry in the translation table is two bytes long
      Lea rsi, "[$hexTranslateTable]";
      Add rax, rsi;
      PrintMemory($channel);                                                    # Print memory addressed by rax for length specified by rdi
      PrintString($channel, ' ') if $i % 2 and $i < 7;
     }
    RestoreFirstFour;
   } name => "PrintOutRaxInHexOn-$channel-$end", call=>1;
 }

sub PrintErrRaxInHex()                                                          # Write the content of register rax in hexadecimal in big endian notation to stderr.
 {@_ == 0 or confess;
  PrintRaxInHex($stderr);
 }

sub PrintErrRaxInHexNL()                                                        # Write the content of register rax in hexadecimal in big endian notation to stderr followed by a new line.
 {@_ == 0 or confess;
  PrintRaxInHex($stderr);
  PrintErrNL;
 }

sub PrintOutRaxInHex()                                                          # Write the content of register rax in hexadecimal in big endian notation to stout.
 {@_ == 0 or confess;
  PrintRaxInHex($stdout);
 }

sub PrintOutRaxInHexNL()                                                        # Write the content of register rax in hexadecimal in big endian notation to stdout followed by a new line.
 {@_ == 0 or confess;
  PrintRaxInHex($stdout);
  PrintOutNL;
 }

sub PrintRax_InHex($;$)                                                         # Write the content of register rax in hexadecimal in big endian notation to the specified channel replacing zero bytes with __.
 {my ($channel, $end) = @_;                                                     # Channel, optional end byte
  @_ == 1 or @_ == 2 or confess "One or two parameters";
  my $hexTranslateTable = hexTranslateTable;
  $end //= 7;                                                                   # Default end byte

  Subroutine2
   {SaveFirstFour rax;                                                          # Rax is a parameter
    Mov rdx, rax;                                                               # Content to be printed
    Mov rdi, 2;                                                                 # Length of a byte in hex

    for my $i((7-$end)..7)                                                      # Each byte
     {my $s = $bitsInByte*$i;
      Mov rax, rdx;
      Shl rax, $s;                                                              # Push selected byte high
      Shr rax, (RegisterSize(rax) - 1) * $bitsInByte;                           # Push select byte low
      Cmp rax, 0;
      IfEq                                                                      # Print __ for zero bytes
      Then
       {PrintString($channel, "__");
       },
      Else                                                                      # Print byte in hexadecimal otherwise
       {Shl rax, 1;                                                             # Multiply by two because each entry in the translation table is two bytes long
        Lea rsi, "[$hexTranslateTable]";
        Add rax, rsi;
        PrintMemory($channel);                                                  # Print memory addressed by rax for length specified by rdi
       };
      PrintString($channel, ' ') if $i % 2 and $i < 7;
     }
    RestoreFirstFour;
   } name => "PrintOutRax_InHexOn-$channel-$end", call=>1;
 }

sub PrintErrRax_InHex()                                                         # Write the content of register rax in hexadecimal in big endian notation to stderr.
 {@_ == 0 or confess;
  PrintRax_InHex($stderr);
 }

sub PrintErrRax_InHexNL()                                                       # Write the content of register rax in hexadecimal in big endian notation to stderr followed by a new line.
 {@_ == 0 or confess;
  PrintRax_InHex($stderr);
  PrintErrNL;
 }

sub PrintOutRax_InHex()                                                         # Write the content of register rax in hexadecimal in big endian notation to stout.
 {@_ == 0 or confess;
  PrintRax_InHex($stdout);
 }

sub PrintOutRax_InHexNL()                                                       # Write the content of register rax in hexadecimal in big endian notation to stdout followed by a new line.
 {@_ == 0 or confess;
  PrintRax_InHex($stdout);
  PrintOutNL;
 }

sub PrintOutRaxInReverseInHex                                                   # Write the content of register rax to stderr in hexadecimal in little endian notation.
 {@_ == 0 or confess;
  Comment "Print Rax In Reverse In Hex";
  Push rax;
  Bswap rax;
  PrintOutRaxInHex;
  Pop rax;
 }

sub PrintOneRegisterInHex($$)                                                   # Print the named register as a hex string.
 {my ($channel, $r) = @_;                                                       # Channel to print on, register to print
  @_ == 2 or confess "Two parameters";

  Subroutine2
   {if   ($r =~ m(\Ar))                                                         # General purpose register
     {if ($r =~ m(\Arax\Z))
       {PrintRaxInHex($channel);
       }
      else
       {PushR rax;
        Mov rax, $r;
        PrintRaxInHex($channel);
        PopR rax;
       }
     }
    else
     {my sub printReg(@)                                                        # Print the contents of a register
       {my (@regs) = @_;                                                        # Size in bytes, work registers
        my $s = RegisterSize $r;                                                # Size of the register
        PushRR @regs;                                                           # Save work registers
        PushRR $r;                                                              # Place register contents on stack - might be a x|y|z - without tracking
        PopRR  @regs;                                                           # Load work registers without tracking
        for my $i(keys @regs)                                                   # Print work registers to print input register
         {my $R = $regs[$i];
          if ($R !~ m(\Arax))
           {PrintString($channel, "  ");                                        # Separate blocks of bytes with a space
            Mov rax, $R;
           }
          PrintRaxInHex($channel);                                              # Print work register
          PrintString($channel, " ") unless $i == $#regs;
         }
        PopRR @regs;                                                            # Balance the single push of what might be a large register
       };
      if    ($r =~ m(\A[kr])) {printReg qw(rax)}                                # General purpose 64 bit register requested
      elsif ($r =~ m(\Ax))    {printReg qw(rax rbx)}                            # Xmm*
      elsif ($r =~ m(\Ay))    {printReg qw(rax rbx rcx rdx)}                    # Ymm*
      elsif ($r =~ m(\Az))    {printReg qw(rax rbx rcx rdx r8 r9 r10 r11)}      # Zmm*
     }
   } name => "PrintOneRegister${r}InHexOn$channel", call=>1;                    # One routine per register printed
 }

sub PrintErrOneRegisterInHex($)                                                 # Print the named register as a hex string on stderr.
 {my ($r) = @_;                                                                 # Register to print
  @_ == 1 or confess "One parameter";
  PrintOneRegisterInHex($stderr, $r)
 }

sub PrintErrOneRegisterInHexNL($)                                               # Print the named register as a hex string on stderr followed by new line.
 {my ($r) = @_;                                                                 # Register to print
  @_ == 1 or confess "One parameter";
  PrintOneRegisterInHex($stderr, $r);
  PrintErrNL;
 }

sub PrintOutOneRegisterInHex($)                                                 # Print the named register as a hex string on stdout.
 {my ($r) = @_;                                                                 # Register to print
  @_ == 1 or confess "One parameter";
  PrintOneRegisterInHex($stdout, $r)
 }

sub PrintOutOneRegisterInHexNL($)                                               # Print the named register as a hex string on stdout followed by new line.
 {my ($r) = @_;                                                                 # Register to print
  @_ == 1 or confess "One parameter";
  PrintOneRegisterInHex($stdout, $r);
  PrintOutNL;
 }

sub PrintRegisterInHex($@)                                                      # Print the named registers as hex strings.
 {my ($channel, @r) = @_;                                                       # Channel to print on, names of the registers to print
  @_ >= 2 or confess "Two or more parameters required";

  for my $r(map{registerNameFromNumber $_} @r)                                  # Each register to print
   {PrintString($channel,  sprintf("%6s: ", $r));                               # Register name
    PrintOneRegisterInHex $channel, $r;
    PrintNL($channel);
   }
 }

sub PrintErrRegisterInHex(@)                                                    # Print the named registers as hex strings on stderr.
 {my (@r) = @_;                                                                 # Names of the registers to print
  PrintRegisterInHex $stderr, @r;
 }

sub PrintOutRegisterInHex(@)                                                    # Print the named registers as hex strings on stdout.
 {my (@r) = @_;                                                                 # Names of the registers to print
  PrintRegisterInHex $stdout, @r;
 }

sub PrintOutRipInHex                                                            #P Print the instruction pointer in hex.
 {@_ == 0 or confess;
  my @regs = qw(rax);
  Subroutine2
   {PushR @regs;
    my $l = Label;
    push @text, <<END;
$l:
END
    Lea rax, "[$l]";                                                            # Current instruction pointer
    PrintOutString "rip: ";
    PrintOutRaxInHex;
    PrintOutNL;
    PopR @regs;
   } name=> "PrintOutRipInHex", call => 1;
 }

sub PrintOutRflagsInHex                                                         #P Print the flags register in hex.
 {@_ == 0 or confess;
  my @regs = qw(rax);

  Subroutine2
   {PushR @regs;
    Pushfq;
    Pop rax;
    PrintOutString "rfl: ";
    PrintOutRaxInHex;
    PrintOutNL;
    PopR @regs;
   } name=> "PrintOutRflagsInHex", call => 1;
 }

sub PrintOutRegistersInHex                                                      # Print the general purpose registers in hex.
 {@_ == 0 or confess "No parameters required";

  Subroutine2
   {PrintOutRipInHex;
    PrintOutRflagsInHex;

    my @regs = qw(rax);
    PushR @regs;

    my $w = registers_64();
    for my $r(sort @$w)
     {next if $r =~ m(rip|rflags);
      if ($r eq rax)
       {Pop rax;
        Push rax
       }
      PrintOutString reverse(pad(reverse($r), 3)).": ";
      Mov rax, $r;
      PrintOutRaxInHex;
      PrintOutNL;
     }
    PopR @regs;
   } name=> "PrintOutRegistersInHex", call => 1;
 }

sub PrintErrZF                                                                  # Print the zero flag without disturbing it on stderr.
 {@_ == 0 or confess;

  Pushfq;
  IfNz Then {PrintErrStringNL "ZF=0"}, Else {PrintErrStringNL "ZF=1"};
  Popfq;
 }

sub PrintOutZF                                                                  # Print the zero flag without disturbing it on stdout.
 {@_ == 0 or confess "No parameters";

  Pushfq;
  IfNz Then {PrintOutStringNL "ZF=0"}, Else {PrintOutStringNL "ZF=1"};
  Popfq;
 }

#D2 Print hexadecimal                                                           # Print numbers in hexadecimal right justified in a field

sub PrintRightInHex($$$)                                                        # Print out a number in hex right justified in a field of specified width on the specified channel
 {my ($channel, $number, $width) = @_;                                          # Channel, number as a variable, width of output field as a variable
  @_ == 3 or confess "Three parameters required";

  $channel =~ m(\A(1|2)\Z) or confess "Invalid channel should be stderr or stdout";
  ref($number) =~ m(variable)i or confess "number must be a variable";
  ref($width)  =~ m(variable)i or confess "width must be a variable";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    PushR rax, rdi, r14, r15, xmm0;
    ClearRegisters xmm0;
    $$p{number}->setReg(r14);

    K(loop => 16)->for(sub
     {Mov r15, r14;                                                             # Load xmm0 with hexadecimal digits
      And r15, 0xf;
      Cmp r15, 9;
      IfGt
      Then
       {Add r15, ord('A') - 10;
       },
      Else
       {Add r15, ord('0');
       };
      Pslldq xmm0, 1;
      Pinsrb xmm0, r15b, 0;
      Shr r14, 4;
     });

    Block                                                                       # Translate leading zeros to spaces
     {my ($end) = @_;
      for my $i(0..14)
       {Pextrb r15, xmm0, $i;
        Cmp r15b, ord('0');
        Jne $end;
        Mov r15, ord(' ');
        Pinsrb xmm0, r15b, $i;
       }
     };

    PushR xmm0;                                                                 # Print xmm0 within the width of the field
    Mov rax, rsp;
    $$p{width}->setReg(rdi);
    Add rax, 16;
    Sub rax, rdi;
    PrintOutMemory;
    PopR;
    PopR;
   } name => "PrintRightInHex_${channel}",
     parameters=>[qw(width number)];

  $s->call(parameters => {number => $number, width=>$width});
 }

sub PrintErrRightInHex($$)                                                      # Write the specified variable in hexadecimal right justified in a field of specified width on stderr.
 {my ($number, $width) = @_;                                                    # Number as a variable, width of output field as a variable
  @_ == 2 or confess "Two parameters required";
  PrintRightInHex($stderr, $number, $width);
 }

sub PrintErrRightInHexNL($$)                                                    # Write the specified variable in hexadecimal right justified in a field of specified width on stderr followed by a new line.
 {my ($number, $width) = @_;                                                    # Number as a variable, width of output field as a variable
  @_ == 2 or confess "Two parameters required";
  PrintRightInHex($stderr, $number, $width);
  PrintErrNL;
 }

sub PrintOutRightInHex($$)                                                      # Write the specified variable in hexadecimal right justified in a field of specified width on stdout.
 {my ($number, $width) = @_;                                                    # Number as a variable, width of output field as a variable
  @_ == 2 or confess "Two parameters required";
  PrintRightInHex($stdout, $number, $width);
 }

sub PrintOutRightInHexNL($$)                                                    # Write the specified variable in hexadecimal right justified in a field of specified width on stdout followed by a new line.
 {my ($number, $width) = @_;                                                    # Number as a variable, width of output field as a variable
  @_ == 2 or confess "Two parameters required";
  PrintRightInHex($stdout, $number, $width);
  PrintOutNL;
 }

#D2 Print binary                                                                # Print numbers in binary right justified in a field

sub PrintRightInBin($$$)                                                        # Print out a number in hex right justified in a field of specified width on the specified channel
 {my ($channel, $number, $width) = @_;                                          # Channel, number as a variable, width of output field as a variable
  @_ == 3 or confess "Three parameters required";

  $channel =~ m(\A(1|2)\Z) or confess "Invalid channel should be stderr or stdout";
  ref($number) =~ m(variable)i or confess "number must be a variable";
  ref($width)  =~ m(variable)i or confess "width must be a variable";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    PushR rax, rdi, rsi, r14, r15;
    $$p{number}->setReg(rax);
    Mov rsi, rsp;
    my $bir = RegisterSize(rax) * $bitsInByte;
    Mov r14, rsi;
    Sub rsp, $bir;                                                              # Allocate space on the stack for the maximum length bit string written out as characters

    K(loop => $bir)->for(sub                                                    # Load bits onto stack as characters
     {Dec r14;
      Mov r15, rax;
      And r15, 1;
      Cmp r15, 0;
      IfNe
      Then
       {Mov "byte[r14]", ord('1');
       },
      Else
       {Mov "byte[r14]", ord('0');
       };
      Shr rax, 1;
     });

    K(loop => $bir)->for(sub                                                    # Replace leading zeros with spaces
     {my ($index, $start, $next, $end) = @_;
      Cmp "byte[r14]",ord('0');
      IfEq
      Then
       {Mov "byte[r14]", ord(' ');
       },
      Else
       {Jmp $end;
       };
      Inc r14;
     });

    Mov rax, rsp;                                                               # Write stack in a field of specified width
    $$p{width}->setReg(rdi);
    Add rax, $bir;
    Sub rax, rdi;
    PrintMemory($channel);
    Mov rsp, rsi;                                                               # Restore stack
    PopR;
   } name => "PrintRightInBin_${channel}",
     parameters=>[qw(width number)];

  $s->call(parameters => {number => $number, width=>$width});
 }

sub PrintErrRightInBin($$)                                                      # Write the specified variable in binary right justified in a field of specified width on stderr.
 {my ($number, $width) = @_;                                                    # Number as a variable, width of output field as a variable
  @_ == 2 or confess "Two parameters required";
  PrintRightInBin($stderr, $number, $width);
 }

sub PrintErrRightInBinNL($$)                                                    # Write the specified variable in binary right justified in a field of specified width on stderr followed by a new line.
 {my ($number, $width) = @_;                                                    # Number as a variable, width of output field as a variable
  @_ == 2 or confess "Two parameters required";
  PrintRightInBin($stderr, $number, $width);
  PrintErrNL;
 }

sub PrintOutRightInBin($$)                                                      # Write the specified variable in binary right justified in a field of specified width on stdout.
 {my ($number, $width) = @_;                                                    # Number as a variable, width of output field as a variable
  @_ == 2 or confess "Two parameters required";
  PrintRightInBin($stdout, $number, $width);
 }

sub PrintOutRightInBinNL($$)                                                    # Write the specified variable in binary right justified in a field of specified width on stdout followed by a new line.
 {my ($number, $width) = @_;                                                    # Number as a variable, width of output field as a variable
  @_ == 2 or confess "Two parameters required";
  PrintRightInBin($stdout, $number, $width);
  PrintOutNL;
 }

#D2 Print UTF strings                                                           # Print utf-8 and iutf-32 strings

sub PrintUtf8Char($)                                                            # Print the utf-8 character addressed by rax to the specified channel. The character must be in little endian form.
 {my ($channel) = @_;                                                           # Channel

  Subroutine2
   {my ($p, $s) = @_;                                                           # Parameters
    PushR rax, rdi, r15;
    Mov r15d, "[rax]";                                                          # Load character - this assumes that each utf8 character sits by itself, right adjusted, in a block of 4 bytes
    Lzcnt r15, r15;                                                             # Find width of utf-8 character
    Shr r15, 3;                                                                 # From bits to bytes
    Mov rdi, RegisterSize r15;                                                  # Maximum number of bytes
    Sub rdi, r15;                                                               # Width in bytes
    PrintMemory($channel);                                                      # Print letter from stack
    PopR;
   } name => qq(Nasm::X86::printUtf8Char_$channel), call=>1;
 }

sub PrintErrUtf8Char()                                                          # Print the utf-8 character addressed by rax to stderr.
 {PrintUtf8Char($stdout);
 }

sub PrintOutUtf8Char()                                                          # Print the utf-8 character addressed by rax to stdout.
 {PrintUtf8Char($stdout);
 }

sub PrintUtf32($$$)                                                             #P Print the specified number of utf32 characters at the specified address to the specified channel.
 {my ($channel, $size, $address) = @_;                                          # Channel, variable: number of characters to print, variable: address of memory
  @_ == 3 or confess "Three parameters";

  Subroutine2
   {my ($p, $s) = @_;                                                           # Parameters, subroutine description

    PushR (rax, r14, r15);
    my $count = $$p{size} / 2; my $count1 = $count - 1;
    $count->for(sub
     {my ($index, $start, $next, $end) = @_;
      my $a = $$p{address} + $index * 8;
      $a->setReg(rax);
      Mov rax, "[rax]";
      Mov r14, rax;
      Mov r15, rax;
      Shl r15, 32;
      Shr r14, 32;
      Or r14,r15;
      Mov rax, r14;
      PrintOutRaxInHex;
      If $index % 8 == 7,
      Then
       {PrintOutNL;
       },
      Else
       {If $index != $count1, sub
         {PrintOutString "  ";
         };
       };
     });
    PrintOutNL;
    PopR;
   } structures=>{size => $size, address => $address}, call=>1,
     name => qq(Nasm::X86::printUtf32_$channel);
 }

sub PrintErrUtf32($$)                                                           # Print the utf-8 character addressed by rax to stderr.
 {my ($size, $address) = @_;                                                    # Variable: number of characters to print, variable: address of memory
  @_ == 2 or confess "Two parameters";
  PrintUtf32($stderr, $size, $address);
 }

sub PrintOutUtf32($$)                                                           # Print the utf-8 character addressed by rax to stdout.
 {my ($size, $address) = @_;                                                    # Variable: number of characters to print, variable: address of memory
  @_ == 2 or confess "Two parameters";
  PrintUtf32($stderr, $size, $address);
 }

#D2 Print in decimal                                                            # Print numbers in decimal right justified in fields of specified width.

sub PrintRaxInDec($)                                                            # Print rax in decimal on the specified channel.
 {my ($channel) = @_;                                                           # Channel to write on
  @_ == 1 or confess "One parameter";

  Subroutine2
   {PushR rax, rdi, rdx, r9, r10;
    Mov r9, 0;                                                                  # Number of decimal digits
    Mov r10, 10;                                                                # Base of number system
    my $convert = SetLabel;
      Mov rdx, 0;                                                               # Rdx must be clear to receive remainder
      Idiv r10;                                                                 # Remainder after integer division by 10
      Add rdx, 48;                                                              # Convert remainder to ascii
      Push rdx;                                                                 # Save remainder
      Inc r9;                                                                   # Number of digits
      Cmp rax, 0;
    Jnz $convert;

    Mov rdi, 1;                                                                 # Length of each write

    my $print = SetLabel;                                                       # Print digits
      Mov rax, rsp;
      PrintMemory($channel);
      Dec r9;                                                                   # Number of digits
      Pop rax;                                                                  # Remove digit from stack
    Jnz $print;

    PopR;
   } name => "PrintRaxInDec_$channel", call=>1;
 }

sub PrintOutRaxInDec                                                            # Print rax in decimal on stdout.
 {PrintRaxInDec($stdout);
 }

sub PrintOutRaxInDecNL                                                          # Print rax in decimal on stdout followed by a new line.
 {PrintOutRaxInDec;
  PrintOutNL;
 }

sub PrintErrRaxInDec                                                            # Print rax in decimal on stderr.
 {PrintRaxInDec($stderr);
 }

sub PrintErrRaxInDecNL                                                          # Print rax in decimal on stderr followed by a new line.
 {PrintErrRaxInDec;
  PrintErrNL;
 }

sub PrintRaxRightInDec($$)                                                      # Print rax in decimal right justified in a field of the specified width on the specified channel.
 {my ($width, $channel) = @_;                                                   # Width, channel

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    PushR rax, rdi, rdx, r9, r10;
    Mov r9, 0;                                                                  # Number of decimal digits
    Mov r10, 10;                                                                # Base of number system
    my $convert = SetLabel;
      Mov rdx, 0;                                                               # Rdx must be clear to receive remainder
      Idiv r10;                                                                 # Remainder after integer division by 10
      Add rdx, 48;                                                              # Convert remainder to ascii
      Push rdx;                                                                 # Save remainder
      Inc r9;                                                                   # Number of digits
      Cmp rax, 0;
    Jnz $convert;

    Mov rdi, 1;                                                                 # Length of each write
    $$p{width}->setReg(r10);                                                    # Pad to this width if necessary
    Cmp r9, r10;
    IfLt
    Then                                                                        # Padding required
     {(V(width => r10) - V(actual => r9))->spaces($channel);
     };

    my $print = SetLabel;                                                       # Print digits
      Mov rax, rsp;
      PrintMemory($channel);
      Dec r9;                                                                   # Number of digits
      Pop rax;                                                                  # Remove digit from stack
    Jnz $print;

    PopR;
   } parameters=>[qw(width)], name => "PrintRaxRightInDec_${channel}";

  $s->call(parameters=>{width => $width});
 }

sub PrintErrRaxRightInDec($)                                                    # Print rax in decimal right justified in a field of the specified width on stderr.
 {my ($width) = @_;                                                             # Width
  PrintRaxRightInDec($width, $stderr);
 }

sub PrintErrRaxRightInDecNL($)                                                  # Print rax in decimal right justified in a field of the specified width on stderr followed by a new line.
 {my ($width) = @_;                                                             # Width
  PrintRaxRightInDec($width, $stderr);
  PrintErrNL;
 }

sub PrintOutRaxRightInDec($)                                                    # Print rax in decimal right justified in a field of the specified width on stdout.
 {my ($width) = @_;                                                             # Width
  PrintRaxRightInDec($width, $stdout);
 }

sub PrintOutRaxRightInDecNL($)                                                  # Print rax in decimal right justified in a field of the specified width on stdout followed by a new line.
 {my ($width) = @_;                                                             # Width
  PrintRaxRightInDec($width, $stdout);
  PrintOutNL;
 }

sub PrintRaxAsText($)                                                           # Print the string in rax on the specified channel.
 {my ($channel) = @_;                                                           # Channel to write on
  @_ == 1 or confess "One parameter";

  my $w = RegisterSize rax;
  PushR rdi, rdx, rax;
  Lzcnt rdi, rax;
  Shr rdi, 3;
  Mov rdx, rdi;
  Mov rdi, 8;
  Sub rdi, rdx;

  Mov rax, rsp;
  PrintMemory($channel);
  PopR;
 }

sub PrintOutRaxAsText                                                           # Print rax in decimal on stdout.
 {PrintRaxAsText($stdout);
 }

sub PrintOutRaxAsTextNL                                                         # Print rax in decimal on stdout followed by a new line.
 {PrintRaxAsText($stdout);
  PrintOutNL;
 }

sub PrintErrRaxAsText                                                           # Print rax in decimal on stderr.
 {PrintRaxAsText($stderr);
 }

sub PrintErrRaxAsTextNL                                                         # Print rax in decimal on stderr followed by a new line.
 {PrintRaxAsText($stderr);
  PrintOutNL;
 }

sub PrintRaxAsChar($)                                                           # Print the character in rax on the specified channel.
 {my ($channel) = @_;                                                           # Channel to write on
  @_ == 1 or confess "One parameter";

  PushR rdi, rax;
  Mov rax, rsp;
  Mov rdi, 1;
  PrintMemory($channel);
  PopR;
 }

sub PrintOutRaxAsChar                                                           # Print the character in on stdout.
 {PrintRaxAsChar($stdout);
 }

sub PrintOutRaxAsCharNL                                                         # Print the character in on stdout followed by a new line.
 {PrintRaxAsChar($stdout);
  PrintOutNL;
 }

sub PrintErrRaxAsChar                                                           # Print the character in on stderr.
 {PrintRaxAsChar($stderr);
 }

sub PrintErrRaxAsCharNL                                                         # Print the character in on stderr followed by a new line.
 {PrintRaxAsChar($stderr);
  PrintOutNL;
 }

#D1 Variables                                                                   # Variable definitions and operations

#D2 Definitions                                                                 # Variable definitions

sub Variable($;$%)                                                              # Create a new variable with the specified name initialized via an optional expression.
 {my ($name, $expr, %options) = @_;                                             # Name of variable, optional expression initializing variable, options
  my $size   = 3;                                                               # Size  of variable in bytes as a power of 2
  my $width  = 2**$size;                                                        # Size of variable in bytes
  my $const  = $options{constant} // 0;                                         # Constant variable 0- implicitly global
  my $global = $options{global}   // 0;                                         # Global variable

  my $label;
  if ($const)                                                                   # Constant variable
   {defined($expr) or confess "Value required for constant";
    $expr =~ m(r) and confess
     "Cannot use register expression $expr to initialize a constant";
    RComment qq(Constant name: "$name", value $expr);
    $label = Rq($expr);
   }
  elsif ($global)                                                               # Global variables are held in the data segment not on the stack
   {$label = Dq($expr // 0);
   }
  else                                                                          # Local variable: Position on stack of variable
   {my $stack = ++$VariableStack[-1];
    $label = "rbp-8*($stack)";

    if (defined $expr)                                                          # Initialize variable if an initializer was supplied
     {if ($Registers{$expr} and $expr =~ m(\Ar))                                # Expression is ready to go
       {Mov "[$label]", $expr;
       }
      else                                                                      # Transfer expression
       {PushR r15;
        Mov r15, $expr;
        Mov "[$label]", r15;
        PopR r15;
       }
     }
   }

  genHash(__PACKAGE__."::Variable",                                             # Variable definition
    constant  => $const,                                                        # Constant if true
    global    => $global,                                                       # Global if true
    expr      => $expr,                                                         # Expression that initializes the variable
    label     => $label,                                                        # Address in memory
    name      => $name,                                                         # Name of the variable
    level     => scalar @VariableStack,                                         # Lexical level
    reference => undef,                                                         # Reference to another variable
    width     => RegisterSize(rax),                                             # Size of the variable in bytes
   );
 }

#sub G(*;$%)                                                                     # Define a global variable. Global variables with the same name are not necessarily the same variable.  Two global variables are identical iff they have have the same label field.
# {my ($name, $expr, %options) = @_;                                             # Name of variable, initializing expression, options
#  &Variable($name, $expr, global => 1, %options);
# }

sub K(*;$%)                                                                     # Define a constant variable.
 {my ($name, $expr, %options) = @_;                                             # Name of variable, initializing expression, options
  &Variable(@_, constant => 1, %options)
 }

sub R(*)                                                                        # Define a reference variable.
 {my ($name) = @_;                                                              # Name of variable
  my $r = &Variable($name);                                                     # The referring variable is 64 bits wide
  $r->reference = 1;                                                            # Mark variable as a reference
  $r                                                                            # Size of the referenced variable
 }

sub V(*;$%)                                                                     # Define a variable.
 {my ($name, $expr, %options) = @_;                                             # Name of variable, initializing expression, options
  &Variable(@_)
 }

#D2 Print variables                                                             # Print the values of variables or the memory addressed by them

sub Nasm::X86::Variable::dump($$$;$$)                                           #P Dump the value of a variable to the specified channel adding an optional title and new line if requested.
 {my ($left, $channel, $newLine, $title1, $title2) = @_;                        # Left variable, channel, new line required, optional leading title, optional trailing title
  @_ >= 3 or confess;
  PushR my @regs = (rax, rdi);
  my $label = $left->label;                                                     # Address in memory
  Mov rax, "[$label]";
  Mov rax, "[rax]" if $left->reference;
  confess  dump($channel) unless $channel =~ m(\A1|2\Z);
  PrintString  ($channel, $title1//$left->name.": ") unless defined($title1) && $title1 eq '';
  PrintRaxInHex($channel);
  PrintString  ($channel, $title2) if defined $title2;
  PrintNL      ($channel) if $newLine;
  PopR @regs;
 }

sub Nasm::X86::Variable::err($;$$)                                              # Dump the value of a variable on stderr.
 {my ($left, $title1, $title2) = @_;                                            # Left variable, optional leading title, optional trailing title
  $left->dump($stderr, 0, $title1, $title2);
 }

sub Nasm::X86::Variable::out($;$$)                                              # Dump the value of a variable on stdout.
 {my ($left, $title1, $title2) = @_;                                            # Left variable, optional leading title, optional trailing title
  $left->dump($stdout, 0, $title1, $title2);
 }

sub Nasm::X86::Variable::errNL($;$$)                                            # Dump the value of a variable on stderr and append a new line.
 {my ($left, $title1, $title2) = @_;                                            # Left variable, optional leading title, optional trailing title
  $left->dump($stderr, 1, $title1, $title2);
 }

sub Nasm::X86::Variable::d($;$$)                                                # Dump the value of a variable on stderr and append a new line.
 {my ($left, $title1, $title2) = @_;                                            # Left variable, optional leading title, optional trailing title
  $left->dump($stderr, 1, $title1, $title2);
 }

sub Nasm::X86::Variable::outNL($;$$)                                            # Dump the value of a variable on stdout and append a new line.
 {my ($left, $title1, $title2) = @_;                                            # Left variable, optional leading title, optional trailing title
  $left->dump($stdout, 1, $title1, $title2);
 }

sub Nasm::X86::Variable::debug($)                                               # Dump the value of a variable on stdout with an indication of where the dump came from.
 {my ($left) = @_;                                                              # Left variable
  PushR my @regs = (rax, rdi);
  Mov rax, $left->label;                                                        # Address in memory
  Mov rax, "[rax]";
  &PrintErrString(pad($left->name, 32).": ");
  &PrintErrRaxInHex();
  my ($p, $f, $l) = caller(0);                                                  # Position of caller in file
  &PrintErrString("               at $f line $l");
  &PrintErrNL();
  PopR @regs;
 }

#D3 Decimal representation                                                      # Print out a variable as a decimal number

sub Nasm::X86::Variable::errInDec($;$$)                                         # Dump the value of a variable on stderr in decimal.
 {my ($number, $title1, $title2) = @_;                                          # Number as variable, optional leading title, optional trailing title
  PrintErrString($title1 // $number->name.": ");
  PushR rax;
  $number->setReg(rax);
  PrintRaxInDec($stderr);
  PopR;
  PrintErrString($title2) if $title2;
 }

sub Nasm::X86::Variable::errInDecNL($;$$)                                       # Dump the value of a variable on stderr in decimal followed by a new line.
 {my ($number, $title1, $title2) = @_;                                          # Number as variable, optional leading title, optional trailing title
  $number->errInDec($title1, $title2);
  PrintErrNL;
 }

sub Nasm::X86::Variable::outInDec($;$$)                                         # Dump the value of a variable on stdout in decimal.
 {my ($number, $title1, $title2) = @_;                                          # Number as variable, optional leading title, optional trailing title
  PrintOutString($title1 // $number->name.": ");
  PushR rax;
  $number->setReg(rax);
  PrintRaxInDec($stdout);
  PopR;
  PrintOutString($title2) if $title2;
 }

sub Nasm::X86::Variable::outInDecNL($;$$)                                       # Dump the value of a variable on stdout in decimal followed by a new line.
 {my ($number, $title1, $title2) = @_;                                          # Number as variable, optional leading title, optional trailing title
  $number->outInDec($title1, $title2);
  PrintOutNL;
 }

#D3 Decimal representation right justified                                      # Print out a variable as a decimal number right adjusted in a field of specified width

sub Nasm::X86::Variable::rightInDec($$$)                                        # Dump the value of a variable on the specified channel as a decimal  number right adjusted in a field of specified width.
 {my ($number, $channel, $width) = @_;                                           # Number as variable, channel, width
  PushR rax;
  $number->setReg(rax);
  PrintRaxRightInDec($width, $channel);
  PopR;
 }

sub Nasm::X86::Variable::errRightInDec($$)                                      # Dump the value of a variable on stderr as a decimal number right adjusted in a field of specified width.
 {my ($number, $width) = @_;                                                    # Number, width
  $number->rightInDec($stdout, $width);
 }

sub Nasm::X86::Variable::errRightInDecNL($$)                                    # Dump the value of a variable on stderr as a decimal number right adjusted in a field of specified width followed by a new line.
 {my ($number, $width) = @_;                                                    # Number, width
  $number->rightInDec($stdout, $width);
  PrintErrNL;
 }

sub Nasm::X86::Variable::outRightInDec($$)                                      # Dump the value of a variable on stdout as a decimal number right adjusted in a field of specified width.
 {my ($number, $width) = @_;                                                    # Number, width
  $number->rightInDec($stdout, $width);
 }

sub Nasm::X86::Variable::outRightInDecNL($$)                                    # Dump the value of a variable on stdout as a decimal number right adjusted in a field of specified width followed by a new line.
 {my ($number, $width) = @_;                                                    # Number, width
  $number->rightInDec($stdout, $width);
  PrintOutNL;
 }

#D2 Hexadecimal representation, right justified                                 # Print number variables in hexadecimal right justified in fields of specified width.

sub Nasm::X86::Variable::rightInHex($$$)                                        # Write the specified variable number in hexadecimal right justified in a field of specified width to the specified channel.
 {my ($number, $channel, $width) = @_;                                          # Number to print as a variable, channel to print on, width of output field
  @_ == 3 or confess "Three parameters";
  PrintRightInHex($channel, $number, $width);
 }

sub Nasm::X86::Variable::errRightInHex($$)                                      # Write the specified variable number in hexadecimal right justified in a field of specified width to stderr
 {my ($number, $width) = @_;                                                    # Number to print as a variable, width of output field
  @_ == 2 or confess "Two parameters";
  PrintRightInHex($stderr, $number, $width);
 }

sub Nasm::X86::Variable::errRightInHexNL($$)                                    # Write the specified variable number in hexadecimal right justified in a field of specified width to stderr followed by a new line
 {my ($number, $width) = @_;                                                    # Number to print as a variable, width of output field
  @_ == 2 or confess "Two parameters";
  PrintRightInHex($stderr, $number, $width);
  PrintErrNL;
 }

sub Nasm::X86::Variable::outRightInHex($$)                                      # Write the specified variable number in hexadecimal right justified in a field of specified width to stdout
 {my ($number, $width) = @_;                                                    # Number to print as a variable, width of output field
  @_ == 2 or confess "Two parameters";
  PrintRightInHex($stdout, $number, $width);
 }

sub Nasm::X86::Variable::outRightInHexNL($$)                                    # Write the specified variable number in hexadecimal right justified in a field of specified width to stdout followed by a new line
 {my ($number, $width) = @_;                                                    # Number to print as a variable, width of output field
  @_ == 2 or confess "Two parameters";
  PrintRightInHex($stdout, $number, $width);
  PrintOutNL;
 }

#D2 Binary representation, right justified                                      # Print number variables in binary right justified in fields of specified width.

sub Nasm::X86::Variable::rightInBin($$$)                                        # Write the specified variable number in binary right justified in a field of specified width to the specified channel.
 {my ($number, $channel, $width) = @_;                                          # Number to print as a variable, channel to print on, width of output field
  @_ == 3 or confess "Three parameters";
  PrintRightInBin($channel, $number, $width);
 }

sub Nasm::X86::Variable::errRightInBin($$)                                      # Write the specified variable number in binary right justified in a field of specified width to stderr
 {my ($number, $width) = @_;                                                    # Number to print as a variable, width of output field
  @_ == 2 or confess "Two parameters";
  PrintRightInBin($stderr, $number, $width);
 }

sub Nasm::X86::Variable::errRightInBinNL($$)                                    # Write the specified variable number in binary right justified in a field of specified width to stderr followed by a new line
 {my ($number, $width) = @_;                                                    # Number to print as a variable, width of output field
  @_ == 2 or confess "Two parameters";
  PrintRightInBin($stderr, $number, $width);
  PrintErrNL;
 }

sub Nasm::X86::Variable::outRightInBin($$)                                      # Write the specified variable number in binary right justified in a field of specified width to stdout
 {my ($number, $width) = @_;                                                    # Number to print as a variable, width of output field
  @_ == 2 or confess "Two parameters";
  PrintRightInBin($stdout, $number, $width);
 }

sub Nasm::X86::Variable::outRightInBinNL($$)                                    # Write the specified variable number in binary right justified in a field of specified width to stdout followed by a new line
 {my ($number, $width) = @_;                                                    # Number to print as a variable, width of output field
  @_ == 2 or confess "Two parameters";
  PrintRightInBin($stdout, $number, $width);
  PrintOutNL;
 }

#D3 Spaces                                                                      # Print out a variable number of spaces

sub Nasm::X86::Variable::spaces($$)                                             # Print the specified number of spaces to the specified channel.
 {my ($count, $channel) = @_;                                                   # Number of spaces, channel
  $count->for(sub {PrintSpace $channel});
 }

sub Nasm::X86::Variable::errSpaces($)                                           # Print the specified number of spaces to stderr.
 {my ($count) = @_;                                                             # Number of spaces
  $count->spaces($stderr);
 }

sub Nasm::X86::Variable::outSpaces($)                                           # Print the specified number of spaces to stdout.
 {my ($count) = @_;                                                             # Number of spaces
  $count->spaces($stdout);
 }

#D3 C style zero terminated strings                                             # Print out C style zero terminated strings.

sub Nasm::X86::Variable::errCString($)                                          # Print a zero terminated C style string addressed by a variable on stderr.
 {my ($string) = @_;                                                            # String
  PrintCString($stderr, $string);
 }

sub Nasm::X86::Variable::errCStringNL($)                                        # Print a zero terminated C style string addressed by a variable on stderr followed by a new line.
 {my ($string) = @_;                                                            # String
  $string->errCString($string);
  PrintErrNL;
 }

sub Nasm::X86::Variable::outCString($)                                          # Print a zero terminated C style string addressed by a variable on stdout.
 {my ($string) = @_;                                                            # String
  PrintCString($stdout, $string);
 }

sub Nasm::X86::Variable::outCStringNL($)                                        # Print a zero terminated C style string addressed by a variable on stdout followed by a new line.
 {my ($string) = @_;                                                            # String
  $string->outCString;
  PrintOutNL;
 }

#D2 Operations                                                                  # Variable operations

if (1)                                                                          # Define operator overloading for Variables
 {package Nasm::X86::Variable;
  use overload
    '+'  => \&add,
    '-'  => \&sub,
    '*'  => \&times,
    '/'  => \&divide,
    '%'  => \&mod,
   '=='  => \&eq,
   '!='  => \&ne,
   '>='  => \&ge,
    '>'  => \&gt,
   '<='  => \&le,
   '<'   => \&lt,
   '++'  => \&inc,
   '--'  => \&dec,
   '""'  => \&str,
#  '&'   => \&and,                                                              # We use the zero flag as the bit returned by a Boolean operation so we cannot implement '&' or '|' which were previously in use because '&&' and '||' and "and" and "or" are all disallowed in Perl operator overloading.
#  '|'   => \&or,
   '+='  => \&plusAssign,
   '-='  => \&minusAssign,
   '='   => \&equals,
   '<<'  => \&shiftLeft,
   '>>'  => \&shiftRight,
  '!'    => \&not,
 }

sub Nasm::X86::Variable::call($)                                                # Execute the call instruction for a target whose address is held in the specified variable.
 {my ($target) = @_;                                                            # Variable containing the address of the code to call
  $target->setReg(rdi);                                                         # Address of code to call
  Call rdi;                                                                     # Call referenced code
 }

sub Nasm::X86::Variable::address($;$)                                           # Get the address of a variable with an optional offset.
 {my ($left, $offset) = @_;                                                     # Left variable, optional offset
  my $o = $offset ? "+$offset" : "";
  "[".$left-> label."$o]"
 }

sub Nasm::X86::Variable::clone($$)                                              # Clone a variable to make a new variable.
 {my ($variable, $name) = @_;                                                   # Variable to clone, new name for variable
  @_ == 2 or confess "Two parameters";
  my $c = V($name);                                                             # Use supplied name or fall back on existing name
  $c->copy($variable);                                                          # Copy into created variable
  $c                                                                            # Return the clone of the variable
 }

sub Nasm::X86::Variable::copy($$)                                               # Copy one variable into another.
 {my ($left, $right) = @_;                                                      # Left variable, right variable
  @_ == 2 or confess "Two parameters";

  my $l = $left ->address;
  my $r = ref($right) ? $right->address : $right;                               # Variable address or register expression (which might in fact be a constant)

  Mov rdi, $r;                                                                  # Load right hand side

  if (ref($right) and $right->reference)                                        # Dereference a reference
   {Mov rdi, "[rdi]";
   }

  if ($left ->reference)                                                        # Copy a reference
   {Mov rsi, $l;
    Mov "[rsi]", rdi;
   }
  else                                                                          # Copy a non reference
   {Mov $l, rdi;
   }
  $left                                                                         # Return the variable on the left now that it has had the right hand side copied into it.
 }

sub Nasm::X86::Variable::copyRef($$)                                            # Copy a reference to a variable.
 {my ($left, $right) = @_;                                                      # Left variable, right variable
  @_ == 2 or confess "Two parameters";

  $left->reference  or confess "Left hand side must be a reference";

  my $l = $left ->address;
  my $r = $right->address;

  if ($right->reference)                                                        # Right is a reference so we copy its value to create a new reference to the original data
   {Mov rdi, $r;
   }
  else                                                                          # Right is not a reference so we copy its address to make a reference to the data
   {Lea rdi, $r;
   }
  Mov $l, rdi;                                                                  # Save value of address in left

  $left;                                                                        # Chain
 }

sub Nasm::X86::Variable::copyZF($)                                              # Copy the current state of the zero flag into a variable.
 {my ($var) = @_;                                                               # Variable
  @_ == 1 or confess "One parameter";

  my $a = $var->address;                                                        # Address of the variable

  PushR (rax);
  Lahf;                                                                         # Save flags to ah: (SF:ZF:0:AF:0:PF:1:CF)
  Shr ah, 6;                                                                    # Put zero flag in bit zero
  And ah, 1;                                                                    # Isolate zero flag
  Mov $a, ah;                                                                   # Save zero flag
  PopR;
 }

sub Nasm::X86::Variable::copyZFInverted($)                                      # Copy the opposite of the current state of the zero flag into a variable.
 {my ($var) = @_;                                                               # Variable
  @_ == 1 or confess "One parameter";

  my $a = $var->address;                                                        # Address of the variable

  PushR (rax, r15);
  Lahf;                                                                         # Save flags to ah: (SF:ZF:0:AF:0:PF:1:CF)
  Shr ah, 6;                                                                    # Put zero flag in bit zero
  Not ah;                                                                       # Invert zero flag
  And ah, 1;                                                                    # Isolate zero flag
  if ($var->reference)                                                          # Dereference and save
   {PushR rdx;
    Mov rdx, $a;
    Mov "[rdx]", ah;                                                            # Save zero flag
    PopR rdx;
   }
  else                                                                          # Save without dereferencing
   {Mov $a, ah;                                                                 # Save zero flag
   }
  PopR;
 }

sub Nasm::X86::Variable::equals($$$)                                            # Equals operator.
 {my ($op, $left, $right) = @_;                                                 # Operator, left variable,  right variable
  $op
 }

sub Nasm::X86::Variable::assign($$$)                                            # Assign to the left hand side the value of the right hand side.
 {my ($left, $op, $right) = @_;                                                 # Left variable, operator, right variable
  $left->constant and confess "cannot assign to a constant";

  Comment "Variable assign";
  PushR (r14, r15);
  Mov r14, $left ->address;
  if ($left->reference)                                                         # Dereference left if necessary
   {Mov r14, "[r14]";
   }
  if (!ref($right))                                                             # Load right constant
   {Mov r15, $right;
   }
  else                                                                          # Load right variable
   {Mov r15, $right->address;
    if ($right->reference)                                                      # Dereference right if necessary
     {Mov r15, "[r15]";
     }
   }
  &$op(r14, r15);
  if ($left->reference)                                                         # Store in reference on left if necessary
   {PushR r13;
    Mov r13, $left->address;
    Mov "[r13]", r14;
    PopR r13;
   }
  else                                                                          # Store in variable
   {Mov $left ->address, r14;
   }
  PopR;

  $left;
 }

sub Nasm::X86::Variable::plusAssign($$)                                         # Implement plus and assign.
 {my ($left, $right) = @_;                                                      # Left variable,  right variable
  $left->assign(\&Add, $right);
 }

sub Nasm::X86::Variable::minusAssign($$)                                        # Implement minus and assign.
 {my ($left, $right) = @_;                                                      # Left variable,  right variable
  $left->assign(\&Sub, $right);
 }

sub Nasm::X86::Variable::arithmetic($$$$)                                       # Return a variable containing the result of an arithmetic operation on the left hand and right hand side variables.
 {my ($op, $name, $left, $right) = @_;                                          # Operator, operator name, Left variable,  right variable

  my $l = $left ->address;
  my $r = ref($right) ? $right->address : $right;                               # Right can be either a variable reference or a constant

  Comment "Arithmetic Start";
  PushR (r14, r15);
  Mov r15, $l;
  if ($left->reference)                                                         # Dereference left if necessary
   {Mov r15, "[r15]";
   }
  Mov r14, $r;
  if (ref($right) and $right->reference)                                        # Dereference right if necessary
   {Mov r14, "[r14]";
   }
  &$op(r15, r14);
  my $v = V(join(' ', '('.$left->name, $name, (ref($right) ? $right->name : $right).')'), r15);
  PopR;
  Comment "Arithmetic End";

  return $v;
 }

sub Nasm::X86::Variable::add($$)                                                # Add the right hand variable to the left hand variable and return the result as a new variable.
 {my ($left, $right) = @_;                                                      # Left variable,  right variable
  Nasm::X86::Variable::arithmetic(\&Add, q(add), $left, $right);
 }

sub Nasm::X86::Variable::sub($$)                                                # Subtract the right hand variable from the left hand variable and return the result as a new variable.
 {my ($left, $right) = @_;                                                      # Left variable,  right variable
  Nasm::X86::Variable::arithmetic(\&Sub, q(sub), $left, $right);
 }

sub Nasm::X86::Variable::times($$)                                              # Multiply the left hand variable by the right hand variable and return the result as a new variable.
 {my ($left, $right) = @_;                                                      # Left variable,  right variable
  Nasm::X86::Variable::arithmetic(\&Imul, q(times), $left, $right);
 }

sub Nasm::X86::Variable::division($$$)                                          # Return a variable containing the result or the remainder that occurs when the left hand side is divided by the right hand side.
 {my ($op, $left, $right) = @_;                                                 # Operator, Left variable,  right variable

  my $l = $left ->address;
  my $r = ref($right) ? $right->address : $right;                               # Right can be either a variable reference or a constant
  PushR my @regs = (rax, rdx, r15);
  Mov rax, $l;
  Mov rax, "[rax]" if $left->reference;
  Mov r15, $r;
  Mov r15, "[r15]" if ref($right) and $right->reference;
  Idiv r15;
  my $v = V(join(' ', '('.$left->name, $op, (ref($right) ? $right->name : '').')'), $op eq "%" ? rdx : rax);
  PopR @regs;
  $v;
 }

sub Nasm::X86::Variable::divide($$)                                             # Divide the left hand variable by the right hand variable and return the result as a new variable.
 {my ($left, $right) = @_;                                                      # Left variable, right variable
  Nasm::X86::Variable::division("/", $left, $right);
 }

sub Nasm::X86::Variable::mod($$)                                                # Divide the left hand variable by the right hand variable and return the remainder as a new variable.
 {my ($left, $right) = @_;                                                      # Left variable, right variable
  Nasm::X86::Variable::division("%", $left, $right);
 }

sub Nasm::X86::Variable::shiftLeft($$)                                          # Shift the left hand variable left by the number of bits specified in the right hand variable and return the result as a new variable.
 {my ($left, $right) = @_;                                                      # Left variable, right variable
  PushR rcx, r15;
  $left ->setReg(r15);                                                          # Value to shift
  confess "Variable required not $right" unless ref($right);
  $right->setReg(rcx);                                                          # Amount to shift
  Shl r15, cl;                                                                  # Shift
  my $r = V "shift left" => r15;                                                # Save result in a new variable
  PopR;
  $r
 }

sub Nasm::X86::Variable::shiftRight($$)                                         # Shift the left hand variable right by the number of bits specified in the right hand variable and return the result as a new variable.
 {my ($left, $right) = @_;                                                      # Left variable, right variable
  PushR rcx, r15;
  $left ->setReg(r15);                                                          # Value to shift
  confess "Variable required not $right" unless ref($right);
  $right->setReg(rcx);                                                          # Amount to shift
  Shr r15, cl;                                                                  # Shift
  my $r = V "shift right" => r15;                                               # Save result in a new variable
  PopR;
  $r
 }

sub Nasm::X86::Variable::not($)                                                 # Form two complement of left hand side and return it as a variable.
 {my ($left) = @_;                                                              # Left variable
  $left->setReg(rdi);                                                           # Value to negate
  Not rdi;                                                                      # Two's complement
  V "neg" => rdi;                                                               # Save result in a new variable
 }

#D2 Boolean                                                                     # Operations on variables that yield a boolean result

sub Nasm::X86::Variable::boolean($$$$)                                          # Combine the left hand variable with the right hand variable via a boolean operator.
 {my ($sub, $op, $left, $right) = @_;                                           # Operator, operator name, Left variable,  right variable

  !ref($right) or ref($right) =~ m(Variable) or confess "Variable expected";
  my $r = ref($right) ? $right->address : $right;                               # Right can be either a variable reference or a constant

  Comment "Boolean Arithmetic Start";
  PushR r15;

  Mov r15, $left ->address;
  if ($left->reference)                                                         # Dereference left if necessary
   {Mov r15, "[r15]";
   }
  if (ref($right) and $right->reference)                                        # Dereference on right if necessary
   {PushR r14;
    Mov r14, $right ->address;
    Mov r14, "[r14]";
    Cmp r15, r14;
    PopR r14;
   }
  elsif (ref($right))                                                           # Variable but not a reference on the right
   {Cmp r15, $right->address;
   }
  else                                                                          # Constant on the right
   {Cmp r15, $right;
   }

  &$sub(sub {Mov  r15, 1}, sub {Mov  r15, 0});
  my $v = V(join(' ', '('.$left->name, $op, (ref($right) ? $right->name : '').')'), r15);

  PopR r15;
  Comment "Boolean Arithmetic end";

  $v
 }

sub Nasm::X86::Variable::booleanZF($$$$)                                        # Combine the left hand variable with the right hand variable via a boolean operator and indicate the result by setting the zero flag if the result is true.
 {my ($sub, $op, $left, $right) = @_;                                           # Operator, operator name, Left variable,  right variable

  !ref($right) or ref($right) =~ m(Variable) or confess "Variable expected";
  my $r = ref($right) ? $right->address : $right;                               # Right can be either a variable reference or a constant

  Comment "Boolean ZF Arithmetic Start";
  PushR r15;

  Mov r15, $left ->address;
  if ($left->reference)                                                         # Dereference left if necessary
   {Mov r15, "[r15]";
   }
  if (ref($right) and $right->reference)                                        # Dereference on right if necessary
   {PushR r14;
    Mov r14, $right ->address;
    Mov r14, "[r14]";
    Cmp r15, r14;
    PopR r14;
   }
  elsif (ref($right))                                                           # Variable but not a reference on the right
   {Cmp r15, $right->address;
   }
  else                                                                          # Constant on the right
   {Cmp r15, $right;
   }

  &$sub(sub {Cmp rsp, rsp}, sub {Test rsp, rsp});

  PopR r15;
  Comment "Boolean ZF Arithmetic end";

  V(empty);                                                                     # Return an empty variable so that If regenerates the follow on code
 }

sub Nasm::X86::Variable::booleanC($$$$)                                         # Combine the left hand variable with the right hand variable via a boolean operator using a conditional move instruction.
 {my ($cmov, $op, $left, $right) = @_;                                          # Conditional move instruction name, operator name, Left variable,  right variable

  !ref($right) or ref($right) =~ m(Variable) or confess "Variable expected";
  my $r = ref($right) ? $right->address : $right;                               # Right can be either a variable reference or a constant

  PushR r15;
  Mov r15, $left ->address;
  if ($left->reference)                                                         # Dereference left if necessary
   {Mov r15, "[r15]";
   }
  if (ref($right) and $right->reference)                                        # Dereference on right if necessary
   {PushR r14;
    Mov r14, $right ->address;
    Mov r14, "[r14]";
    Cmp r15, r14;
    PopR r14;
   }
  elsif (ref($right))                                                           # Variable but not a reference on the right
   {Cmp r15, $right->address;
   }
  else                                                                          # Constant on the right
   {Cmp r15, $right;
   }

  Mov r15, 1;                                                                   # Place a one below the stack
  my $w = RegisterSize r15;
  Mov "[rsp-$w]", r15;
  Mov r15, 0;                                                                   # Assume the result was false
  &$cmov(r15, "[rsp-$w]");                                                      # Indicate true result
  my $v = V(join(' ', '('.$left->name, $op, (ref($right) ? $right->name : '').')'), r15);
  PopR r15;

  $v
 }

sub Nasm::X86::Variable::eq($$)                                                 # Check whether the left hand variable is equal to the right hand variable.
 {my ($left, $right) = @_;                                                      # Left variable,  right variable
  Nasm::X86::Variable::booleanZF(\&IfEq, q(eq), $left, $right);
 }

sub Nasm::X86::Variable::ne($$)                                                 # Check whether the left hand variable is not equal to the right hand variable.
 {my ($left, $right) = @_;                                                      # Left variable,  right variable
  Nasm::X86::Variable::booleanZF(\&IfNe, q(ne), $left, $right);
 }

sub Nasm::X86::Variable::ge($$)                                                 # Check whether the left hand variable is greater than or equal to the right hand variable.
 {my ($left, $right) = @_;                                                      # Left variable,  right variable
  Nasm::X86::Variable::booleanZF(\&IfGe, q(ge), $left, $right);
 }

sub Nasm::X86::Variable::gt($$)                                                 # Check whether the left hand variable is greater than the right hand variable.
 {my ($left, $right) = @_;                                                      # Left variable,  right variable
  Nasm::X86::Variable::booleanZF(\&IfGt, q(gt), $left, $right);
 }

sub Nasm::X86::Variable::le($$)                                                 # Check whether the left hand variable is less than or equal to the right hand variable.
 {my ($left, $right) = @_;                                                      # Left variable,  right variable
  Nasm::X86::Variable::booleanZF(\&IfLe, q(le), $left, $right);
 }

sub Nasm::X86::Variable::lt($$)                                                 # Check whether the left hand variable is less than the right hand variable.
 {my ($left, $right) = @_;                                                      # Left variable,  right variable
  Nasm::X86::Variable::booleanZF(\&IfLt, q(lt), $left, $right);
 }

sub Nasm::X86::Variable::isRef($)                                               # Check whether the specified  variable is a reference to another variable.
 {my ($variable) = @_;                                                          # Variable
  my $n = $variable->name;                                                      # Variable name
  $variable->reference
 }

sub Nasm::X86::Variable::setReg($$)                                             # Set the named registers from the content of the variable.
 {my ($variable, $register) = @_;                                               # Variable, register to load

  my $r = registerNameFromNumber $register;
  if (CheckMaskRegister($r))                                                    # Mask register is being set
   {if ($variable->isRef)
     {confess "Cannot set a mask register to the address of a variable";
     }
    else
     {PushR r15;
      Mov r15, $variable->address;
      Kmovq $r, r15;
      PopR;
     }
   }
  else                                                                          # Set normal register
   {if ($variable->isRef)
     {Mov $r, $variable->address;
      Mov $r, "[$r]";
     }
    else
     {Mov $r, $variable->address;
     }
   }

  $register                                                                     # name of register being set
 }

sub Nasm::X86::Variable::getReg($$)                                             # Load the variable from a register expression.
 {my ($variable, $register) = @_;                                               # Variable, register expression to load
  @_ == 2 or confess "Two parameters";
  my $r = registerNameFromNumber $register;
  if ($variable->isRef)                                                         # Move to the location referred to by this variable
   {Comment "Get variable value from register $r";
    my $p = $r eq r15 ? r14 : r15;
    PushR $p;
    Mov $p, $variable->address;
    Mov "[$p]", $r;
    PopR $p;
   }
  else                                                                          # Move to this variable
   {Mov $variable->address, $r;
   }
  $variable                                                                     # Chain
 }

sub Nasm::X86::Variable::getConst($$)                                           # Load the variable from a constant in effect setting a variable to a specified value.
 {my ($variable, $constant) = @_;                                               # Variable, constant to load
  @_ == 2 or confess "Two parameters";
  Mov rdi, $constant;
  $variable->getReg(rdi);
 }

sub Nasm::X86::Variable::incDec($$)                                             # Increment or decrement a variable.
 {my ($left, $op) = @_;                                                         # Left variable operator, address of operator to perform inc or dec
  $left->constant and confess "Cannot increment or decrement a constant";
  my $l = $left->address;
  if ($left->reference)
   {PushR (rdi, rsi);                                                           # Violates the rdi/rsi rule if removed
    Mov rsi, $l;
    Mov rdi, "[rsi]";
    &$op(rdi);
    Mov "[rsi]", rdi;
    PopR;
    return $left;
   }
  else
   {PushR rsi;
    Mov rsi, $l;
    &$op(rsi);
    Mov $l, rsi;
    PopR rsi;
    return $left;
   }
 }

sub Nasm::X86::Variable::inc($)                                                 # Increment a variable.
 {my ($left) = @_;                                                              # Variable
  $left->incDec(\&Inc);
 }

sub Nasm::X86::Variable::dec($)                                                 # Decrement a variable.
 {my ($left) = @_;                                                              # Variable
  $left->incDec(\&Dec);
 }

sub Nasm::X86::Variable::str($)                                                 # The name of the variable.
 {my ($left) = @_;                                                              # Variable
  $left->name;
 }

sub Nasm::X86::Variable::min($$)                                                # Minimum of two variables.
 {my ($left, $right) = @_;                                                      # Left variable, right variable or constant
  PushR (r12, r14, r15);
  $left->setReg(r14);

  if (ref($right))                                                              # Right hand side is a variable
   {$right->setReg(r15);
   }
  else                                                                          # Right hand side is a constant
   {Mov r15, $right;
   }

  Cmp r14, r15;
  Cmovg  r12, r15;
  Cmovle r12, r14;
  my $r = V("min", r12);
  PopR;
  $r
 }

sub Nasm::X86::Variable::max($$)                                                # Maximum of two variables.
 {my ($left, $right) = @_;                                                      # Left variable, right variable or constant
  PushR (r12, r14, r15);
  $left->setReg(r14);

  if (ref($right))                                                              # Right hand side is a variable
   {$right->setReg(r15);
   }
  else                                                                          # Right hand side is a constant
   {Mov r15, $right;
   }

  Cmp r14, r15;
  Cmovg  r12, r14;
  Cmovle r12, r15;

  my $r = V("max", r12);
  PopR;
  $r
 }

sub Nasm::X86::Variable::and($$)                                                # And two variables.
 {my ($left, $right) = @_;                                                      # Left variable, right variable
  PushR (r14, r15);
  Mov r14, 0;
  $left->setReg(r15);
  Cmp r15, 0;
  &IfNe (
    sub
     {$right->setReg(r15);
      Cmp r15, 0;
      &IfNe(sub {Add r14, 1});
     }
   );
  my $r = V("And(".$left->name.", ".$right->name.")", r14);
  PopR;
  $r
 }

sub Nasm::X86::Variable::or($$)                                                 # Or two variables.
 {my ($left, $right) = @_;                                                      # Left variable, right variable
  PushR (r14, r15);
  Mov r14, 1;
  $left->setReg(r15);
  Cmp r15, 0;
  &IfEq (
    sub
     {$right->setReg(r15);
      Cmp r15, 0;
      &IfEq(sub {Mov r14, 0});
     }
   );
  my $r = V("Or(".$left->name.", ".$right->name.")", r14);
  PopR;
  $r
 }

sub Nasm::X86::Variable::setMask($$$)                                           # Set the mask register to ones starting at the specified position for the specified length and zeroes elsewhere.
 {my ($start, $length, $mask) = @_;                                             # Variable containing start of mask, variable containing length of mask, mask register
  @_ == 3 or confess "Three parameters";

  PushR (r13, r14, r15);
  Mov r15, -1;
  if ($start)                                                                   # Non zero start
   {$start->setReg(r14);
    Bzhi r15, r15, r14;
    Not  r15;
    ref($length) or confess "Not a variable";
    $length->setReg(r13);
    Add  r14, r13;
   }
  else                                                                          # Starting at zero
   {confess "Deprecated: use setMaskFirst instead";
     $length->setReg(r13);
    Mov r14, $length;
   }
  Bzhi r15, r15, r14;
  Kmovq $mask, r15;
  PopR;
 }

sub Nasm::X86::Variable::setMaskFirst($$)                                       # Set the first bits in the specified mask register.
 {my ($length, $mask) = @_;                                                     # Variable containing length to set, mask register
  @_ == 2 or confess "Two parameters";

  PushR my @save = my ($l, $b) = ChooseRegisters(2, $mask);                     # Choose two registers not the mask register
  Mov $b, -1;
  $length->setReg($l);
  Bzhi $b, $b, $l;
  Kmovq $mask, $b if $mask =~ m(\Ak)i;                                          # Set mask register if provided
  Mov   $mask, $b if $mask =~ m(\Ar)i;                                          # Set general purpose register if provided
  PopR;
 }

sub Nasm::X86::Variable::setMaskBit($$)                                         # Set a bit in the specified mask register retaining the other bits.
 {my ($index, $mask) = @_;                                                      # Variable containing bit position to set, mask register
  @_ == 2 or confess "Two parameters";
  $mask =~ m(\Ak)i or confess "Mask register required";
  PushR my @save = my ($l, $b) = (r14, r15);
  Kmovq $b, $mask;
  $index->setReg($l);
  Bts $b, $l;
  Kmovq $mask, $b;                                                              # Set mask register if provided
  PopR;
 }

sub Nasm::X86::Variable::clearMaskBit($$)                                       # Clear a bit in the specified mask register retaining the other bits.
 {my ($index, $mask) = @_;                                                      # Variable containing bit position to clear, mask register
  @_ == 2 or confess "Two parameters";
  $mask =~ m(\Ak)i or confess "Mask register required";

  PushR my @save = my ($l, $b) = (r14, r15);
  Kmovq $b, $mask;
  $index->setReg($l);
  Btc $b, $l;
  Kmovq $mask, $b;                                                              # Set mask register if provided
  PopR;
 }

sub Nasm::X86::Variable::setBit($$)                                             # Set a bit in the specified register retaining the other bits.
 {my ($index, $mask) = @_;                                                      # Variable containing bit position to set, mask register
  @_ == 2 or confess "Two parameters";

  PushR my @save = my ($l) = ChooseRegisters(1, $mask);                         # Choose a register
  $index->setReg($l);
  Bts $mask, $l;
  PopR;
 }

sub Nasm::X86::Variable::clearBit($$)                                           # Clear a bit in the specified mask register retaining the other bits.
 {my ($index, $mask) = @_;                                                      # Variable containing bit position to clear, mask register
  @_ == 2 or confess "Two parameters";

  PushR my @save = my ($l) = ChooseRegisters(1, $mask);                         # Choose a register
  $index->setReg($l);
  Btc $mask, $l;
  PopR;
 }

sub Nasm::X86::Variable::setZmm($$$$)                                           # Load bytes from the memory addressed by specified source variable into the numbered zmm register at the offset in the specified offset moving the number of bytes in the specified variable.
 {my ($source, $zmm, $offset, $length) = @_;                                    # Variable containing the address of the source, number of zmm to load, variable containing offset in zmm to move to, variable containing length of move
  @_ == 4 or confess;
  ref($offset) && ref($length) or confess "Missing variable";                   # Need variables of offset and length
  Comment "Set Zmm $zmm from Memory";
  PushR (k7, r14, r15);
  $offset->setMask($length, k7);                                                # Set mask for target
  $source->setReg(r15);
  $offset->setReg(r14);                                                         # Position memory for target
  Sub r15, r14;                                                                 # Position memory for target
  Vmovdqu8 "zmm${zmm}{k7}", "[r15]";                                            # Read from memory
  PopR;
 }

sub Nasm::X86::Variable::loadZmm($$)                                            # Load bytes from the memory addressed by the specified source variable into the numbered zmm register.
 {my ($source, $zmm) = @_;                                                      # Variable containing the address of the source, number of zmm to get
  @_ == 2 or confess "Two parameters";

  $source->setReg(rdi);
  Vmovdqu8 "zmm$zmm", "[rdi]";
 }

sub bRegFromZmm($$$)                                                            # Load the specified register from the byte at the specified offset located in the numbered zmm.
 {my ($register, $zmm, $offset) = @_;                                           # Register to load, numbered zmm register to load from, constant offset in bytes
  @_ == 3 or confess "Three parameters";
  my $z = registerNameFromNumber $zmm;
  $offset >= 0 && $offset <= RegisterSize zmm0 or
    confess "Offset $offset Out of range";

  PushRR $z;                                                                    # Push source register

  my $b = byteRegister $register;                                               # Corresponding byte register

  Mov $b, "[rsp+$offset]";                                                      # Load byte register from offset
  Add rsp, RegisterSize $z;                                                     # Pop source register
 }

sub bRegIntoZmm($$$)                                                            # Put the byte content of the specified register into the byte in the numbered zmm at the specified offset in the zmm.
 {my ($register,  $zmm, $offset) = @_;                                          # Register to load, numbered zmm register to load from, constant offset in bytes
  @_ == 3 or confess "Three parameters";
  $offset >= 0 && $offset <= RegisterSize zmm0 or confess "Out of range";

  PushR "zmm$zmm";                                                              # Push source register

  my $b = byteRegister $register;                                               # Corresponding byte register

  Mov "[rsp+$offset]", $b;                                                      # Save byte at specified offset
  PopR "zmm$zmm";                                                               # Reload zmm
 }

sub wRegFromZmm($$$)                                                            # Load the specified register from the word at the specified offset located in the numbered zmm.
 {my ($register, $zmm, $offset) = @_;                                           # Register to load, numbered zmm register to load from, constant offset in bytes
  @_ == 3 or confess "Three parameters";
  my $z = registerNameFromNumber $zmm;
  $offset >= 0 && $offset <= RegisterSize zmm0 or
    confess "Offset $offset Out of range";

  PushRR $z;                                                                    # Push source register

  my $w = wordRegister $register;                                               # Corresponding word register

  Mov $w, "[rsp+$offset]";                                                      # Load word register from offset
  Add rsp, RegisterSize $z;                                                     # Pop source register
 }

sub wRegIntoZmm($$$)                                                            # Put the specified register into the word in the numbered zmm at the specified offset in the zmm.
 {my ($register,  $zmm, $offset) = @_;                                          # Register to load, numbered zmm register to load from, constant offset in bytes
  @_ == 3 or confess "Three parameters";
  $offset >= 0 && $offset <= RegisterSize zmm0 or confess "Out of range";

  PushR "zmm$zmm";                                                              # Push source register

  my $w = wordRegister $register;                                               # Corresponding word register

  Mov "[rsp+$offset]", $w;                                                      # Save word at specified offset
  PopR "zmm$zmm";                                                               # Reload zmm
 }

sub LoadRegFromMm($$$)                                                          # Load the specified register from the numbered zmm at the quad offset specified as a constant number.
 {my ($mm, $offset, $reg) = @_;                                                 # Mm register, offset in quads, general purpose register to load
  @_ == 3 or confess "Three parameters";
  my $w = RegisterSize rax;                                                     # Size of rax
  my $W = RegisterSize $mm;                                                     # Size of mm register
  Vmovdqu64 "[rsp-$W]", $mm;                                                    # Write below the stack
  Mov $reg, "[rsp+$w*$offset-$W]";                                              # Load register from offset
 }

sub SaveRegIntoMm($$$)                                                          # Save the specified register into the numbered zmm at the quad offset specified as a constant number.
 {my ($mm, $offset, $reg) = @_;                                                 # Mm register, offset in quads, general purpose register to load
  @_ == 3 or confess "Three parameters";
  my $w = RegisterSize rax;                                                     # Size of rax
  my $W = RegisterSize $mm;                                                     # Size of mm register
  Vmovdqu64 "[rsp-$W]", $mm;                                                    # Write below the stack
  Mov "[rsp+$w*$offset-$W]", $reg;                                              # Save register into offset
  Vmovdqu64 $mm, "[rsp-$W]";                                                    # Reload from the stack
 }

sub getBwdqFromMm($$$)                                                          # Get the numbered byte|word|double word|quad word from the numbered zmm register and return it in a variable.
 {my ($size, $mm, $offset) = @_;                                                # Size of get, mm register, offset in bytes either as a constant or as a variable
  @_ == 3 or confess "Three parameters";

  my $o;                                                                        # The offset into the mm register
  if (ref($offset))                                                             # The offset is being passed in a variable
   {$offset->setReg($o = rsi);
   }
  else                                                                          # The offset is being passed as a register expression
   {$o = $offset;
   }

  my $w = RegisterSize $mm;                                                     # Size of mm register
  Vmovdqu32 "[rsp-$w]", $mm;                                                    # Write below the stack

  ClearRegisters rdi if $size !~ m(q|d);                                        # Clear the register if necessary
  Mov  byteRegister(rdi), "[rsp+$o-$w]" if $size =~ m(b);                       # Load byte register from offset
  Mov  wordRegister(rdi), "[rsp+$o-$w]" if $size =~ m(w);                       # Load word register from offset
  Mov dWordRegister(rdi), "[rsp+$o-$w]" if $size =~ m(d);                       # Load double word register from offset
  Mov rdi,                "[rsp+$o-$w]" if $size =~ m(q);                       # Load register from offset

  V("$size at offset $offset in $mm", rdi);                                     # Create variable
 }

sub bFromX($$)                                                                  # Get the byte from the numbered xmm register and return it in a variable.
 {my ($xmm, $offset) = @_;                                                      # Numbered xmm, offset in bytes
  getBwdqFromMm('b', "xmm$xmm", $offset)                                        # Get the numbered byte|word|double word|quad word from the numbered xmm register and return it in a variable
 }

sub wFromX($$)                                                                  # Get the word from the numbered xmm register and return it in a variable.
 {my ($xmm, $offset) = @_;                                                      # Numbered xmm, offset in bytes
  getBwdqFromMm('w', "xmm$xmm", $offset)                                        # Get the numbered byte|word|double word|quad word from the numbered xmm register and return it in a variable
 }

sub dFromX($$)                                                                  # Get the double word from the numbered xmm register and return it in a variable.
 {my ($xmm, $offset) = @_;                                                      # Numbered xmm, offset in bytes
  getBwdqFromMm('d', "xmm$xmm", $offset)                                        # Get the numbered byte|word|double word|quad word from the numbered xmm register and return it in a variable
 }

sub qFromX($$)                                                                  # Get the quad word from the numbered xmm register and return it in a variable.
 {my ($xmm, $offset) = @_;                                                      # Numbered xmm, offset in bytes
  getBwdqFromMm('q', "xmm$xmm", $offset)                                        # Get the numbered byte|word|double word|quad word from the numbered xmm register and return it in a variable
 }

sub bFromZ($$)                                                                  # Get the byte from the numbered zmm register and return it in a variable.
 {my ($zmm, $offset) = @_;                                                      # Numbered zmm, offset in bytes
  getBwdqFromMm('b', "zmm$zmm", $offset)                                        # Get the numbered byte|word|double word|quad word from the numbered zmm register and return it in a variable
 }

sub wFromZ($$)                                                                  # Get the word from the numbered zmm register and return it in a variable.
 {my ($zmm, $offset) = @_;                                                      # Numbered zmm, offset in bytes
  getBwdqFromMm('w', "zmm$zmm", $offset)                                        # Get the numbered byte|word|double word|quad word from the numbered zmm register and return it in a variable
 }

sub dFromZ($$)                                                                  # Get the double word from the numbered zmm register and return it in a variable.
 {my ($zmm, $offset) = @_;                                                      # Numbered zmm, offset in bytes
  getBwdqFromMm('d', "zmm$zmm", $offset)                                        # Get the numbered byte|word|double word|quad word from the numbered zmm register and return it in a variable
 }

sub qFromZ($$)                                                                  # Get the quad word from the numbered zmm register and return it in a variable.
 {my ($zmm, $offset) = @_;                                                      # Numbered zmm, offset in bytes
  getBwdqFromMm('q', "zmm$zmm", $offset)                                        # Get the numbered byte|word|double word|quad word from the numbered zmm register and return it in a variable
 }

sub Nasm::X86::Variable::bFromZ($$$)                                            # Get the byte from the numbered zmm register and put it in a variable.
 {my ($variable, $zmm, $offset) = @_;                                           # Variable, numbered zmm, offset in bytes
  @_ == 3 or confess "Three parameters";
  $variable->copy(getBwdqFromMm 'b', "zmm$zmm", $offset);                       # Get the numbered byte|word|double word|quad word from the numbered zmm register and put it in a variable
 }

sub Nasm::X86::Variable::wFromZ($$$)                                            # Get the word from the numbered zmm register and put it in a variable.
 {my ($variable, $zmm, $offset) = @_;                                           # Variable, numbered zmm, offset in bytes
  @_ == 3 or confess "Three parameters";
  $variable->copy(getBwdqFromMm 'w', "zmm$zmm", $offset);                       # Get the numbered byte|word|double word|quad word from the numbered zmm register and put it in a variable
 }

sub Nasm::X86::Variable::dFromZ($$$)                                            # Get the double word from the numbered zmm register and put it in a variable.
 {my ($variable, $zmm, $offset) = @_;                                           # Variable, numbered zmm, offset in bytes
  @_ == 3 or confess "Three parameters";
  $variable->copy(getBwdqFromMm 'd', "zmm$zmm", $offset);                       # Get the numbered byte|word|double word|quad word from the numbered zmm register and put it in a variable
 }

sub Nasm::X86::Variable::qFromZ($$$)                                            # Get the quad word from the numbered zmm register and put it in a variable.
 {my ($variable, $zmm, $offset) = @_;                                           # Variable, numbered zmm, offset in bytes
  @_ == 3 or confess "Three parameters";
  $variable->copy(getBwdqFromMm 'q', "zmm$zmm", $offset);                       # Get the numbered byte|word|double word|quad word from the numbered zmm register and put it in a variable
 }

sub Nasm::X86::Variable::dFromPointInZ($$)                                      # Get the double word from the numbered zmm register at a point specified by the variable and return it in a variable.
 {my ($point, $zmm) = @_;                                                       # Point, numbered zmm
  PushR 7, 14, 15, $zmm;
  $point->setReg(r15);
  Kmovq k7, r15;
  my ($z) = zmm $zmm;
  Vpcompressd "$z\{k7}", $z;
  Vpextrd r15d, xmm($zmm), 0;                                                   # Extract dword from corresponding xmm
  my $r = V d => r15;
  PopR;
  $r;
 }

sub Nasm::X86::Variable::dIntoPointInZ($$$)                                     # Put the variable double word content into the numbered zmm register at a point specified by the variable.
 {my ($point, $zmm, $content) = @_;                                             # Point, numbered zmm, content to be inserted as a variable
  PushR 7, 14, 15;
  $content->setReg(r14);
  $point->setReg(r15);
  Kmovq k7, r15;
  Vpbroadcastd zmmM($zmm, 7), r14d;                                             # Insert dword at desired location
  PopR;
 }

sub Nasm::X86::Variable::putBwdqIntoMm($$$$)                                    # Place the value of the content variable at the byte|word|double word|quad word in the numbered zmm register.
 {my ($content, $size, $mm, $offset) = @_;                                      # Variable with content, size of put, numbered zmm, offset in bytes
  @_ == 4 or confess "Four parameters";

  my $o;                                                                        # The offset into the mm register
  if (ref($offset))                                                             # The offset is being passed in a variable
   {$offset->setReg($o = rsi);
   }
  else                                                                          # The offset is being passed as a register expression
   {$o = $offset;
    Comment "Put $size at $offset in $mm";
    $offset >= 0 && $offset <= RegisterSize $mm or
      confess "Out of range" if $offset =~ m(\A\d+\Z);                          # Check the offset if it is a number
   }

  $content->setReg(rsi);
  my $w = RegisterSize $mm;                                                     # Size of mm register
  Vmovdqu32 "[rsp-$w]", $mm;                                                    # Write below the stack
  Mov "[rsp+$o-$w]",  byteRegister(rsi) if $size =~ m(b);                       # Write byte register
  Mov "[rsp+$o-$w]",  wordRegister(rsi) if $size =~ m(w);                       # Write word register
  Mov "[rsp+$o-$w]", dWordRegister(rsi) if $size =~ m(d);                       # Write double word register
  Mov "[rsp+$o-$w]", rsi                if $size =~ m(q);                       # Write register
  Vmovdqu32 $mm, "[rsp-$w]";                                                    # Read below the stack
 }

sub Nasm::X86::Variable::bIntoX($$$)                                            # Place the value of the content variable at the byte in the numbered xmm register.
 {my ($content, $xmm, $offset) = @_;                                            # Variable with content, numbered xmm, offset in bytes
  @_ == 3 or confess "Three parameters";
  $content->putBwdqIntoMm('b', "xmm$xmm", $offset)                              # Place the value of the content variable at the word in the numbered xmm register
 }

sub Nasm::X86::Variable::wIntoX($$$)                                            # Place the value of the content variable at the word in the numbered xmm register.
 {my ($content, $xmm, $offset) = @_;                                            # Variable with content, numbered xmm, offset in bytes
  @_ == 3 or confess "Three parameters";
  $content->putBwdqIntoMm('w', "xmm$xmm", $offset)                              # Place the value of the content variable at the byte|word|double word|quad word in the numbered xmm register
 }

sub Nasm::X86::Variable::dIntoX($$$)                                            # Place the value of the content variable at the double word in the numbered xmm register.
 {my ($content, $xmm, $offset) = @_;                                            # Variable with content, numbered xmm, offset in bytes
  @_ == 3 or confess "Three parameters";
  $content->putBwdqIntoMm('d', "xmm$xmm", $offset)                              # Place the value of the content variable at the byte|word|double word|quad word in the numbered xmm register
 }

sub Nasm::X86::Variable::qIntoX($$$)                                            # Place the value of the content variable at the quad word in the numbered xmm register.
 {my ($content, $xmm, $offset) = @_;                                            # Variable with content, numbered xmm, offset in bytes
  @_ == 3 or confess "Three parameters";
  $content->putBwdqIntoMm('q', "xmm$xmm", $offset)                              # Place the value of the content variable at the byte|word|double word|quad word in the numbered xmm register
 }

sub Nasm::X86::Variable::bIntoZ($$$)                                            # Place the value of the content variable at the byte in the numbered zmm register.
 {my ($content, $zmm, $offset) = @_;                                            # Variable with content, numbered zmm, offset in bytes
  @_ == 3 or confess "Three parameters";
  checkZmmRegister($zmm);
  $content->putBwdqIntoMm('b', "zmm$zmm", $offset)                              # Place the value of the content variable at the word in the numbered zmm register
 }

sub Nasm::X86::Variable::putWIntoZmm($$$)                                       # Place the value of the content variable at the word in the numbered zmm register.
 {my ($content, $zmm, $offset) = @_;                                            # Variable with content, numbered zmm, offset in bytes
  @_ == 3 or confess "Three parameters";
  checkZmmRegister($zmm);
  $content->putBwdqIntoMm('w', "zmm$zmm", $offset)                              # Place the value of the content variable at the byte|word|double word|quad word in the numbered zmm register
 }

sub Nasm::X86::Variable::dIntoZ($$$)                                            # Place the value of the content variable at the double word in the numbered zmm register.
 {my ($content, $zmm, $offset) = @_;                                            # Variable with content, numbered zmm, offset in bytes
  @_ == 3 or confess "Three parameters";
  checkZmmRegister($zmm);
  $content->putBwdqIntoMm('d', "zmm$zmm", $offset)                              # Place the value of the content variable at the byte|word|double word|quad word in the numbered zmm register
 }

sub Nasm::X86::Variable::qIntoZ($$$)                                            # Place the value of the content variable at the quad word in the numbered zmm register.
 {my ($content, $zmm, $offset) = @_;                                            # Variable with content, numbered zmm, offset in bytes
  checkZmmRegister $zmm;
  $content->putBwdqIntoMm('q', "zmm$zmm", $offset)                              # Place the value of the content variable at the byte|word|double word|quad word in the numbered zmm register
 }

#D2 Stack                                                                       # Push and pop variables to and from the stack

#sub Nasm::X86::Variable::push($)                                                # Push a variable onto the stack.
# {my ($variable) = @_;                                                          # Variable
#  PushR rax; Push rax;                                                          # Make a slot on the stack and save rax
#  $variable->setReg(rax);                                                       # Variable to rax
#  my $s = RegisterSize rax;                                                     # Size of rax
#  Mov "[rsp+$s]", rax;                                                          # Move variable to slot
#  PopR rax;                                                                     # Remove rax to leave variable on top of the stack
# }
#
#sub Nasm::X86::Variable::pop($)                                                 # Pop a variable from the stack.
# {my ($variable) = @_;                                                          # Variable
#  PushR rax;                                                                    # Liberate a register
#  my $s = RegisterSize rax;                                                     # Size of rax
#  Mov rax, "[rsp+$s]";                                                          # Load from stack
#  $variable->getReg(rax);                                                       # Variable to rax
#  PopR rax;                                                                     # Remove rax to leave variable on top of the stack
#  Add rsp, $s;                                                                  # Remove variable from stack
# }

#D2 Memory                                                                      # Actions on memory described by variables

sub Nasm::X86::Variable::clearMemory($$)                                        # Clear the memory described in this variable.
 {my ($address, $size) = @_;                                                    # Address of memory to clear, size of the memory to clear
  &ClearMemory(size=>$size, address=>$address);                                 # Free the memory
 }

sub Nasm::X86::Variable::copyMemory($$$)                                        # Copy from one block of memory to another.
 {my ($target, $source, $size) = @_;                                            # Address of target, address of source, length to copy
  @_ == 3 or confess "Three parameters";
#  $target->name eq q(target) or confess "Need target";
#  $source->name eq q(source) or confess "Need source";
#  $size  ->name eq q(size)   or confess "Need size";
  &CopyMemory(target => $target, source => $source, size => $size);             # Copy the memory
 }

sub Nasm::X86::Variable::printMemoryInHexNL($$$)                                # Write, in hexadecimal, the memory addressed by a variable to stdout or stderr.
 {my ($address, $channel, $size) = @_;                                          # Address of memory, channel to print on, number of bytes to print
  @_ == 3 or confess "Three parameters";
#  $address->name eq q(address) or confess "Need address";
#  $size   ->name eq q(size)    or confess "Need size";
  PushR (rax, rdi);
  $address->setReg(rax);
  $size->setReg(rdi);
  &PrintMemoryInHex($channel);
  &PrintNL($channel);
  PopR;
 }

sub Nasm::X86::Variable::printErrMemoryInHexNL($$)                              # Write the memory addressed by a variable to stderr.
 {my ($address, $size) = @_;                                                    # Address of memory, number of bytes to print
  $address->printMemoryInHexNL($stderr, $size);
 }

sub Nasm::X86::Variable::printOutMemoryInHexNL($$)                              # Write the memory addressed by a variable to stdout.
 {my ($address, $size) = @_;                                                    # Address of memory, number of bytes to print
  $address->printMemoryInHexNL($stdout, $size);
 }

sub Nasm::X86::Variable::freeMemory($$)                                         # Free the memory addressed by this variable for the specified length.
 {my ($address, $size) = @_;                                                    # Address of memory to free, size of the memory to free
  $address->name eq q(address) or confess "Need address";
  $size   ->name eq q(size)    or confess "Need size";
  &FreeMemory(size=>$size, address=>$address);                                  # Free the memory
 }

sub Nasm::X86::Variable::allocateMemory(@)                                      # Allocate the specified amount of memory via mmap and return its address.
 {my ($size) = @_;                                                              # Size
  @_ >= 1 or confess;
  $size->name eq q(size) or confess "Need size";
  &AllocateMemory(size => $size, my $a = V(address));
  $a
 }

#D2 Structured Programming with variables                                       # Structured programming operations driven off variables.

sub Nasm::X86::Variable::for($&)                                                # Iterate a block a variable number of times.
 {my ($limit, $block) = @_;                                                     # Number of times, Block
  @_ == 2 or confess "Two parameters";
  Comment "Variable::For $limit";
  my $index = V(q(index), 0);                                                   # The index that will be incremented
  my $start = Label;
  my $next  = Label;
  my $end   = Label;
  SetLabel $start;                                                              # Start of loop

  If $index >= $limit, sub {Jge $end};                                          # Condition

  &$block($index, $start, $next, $end);                                         # Execute block

  SetLabel $next;                                                               # Next iteration
  $index++;                                                                     # Increment
  Jmp $start;
  SetLabel $end;
 }

#D1 Stack                                                                       # Manage data on the stack

#D2 Push, Pop, Peek                                                             # Generic versions of push, pop, peek

sub PushRR(@)                                                                   #P Push registers onto the stack without tracking.
 {my (@r) = @_;                                                                 # Register
  my $w = RegisterSize rax;
  for my $r(map {registerNameFromNumber $_} @r)
   {my $size = RegisterSize $r;
    $size or confess "No such register: $r";
    if    ($size > $w)                                                          # Wide registers
     {Sub rsp, $size;
      Vmovdqu32 "[rsp]", $r;
     }
    elsif ($r =~ m(\Ak))                                                        # Mask as they do not respond to push
     {Sub rsp, $size;
      Kmovq "[rsp]", $r;
     }
    else                                                                        # Normal register
     {Push $r;
     }
   }
 }

my @PushR;                                                                      # Track pushes

sub PushR(@)                                                                    #P Push registers onto the stack.
 {my (@r) = @_;                                                                 # Registers
  push @PushR, [@r];
# CommentWithTraceBack;
  PushRR   @r;                                                                  # Push
  scalar(@PushR)                                                                # Stack depth
 }

sub PushRAssert($)                                                              #P Check that the stack ash the expected depth.
 {my ($depth) = @_;                                                             # Expected Depth
  confess "Stack mismatch" unless $depth == scalar(@PushR)
 }

sub PopRR(@)                                                                    #P Pop registers from the stack without tracking.
 {my (@r) = @_;                                                                 # Register
  my $w = RegisterSize rax;
  for my $r(reverse map{registerNameFromNumber $_}  @r)                         # Pop registers in reverse order
   {my $size = RegisterSize $r;
    if    ($size > $w)
     {Vmovdqu32 $r, "[rsp]";
      Add rsp, $size;
     }
    elsif ($r =~ m(\Ak))
     {Kmovq $r, "[rsp]";
      Add rsp, $size;
     }
    else
     {Pop $r;
     }
   }
 }

sub PopR(@)                                                                     # Pop registers from the stack. Use the last stored set if none explicitly supplied.  Pops are done in reverse order to match the original pushing order.
 {my (@r) = @_;                                                                 # Register
  @PushR or confess "No stacked registers";
  my $r = pop @PushR;
  dump(\@r) eq dump($r) or confess "Mismatched registers:\n".dump($r, \@r) if @r;
  PopRR @$r;                                                                    # Pop registers from the stack without tracking
# CommentWithTraceBack;
 }

sub PopEax()                                                                    # We cannot pop a double word from the stack in 64 bit long mode using pop so we improvise.
 {my $l = RegisterSize eax;                                                     # Eax is half rax
  Mov eax, "[rsp]";
  Add rsp, RegisterSize eax;
 }

sub PeekR($)                                                                    # Peek at register on stack.
 {my ($r) = @_;                                                                 # Register
  my $w = RegisterSize rax;
  my $size = RegisterSize $r;
  if    ($size > $w)                                                            # X|y|zmm*
   {Vmovdqu32 $r, "[rsp]";
   }
  else                                                                          # General purpose 8 byte register
   {Mov $r, "[rsp]";
   }
 }

my @PushZmm;                                                                    # Zmm pushes

sub PushZmm(@)                                                                  # Push several zmm registers.
 {my (@Z) = @_;                                                                 # Zmm register numbers
  if (@Z)
   {my @z = zmm @Z;
    my $w = RegisterSize zmm0;
    Sub rsp, @z * $w;
    for my $i(keys @z)
     {Vmovdqu64 "[rsp+$w*$i]", $z[$i];
     }
    push @PushZmm, [@Z];
   }
 }

sub PopZmm                                                                      # Pop zmm registers.
 {@PushZmm or confess "No Zmm registers saved";
  my $z = pop @PushZmm;
  my @z = zmm @$z;
  my $w = RegisterSize zmm0;
  for my $i(keys @z)
   {Vmovdqu64 $z[$i], "[rsp+$w*$i]";
   }
  Add rsp, @z * $w;
 }

my @PushMask;                                                                   # Mask pushes

sub PushMask(@)                                                                 # Push several Mask registers.
 {my (@M) = @_;                                                                 # Mask register numbers
  if (@M)
   {my @m = map {"k$_"} @M;
    my $w = RegisterSize k0;
    Sub rsp, @m * $w;
    for my $i(keys @m)
     {Kmovq "[rsp+$w*$i]", $m[$i];
     }
    push @PushMask, [@M];
   }
 }

sub PopMask                                                                     # Pop Mask registers.
 {@PushMask or confess "No Mask registers saved";
  my $m = pop @PushMask;
  my @m = map {"k$_"} @$m;
  my $w = RegisterSize k0;
  for my $i(keys @m)
   {Kmovq $m[$i], "[rsp+$w*$i]";
   }
  Add rsp, @m * $w;
 }

#D2 Declarations                                                                # Declare variables and structures

#D3 Structures                                                                  # Declare a structure

sub Structure()                                                                 # Create a structure addressed by a register.
 {@_ == 0 or confess;
  my $local = genHash(__PACKAGE__."::Structure",
    size      => 0,
    variables => [],
   );
 }

sub Nasm::X86::Structure::field($$;$)                                           # Add a field of the specified length with an optional comment.
 {my ($structure, $length, $comment) = @_;                                      # Structure data descriptor, length of data, optional comment
  @_ >= 2 or confess;
  my $variable = genHash(__PACKAGE__."::StructureField",
    structure  => $structure,                                                   # Structure containing the field
    loc        => $structure->size,                                             # Offset of the field
    size       => $length,                                                      # Size of the field
    comment    => $comment                                                      # Comment describing the purpose of the field
   );
  $structure->size += $length;                                                  # Update size of local data
  push $structure->variables->@*, $variable;                                    # Save variable
  $variable
 }

sub Nasm::X86::StructureField::addr($;$)                                        # Address a field in a structure by either the default register or the named register.
 {my ($field, $register) = @_;                                                  # Field, optional address register else rax
  @_ <= 2 or confess;
  my $loc = $field->loc;                                                        # Offset of field in structure
  my $reg = $register || 'rax';                                                 # Register locating the structure
  "[$loc+$reg]"                                                                 # Address field
 }

sub All8Structure($)                                                            # Create a structure consisting of 8 byte fields.
 {my ($N) = @_;                                                                 # Number of variables required
  @_ == 1 or confess "One parameter";
  my $s = Structure;                                                            # Structure of specified size based on specified register
  my @f;
  my $z = RegisterSize rax;
  for(1..$N)                                                                    # Create the variables
   {push @f, $s->field($z);
   }
  ($s, @f)                                                                      # Structure, fields
 }

#D3 Stack Frame                                                                 # Declare local variables in a frame on the stack

sub LocalData22()                                                               # Map local data.
 {@_ == 0 or confess;
  my $local = genHash(__PACKAGE__."::LocalData",
    size      => 0,
    variables => [],
   );
 }

sub Nasm::X86::LocalData::start22($)                                            # Start a local data area on the stack.
 {my ($local) = @_;                                                             # Local data descriptor
  @_ == 1 or confess "One parameter";
  my $size = $local->size;                                                      # Size of local data
  Push rbp;
  Mov rbp,rsp;
  Sub rsp, $size;
 }

sub Nasm::X86::LocalData::free22($)                                             # Free a local data area on the stack.
 {my ($local) = @_;                                                             # Local data descriptor
  @_ == 1 or confess "One parameter";
  Mov rsp, rbp;
  Pop rbp;
 }

sub Nasm::X86::LocalData::variable22($$;$)                                      # Add a local variable.
 {my ($local, $length, $comment) = @_;                                          # Local data descriptor, length of data, optional comment
  @_ >= 2 or confess;
  my $variable = genHash(__PACKAGE__."::LocalVariable",
    loc        => $local->size,
    size       => $length,
    comment    => $comment
   );
  $local->size += $length;                                                      # Update size of local data
  $variable
 }

sub Nasm::X86::LocalVariable::stack22($)                                        # Address a local variable on the stack.
 {my ($variable) = @_;                                                          # Variable
  @_ == 1 or confess "One parameter";
  my $l = $variable->loc;                                                       # Location of variable on stack
  my $S = $variable->size;
  my $s = $S == 8 ? 'qword' : $S == 4 ? 'dword' : $S == 2 ? 'word' : 'byte';    # Variable size
  "${s}[rbp-$l]"                                                                # Address variable - offsets are negative per Tino
 }

sub Nasm::X86::LocalData::allocate8($@)                                         # Add some 8 byte local variables and return an array of variable definitions.
 {my ($local, @comments) = @_;                                                  # Local data descriptor, optional comment
  my @v;
  for my $c(@comments)
   {push @v, Nasm::X86::LocalData::variable($local, 8, $c);
   }
  wantarray ? @v : $v[-1];                                                      # Avoid returning the number of elements accidently
 }

sub AllocateAll8OnStack22($)                                                    # Create a local data descriptor consisting of the specified number of 8 byte local variables and return an array: (local data descriptor,  variable definitions...).
 {my ($N) = @_;                                                                 # Number of variables required
  my $local = LocalData22;                                                      # Create local data descriptor
  my @v;
  for(1..$N)                                                                    # Create the variables
   {my $v = $local->variable(RegisterSize(rax));
    push @v, $v->stack;
   }
  $local->start;                                                                # Create the local data area on the stack
  ($local, @v)
 }

#D1 Operating system                                                            # Interacting with the operating system.

#D2 Processes                                                                   # Create and manage processes

sub Fork()                                                                      # Fork: create and execute a copy of the current process.
 {@_ == 0 or confess;
  Comment "Fork";
  Mov rax, 57;
  Syscall
 }

sub GetPid()                                                                    # Get process identifier.
 {@_ == 0 or confess;
  Comment "Get Pid";

  Mov rax, 39;
  Syscall
 }

sub GetPidInHex()                                                               # Get process identifier in hex as 8 zero terminated bytes in rax.
 {@_ == 0 or confess;
  Comment "Get Pid";
  my $hexTranslateTable = hexTranslateTable;

  my $s = Subroutine2
   {SaveFirstFour;
    Mov rax, 39;                                                                # Get pid
    Syscall;
    Mov rdx, rax;                                                               # Content to be printed

    ClearRegisters rax;                                                         # Save a trailing 00 on the stack
    Push ax;
    for my $i(reverse 5..7)
     {my $s = 8*$i;
      Mov rdi,rdx;
      Shl rdi,$s;                                                               # Push selected byte high
      Shr rdi,56;                                                               # Push select byte low
      Shl rdi,1;                                                                # Multiply by two because each entry in the translation table is two bytes long
      Mov ax, "[$hexTranslateTable+rdi]";
      Push ax;
     }
    Pop rax;                                                                    # Get result from stack
    RestoreFirstFourExceptRax;
   } name => "GetPidInHex";

  $s->call;
 }

sub GetPPid()                                                                   # Get parent process identifier.
 {@_ == 0 or confess;
  Comment "Get Parent Pid";

  Mov rax, 110;
  Syscall
 }

sub GetUid()                                                                    # Get userid of current process.
 {@_ == 0 or confess;
  Comment "Get User id";

  Mov rax, 102;
  Syscall
 }

sub WaitPid()                                                                   # Wait for the pid in rax to complete.
 {@_ == 0 or confess;
  Comment "WaitPid - wait for the pid in rax";

    my $s = Subroutine2
   {SaveFirstSeven;
    Mov rdi,rax;
    Mov rax, 61;
    Mov rsi, 0;
    Mov rdx, 0;
    Mov r10, 0;
    Syscall;
    RestoreFirstSevenExceptRax;
   } name => "WaitPid";

  $s->call;
 }

sub ReadTimeStampCounter()                                                      # Read the time stamp counter and return the time in nanoseconds in rax.
 {@_ == 0 or confess;

  my $s = Subroutine2
   {Comment "Read Time-Stamp Counter";
    PushR rdx;
    ClearRegisters rax;
    Cpuid;
    Rdtsc;
    Shl rdx,32;
    Or rax,rdx;
    PopR;
   } name => "ReadTimeStampCounter";

  $s->call;
 }

#D2 Memory                                                                      # Allocate and print memory

sub PrintMemoryInHex($)                                                         # Dump memory from the address in rax for the length in rdi on the specified channel. As this method prints in blocks of 8 up to 7 bytes will be missing from the end unless the length is a multiple of 8 .
 {my ($channel) = @_;                                                           # Channel
  @_ == 1 or confess "One parameter";
  Comment "Print out memory in hex on channel: $channel";

  my $s = Subroutine2
   {my $size = RegisterSize rax;
    SaveFirstFour;

    Test rdi, 0x7;                                                              # Round the number of bytes to be printed
    IfNz
    Then                                                                        # Round up
     {Add rdi, 8;
     };
    And rdi, 0x3f8;                                                             # Limit the number of bytes to be printed to 1024

    Mov rsi, rax;                                                               # Position in memory
    Lea rdi,"[rax+rdi-$size+1]";                                                # Upper limit of printing with an 8 byte register
    For                                                                         # Print string in blocks
     {Mov rax, "[rsi]";
      Bswap rax;
      PrintRaxInHex($channel);
      Mov rdx, rsi;
      Add rdx, $size;
      Cmp rdx, rdi;
      IfLt
      Then
       {PrintString($channel, "  ");
       }
     } rsi, rdi, $size;
    RestoreFirstFour;
   } name=> "PrintOutMemoryInHexOnChannel$channel";

  $s->call;
 }

sub PrintErrMemoryInHex                                                         # Dump memory from the address in rax for the length in rdi on stderr.
 {@_ == 0 or confess;
  PrintMemoryInHex($stderr);
 }

sub PrintOutMemoryInHex                                                         # Dump memory from the address in rax for the length in rdi on stdout.
 {@_ == 0 or confess;
  PrintMemoryInHex($stdout);
 }

sub PrintErrMemoryInHexNL                                                       # Dump memory from the address in rax for the length in rdi and then print a new line.
 {@_ == 0 or confess;
  PrintMemoryInHex($stderr);
  PrintNL($stderr);
 }

sub PrintOutMemoryInHexNL                                                       # Dump memory from the address in rax for the length in rdi and then print a new line.
 {@_ == 0 or confess;
  PrintMemoryInHex($stdout);
  PrintNL($stdout);
 }

sub PrintMemory_InHex($)                                                        # Dump memory from the address in rax for the length in rdi on the specified channel. As this method prints in blocks of 8 up to 7 bytes will be missing from the end unless the length is a multiple of 8 .
 {my ($channel) = @_;                                                           # Channel
  @_ == 1 or confess "One parameter";
  Comment "Print out memory in hex on channel: $channel";

  my $s = Subroutine2
   {my $size = RegisterSize rax;
    SaveFirstFour;

    Test rdi, 0x7;                                                              # Round the number of bytes to be printed
    IfNz
    Then                                                                        # Round up
     {Add rdi, 8;
     };
    And rdi, 0x3f8;                                                             # Limit the number of bytes to be printed to 1024

    Mov rsi, rax;                                                               # Position in memory
    Lea rdi,"[rax+rdi-$size+1]";                                                # Upper limit of printing with an 8 byte register
    For                                                                         # Print string in blocks
     {Mov rax, "[rsi]";
      Bswap rax;
      PrintRax_InHex($channel);
      Mov rdx, rsi;
      Add rdx, $size;
      Cmp rdx, rdi;
      IfLt
      Then
       {PrintString($channel, "  ");
       }
     } rsi, rdi, $size;
    RestoreFirstFour;
   } name=> "PrintOutMemory_InHexOnChannel$channel";

  $s->call;
 }

sub PrintErrMemory_InHex                                                        # Dump memory from the address in rax for the length in rdi on stderr.
 {@_ == 0 or confess;
  PrintMemory_InHex($stderr);
 }

sub PrintOutMemory_InHex                                                        # Dump memory from the address in rax for the length in rdi on stdout.
 {@_ == 0 or confess;
  PrintMemory_InHex($stdout);
 }

sub PrintErrMemory_InHexNL                                                      # Dump memory from the address in rax for the length in rdi and then print a new line.
 {@_ == 0 or confess;
  PrintMemory_InHex($stderr);
  PrintNL($stderr);
 }

sub PrintOutMemory_InHexNL                                                      # Dump memory from the address in rax for the length in rdi and then print a new line.
 {@_ == 0 or confess;
  PrintMemory_InHex($stdout);
  PrintNL($stdout);
 }

sub PrintMemory($)                                                              # Print the memory addressed by rax for a length of rdi on the specified channel.
 {my ($channel) = @_;                                                           # Channel
  @_ == 1 or confess "One parameter";

  my $s = Subroutine2
   {Comment "Print memory on channel: $channel";
    SaveFirstFour rax, rdi;
    Mov rsi, rax;
    Mov rdx, rdi;
    Mov rax, 1;
    Mov rdi, $channel;
    Syscall;
    RestoreFirstFour();
   } name => "PrintOutMemoryOnChannel$channel";

  $s->call;
 }

sub PrintMemoryNL                                                               # Print the memory addressed by rax for a length of rdi on the specified channel followed by a new line.
 {my ($channel) = @_;                                                           # Channel
  @_ == 1 or confess "One parameter";
  PrintMemory($channel);
  PrintNL($channel);
 }

sub PrintErrMemory                                                              # Print the memory addressed by rax for a length of rdi on stderr.
 {@_ == 0 or confess;
  PrintMemory($stdout);
 }

sub PrintOutMemory                                                              # Print the memory addressed by rax for a length of rdi on stdout.
 {@_ == 0 or confess;
  PrintMemory($stdout);
 }

sub PrintErrMemoryNL                                                            # Print the memory addressed by rax for a length of rdi followed by a new line on stderr.
 {@_ == 0 or confess;
  PrintErrMemory;
  PrintErrNL;
 }

sub PrintOutMemoryNL                                                            # Print the memory addressed by rax for a length of rdi followed by a new line on stdout.
 {@_ == 0 or confess;
  PrintOutMemory;
  PrintOutNL;
 }

sub AllocateMemory(@)                                                           # Allocate the variable specified amount of memory via mmap and return its address as a variable.
 {my ($size) = @_;                                                              # Size as a variable
  @_ == 1 or confess "Size required";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    Comment "Allocate memory";
    SaveFirstSeven;

    my %d = getSystemConstantsFromIncludeFile "linux/mman.h",                   # Memory map constants
      qw(MAP_PRIVATE MAP_ANONYMOUS PROT_WRITE PROT_READ);

    my $pa = $d{MAP_PRIVATE} | $d{MAP_ANONYMOUS};
    my $wr = $d{PROT_WRITE}  | $d{PROT_READ};

    Mov rax, 9;                                                                 # Memory map
    $$p{size}->setReg(rsi);                                                     # Amount of memory
    Xor rdi, rdi;                                                               # Anywhere
    Mov rdx, $wr;                                                               # Read write protections
    Mov r10, $pa;                                                               # Private and anonymous map
    Mov r8,  -1;                                                                # File descriptor for file backing memory if any
    Mov r9,  0;                                                                 # Offset into file
    Syscall;
    Cmp rax, -1;                                                                # Check return code
    IfEq(sub
     {PrintErrString "Cannot allocate memory, return code -1";
      $$p{size}->errNL;
      Exit(1);
     });
    Cmp eax, 0xffffffea;                                                        # Check return code
    IfEq(sub
     {PrintErrString "Cannot allocate memory, return code 0xffffffea";
      $$p{size}->errNL;
      Exit(1);
     });
    Cmp rax, -12;                                                               # Check return code
    IfEq(sub
     {PrintErrString "Cannot allocate memory, return code -12";
      $$p{size}->errNL;
      Exit(1);
     });
     $$p{address}->getReg(rax);                                                 # Amount of memory

    RestoreFirstSeven;
   } parameters=>[qw(address size)], name => 'AllocateMemory';

  $s->call(parameters=>{size=>$size, address => my $address = V address => 0});

  $address;
 }

sub FreeMemory(@)                                                               # Free memory specified by variables.
 {my ($address, $size) = @_;                                                    # Variable address of memory, variable size of memory
  @_ == 2 or confess "Address, size to free";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    SaveFirstFour;
    Mov rax, 11;                                                                # Munmap
    $$p{address}->setReg(rdi);                                                  # Address
    $$p{size}   ->setReg(rsi);                                                  # Length
    Syscall;
    RestoreFirstFour;
   } parameters=>[qw(size address)], name=> 'FreeMemory';

  $s->call(parameters => {address=>$address, size=>$size});
 }

sub ClearMemory($$)                                                             # Clear memory wit a variable address and variable length
 {my ($address, $size) = @_;                                                    # Variables
  @_ == 2 or confess "address, size required";
  Comment "Clear memory";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    PushR (zmm0, rax, rdi, rsi, rdx);
    $$p{address}->setReg(rax);
    $$p{size}   ->setReg(rdi);
    Lea rdx, "[rax+rdi]";                                                       # Address of upper limit of buffer

    ClearRegisters zmm0;                                                        # Clear the register that will be written into memory

    Mov rsi, rdi;                                                               # Modulus the size of zmm
    And rsi, 0x3f;                                                              # Remainder modulo 64
    Cmp rsi, 0;                                                                 # Test remainder
    IfNz sub                                                                    # Need to align so that the rest of the clear can be done in full zmm blocks
     {PushR k7;
      V(align, rsi)->setMaskFirst(k7);                                          # Set mask bits
      Vmovdqu8 "[rax]{k7}", zmm0;                                               # Masked move to memory
      PopR;
      Add rax, rsi;                                                             # Update point to clear from
      Sub rdi, rsi;                                                             # Reduce clear length
     };

    For                                                                         # Clear remaining memory in full zmm blocks
     {Vmovdqu64 "[rax]", zmm0;
     } rax, rdx, RegisterSize zmm0;

    PopR;
   } parameters=>[qw(size address)], name => 'ClearMemory';

  $s->call(parameters => {address => $address, size => $size});
 }

#sub MaskMemory22(@)                                                             # Write the specified byte into locations in the target mask that correspond to the locations in the source that contain the specified byte.
# {my (@variables) = @_;                                                         # Variables
#  @_ >= 2 or confess;
#  Comment "Clear memory";
#
#  my $size = RegisterSize zmm0;
#
#  my $s = Subroutine
#   {my ($p) = @_;                                                               # Parameters
#    PushR (k6, k7, rax, rdi, rsi, rdx, r8, r9, r10, zmm0, zmm1, zmm2);
#    $$p{source}->setReg(rax);
#    $$p{mask}  ->setReg(rdx);
#    $$p{match} ->setReg(rsi);
#    $$p{set}   ->setReg(rdi);
#    $$p{size}  ->setReg(r8);
#    Lea r9, "[rax+r8]";                                                         # Address of upper limit of source
#
#    Vpbroadcastb zmm1, rsi;                                                     # Character to match
#    Vpbroadcastb zmm2, rdi;                                                     # Character to write into mask
#
#    Mov r10, r8;                                                                # Modulus the size of zmm
#    And r10, 0x3f;
#    Test r10, r10;
#    IfNz sub                                                                    # Need to align so that the rest of the clear can be done in full zmm blocks
#     {V(align, r10)->setMaskFirst(k7);                                          # Set mask bits
#      Vmovdqu8 "zmm0\{k7}", "[rax]";                                            # Load first incomplete block of source
#      Vpcmpub  "k6{k7}", zmm0, zmm1, 0;                                         # Characters in source that match
#      Vmovdqu8 "[rdx]{k6}", zmm2;                                               # Write set byte into mask at match points
#      Add rax, r10;                                                             # Update point to mask from
#      Add rdx, r10;                                                             # Update point to mask to
#      Sub  r8, r10;                                                             # Reduce mask length
#     };
#
#    For                                                                         # Clear remaining memory in full zmm blocks
#     {Vmovdqu8 zmm0, "[rax]";                                                   # Load complete block of source
#      Vpcmpub  "k7", zmm0, zmm1, 0;                                             # Characters in source that match
#      Vmovdqu8 "[rdx]{k7}", zmm2;                                               # Write set byte into mask at match points
#      Add rdx, $size;                                                           # Update point to mask to
#     } rax, r9, $size;
#
#    PopR;
#   } [qw(size source mask match set)];                                          # Match is the character to match on in the source, set is the character to write into the mask at the corresponding position.
#
#  $s->call(@variables);
# }

#sub MaskMemoryInRange4_22(@)                                                    # Write the specified byte into locations in the target mask that correspond to the locations in the source that contain 4 bytes in the specified range.
# {my (@variables) = @_;                                                         # Variables
#  @_ >= 6 or confess;
#  Comment "Clear memory";
#
#  my $size = RegisterSize zmm0;
#
#  my $s = Subroutine
#   {my ($p) = @_;                                                               # Parameters
#    PushR (k4, k5, k6, k7, zmm(0..9), map{"r$_"} qw(ax di si dx), 8..15);
#    $$p{source}->setReg(rax);
#    $$p{mask}  ->setReg(rdx);
#    $$p{low}   ->setReg(r10);
#    $$p{high}  ->setReg(r11);
#    $$p{set}   ->setReg(rdi);
#    $$p{size}  ->setReg(rsi);
#
#    Vpbroadcastb zmm1, rdi;                                                     # Character to write into mask
#                Vpbroadcastb zmm2, r10;                                         # Character 1 low
#    Shr r10, 8; Vpbroadcastb zmm3, r10;                                         # Character 2 low
#    Shr r10, 8; Vpbroadcastb zmm4, r10;                                         # Character 3 low
#    Shr r10, 8; Vpbroadcastb zmm5, r10;                                         # Character 4 low
#                Vpbroadcastb zmm6, r11;                                         # Character 1 high
#    Shr r11, 8; Vpbroadcastb zmm7, r11;                                         # Character 2 high
#    Shr r11, 8; Vpbroadcastb zmm8, r11;                                         # Character 3 high
#    Shr r11, 8; Vpbroadcastb zmm9, r11;                                         # Character 4 high
#    Lea r8, "[rax+rsi]";                                                        # Address of upper limit of source
#
#    my sub check($$)                                                            # Check a character
#     {my ($z, $f) = @_;                                                         # First zmm, finished label
#      my $Z = $z + 4;
#      Vpcmpub  "k6{k7}", zmm0, "zmm$z", 5;                                      # Greater than or equal
#      Vpcmpub  "k7{k6}", zmm0, "zmm$Z", 2;                                      # Less than or equal
#      Ktestq k7, k7;
#      Jz $f;                                                                    # No match
#      Kshiftlq k7, k7, 1;                                                       # Match - move up to next character
#     };
#
#    my sub last4()                                                              # Expand each set bit four times
#     {Kshiftlq k6, k7, 1;  Kandq k7, k6, k7;                                    # We have found a character in the specified range
#      Kshiftlq k6, k7, 2;  Kandq k7, k6, k7;                                    # Last four
#     };
#
#    For                                                                         # Mask remaining memory in full zmm blocks
#     {my $finished = Label;                                                     # Point where we have finished the initial comparisons
#      Vmovdqu8 zmm0, "[rax]";                                                   # Load complete block of source
#      Kxnorq k7, k7, k7;                                                        # Complete block - sets register to all ones
#      check($_, $finished) for 2..5;  last4;                                    # Check a range
#
#      Vmovdqu8 "[rdx]{k7}", zmm1;                                               # Write set byte into mask at match points
#      Add rdx, $size;                                                           # Update point to mask to
#      SetLabel $finished;
#     } rax, r8, $size;
#
#
#    Mov r10, rsi; And r10, 0x3f;                                                # Modulus the size of zmm
#    Test r10, r10;
#    IfNz sub                                                                    # Need to align so that the rest of the mask can be done in full zmm blocks
#     {my $finished = Label;                                                     # Point where we have finished the initial comparisons
#      V(align, r10)->setMaskFirst(k7);                                          # Set mask bits
#      Vmovdqu8 "zmm0\{k7}", "[rax]";                                            # Load first incomplete block of source
#      check($_, $finished) for 2..5;  last4;                                    # Check a range
#      Vmovdqu8 "[rdx]{k7}", zmm1;                                               # Write set byte into mask at match points
#      Add rax, r10;                                                             # Update point to mask from
#      Add rdx, r10;                                                             # Update point to mask to
#      Sub  r8, r10;                                                             # Reduce mask length
#      SetLabel $finished;
#     };
#
#    PopR;
#   } [qw(size source mask set low high)];
#
#  $s->call(@variables);
# } # MaskMemoryInRange4

sub CopyMemory($$$)                                                             # Copy memory.
 {my ($source, $target, $size) = @_;                                            # Source address variable, target address variable, length variable
  @_ == 3 or confess "Source, target, size required";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    SaveFirstSeven;
    $$p{source}->setReg(rsi);
    $$p{target}->setReg(rax);
    $$p{size}  ->setReg(rdi);
    ClearRegisters rdx;
    For                                                                         # Clear memory
     {Mov "r8b", "[rsi+rdx]";
      Mov "[rax+rdx]", "r8b";
     } rdx, rdi, 1;
    RestoreFirstSeven;
   } parameters=>[qw(source target size)], name => 'CopyMemory';

  $s->call(parameters=>{source => $source, target=>$target, size=>$size});
 }

#D2 Files                                                                       # Interact with the operating system via files.

sub OpenRead()                                                                  # Open a file, whose name is addressed by rax, for read and return the file descriptor in rax.
 {@_ == 0 or confess "Zero parameters";

  my $s = Subroutine2
   {my %s = getSystemConstantsFromIncludeFile  "fcntl.h", qw(O_RDONLY);         # Constants for reading a file

    SaveFirstFour;
    Mov rdi,rax;
    Mov rax,2;
    Mov rsi, $s{O_RDONLY};
    Xor rdx,rdx;
    Syscall;
    RestoreFirstFourExceptRax;
   } name=> "OpenRead";

  $s->call;
 }

sub OpenWrite()                                                                 # Create the file named by the terminated string addressed by rax for write.
 {@_ == 0 or confess "Zero parameters";

  my $s = Subroutine2
   {my %s = getSystemConstantsFromIncludeFile                                   # Constants for creating a file
      "fcntl.h", qw(O_CREAT O_WRONLY);
    my $write = $s{O_WRONLY} | $s{O_CREAT};

    SaveFirstFour;
    Mov rdi, rax;
    Mov rax, 2;
    Mov rsi, $write;
    Mov rdx, 0x1c0;                                                             # Permissions: u=rwx  1o=x 4o=r 8g=x 10g=w 20g=r 40u=x 80u=r 100u=r 200=T 400g=S 800u=S #0,2,1000, nothing
    Syscall;

    RestoreFirstFourExceptRax;
   } name=> "OpenWrite";

  $s->call;
 }

sub CloseFile()                                                                 # Close the file whose descriptor is in rax.
 {@_ == 0 or confess "Zero parameters";

  my $s = Subroutine2
   {Comment "Close a file";
    SaveFirstFour;
    Mov rdi, rax;
    Mov rax, 3;
    Syscall;
    RestoreFirstFourExceptRax;
   } name=> "CloseFile";

  $s->call;
 }

sub StatSize()                                                                  # Stat a file whose name is addressed by rax to get its size in rax.
 {@_ == 0 or confess "Zero parameters";

  my ($F, $S) = (q(sys/stat.h), q(struct stat));                                # Get location of struct stat.st_size field
  my $Size = getStructureSizeFromIncludeFile $F, $S;
  my $off  = getFieldOffsetInStructureFromIncludeFile $F, $S, q(st_size);

  my $s = Subroutine2
   {Comment "Stat a file for size";
    SaveFirstFour rax;
    Mov rdi, rax;                                                               # File name
    Mov rax,4;
    Lea rsi, "[rsp-$Size]";
    Syscall;
    Mov rax, "[$off+rsp-$Size]";                                                # Place size in rax
    RestoreFirstFourExceptRax;
   } name=> "StatSize";

  $s->call;
 }

sub ReadChar()                                                                  # Read a character from stdin and return it in rax else return -1 in rax if no character was read.
 {@_ == 0 or confess "Zero parameters";
  my $s = Subroutine2
   {my ($p) = @_;
    SaveFirstFour;                                                              # Generated code

    Mov rax, 0;                                                                 # Read
    Mov rdi, 0;                                                                 # Stdin
    Lea rsi, "[rsp-8]";                                                         # Make space on stack
    Mov rdx, 1;                                                                 # One character
    Syscall;

    Cmp rax, 1;
    IfEq
    Then
     {Mov al, "[rsp-8]";
     },
    Else
     {Mov rax, -1;
     };

    RestoreFirstFourExceptRax;
   } name => 'ReadChar';

  $s->call
 }

sub ReadLine()                                                                  # Reads up to 8 characters followed by a terminating return and place them into rax.
 {@_ == 0 or confess "Zero parameters";
  my $s = Subroutine2
   {my ($p) = @_;
    PushR rcx, r14, r15;
    ClearRegisters rax, rcx, r14, r15;

    (V max => RegisterSize(rax))->for(sub                                       # Read each character
     {my ($index, $start, $next, $end) = @_;

      ReadChar;
      Cmp rax, 0xf0;                                                            # Too high
      IfGe Then {Jmp $end};
      Cmp rax, 0xa;                                                             # Too low
      IfLe Then {Jmp $end};
      $index->setReg(rcx);
      Shl rcx, 3;
      Shl rax, cl;                                                              # Move into position
      Or r15, rax;
      Add rcx, $bitsInByte;
     });

    Mov rax, r15;                                                               # Return result in rax
    PopR;
   } name => 'ReadLine';

  $s->call
 }

sub ReadInteger()                                                               # Reads an integer in decimal and returns it in rax.
 {@_ == 0 or confess "Zero parameters";
  my $s = Subroutine2
   {my ($p) = @_;
    PushR r15;
    ClearRegisters rax, r15;

    (V max => RegisterSize(rax))->for(sub                                       # Read each character
     {my ($index, $start, $next, $end) = @_;

      ReadChar;
      Cmp rax, 0x3A;                                                            # Too high
      IfGe Then {Jmp $end};
      Cmp rax, 0x29;                                                            # Too low
      IfLe Then {Jmp $end};
      Imul r15, 10;                                                             # Move into position
      Sub rax, 0x30;
      Add r15, rax;
     });

    Mov rax, r15;                                                               # Return result in rax
    PopR;
   } name => 'ReadInteger';

  $s->call
 }

sub ReadFile(@)                                                                 # Read a file into memory.
 {my ($File) = @_;                                                              # Variable addressing a zero terminated string naming the file
  @_ == 1 or confess "One parameter required";

  my $s = Subroutine2
   {my ($p) = @_;
    Comment "Read a file into memory";
    SaveFirstSeven;                                                             # Generated code
    my $size = V(size);
    my $fdes = V(fdes);

    $$p{file}->setReg(rax);                                                     # File name

    StatSize;                                                                   # File size
    $size->getReg(rax);                                                         # Save file size

    $$p{file}->setReg(rax);                                                     # File name
    OpenRead;                                                                   # Open file for read
    $fdes->getReg(rax);                                                         # Save file descriptor

    my %d  = getSystemConstantsFromIncludeFile                                  # Memory map constants
     "linux/mman.h", qw(MAP_PRIVATE PROT_READ);
    my $pa = $d{MAP_PRIVATE};
    my $ro = $d{PROT_READ};

    Mov rax, 9;                                                                 # Memory map
    $size->setReg(rsi);                                                         # Amount of memory
    Xor rdi, rdi;                                                               # Anywhere
    Mov rdx, $ro;                                                               # Read write protections
    Mov r10, $pa;                                                               # Private and anonymous map
    $fdes->setReg(r8);                                                          # File descriptor for file backing memory
    Mov r9,  0;                                                                 # Offset into file
    Syscall;
    $size       ->setReg(rdi);
    $$p{address}->getReg(rax);
    $$p{size}   ->getReg(rdi);
    RestoreFirstSeven;
   } parameters=>[qw(file address size)], name => 'ReadFile';

  my $file    = ref($File) ? $File : V file => Rs $File;
  my $size    = V('size');
  my $address = V('address');
  $s->call(parameters=>{file => $file, size=>$size, address=>$address});

  ($address, $size)                                                             # Return address and size of mapped file
 }

sub executeFileViaBash($)                                                       # Execute the file named in a variable
 {my ($file) = @_;                                                              # File variable
  @_ == 1 or confess "File required";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    SaveFirstFour;
    Fork;                                                                       # Fork

    Test rax, rax;

    IfNz                                                                        # Parent
    Then
     {WaitPid;
     },
    Else                                                                        # Child
     {$$p{file}->setReg(rdi);
      Mov rsi, 0;
      Mov rdx, 0;
      Mov rax, 59;
      Syscall;
     };
    RestoreFirstFour;
   } parameters=>[qw(file)], name => 'executeFileViaBash';

  $s->call(parameters=>{file => $file});
 }

sub unlinkFile(@)                                                               # Unlink the named file.
 {my ($file) = @_;                                                              # File variable
  @_ == 1 or confess "File required";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    SaveFirstFour;
    $$p{file}->setReg(rdi);
    Mov rax, 87;
    Syscall;
    RestoreFirstFour;
   } parameters=>[qw(file)], name => 'unlinkFile';

  $s->call(parameters=>{file => $file});
 }

#D1 Hash functions                                                              # Hash functions

sub Hash()                                                                      # Hash a string addressed by rax with length held in rdi and return the hash code in r15.
 {@_ == 0 or confess;

  my $s = Subroutine2                                                           # Read file
   {Comment "Hash";

    PushR my @regs = (rax, rdi, k1, zmm0, zmm1);                                # Save registers
    PushR r15;
    Vpbroadcastq zmm0, rdi;                                                     # Broadcast length through ymm0
    Vcvtuqq2pd   zmm0, zmm0;                                                    # Convert to lengths to float
    Vgetmantps   zmm0, zmm0, 4;                                                 # Normalize to 1 to 2, see: https://hjlebbink.github.io/x86doc/html/VGETMANTPD.html

    Add rdi, rax;                                                               # Upper limit of string

    ForIn                                                                       # Hash in ymm0 sized blocks
     {Vmovdqu ymm1, "[rax]";                                                    # Load data to hash
      Vcvtudq2pd zmm1, ymm1;                                                    # Convert to float
      Vgetmantps zmm0, zmm0, 4;                                                 # Normalize to 1 to 2, see: https://hjlebbink.github.io/x86doc/html/VGETMANTPD.html

      Vmulpd zmm0, zmm1, zmm0;                                                  # Multiply current hash by data
     }
    sub                                                                         # Remainder in partial block
     {Mov r15, -1;
      Bzhi r15, r15, rdi;                                                       # Clear bits that we do not wish to load
      Kmovq k1, r15;                                                            # Take up mask
      Vmovdqu8 "ymm1{k1}", "[rax]";                                             # Load data to hash

      Vcvtudq2pd zmm1, ymm1;                                                    # Convert to float
      Vgetmantps   zmm0, zmm0, 4;                                               # Normalize to 1 to 2, see: https://hjlebbink.github.io/x86doc/html/VGETMANTPD.html

      Vmulpd zmm0, zmm1, zmm0;                                                  # Multiply current hash by data
     }, rax, rdi, RegisterSize ymm0;

    Vgetmantps   zmm0, zmm0, 4;                                                 # Normalize to 1 to 2, see: https://hjlebbink.github.io/x86doc/html/VGETMANTPD.html

    Mov r15, 0b11110000;                                                        # Top 4 to bottom 4
    Kmovq k1, r15;
    Vpcompressq  "zmm1{k1}", zmm0;
    Vaddpd       ymm0, ymm0, ymm1;                                              # Top 4 plus bottom 4

    Mov r15, 0b1100;                                                            # Top 2 to bottom 2
    Kmovq k1, r15;
    Vpcompressq  "ymm1{k1}", ymm0;
    Vaddpd       xmm0, xmm0, xmm1;                                              # Top 2 plus bottom 2

    Pslldq       xmm0, 2;                                                       # Move centers into double words
    Psrldq       xmm0, 4;
    Mov r15, 0b0101;                                                            # Centers to lower quad
    Kmovq k1, r15;
    Vpcompressd  "xmm0{k1}", xmm0;                                              # Compress to lower quad
    PopR r15;

    Vmovq r15, xmm0;                                                            # Result in r15

    PopR @regs;
   } name=> "Hash";

  $s->call;
 }

#D1 Unicode                                                                     # Convert utf8 to utf32

sub GetNextUtf8CharAsUtf32($$$$)                                                # Get the next UTF-8 encoded character from the addressed memory and return it as a UTF-32 char.
 {my ($in, $out, $size, $fail) = @_;                                            # Address of character variable, output character variable, output size of input, output error  if any
  @_ == 4 or confess "In, out, size, fail required";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters

    PushR (r11, r12, r13, r14, r15);
    $$p{fail}->getConst(0);                                                     # Clear failure indicator
    $$p{in}->setReg(r15);                                                       # Character to convert
    ClearRegisters r14;                                                         # Move to byte register below does not clear the entire register
    Mov r14b, "[r15]";
    my $success = Label;                                                        # As shown at: https://en.wikipedia.org/wiki/UTF-8

    Cmp r14, 0x7f;                                                              # Ascii
    IfLe
    Then
     {$$p{out}->getReg(r14);
      $$p{size}->copy(1);
      Jmp $success;
     };

    Cmp r14, 0xdf;                                                              # Char size is: 2 bytes
    IfLe
    Then
     {Mov r13b, "[r15+1]";
      And r13, 0x3f;
      And r14, 0x1f;
      Shl r14, 6;
      Or  r14,  r13;
      $$p{out}->getReg(r14);
      $$p{size}->copy(2);
      Jmp $success;
     };

    Cmp r14, 0xef;                                                              # Char size is: 3 bytes
    IfLe
    Then
     {Mov r12b, "[r15+2]";
      And r12, 0x3f;
      Mov r13b, "[r15+1]";
      And r13, 0x3f;
      And r14, 0x0f;
      Shl r13,  6;
      Shl r14, 12;
      Or  r14,  r13;
      Or  r14,  r12;
      $$p{out}->getReg(r14);
      $$p{size}->copy(3);
      Jmp $success;
     };

    Cmp r14, 0xf7;                                                              # Char size is: 4 bytes
    IfLe
    Then
     {Mov r11b, "[r15+3]";
      And r11, 0x3f;
      Mov r12b, "[r15+2]";
      And r12, 0x3f;
      Mov r13b, "[r15+1]";
      And r13, 0x3f;
      And r14, 0x07;
      Shl r12,  6;
      Shl r13, 12;
      Shl r14, 18;
      Or  r14,  r13;
      Or  r14,  r12;
      Or  r14,  r11;
      $$p{out}->getReg(r14);
      $$p{size}->copy(4);
      Jmp $success;
     };

    $$p{fail}->getConst(1);                                                     # Conversion failed

    SetLabel $success;

    PopR;
   } parameters=>[qw(in out  size  fail)], name => 'GetNextUtf8CharAsUtf32';

  $s->call(parameters=>{in=>$in, out=>$out, size=>$size, fail=>$fail});
 } # GetNextUtf8CharAsUtf32

sub ConvertUtf8ToUtf32(@)                                                       # Convert a string of utf8 to an allocated block of utf32 and return its address and length.
 {my ($u8, $size8, $u32, $size32, $count) = @_;                                 # utf8 string address variable, utf8 length variable, utf32 string address variable, utf32 length variable, number of utf8 characters converteed
  @_ == 5 or confess "Five parameters required";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    PushR (r10, r11, r12, r13, r14, r15);

    my $size = $$p{size8} * 4;                                                  # Estimated length for utf32
    AllocateMemory size => $size, my $address = V(address);

     $$p{u8}            ->setReg(r14);                                          # Current position in input string
    ($$p{u8}+$$p{size8})->setReg(r15);                                          # Upper limit of input string
    $address->setReg(r13);                                                      # Current position in output string
    ClearRegisters r12;                                                         # Number of characters in output string

    ForEver sub                                                                 # Loop through input string  converting each utf8 sequence to utf32
     {my ($start, $end) = @_;
      my ($out, $size, $fail) = (V(out), V(size), V('fail'));
      GetNextUtf8CharAsUtf32 V(in, r14), $out, $size, $fail;                    # Get next utf-8 character and convert it to utf32
      If $fail > 0,
      Then
       {PrintErrStringNL "Invalid utf8 character at index:";
        PrintErrRegisterInHex r12;
        Exit(1);
       };

      Inc r12;                                                                  # Count characters converted
      $out->setReg(r11);                                                        # Output character

      Mov  "[r13]",  r11d;
      Add    r13,    RegisterSize eax;                                          # Move up 32 bits output string
      $size->setReg(r10);                                                       # Decoded this many bytes
      Add   r14, r10;                                                           # Move up in input string
      Cmp   r14, r15;
      Jge $end;                                                                 # Exhausted input string
    };

    $$p{u32}   ->copy($address);                                                # Address of allocation
    $$p{size32}->copy($size);                                                   # Size of allocation
    $$p{count} ->getReg(r12);                                                   # Number of unicode points converted from utf8 to utf32
    PopR;
   } parameters=>[qw(u8 size8 u32 size32 count)], name => 'ConvertUtf8ToUtf32';

  $s->call(parameters=>
    {u8=>$u8, size8=>$size8, u32=>$u32, size32=>$size32, count=>$count});
 } # ConvertUtf8ToUtf32

#   4---+---3---+---2---+---1---+---0  Octal not decimal
# 0  CCCCCCCC                          ClassifyInRange                  C == classification
# 1  XXXXXXXX                          ClassifyWithInRange              X == offset in range
# 2  CCCCCCCC                XXXXXXXX  ClassifyWithInRangeAndSaveOffset C == classification, X == offset in range 0-2**10

sub ClassifyRange($$$)                                                          #P Implementation of ClassifyInRange and ClassifyWithinRange.
 {my ($recordOffsetInRange, $address, $size) = @_;                              # Record offset in classification in high byte if 1 else in classification if 2, variable address of utf32 string to classify, variable length of utf32 string to classify
  @_ == 3 or confess "Three parameters required";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    my $finish = Label;

    PushR my @save =  (($recordOffsetInRange ? (r11, r12, r13) : ()),           # More registers required if we are recording position in range
                       r14, r15, k6, k7, zmm 29..31);

    Mov r15, 0x88888888;                                                        # Create a mask for the classification bytes
    Kmovq k7, r15;
    Kshiftlq k6, k7, 32;                                                        # Move mask into upper half of register
    Korq  k7, k6, k7;                                                           # Classification bytes masked by k7

    Knotq k7, k7;                                                               # Utf32 characters mask
    Vmovdqu8 "zmm31\{k7}{z}", zmm1;                                             # Utf32 characters at upper end of each range
    Vmovdqu8 "zmm30\{k7}{z}", zmm0;                                             # Utf32 characters at lower end of each range

    $$p{address}->setReg(r15);                                                  # Address of first utf32 character
    $$p{size}->for(sub                                                          # Process each utf32 character in the block of memory
     {my ($index, $start, $next, $end) = @_;

      Mov r14d, "[r15]";                                                        # Load utf32 character
      Add r15, RegisterSize r14d;                                               # Move up to next utf32 character
      Vpbroadcastd       zmm29, r14d;                                           # Process 16 copies of the utf32 character
      Vpcmpud  k7,       zmm29, zmm30, 5;                                       # Look for start of range
      Vpcmpud "k6\{k7}", zmm29, zmm31, 2;                                       # Look for end of range
      Ktestw k6, k6;                                                            # Was there a match ?
      Jz $next;                                                                 # No character was matched
                                                                                # Process matched character
      if ($recordOffsetInRange == 1)                                            # Record offset in classification range in high byte as used for bracket matching
       {Vpcompressd "zmm29\{k6}", zmm0;                                         # Place classification byte at start of xmm29
        Vpextrd r13d, xmm29, 0;                                                 # Extract start of range
        Mov r12, r13;                                                           # Copy start of range
        Shr r12, 24;                                                            # Classification start
        And r13, 0x00ffffff;                                                    # Range start
        Sub r14, r13;                                                           # Offset in range
        Add r12, r14;                                                           # Offset in classification
        Mov "[r15-1]", r12b;                                                    # Save classification in high byte as in case 1 above.
       }
      elsif ($recordOffsetInRange == 2)                                         # Record classification in high byte and offset in classification range in low byte as used for alphabets
       {Vpcompressd "zmm29\{k6}", zmm0;                                         # Place classification byte and start of range at start of xmm29
        Vpextrd r13d, xmm29, 0;                                                 # Extract start of range specification
        Mov r12, r13;                                                           # Range classification code and start of range
        Shr r12, 24; Shl r12, 24;                                               # Clear low three bytes
        And r13, 0x00ffffff;                                                    # Utf Range start minus classification code

        Vpcompressd "zmm29\{k6}", zmm1;                                         # Place start of alphabet at start of xmm29
        Vpextrd r11d, xmm29, 0;                                                 # Extract offset of alphabet in range
        Shr r11, 24;                                                            # Alphabet offset
        Add r11, r14;                                                           # Range start plus utf32
        Sub r11, r13;                                                           # Offset of utf32 in alphabet range
        Or  r12, r11;                                                           # Case 2 above
        Mov "[r15-4]", r12d;                                                    # Save offset of utf32 in alphabet range in low bytes as in case 2 above.
       }
      else                                                                      # Record classification in high byte
       {Vpcompressd "zmm29\{k6}", zmm0;                                         # Place classification byte at start of xmm29
        Vpextrb "[r15-1]", xmm29, 3;                                            # Extract and save classification in high byte as in case 0 above.
       }
     });

    SetLabel $finish;
    PopR;
   } parameters=>[qw(address size)],
     name => "ClassifyRange_$recordOffsetInRange";

  $s->call(parameters=>{address=>$address, size=>$size});
 } # ClassifyRange

sub ClassifyInRange($$)                                                         # Character classification: classify the utf32 characters in a block of memory of specified length using a range specification held in zmm0, zmm1 formatted in double words with each double word in zmm0 having the classification in the highest 8 bits and with zmm0 and zmm1 having the utf32 character at the start (zmm0) and end (zmm1) of each range in the lowest 18 bits.  The classification bits from the first matching range are copied into the high (unused) byte of each utf32 character in the block of memory.  The effect is to replace the high order byte of each utf32 character with a classification code saying what type of character we are working.
 {my ($address, $size) = @_;                                                    # Variable address of utf32 string to classify, variable length of utf32 string to classify
  @_ == 2 or confess "Two parameters required";
  ClassifyRange(0, $address, $size);
 }

sub ClassifyWithInRange(@)                                                      # Bracket classification: Classify the utf32 characters in a block of memory of specified length using a range specification held in zmm0, zmm1 formatted in double words with the classification range in the high byte of each dword in zmm0 and the utf32 character at the start (zmm0) and end (zmm1) of each range in the lower 18 bits of each dword.  The classification bits from the position within the first matching range are copied into the high (unused) byte of each utf32 character in the block of memory.  With bracket matching this gives us a normalized bracket number.
 {my ($address, $size) = @_;                                                    # Variable address of utf32 string to classify, variable length of utf32 string to classify
  @_ == 2 or confess "Two parameters required";
  ClassifyRange(1, $address, $size);
 }

sub ClassifyWithInRangeAndSaveOffset(@)                                         # Alphabetic classification: classify the utf32 characters in a block of memory of specified length using a range specification held in zmm0, zmm1 formatted in double words with the classification code in the highest byte of each double word in zmm0 and the offset of the first element in the range in the highest byte of each dword in zmm1.  The lowest 18 bits of each double word in zmm0 and zmm1  contain the utf32 characters marking the start and end of each range. The classification bits from zmm1 for the first matching range are copied into the high byte of each utf32 character in the block of memory.  The offset in the range is copied into the lowest byte of each utf32 character in the block of memory.  The middle two bytes are cleared.  The classification byte is placed in the lowest byte of the utf32 character.
 {my ($address, $size) = @_;                                                    # Variable address of utf32 string to classify, variable length of utf32 string to classify
  @_ == 2 or confess "Two parameters required";
  ClassifyRange(2, $address, $size);
 }

#   4---+---3---+---2---+---1---+---0  Octal not decimal
#    CCCCCCCC        XXXXXXXXXXXXXXXX  ClassifyWithInRangeAndSaveWordOffset C == classification, X == offset in range 0-2**16

sub ClassifyWithInRangeAndSaveWordOffset($$$)                                   # Alphabetic classification: classify the utf32 characters in a block of memory of specified length using a range specification held in zmm0, zmm1, zmm2 formatted in double words. Zmm0 contains the low end of the range, zmm1 the high end and zmm2 contains the range offset in the high word of each Dword and the lexical classification on the lowest byte of each dword. Each utf32 character recognized is replaced by a dword whose upper byte is the lexical classification and whose lowest word is the range offset.
 {my ($address, $size, $classification) = @_;                                   # Variable address of string of utf32 characters, variable size of string in utf32 characters, variable one byte classification code for this range
  @_ == 3 or confess "Three parameters required";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    my $finish = Label;

    PushR my @save =  (r12, r13, r14, r15, k6, k7, zmm 29..31);

    $$p{address}->setReg(r15);                                                  # Address of first utf32 character
    $$p{size}->for(sub                                                          # Process each utf32 character in the block of memory
     {my ($index, $start, $next, $end) = @_;

      Mov r14d, "[r15]";                                                        # Load utf32 character
      Add r15, RegisterSize r14d;                                               # Move up to next utf32 character
      Vpbroadcastd       zmm31, r14d;                                           # Process 16 copies of the utf32 character
      Vpcmpud  k7,       zmm31, zmm0, 5;                                        # Look for start of range
      Vpcmpud "k6\{k7}", zmm31, zmm1, 2;                                        # Look for end of range
      Ktestw k6, k6;                                                            # Was there a match ?
      Jz $next;                                                                 # No character was matched
                                                                                # Process matched character
      Vpcompressd "zmm31\{k6}", zmm2;                                           # Corresponding classification and offset
      Vpextrd r13d, xmm31, 0;                                                   # Extract start of range specification - we can subtract this from the character to get its offset in this range
      Mov r12, r14;                                                             # Range classification code and start of range
      Sub r12, r13;                                                             # We now have the offset in the range

      $$p{classification}->setReg(r13);                                         # Classification code
      Shl r13, 24;                                                              # Shift classification code into position
      Or  r12, r13;                                                             # Position classification code
      Mov "[r15-4]", r12d;                                                      # Classification in highest byte of dword, offset in range in lowest word
     });
    PopR;
   } parameters => [qw(address size classification)],
     name       => "ClassifyWithInRangeAndSaveWordOffset";

  $s->call(parameters=>{address=>$address, size=>$size,
           classification=>$classification});
 } # ClassifyWithInRangeAndSaveWordOffset

#D1 Short Strings                                                               # Operations on Short Strings

sub CreateShortString($)                                                        # Create a description of a short string.
 {my ($zmm) = @_;                                                               # Numbered zmm containing the string
  @_ == 1 or confess "One parameter";
  $zmm =~ m(\A\d+\Z) && $zmm >=0 && $zmm < 32 or
    confess "Zmm register number required";

  genHash(__PACKAGE__."::ShortString",                                          # A short string up to 63 bytes long held in a zmm register.
    maximumLength      =>  RegisterSize(zmm0) - 1,                              # The maximum length of a short string if we want to store bytes
    maximumLengthWords => (RegisterSize(zmm0) - 2) / 2,                         # The maximum length of a short string if we want to store words
    zmm                => $zmm,                                                 # The number of the zmm register containing the string
    x                  => "xmm$zmm",                                            # The associated xmm register
    z                  => "zmm$zmm",                                            # The full name of the zmm register
    lengthWidth        => 1,                                                    # The length in bytes of the length field - the data follows immediately afterwards
   );
 }

sub Nasm::X86::ShortString::clear($)                                            # Clear a short string.
 {my ($string) = @_;                                                            # String
  @_ == 1 or confess "One parameter";
  my $z = $string->z;                                                           # Zmm register to use
  ClearRegisters $z;                                                            # Clear the register we are going to use as a short string
 }

sub Nasm::X86::ShortString::load($$$)                                           # Load the variable addressed data with the variable length into the short string.
 {my ($string, $address, $length) = @_;                                         # String, address, length
  @_ == 3 or confess '3 parameters';
  my $z = $string->z;                                                           # Zmm register to use
  my $x = $string->x;                                                           # Corresponding xmm

  $string->clear;                                                               # Clear the register we are going to use as a short string

  PushR r14, r15, k7;
  $length->setReg(r15);                                                         # Length of string
  Mov r14, -1;                                                                  # Clear bits that we do not wish to load
  Bzhi r14, r14, r15;
  Shl r14, 1;                                                                   # Move over length byte
  Kmovq k7, r14;                                                                # Load mask

  $address->setReg(r14);                                                        # Address of data to load
  Vmovdqu8 "${z}{k7}", "[r14-1]";                                               # Load string skipping length byte
  Pinsrb $x, r15b, 0;                                                           # Set length in zmm
  PopR;
 }

sub Nasm::X86::ShortString::loadConstantString($$)                              # Load the a short string with a constant string.
 {my ($string, $data) = @_;                                                     # Short string, string to load
  @_ == 2 or confess '2 parameters';
  my $z = $string->z;                                                           # Zmm register to use
  my $x = $string->x;                                                           # Corresponding xmm

  $string->clear;                                                               # Clear the register we are going to use as a short string

  PushR r14, r15, k7;
  Mov r15, length $data;                                                        # Length of string
  Mov r14, -1;                                                                  # Clear bits that we do not wish to load
  Bzhi r14, r14, r15;
  Shl r14, 1;                                                                   # Move over length byte
  Kmovq k7, r14;                                                                # Load mask

  Mov r14, Rs($data);                                                           # Address of data to load
  Vmovdqu8 "${z}{k7}", "[r14-1]";                                               # Load string skipping length byte
  Pinsrb $x, r15b, 0;                                                           # Set length in zmm
  PopR;
  $string
 }

sub Nasm::X86::ShortString::loadDwordBytes($$$$;$)                              # Load the specified byte of each dword in the variable addressed data with the variable length into the short string.
 {my ($string, $byte, $address, $length, $Offset) = @_;                         # String, byte offset 0-3, variable address, variable length, variable offset in short string at which to start
  @_ == 4 or @_ == 5 or confess "4 or 5 parameters";
  my $offset = $Offset // 0;                                                    # Offset in short string at which to start the load
  $byte >= 0 and $byte < 4 or confess "Invalid byte offset in dword";
  my $z = $string->z;                                                           # Zmm register to use
  my $x = $string->x;                                                           # Corresponding xmm
  my $w = $string->lengthWidth;                                                 # The length of the initial field followed by the data

  $string->clear;                                                               # Clear the register we are going to use as a short string

  PushR r13, r14, r15, $z;                                                      # Build an image of the short string on the stack and then pop it into the short string zmm

  my $m = $length->min($string->maximumLength);                                 # Length to load
  $m->setReg(r15);
  Add r15, $offset if $Offset;                                                  # Include the offset in the length of the string if an offset has been supplied
  Mov "[rsp]", r15b;                                                            # Save length on stack image of short string

  $address->setReg(r15);                                                        # Source dwords
  $m->for(sub                                                                   # Load each byte while there is room in the short string
   {my ($index, $start, $next, $end) = @_;                                      # Execute block
    $index->setReg(r14);                                                        # Index source and target
    Mov r13b, "[r15+4*r14+$byte]";                                              # Load next byte from specified position in the source dword
    Mov "[rsp+r14+$w+$offset]", r13b;                                           # Save next byte skipping length
   });

  PopR;
 }

sub Nasm::X86::ShortString::loadDwordWords($$$$;$)                              # Load the specified word of each dword in the variable addressed data with the variable length into the short string.
 {my ($string, $byte, $address, $length, $Offset) = @_;                         # String, byte offset 0-3 of word, variable address, variable length in words of data to be loaded, variable offset in short string at which to start
  @_ == 4 or @_ == 5 or confess "4 or 5 parameters";
  my $offset = $Offset // 0;                                                    # Offset in short string at which to start the load
  $byte >= 0 and $byte < 3 or confess "Invalid byte offset in dword";
  my $z = $string->z;                                                           # Zmm register to use
  my $x = $string->x;                                                           # Corresponding xmm
  my $w = $string->lengthWidth;                                                 # The length of the initial field followed by the data

  $string->clear;                                                               # Clear the register we are going to use as a short string

  PushR r13, r14, r15, $z;                                                      # Build an image of the short string on the stack and then pop it into the short string zmm

  my $m = $length->min($string->maximumLengthWords);                            # Length to load in words
  $m->setReg(r15);
  Shl r15, 1;                                                                   # Double the length because the short string measures its length in bytes but we are loading words.
  Add r15, $offset if $Offset;                                                  # Include the offset in the length of the string if an offset has been supplied
  Mov "[rsp]", r15b;                                                            # Save length on stack image of short string

  $address->setReg(r15);                                                        # Source dwords
  $m->for(sub                                                                   # Load each word while there is room in the short string
   {my ($index, $start, $next, $end) = @_;                                      # Execute block
    $index->setReg(r14);                                                        # Index source and target
    Mov r13w, "[r15+4*r14+$byte]";                                              # Load next word from specified position in the source dword
    Mov "[rsp+2*r14+$w+$offset]", r13w;                                         # Save next word skipping length
   });

  PopR;
 }

sub Nasm::X86::ShortString::len($)                                              # Return the length of a short string in a variable.
 {my ($string) = @_;                                                            # String
  @_ == 1 or confess "One parameter";
  my $z = $string->z;                                                           # Zmm register to use
  my $x = $string->x;                                                           # Corresponding xmm
  PushR r15;
  Pextrb r15, $x, 0;                                                            # Length
  my $l = V(size, r15);                                                         # Length as a variable
  PopR;
  $l
 }

sub Nasm::X86::ShortString::setLength($$)                                       # Set the length of the short string.
 {my ($string, $length) = @_;                                                   # String, variable size
  @_ == 2 or confess "Two parameters";
  my $x = $string->x;                                                           # Corresponding xmm
  PushR (r15);
  $length->setReg(r15);                                                         # Length of string
  Pinsrb $x, r15b, 0;                                                           # Set length in zmm
  PopR;
 }

sub Nasm::X86::ShortString::append($$)                                          # Append the right hand short string to the left hand short string and return a variable containing one if the operation succeeded else zero.
 {my ($left, $right) = @_;                                                      # Target zmm, source zmm
  @_ == 2 or confess "Two parameters";
  my $lz = $left ->z;                                                           # Zmm register for left string
  my $lx = $left ->x;                                                           # Corresponding xmm
  my $rz = $right->z;                                                           # Zmm register for left string
  my $rx = $right->x;                                                           # Corresponding xmm
  my $w  = $left->lengthWidth;                                                  # The length of the initial field followed by the data
  my $m  = $left->maximumLength;                                                # Maximum width of a short string

  my $s = Subroutine2                                                           # Append two short strings
   {PushR (k7, rcx, r14, r15);
    Pextrb r15, $rx, 0;                                                         # Length of right hand string
    Mov   r14, -1;                                                              # Expand mask
    Bzhi  r14, r14, r15;                                                        # Skip bits for left
    Pextrb rcx, $lx, 0;                                                         # Length of left hand string
    Inc   rcx;                                                                  # Skip length
    Shl   r14, cl;                                                              # Skip length
    Kmovq k7,  r14;                                                             # Unload mask
    PushRR $rz;                                                                 # Stack right
    Sub   rsp, rcx;                                                             # Position for masked read
    Vmovdqu8 $lz."{k7}", "[rsp+$w]";                                            # Load right string
    Add   rsp, rcx;                                                             # Restore stack
    Add   rsp, RegisterSize zmm0;
    Dec   rcx;                                                                  # Length of left
    Add   rcx, r15;                                                             # Length of combined string = length of left plus length of right
    Pinsrb $lx, cl, 0;                                                          # Save new length in left hand result
    PopR;
   } name=> "Nasm::X86::ShortString::append_${lz}_${rz}";

  my $R = V result => 0;                                                        # Assume we will fail
  If $left->len + $right->len <= $m,                                            # Complain if result will be too long
  Then
   {$s->call;                                                                   # Perform move
    $R->copy(1);                                                                # Success
   };

  $R
 }

sub Nasm::X86::ShortString::appendByte($$)                                      # Append the lowest byte in a variable to the specified short string and return a variable containing one if the operation succeeded else zero.
 {my ($string, $char) = @_;                                                     # String, variable byte
  @_ == 2 or confess "Two parameters";
  my $z = $string->z;                                                           # Zmm register to use
  my $x = $string->x;                                                           # Corresponding xmm
  my $w = $string->lengthWidth;                                                 # The length of the initial field followed by the data

  my $s = Subroutine2                                                           # Append byte to short string
   {my ($p) = @_;                                                               # Parameters
    PushR r14, r15;
    Pextrb r15, $x, 0;                                                          # Length of string
    Cmp r15, $string->maximumLength;                                            # Check current length against maximum length for a short string
    IfLt
    Then                                                                        # Room for an additional character
     {PushR $z;                                                                 # Stack string
      $$p{char}->setReg(r14);                                                   # Byte to append
      Mov "[rsp+r15+$w]", r14b;                                                 # Place byte
      PopR;                                                                     # Reload string with additional byte
      Inc r15;                                                                  # New length
      Pinsrb $x, r15b, 0;                                                       # Set length in zmm
      $$p{result}->copy(1);                                                     # Show success
     };
    PopR;
   } parameters=>[qw(result char)],
     name=> "Nasm::X86::ShortString::appendByte_$z";

  my $R = V result => 0;                                                        # Assume we will fail
  $s->call(parameters=>{result=>$R, char => $char});

  $R
 }

sub Nasm::X86::ShortString::appendVar($$)                                       # Append the value of a variable to a short string and return a variable with one in it if we succeed, else zero.
 {my ($string, $var) = @_;                                                      # Short string, variable
  @_ == 2 or confess "Two parameters";
  my $z = $string->z;                                                           # Zmm register for string
  my $w  = RegisterSize rax;                                                    # The size of a variable

  my $s = Subroutine                                                            # Append byte to short string
   {my ($p) = @_;                                                               # Parameters
    PushR r14, r15;
    my $l = $string->len;                                                       # Length of short string
    If $l + $w <= $string->maximumLength,                                       # Room within short string
    Then
     {PushR r14, r15, $z;
      $l->setReg(r15);                                                          # Length of string
      $$p{var}->setReg(r14);                                                    # Value of variable
      Mov "[rsp+r15+1]", r14;                                                   # Insert value of variable into copy of short string on stack
      PopR;
      $string->setLength($l + $w);
      $$p{result}->copy(1);                                                     # Show success
     };
   } [qw(result var)], name=> "Nasm::X86::ShortString::appendVar_$z";


  my $R = V result => 0;                                                        # Assume we will fail
  $s->call($R, var => $var);

  $R
 }

#D1 C Strings                                                                   # C strings are a series of bytes terminated by a zero byte.

sub Cstrlen()                                                                   #P Length of the C style string addressed by rax returning the length in r15.
 {@_ == 0 or confess "Deprecated in favor of StringLength";

  my $s = Subroutine2                                                           # Create arena
   {PushR my @regs = (rax, rdi, rcx);
    Mov rdi, rax;
    Mov rcx, -1;
    ClearRegisters rax;
    push @text, <<END;
    repne scasb
END
    Mov r15, rcx;
    Not r15;
    Dec r15;
    PopR @regs;
   } name => "Cstrlen";

  $s->call;
 }

sub StringLength($)                                                             # Length of a zero terminated string.
 {my ($string) = @_;                                                            # String
  @_ == 1 or confess "One parameter: zero terminated string";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    PushR rax, rdi, rcx;
    $$p{string}->setReg(rax);                                                   # Address string
    Mov rdi, rax;
    Mov rcx, -1;
    ClearRegisters rax;
    push @text, <<END;
    repne scasb
END
    Not rcx;
    Dec rcx;
    $$p{size}->getReg(rcx);                                                     # Save length
    PopR;
   } parameters => [qw(string size)], name => 'StringLength';

  $s->call(parameters=>{string=>$string, size => my $z = V size => 0});         # Variable that holds the length of the string

  $z
 }

#D1 Arenas                                                                      # An arena is single extensible block of memory which contains other data structures such as strings, arrays, trees within it.

our $ArenaFreeChain = 0;                                                        # The key of the Yggdrasil tree entry in the arena recording the start of the free chain

sub DescribeArena(%)                                                            # Describe a relocatable arena.
 {my (%options) = @_;                                                           # Optional variable addressing the start of the arena
  my $N = 4096;                                                                 # Initial size of arena
  my $w = RegisterSize 31;

  my $quad = RegisterSize rax;                                                  # Field offsets
  my $size = 0;
  my $used = $size + $quad;
  my $tree = $used + $quad;
  my $data = $w;                                                                # Data starts in the next zmm block

  genHash(__PACKAGE__."::Arena",                                                # Definition of arena
    N          => $N,                                                           # Initial allocation
    size       => $size,                                                        # Size field offset
    used       => $used,                                                        # Used field offset
    tree       => $tree,                                                        # Yggdrasil - a tree of global variables in this arena
    data       => $data,                                                        # The start of the data
    address    => ($options{address} // V address => 0),                        # Variable that addresses the memory containing the arena
    zmmBlock   => $w,                                                           # Size of a zmm block - 64 bytes
    nextOffset => $w - RegisterSize(eax),                                       # Position of next offset on free chain
   );
 }

sub CreateArena(%)                                                              # Create an relocatable arena and returns its address in rax. We add a chain header so that 64 byte blocks of memory can be freed and reused within the arena.
 {my (%options) = @_;                                                           # Free=>1 adds a free chain.
  my $arena = DescribeArena;                                                    # Describe an arena
  my $N     = $arena->N;
  my $used  = $arena->used;
  my $data  = $arena->data;
  my $size  = $arena->size;

  my $s = Subroutine2                                                           # Allocate arena
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    my $arena = AllocateMemory K size=> $N;                                     # Allocate memory and save its location in a variable

    PushR rax;
    $$s{arena}->address->copy($arena);                                          # Save address of arena
    $arena->setReg(rax);
    Mov "dword[rax+$used]", $data;                                              # Initially used space
    Mov "dword[rax+$size]", $N;                                                 # Size
    PopR;
   } structures=>{arena=>$arena}, name => 'CreateArena';

  $s->call(structures=>{arena=>$arena});                                        # Variable that holds the reference to the arena which is updated when the arena is reallocated

  $arena
 }

sub Nasm::X86::Arena::chain($$@)                                                #P Return a variable with the end point of a chain of double words in the arena starting at the specified variable.
 {my ($arena, $variable, @offsets) = @_;                                        # Arena descriptor, start variable,  offsets chain
  @_ >= 2 or confess "Two or more parameters";

  PushR (r14, r15);                                                             # Register 14 is the arena address, 15 the current offset in the arena
  $arena->address->setReg(r14);
  $variable->setReg(r15);
  for my $o(@offsets)                                                           # Each offset
   {Mov r15d, "dword[r14+r15+$o]";                                              # Step through each offset
   }
  my $r = V join (' ', @offsets), r15;                                          # Create a variable with the result
  PopR;
  $r
 }

sub Nasm::X86::Arena::length($)                                                 # Get the currently used length of an arena.
 {my ($arena) = @_;                                                             # Arena descriptor
  @_ == 1 or confess "One parameter";

  SaveFirstFour;
  $arena->address->setReg(rax);                                                 # Address arena
  Mov rdx, "[rax+$$arena{used}]";                                               # Used
  Sub rdx, $arena->data;                                                        # Subtract size of header so we get the actual amount in use
  my $size = V size => rdx;                                                     # Save length in a variable
  RestoreFirstFour;
  $size                                                                         # Return variable length
 }

sub Nasm::X86::Arena::arenaSize($)                                              # Get the size of an arena.
 {my ($arena) = @_;                                                             # Arena descriptor
  @_ == 1 or confess "One parameter";

  PushR rax;
  $arena->address->setReg(rax);                                                 # Address arena
  Mov rax, "[rax+$$arena{size}]";                                               # Get size
  my $size = V size => rax;                                                     # Save size in a variable
  PopR;
  $size                                                                         # Return size
 }

sub Nasm::X86::Arena::updateSpace($$)                                           #P Make sure that the variable addressed arena has enough space to accommodate content of the variable size.
 {my ($arena, $size) = @_;                                                      # Arena descriptor, variable size needed
  @_ == 2 or confess "Two parameters";

  my $s = Subroutine2
   {my ($p, $s) = @_;                                                           # Parameters, structures
    PushR (rax, r11, r12, r13, r14, r15);
    my $base     = rax;                                                         # Base of arena
    my $size     = r15;                                                         # Current size
    my $used     = r14;                                                         # Currently used space
    my $request  = r13;                                                         # Requested space
    my $newSize  = r12;                                                         # New size needed
    my $proposed = r11;                                                         # Proposed size

    my $arena = $$s{arena};                                                     # Address arena
    $arena->address->setReg($base);                                             # Address arena
    $$p{size}->setReg($request);                                                # Requested space

    Mov $size, "[$base+$$arena{size}]";
    Mov $used, "[$base+$$arena{used}]";
    Mov $newSize, $used;
    Add $newSize, $request;

    Cmp $newSize,$size;                                                         # New size needed
    IfGt                                                                        # New size is bigger than current size
    Then                                                                        # More space needed
     {Mov $proposed, 4096 * 1;                                                  # Minimum proposed arena size
      K(loop, 36)->for(sub                                                      # Maximum number of shifts
       {my ($index, $start, $next, $end) = @_;
        Shl $proposed, 1;                                                       # New proposed size
        Cmp $proposed, $newSize;                                                # Big enough?
        Jge $end;                                                               # Big enough!
       });
      my $oldSize = V(size, $size);                                             # The old size of the arena
      my $newSize = V(size, $proposed);                                         # The old size of the arena
      my $address = AllocateMemory($newSize);                                   # Create new arena
      CopyMemory($arena->address, $address, $oldSize);                          # Copy old arena into new arena
      FreeMemory $arena->address, $oldSize;                                     # Free previous memory previously occupied arena
      $arena->address->copy($address);                                          # Save new arena address

      $arena->address->setReg($base);                                           # Address arena
      Mov "[$base+$$arena{size}]", $proposed;                                   # Save the new size in the arena
     };

    PopR;
   } parameters => [qw(size)],
     structures => {arena => $arena},
     name       => 'Nasm::X86::Arena::updateSpace';

  $s->call(parameters=>{size => $size}, structures=>{arena => $arena});
 } # updateSpace

sub Nasm::X86::Arena::makeReadOnly($)                                           # Make an arena read only.
 {my ($arena) = @_;                                                             # Arena descriptor
  @_ == 1 or confess "One parameter";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    Comment "Make an arena readable";
    SaveFirstFour;
    $$p{address}->setReg(rax);
    Mov rdi, rax;                                                               # Address of arena
    Mov rsi, "[rax+$$arena{size}]";                                             # Size of arena

    Mov rdx, 1;                                                                 # Read only access
    Mov rax, 10;
    Syscall;
    RestoreFirstFour;                                                           # Return the possibly expanded arena
   } parameters=>[qw(address)], name => 'Nasm::X86::Arena::makeReadOnly';

  $s->call(parameters=>{address => $arena->address});
 }

sub Nasm::X86::Arena::makeWriteable($)                                          # Make an arena writable.
 {my ($arena) = @_;                                                             # Arena descriptor
  @_ == 1 or confess "One parameter";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    Comment "Make an arena writable";
    SaveFirstFour;
    $$p{address}->setReg(rax);
    Mov rdi, rax;                                                               # Address of arena
    Mov rsi, "[rax+$$arena{size}]";                                             # Size of arena
    Mov rdx, 3;                                                                 # Read only access
    Mov rax, 10;
    Syscall;
    RestoreFirstFour;                                                           # Return the possibly expanded arena
   } parameters=>[qw(address)], name => 'Nasm::X86::Arena::makeWriteable';

  $s->call(parameters=>{address => $arena->address});
 }

sub Nasm::X86::Arena::allocate($$)                                              # Allocate the variable amount of space in the variable addressed arena and return the offset of the allocation in the arena as a variable.
 {my ($arena, $size) = @_;                                                      # Arena descriptor, variable amount of allocation
  @_ == 2 or confess "Two parameters";

  SaveFirstFour;
  my $offset = V("offset");                                                     # Variable to hold offset of allocation
  $arena->updateSpace($size);                                                   # Update space if needed
  $arena->address->setReg(rax);
  Mov rsi, "[rax+$$arena{used}]";                                               # Currently used
  $offset->getReg(rsi);
  $size  ->setReg(rdi);
  Add rsi, rdi;
  Mov "[rax+$$arena{used}]", rsi;                                               # Update currently used
  RestoreFirstFour;
  $offset
 }

sub Nasm::X86::Arena::allocZmmBlock($)                                          # Allocate a block to hold a zmm register in the specified arena and return the offset of the block as a variable.
 {my ($arena) = @_;                                                             # Arena
  @_ == 1 or confess "One parameter";
  my $offset = V("offset");                                                     # Variable to hold offset of allocation
# Reinstate when we have trees working as an array
##  my $ffb = $arena->firstFreeBlock;                                             # Check for a free block
##  If $ffb > 0,
##  Then                                                                          # Free block available
##   {PushR my @save = (r8, r9, zmm31);
##    $arena->getZmmBlock($ffb, 31, r8, r9);                                      # Load the first block on the free chain
##    my $second = dFromZ(31, $arena->nextOffset, r8);                            # The location of the next pointer is forced upon us by string which got there first.
##    $arena->setFirstFreeBlock($second);                                         # Set the first free block field to point to the second block
##    $offset->copy($ffb);                                                        # Get the block at the start of the chain
##    PopR @save;
##   },
##  Else                                                                          # Cannot reuse a free block so allocate
   {$offset->copy($arena->allocate(K size => $arena->zmmBlock));                # Copy offset of allocation
   };

  $arena->clearZmmBlock($offset);                                               # Clear the zmm block - possibly this only needs to be done if we are reusing a block

  $offset                                                                       # Return offset of allocated block
 }

sub Nasm::X86::Arena::checkYggdrasilCreated($)                                  #P Return a tree descriptor to the Yggdrasil world tree for an arena.  If Yggdrasil has not been created the B<found> variable will be zero else one.
 {my ($arena) = @_;                                                             # Arena descriptor
  @_ == 1 or confess "One parameter";

  my $y = "Yggdrasil";
  my $t = $arena->DescribeTree;                                                 # Tree descriptor for Yggdrasil
  PushR rax;
  $arena->address->setReg(rax);                                                 #P Address underlying arena
  Mov rax, "[rax+$$arena{tree}]";                                               # Address Yggdrasil
  my $v = V('Yggdrasil', rax);                                                  # Offset to Yggdrasil if Yggdrasil exists else zero
  Cmp rax, 0;                                                                   # Does Yggdrasil even exist?
  IfNe
  Then                                                                          # Yggdrasil has been created so we can address it
   {$t->first->copy(rax);
    $t->found->copy(1);
   },
  Else                                                                          # Yggdrasil has not been created
   {$t->found->copy(0);
   };
  Cmp rax, 0;                                                                   # Restate whether Yggdrasil exists so that we can test its status quickly in the following code.
  PopR rax;
  $t
 }

sub Nasm::X86::Arena::establishYggdrasil($)                                     #P Return a tree descriptor to the Yggdrasil world tree for an arena creating the world tree Yggdrasil if it has not already been created.
 {my ($arena) = @_;                                                             # Arena descriptor
  @_ == 1 or confess "One parameter";

  my $y = "Yggdrasil";
  my $t = $arena->DescribeTree;                                                 # Tree descriptor for Yggdrasil
  PushR my @save = (rax, rdi);
  $arena->address->setReg(rax);                                                 #P Address underlying arena
  Mov rdi, "[rax+$$arena{tree}]";                                               # Address Yggdrasil
  Cmp rdi, 0;                                                                   # Does Yggdrasil even exist?
  IfNe
  Then                                                                          # Yggdrasil has been created so we can address it
   {$t->first->copy(rdi);
   },
  Else                                                                          # Yggdrasil has not been created
   {my $T = $arena->CreateTree();
    $T->first->setReg(rdi);
    $t->first->copy(rdi);
    Mov "[rax+$$arena{tree}]", rdi;                                             # Save offset of Yggdrasil
   };
  PopR @save;
  $t
 }

sub Nasm::X86::Arena::firstFreeBlock($)                                         #P Create and load a variable with the first free block on the free block chain or zero if no such block in the given arena.
 {my ($arena) = @_;                                                             # Arena descriptor
  @_ == 1 or confess "One parameter";
  my $v = V('free', 0);                                                         # Offset of first free block
  my $t = $arena->checkYggdrasilCreated;                                        # Check Yggdrasil
  IfNe
  Then
   {PushR rax;
    my $d = $t->find(K key => $ArenaFreeChain);                                 # Locate free chain
    If ($t->found > 0,                                                          # Located offset of free chain
    Then
     {$v->copy($t->data);                                                       # Offset of first free block
     });
    PopR rax;
   };
  $v                                                                            # Return offset of first free block or zero if there is none
 }

sub Nasm::X86::Arena::setFirstFreeBlock($$)                                     #P Set the first free block field from a variable.
 {my ($arena, $offset) = @_;                                                    # Arena descriptor, first free block offset as a variable
  @_ == 2 or confess "Two parameters";

  my $t = $arena->establishYggdrasil;
  $t->insert(K('key', $ArenaFreeChain), $offset);                               # Save offset of first block in free chain
 }

sub Nasm::X86::Arena::dumpFreeChain($)                                          #P Dump the addresses of the blocks currently on the free chain.
 {my ($arena) = @_;                                                             # Arena descriptor
  @_ == 1 or confess "One parameters";

  PushR my @save = (r8, r9, r15, zmm31);
  my $ffb = $arena->firstFreeBlock;                                             # Get first free block
  PrintOutStringNL "Free chain";
  V( loop => 99)->for(sub                                                       # Loop through free block chain
   {my ($index, $start, $next, $end) = @_;
    If $ffb == 0, Then {Jmp $end};                                              # No more free blocks
    $ffb->outNL;
    $arena->getZmmBlock($ffb, 31, r8, r9);                                      # Load the first block on the free chain
    my $n = dFromZ 31, $arena->nextOffset;                                      # The location of the next pointer is forced upon us by string which got there first.
    $ffb->copy($n);
   });
  PrintOutStringNL "Free chain end";
  PopR;
 }

sub Nasm::X86::Arena::getZmmBlock($$$)                                          #P Get the block with the specified offset in the specified string and return it in the numbered zmm.
 {my ($arena, $block, $zmm) = @_;                                               # Arena descriptor, offset of the block as a variable, number of zmm register to contain block
  @_ == 3 or confess "Three parameters";

  my $a = rdi;                                                                  # Work registers
  my $o = rsi;

  $arena->address->setReg($a);                                                  # Arena address
  $block->setReg($o);                                                           # Offset of block in arena

  Cmp $o, $arena->data;
  IfLt                                                                          # We could have done this using variable arithmetic, but such arithmetic is expensive and so it is better to use register arithmetic if we can.
  Then
   {PrintErrTraceBack "Attempt to get block before start of arena";
   };

  Vmovdqu64 "zmm$zmm", "[$a+$o]";                                               # Read from memory
 }

sub Nasm::X86::Arena::putZmmBlock($$$)                                          #P Write the numbered zmm to the block at the specified offset in the specified arena.
 {my ($arena, $block, $zmm) = @_;                                               # Arena descriptor, offset of the block as a variable, number of zmm register to contain block, first optional work register, second optional work register
  @_ == 3 or confess "Three parameters";

  my $a = rdi;                                                                  # Work registers
  my $o = rsi;

  $arena->address->setReg($a);                                                  # Arena address
  $block->setReg($o);                                                           # Offset of block in arena

  Cmp $o, $arena->data;
  IfLt                                                                          # We could have done this using variable arithmetic, but such arithmetic is expensive and so it is better to use register arithmetic if we can.
  Then
   {PrintErrTraceBack "Attempt to put block before start of arena";
   };

  Vmovdqu64 "[$a+$o]", "zmm$zmm";                                               # Read from memory
 }

sub Nasm::X86::Arena::clearZmmBlock($$)                                         #P Clear the zmm block at the specified offset in the arena
 {my ($arena, $offset) = @_;                                                    # Arena descriptor, offset of the block as a variable
  @_ == 2 or confess "Two parameters";

  PushR zmm31;                                                                  # Clear a zmm block
  ClearRegisters zmm31;
  $arena->putZmmBlock($offset, 31);
  PopR;
 }

sub Nasm::X86::Arena::freeZmmBlock($$)                                          #P Free a block in an arena by placing it on the free chain.
 {my ($arena, $offset) = @_;                                                    # Arena descriptor, offset of zmm block to be freed
  @_ == 2 or confess "Two parameters";

  PushR my @save = (r15, zmm31);
  my $rfc = $arena->firstFreeBlock;                                             # Get first free block
  ClearRegisters @save;                                                         # Second block
  $rfc->dIntoZ(31, $arena->nextOffset, r15);                                    # The position of the next pointer was dictated by strings.
  $arena->putZmmBlock($offset, 31);                                             # Link the freed block to the rest of the free chain
  $arena->setFirstFreeBlock($offset);                                           # Set free chain field to point to latest free chain element
  PopR;
 }

sub Nasm::X86::Arena::m($$$)                                                    # Append the variable addressed content of variable size to the specified arena.
 {my ($arena, $address, $size) = @_;                                            # Arena descriptor, variable address of content, variable length of content
  @_ == 3 or confess "Three parameters";

  my $used = "[rax+$$arena{used}]";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    SaveFirstFour;
    my $arena = $$s{arena};
    $arena->address->setReg(rax);
    my $oldUsed = V("used", $used);
    $arena->updateSpace($$p{size});                                             # Update space if needed

    my $target  = $oldUsed + $arena->address;
    CopyMemory($$p{address}, $target, $$p{size});                               # Copy data into the arena

    my $newUsed = $oldUsed + $$p{size};

    $arena->address->setReg(rax);                                               # Update used field
    $newUsed->setReg(rdi);
    Mov $used, rdi;

    RestoreFirstFour;
   } structures => {arena => $arena},
     parameters => [qw(address size)],
     name       => 'Nasm::X86::Arena::m';

  $s->call(structures => {arena => $arena},
           parameters => {address => $address, size => $size});
 }

sub Nasm::X86::Arena::q($$)                                                     # Append a constant string to the arena.
 {my ($arena, $string) = @_;                                                    # Arena descriptor, string
  @_ == 2 or confess "Two parameters";

  my $s = Rs($string);
  $arena->m(V('address', $s), V('size', length($string)));
 }

sub Nasm::X86::Arena::ql($$)                                                    # Append a quoted string containing new line characters to the specified arena.
 {my ($arena, $const) = @_;                                                     # Arena, constant
  @_ == 2 or confess "Two parameters";
  for my $l(split /\s*\n/, $const)
   {$arena->q($l);
    $arena->nl;
   }
 }

sub Nasm::X86::Arena::char($$)                                                  # Append a character expressed as a decimal number to the specified arena.
 {my ($arena, $char) = @_;                                                      # Arena descriptor, number of character to be appended
  @_ == 2 or confess "Two parameters";
  my $s = Rb(ord($char));
  $arena->m(V(address, $s), V(size, 1));                                        # Move data
 }

sub Nasm::X86::Arena::nl($)                                                     # Append a new line to the arena addressed by rax.
 {my ($arena) = @_;                                                             # Arena descriptor
  @_ == 1 or confess "One parameter";
  $arena->char("\n");
 }

sub Nasm::X86::Arena::z($)                                                      # Append a trailing zero to the arena addressed by rax.
 {my ($arena) = @_;                                                             # Arena descriptor
  @_ == 1 or confess "One parameter";
  $arena->char("\0");
 }

sub Nasm::X86::Arena::append($@)                                                # Append one arena to another.
 {my ($target, $source) = @_;                                                   # Target arena descriptor, source arena descriptor
  @_ == 2 or confess "Two parameters";

  SaveFirstFour;
  $source->address->setReg(rax);
  Mov rdi, "[rax+$$source{used}]";
  Sub rdi, $source->data;
  Lea rsi, "[rax+$$source{data}]";
  $target->m(V(address, rsi), V(size, rdi));
  RestoreFirstFour;
 }

sub Nasm::X86::Arena::clear($)                                                  # Clear an arena
 {my ($arena) = @_;                                                             # Arena descriptor
  @_ == 1 or confess "One parameter";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    PushR (rax, rdi);
    $$p{address}->setReg(rax);
    Mov rdi, $arena->data;
    Mov "[rax+$$arena{used}]", rdi;
    PopR;
   } parameters=>[qw(address)], name => 'Nasm::X86::Arena::clear';

  $s->call(parameters=>{address => $arena->address});
 }

sub Nasm::X86::Arena::write($$)                                                 # Write the content of the specified arena to a file specified by a zero terminated string.
 {my ($arena, $file) = @_;                                                      # Arena descriptor, variable addressing file name
  @_ == 2 or confess "Two parameters";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    SaveFirstFour;

    $$p{file}->setReg(rax);
    OpenWrite;                                                                  # Open file
    my $file = V(fd => rax);                                                    # File descriptor

    $$p{address}->setReg(rax);                                                  # Write file
    Lea rsi, "[rax+$$arena{data}]";
    Mov rdx, "[rax+$$arena{used}]";
    Sub rdx, $arena->data;

    Mov rax, 1;                                                                 # Write content to file
    $file->setReg(rdi);
    Syscall;

    $file->setReg(rax);
    CloseFile;
    RestoreFirstFour;
   } parameters=>[qw(file address)], name => 'Nasm::X86::Arena::write';

  $s->call(parameters=>{address => $arena->address, file => $file});
 }

sub Nasm::X86::Arena::read($@)                                                  # Read a file specified by a variable addressed zero terminated string and place the contents of the file into the named arena.
 {my ($arena, $file) = @_;                                                      # Arena descriptor, variable addressing file name
  @_ == 2 or confess "Two parameters";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    Comment "Read an arena";
    my ($address, $size) = ReadFile $$p{file};
    my $arena = $$s{arena};
    $arena->m($address, $size);                                                 # Move data into arena
    FreeMemory($size, $address);                                                # Free memory allocated by read
   } structures => {arena=>$arena},
     parameters => [qw(file)],
     name       => 'Nasm::X86::Arena::read';

  $s->call(structures => {arena => $arena}, parameters => {file => $file});
 }

sub Nasm::X86::Arena::out($)                                                    # Print the specified arena on sysout.
 {my ($arena) = @_;                                                             # Arena descriptor
  @_ == 1 or confess "One parameter";

  my $s = Subroutine2
   {my ($p) = @_;                                                               # Parameters
    SaveFirstFour;
    $$p{address}->setReg(rax);

    Mov rdi, "[rax+$$arena{used}]";                                             # Length to print
    Sub rdi, $arena->data;                                                      # Length to print
    Lea rax, "[rax+$$arena{data}]";                                             # Address of data field
    PrintOutMemory;
    RestoreFirstFour;
   } parameters=>[qw(address)], name => 'Nasm::X86::Arena::out';

  $s->call(parameters=>{address => $arena->address});
 }

sub Nasm::X86::Arena::outNL($)                                                  # Print the specified arena on sysout followed by a new line.
 {my ($arena) = @_;                                                             # Arena descriptor
  @_ == 1 or confess "One parameter";

  $arena->out;
  PrintOutNL;
 }

sub Nasm::X86::Arena::dump($$;$)                                                # Dump details of an arena.
 {my ($arena, $title, $depth) = @_;                                             # Arena descriptor, title string, optional variable number of 64 byte blocks to dump
  @_ == 2 or @_ == 3 or confess "Two or three parameters";
  my $blockSize = 64;                                                           # Print in blocks of this size

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    PushR rax, rdi;
    my $arena = $$s{arena};
    $arena->address->setReg(rax);                                               # Get address of arena
    PrintOutString("Arena   ");

    PushR rax;                                                                  # Print size
    Mov rax, "[rax+$$arena{size}]";
    PrintOutString "  Size: ";
    PrintOutRaxRightInDec K width => 8;
    PrintOutString "  ";
    PopR rax;

    PushR rax;                                                                  # Print size
    Mov rax, "[rax+$$arena{used}]";
    PrintOutString("  Used: ");
    PrintOutRaxRightInDec  K width => 8;
    PrintOutNL;
    PopR rax;

    $$p{depth}->for(sub                                                         # Print the requested number of blocks
     {my ($index, $start, $next, $end) = @_;
      Mov rdi, $blockSize;                                                      # Length of each print
      ($index*RegisterSize(zmm31))->out('', ' | ');
      my $address = $arena->address + $index * $blockSize;                      # Address of block to print
      $address->setReg(rax);
      PrintOutMemory_InHexNL;
     });

    PopR;
   } structures=>{arena=>$arena},
     parameters=>[qw(depth)],
     name => "Nasm::X86::Arena::dump";

  PrintOutStringNL $title;
  $s->call(structures=>{arena=>$arena}, parameters=>{depth => ($depth // V('depth', 4))});
 }

#D1 String                                                                      # Strings made from zmm sized blocks of text

sub DescribeString(%)                                                           # Describe a string.
 {my (%options) = @_;                                                           # String options
  @_ >= 1 or confess;
  my $b = RegisterSize zmm0;                                                    # Size of a block == size of a zmm register
  my $o = RegisterSize eax;                                                     # Size of a double word
  my $l = 1;                                                                    # Length of the per block length field

  genHash(__PACKAGE__."::String",                                               # String definition
    arena       => $options{arena},                                             # Arena
    links       => $b - 2 * $o,                                                 # Location of links in bytes in zmm
    next        => $b - 1 * $o,                                                 # Location of next offset in block in bytes
    prev        => $b - 2 * $o,                                                 # Location of prev offset in block in bytes
    length      => $b - 2 * $o - $l,                                            # Maximum length in a block
    lengthWidth => $l,                                                          # Maximum length in a block
    first       => ($options{first}//V('first')),                               # Variable addressing first block in string if one has not been supplied
   );
 }

sub Nasm::X86::Arena::DescribeString($%)                                        # Describe a string and optionally set its first block .
 {my ($arena, %options) = @_;                                                   # Arena description, arena options
  DescribeString(arena=>$arena, %options);
 }

sub Nasm::X86::Arena::CreateString($)                                           # Create a string from a doubly link linked list of 64 byte blocks linked via 4 byte offsets in an arena and return its descriptor.
 {my ($arena) = @_;                                                             # Arena description
  @_ == 1 or confess "One parameter";

  my $s = $arena->DescribeString;                                               # String descriptor
  my $first = $s->allocBlock;                                                   # Allocate first block
  $s->first->copy($first);                                                      # Record offset of first block

  if (1)                                                                        # Initialize circular list - really it would be better to allow the first block not to have pointers until it actually needed them for compatibility with short strings.
   {my $nn = $s->next;
    my $pp = $s->prev;
    PushR (r14, r15);
    $arena->address->setReg(r15);
    $first->setReg(r14);
    Mov "[r15+r14+$nn]", r14d;
    Mov "[r15+r14+$pp]", r14d;
    PopR;
   }
  $s                                                                            # Description of string
 }

#sub Nasm::X86::String::address($)                                              #P Address of a string.
# {my ($String) = @_;                                                           # String descriptor
#  @_ == 1 or confess "One parameter";
#  $String->arena->address;
# }

sub Nasm::X86::String::allocBlock($)                                            #P Allocate a block to hold a zmm register in the specified arena and return the offset of the block in a variable.
 {my ($string) = @_;                                                            # String descriptor
  @_ == 1 or confess "One parameters";
  $string->arena->allocZmmBlock;                                                # Allocate block and return its offset as a variable
 }

sub Nasm::X86::String::getBlockLength($$)                                       #P Get the block length of the numbered zmm and return it in a variable.
 {my ($String, $zmm) = @_;                                                      # String descriptor, number of zmm register
  @_ == 2 or confess "Two parameters";
  bFromZ $zmm, 0;                                                               # Block length
 }

sub Nasm::X86::String::setBlockLengthInZmm($$$)                                 #P Set the block length of the numbered zmm to the specified length.
 {my ($String, $length, $zmm) = @_;                                             # String descriptor, length as a variable, number of zmm register
  @_ == 3 or confess "Three parameters";
  PushR (r15);                                                                  # Save work register
  $length->setReg(r15);                                                         # New length
  $length->bIntoZ($zmm, 0);                                                     # Insert block length
  PopR;                                                                         # Length of block is a byte
 }

sub Nasm::X86::String::getZmmBlock($$$)                                         #P Get the block with the specified offset in the specified string and return it in the numbered zmm.
 {my ($String, $block, $zmm) = @_;                                              # String descriptor, offset of the block as a variable, number of zmm register to contain block
  @_ == 3 or confess "Three parameters";
  $String->arena->getZmmBlock($block, $zmm);
 }

sub Nasm::X86::String::putZmmBlock($$$)                                         #P Write the numbered zmm to the block at the specified offset in the specified arena.
 {my ($String, $block, $zmm) = @_;                                              # String descriptor, block in arena, content variable
  @_ == 3 or confess "Three parameters";
  $String->arena->putZmmBlock($block, $zmm);
 }

sub Nasm::X86::String::getNextAndPrevBlockOffsetFromZmm($$)                     #P Get the offsets of the next and previous blocks as variables from the specified zmm.
 {my ($String, $zmm) = @_;                                                      # String descriptor, zmm containing block
  @_ == 2 or confess "Two parameters";
  my $l = $String->links;                                                       # Location of links
  PushR my @regs = (r14, r15);                                                  # Work registers
  my $L = qFromZ($zmm, $String->links);                                         # Links in one register
  $L->setReg(r15);                                                              # Links
  Mov r14d, r15d;                                                               # Next
  Shr r15, RegisterSize(r14d) * 8;                                              # Prev
  my @r = (V("Next block offset", r15), V("Prev block offset", r14));           # Result
  PopR @regs;                                                                   # Free work registers
  @r;                                                                           # Return (next, prev)
 }

sub Nasm::X86::String::putNextandPrevBlockOffsetIntoZmm($$$$)                   #P Save next and prev offsets into a zmm representing a block.
 {my ($String, $zmm, $next, $prev) = @_;                                        # String descriptor, zmm containing block, next offset as a variable, prev offset as a variable
  @_ == 4 or confess;
  if ($next and $prev)                                                          # Set both previous and next
   {PushR my @regs = (r14, r15);                                                # Work registers
    $next->setReg(r14);                                                         # Next offset
    $prev->setReg(r15);                                                         # Prev offset
    Shl r14, RegisterSize(r14d) * 8;                                            # Prev high
    Or r15, r14;                                                                # Links in one register
    my $l = V("Links", r15);                                                    # Links as variable
    $l->qIntoZ($zmm, $String->links);                                           # Load links into zmm
    PopR @regs;                                                                 # Free work registers
   }
  elsif ($next)                                                                 # Set just next
   {PushR my @regs = (r8, r15);                                                 # Work registers
    $next->setReg(r15);                                                         # Next offset
    my $l = V("Links", r15);                                                    # Links as variable
    $l->dIntoZ($zmm, $String->next);                                            # Load links into zmm
    PopR @regs;                                                                 # Free work registers
   }
  elsif ($prev)                                                                 # Set just prev
   {PushR my @regs = (r8, r15);                                                 # Work registers
    $prev->setReg(r15);                                                         # Next offset
    my $l = V("Links", r15);                                                    # Links as variable
    $l->dIntoZ($zmm, $String->prev);                                            # Load links into zmm
    PopR @regs;                                                                 # Free work registers
   }
 }

sub Nasm::X86::String::dump($)                                                  # Dump a string to sysout.
 {my ($string) = @_;                                                            # String descriptor
  @_ == 1 or confess "One parameter";

  my $s = Subroutine2
   {my ($p, $s) = @_;                                                           # Parameters, structures
    PushR zmm31;
    my $string = $$s{string};
    my $block  = $string->first;                                                # The first block
                 $string->getZmmBlock($block, 31);                              # The first block in zmm31
    my $length = $string->getBlockLength(  31);                                 # Length of block

    PrintOutString "String Dump      Total Length: ";                           # Title
    $string->len->outRightInDecNL(K width => 8);

    $block ->out("Offset: ");                                                   # Offset of first block in hex
    PrintOutString "  Length: ";
    $length->outRightInDec(K width => 2);                                       # Length of block in decimal
    PrintOutString "  ";
    PrintOutOneRegisterInHexNL zmm31;                                           # Print block

    ForEver                                                                     # Each block in string
     {my ($start, $end) = @_;
      my ($next, $prev) = $string->getNextAndPrevBlockOffsetFromZmm(31);        # Get links from current block
      If $next == $block, sub{Jmp $end};                                        # Next block is the first block so we have printed the string
      $string->getZmmBlock($next, 31);                                          # Next block in zmm
      my $length = $string->getBlockLength(31);                                 # Length of block
      $next  ->out("Offset: ");                                                 # Offset of block in hex
      PrintOutString "  Length: ";
      $length->outRightInDec(K width => 2);                                     # Length of block in decimal
      PrintOutString "  ";
      PrintOutOneRegisterInHexNL zmm31;                                         # Print block
     };
    PrintOutNL;

    PopR;
   } structures=>{string=>$string}, name => 'Nasm::X86::String::dump';

  $s->call(structures=>{string=>$string});
 }

sub Nasm::X86::String::len($)                                                   # Find the length of a string.
 {my ($string) = @_;                                                            # String descriptor
  @_ == 1 or confess "One parameter";

  my $s = Subroutine2
   {my ($p, $s) = @_;                                                           # Parameters, structures
    Comment "Length of a string";
    PushR zmm31;
    my $string = $$s{string};                                                   # String
    my $block  = $string->first;                                                # The first block
                 $string->getZmmBlock($block, 31);                              # The first block in zmm31
    my $length = $string->getBlockLength(  31);                                 # Length of block

    ForEver                                                                     # Each block in string
     {my ($start, $end) = @_;
      my ($next, $prev) = $string->getNextAndPrevBlockOffsetFromZmm(31);        # Get links from current block
      If  $next == $block, sub{Jmp $end};                                       # Next block is the first block so we have traversed the entire string
      $string->getZmmBlock($next, 31);                                          # Next block in zmm
      $length += $string->getBlockLength(31);                                   # Add length of block
     };
    $$p{size}->copy($length);
    PopR;
   } parameters => [qw(size)],
     structures => {string => $string},
     name       => 'Nasm::X86::String::len';

  $s->call(parameters => {size   => my $size = V size => 0},
           structures => {string => $string});

  $size
 }

sub Nasm::X86::String::concatenate($$)                                          # Concatenate two strings by appending a copy of the source to the target string.
 {my ($target, $source) = @_;                                                   # Target string, source string
  @_ == 2 or confess "Two parameters";

  my $s = Subroutine2
   {my ($p, $s) = @_;                                                           # Parameters, structures
    Comment "Concatenate strings";
    PushZmm 29..31;

    my $source = $$s{source}; my $sf = $source->first;                          # Source string
    my $target = $$s{target}; my $tf = $target->first;                          # Target string

    $source->getZmmBlock($sf, 31);                                              # The first source block
    $target->getZmmBlock($tf, 30);                                              # The first target block
    my ($ts, $tl) = $target->getNextAndPrevBlockOffsetFromZmm(30);              # Target second and last
    $target->getZmmBlock($tl, 30);                                              # The last target block to which we will append

    ForEver                                                                     # Each block in source string
     {my ($start, $end) = @_;                                                   # Start and end labels

      my $new = $target->allocBlock;                                            # Allocate new block
      Vmovdqu8 zmm29, zmm31;                                                    # Load new target block from source
      my ($next, $prev) = $target->getNextAndPrevBlockOffsetFromZmm(30);        # Linkage from last target block

      $target->putNextandPrevBlockOffsetIntoZmm(30, $new,    $prev);            # From last block
      $target->putNextandPrevBlockOffsetIntoZmm(29, $tf,     $tl);              # From new block
      $target->putZmmBlock($tl, 30);                                            # Put the modified last target block
      $tl->copy($new);                                                          # New last target block
      $target->putZmmBlock($tl, 29);                                            # Put the modified new last target block
      Vmovdqu8 zmm30, zmm29;                                                    # Last target block

      my ($sn, $sp) = $source->getNextAndPrevBlockOffsetFromZmm(31);            # Get links from current source block
      If $sn == $sf,
      Then                                                                      # Last source block
       {$target->getZmmBlock($tf, 30);                                          # The first target block
        $target->putNextandPrevBlockOffsetIntoZmm(30, undef, $new);             # Update end of block chain
        $target->putZmmBlock($tf, 30);                                          # Save modified first target block

        Jmp $end
       };

      $source->getZmmBlock($sn, 31);                                            # Next source block
     };

    PopZmm;
   } structures => {source=>$source, target=>$target},
     name       => 'Nasm::X86::String::concatenate';

  $s->call(structures => {source=>$source, target=>$target});
 }

sub Nasm::X86::String::insertChar($$$)                                          # Insert a character into a string.
 {my ($string, $character, $position) = @_;                                     # String, variable character, variable position
  @_ == 3 or confess "Three parameters";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    PushR (k7, r14, r15, zmm30, zmm31);
    my $c = $$p{character};                                                     # The character to insert
    my $P = $$p{position};                                                      # The position in the string at which we want to insert the character

    my $string = $$s{string};                                                   # String
    my $F      = $string->first;                                                # The first block in string

    $string->getZmmBlock($F, 31);                                               # The first source block

    my $C   = V('Current character position', 0);                               # Current character position
    my $L   = $string->getBlockLength(31);                                      # Length of last block
    my $M   = V('Block length', $string->length);                               # Maximum length of a block
    my $One = V('One', 1);                                                      # Literal one
    my $current = $F->clone('current');                                         # Current position in scan of block chain

    ForEver                                                                     # Each block in source string
     {my ($start, $end) = @_;                                                   # Start and end labels

      If $P >= $C,
      Then                                                                      # Position is in current block
       {If $P <= $C + $L,
        Then                                                                    # Position is in current block
         {my $O = $P - $C;                                                      # Offset in current block

          PushR zmm31;                                                          # Stack block
          $O->setReg(r14);                                                      # Offset of character in block
          $c->setReg(r15);                                                      # Character to insert
          Mov "[rsp+r14]", r15b;                                                # Place character after skipping length field

          If $L < $M,
          Then                                                                  # Current block has space
           {($P+1-$C)->setMask($C + $L - $P + 1, k7);                           # Set mask for reload
            Vmovdqu8 "zmm31{k7}", "[rsp-1]";                                    # Reload
            $string->setBlockLengthInZmm($L + 1, 31);                           # Length of block
           },
          Else                                                                  # In the current block but no space so split the block
           {$One->setMask($C + $L - $P + 2, k7);                                # Set mask for reload
            Vmovdqu8 "zmm30{k7}", "[rsp+r14-1]";                                # Reload
            $string->setBlockLengthInZmm($O,          31);                      # New shorter length of original block
            $string->setBlockLengthInZmm($L - $O + 1, 30);                      # Set length of  remainder plus inserted char in the new block

            my $new = $string->allocBlock;                                      # Allocate new block
            my ($next, $prev) = $string->getNextAndPrevBlockOffsetFromZmm(31);  # Linkage from last block

            If $next == $prev,
            Then                                                                # The existing string has one block, add new as the second block
             {$string->putNextandPrevBlockOffsetIntoZmm(31, $new,  $new);
              $string->putNextandPrevBlockOffsetIntoZmm(30, $next, $prev);
             },
            Else                                                                # The existing string has two or more blocks
             {$string->putNextandPrevBlockOffsetIntoZmm(31, $new,  $prev);      # From last block
              $string->putNextandPrevBlockOffsetIntoZmm(30, $next, $current);   # From new block
             };

            $string->putZmmBlock($new, 30);                                     # Save the modified block
           };

          $string->putZmmBlock($current, 31);                                   # Save the modified block
          PopR zmm31;                                                           # Restore stack
          Jmp $end;                                                             # Character successfully inserted
         };
       };

      my ($next, $prev) = $string->getNextAndPrevBlockOffsetFromZmm(31);        # Get links from current source block

      If $next == $F,
      Then                                                                      # Last source block
       {$c->setReg(r15);                                                        # Character to insert
        Push r15;
        Mov r15, rsp;                                                           # Address content on the stack
        $string->append($F, V(size, 1), V(source, r15));                        # Append character if we go beyond limit
        Pop  r15;
        Jmp $end;
       };

      $C += $L;                                                                 # Current character position at the start of the next block
      $current->copy($next);                                                    # Address next block
      $string->getZmmBlock($current, 31);                                       # Next block
      $L->copy($string->getBlockLength(31));                                    # Length of block
     };

    PopR;
   } parameters=>[qw(character position)],
     structures=>{string => $string},
     name => 'Nasm::X86::String::insertChar';

  $s->call(structures=>{string => $string},
           parameters=>{character => $character, position => $position});
 } #insertChar

sub Nasm::X86::String::deleteChar($$)                                           # Delete a character in a string.
 {my ($string, $position) = @_;                                                 # String, variable position in string
  @_ == 2 or confess "Two parameters";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    PushR k7, zmm31;
    my $string = $$s{string};                                                   # String
    my $F = $string->first;                                                     # The first block in string
    my $P = $$p{position};                                                      # The position in the string at which we want to insert the character

    $string->getZmmBlock($F, 31);                                               # The first source block

    my $C = V('Current character position', 0);                                 # Current character position
    my $L = $string->getBlockLength(31);                                        # Length of last block
    my $current = $F->clone('current');                                         # Current position in scan of block chain

    ForEver                                                                     # Each block in source string
     {my ($start, $end) = @_;                                                   # Start and end labels

      If $P >= $C,
      Then                                                                      # Position is in current block
       {If $P <= $C + $L,
        Then                                                                    # Position is in current block
         {my $O = $P - $C;                                                      # Offset in current block
          PushR zmm31;                                                          # Stack block
          ($O+1)->setMask($L - $O, k7);                                         # Set mask for reload
          Vmovdqu8 "zmm31{k7}", "[rsp+1]";                                      # Reload
          $string->setBlockLengthInZmm($L-1, 31);                               # Length of block
          $string->putZmmBlock($current, 31);                                   # Save the modified block
          PopR zmm31;                                                           # Stack block
          Jmp $end;                                                             # Character successfully inserted
         };
       };

      my ($next, $prev) = $string->getNextAndPrevBlockOffsetFromZmm(31);        # Get links from current source block
      $string->getZmmBlock($next, 31);                                          # Next block
      $current->copy($next);
      $L->copy($string->getBlockLength(31));                                    # Length of block
      $C += $L;                                                                 # Current character position at the start of this block
     };

    PopR;
   } parameters=>[qw(position)],
     structures=>{string=>$string},
     name => 'Nasm::X86::String::deleteChar';

  $s->call(parameters=>{position => $position}, structures=>{string => $string});
 }

sub Nasm::X86::String::getCharacter($$)                                         # Get a character from a string at the variable position.
 {my ($string, $position) = @_;                                                 # String, variable position
  @_ == 2 or confess "Two parameters";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    PushR r15, zmm31;
    my $string = $$s{string};                                                   # String
    my $F = $string->first;                                                     # The first block in string
    my $P = $$p{position};                                                      # The position in the string at which we want to insert the character

    $string->getZmmBlock($F, 31);                                               # The first source block
    my $C = V('Current character position', 0);                                 # Current character position
    my $L = $string->getBlockLength(31);                                        # Length of last block

    ForEver                                                                     # Each block in source string
     {my ($start, $end) = @_;                                                   # Start and end labels

      If $P >= $C,
      Then                                                                      # Position is in current block
       {If $P <= $C + $L,
        Then                                                                    # Position is in current block
         {my $O = $P - $C;                                                      # Offset in current block
          PushR zmm31;                                                          # Stack block
          ($O+1)  ->setReg(r15);                                                # Character to get
          Mov r15b, "[rsp+r15]";                                                # Reload
          $$p{out}->getReg(r15);                                                # Save character
          PopR zmm31;                                                           # Stack block
          Jmp $end;                                                             # Character successfully inserted
         };
       };

      my ($next, $prev) = $string->getNextAndPrevBlockOffsetFromZmm(31);        # Get links from current source block
      $string->getZmmBlock($next, 31);                                          # Next block
      $L = $string->getBlockLength(31);                                         # Length of block
      $C += $L;                                                                 # Current character position at the start of this block
     };

    PopR;
   } parameters => [qw(position out)],
     structures => {string => $string},
     name       => 'Nasm::X86::String::getCharacter';

  $s->call(parameters=>{position=>$position, out => my $out = V('out')},
     structures=>{string => $string});

  $out
 }

sub Nasm::X86::String::append($$$)                                              # Append the specified content in memory to the specified string.
 {my ($string, $source, $size) = @_;                                            # String descriptor, variable source address, variable length
  @_ >= 3 or confess;

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    my $Z       = K(zero, 0);                                                   # Zero
    my $O       = K(one,  1);                                                   # One
    my $string  = $$s{string};
    my $first   = $string->first;                                               # First (preallocated) block in string

    my $source  = $$p{source}->clone('source');                                 # Address of content to be appended
    my $size    = $$p{size}  ->clone('size');                                   # Size of content
    my $L       = V(size, $string->length);                                     # Length of string

    PushZmm 29..31;
    ForEver                                                                     # Append content until source exhausted
     {my ($start, $end) = @_;                                                   # Parameters

      $string->getZmmBlock($first, 29);                                         # Get the first block
      my ($second, $last) = $string->getNextAndPrevBlockOffsetFromZmm(29);      # Get the offsets of the second and last blocks
      $string->getZmmBlock($last,  31);                                         # Get the last block
      my $lengthLast      = $string->getBlockLength(31);                        # Length of last block
      my $spaceLast       = $L - $lengthLast;                                   # Space in last block
      my $toCopy          = $spaceLast->min($size);                             # Amount of data required to fill first block
      my $startPos        = $O + $lengthLast;                                   # Start position in zmm

      $source->setZmm(31, $startPos, $toCopy);                                  # Append bytes
      $string->setBlockLengthInZmm($lengthLast + $toCopy, 31);                  # Set the length
      $string->putZmmBlock($last, 31);                                          # Put the block
      If $size <= $spaceLast, sub {Jmp $end};                                   # We are finished because the last block had enough space
      $source += $toCopy;                                                       # Remaining source
      $size   -= $toCopy;                                                       # Remaining source length

      my $new = $string->allocBlock;                                            # Allocate new block
      $string->getZmmBlock($new, 30);                                           # Load the new block
      ClearRegisters zmm30;
      my ($next, $prev) = $string->getNextAndPrevBlockOffsetFromZmm(31);        # Linkage from last block

      If $first == $last,
      Then                                                                      # The existing string has one block, add new as the second block
        {$string->putNextandPrevBlockOffsetIntoZmm(31, $new,  $new);
         $string->putNextandPrevBlockOffsetIntoZmm(30, $last, $last);
        },
      Else                                                                      # The existing string has two or more blocks
       {$string->putNextandPrevBlockOffsetIntoZmm(31, $new,    $prev);          # From last block
        $string->putNextandPrevBlockOffsetIntoZmm(30, $next,   $last);          # From new block
        $string->putNextandPrevBlockOffsetIntoZmm(29, undef,   $new);           # From first block
        $string->putZmmBlock($first, 29);                                       # Put the modified last block
        };

      $string->putZmmBlock($last, 31);                                          # Put the modified last block
      $string->putZmmBlock($new,  30);                                          # Put the modified new block
     };
    PopZmm;
   }  parameters=>[qw(source size)],
      structures=>{string => $string},
     name => 'Nasm::X86::String::append';

  $s->call(structures => {string => $string},
           parameters => {source => $source, size => $size});
 }

sub Nasm::X86::String::appendShortString($$)                                    # Append the content of the specified short string to the string.
 {my ($string, $short) = @_;                                                    # String descriptor, short string
  @_ == 2 or confess "Two parameters";
  my $z = $short->z;                                                            # Zmm register containing short string
  PushR r15, $z;                                                                # Save short string on stack
  my $L = $short->len;                                                          # Length of short string
  Mov r15, rsp;                                                                 # Step over length
  Inc r15;                                                                      # Data of short string on stack without preceding length byte
  my $S = V(source, r15);                                                       # String to append  is on the stack
  $string->append($S, $L);                                                      # Append the short string data on the stack
  PopR;
 }

sub Nasm::X86::String::appendVar($$)                                            # Append the content of the specified variable to a string.
 {my ($string, $var) = @_;                                                      # String descriptor, short string
  @_ == 2 or confess "Two parameters";
  PushR r15;
  $var->setReg(r15);                                                            # Value of variable
  PushR r15;                                                                    # Put value of variable on the stack
  Mov r15, rsp;                                                                 # Step over length
  $string->append(V(address => r15), V(size => $var->width));                   # Append the short string data on the stack
  PopR;
  PopR;
 }

sub Nasm::X86::String::saveToShortString($$;$)                                  # Place as much as possible of the specified string into the specified short string.
 {my ($string, $short, $first) = @_;                                            # String descriptor, short string descriptor, optional offset to first block of string
  @_ == 2 or confess "Two parameters";
  my $z = $short->z; $z eq zmm31 and confess "Cannot use zmm31";                # Zmm register in short string to load must not be zmm31

  my $s = Subroutine2       ### At the moment we only read the first block - we need to read more data out of the string if necessary
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    PushR k7, zmm31, r14, r15;

    my $string = $$s{string};                                                   # String

    $string->getZmmBlock($string->first, 31);                                   # The first block in zmm31

    Mov r15, -1; Shr r15, 1; Shl r15, 9; Shr r15, 8; Kmovq k7, r15;             # Mask for the most we can get out of a block of the string
    $short->clear;
    Vmovdqu8 "${z}{k7}", zmm31;                                                 # Move all the data in the first block

    my $b = $string->getBlockLength(31);                                        # Length of block
    $short->setLength($b);                                                      # Set length of short string

    PopR;
   } structures=>{string => $string},
     name => "Nasm::X86::String::saveToShortString_$z";                         # Separate by zmm register being loaded

  $s->call(structures=>{string => $string});

  $short                                                                        # Chain
 }

sub Nasm::X86::String::getQ1($)                                                 # Get the first quad word in a string and return it as a variable.
 {my ($string) = @_;                                                            # String descriptor
  @_ == 1 or confess "One parameter";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    my $string = $$s{string};                                                   # String

    PushR r8, r9, zmm0;
    $string->arena->getZmmBlock($string->first, 0, r8, r9);                     # Load the first block on the free chain
    Psrldq xmm0, $string->lengthWidth;                                          # Shift off the length field of the long string block
    Pextrq r8, xmm0, 0;                                                         # Extract first quad word
    $$p{q1}->getReg(r8);                                                        # Return first quad word  as a variable
    PopR;
   } parameters => [qw(q1)],
     structures => {string => $string},
     name       => "Nasm::X86::String::getQ1";

  $s->call(parameters=>{q1 => my $q = V q1 => -1},
           structures=>{string => $string});

  $q
 }

sub Nasm::X86::String::clear($)                                                 # Clear the string by freeing all but the first block and putting the remainder on the free chain addressed by Yggdrasil.
 {my ($string) = @_;                                                            # String descriptor
  @_ == 1 or confess "One parameter";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    my $string = $$s{string};                                                   # String

    PushR rax, r14, r15; PushZmm 29..31;

    my $first = $string->first;                                                 # First block
    $string->getZmmBlock($first, 29);                                           # Get the first block
    my ($second, $last) = $string->getNextAndPrevBlockOffsetFromZmm(29);        # Get the offsets of the second and last blocks
    ClearRegisters zmm29;                                                       # Clear first block to empty string
    $string->putNextandPrevBlockOffsetIntoZmm(29, $first, $first);              # Initialize block chain so string is ready for reuse
    $string->putZmmBlock($first, 29);                                           # Put the first block to make an empty string

    If $last != $first,
    Then                                                                        # Two or more blocks on the chain
     {my $ffb = $string->arena->firstFreeBlock;                                 # First free block

      If $second == $last,
      Then                                                                      # Two blocks on the chain
       {ClearRegisters zmm30;                                                   # Second block
        $string->putNextandPrevBlockOffsetIntoZmm(30, $ffb, undef);             # Put second block on head of the list
        $string->putZmmBlock($second, 30);                                      # Put the second block
       },
      Else                                                                      # Three or more blocks on the chain
       {my $z = V(zero, 0);                                                     # A variable with zero in it
        $string->getZmmBlock($second, 30);                                      # Get the second block
        $string->getZmmBlock($last,   31);                                      # Get the last block
        $string->putNextandPrevBlockOffsetIntoZmm(30, undef, $z);               # Reset prev pointer in second block
        $string->putNextandPrevBlockOffsetIntoZmm(31, $ffb, undef);             # Reset next pointer in last block to remainder of free chain
        $string->putZmmBlock($second, 30);                                      # Put the second block
        $string->putZmmBlock($last, 31);                                        # Put the last block
       };
      $string->arena->setFirstFreeBlock($second);                               # The second block becomes the head of the free chain
     };

    PopZmm; PopR;
   } structures=>{string=>$string}, name => 'Nasm::X86::String::clear';

  $s->call(structures=>{string=>$string});
 }

sub Nasm::X86::String::free($)                                                  # Free a string by putting all of its blocks on the free chain addressed by Yggdrasil .
 {my ($string) = @_;                                                            # String descriptor
  @_ == 1 or confess "One parameter";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    my $string = $$s{string};                                                   # String

    PushR rax, r14, r15; PushZmm  30..31;

    my $first = $string->first;                                                 # First block
    $string->getZmmBlock($first,  30);                                          # Get the first block
    my ($second, $last) = $string->getNextAndPrevBlockOffsetFromZmm(30);        # Get the offsets of the second and last blocks

    my $ffb = $string->arena->firstFreeBlock;                                   # First free block
    $string->getZmmBlock($last,   31);                                          # Get the last block
    $string->putNextandPrevBlockOffsetIntoZmm(31, $ffb, undef);                 # Reset next pointer in last block to remainder of free chain
    $string->arena->setFirstFreeBlock($first);                                  # The first block becomes the head of the free chain
    $string->putZmmBlock($first,  30);                                          # Put the second block
    $string->putZmmBlock($last,   31);                                          # Put the last block

    PopZmm; PopR;
   } structures=>{string => $string}, name => 'Nasm::X86::String::free';

  $s->call(structures=>{string => $string});
 }

#D1 Array                                                                       # Array constructed as a set of blocks in an arena

sub DescribeArray(%)                                                            # Describe a dynamic array held in an arena.
 {my (%options) = @_;                                                           # Array description
  my $b = RegisterSize zmm0;                                                    # Size of a block == size of a zmm register
  my $o = RegisterSize eax;                                                     # Size of a double word

  my $a = genHash(__PACKAGE__."::Array",                                        # Array definition
    arena  => ($options{arena} // DescribeArena),                               # Variable address of arena for array
    width  => $o,                                                               # Width of each element
    first  => ($options{first} // V('first')),                                  # Variable addressing first block in array
    slots1 => $b / $o - 1,                                                      # Number of slots in first block
    slots2 => $b / $o,                                                          # Number of slots in second and subsequent blocks
   );

  $a->slots2 == 16 or confess "Number of slots per block not 16";               # Slots per block check

  $a                                                                            # Description of array
 }

sub Nasm::X86::Arena::DescribeArray($%)                                         # Describe a dynamic array held in an arena.
 {my ($arena, %options) = @_;                                                   # Arena description, options
  @_ >= 1 or confess "One or more parameters";
  DescribeArray(arena => $arena, %options)
 }

sub Nasm::X86::Arena::CreateArray($)                                            # Create a dynamic array held in an arena.
 {my ($arena) = @_;                                                             # Arena description
  @_ == 1 or confess "One parameter";

  $arena->DescribeArray(first => $arena->allocZmmBlock);                        # Describe array
 }

sub Nasm::X86::Array::allocBlock($)                                             #P Allocate a block to hold a zmm register in the specified arena and return the offset of the block in a variable.
 {my ($array) = @_;                                                             # Array descriptor
  @_ == 1 or confess "One parameter";

  $array->arena->allocBlock;
 }

sub Nasm::X86::Array::dump($)                                                   # Dump a array.
 {my ($array) = @_;                                                             # Array descriptor
  @_ >= 1 or confess;
  my $W = RegisterSize zmm0;                                                    # The size of a block
  my $w = $array->width;                                                        # The size of an entry in a block
  my $n = $array->slots1;                                                       # The number of slots per block
  my $N = $array->slots2;                                                       # The number of slots per block

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $array = $$s{array};                                                     # Array
    my $F     = $array->first;                                                  # First
    my $arena = $array->arena;                                                  # Arena

    PushR (r8, zmm30, zmm31);
    $arena->getZmmBlock($F, 31);                                                # Get the first block
    my $size = dFromZ 31, 0;                                                    # Size of array
    PrintOutStringNL("array");
    $size->out("Size: ", "  ");
    PrintOutRegisterInHex zmm31;

    If $size > $n,
    Then                                                                        # Array has secondary blocks
     {my $T = $size / $N;                                                       # Number of full blocks

      $T->for(sub                                                               # Print out each block
       {my ($index, $start, $next, $end) = @_;                                  # Execute block
        my $S = dFromZ 31, ($index + 1) * $w;                                   # Address secondary block from first block
        $arena->getZmmBlock($S, 30);                                            # Get the secondary block
        $S->out("Full: ", "  ");
        PrintOutRegisterInHex zmm30;
       });

      my $lastBlockCount = $size % $N;                                          # Number of elements in the last block
      If $lastBlockCount > 0, sub                                               # Print non empty last block
       {my $S = dFromZ 31, ($T + 1) * $w;                                       # Address secondary block from first block
        $arena->getZmmBlock($S, 30);                                            # Get the secondary block
        $S->out("Last: ", "  ");
        PrintOutRegisterInHex zmm30;
       };
     };

    PopR;
   } structures => {array => $array},
     name       => q(Nasm::X86::Array::dump);

  $s->call(structures => {array => $array});
 }

sub Nasm::X86::Array::push($$)                                                  # Push a variable element onto an array.
 {my ($array, $element) = @_;                                                   # Array descriptor, variable element to push
  @_ == 2 or confess "Two parameters";

  my $W = RegisterSize zmm0;                                                    # The size of a block
  my $w = $array->width;                                                        # The size of an entry in a block
  my $n = $array->slots1;                                                       # The number of slots per block
  my $N = $array->slots2;                                                       # The number of slots per block

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $success = Label;                                                        # Short circuit if ladders by jumping directly to the end after a successful push

    my $array = $$s{array};                                                     # Array
    my $arena = $array->arena;                                                  # Arena
    my $F = $array->first;                                                      # First block
    my $E = $$s{element};                                                       # The element to be inserted

    PushR r8, zmm31;
    my $transfer = r8;                                                          # Transfer data from zmm to variable via this register

    $arena->getZmmBlock($F, 31);                                                # Get the first block
    my $size = dFromZ 31, 0;                                                    # Size of array

    If $size < $n,
    Then                                                                        # Room in the first block
     {$E       ->dIntoZ(31, ($size + 1) * $w);                                  # Place element
      ($size+1)->dIntoZ(31, 0);                                                 # Update size
      $arena   ->putZmmBlock($F, 31);                                           # Put the first block back into memory
      Jmp $success;                                                             # Element successfully inserted in first block
     };

    If $size == $n,
    Then                                                                        # Migrate the first block to the second block and fill in the last slot
     {PushR (rax, k7, zmm30);
      Mov rax, -2;                                                              # Load compression mask
      Kmovq k7, rax;                                                            # Set  compression mask
      Vpcompressd "zmm30{k7}{z}", zmm31;                                        # Compress first block into second block
      ClearRegisters zmm31;                                                     # Clear first block
      ($size+1)->dIntoZ(31, 0);                                                 # Save new size in first block
      my $new = $arena->allocZmmBlock;                                          # Allocate new block
      $new->dIntoZ(31, $w);                                                     # Save offset of second block in first block
      $E  ->dIntoZ(30, $W - 1 * $w);                                            # Place new element
      $arena->putZmmBlock($new, 30);                                            # Put the second block back into memory
      $arena->putZmmBlock($F,   31);                                            # Put the first  block back into memory
      PopR;
      Jmp $success;                                                             # Element successfully inserted in second block
     };

    If $size <= $N * ($N - 1),
    Then                                                                        # Still within two levels
     {If $size % $N == 0,
      Then                                                                      # New secondary block needed
       {PushR (rax, zmm30);
        my $new = $arena->allocZmmBlock;                                        # Allocate new block
        $E       ->dIntoZ(30, 0);                                               # Place new element last in new second block
        ($size+1)->dIntoZ(31, 0);                                               # Save new size in first block
        $new     ->dIntoZ(31, ($size / $N + 1) * $w);                           # Address new second block from first block
        $arena   ->putZmmBlock($new, 30);                                       # Put the second block back into memory
        $arena   ->putZmmBlock($F,   31);                                       # Put the first  block back into memory
        PopR;
        Jmp $success;                                                           # Element successfully inserted in second block
       };

      if (1)                                                                    # Continue with existing secondary block
       {PushR (rax, r14, zmm30);
        my $S = dFromZ 31, ($size / $N + 1) * $w;                               # Offset of second block in first block
        $arena   ->getZmmBlock($S, 30);                                         # Get the second block
        $E       ->dIntoZ( 30, ($size % $N) * $w);                              # Place new element last in new second block
        ($size+1)->dIntoZ( 31, 0);                                              # Save new size in first block
        $arena   ->putZmmBlock($S, 30);                                         # Put the second block back into memory
        $arena   ->putZmmBlock($F, 31);                                         # Put the first  block back into memory
        PopR;
        Jmp $success;                                                           # Element successfully inserted in second block
       }
     };

    SetLabel $success;
    PopR;
   } structures => {array=>$array, element=>$element},
     name       => 'Nasm::X86::Array::push';

  $s->call(structures => {array=>$array, element=>$element});
 }

sub Nasm::X86::Array::pop($)                                                    # Pop an element from an array and return it in a variable.
 {my ($array) = @_;                                                             # Array descriptor
  @_ == 1 or confess "One parameter";
  my $W = RegisterSize zmm0;                                                    # The size of a block
  my $w = $array->width;                                                        # The size of an entry in a block
  my $n = $array->slots1;                                                       # The number of slots per block
  my $N = $array->slots2;                                                       # The number of slots per block

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $success = Label;                                                        # Short circuit if ladders by jumping directly to the end after a successful push

    my $E = $$p{element};                                                       # The element being popped

    my $array = $$s{array};                                                     # Array
    my $arena = $array->arena;                                                     # Arena
    my $F     = $array->first;                                                  # First block of array

    PushR r8, zmm31;
    my $transfer = r8;                                                          # Transfer data from zmm to variable via this register
    $arena->getZmmBlock($F, 31);                                                # Get the first block
    my $size = dFromZ 31, 0;                                                    # Size of array

    If $size > 0,
    Then                                                                        # Array has elements
     {If $size <= $n,
      Then                                                                      # In the first block
       {$E       ->dFromZ(31, $size * $w);                                      # Get element
        ($size-1)->dIntoZ(31, 0);                                               # Update size
        $arena   ->putZmmBlock($F, 31);                                         # Put the first block back into memory
        Jmp $success;                                                           # Element successfully retrieved from secondary block
       };

      If $size == $N,
      Then                                                                      # Migrate the second block to the first block now that the last slot is empty
       {PushR (rax, k7, zmm30);
        my $S = dFromZ 31, $w;                                                  # Offset of second block in first block
        $arena->getZmmBlock($S, 30);                                            # Get the second block
        $E->dFromZ(30, $n * $w);                                                # Get element from second block
        Mov rax, -2;                                                            # Load expansion mask
        Kmovq k7, rax;                                                          # Set  expansion mask
        Vpexpandd "zmm31{k7}{z}", zmm30;                                        # Expand second block into first block
        ($size-1)->dIntoZ(31, 0);                                               # Save new size in first block
        $arena-> putZmmBlock($F, 31);                                           # Save the first block
        $arena->freeZmmBlock($S);                                               # Free the now redundant second block
        PopR;
        Jmp $success;                                                           # Element successfully retrieved from secondary block
       };

      If $size <= $N * ($N - 1),
      Then                                                                      # Still within two levels
       {If $size % $N == 1,
       Then                                                                     # Secondary block can be freed
         {PushR (rax, zmm30);
          my $S = dFromZ 31, ($size / $N + 1) * $w;                             # Address secondary block from first block
          $arena    ->getZmmBlock($S, 30);                                      # Load secondary block
          $E->dFromZ(30, 0);                                                    # Get first element from secondary block
          V(zero, 0)->dIntoZ(31, ($size / $N + 1) * $w);                        # Zero at offset of secondary block in first block
          ($size-1)->dIntoZ(31, 0);                                             # Save new size in first block
          $arena->freeZmmBlock($S);                                             # Free the secondary block
          $arena->putZmmBlock ($F, 31);                                         # Put the first  block back into memory
          PopR;
          Jmp $success;                                                         # Element successfully retrieved from secondary block
         };

        if (1)                                                                  # Continue with existing secondary block
         {PushR (rax, r14, zmm30);
          my $S = dFromZ 31, (($size-1) / $N + 1) * $w;                         # Offset of secondary block in first block
          $arena   ->getZmmBlock($S, 30);                                       # Get the secondary block
          $E       ->dFromZ(30, (($size - 1)  % $N) * $w);                      # Get element from secondary block
          ($size-1)->dIntoZ(31, 0);                                             # Save new size in first block
          $arena   ->putZmmBlock($S, 30);                                       # Put the secondary block back into memory
          $arena   ->putZmmBlock($F, 31);                                       # Put the first  block back into memory
          PopR;
          Jmp $success;                                                         # Element successfully retrieved from secondary block
         }
       };
     };

    SetLabel $success;
    PopR;
   } parameters => [qw(element)],
     structures => {array=>$array},
     name       => 'Nasm::X86::Array::pop';

  $s->call
   (structures =>{array   => $array},
    parameters =>{element => my $element = V element => 0});

  $element
 }

sub Nasm::X86::Array::size($)                                                   # Return the size of an array as a variable.
 {my ($array) = @_;                                                             # Array
  @_ == 1 or confess "One parameter";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $success = Label;                                                        # Short circuit if ladders by jumping directly to the end after a successful push

    my $array = $$s{array};                                                     # Array
    my $arena = $array->arena;                                                  # Arena

    PushR zmm31, my $transfer = r8;
    $arena->getZmmBlock($array->first, 31);                                     # Get the first block
    $$p{size}->copy(dFromZ(31, 0));                                             # Size of array

    SetLabel $success;
    PopR;
   }  structures => {array=>$array},
      parameters => [qw(size)],
      name       => 'Nasm::X86::Array::size';

  $s->call(structures => {array => $array},                                     # Get the size of the array
           parameters => {size  => my $size = V(size => 0)});

  $size                                                                         # Return size as a variable
 }

sub Nasm::X86::Array::get($$)                                                   # Get an element from the array.
 {my ($array, $index) = @_;                                                     # Array descriptor, variables
  @_ == 2 or confess "Two parameters";
  my $W = RegisterSize zmm0;                                                    # The size of a block
  my $w = $array->width;                                                        # The size of an entry in a block
  my $n = $array->slots1;                                                       # The number of slots in the first block
  my $N = $array->slots2;                                                       # The number of slots in the secondary blocks

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $success = Label;                                                        # Short circuit if ladders by jumping directly to the end after a successful push

    my $E = $$p{element};                                                       # The element to be returned
    my $I = $$p{index};                                                         # Index of the element to be returned

    my $array = $$s{array};                                                     # Array
    my $F     = $array->first;                                                  # First block of array
    my $arena = $array->arena;                                                  # Arena

    PushR (r8, zmm31);
    my $transfer = r8;                                                          # Transfer data from zmm to variable via this register
    $arena->getZmmBlock($F, 31);                                                # Get the first block
    my $size = dFromZ 31, 0;                                                    # Size of array
    If $I < $size,
    Then                                                                        # Index is in array
     {If $size <= $n,
      Then                                                                      # Element is in the first block
       {$E->dFromZ(31, ($I + 1) * $w);                                          # Get element
        Jmp $success;                                                           # Element successfully inserted in first block
       };

      If $size <= $N * ($N - 1),
      Then                                                                      # Still within two levels
       {my $S = dFromZ 31, ($I / $N + 1) * $w;                                  # Offset of second block in first block
        $arena->getZmmBlock($S, 31);                                            # Get the second block
        $E->dFromZ(31, ($I % $N) * $w);                                         # Offset of element in second block
        Jmp $success;                                                           # Element successfully inserted in second block
       };
     };

    PrintErrString "Index out of bounds on get from array, ";                   # Array index out of bounds
    $I->err("Index: "); PrintErrString "  "; $size->errNL("Size: ");
    Exit(1);

    SetLabel $success;
    PopR;
   } parameters => [qw(index element)],
     structures => {array => $array},
     name       => 'Nasm::X86::Array::get';

  $s->call(structures=>{array=>$array},
           parameters=>{index=>$index, element => my $e = V element => 0});
  $e
 }

sub Nasm::X86::Array::put($$$)                                                  # Put an element into an array at the specified index as long as it is with in its limits established by pushing.
 {my ($array, $index, $element) = @_;                                           # Array descriptor, index as a variable, element as a variable - bu t only the lowest four bytes will be stored in the array
  @_ == 3 or confess 'Three parameters';

  my $W = RegisterSize zmm0;                                                    # The size of a block
  my $w = $array->width;                                                        # The size of an entry in a block
  my $n = $array->slots1;                                                       # The number of slots in the first block
  my $N = $array->slots2;                                                       # The number of slots in the secondary blocks

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $success = Label;                                                        # Short circuit if ladders by jumping directly to the end after a successful push

    my $E = $$p{element};                                                       # The element to be added
    my $I = $$p{index};                                                         # Index of the element to be inserted

    my $array = $$s{array};                                                     # Array
    my $F     = $array->first;                                                  # First block of array
    my $arena = $array->arena;                                                  # Arena

    PushR (r8, zmm31);
    my $transfer = r8;                                                          # Transfer data from zmm to variable via this register
    $arena->getZmmBlock($F, 31);                                                # Get the first block
    my $size = dFromZ 31, 0;                                                    # Size of array
    If $I < $size,
    Then                                                                        # Index is in array
     {If $size <= $n,
       Then                                                                     # Element is in the first block
       {$E->dIntoZ(31, ($I + 1) * $w);                                          # Put element
        $arena->putZmmBlock($F, 31);                                            # Get the first block
        Jmp $success;                                                           # Element successfully inserted in first block
       };

      If $size <= $N * ($N - 1),
      Then                                                                      # Still within two levels
       {my $S = dFromZ 31, ($I / $N + 1) * $w;                                  # Offset of second block in first block
        $arena->getZmmBlock($S, 31);                                            # Get the second block
        $E->dIntoZ(31, ($I % $N) * $w);                                         # Put the element into the second block in first block
        $arena->putZmmBlock($S, 31);                                            # Get the first block
        Jmp $success;                                                           # Element successfully inserted in second block
       };
     };

    PrintErrString "Index out of bounds on put to array, ";                     # Array index out of bounds
    $I->err("Index: "); PrintErrString "  "; $size->errNL("Size: ");
    Exit(1);

    SetLabel $success;
    PopR;
   } parameters=>[qw(index element)],
     structures=>{array=>$array}, name => 'Nasm::X86::Array::put';

  $s->call(parameters=>{index=>$index, element => $element},
           structures=>{array=>$array});
 }

#D1 Tree                                                                        # Tree constructed as sets of blocks in an arena.

sub DescribeTree(%)                                                             # Return a descriptor for a tree with the specified options.
 {my (%options) = @_;                                                           # Tree description options

  confess "Maximum keys must be less than or equal to 14"
    unless ($options{length}//0) <= 14;                                         # Maximum number of keys is 14

  my $b = RegisterSize 31;                                                      # Size of a block == size of a zmm register
  my $o = RegisterSize eax;                                                     # Size of a double word

  my $keyAreaWidth = $b - $o * 2 ;                                              # Key / data area width  in bytes
  my $length = $options{length} // $keyAreaWidth / $o;                          # Length of block to split

  my $l2 = int($length/2);                                                      # Minimum length of length after splitting

  genHash(__PACKAGE__."::Tree",                                                 # Tree
    arena        => ($options{arena} // DescribeArena),                         # Arena definition.
    length       => $length,                                                    # Number of keys in a maximal block
    lengthLeft   => $l2,                                                        # Left minimal number of keys
    lengthMiddle => $l2 + 1,                                                    # Number of splitting key counting from 1
    lengthMin    => $length - 1 - $l2,                                          # The smallest number of keys we are allowed in any node other than a root node.
    lengthOffset => $keyAreaWidth,                                              # Offset of length in keys block.  The length field is a word - see: "MultiWayTree.svg"
    lengthRight  => $length - 1 - $l2,                                          # Right minimal number of keys
    loop         => $b - $o,                                                    # Offset of keys, data, node loop.
    maxKeys      => $length,                                                    # Maximum number of keys allowed in this tree which might well ne less than the maximum we can store in a zmm.
    offset       => V(offset  => 0),                                            # Offset of last node found
    splittingKey => ($l2 + 1) * $o,                                             # Offset at which to split a full block
    treeBits     => $keyAreaWidth + 2,                                          # Offset of tree bits in keys block.  The tree bits field is a word, each bit of which tells us whether the corresponding data element is the offset (or not) to a sub tree of this tree .
    treeBitsMask => 0x3fff,                                                     # Total of 14 tree bits
    keyDataMask  => 0x3fff,                                                     # Key data mask
    nodeMask     => 0x7fff,                                                     # Node mask
    up           => $keyAreaWidth,                                              # Offset of up in data block.
    width        => $o,                                                         # Width of a key or data slot.
    zWidth       => $b,                                                         # Width of a zmm register
    zWidthD      => $b / $o,                                                    # Width of a zmm in double words being the element size
    maxKeysZ     => $b / $o - 2,                                                # The maximum possible number of keys in a zmm register
    maxNodesZ    => $b / $o - 1,                                                # The maximum possible number of nodes in a zmm register

    rootOffset   => $o * 0,                                                     # Offset of the root field in the first block - the root field contains the offset of the block containing the keys of the root of the tree
    upOffset     => $o * 1,                                                     # Offset of the up field which points to any containing tree
    sizeOffset   => $o * 2,                                                     # Offset of the size field which tells us the number of  keys in the tree
    middleOffset => $o * ($l2 + 0),                                             # Offset of the middle slot in bytes
    rightOffset  => $o * ($l2 + 1),                                             # Offset of the first right slot in bytes

    compare      => V(compare => 0),                                            # Last comparison result -1, 0, +1
    data         => V(data    => 0),                                            # Variable containing the current data
    debug        => V(debug   => 0),                                            # Write debug trace if true
    first        => V(first   => 0),                                            # Variable addressing offset to first block of the tree which is the header block
    found        => V(found   => 0),                                            # Variable indicating whether the last find was successful or not
    index        => V(index   => 0),                                            # Index of key in last node found
    key          => V(key     => 0),                                            # Variable containing the current key
    offset       => V(key     => 0),                                            # Variable containing the offset of the block containing the current key
    subTree      => V(subTree => 0),                                            # Variable indicating whether the last find found a sub tree
   )
 }

sub Nasm::X86::Arena::DescribeTree($%)                                          # Return a descriptor for a tree in the specified arena with the specified options.
 {my ($arena, %options) = @_;                                                   # Arena descriptor, options for tree
  @_ >= 1 or confess;

  DescribeTree(arena=>$arena, %options)
 }

sub Nasm::X86::Arena::CreateTree($%)                                            # Create a tree in an arena.
 {my ($arena, %options) = @_;                                                   # Arena description, tree options
  @_ % 2 == 1 or confess "Odd number of parameters required";

  my $tree = $arena->DescribeTree(%options);                                    # Return a descriptor for a tree in the specified arena

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    my $tree  = $$s{tree};                                                      # Tree
    $tree->first->copy($tree->arena->allocZmmBlock);                            # Allocate header

   } structures=>{arena => $arena, tree => $tree},
     name => 'Nasm::X86::Arena::CreateTree';

  $s->call(structures=>{arena => $arena, tree => $tree});

  $tree                                                                         # Description of array
 }

sub Nasm::X86::Tree::describeTree($%)                                           # Create a a description of a tree
 {my ($tree, %options) = @_;                                                    # Tree descriptor, {first=>first node of tree if not the existing first node; arena=>arena used by tree if not the existing arena}
  @_ >= 1 or confess "At least one parameter";

  $tree->arena->DescribeTree(%options);                                         # Return a descriptor for a tree
 }

sub Nasm::X86::Tree::copyDescription($)                                         # Make a copy of a tree descriptor
 {my ($tree) = @_;                                                              # Tree descriptor
  my $t = $tree->describeTree;

  $t->compare->copy = $tree->compare;                                           # Last comparison result -1, 0, +1
  $t->data   ->copy = $tree->data;                                              # Variable containing the last data found
  $t->debug  ->copy = $tree->debug;                                             # Write debug trace if true
  $t->first  ->copy = $tree->first;                                             # Variable addressing offset to first block of keys.
  $t->found  ->copy = $tree->found;                                             # Variable indicating whether the last find was successful or not
  $t->index  ->copy = $tree->index;                                             # Index of key in last node found
  $t->subTree->copy = $tree->subTree;                                           # Variable indicating whether the last find found a sub tree
  $t                                                                            # Return new descriptor
 }

sub Nasm::X86::Tree::firstFromMemory($$)                                        # Load the first block for a tree into the numbered zmm.
 {my ($tree, $zmm) = @_;                                                        # Tree descriptor, number of zmm to contain first block
  @_ == 2 or confess "Two parameters";
  my $base = rdi; my $offset = rsi;
  $tree->arena->address->setReg($base);
  $tree->first->setReg($offset);
  Vmovdqu64 zmm($zmm), "[$base+$offset]";
 }

sub Nasm::X86::Tree::firstIntoMemory($$)                                        # Save the first block of a tree in the numbered zmm back into memory.
 {my ($tree, $zmm) = @_;                                                        # Tree descriptor, number of zmm containing first block
  @_ == 2 or confess "Two parameters";
  my $base = rdi; my $offset = rsi;
  $tree->arena->address->setReg($base);
  $tree->first->setReg($offset);
  Vmovdqu64  "[$base+$offset]", zmm($zmm);
 }

sub Nasm::X86::Tree::rootIntoFirst($$$)                                         # Put the contents of a variable into the root field of the first block of a tree when held in a zmm register.
 {my ($tree, $zmm, $value) = @_;                                                # Tree descriptor, number of zmm containing first block, variable containing value to put
  @_ == 3 or confess "Three parameters";
  $value->dIntoZ($zmm, $tree->rootOffset);
 }

sub Nasm::X86::Tree::rootFromFirst($$)                                          # Return a variable containing the offset of the root block of a tree from the first block when held in a zmm register.
 {my ($tree, $zmm) = @_;                                                        # Tree descriptor, variable containing value to put, number of zmm containing first block
  @_ == 2 or confess "Two parameters";
  dFromZ $zmm, $tree->rootOffset;
 }

sub Nasm::X86::Tree::root($$$)                                                  # Check whether the specified offset refers to the root of a tree when the first block is held in a zmm register. The result is returned by setting the zero flag to one if the offset is the root, else to zero.
 {my ($t, $F, $offset) = @_;                                                    # Tree descriptor, zmm register holding first block, offset of block as a variable
  @_ == 3 or confess "Three parameters";
  my $root = $t->rootFromFirst($F);                                             # Get the offset of the corresponding data block
  $root == $offset                                                              # Check whether the offset is in fact the root
 }

sub Nasm::X86::Tree::sizeFromFirst($$$)                                         # Return a variable containing the number of keys in the specified tree when the first block is held in a zmm register..
 {my ($tree, $zmm) = @_;                                                        # Tree descriptor, number of zmm containing first block
  @_ == 2 or confess "Two parameters";
  dFromZ $zmm, $tree->sizeOffset;
 }

sub Nasm::X86::Tree::sizeIntoFirst($$$)                                         # Put the contents of a variable into the size field of the first block of a tree  when the first block is held in a zmm register.
 {my ($tree, $value, $zmm) = @_;                                                # Tree descriptor, variable containing value to put, number of zmm containing first block
  @_ == 3 or confess "Three parameters";
  $value->dIntoZ($zmm, $tree->sizeOffset);
 }

sub Nasm::X86::Tree::incSizeInFirst($$)                                         # Increment the size field in the first block of a tree when the first block is held in a zmm register.
 {my ($tree, $zmm) = @_;                                                        # Tree descriptor, number of zmm containing first block
  @_ == 2 or confess "Two parameters";
  my $s = dFromZ $zmm, $tree->sizeOffset;
  $tree->sizeIntoFirst($s+1, $zmm);
 }

sub Nasm::X86::Tree::decSizeInFirst($$)                                         # Decrement the size field in the first block of a tree when the first block is held in a zmm register.
 {my ($tree, $zmm) = @_;                                                        # Tree descriptor, number of zmm containing first block
  @_ == 2 or confess "Two parameters";
  my $s = dFromZ $zmm, $tree->sizeOffset;
  If $s == 0,
  Then
   {PrintErrTraceBack "Cannot decrement zero length tree";
   };
  $tree->sizeIntoFirst($s-1, $zmm);
 }

sub Nasm::X86::Tree::size($)                                                    # Return in a variable the number of elements currently in the tree.
 {my ($tree) = @_;                                                              # Tree descriptor
  @_ == 1 or confess "One parameter";
  my $F = 31;
  PushR $F;
  $tree->firstFromMemory($F);
  my $s = $tree->sizeFromFirst($F);
  PopR;
  $s
 }

sub Nasm::X86::Tree::allocBlock($$$$)                                           #P Allocate a keys/data/node block and place it in the numbered zmm registers.
 {my ($tree, $K, $D, $N) = @_;                                                  # Tree descriptor, numbered zmm for keys, numbered zmm for data, numbered zmm for children
  @_ == 4 or confess "4 parameters";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    my $t = $$s{tree};                                                          # Tree
    my $arena = $t->arena;                                                      # Arena
    my $k = $arena->allocZmmBlock;                                              # Keys
    my $d = $arena->allocZmmBlock;                                              # Data
    my $n = $arena->allocZmmBlock;                                              # Children

    PushR r8;
    $t->putLoop($d, $K);                                                        # Set the link from key to data
    $t->putLoop($n, $D);                                                        # Set the link from data to node
    $t->putLoop($t->first, $N);                                                 # Set the link from node to tree first block

    $$p{address}->copy($k);                                                     # Address of block
    PopR r8;
   } structures => {tree => $tree},
     parameters => [qw(address)],
     name       => qq(Nasm::X86::Tree::allocBlock::${K}::${D}::${N});           # Create a subroutine for each combination of registers encountered

  $s->call(structures => {tree => $tree},
           parameters => {address =>  my $a = V address => 0});

  $a
 } # allocBlock

sub Nasm::X86::Tree::upFromData($$)                                             # Up from the data zmm in a block in a tree
 {my ($tree, $zmm) = @_;                                                        # Tree descriptor, number of zmm containing data block
  @_ == 2 or confess "Two parameters";
  dFromZ $zmm, $tree->up;
 }

sub Nasm::X86::Tree::upIntoData($$)                                             # Up into the data zmm in a block in a tree
 {my ($tree, $value, $zmm) = @_;                                                # Tree descriptor, variable containing value to put, number of zmm containing first block
  @_ == 3 or confess "Three parameters";
  $value->dIntoZ($zmm, $tree->up);
 }

sub Nasm::X86::Tree::lengthFromKeys($$)                                         #P Get the length of the keys block in the numbered zmm and return it as a variable.
 {my ($t, $zmm) = @_;                                                           # Tree descriptor, zmm number
  @_ == 2 or confess "Two parameters";

  bFromZ($zmm, $t->lengthOffset);                                               # The length field as a variable
 }

sub Nasm::X86::Tree::lengthIntoKeys($$$)                                        #P Get the length of the block in the numbered zmm from the specified variable.
 {my ($t, $zmm, $length) = @_;                                                  # Tree, zmm number, length variable
  @_ == 3 or confess "Three parameters";
  ref($length) or confess dump($length);
  $length->bIntoZ($zmm, $t->lengthOffset)                                       # Set the length field
 }

sub Nasm::X86::Tree::incLengthInKeys($$)                                        #P Increment the number of keys in a keys block or complain if such is not possible
 {my ($t, $K) = @_;                                                             # Tree, zmm number
  @_ == 2 or confess "Two parameters";
  my $l = $t->lengthOffset;                                                     # Offset of length bits
  PushR r15;
  ClearRegisters r15;
  bRegFromZmm r15, $K, $l;                                                      # Length
  Cmp r15, $t->length;
  IfLt
  Then
   {Inc r15;
    bRegIntoZmm r15, $K, $l;
   },
  Else
   {PrintErrTraceBack "Cannot increment length of block beyond ".$t->length;
   };
  PopR;
 }

sub Nasm::X86::Tree::decLengthInKeys($$)                                        #P Decrement the number of keys in a keys block or complain if such is not possible
 {my ($t, $K) = @_;                                                             # Tree, zmm number
  @_ == 2 or confess "Two parameters";
  my $l = $t->lengthOffset;                                                     # Offset of length bits
  PushR r15;
  ClearRegisters r15;
  bRegFromZmm r15, $K, $l;                                                      # Length
  Cmp r15, 0;
  IfGt
  Then
   {Dec r15;
    bRegIntoZmm r15, $K, $l;
   },
  Else
   {PrintErrTraceBack "Cannot decrement length of block below 0";
   };

  PopR;
 }

sub Nasm::X86::Tree::leafFromNodes($$)                                          #P Return a variable containing true if we are on a leaf.  We determine whether we are on a leaf by checking the offset of the first sub node.  If it is zero we are on a leaf otherwise not.
 {my ($tree, $zmm) = @_;                                                        # Tree descriptor, number of zmm containing node block
  @_ == 2 or confess "Two parameters";
  my $n = dFromZ $zmm, 0;                                                       # Get first node
  my $l = V leaf => 0;                                                          # Return a variable which is non zero if  this is a leaf
  If $n == 0, Then {$l->copy(1)};                                               # Leaf if the node is zero
  $l
 }

sub Nasm::X86::Tree::getLoop($$)                                                #P Return the value of the loop field as a variable.
 {my ($t, $zmm) = @_;                                                           # Tree descriptor, numbered zmm
  @_ == 2 or confess "Two parameters";
  dFromZ $zmm, $t->loop;                                                        # Get loop field as a variable
 }

sub Nasm::X86::Tree::putLoop($$$)                                               #P Set the value of the loop field from a variable.
 {my ($t, $value, $zmm) = @_;                                                   # Tree descriptor, variable containing offset of next loop entry, numbered zmm
  @_ == 3 or confess "Three parameters";
  $value->dIntoZ($zmm, $t->loop);                                               # Put loop field as a variable
 }

sub Nasm::X86::Tree::maskForFullKeyArea                                         # Place a mask for the full key area in the numbered mask register
 {my ($tree, $maskRegister) = @_;                                               # Tree description, mask register
  my $m = registerNameFromNumber $maskRegister;
  ClearRegisters $m;                                                            # Zero register
  Knotq $m, $m;                                                                 # Invert to fill with ones
  Kshiftrw $m, $m, 2;                                                           # Mask with ones in the full key area
 }

sub Nasm::X86::Tree::maskForFullNodesArea                                       # Place a mask for the full nodes area in the numbered mask register
 {my ($tree, $maskRegister) = @_;                                               # Tree description, mask register
  my $m = registerNameFromNumber $maskRegister;
  ClearRegisters $m;                                                            # Zero register
  Knotq $m, $m;                                                                 # Invert to fill with ones
  Kshiftrw $m, $m, 1;                                                           # Mask with ones in the full key area
 }

sub Nasm::X86::Tree::getBlock($$$$$)                                            #P Get the keys, data and child nodes for a tree node from the specified offset in the arena for the tree.
 {my ($t, $offset, $K, $D, $N) = @_;                                            # Tree descriptor, offset of block as a variable, numbered zmm for keys, numbered data for keys, numbered zmm for nodes
  @_ == 5 or confess "Five parameters";
  my $a = $t->arena;                                                            # Underlying arena
  $a->getZmmBlock($offset, $K);                                                 # Get the keys block
  my $data = $t->getLoop(  $K);                                                 # Get the offset of the corresponding data block
  $a->getZmmBlock($data,   $D);                                                 # Get the data block
  my $node = $t->getLoop  ($D);                                                 # Get the offset of the corresponding node block
  $a->getZmmBlock($node,   $N);                                                 # Get the node block
 }

sub Nasm::X86::Tree::putBlock($$$$$$)                                           #P Put a tree block held in three zmm registers back into the arena holding the tree at the specified offset.
 {my ($t, $offset, $K, $D, $N) = @_;                                            # Tree descriptor, offset of block as a variable, numbered zmm for keys, numbered data for keys, numbered zmm for nodes
  @_ == 5 or confess "Five parameters";
  my $a    = $t->arena;                                                         # Arena for tree
  my $data = $t->getLoop(  $K);                                                 # Get the offset of the corresponding data block
  my $node = $t->getLoop(  $D);                                                 # Get the offset of the corresponding node block
  $a->putZmmBlock($offset, $K);                                                 # Put the keys block
  $a->putZmmBlock($data,   $D);                                                 # Put the data block
  $a->putZmmBlock($node,   $N);                                                 # Put the node block
 }

sub Nasm::X86::Tree::overWriteKeyDataTreeInLeaf($$$$$$$)                        # Over write an existing key/data/sub tree triple in a set of zmm registers and set the tree bit as indicated.
 {my ($tree, $point, $K, $D, $IK, $ID, $subTree) = @_;                          # Point at which to overwrite formatted as a one in a sea of zeros, key, data, insert key, insert data, sub tree if tree.

  @_ == 7 or confess "Seven parameters";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    my $success = Label;                                                        # End label

    PushR 1..7, rdi;

    $$p{point}->setReg(rdi);                                                    # Load mask register showing point of insertion.
    Kmovq k7, rdi;                                                              # A sea of zeros with a one at the point of insertion

    $$p{key}  ->setReg(rdi); Vpbroadcastd zmmM($K, 7), edi;                     # Insert value at expansion point
    $$p{data} ->setReg(rdi); Vpbroadcastd zmmM($D, 7), edi;

    Kmovq rdi, k7;
    If $$p{subTree} > 0,                                                        # Set the inserted tree bit
    Then
     {$tree->setTreeBit ($K, rdi);
     },
    Else
     {$tree->clearTreeBit($K, rdi);
     };

    PopR;
   } name => "Nasm::X86::Tree::overWriteKeyDataTreeInLeaf($K, $D)",             # Different variants for different blocks of registers.
     structures => {tree=>$tree},
     parameters => [qw(point key data subTree)];

  $s->call(structures => {tree  => $tree},
           parameters => {key   => $IK, data => $ID,
                          point => $point, subTree => $subTree});
 }

sub Nasm::X86::Tree::indexXX($$$$)                                              # Return, as a variable, the mask obtained by performing a specified comparison on the key area of a node against a specified key.
 {my ($tree, $key, $K, $cmp) = @_;                                              # Tree definition, key as a variable, zmm containing keys, comparison from B<Vpcmp>
  @_ == 4 or confess "Four parameters";

  my $A = $K == 17 ? 18 : 17;                                                   # The broadcast facility 1 to 16 does not seem to work reliably so we load an alternate zmm
  PushR rcx, r14, r15, k7, $A;                                                  # Registers

  $key->setReg(r14);
  Vpbroadcastd zmm($A), r14d;                                                   # Load key to test
  Vpcmpud k7, zmm($K, $A), $cmp;                                                # Check keys from memory broadcast
  my $l = $tree->lengthFromKeys($K);                                            # Current length of the keys block
  $l->setReg(rcx);                                                              # Create a mask of ones that matches the width of a key node in the current tree.
  Mov   r15, 1;                                                                 # The one
  Shl   r15, cl;                                                                # Position the one at end of keys block
  Dec   r15;                                                                    # Reduce to fill block with ones
  Kmovq r14, k7;                                                                # Matching keys
  And   r15, r14;                                                               # Matching keys in mask area
  my $r = V index => r15;                                                       # Save result as a variable
  PopR;

  $r                                                                            # Point of key if non zero, else no match
 }

sub Nasm::X86::Tree::indexEq($$$)                                               # Return the  position of a key in a zmm equal to the specified key as a point in a variable.
 {my ($tree, $key, $K) = @_;                                                    # Tree definition, key as a variable, zmm containing keys
  @_ == 3 or confess "Three parameters";

  $tree->indexXX($key, $K, $Vpcmp->eq);                                         # Check for equal keys from the broadcasted memory
 }

sub Nasm::X86::Tree::insertionPoint($$$)                                        # Return the position at which a key should be inserted into a zmm as a point in a variable.
 {my ($tree, $key, $K) = @_;                                                    # Tree definition, key as a variable, zmm containing keys
  @_ == 3 or confess "Three parameters";

  $tree->indexXX($key, $K, $Vpcmp->le) + 1;                                     # Check for less than or equal keys
 }

sub Nasm::X86::Tree::insertKeyDataTreeIntoLeaf($$$$$$$$)                        # Insert a new key/data/sub tree triple into a set of zmm registers if there is room, increment the length of the node and set the tree bit as indicated and increment the number of elements in the tree.
 {my ($tree, $point, $F, $K, $D, $IK, $ID, $subTree) = @_;                      # Point at which to insert formatted as a one in a sea of zeros, first, key, data, insert key, insert data, sub tree if tree.

  @_ == 8 or confess "Eight parameters";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    my $success = Label;                                                        # End label
    my $t = $$s{tree};                                                          # Address tree

    my $W1 = r8;                                                                # Work register
    PushR 1..7, $W1;

    my $point = $$p{point};                                                     # Point at which to insert
    $$p{point}->setReg($W1);                                                    # Load mask register showing point of insertion.

    Kmovq k7, $W1;                                                              # A sea of zeros with a one at the point of insertion

    $t->maskForFullKeyArea(6);                                                  # Mask for key area

    Kandnq  k4, k7, k6;                                                         # Mask for key area with a hole at the insertion point

    Vpexpandd zmmM($K, 4), zmm($K);                                             # Expand to make room for the value to be inserted
    Vpexpandd zmmM($D, 4), zmm($D);

    $$p{key}  ->setReg($W1); Vpbroadcastd zmmM($K, 7), $W1."d";                 # Insert value at expansion point
    $$p{data} ->setReg($W1); Vpbroadcastd zmmM($D, 7), $W1."d";

    $t->incLengthInKeys($K);                                                    # Increment the length of this node to include the inserted value

    $t->insertIntoTreeBits($K, 7, $$p{subTree});                                # Set the matching tree bit depending on whether we were supplied with a tree or a variable

    $t->incSizeInFirst($F);                                                     # Update number of elements in entire tree.

    PopR;
   } name => "Nasm::X86::Tree::insertKeyDataTreeIntoLeaf($F, $K, $D)",          # Different variants for different blocks of registers.
     structures => {tree=>$tree},
     parameters => [qw(point key data subTree)];

  $s->call(structures => {tree  => $tree},
           parameters => {key   => $IK, data => $ID,
                          point => $point, subTree => $subTree});
 }

sub Nasm::X86::Tree::splitNode($$)                                              #P Split a node if it it is full returning a variable that indicates whether a split occurred or not.
 {my ($tree, $offset) = @_;                                                     # Tree descriptor,  offset of block in arena of tree as a variable
  @_ == 2 or confess 'Two parameters';

  my $PK = 31; my $PD = 30; my $PN = 29;                                        # Key, data, node blocks
  my $LK = 28; my $LD = 27; my $LN = 26;
  my $RK = 25; my $RD = 24; my $RN = 23;
  my $F  = 22;
                                                                                # First block of this tree
  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $success = Label;                                                        # Short circuit if ladders by jumping directly to the end after a successful push

    my $t     = $$s{tree};                                                      # Tree
    my $arena = $t->arena;                                                      # Arena

    PushR ((my $W1 = r8), (my $W2 = r9)); PushZmm 22...31;
    ClearRegisters 22..31;                                                      # Otherwise we get left over junk

    my $offset = $$p{offset};                                                   # Offset of block in arena
    my $split  = $$p{split};                                                    # Indicate whether we split or not
    $t->getBlock($offset, $LK, $LD, $LN);                                       # Load node as left

    my $length = $t->lengthFromKeys($LK);
    If $t->lengthFromKeys($LK) < $t->maxKeys,
    Then                                                                        # Only split full blocks
     {$split->copy(K split => 0);                                               # Split not required
      Jmp $success;
     };

    my $parent = $t->upFromData($LD);                                           # Parent of this block

    my $r = $t->allocBlock    ($RK, $RD, $RN);                                  # Create a new right block
    If $parent > 0,
    Then                                                                        # Not the root node because it has a parent
     {$t->upIntoData      ($parent, $RD);                                       # Address existing parent from new right
      $t->getBlock        ($parent, $PK, $PD, $PN);                             # Load extant parent
      $t->splitNotRoot
                          ($r,      $PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN);
      $t->putBlock        ($parent, $PK, $PD, $PN);
      $t->putBlock        ($offset, $LK, $LD, $LN);
     },
    Else                                                                        # Split the root node
     {my $p = $t->allocBlock       ($PK, $PD, $PN);                             # Create a new parent block
      $t->splitRoot   ($offset, $r, $PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN);
      $t->upIntoData      ($p,      $LD);                                       # Left  points up to new parent
      $t->upIntoData      ($p,      $RD);                                       # Right points up to new parent
      $t->putBlock        ($p,      $PK, $PD, $PN);
      $t->putBlock        ($offset, $LK, $LD, $LN);
      $t->putBlock        ($r,      $RK, $RD, $RN);

      $t->firstFromMemory ($F);                                                 # Update new root of tree
      $t->rootIntoFirst   ($F, $p);
      $t->firstIntoMemory ($F);
     };

    $t->leafFromNodes($RN);                                                     # Whether the right block is a leaf
    IfNe                                                                        # If the zero Flag is zero then this is not a leaf
    Then
     {(K(nodes => $t->lengthRight) + 1)->for(sub                                # Reparent the children of the right hand side now known not to be a leaf
       {my ($index, $start, $next, $end) = @_;
        my $n = dFromZ $RN, $index * $t->width;                                 # Offset of node
        $t->getBlock  ($n, $LK, $LD, $LN);                                      # Get child of right node reusing the left hand set of registers as we no longer need them having written them to memory
        $t->upIntoData($r,      $LD);                                           # Parent for child of right hand side
        $t->putBlock  ($n, $LK, $LD, $LN);                                      # Save block into memory now that its parent pointer has been updated
       });
     };

    $t->putBlock        ($r,      $RK, $RD, $RN);                               # Save right block

    SetLabel $success;                                                          # Insert completed successfully
    PopZmm;
    PopR;
   }  structures => {tree => $tree},
      parameters => [qw(offset split)],
      name       => 'Nasm::X86::Tree::splitNode';

  $s->call(structures => {tree   => $tree},
           parameters => {offset => $offset, split => my $p = V split => 1});

  $p                                                                            # Return a variable containing one if the node was split else zero.
 } # splitNode

sub Nasm::X86::Tree::splitNotRoot($$$$$$$$$$$)                                  # Split a non root left node pushing its excess right and up.
 {my ($tree, $newRight, $PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN) = @_;      # Tree definition, variable offset in arena of right node block, parent keys zmm, data zmm, nodes zmm, left keys zmm, data zmm, nodes zmm, right keys
  @_ == 11 or confess "Eleven parameters required";

  my $w         = $tree->width;                                                 # Size of keys, data, nodes
  my $zw        = $tree->zWidthD;                                               # Number of dwords in a zmm
  my $zwn       = $tree->maxNodesZ;                                             # Maximum number of dwords that could be used for nodes in a zmm register.
  my $zwk       = $tree->maxKeysZ;                                              # Maxiumum number of dwords used for keys/data in a zmm
  my $lw        = $tree->maxKeys;                                               # Maximum number of keys in a node
  my $ll        = $tree->lengthLeft;                                            # Minimum node width on left
  my $lm        = $tree->lengthMiddle;                                          # Position of splitting key
  my $lr        = $tree->lengthRight;                                           # Minimum node on right
  my $lb        = $tree->lengthOffset;                                          # Position of length byte
  my $tb        = $tree->treeBits;                                              # Position of tree bits
  my $up        = $tree->up;                                                    # Position of up word in data
  my $transfer  = r8;                                                           # Transfer register
  my $transferD = r8d;                                                          # Transfer register as a dword
  my $transferW = r8w;                                                          # Transfer register as a  word
  my $work      = r9;                                                           # Work register as a dword

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Variable parameters, structure variables, structure copies, subroutine description
    PushR $transfer, $work, 1..7;

    my $SK = dFromZ $LK, $ll * $w;                                              # Splitting key
    my $SD = dFromZ $LD, $ll * $w;                                              # Data corresponding to splitting key

    my $mask = sub                                                              # Set k7 to a specified bit mask
     {my ($prefix, @onesAndZeroes) = @_;                                        # Prefix bits, alternating zeroes and ones
      LoadBitsIntoMaskRegister(7, $prefix, @onesAndZeroes);                     # Load k7 with mask
     };

    &$mask("00", $zwk);                                                         # Area to clear in keys and data preserving last qword
    Vmovdqu32    zmmM($RK, 7),  zmm($LK);
    Vmovdqu32    zmmM($RD, 7),  zmm($LD);

    &$mask("0",  $zwn);                                                         # Area to clear in nodes preserving last dword
    Vmovdqu32    zmmM($RN, 7),  zmm($LN);

    &$mask("00", $lw-$zwk,  $lr, -$ll-1);                                       # Compress right data/keys
    Vpcompressd  zmmM($RK, 7),  zmm($RK);
    Vpcompressd  zmmM($RD, 7),  zmm($RD);

    &$mask("0",  $lw-$zwk, $lr+1, -$lr-1);                                      # Compress right nodes
    Vpcompressd  zmmM($RN, 7),  zmm($RN);

    &$mask("11", $ll-$zwk, $ll);                                                # Clear left keys and data
    Vmovdqu32    zmmMZ($LK, 7), zmm($LK);
    Vmovdqu32    zmmMZ($LD, 7), zmm($LD);

    &$mask("1",  $ll-$zwk, $ll+1);                                              # Clear left nodes
    Vmovdqu32    zmmMZ($LN, 7), zmm($LN);

    &$mask("11", 2+$lr-$zw,  $lr);                                              # Clear right keys and data
    Vmovdqu32    zmmMZ($RK, 7), zmm($RK);
    Vmovdqu32    zmmMZ($RD, 7), zmm($RD);

    &$mask("1",  $lr-$zwk, $lr+1);                                              # Clear right nodes
    Vmovdqu32    zmmMZ($RN, 7), zmm($RN);

    my $t = $$s{tree};                                                          # Address tree

    &$mask("00", $zwk);                                                         # Area to clear in keys and data preserving last qword
    my $in = $t->insertionPoint($SK, $PK);                                      # The position at which the key would be inserted if this were a leaf
    $in->setReg($transfer);
    Kmovq k6, $transfer;                                                        # Mask shows insertion point
    Kandnq k5, k6, k7;                                                          # Mask shows expansion needed to make the insertion possible

    Vpexpandd zmmM($PK, 5), zmm($PK);                                           # Make room in parent keys and place the splitting key
    Vpexpandd zmmM($PD, 5), zmm($PD);                                           # Make room in parent data and place the data associated with the splitting key

    $SK->setReg($transfer);                                                     # Key to be inserted
    Vpbroadcastd zmmM($PK, 6), $transferD;                                      # Insert key

    $SD->setReg($transfer);                                                     # Data to be inserted
    Vpbroadcastd zmmM($PD, 6), $transferD;                                      # Insert data


    $in->setReg($transfer);                                                     # Next node up as we always expand to the right
    Shl $transfer, 1;
    Kmovq k4, $transfer;                                                        # Mask shows insertion point
    &$mask("0", $zwn);                                                          # Area to clear in keys and data preserving last qword
    Kandnq k3, k4, k7;                                                          # Mask shows expansion needed to make the insertion possible
    Vpexpandd zmmM($PN, 3), zmm($PN);                                           # Expand nodes

    $$p{newRight}->setReg($transfer);                                           # New right node to be inserted
    Vpbroadcastd zmmM($PN, 4), $transferD;                                      # Insert node

                                                                                # Lengths
    wRegFromZmm $work, $PK, $lb;                                                # Increment length of parent field
    Inc $work;
    wRegIntoZmm $work, $PK, $lb;

    Mov $work, $ll;                                                             # Lengths
    wRegIntoZmm $work, $LK, $lb;                                                # Left after split
    Mov $work, $lr;                                                             # Lengths
    wRegIntoZmm $work, $RK, $lb;                                                # Right after split

    &$mask("01", -$zwk);                                                        # Copy parent offset from left to right so that the new right node  still has the same parent
    Vmovdqu32 zmmM($RD, 7), zmm($LD);

    wRegFromZmm $transfer, $LK, $tb;                                            # Tree bits
    Mov $work, $transfer;
    And $work, (1 << $ll) - 1;
    wRegIntoZmm $work, $LK, $tb;                                                # Left after split

    Mov $work, $transfer;
    Shr $work, $lm;
    And $work, (1 << $lr) - 1;
    wRegIntoZmm $work, $RK, $tb;                                                # Right after split

    Mov $work, $transfer;                                                       # Insert splitting key tree bit into parent at the location indicated by k5
    Shr $work, $ll;
    And  $work, 1;                                                              # Tree bit to be inserted parent at the position indicated by a single 1 in k5 in parent
    wRegFromZmm $transfer, $PK, $tb;                                            # Tree bits from parent

    Cmp  $work, 0;                                                              # Are we inserting a zero into the tree bits?
    IfEq
    Then                                                                        # Inserting zero
     {InsertZeroIntoRegisterAtPoint k6, $transfer;                              # Insert a zero into transfer at the point indicated by k5
     },
    Else                                                                        # Inserting one
     {InsertOneIntoRegisterAtPoint k6, $transfer;                               # Insert a zero into transfer at the point indicated by k5
     };
    wRegIntoZmm $transfer, $PK, $tb;                                            # Save parent tree bits after split

    PopR;
   }
  structures => {tree => $tree},
  parameters => [qw(newRight)],
  name       => "Nasm::X86::Tree::splitNotRoot".
          "($lw, $PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN)";

  $s->call(
    structures => {tree => $tree},
    parameters => {newRight => $newRight});
 }
sub Nasm::X86::Tree::splitRoot($$$$$$$$$$$$)                                    # Split a non root node into left and right nodes with the left half left in the left node and splitting key/data pushed into the parent node with the remainder pushed into the new right node
 {my ($tree, $nLeft, $nRight, $PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN) = @_;# Tree definition, variable offset in arena of new left node block, variable offset in arena of new right node block, parent keys zmm, data zmm, nodes zmm, left keys zmm, data zmm, nodes zmm, right keys
  @_ == 12 or confess "Twelve parameters required";

  my $w         = $tree->width;                                                 # Size of keys, data, nodes
  my $zw        = $tree->zWidthD;                                               # Number of dwords in a zmm
  my $zwn       = $tree->maxNodesZ;                                             # Maximum number of dwords that could be used for nodes in a zmm register.
  my $zwk       = $tree->maxKeysZ;                                              # Maxiumum number of dwords used for keys/data in a zmm
  my $lw        = $tree->maxKeys;                                               # Maximum number of keys in a node
  my $ll        = $tree->lengthLeft;                                            # Minimum node width on left
  my $lm        = $tree->lengthMiddle;                                          # Position of splitting key
  my $lr        = $tree->lengthRight;                                           # Minimum node on right
  my $lb        = $tree->lengthOffset;                                          # Position of length byte
  my $tb        = $tree->treeBits;                                              # Position of tree bits
  my $transfer  = r8;                                                           # Transfer register
  my $transferD = r8d;                                                          # Transfer register as a dword
  my $transferW = r8w;                                                          # Transfer register as a  word

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Variable parameters, structure variables, structure copies, subroutine description

    my $mask = sub                                                              # Set k7 to a specified bit mask
     {my ($prefix, @onesAndZeroes) = @_;                                        # Prefix bits, alternating zeroes and ones
      LoadBitsIntoMaskRegister(7, $prefix, @onesAndZeroes);                     # Load k7 with mask
     };

    my $t = $$s{tree};                                                          # Address tree

    PushR $transfer, 6, 7;

    $t->maskForFullKeyArea(7);                                                  # Mask for keys area
    $t->maskForFullNodesArea(6);                                                # Mask for nodes area

    Mov $transfer, -1;
    Vpbroadcastd zmmM($PK, 7), $transferD;                                      # Force keys to be high so that insertion occurs before all of them

    Mov $transfer, 0;
    Vpbroadcastd zmmM($PD, 7), $transferD;                                      # Zero other keys and data
    Vpbroadcastd zmmM($RK, 7), $transferD;
    Vpbroadcastd zmmM($RD, 7), $transferD;

    Mov $transfer, 0;
    Vpbroadcastd zmmM($PN, 6), $transferD;
    Vpbroadcastd zmmM($RN, 6), $transferD;

    my $newRight = $$p{newRight};
    $t->splitNotRoot($newRight, $PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN);   # Split the root node as if it were a non root node

    $$p{newLeft} ->dIntoZ($PN, 0);                                              # Place first - left sub node into new root
    $$p{newRight}->dIntoZ($PN, 4);                                              # Place second - right sub node into new root

    Kshiftrw k7, k7, 1;                                                         # Reset parent keys/data outside of single key/data
    Kshiftlw k7, k7, 1;
    Mov $transfer, 0;
    Vpbroadcastd zmmM($PK, 7), $transferD;

    Mov $transfer, 1;                                                           # Lengths
    wRegIntoZmm $transfer, $PK, $lb;                                            # Left after split

    wRegFromZmm $transfer, $PK, $tb;                                            # Parent tree bits
    And $transfer, 1;
    wRegIntoZmm $transfer, $PK, $tb;

    PopR;
   }
  structures => {tree => $tree},
  parameters => [qw(newLeft newRight)],
  name       => "Nasm::X86::Tree::splitRoot".
          "($lw, $PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN)";

  $s->call
   (structures => {tree => $tree},
    parameters => {newLeft => $nLeft, newRight => $nRight});
 }

sub Nasm::X86::Tree::put($$$)                                                   # Put a variable key and data into a tree. The data could be a tree descriptor to place a sub tree into a tree at the indicated key.
 {my ($tree, $key, $data) = @_;                                                 # Tree definition, key as a variable, data as a variable or a tree descriptor
  @_ == 3 or confess "Three parameters";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    my $success = Label;                                                        # End label

    PushR my ($W1, $W2) = (r8, r9);
    PushZmm my ($F, $K, $D, $N) = reverse 28..31;

    my $t = $$s{tree};
    my $k = $$p{key};
    my $d = $$p{data};
    my $a = $t->arena;

    my $start = SetLabel;                                                       # Start the descent through the tree

    $t->firstFromMemory($F);
    my $Q = $t->rootFromFirst($F);                                              # Start the descent at the root node

    If $Q == 0,                                                                 # First entry as there is no root node.
    Then
     {my $block = $t->allocBlock($K, $D, $N);
      $k->dIntoZ                ($K, 0);
      $d->dIntoZ                ($D, 0);
      $t->incLengthInKeys       ($K);
      $t->putBlock($block,       $K, $D, $N);
      $t->rootIntoFirst         ($F, $block);
      $t->incSizeInFirst        ($F);
      $t->firstIntoMemory       ($F);                                           # First back into memory
      Jmp $success;
     };

    my $descend = SetLabel;                                                     # Descend to the next level

    $t->getBlock($Q, $K, $D, $N);                                               # Get the current block from memory

    my $eq = $t->indexEq($k, $K);                                               # Check for an equal key
    If $eq > 0,                                                                 # Equal key found
    Then                                                                        # Overwrite the existing key/data
     {$t->overWriteKeyDataTreeInLeaf($eq, $K, $D, $k, $d,  $$p{subTree});
      $t->putBlock                  ($Q,  $K, $D, $N);
      Jmp $success;
     };

    my $split = $t->splitNode($Q);                                              # Split blocks that are full
    If $split > 0,
    Then
     {Jmp $start;                                                               # Restart the descent now that this block has been split
     };

    my $leaf = $t->leafFromNodes($N);                                           # Are we on a leaf node ?
    If $leaf > 0,
    Then
     {my $i = $t->insertionPoint($k, $K);                                       # Find insertion point
      $t->insertKeyDataTreeIntoLeaf($i, $F, $K, $D, $k, $d, $$p{subTree});
      $t->putBlock                 ($Q, $K, $D, $N);
      $t->firstIntoMemory          ($F);                                        # First back into memory
      Jmp $success;
     };

    my $in = $t->insertionPoint($k, $K);                                        # The position at which the key would be inserted if this were a leaf
    my $next = $in->dFromPointInZ($N);                                          # The node to the left of the insertion point - this works because the insertion point can be upto one more than the maximum number of keys

    $Q->copy($next);                                                            # Get the offset of the next node - we are not on a leaf so there must be one
    Jmp $descend;                                                               # Descend to the next level

    SetLabel $success;
    PopZmm;
    PopR;
   } name => "Nasm::X86::Tree::put",
     structures => {tree=>$tree},
     parameters => [qw(key data subTree)];

  $s->call(structures => {tree => $tree},
           parameters => {key  => $key, data=>$data,
            subTree => V(subTree => ref($data) =~ m(Tree) ? 1 : 0)});
 }

sub Nasm::X86::Tree::find($$)                                                   # Find a key in a tree and test whether the found data is a sub tree.  The results are held in the variables "found", "data", "subTree" addressed by the tree descriptor. The key just searched for is held in the key field of the tree descriptor. The point at which it was found is held in B<found> which will be zero if the key was not found.
 {my ($tree, $key) = @_;                                                        # Tree descriptor, key field to search for
  @_ == 2 or confess "Two parameters";
  ref($key) =~ m(Variable) or confess "Variable required";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $success = Label;                                                        # Short circuit if ladders by jumping directly to the end after a successful push

    PushR 6..7, 8..15, 28..31;

    my $t = $$s{tree};                                                          # Tree to search
    my $k = $$p{key};                                                           # Key to find
    $t->key->copy($k);                                                          # Copy in key so we know what was searched for

    my $F = 31; my $K = 30; my $D = 29; my $N = 28;
    my $lengthMask = k6; my $testMask = k7;
    my $W1 = r8;  my $W2 = r9;                                                  # Work registers

    $t->found  ->copy(0);                                                       # Key not found
    $t->data   ->copy(0);                                                       # Data not yet found
    $t->subTree->copy(0);                                                       # Not yet a sub tree
    $t->offset ->copy(0);                                                       # Offset not known

    $t->firstFromMemory      ($F);                                              # Load first block
    my $Q = $t->rootFromFirst($F);                                              # Start the search from the root
    If $Q == 0,
    Then                                                                        # Empty tree so we have not found the key
     {Jmp $success;                                                             # Return
     };

    K(loop, 99)->for(sub                                                        # Step down through tree
     {my ($index, $start, $next, $end) = @_;

      $t->getBlock($Q, $K, $D, $N);                                             # Get the keys/data/nodes

      my $eq = $t->indexEq($k, $K);                                             # The position of a key in a zmm equal to the specified key as a point in a variable.
      If $eq  > 0,                                                              # Result mask is non zero so we must have found the key
      Then
       {my $d = $eq->dFromPointInZ($D);                                         # Get the corresponding data
        $t->found ->copy($eq);                                                  # Key found at this point
        $t->data  ->copy($d);                                                   # Data associated with the key
        $t->offset->copy($Q);                                                   # Offset of the containing block
        Jmp $success;                                                           # Return
       };

      my $leaf = $t->leafFromNodes($N);                                         # Are we on a leaf
      If $leaf > 0,
      Then                                                                      # Zero implies that this is a leaf node so we cannot search any further and will have to go with what you have
       {Jmp $success;                                                           # Return
       };

      my $i = $t->insertionPoint($k, $K);                                       # The insertion point if we were inserting
      my $n = $i->dFromPointInZ($N);                                            # Get the corresponding data
      $Q->copy($n);                                                             # Corresponding node
     });
    PrintErrTraceBack "Stuck in find";                                          # We seem to be looping endlessly

    SetLabel $success;                                                          # Find completed successfully
    PopR;
   } parameters=>[qw(key)],
     structures=>{tree=>$tree},
     name => 'Nasm::X86::Tree::find';

  $s->call(structures=>{tree => $tree}, parameters=>{key => $key});
 } # find

sub Nasm::X86::Tree::findAndReload($$)                                          # Find a key in the specified tree and clone it is it is a sub tree.
 {my ($t, $key) = @_;                                                           # Tree descriptor, key as a dword
  @_ == 2 or confess "Two parameters";

  $t->find($key);                                                               # Find the key
  If $t->found > 0,                                                             # Make the found data the new  tree
  Then
   {$t->first->copy($t->data);                                                  # Copy the data variable to the first variable without checking whether it is valid
   };
 }

sub Nasm::X86::Tree::findShortString($$)                                        # Find the data at the end of a key chain held in a short string.  Return a tree descriptor referencing the data located or marked as failed to find.
 {my ($tree, $string) = @_;                                                     # Tree descriptor, short string
  @_ == 2 or confess "2 parameters";
  my $t = $tree->copyDescription;                                               # Reload the input tree so we can walk down the chain
  my $w = $tree->width;                                                         # Size of a key on the tree
  my $z = $string->z;                                                           # The zmm containing the short string

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $L = $string->len;                                                       # Length of the short string
    my $t = $$s{tree};                                                          # Tree
    $t->found->copy(0);                                                         # Not yet found

    PushR rax, r14, r15;
    ClearRegisters r15;
    PushR r15, $z;                                                              # Put the zmm holding the short string onto the stack with a register block full of zeroes above it
    Lea rax, "[rsp+1]";                                                         # Address first data byte of short string
    $L->setReg(r15);                                                            # Length of key remaining to write into key chain

    AndBlock
     {my ($fail, $end, $start) = @_;                                            # Fail block, end of fail block, start of test block
      Cmp r15, $w;                                                              # Can we write a full key block ?
      IfGt
      Then                                                                      # Full dwords from key still to load
       {Mov r14d, "[rax]";                                                      # Load dword from string
        $t->findAndReload(V(key, r14));                                         # Find dword of key
        If $t->found == 0,                                                      # Failed to find dword
        Then
         {Jmp $end;
         };
        Add rax, $w;                                                            # Move up over found key
        Sub r15, $w;                                                            # Reduce amount of key still to find
        Jmp $start;                                                             # Restart
       };
      Mov r14d, "[rax]";                                                        # Load possibly partial dword from string which might have some trailing zeroes in it from the register block above
      $t->find(V(key, r14));                                                    # Find remaining key and data
     };
    PopR; PopR;
   } structures => {tree => $tree},
     name       => "Nasm::X86::Tree::findShortString_$z";

  $s->call(structures=>{tree=>$tree});                                          # Find the data at the end of the short string key

  $t                                                                            # Return the cloned tree descriptor as it shows the data and the find status
 } # findShortString

sub Nasm::X86::Tree::insertShortString($$$)                                     # Insert some data at the end of a chain of sub trees keyed by the contents of a short string.
 {my ($tree, $string, $data) = @_;                                              # Tree descriptor, short string, data as a dword
  @_ == 3 or confess "Three parameters";
  my $w = $tree->width;                                                         # Size of a key on the tree
  my $z = $string->z;                                                           # The zmm containing the short string

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $L = $string->len;                                                       # Length of the short string

    PushR rax, r14, r15;
    ClearRegisters r15;
    PushR r15, $z;                                                              # Put the zmm holding the short string onto the stack with a register block full of zeroes above it
    my $W = $string->lengthWidth;                                               # The length of the initial field followed by the data
    Lea rax, "[rsp+$W]";                                                        # Address first data byte of short string
    $L->setReg(r15);                                                            # Length of key remaining to write into key chain

    my $t = $$s{tree};                                                          # Reload the input tree so we can walk down the chain from it.

    AndBlock
     {my ($fail, $end, $start) = @_;                                            # Fail block, end of fail block, start of test block
      Cmp r15, $w;                                                              # Can we write a full key block ?
      IfGt
      Then                                                                      # Full dwords from key still to load
       {Mov r14d, "[rax]";                                                      # Load dword from string
        $t->insertTreeAndReload(V(key, r14));                                   # Create sub tree
        Add rax, $w;                                                            # Move up over inserted key
        Sub r15, $w;                                                            # Reduce amount of key still to write
        Jmp $start;                                                             # Restart
       };
      Mov r14d, "[rax]";                                                        # Load possibly partial dword from string which might have some trailing zeroes in it from the register block above
      $t->insert(V(key, r14), $$p{data});                                       # Insert remaining key and data
     };
    PopR; PopR;
   } structures => {tree => $tree},
     parameters => [qw(data)],
     name       => "Nasm::X86::Tree::insertinsertShortString_$z";

  my $t = $tree->arena->DescribeTree();                                         # Use a copy of the tree descriptor so that we can modify its first field
     $t->first->copy($tree->first);
  $s->call(structures => {tree => $t}, parameters => {data => $data});          # Insert the data at the end of the short string key
 } # insertShortString

sub Nasm::X86::Tree::leftOrRightMost($$$$)                                      # Return the offset of the left most or right most node.
 {my ($tree, $dir, $node, $offset) = @_;                                        # Tree descriptor, direction: left = 0 or right = 1, start node,  offset of located node
  @_ == 4 or confess "Four parameters";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $success = Label;                                                        # Short circuit if ladders by jumping directly to the end after a successful push

    my $t        = $$s{tree};                                                   # Tree
       $t->first->copy(my $F = $$p{node});                                      # First block
    my $arena = $t->arena;                                                      # Arena
    PushR rax, r8, r9; PushZmm 29..31;

    K(loopLimit, 9)->for(sub                                                    # Loop a reasonable number of times
     {my ($index, $start, $next, $end) = @_;
      $t->getBlock($F, 31, 30, 29);                                             # Get the first keys block
      my $n = dFromZ 29, 0;                                                     # Get the node block offset from the data block loop
      If $n == 0,
      Then                                                                      # Reached the end so return the containing block
       {$$p{offset}->copy($F);
        Jmp $success;
       };
      if ($dir == 0)                                                            # Left most
       {my $l = dFromZ 29, 0;                                                   # Get the left most node
        $F->copy($l);                                                           # Continue with the next level
       }
      else                                                                      # Right most
       {my $l = $t->lengthFromKeys(31);                                         # Length of the node
        my $r = dFromZ 31, $l;                                                  # Get the right most child
        $F->copy($r);                                                           # Continue with the next level
       }
     });
    PrintErrStringNL "Stuck in LeftOrRightMost";
    Exit(1);

    SetLabel $success;                                                          # Insert completed successfully
    PushZmm; PopR;
   } structures => {tree => $tree},
     parameters => [qw(node offset)],
     name       => $dir==0 ? "Nasm::X86::Tree::leftMost" :
                             "Nasm::X86::Tree::rightMost";

  $s->call(structures => {tree=>$tree},
           parameters => {node => $node, offset=>$offset});
 }

sub Nasm::X86::Tree::leftMost($$$)                                              # Return the offset of the left most node from the specified node.
 {my ($t, $node, $offset) = @_;                                                 # Tree descriptor, start node, returned offset
  @_ == 3 or confess "Three parameters";
  $t->leftOrRightMost(0, $node, $offset)                                        # Return the left most node
 }

sub Nasm::X86::Tree::rightMost($$$)                                             # Return the offset of the left most node from the specified node.
 {my ($t, $node, $offset) = @_;                                                 # Tree descriptor, start node, returned offset
  @_ == 3 or confess "Three parameters";
  $t->leftOrRightMost(1, $node, $offset)                                        # Return the right most node
 }

sub Nasm::X86::Tree::nodeFromData($$$)                                          #P Load the the node block into the numbered zmm corresponding to the data block held in the numbered zmm.
 {my ($t, $data, $node) = @_;                                                   # Tree descriptor, numbered zmm containing data, numbered zmm to hold node block
confess "Not needed";
  @_ == 3 or confess "Three parameters";
  my $loop = $t->getLoop($data);                                                # Get loop offset from data
  $t->getZmmBlock($t->arena, $loop, $node);                                     # Node
 }

sub Nasm::X86::Tree::depth($$)                                                  # Return the depth of a node within a tree.
 {my ($tree, $node) = @_;                                                       # Tree descriptor, node
  @_ == 2 or confess "Two parameters required";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $success = Label;                                                        # Short circuit if ladders by jumping directly to the end after a successful push

    my $t = $$s{tree};                                                          # Tree
    my $arena = $tree->arena;                                                   # Arena
    my $N = $$p{node};                                                          # Starting node

    PushR r8, r9, r14, r15, zmm30, zmm31;
    my $tree = $N->clone('tree');                                               # Start at the specified node

    K(loop, 9)->for(sub                                                         # Step up through tree
     {my ($index, $start, $next, $end) = @_;
      $t->getKeysData($tree, 31, 30, r8, r9);                                   # Get the first node of the tree
      my $P = $t->getUpFromData(30);                                            # Parent
      If $P == 0,
      Then                                                                      # Empty tree so we have not found the key
       {$$p{depth}->copy($index+1);                                             # Key not found
        Jmp $success;                                                           # Return
       };
      $tree->copy($P);                                                          # Up to next level
     });
    PrintErrStringNL "Stuck in depth";                                          # We seem to be looping endlessly
    Exit(1);

    SetLabel $success;                                                          # Insert completed successfully
    PopR;
   }  structures => {tree => $tree},
      parameters => [qw(node depth)],
      name       => 'Nasm::X86::Tree::depth';

  $s->call(structures => {tree => $tree->copyDescription},
           parameters => {node => $node, depth => my $d = V depth => 0});

  $d
 } # depth

#D2 Sub trees                                                                   # Construct trees of trees.

sub Nasm::X86::Tree::isTree($$$)                                                #P Set the Zero Flag to oppose the tree bit in the numbered zmm register holding the keys of a node to indicate whether the data element indicated by the specified register is an offset to a sub tree in the containing arena or not.
{my ($t, $zmm, $point) = @_;                                                    # Tree descriptor, numbered zmm register holding the keys for a node in the tree, register showing point to test
 @_ == 3 or confess "Three parameters";

  my $z = registerNameFromNumber $zmm;                                          # Full name of zmm register
  my $o = $t->treeBits;                                                         # Bytes from tree bits to end of zmm
  my $w = $t->zWidth;                                                           # Size of zmm register
  Vmovdqu64    "[rsp-$w]", $z;                                                  # Write beyond stack
  Test $point, "[rsp-$w+$o]";                                                   # Test the tree bit under point
 } # isTree

sub Nasm::X86::Tree::getTreeBit($$$)                                            #P Get the tree bit from the numbered zmm at the specified point and return it in a variable as a one or a zero.
 {my ($t, $zmm, $point) = @_;                                                   # Tree descriptor, register showing point to test, numbered zmm register holding the keys for a node in the tree
  @_ == 3 or confess "Three parameters";

  $t->getTreeBits($zmm, rdi);                                                   # Tree bits
  $point->setReg(rsi);
  And rdi, rsi;                                                                 # Write beyond stack
  my $r = V treeBit => 0;
  Cmp di, 0;
  IfNe Then {$r->copy(1)};
  $r
 }

sub Nasm::X86::Tree::setOrClearTreeBit($$$$)                                    #P Set or clear the tree bit selected by the specified point in the numbered zmm register holding the keys of a node to indicate that the data element indicated by the specified register is an offset to a sub tree in the containing arena.
 {my ($t, $set, $point, $zmm) = @_;                                             # Tree descriptor, set if true else clear, register holding point to set, numbered zmm register holding the keys for a node in the tree
  @_ == 4 or confess "Four parameters";
  CheckGeneralPurposeRegister($point);
  my $z = registerNameFromNumber $zmm;                                          # Full name of zmm register
  my $o = $t->treeBits;                                                         # Tree bits to end of zmm
  my $r = registerNameFromNumber $point;
  PushR $z;                                                                     # Push onto stack so we can modify it
  if ($set)                                                                     # Set the indexed bit
   {And $point, $t->treeBitsMask;                                               # Mask tree bits to prevent operations outside the permitted area
    Or "[rsp+$o]", $point;                                                      # Set tree bit in zmm
   }
  else                                                                          # Clear the indexed bit
   {And $point, $t->treeBitsMask;                                               # Mask tree bits to prevent operations outside the permitted area
    Not $point;
    And "[rsp+$o]", $point;
   }
  PopR;                                                                         # Retrieve zmm
 } # setOrClearTree

sub Nasm::X86::Tree::setTreeBit($$$)                                            #P Set the tree bit in the numbered zmm register holding the keys of a node to indicate that the data element indexed by the specified register is an offset to a sub tree in the containing arena.
 {my ($t, $zmm, $point) = @_;                                                   # Tree descriptor, numbered zmm register holding the keys for a node in the tree, register holding the point to clear
  @_ == 3 or confess "Three parameters";
  $t->setOrClearTreeBit(1, $point, $zmm);
 } # setTree

sub Nasm::X86::Tree::clearTreeBit($$$)                                          #P Clear the tree bit in the numbered zmm register holding the keys of a node to indicate that the data element indexed by the specified register is an offset to a sub tree in the containing arena.
{my ($t, $zmm, $point) = @_;                                                    # Tree descriptor, numbered zmm register holding the keys for a node in the tree, register holding register holding the point to set
  @_ == 3 or confess "Three parameters";
  $t->setOrClearTreeBit(0, $point, $zmm);
 } # clearTree


sub Nasm::X86::Tree::setOrClearTreeBitToMatchContent($$$$)                      #P Set or clear the tree bit pointed to by the specified register depending on the content of the specified variable.
 {my ($t, $zmm, $point, $content) = @_;                                         # Tree descriptor, numbered zmm, register indicating point, content indicating zero or one
  @_ == 4 or confess "Four parameters";

  if (ref($point))                                                              # Point is a variable so we must it in a register
   {PushR r15;
    $point->setReg(r15);
    If $content > 0,                                                              # Content represents a tree
    Then
     {$t->setTreeBit($zmm, r15);
     },
    Else                                                                          # Content represents a variable
     {$t->clearTreeBit($zmm, r15);
     };
    PopR;
   }
  Else
   {If $content > 0,                                                              # Content represents a tree
    Then
     {$t->setTreeBit($zmm, $point);
     },
    Else                                                                          # Content represents a variable
     {$t->clearTreeBit($zmm, $point);
     };
   }
 }

sub Nasm::X86::Tree::getTreeBits($$$)                                           #P Load the tree bits from the numbered zmm into the specified register.
 {my ($t, $zmm, $register) = @_;                                                # Tree descriptor, numbered zmm, target register
  @_ == 3 or confess "Three parameters";
  wRegFromZmm $register, $zmm, $t->treeBits;
  And $register, $t->treeBitsMask;
 }

sub Nasm::X86::Tree::setTreeBits($$$)                                           #P Put the tree bits in the specified register into the numbered zmm.
 {my ($t, $zmm, $register) = @_;                                                # Tree descriptor, numbered zmm, target register
  @_ == 3 or confess "Three parameters";
  And $register, $t->treeBitsMask;
  wRegIntoZmm $register, $zmm, $t->treeBits;
 }

sub Nasm::X86::Tree::insertTreeBit($$$$)                                        #P Insert a zero or one into the tree bits field in the numbered zmm at the specified point moving the bits at and beyond point one position to the right.
 {my ($t, $onz, $zmm, $point) = @_;                                             # Tree descriptor, 0 - zero or 1 - one, numbered zmm, register indicating point
  @_ == 4 or confess "Four parameters";
  my $z = registerNameFromNumber $zmm;
  my $p = registerNameFromNumber $point;
  PushR my @save = my ($bits) = ChooseRegisters(1, $point);                     # Tree bits register
  $t->getTreeBits($zmm, $bits);                                                 # Get tree bits
  if ($onz)
   {InsertOneIntoRegisterAtPoint ($p, $bits);                                   # Insert a one into the tree bits at the indicated location
   }
  else
   {InsertZeroIntoRegisterAtPoint($p, $bits);                                   # Insert a zero into the tree bits at the indicated location
   }
  $t->setTreeBits($zmm, $bits);                                                 # Put tree bits
  PopR;
 }

sub Nasm::X86::Tree::insertZeroIntoTreeBits($$$)                                #P Insert a zero into the tree bits field in the numbered zmm at the specified point moving the bits at and beyond point one position to the right.
 {my ($t, $zmm, $point) = @_;                                                   # Tree descriptor, numbered zmm, register indicating point
  @_ == 3 or confess "3 parameters";
  $t->insertTreeBit(0, $zmm, $point);                                           # Insert a zero into the tree bits field in the numbered zmm at the specified point
 }

sub Nasm::X86::Tree::insertOneIntoTreeBits($$$)                                 #P Insert a one into the tree bits field in the numbered zmm at the specified point moving the bits at and beyond point one position to the right.
 {my ($t, $zmm, $point) = @_;                                                   # Tree descriptor, numbered zmm, register indicating point
  @_ == 3 or confess "Three parameters";
  $t->insertTreeBit(1, $zmm, $point);                                           # Insert a one into the tree bits field in the numbered zmm at the specified point
 }

sub Nasm::X86::Tree::insertIntoTreeBits($$$$)                                   #P Insert a one into the tree bits field in the numbered zmm at the specified point moving the bits at and beyond point one position to the right.
 {my ($t, $zmm, $point, $content) = @_;                                         # Tree descriptor, numbered zmm, register indicating point
  @_ == 4 or confess "Four parameters";

  if (ref($point))                                                              # Point is a variable so we must put into a register
   {PushR r15;
    $point->setReg(r15);
    If $content > 0,                                                            # Content represents a one
    Then
     {$t->insertOneIntoTreeBits ($zmm, r15);
     },
    Else                                                                        # Content represents a zero
     {$t->insertZeroIntoTreeBits($zmm, r15);
     };
    PopR;
   }
  else
   {If $content > 0,                                                            # Content represents a one
    Then
     {$t->insertOneIntoTreeBits ($zmm, $point);
     },
    Else                                                                        # Content represents a zero
     {$t->insertZeroIntoTreeBits($zmm, $point);
     };
   }
 }

#D2 Print                                                                       # Print a tree

sub Nasm::X86::Tree::print($)                                                   # Print a tree.
 {my ($tree) = @_;                                                              # Tree
  @_ == 1 or confess "One parameter";

  my $s = Subroutine2                                                           # Print a tree
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    my $t = $$s{tree};                                                          # Tree
    my $F = $t->first;                                                          # First block of tree
    PrintOutString "Tree at: "; $F->outNL(' ');
    my $arena = $t->arena;                                                      # Arena

    $t->by(sub                                                                  # Iterate through the tree
     {my ($iter, $end) = @_;
      $iter->tree->depth($iter->node, my $D = V(depth));
      $iter->key ->out('key: ');
      $iter->data->out(' data: ');
      $D   ->outNL    (' depth: ');
      $t->find($iter->key);                                                     # Slow way to find out if this is a subtree
      If $t->subTree > 0,
      Then
       {my $T = $t->describeTree(first => $t->data);
         $sub->call(structures => {tree => $T});
       };
     });
   } structures=>{tree=>$tree},
     name => "Nasm::X86::Tree::print";

  $s->call(structures=>{tree=>$tree});
 }

sub Nasm::X86::Tree::dump($$)                                                   # Dump a tree and all its sub trees.
 {my ($tree, $title) = @_;                                                      # Tree, title
  @_ == 2 or confess "Two parameters";

  PushR my ($W1, $W2, $F) = (r8, r9, 31);

  my $s = Subroutine2                                                           # Print a tree
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    my $t = $$s{tree};                                                          # Tree
    my $I = $$p{indentation};                                                   # Indentation to apply to the start of each new line
    my $arena = $t->arena;                                                      # Arena

    PushR my ($W1, $W2, $treeBitsR, $treeBitsIndexR, $K, $D, $N) =
           (r8, r9, r10, r11, 30, 29, 28);

    Block                                                                       # Print each node in the tree
     {my ($end, $start) = @_;                                                   # Labels
      my $offset = $$p{offset};                                                 # Offset of node to print
      $t->getBlock($offset, $K, $D, $N);                                        # Load node
      $t->getTreeBits($K, $treeBitsR);                                          # Tree bits for this node
      my $l = $t->lengthFromKeys($K);                                           # Number of nodes

      my $root = $t->rootFromFirst($F);                                         # Root or not

      $I->outSpaces;
      PrintOutString "At: ";                                                    # Print position and length
      $offset->outRightInHex(K width => 4);
      (K(col => 20) - $I)->outSpaces;
      PrintOutString "length: ";
      $l->outRightInDec(K width => 4);

      PrintOutString ",  data: ";                                               # Position of data block
      $t->getLoop($K)->outRightInHex(K width => 4);

      PrintOutString ",  nodes: ";                                              # Position of nodes block
      $t->getLoop($D)->outRightInHex(K width => 4);

      PrintOutString ",  first: ";                                              # First block of tree
      $t->getLoop($N)->outRightInHex(K width => 4);

      my $U = $t->upFromData($D);                                               # Up field determines root / parent / leaf

      If $root == $offset,
      Then
       {PrintOutString ", root";                                                # Root
       },
      Else
       {PrintOutString ",  up: ";                                               # Up
        $U->outRightInHex(K width => 4);
       };

      If dFromZ($N, 0) == 0,                                                    # Leaf or parent
      Then
       {PrintOutString ", leaf";
       },
      Else
       {PrintOutString ", parent";
       };

      $t->getTreeBits($K, $W1);
      Cmp $W1, 0;
      IfGt
      Then                                                                      # Identify the data elements which are sub trees
       {PrintOutString ",  trees: ";
        V(bits => $W1)->outRightInBin(K width => $t->maxKeys);
       };
      PrintOutNL;

      $I->copy($I + 2);                                                         # Indent sub tree

      $I->outSpaces; PrintOutString "Index:";                                   # Indices
      $l->for(sub
       {my ($index, $start, $next, $end) = @_;
        PrintOutString ' ';
        $index->outRightInDec(K width => 4);
       });
      PrintOutNL;

      my $printKD = sub                                                         # Print keys or data or nodes
       {my ($name, $zmm, $nodes, $tb) = @_;                                     # Key or data or node, zmm containing key or data or node, hex if true else decimal, print tree bits if tree
        $I->outSpaces; PrintOutString $name;                                    # Keys
        Mov $treeBitsIndexR, 1 if $tb;                                          # Check each tree bit position
        ($nodes ? $l + 1 : $l)->for(sub                                         # There is one more node than keys or data
         {my ($index, $start, $next, $end) = @_;
          my $i = $index * $t->width;                                           # Key or Data offset
          my $k = dFromZ $zmm, $i;                                              # Key or Data

          if (!$tb)                                                             # No tree bits
           {PrintOutString ' ';
            $k->outRightInHex(K width => 4);
            #$k->outRightInHex(K width => 4) if  $nodes;
            #$k->outRightInDec(K width => 4) if !$nodes;
           }
          else
           {Test $treeBitsR, $treeBitsIndexR;                                   # Check for a tree bit
            IfNz
            Then                                                                # This key indexes a sub tree
             {PrintOutString '_';
              $k->outRightInHex(K width => 4);
             },
            Else
             {PrintOutString ' ';
              $k->outRightInDec(K width => 4);
             };
           }
          Shl $treeBitsIndexR, 1 if $tb;                                        # Next tree bit position
         });
        PrintOutNL;
       };

      $printKD->('Keys :', $K, 0, 0);                                           # Print keys
      $printKD->('Data :', $D, 0, 1);                                           # Print data either as _hex for a sub tree reference or in decimal for data
      If dFromZ($N, 0) > 0,                                                     # If the first node is not zero we are not on a leaf
      Then
       {$printKD->('Nodes:', $N, 1, 0);
       };

      Cmp $treeBitsR, 0;                                                        # Any tree bit sets?
      IfNe
      Then                                                                      # Tree bits present
       {Mov $treeBitsIndexR, 1;                                                 # Check each tree bit position
        K(loop, $t->maxKeys)->for(sub
         {my ($index, $start, $next, $end) = @_;
          Test $treeBitsR, $treeBitsIndexR;                                     # Check for a tree bit
          IfNz
          Then                                                                  # This key indexes a sub tree
           {my $i = $index * $t->width;                                         # Key/data offset
            my $d = dFromZ($D, $i);                                             # Data
            my $I = V(indentation => 0)->copy($I + 2);
            $sub->call(parameters => {indentation => $I, offset => $d},
                       structures => {tree        => $t});                      # Print sub tree referenced by data field
           };
          Shl $treeBitsIndexR, 1;                                               # Next tree bit position
         });
       };

      ($l+1)->for(sub                                                           # Print sub nodes
       {my ($index, $start, $next, $end) = @_;
        my $i = $index * $t->width;                                             # Key/Data offset
        my $d = dFromZ($N, $i);                                                 # Sub nodes
        If $d > 0,                                                              # Print any sub nodes
        Then
         {my $I = V(indentation => 0)->copy($I + 2);
          $sub->call(parameters => {indentation => $I, offset=>$d},
                     structures => {tree        => $t});                        # Print sub tree referenced by data field
         };
       });

      ($I - 2)->outSpaces; PrintOutStringNL "end";                              # Separate sub tree dumps

     };

    PopR;
   } parameters => [qw(indentation offset)],
     structures => {tree => $tree},
     name       => "Nasm::X86::Tree::dump";

  PrintOutStringNL $title;                                                      # Title of the piece so we do not lose it

  $tree->firstFromMemory($F);
  my $Q = $tree->rootFromFirst($F);
  my $size = $tree->sizeFromFirst($F);                                         # Size of tree

  If $Q == 0,                                                                   # Empty tree
  Then
   {PrintOutStringNL "- empty";
   },
  Else
   {$s->call(structures => {tree        => $tree},                              # Print root node
             parameters => {indentation => V(indentation => 0),
                            offset      => $Q});
   };

  PopR;
 }

sub Nasm::X86::Tree::printInOrder($$)                                           # Print a tree in order
 {my ($tree, $title) = @_;                                                      # Tree, title
  @_ == 2 or confess "Two parameters";

  PushR my ($W1, $W2, $F) = (r8, r9, 31);

  my $s = Subroutine2                                                           # Print a tree
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition

    my $t = $$s{tree};                                                          # Tree
    my $arena = $t->arena;                                                      # Arena

    PushR my ($W1, $W2, $treeBitsR, $treeBitsIndexR, $K, $D, $N) =
           (r8, r9, r10, r11, 30, 29, 28);

    Block                                                                       # Print each node in the tree
     {my ($end, $start) = @_;                                                   # Labels
      my $offset = $$p{offset};                                                 # Offset of node to print
      $t->getBlock($offset, $K, $D, $N);                                        # Load node
      my $l = $t->lengthFromKeys($K);                                           # Number of nodes
      $l->for(sub                                                               # Print sub nodes
       {my ($index, $start, $next, $end) = @_;
        my $i = $index * $t->width;                                             # Key/Data?node offset
        my $k = dFromZ $K, $i;                                                  # Key
        my $d = dFromZ $D, $i;                                                  # Data
        my $n = dFromZ $N, $i;                                                  # Sub nodes
        If $n > 0,                                                              # Not a leaf
        Then
         {$sub->call(parameters => {offset => $n},                              # Recurse
                     structures => {tree   => $t});
         };
        $k->outRightInHex(K width => 4);                                        # Print key
       });

      If $l > 0,                                                                # Print final sub tree
      Then
       {my $o = $l * $t->width;                                                 # Final sub tree offset
        my $n = dFromZ $N, $l * $t->width;                                      # Final sub tree
        If $n > 0,                                                              # Not a leaf
        Then
         {$sub->call(parameters => {offset => $n},
                     structures => {tree   => $t});

         };
       };
     };
    PopR;
   } parameters => [qw(offset)],
     structures => {tree => $tree},
     name       => "Nasm::X86::Tree::printInOrder";

  PrintOutStringNL $title;                                                      # Title of the piece so we do not lose it

  $tree->firstFromMemory($F);
  my $R = $tree->rootFromFirst($F);
  my $C = $tree->sizeFromFirst($F);

  If $R == 0,                                                                   # Empty tree
  Then
   {PrintOutStringNL "- empty";
   },
  Else
   {$C->outRightInDec(K width => 4);
    PrintOutString ": ";

     $s->call(structures => {tree  => $tree},                                   # Print root node
             parameters => {offset => $R});
    PrintOutNL;
   };

  PopR;
 }

#D2 Iteration                                                                   # Iterate through a tree non recursively

sub Nasm::X86::Tree::iterator($)                                                # Iterate through a multi way tree starting either at the specified node or the first node of the specified tree.
 {my ($t) = @_;                                                                 # Tree, optional arena else the arena associated with the tree, optionally the node to start at else the first node of the supplied tree will be used
  @_ == 1 or @_ == 3 or confess "1 or 3 parameters";
  Comment "Nasm::X86::Tree::iterator";

  my $i = genHash(__PACKAGE__.'::Tree::Iterator',                               # Iterator
    tree  => $t,                                                                # Tree we are iterating over
    node  => V(node  =>  0),                                                    # Current node within tree
    pos   => V(pos   => -1),                                                    # Current position within node
    key   => V(key   =>  0),                                                    # Key at this position
    data  => V(data  =>  0),                                                    # Data at this position
    count => V(count =>  0),                                                    # Counter - number of node
    more  => V(more  =>  1),                                                    # Iteration not yet finished
   );

  $i->node   ->copy($t->first);                                                 # Start at the first node in the tree
  $i->next;                                                                     # First element if any
 }

sub Nasm::X86::Tree::Iterator::next($)                                          # Next element in the tree.
 {my ($iterator) = @_;                                                          # Iterator
  @_ == 1 or confess "One parameter";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $success = Label;                                                        # Short circuit if ladders by jumping directly to the end after a successful push

    my $iter  = $$s{iterator};                                                  # Iterator
    my $tree  = $iter->tree;                                                    # Tree
    my $arena = $tree->arena;                                                   # Arena

    my $C = $iter->node;                                                        # Current node required
    $iter->count->copy($iter->count + 1);                                       # Count the calls to the iterator

    my $new  = sub                                                              # Load iterator with latest position
     {my ($node, $pos) = @_;                                                    # Parameters
      PushR r8, r9; PushZmm 29..31;
      $iter->node->copy($node);                                                 # Set current node
      $iter->pos ->copy($pos);                                                  # Set current position in node
      $iter->tree->getKeysData($node, 31, 30, r8, r9);                          # Load keys and data

      my $offset = $pos * $iter->tree->width;                                   # Load key and data
      $iter->key ->copy(dFromZ 31, $offset);
      $iter->data->copy(dFromZ 30, $offset);
      PopZmm; PopR;
     };

    my $done = sub                                                              # The tree has been completely traversed
     {PushR rax;
      Mov rax, 0;
      $iter->more->getReg(rax);
      PopR rax;
      };

    If $iter->pos == -1,
    Then                                                                        # Initial descent
     {my $end = Label;

      PushR r8, r9; PushZmm 29..31;
      $tree->getBlock($C, 31, 30, 29);                                          # Load keys and data

      my $l = $tree->lengthFromKeys(31);                                        # Length of the block
      If $l == 0,                                                               # Check for  empty tree.
      Then                                                                      # Empty tree
       {&$done;
        Jmp $end;
       };

      my $nodes = $tree->getLoop(30, r8);                                       # Nodes

      If $nodes > 0,
      Then                                                                      # Go left if there are child nodes
       {$tree->leftMost($C, my $l = V(offset));
        &$new($l, K(zero, 0));
       },
      Else
       {my $l = $tree->lengthFromKeys(31);                                     # Number of keys
        If $l > 0,
        Then                                                                    # Start with the current node as it is a leaf
         {&$new($C, K(zero, 0));
         },
        Else
         {&$done;
         };
       };

      SetLabel $end;
      PopZmm; PopR;
      Jmp $success;                                                             # Return with iterator loaded
     };

    my $up = sub                                                                # Iterate up to next node that has not been visited
     {my $top = Label;                                                          # Reached the top of the tree
      my $n = $C->clone('first');
      my $zmmNK = 31; my $zmmPK = 28; my $zmmTest = 25;
      my $zmmND = 30; my $zmmPD = 27;
      my $zmmNN = 29; my $zmmPN = 26;
      PushR k7, r8, r9, r14, r15; PushZmm 25..31;
      my $t = $iter->tree;

      ForEver                                                                   # Up through the tree
       {my ($start, $end) = @_;                                                 # Parameters
        $t->getKeysData($n, $zmmNK, $zmmND, r8, r9);                            # Load keys and data for current node
        my $p = $t->getUpFromData($zmmND);
        If $p == 0, sub{Jmp $end};                                              # Jump to the end if we have reached the top of the tree
        $t->getBlock($p, $zmmPK, $zmmPD, $zmmPN);                               # Load keys, data and children nodes for parent which must have children
        $n->setReg(r15);                                                        # Offset of child
        Vpbroadcastd "zmm".$zmmTest, r15d;                                      # Current node broadcasted
        Vpcmpud k7, "zmm".$zmmPN, "zmm".$zmmTest, 0;                            # Check for equal offset - one of them will match to create the single insertion point in k6
        Kmovw r14d, k7;                                                         # Bit mask ready for count
        Tzcnt r14, r14;                                                         # Number of leading zeros gives us the position of the child in the parent
        my $i = V(indexInParent, r14);                                          # Index in parent
        my $l = $t->lengthFromKeys($zmmPK);                                     # Length of parent

        If $i < $l,
        Then                                                                    # Continue with this node if all the keys have yet to be finished
         {&$new($p, $i);
          Jmp $top;
         };
        $n->copy($p);                                                           # Continue with parent
       };
      &$done;                                                                   # No nodes not visited
      SetLabel $top;
      PopZmm;
      PopR;
     };

    $iter->pos->copy(my $i = $iter->pos + 1);                                   # Next position in block being scanned
    PushR r8, r9; PushZmm 29..31;
    my $t = $iter->tree;
    $t->getBlock($C, 31, 30, 29, r8, r9);                                       # Load keys and data
    my $l = $t->lengthFromKeys(31);                                             # Length of keys
    my $n = dFromZ 29, 0;                                                       # First node will ne zero if on a leaf
    If $n == 0,
    Then                                                                        # Leaf
     {If $i < $l,
      Then
       {&$new($C, $i);
       },
      Else
       {&$up;
       };
     },
    Then                                                                        # Node
     {my $offsetAtI = dFromZ 29, $i * $iter->tree->width;
      $iter->tree->leftMost($offsetAtI, my $l = V(offset));
      &$new($l, K(zero, 0));
     };

    PopZmm; PopR;
    SetLabel $success;
   } structures => {iterator => $iterator},
     name       => 'Nasm::X86::Tree::Iterator::next ';

  $s->call(structures => {iterator=>$iterator});

  $iterator                                                                     # Return the iterator
 }

sub Nasm::X86::Tree::by($&)                                                     # Call the specified block with each (key, data) from the specified tree in order.
 {my ($tree, $block) = @_;                                                      # Tree descriptor, block to execute
  @_ == 2 or confess "Two parameters required";

  my $iter  = $tree->iterator;                                                     # Create an iterator
  my $start = SetLabel Label; my $end = Label;                                  # Start and end of loop
  If $iter->more == 0, sub {Jmp $end};                                          # Jump to end if there are no more elements to process
  &$block($iter, $end);                                                         # Perform the block parameterized by the iterator and the end label
  $iter->next;                                                                  # Next element
  Jmp $start;                                                                   # Process next element
  SetLabel $end;                                                                # End of the loop
 }

#D1 Quarks                                                                      # Quarks allow us to replace unique strings with unique numbers.  We can translate either from a string to its associated number or from a number to its associated string or from a quark in one set of quarks to the corresponding quark with the same string in another set of quarks.

sub DescribeQuarks(%)                                                           # Return a descriptor for a set of quarks.
 {my (%options) = @_;                                                           # Options

  genHash(__PACKAGE__."::Quarks",                                               # Quarks
    arena            => ($options{arena} // DescribeArena),                     # The arena containing the quarks
    stringsToNumbers => ($options{stringsToNumbers} // DescribeTree),           # A tree mapping strings to numbers
    numbersToStrings => ($options{numbersToStrings} // DescribeArray),          # Array mapping numbers to strings
   );
 }

sub Nasm::X86::Arena::DescribeQuarks($)                                         # Return a descriptor for a tree in the specified arena.
 {my ($arena) = @_;                                                             # Arena descriptor
  DescribeQuarks(arena=>$arena)
 }

sub Nasm::X86::Arena::CreateQuarks($)                                           # Create quarks in a specified arena.  A quark maps a  string to a number and provides a way to recover the string given the number. The string is stored in the arena if it is not already present and its offset is stored as the value of the numbers array associated with the quarks. The string tree is separated first by the string length, then the string contents in 4 byte blocks until the string is exhausted.  The index of the element in the numbers array i stored in the last sub tree reached by the string. The quark number is used to index the numbers array to get the value of the offset of the string in the arena.
 {my ($arena) = @_;                                                             # Arena description optional arena address
  @_ == 1 or confess "1 parameter";

  my $q = $arena->DescribeQuarks;                                               # Return a descriptor for a tree at the specified offset in the specified arena
  $q->stringsToNumbers = $arena->CreateTree;
  $q->numbersToStrings = $arena->CreateArray;

  $q                                                                            # Description of array
 }

sub Nasm::X86::Quarks::reload($%)                                               # Reload the description of a set of quarks.
 {my ($q, %options) = @_;                                                       # Quarks, {arena=>arena to use; tree => first tree block; array => first array block}
  @_ >= 1 or confess "One or more parameters";

  $q->stringsToNumbers->reload(arena=>$options{arena}, first=>$options{tree});
  $q->numbersToStrings->reload(arena=>$options{arena}, first=>$options{array});

  $q                                                                            # Return upgraded quarks descriptor
 }

sub Nasm::X86::Quarks::put($$)                                                  # Create a quark from a string and return its number.
 {my ($q, $string) = @_;                                                        # Quarks, string
  @_ == 2 or confess "Two parameters";

  PushR zmm0;
  my $s = CreateShortString(0)->loadConstantString($string);                    # Load the operator name in its alphabet with the alphabet number on the first byte
  my $N = $q->quarkFromShortString($s);                                         # Create quark from string
  PopR;
  $N                                                                            # Created quark number for subroutine
 }

sub Nasm::X86::Quarks::quarkFromShortString($$)                                 # Create a quark from a short string.
 {my ($q, $string) = @_;                                                        # Quarks, short string
  @_ == 2 or confess "2 parameters";

  my $l = $string->len;
  my $Q = V(quark);                                                             # The variable that will hold the quark number

  AndBlock
   {my ($fail, $end, $start) = @_;                                              # Fail block, end of fail block, start of test block

    my $t = $q->stringsToNumbers->copyDescription;                              # Reload strings to numbers
    $t->findAndReload($l);                                                      # Separate by length
    If $t->found == 0, Then {Jmp $fail};                                        # Length not found
    $t->findShortString($string);                                               # Find the specified short string
    If $t->found == 0, Then {Jmp $fail};                                        # Short string not found
    $Q->copy($t->data);                                                         # Load found quark number
   }
  Fail
   {my $N = $q->numbersToStrings->size;                                         # Get the number of quarks
    my $S = $q->arena->CreateString;                                            # Create a string in the arena to hold the quark name
       $S->appendShortString($string);                                          # Append the short string to the string
    my $T = $q->stringsToNumbers->copyDescription;                              # Reload strings to numbers tree descriptor
    $T->insertTreeAndReload($l);                                                # Classify strings by length
    $T->insertShortString($string, $N);                                         # Insert the string with the quark number as data into the tree of quark names
    $q->numbersToStrings->push($S->first);                                      # Append the quark number with a reference to the first block of the string
    $Q->copy($N);
   };

  $Q                                                                            # Quark number for short string in a variable
 }

sub Nasm::X86::Quarks::locateQuarkFromShortString($$)                           # Locate (if possible) but do not create a quark from a short string. A quark of -1 is returned if there is no matching quark otherwise the number of the matching quark is returned in a variable.
 {my ($q, $string) = @_;                                                        # Quarks, short string
  @_ == 2 or confess "2 parameters";

  my $l = $string->len;
  my $Q = V(quark);                                                             # The variable that will hold the quark number

  AndBlock
   {my ($fail, $end, $start) = @_;                                              # Fail block, end of fail block, start of test block

    my $t = $q->stringsToNumbers->copyDescription;                              # Reload strings to numbers
    $t->findAndReload($l);                                                      # Separate by length
    If $t->found == 0, Then {Jmp $fail};                                        # Length not found
    $t->findShortString($string);                                               # Find the specified short string
    If $t->found == 0, Then {Jmp $fail};                                        # Length not found
    $Q->copy($t->data);                                                         # Load found quark number
   }
  Fail
   {$Q->copy(-1);
   };

  $Q                                                                            # Quark number for short string in a variable
 }

sub Nasm::X86::Quarks::shortStringFromQuark($$$)                                # Load a short string from the quark with the specified number. Returns a variable that is set to one if the quark was found else zero.
 {my ($q, $number, $string) = @_;                                               # Quarks, variable quark number, short string to load
  @_ == 3 or confess "3 parameters";

  my $f = V(found);                                                             # Whether the quark was found

  AndBlock
   {my ($fail, $end, $start) = @_;                                              # Fail block, end of fail block, start of test block
    my $N = $q->numbersToStrings->size;                                         # Get the number of quarks
    If $number >= $N, Then {Jmp $fail};                                         # Quark number too big to be valid
    my $e = $q->numbersToStrings->get($number);                                 # Get long string indexed by quark

    my $S = $q->numbersToStrings->arena->DescribeString(first=>$e);             # Long string descriptor
    $S->saveToShortString($string);                                             # Load long string into short string
    $f->copy(1);                                                                # Show short string is valid
   }
  Fail                                                                          # Quark too big
   {$f->copy(0);                                                                # Show failure code
   };

  $f
 }

sub Nasm::X86::Quarks::quarkToQuark($$$)                                        # Given a variable quark number in one set of quarks find the corresponding quark in another set of quarks and return it in a variable.  No new quarks are created in this process.  If the quark cannot be found in the first set we return -1, if it cannot be found in the second set we return -2 else the number of the matching quark.
 {my ($Q, $number, $q) = @_;                                                    # First set of quarks, variable quark number in first set, second set of quarks
  @_ == 3 or confess "3 parameters";
  ref($q) && ref($q) =~ m(Nasm::X86::Quarks) or
    confess "Quarks required";

  my $N = V(found);                                                             # Whether the quark was found

  PushR zmm31;

  my $s = CreateShortString 0;
  If $Q->shortStringFromQuark($number, $s) == 0,                                # Quark not found in the first set
  Then
   {$N->copy(-1);                                                               # Not found in first set
   },
  Ef {$q->locateQuarkFromShortString($s) >= 0}                                  # Found the matching quark in the second set
  Then
   {$N->copy($q->locateQuarkFromShortString($s));                               # Load string from quark in second set
   },
  Else
   {$N->copy(-2);                                                               # Not found in second set
   };

  PopR;

  $N                                                                            # Return the variable containing the matching quark or -1 if no such quark
 }

sub Nasm::X86::Quarks::quarkFromSub($$$)                                        # Create a quark from a subroutine definition.
 {my ($q, $sub, $name) = @_;                                                    # Quarks, subroutine address as a variable, name as a short string
  @_ == 3 or confess "3 parameters";
  ref($sub) && ref($sub) =~ m(Nasm::X86::Variable) or
    confess "Subroutine address required as a variable";

  PushR zmm0;
  my $N = $q->quarkFromShortString($name);                                      # Create quark
  my $e = $q->numbersToStrings->get($N);                                        # Get the long string associated with the sub
  my $l = $q->arena->DescribeString(first => $e);                               # Create a definition for the string addressed by the quark
  $l->clear;                                                                    # Empty the string
  $l->appendVar($sub);                                                          # Append the subroutine address saving the full address in the first 8 bytes of the long string
  $l->appendShortString($name);                                                 # Append the subroutine name to the string
  PopR;
  $N                                                                            # Quark number gives rapid access to the sub
 }

sub Nasm::X86::Quarks::quarkFromSub22($$$)                                      # Create a quark from a subroutine definition.
 {my ($q, $sub, $string) = @_;                                                  # Quarks, subroutine definition, name as a short string
  @_ == 3 or confess "3 parameters";
  ref($sub) && ref($sub) =~ m(Nasm::X86::Sub) or
    confess "Subroutine definition needed";

  my $N = $q->quarkFromShortString($string);                                    # Create quark
  $q->numbersToStrings->put(index => $N, element => $sub->V);                   # Reuse the array element to point to the sub and the sub name held a a string in the arena
  $N                                                                            # Quark number gives rapid access to the sub
 }

sub Nasm::X86::Quarks::subFromQuark($$)                                         # Get the offset of a subroutine as a variable from a set of quarks.
 {my ($q, $number) = @_;                                                        # Quarks, variable subroutine number
  @_ == 2 or confess "2 parameters";

  my $s = V('sub');                                                             # The offset of the subroutine or -1 if the subroutine cannot be found

  AndBlock
   {my ($fail, $end, $start) = @_;                                              # Fail block, end of fail block, start of test block
    my $N = $q->numbersToStrings->size;                                         # Get the number of quarks
    If $number >= $N, Then {Jmp $fail};                                         # Quark number too big to be valid
    my $e = $q->numbersToStrings->get($number);                                 # Get the offset of the long string describing the sub
    my $l = $q->arena->DescribeString(first => $e);                             # Create a definition for the string addressed by the quark
    $s->copy($l->getQ1);                                                        # Load first quad word in string
   }
  Fail                                                                          # Quark too big
   {$s->copy(-1);                                                               # Show failure
   };

  $s                                                                            # Return subroutine offset or -1
 }

sub Nasm::X86::Quarks::call($$)                                                 # Call a subroutine via its quark number. Return one in a variable if the subroutine was found and called else zero.
 {my ($q, $number) = @_;                                                        # Quarks, variable subroutine number
  @_ == 2 or confess "2 parameters";

  my $s = V(found);                                                             # Whether the quark was found

  AndBlock
   {my ($fail, $end, $start) = @_;                                              # Fail block, end of fail block, start of test block
    my $N = $q->numbersToStrings->size;                                         # Get the number of quarks
    If $number >= $N, Then {Jmp $fail};                                         # Quark number too big to be valid
    my $e = $q->numbersToStrings->get($number);                                 # Get subroutine indexed by quark
    my $l = $q->arena->DescribeString(first => $e);                             # Create a definition for the string addressed by the quark

    PushR r15;
    $l->getQ1->setReg(r15);                                                     # Load first quad word in string
    Call r15;                                                                   # Call sub routine
    PopR r15;
    $s->copy(1);                                                                # Show subroutine was found and called
   }
  Fail                                                                          # Quark too big
   {$s->copy(0);                                                                # Show failure
   };

  $s                                                                            # Return subroutine offset or -1
 }

sub Nasm::X86::Quarks::dump($)                                                  # Dump a set of quarks.
 {my ($q) = @_;                                                                 # Quarks
  @_ == 1 or confess "1 parameter";

  my $l = $q->numbersToStrings->size;                                           # Number of subs
  PushR r15, zmm0;
  my $L = $q->arena->length;
  $l->for(sub
   {my ($index, $start, $next, $end) = @_;
    my $e = $q->numbersToStrings->get($index);                                  # Get long string indexed by quark
    $index->out("Quark : "); $e->out(" => ");

    my $n = $q->numbersToStrings->get($index);
    If $n < $L,                                                                 # Appears to be a string within the arena
    Then
     {my $p = $q->arena->address + $n;
      $p->setReg(r15);
      Vmovdqu64 zmm0, "[r15]";
      PrintOutString " == ";
      PrintOneRegisterInHex $stdout, zmm0;
     };
    PrintOutNL;
   });
  PopR;
 }

sub Nasm::X86::Quarks::putSub($$$)                                              # Put a new subroutine definition into the sub quarks.
 {my ($q, $string, $sub) = @_;                                                  # Subquarks, string containing operator type and method name, variable offset to subroutine
  @_ == 3 or confess "3 parameters";
  !ref($string) or
    confess "Scalar string required, not ".dump($string);
  ref($sub) && ref($sub) =~ m(Nasm::X86::Sub) or
    confess "Subroutine definition required, not ".dump($string);

  PushR zmm0;
  my $s = CreateShortString(0)->loadConstantString($string);                    # Load the operator name with the alphabet number in the first byte
  my $N = $q->quarkFromSub($sub->V, $s);                                        # Create quark from sub
  PopR;
  $N                                                                            # Created quark number for subroutine
 }

sub Nasm::X86::Quarks::subFromQuarkViaQuarks($$$)                               # Given the quark number for a lexical item and the quark set of lexical items get the offset of the associated method.
 {my ($q, $lexicals, $number) = @_;                                             # Sub quarks, lexical item quarks, lexical item quark
  @_ == 3 or confess "3 parameters";

  ref($lexicals) && ref($lexicals) =~ m(Nasm::X86::Quarks) or                   # Check that we have been given a quark set as expected
    confess "Quarks expected";

  my $Q = $lexicals->quarkToQuark($number, $q);                                 # Either the offset to the specified method or -1.
  my $r = V('sub', 0);                                                          # Matching routine not found
  If $Q >= 0,                                                                   # Quark found
  Then
   {my $e = $q->numbersToStrings->get($Q);                                      # Get subroutine indexed by quark
    my $l = $q->arena->DescribeString(first => $e);                             # Create a definition for the string addressed by the quark
    $r->copy($l->getQ1);                                                        # Subroutine address
   };
  $r                                                                            # Return sub routine offset
 }

sub Nasm::X86::Quarks::subFromShortString($$)                                   # Given a short string get the offset of the associated subroutine or zero if no such subroutine exists.
 {my ($q, $shortString) = @_;                                                   # Sub quarks, short string
  @_ == 2 or confess "Two parameters";

  ref($shortString) && ref($shortString) =~ m(Nasm::X86::ShortString) or        # Check that we have been given a short string as expected
    confess "shortString expected";

  my $r = V('sub', 0);                                                          # Matching routine not found
  my $number = $q->locateQuarkFromShortString($shortString);                    # Quark number from short string
  If $number > -1,                                                              # We found the quark number
  Then
   {my $e = $q->numbersToStrings->get($number);                                 # Get subroutine indexed by quark
    my $l = $q->arena->DescribeString(first => $e);                             # Create a definition for the string addressed by the quark
    $r->copy($l->getQ1);                                                        # Subroutine address
   };
  $r                                                                            # Return sub routine offset
 }

sub Nasm::X86::Quarks::callSubFromShortString($$$@)                             # Given a short string call the associated subroutine if it exists.
 {my ($q, $sub, $shortString, @parameters) = @_;                                # Sub quarks, subroutine definition, short string, parameters
  @_ >= 2 or confess "At least two parameters";

  ref($shortString) && ref($shortString) =~ m(Nasm::X86::ShortString) or        # Check that we have been given a short string as expected
    confess "shortString expected";

  my $s = $q->subFromShortString($shortString);                                 # Quark number from short string
  If $s > 0,                                                                    # We found the sub
  Then
   {$sub->via($s, @parameters);                                                 # Call referenced subroutine
   };
  $s                                                                            # Return subroutine offset
 }

sub Nasm::X86::Quarks::callSubFromQuarkViaQuarks($$$$@)                         # Given the quark number for a lexical item and the quark set of lexical items call the associated method.
 {my ($q, $lexicals, $sub, $number, @parameters) = @_;                          # Sub quarks, lexical item quarks, subroutine definition, lexical item quark, parameters
  @_ >= 4 or confess "At least four parameters";

  my $s = $q->subFromQuarkViaQuarks($lexicals, $number);                        # Either the offset to the specified method or -1.
  If $s > 0,                                                                    # Quark found
  Then
   {$sub->via($s, @parameters);
   };
  $s                                                                            # Return sub routine offset
 }

sub Nasm::X86::Quarks::subFromQuarkNumber($$)                                   # Get the sub associated with a sub quark by its number.
 {my ($q, $number) = @_;                                                        # Sub quarks, lexical item quark
  @_ == 2 or confess "Two parameters";

  my $r = V('sub', -1);                                                         # Matching routine not found
  my $l = $q->numbersToStrings->size;                                           # Number of subs
  If $number < $l,                                                              # Quark found
  Then
   {my $e = $q->numbersToStrings->get($number);                                 # Get subroutine indexed by quark
    my $l = $q->arena->DescribeString(first => $e);                             # Create a definition for the string addressed by the quark
    $r->copy($l->getQ1);                                                        # Subroutine address
   };

  $r                                                                            # Return sub routine offset
 }

sub Nasm::X86::Quarks::callSubFromQuarkNumber($$$@)                             # Call the sub associated with a quark number.
 {my ($q, $sub, $number, @parameters) = @_;                                     # Sub quarks, subroutine definition, lexical item quark, parameters to called subroutine
  @_ >= 3 or confess "At least three parameters";

  my $s = $q->subFromQuarkNumber($number);
  $sub->via($s, @parameters);
 }

#D1 Assemble                                                                    # Assemble generated code

sub CallC($@)                                                                   # Call a C subroutine.
 {my ($sub, @parameters) = @_;                                                  # Name of the sub to call, parameters
  my @order = (rdi, rsi, rdx, rcx, r8, r9, r15);
  PushR @order;

  for my $i(keys @parameters)                                                   # Load parameters into designated registers
   {Mov $order[$i], $parameters[$i];
   }

  Push rax;                                                                     # Align stack on 16 bytes
  Mov rax, rsp;                                                                 # Move stack pointer
  Shl rax, 60;                                                                  # Get lowest nibble
  Shr rax, 60;
  IfEq                                                                          # If we are 16 byte aligned push two twos
  Then
   {Mov rax, 2; Push rax; Push rax;
   },
  Else                                                                          # If we are not 16 byte aligned push one one.
   {Mov rax, 1; Push rax;
   };

  if (ref($sub))                                                                # Where do we use this option?
   {Call $sub->start;
   }
  else                                                                          # Call named subroutine
   {Call $sub;
   }

  Pop r15;                                                                      # Decode and reset stack after 16 byte alignment
  Cmp r15, 2;                                                                   # Check for double push
  Pop r15;                                                                      # Single or double push
  IfEq Then {Pop r15};                                                          # Double push
  PopR @order;
 }

sub Extern(@)                                                                   # Name external references.
 {my (@externalReferences) = @_;                                                # External references
  push @extern, @_;
 }

sub Link(@)                                                                     # Libraries to link with.
 {my (@libraries) = @_;                                                         # External references
  push @link, @_;
 }

sub Start()                                                                     # Initialize the assembler.
 {@bss = @data = @rodata = %rodata = %rodatas = %subroutines = @text =
  @PushR = @PushZmm = @PushMask = @extern = @link = @VariableStack = ();
# @RegistersAvailable = ({map {$_=>1} @GeneralPurposeRegisters});               # A stack of hashes of registers that are currently free and this can be used without pushing and popping them.
  SubroutineStartStack;                                                         # Number of variables at each lexical level
  $Labels = 0;
 }

sub Exit(;$)                                                                    # Exit with the specified return code or zero if no return code supplied.  Assemble() automatically adds a call to Exit(0) if the last operation in the program is not a call to Exit.
 {my ($c) = @_;                                                                 # Return code
  $c //= 0;
  my $s = Subroutine
   {Comment "Exit code: $c";
    PushR (rax, rdi);
    Mov rdi, $c;
    Mov rax, 60;
    Syscall;
    PopR;
   } [], name => "Exit_$c";

  $s->call;
 }

my $LocateIntelEmulator;                                                        # Location of Intel Software Development Emulator

sub LocateIntelEmulator()                                                       #P Locate the Intel Software Development Emulator.
 {my @locations = qw(/var/isde/sde64 sde/sde64 ./sde64);                        # Locations at which we might find the emulator
  my $downloads = q(/home/phil/Downloads);                                      # Downloads folder

  return $LocateIntelEmulator if defined $LocateIntelEmulator;                  # Location has already been discovered

  for my $l(@locations)                                                         # Try each locations
   {return $LocateIntelEmulator = $l if -e $l;                                  # Found it - cache and return
   }

  if (qx(sde64 -version) =~ m(Intel.R. Software Development Emulator))          # Try path
   {return $LocateIntelEmulator = "sde64";
   }

  return undef unless -e $downloads;                                            # Skip local install if not developing
  my $install = <<END =~ s(\n) (  && )gsr =~ s(&&\s*\Z) ()sr;                   # Install sde
cd $downloads
curl https://software.intel.com/content/dam/develop/external/us/en/documents/downloads/sde-external-8.63.0-2021-01-18-lin.tar.bz2 > sde.tar.bz2
tar -xf sde.tar.bz2
sudo mkdir -p /var/isde/
sudo cp -r * /var/isde/
ls -ls /var/isde/
END

  say STDERR qx($install);                                                      # Execute install

  for my $l(@locations)                                                         # Retry install locations after install
   {return $LocateIntelEmulator = $l if -e $l;                                  # Found it - cache and return
   }
  undef                                                                         # Still not found - give up
 }

sub getInstructionCount()                                                       #P Get the number of instructions executed from the emulator mix file.
 {return 0 unless -e $sdeMixOut;
  my $s = readFile $sdeMixOut;
  if ($s =~ m(\*total\s*(\d+))) {return $1}
  confess;
 }

sub Optimize(%)                                                                 #P Perform code optimizations.
 {my (%options) = @_;                                                           # Options
  my %o = map {$_=>1} $options{optimize}->@*;
  if (1 or $o{if})                                                              # Optimize if statements by looking for the unnecessary reload of the just stored result
   {for my $i(1..@text-2)                                                       # Each line
     {my $t = $text[$i];
      if ($t =~ m(\A\s+push\s+(r\d+)\s*\Z)i)                                    # Push
       {my $R = $1;                                                             # Register being pushed
        my $s = $text[$i-1];                                                    # Previous line
        if ($s =~ m(\A\s+pop\s+$R\s*\Z)i)                                       # Matching push
         {my $r = $text[$i-2];
          if ($r =~ m(\A\s+mov\s+\[rbp-8\*\((\d+)\)],\s*$R\s*\Z)i)              # Save to variable
           {my $n = $1;                                                         # Variable number
            my $u = $text[$i+1];
            if ($u =~ m(\A\s+mov\s+$R,\s*\[rbp-8\*\($n\)]\s*\Z)i)               # Reload register
             {for my $j($i-1..$i+1)
               {$text[$j] = '; out '. $text[$j];
               }
             }
           }
         }
       }
     }
   }
 }

our $assembliesPerformed  = 0;                                                  # Number of assemblies performed
our $instructionsExecuted = 0;                                                  # Total number of instructions executed
our $totalBytesAssembled  = 0;                                                  # Total size of the output programs

sub Assemble(%)                                                                 # Assemble the generated code.
 {my (%options) = @_;                                                           # Options
  my $aStart = time;
  my $library    = $options{library};                                           # Create  the named library if supplied from the supplied assembler code
  my $debug      = $options{debug}//0;                                          # Debug: 0 - none (minimal output), 1 - normal (debug output and confess of failure), 2 - failures (debug output and no confess on failure) .
  my $debugTrace = $options{trace}//0;                                          # Trace: 0 - none (minimal output), 1 - trace with sde64
  my $keep       = $options{keep};                                              # Keep the executable

  my $sourceFile = q(z.asm);                                                    # Source file
  my $execFile   = $keep // q(z);                                               # Executable file
  my $listFile   = q(z.txt);                                                    # Assembler listing
  my $objectFile = $library // q(z.o);                                          # Object file
  my $o1         = 'zzzOut.txt';                                                # Stdout from run
  my $o2         = 'zzzErr.txt';                                                # Stderr from run

  unlink $o1, $o2, $objectFile, $execFile, $listFile, $sourceFile;              # Remove output files

  Exit 0 unless $library or @text > 4 && $text[-4] =~ m(Exit code:);            # Exit with code 0 if an exit was not the last thing coded in a program but ignore for a library.

# Optimize(%options);                                                           # Perform any optimizations requested

  if (1)                                                                        # Concatenate source code
   {my $r = join "\n", map {s/\s+\Z//sr}   @rodata;
    my $d = join "\n", map {s/\s+\Z//sr}   @data;
    my $B = join "\n", map {s/\s+\Z//sr}   @bss;
    my $t = join "\n", map {s/\s+\Z//sr}   @text;
    my $x = join "\n", map {qq(extern $_)} @extern;
    my $N = $VariableStack[0];                                                  # Number of variables needed on the stack

    my $A = <<END;                                                              # Source code
bits 64
default rel
END

    $A .= <<END if $t and !$library;
global _start, main
  _start:
  main:
  Enter $N*8, 0
  $t
  Leave
END

    $A .= <<END if $t and $library;
  $t
END

    $A .= <<END if $r;
section .rodata
  $r
END
    $A .= <<END if $d;
section .data
  $d
END
    $A .= <<END if $B;
section .bss
  $B
  $d
END
    $A .= <<END if $x;
section .text
$x
END

    owf($sourceFile, $A);                                                       # Save source code to source file
   }

  if (!confirmHasCommandLineCommand(q(nasm)))                                   # Check for network assembler
   {my $f = fpf(currentDirectory, $sourceFile);
    say STDERR <<END;
Assember code written to the following file:

$f

I cannot compile this file because you do not have Nasm installed, see:

https://www.nasm.us/
END
    return;
   }

  my $emulator = exists $options{emulator} ? $options{emulator} : 1;            # Emulate by default unless told otherwise
  my $sde      = LocateIntelEmulator;                                           # Locate the emulator
  my $run      = !$keep && !$library;                                           # Are we actually going to run the resulting code?

  if ($run and $emulator and !$sde)                                             # Complain about the emulator if we are going to run and we have not suppressed the emulator and the emulator is not present
   {my $f = fpf(currentDirectory, $execFile);
    say STDERR <<END;
Executable written to the following file:

$f

I am going to run this without using the Intel emulator. Your program will
crash if it contains instructions not implemented on your computer.

You can get the Intel emulator from:

https://software.intel.com/content/dam/develop/external/us/en/documents/downloads/sde-external-8.63.0-2021-01-18-lin.tar.bz2

To avoid this message, use option(1) below to produce just an executable
without running it, or use the option(2) to run without the emulator:

(1) Assemble(keep=>"executable file name")

(2) Assemble(emulator=>0)
END
    $emulator = 0;
   }

  if (my @emulatorFiles = searchDirectoryTreesForMatchingFiles(qw(. .txt)))     # Remove prior emulator output files
   {for my $f(@emulatorFiles)
     {unlink $f if $f =~ m(sde-mix-out);
     }
   }
  unlink qw(sde-ptr-check.out.txt sde-mix-out.txt sde-debugtrace-out.txt);

  if (1)                                                                        # Assemble
   {my $I = @link ? $interpreter : '';                                          # Interpreter only required if calling C
    my $L = join " ",  map {qq(-l$_)} @link;                                    # List of libraries to link supplied via Link directive.
    my $e = $execFile;
    my $a = qq(nasm -O0 -l $listFile -o $objectFile $sourceFile);               # Assembly options

    my $cmd  = $library
      ? qq($a -fbin)
      : qq($a -felf64 -g && ld $I $L -o $e $objectFile && chmod 744 $e);

#   say STDERR $cmd;
    qx($cmd);
  }

  my $aTime = time - $aStart;

  my $out  = $run ? "1>$o1" : '';
  my $err  = $run ? "2>$o2" : '';

  my $exec = sub                                                                # Execution string
   {my $o = qq($sde -mix -ptr-check);                                           # Emulator options
       $o = qq($sde -mix -ptr-check -debugtrace -footprint) if $debugTrace;     # Emulator options
    my $e = $execFile;
    $emulator ? qq($o -- ./$e $err $out) : qq(./$e $err $out);                  # Execute with or without the emulator
   }->();


  if (1)                                                                        # Execution details
   {my $eStart = time;
    qx($exec) if $run;                                                          # Run unless suppressed by user or library
    my $eTime = time - $eStart;

    my $instructions       = getInstructionCount;                               # Instructions executed under emulator
    $instructionsExecuted += $instructions;                                     # Count instructions executed
    my $p = $assembliesPerformed++;                                             # Count assemblies
    my $n = $options{number};
    !$n or $n == $p or warn "Assembly $p versus number => $n";

    my $bytes = (fileSize($execFile)//9448) - 9448;                             # Estimate the size of the output program
    $totalBytesAssembled += $bytes;                                             # Estimate total of all programs assembled

    my (undef, $file, $line) = caller();                                        # Line in caller

    say STDERR sprintf("        %12s    %12s    %12s    %12s  %12s  %12s",      # Header if necessary
       "Clocks", "Bytes", "Total Clocks", "Total Bytes", "Run Time", "Assembler")
      if $assembliesPerformed % 100 == 1;

    say STDERR                                                                  # Rows
      sprintf("%4d    %12s    %12s    %12s    %12s  %12.2f  %12.2f  at $file line $line",
      $assembliesPerformed,
      (map {numberWithCommas $_} $instructions,         $bytes,
                                 $instructionsExecuted, $totalBytesAssembled),
                                 $eTime, $aTime);
   }

  if ($run and $debug == 0 and -e $o2)                                          # Print errors if not debugging
   {say STDERR readBinaryFile($o2);
   }

  if ($run and $debug == 1)                                                     # Print files if soft debugging
   {say STDERR readFile($o1) =~ s(0) ( )gsr;
    say STDERR readFile($o2);
   }

  confess "Failed $?" if $debug < 2 and $?;                                     # Check that the assembly succeeded

  if ($run and $debug < 2 and -e $o2 and readFile($o2) =~ m(SDE ERROR:)s)       # Emulator detected an error
   {confess "SDE ERROR\n".readFile($o2);
   }

  unlink $objectFile unless $library;                                           # Delete files
  unlink $execFile   unless $keep;                                              # Delete executable unless asked to keep it or its a library

  if (my $N = $options{countComments})                                          # Count the comments so we can see what code to put into subroutines
   {my %c; my %b;                                                               # The number of lines between the comments, the number of blocks
    my $s;
    for my $c(readFile $sourceFile)
     {if (!$s)
       {if ($c =~ m(;\s+CommentWithTraceBack\s+PushR))
         {$s = $c =~ s(Push) (Pop)r;
          $b{$s}++;
         }
       }
      elsif ($c eq $s)  {$s = undef}
      else              {$c{$s}++}
     }

    my @c;
    for my $c(keys %c)                                                          # Remove comments that do not appear often
     {push @c, [$c{$c}, $b{$c}, $c] if $c{$c} >= $N;
     }
    my @d = sort {$$b[0] <=> $$a[0]} @c;
    say STDERR formatTable(\@d, [qw(Lines Blocks Comment)]);                    # Print frequently appearing comments
   }

  Start;                                                                        # Clear work areas for next assembly

  if ($run and defined(my $e = $options{eq}))                                   # Diff results against expected
   {my $g = readFile($debug < 2 ? $o1 : $o2);
       $e =~ s(\s+#.*?\n) (\n)gs;                                               # Remove comments so we can annotate listings
    s(Subroutine trace back.*) ()s for $e, $g;                                  # Remove any trace back because the location of the subroutine in memory will vary
    if ($g ne $e)
     {my ($s, $G, $E) = stringsAreNotEqual($g, $e);
      if (length($s))
       {my $line = 1 + length($s =~ s([^\n])  ()gsr);
        my $char = 1 + length($s =~ s(\A.*\n) ()sr);
        say STDERR "Comparing wanted with got failed at line: $line, character: $char";
        say STDERR "Start:\n$s";
       }
      my $b1 = '+' x 80;
      my $b2 = '_' x 80;
      say STDERR "Want $b1\n", firstNChars($E, 80);
      say STDERR "Got  $b2\n", firstNChars($G, 80);
      say STDERR "Want: ", dump($e);
      say STDERR "Got : ", dump($g);
      confess "Test failed";                                                    # Test failed unless we are debugging test failures
     }
    return 1;                                                                   # Test passed
   }

  return scalar(readFile($debug < 2 ? $o1 : $o2)) if $run;                      # Show stdout results unless stderr results requested
  $exec;                                                                        # Retained output
 }

sub removeNonAsciiChars($)                                                      #P Return a copy of the specified string with all the non ascii characters removed.
 {my ($string) = @_;                                                            # String
  $string =~ s([^a-z0..9]) ()igsr;                                              # Remove non ascii characters
 }

sub totalBytesAssembled                                                         #P Total size in bytes of all files assembled during testing.
 {$totalBytesAssembled
 }

sub CreateLibrary(%)                                                            # Create a library.
 {my (%library) = @_;                                                           # Library definition

  my @s = sort keys $library{subroutines}->%*;                                  # The names of the subroutines in the library

  my %s = map                                                                   # The library is initialized by calling it - the library loads the addresses of its subroutines onto the stack for easy retrieval by the caller.
   {my $l = Label;                                                              # Start label for subroutine
    my  $o = "qword[rsp-".(($_+1) * RegisterSize rax)."]";                      # Position of subroutine on stack
    Mov $o, $l.'-$$';                                                           # Put offset of subroutine on stack
    Add $o, r15;                                                                # The library must be called via r15 to convert the offset to the address of each subroutine

    $s[$_] => genHash("NasmX86::Library::Subroutine",                           # Subroutine definitions
      number  => $_ + 1,                                                        # Number of subroutine from 1
      label   => $l,                                                            # Label of subroutine
      name    => $s[$_],                                                        # Name of subroutine
      code    => $library{subroutines}{$s[$_]},                                 # Perl subroutine to write code of assembler subroutine
      call    => undef,                                                         # Perl subroutine to call assembler subroutine
   )} keys @s;

  Ret;                                                                          # Return from library initialization

  for my $s(@s{@s})                                                             # Generate code for each subroutine in the library
   {Align 16;
    SetLabel $s->label;                                                         # Start label
    $s->code->();                                                               # Code of subroutine
    Ret;                                                                        # Return from subroutine
   }

  unlink my $l = $library{file};                                                # The name of the file containing the library

  Assemble library => $l;                                                       # Create the library file

  $library{locations} = \%s;                                                    # Location of each subroutine on the stack

  genHash "NasmX86::Library", %library
 }

sub NasmX86::Library::load($)                                                   # Load a library and return the addresses of its subroutines as variables.
 {my ($library) = @_;                                                           # Description of library to load
  my ($address, $size) = ReadFile $$library{file};                              # Read library file into memory
  $address->call(r15);                                                          # Load addresses of subroutines onto stack

  my @s = sort keys $$library{subroutines}->%*;                                 # The names of the subroutines in the library

  my %s = $$library{locations}->%*;                                             # Subroutines in library
  for my $s(@s{@s})                                                             # Copy the address of each subroutine from the stack taking care not to disturb the stack beyond the stack pointer.
   {Mov r15, "[rsp-".(($s->number + 1) * RegisterSize rax)."]";                 # Address of subroutine in this process
    $s->call = V $s->name => r15;                                               # Address of subroutine in this process from stack as a variable
   }

  $$library{address} = $address;                                                # Save address and size of library
  $$library{size}    = $size;

  map {my $c = $_->call; sub {$c->call}} @s{@s};                                # Call subroutine via variable - perl bug because $_ by  itself is not enough
 }

#d
#-------------------------------------------------------------------------------
# Export - eeee
#-------------------------------------------------------------------------------

if (0)                                                                          # Print exports
 {my @e;
  for my $a(sort keys %Nasm::X86::)
   {next if $a =~ m(BAIL_OUT|BEGIN|DATA|confirmHasCommandLineCommand|currentDirectory|fff|fileMd5Sum|fileSize|findFiles|firstNChars|formatTable|fpe|fpf|genHash|lll|owf|pad|readFile|stringsAreNotEqual|stringMd5Sum|temporaryFile);
    next if $a =~ m(\AEXPORT);
    next if $a !~ m(\A[A-Z]) and !$Registers{$a};
    next if $a =~ m(::\Z);
    push @e, $a if $Nasm::X86::{$a} =~ m(\*Nasm::X86::);
   }
  say STDERR q/@EXPORT_OK    = qw(/.join(' ', @e).q/);/;
  exit;
 }

use Exporter qw(import);

use vars qw(@ISA @EXPORT @EXPORT_OK %EXPORT_TAGS);

@ISA          = qw(Exporter);
@EXPORT       = qw();
@EXPORT_OK    = qw(Add All8Structure AllocateAll8OnStack AllocateMemory And AndBlock Andn ArenaFreeChain Assemble Bswap Bt Btc Btr Bts Bzhi Call CallC CheckGeneralPurposeRegister CheckMaskRegister CheckNumberedGeneralPurposeRegister ChooseRegisters ClassifyInRange ClassifyRange ClassifyWithInRange ClassifyWithInRangeAndSaveOffset ClassifyWithInRangeAndSaveWordOffset ClearMemory ClearRegisters ClearZF CloseFile Cmova Cmovae Cmovb Cmovbe Cmovc Cmove Cmovg Cmovge Cmovl Cmovle Cmovna Cmovnae Cmovnb Cmp Comment CommentWithTraceBack ConvertUtf8ToUtf32 CopyMemory Cpuid CreateArena CreateShortString Cstrlen DComment Db Dbwdq Dd Dec DescribeArena DescribeArray DescribeQuarks DescribeString DescribeTree Dq Ds Dw Ef Else Enter Exit Extern Fail For ForEver ForIn Fork FreeMemory G GetNextUtf8CharAsUtf32 GetPPid GetPid GetPidInHex GetUid Hash ISA Idiv If IfC IfEq IfGe IfGt IfLe IfLt IfNc IfNe IfNz IfZ Imul Inc InsertOneIntoRegisterAtPoint InsertZeroIntoRegisterAtPoint Ja Jae Jb Jbe Jc Jcxz Je Jecxz Jg Jge Jl Jle Jmp Jna Jnae Jnb Jnbe Jnc Jne Jng Jnge Jnl Jnle Jno Jnp Jns Jnz Jo Jp Jpe Jpo Jrcxz Js Jz K Kaddb Kaddd Kaddq Kaddw Kandb Kandd Kandnb Kandnd Kandnq Kandnw Kandq Kandw Kmovb Kmovd Kmovq Kmovw Knotb Knotd Knotq Knotw Korb Kord Korq Kortestb Kortestd Kortestq Kortestw Korw Kshiftlb Kshiftld Kshiftlq Kshiftlw Kshiftrb Kshiftrd Kshiftrq Kshiftrw Ktestb Ktestd Ktestq Ktestw Kunpckb Kunpckd Kunpckq Kunpckw Kxnorb Kxnord Kxnorq Kxnorw Kxorb Kxord Kxorq Kxorw Label Lahf Lea Leave Link LoadBitsIntoMaskRegister LoadConstantIntoMaskRegister LoadRegFromMm LoadZmm LocalData LocateIntelEmulator Loop Lzcnt Macro MaskMemory22 MaskMemoryInRange4_22 Mov Movdqa Mulpd Neg Not OnSegv OpenRead OpenWrite Optimize Or OrBlock Pass PeekR Pextrb Pextrd Pextrq Pextrw Pi32 Pi64 Pinsrb Pinsrd Pinsrq Pinsrw Pop PopEax PopMask PopR PopRR PopZmm Popcnt Popfq PrintErrMemory PrintErrMemoryInHex PrintErrMemoryInHexNL PrintErrMemoryNL PrintErrNL PrintErrRaxInHex PrintErrRegisterInHex PrintErrSpace PrintErrString PrintErrStringNL PrintErrTraceBack PrintErrUtf32 PrintErrUtf8Char PrintErrZF PrintMemory PrintMemoryInHex PrintMemoryNL PrintNL PrintOneRegisterInHex PrintOutMemory PrintOutMemoryInHex PrintOutMemoryInHexNL PrintOutMemoryNL PrintOutNL PrintOutRaxInHex PrintOutRaxInReverseInHex PrintOutRegisterInHex PrintOutRegistersInHex PrintOutRflagsInHex PrintOutRipInHex PrintOutSpace PrintOutString PrintOutStringNL PrintOutTraceBack PrintOutUtf32 PrintOutUtf8Char PrintOutZF PrintRaxInHex PrintRegisterInHex PrintSpace PrintString PrintStringNL PrintTraceBack PrintUtf32 PrintUtf8Char Pslldq Psrldq Push PushMask PushR PushRAssert PushRR PushZmm Pushfq R RComment Rb Rbwdq Rd Rdtsc ReadFile ReadTimeStampCounter RegisterSize RegistersAvailable RegistersFree ReorderSyscallRegisters RestoreFirstFour RestoreFirstFourExceptRax RestoreFirstFourExceptRaxAndRdi RestoreFirstSeven RestoreFirstSevenExceptRax RestoreFirstSevenExceptRaxAndRdi Ret Rq Rs Rutf8 Rw SaveFirstFour SaveFirstSeven SaveRegIntoMm SetLabel SetMaskRegister SetZF Seta Setae Setb Setbe Setc Sete Setg Setge Setl Setle Setna Setnae Setnb Setnbe Setnc Setne Setng Setnge Setnl Setno Setnp Setns Setnz Seto Setp Setpe Setpo Sets Setz Shl Shr Start StatSize StringLength Structure Sub Subroutine SubroutineStartStack Syscall Test Then Tzcnt UnReorderSyscallRegisters V VERSION Vaddd Vaddpd Variable Vcvtudq2pd Vcvtudq2ps Vcvtuqq2pd Vdpps Vgetmantps Vmovd Vmovdqa32 Vmovdqa64 Vmovdqu Vmovdqu32 Vmovdqu64 Vmovdqu8 Vmovq Vmulpd Vpandb Vpandd Vpandnb Vpandnd Vpandnq Vpandnw Vpandq Vpandw Vpbroadcastb Vpbroadcastd Vpbroadcastq Vpbroadcastw Vpcmpeqb Vpcmpeqd Vpcmpeqq Vpcmpeqw Vpcmpub Vpcmpud Vpcmpuq Vpcmpuw Vpcompressd Vpcompressq Vpexpandd Vpexpandq Vpextrb Vpextrd Vpextrq Vpextrw Vpinsrb Vpinsrd Vpinsrq Vpinsrw Vpmullb Vpmulld Vpmullq Vpmullw Vporb Vpord Vporq Vporvpcmpeqb Vporvpcmpeqd Vporvpcmpeqq Vporvpcmpeqw Vporw Vprolq Vpsubb Vpsubd Vpsubq Vpsubw Vptestb Vptestd Vptestq Vptestw Vpxorb Vpxord Vpxorq Vpxorw Vsqrtpd WaitPid Xchg Xor ah al ax bh bl bp bpl bx ch cl cs cx dh di dil dl ds dx eax ebp ebx ecx edi edx es esi esp fs gs k0 k1 k2 k3 k4 k5 k6 k7 mm0 mm1 mm2 mm3 mm4 mm5 mm6 mm7 r10 r10b r10d r10l r10w r11 r11b r11d r11l r11w r12 r12b r12d r12l r12w r13 r13b r13d r13l r13w r14 r14b r14d r14l r14w r15 r15b r15d r15l r15w r8 r8b r8d r8l r8w r9 r9b r9d r9l r9w rax rbp rbx rcx rdi rdx rflags rip rsi rsp si sil sp spl ss st0 st1 st2 st3 st4 st5 st6 st7 xmm0 xmm1 xmm10 xmm11 xmm12 xmm13 xmm14 xmm15 xmm16 xmm17 xmm18 xmm19 xmm2 xmm20 xmm21 xmm22 xmm23 xmm24 xmm25 xmm26 xmm27 xmm28 xmm29 xmm3 xmm30 xmm31 xmm4 xmm5 xmm6 xmm7 xmm8 xmm9 ymm0 ymm1 ymm10 ymm11 ymm12 ymm13 ymm14 ymm15 ymm16 ymm17 ymm18 ymm19 ymm2 ymm20 ymm21 ymm22 ymm23 ymm24 ymm25 ymm26 ymm27 ymm28 ymm29 ymm3 ymm30 ymm31 ymm4 ymm5 ymm6 ymm7 ymm8 ymm9 zmm0 zmm1 zmm10 zmm11 zmm12 zmm13 zmm14 zmm15 zmm16 zmm17 zmm18 zmm19 zmm2 zmm20 zmm21 zmm22 zmm23 zmm24 zmm25 zmm26 zmm27 zmm28 zmm29 zmm3 zmm30 zmm31 zmm4 zmm5 zmm6 zmm7 zmm8 zmm9);
%EXPORT_TAGS  = (all => [@EXPORT, @EXPORT_OK]);

# podDocumentation
=pod

=encoding utf-8

=head1 Name

Nasm::X86 - Generate X86 assembler code using Perl as a macro pre-processor.

=head1 Synopsis

Write and execute B<x64> B<Avx512> assembler code from L<perl> using L<perl> as a
macro assembler.  The generated code can be run under the Intel emulator to
obtain execution trace and instruction counts.

=head2 Examples

=head3 Avx512 instructions

Use B<Avx512> instructions to perform B<64> comparisons in parallel.

  my $P = "2F";                                                                 # Value to test for
  my $l = Rb 0;  Rb $_ for 1..RegisterSize zmm0;                                # 0..63
  Vmovdqu8 zmm0, "[$l]";                                                        # Load data to test
  PrintOutRegisterInHex zmm0;

  Mov rax, "0x$P";                                                              # Broadcast the value to be tested
  Vpbroadcastb zmm1, rax;
  PrintOutRegisterInHex zmm1;

  for my $c(0..7)                                                               # Each possible test
   {my $m = "k$c";
    Vpcmpub $m, zmm1, zmm0, $c;
    PrintOutRegisterInHex $m;
   }

  Kmovq rax, k0;                                                                # Count the number of trailing zeros in k0
  Tzcnt rax, rax;
  PrintOutRegisterInHex rax;

  is_deeply Assemble, <<END;                                                    # Assemble and test
  zmm0: 3F3E 3D3C 3B3A 3938   3736 3534 3332 3130   2F2E 2D2C 2B2A 2928   2726 2524 2322 2120   1F1E 1D1C 1B1A 1918   1716 1514 1312 1110   0F0E 0D0C 0B0A 0908   0706 0504 0302 0100
  zmm1: 2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F
    k0: 0000 8000 0000 0000
    k1: FFFF 0000 0000 0000
    k2: FFFF 8000 0000 0000
    k3: 0000 0000 0000 0000
    k4: FFFF 7FFF FFFF FFFF
    k5: 0000 FFFF FFFF FFFF
    k6: 0000 7FFF FFFF FFFF
    k7: FFFF FFFF FFFF FFFF
   rax: 0000 0000 0000 002F
END

With the print statements removed, the Intel Emulator indicates that 26
instructions were executed:

  CALL_NEAR                                                              1
  ENTER                                                                  2
  JMP                                                                    1
  KMOVQ                                                                  1
  MOV                                                                    5
  POP                                                                    1
  PUSH                                                                   3
  SYSCALL                                                                1
  TZCNT                                                                  1
  VMOVDQU8                                                               1
  VPBROADCASTB                                                           1
  VPCMPUB                                                                8

  *total                                                                26

=head3 Create a library

Create a library with three subroutines in it and save the library to a file:

  my $library = CreateLibrary          # Library definition
   (subroutines =>                     # Sub routines in libray
     {inc => sub {Inc rax},            # Increment rax
      dup => sub {Shl rax, 1},         # Double rax
      put => sub {PrintOutRaxInDecNL}, # Print rax in decimal
     },
    file => q(library),
   );

Reload the library and call its subroutines from a separate assembly:

  my ($dup, $inc, $put) = $library->load; # Load the library into variables

  Mov rax, 1; &$put;
  &$inc;      &$put;                      # Use the subroutines from the library
  &$dup;      &$put;
  &$dup;      &$put;
  &$inc;      &$put;

  ok Assemble eq => <<END;
1
2
4
8
9
END

=head3 Read and write characters

Read a line of characters from stdin and print them out on stdout:

  my $e = q(readChar);

  ForEver
   {my ($start, $end) = @_;
    ReadChar;
    Cmp rax, 0xa;
    Jle $end;
    PrintOutRaxAsChar;
    PrintOutRaxAsChar;
   };
  PrintOutNL;

  Assemble keep => $e;

  is_deeply qx(echo "ABCDCBA" | ./$e), <<END;
AABBCCDDCCBBAA
END

=head3 Write unicode characters

Generate and write some unicode utf8 characters:

  V( loop => 16)->for(sub
   {my ($index, $start, $next, $end) = @_;
    $index->setReg(rax);
    Add rax, 0xb0;   Shl rax, 16;
    Mov  ax, 0x9d9d; Shl rax, 8;
    Mov  al, 0xf0;
    PrintOutRaxAsText;
   });
  PrintOutNL;

  ok Assemble(debug => 0, trace => 0, eq => <<END);
𝝰𝝱𝝲𝝳𝝴𝝵𝝶𝝷𝝸𝝹𝝺𝝻𝝼𝝽𝝾𝝿
END

=head3 Read a file

Read this file:

  ReadFile(V(file, Rs($0)), (my $s = V(size)), my $a = V(address));          # Read file
  $a->setReg(rax);                                                              # Address of file in memory
  $s->setReg(rdi);                                                              # Length  of file in memory
  PrintOutMemory;                                                               # Print contents of memory to stdout

  my $r = Assemble(1 => (my $f = temporaryFile));                               # Assemble and execute
  ok fileMd5Sum($f) eq fileMd5Sum($0);                                          # Output contains this file


=head3 Call functions in Libc

Call B<C> functions by naming them as external and including their library:

  my $format = Rs "Hello %s\n";
  my $data   = Rs "World";

  Extern qw(printf exit malloc strcpy); Link 'c';

  CallC 'malloc', length($format)+1;
  Mov r15, rax;
  CallC 'strcpy', r15, $format;
  CallC 'printf', r15, $data;
  CallC 'exit', 0;

  ok Assemble eq => <<END;
Hello World
END

=head3 Print numbers in decimal from assembly code using nasm and perl:

Debug your programs with powerful print statements:

  Mov rax, 0x2a;
  PrintOutRaxInDecNL;

  ok Assemble eq => <<END;
42
END

=head3 Process management

Start a child process and wait for it, printing out the process identifiers of
each process involved:

   Fork;                                     # Fork

   Test rax,rax;
   IfNz                                      # Parent
   Then
    {Mov rbx, rax;
     WaitPid;
     GetPid;                                 # Pid of parent as seen in parent
     Mov rcx,rax;
     PrintOutRegisterInHex rax, rbx, rcx;
    },
   Else                                      # Child
    {Mov r8,rax;
     GetPid;                                 # Child pid as seen in child
     Mov r9,rax;
     GetPPid;                                # Parent pid as seen in child
     Mov r10,rax;
     PrintOutRegisterInHex r8, r9, r10;
    };

   my $r = Assemble;

 #    r8: 0000 0000 0000 0000   #1 Return from fork as seen by child
 #    r9: 0000 0000 0003 0C63   #2 Pid of child
 #   r10: 0000 0000 0003 0C60   #3 Pid of parent from child
 #   rax: 0000 0000 0003 0C63   #4 Return from fork as seen by parent
 #   rbx: 0000 0000 0003 0C63   #5 Wait for child pid result
 #   rcx: 0000 0000 0003 0C60   #6 Pid of parent

=head3 Dynamic arena

Arenas are resizeable, relocatable blocks of memory that hold other dynamic
data structures. Arenas can be transferred between processes and relocated as
needed as all addressing is relative to the start of the block of memory
containing each arena.

Create two dynamic arenas, add some content to them, write each arena to
stdout:

  my $a = CreateArena;

  my $b = CreateArena;
  $a->q('aa');
  $b->q('bb');
  $a->q('AA');
  $b->q('BB');
  $a->q('aa');
  $b->q('bb');

  $a->out;
  $b->out;

  PrintOutNL;

  is_deeply Assemble, <<END;
aaAAaabbBBbb
END

=head4 Dynamic string held in an arena

Create a dynamic string within an arena and add some content to it:

  my $s = Rb(0..255);
  my $A = CreateArena;
  my $S = $A->CreateString;

  $S->append(V(source, $s), K(size, 256));
  $S->len->outNL;
  $S->clear;

  $S->append(V(source, $s), K(size,  16));
  $S->len->outNL;
  $S->dump;

  ok Assemble(debug => 0, eq => <<END);
size: 0000 0000 0000 0100
size: 0000 0000 0000 0010
string Dump
Offset: 0000 0000 0000 0018   Length: 0000 0000 0000 0010
 zmm31: 0000 0018 0000 0018   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 000F   0E0D 0C0B 0A09 0807   0605 0403 0201 0010

END

=head4 Dynamic array held in an arena

Create a dynamic array within an arena, push some content on to it then pop it
off again:

  my $N = 15;
  my $A = CreateArena;
  my $a = $A->CreateArray;

  $a->push(V(element, $_)) for 1..$N;

  K(loop, $N)->for(sub
   {my ($start, $end, $next) = @_;
    my $l = $a->size;
    If $l == 0, Then {Jmp $end};
    $a->pop(my $e = V(element));
    $e->outNL;
   });

  ok Assemble(debug => 0, eq => <<END);
element: 0000 0000 0000 000F
element: 0000 0000 0000 000E
element: 0000 0000 0000 000D
element: 0000 0000 0000 000C
element: 0000 0000 0000 000B
element: 0000 0000 0000 000A
element: 0000 0000 0000 0009
element: 0000 0000 0000 0008
element: 0000 0000 0000 0007
element: 0000 0000 0000 0006
element: 0000 0000 0000 0005
element: 0000 0000 0000 0004
element: 0000 0000 0000 0003
element: 0000 0000 0000 0002
element: 0000 0000 0000 0001
END

=head4 Create a multi way tree in an arena using SIMD instructions

Create a multiway tree as in L<Tree::Multi> using B<Avx512> instructions and
iterate through it:

  my $N = 12;
  my $b = CreateArena;                   # Resizable memory block
  my $t = $b->CreateTree;        # Multi way tree in memory block

  K(count, $N)->for(sub                      # Add some entries to the tree
   {my ($index, $start, $next, $end) = @_;
    my $k = $index + 1;
    $t->insert($k,      $k + 0x100);
    $t->insert($k + $N, $k + 0x200);
   });

  $t->by(sub                                  # Iterate through the tree
   {my ($iter, $end) = @_;
    $iter->key ->out('key: ');
    $iter->data->out(' data: ');
    $iter->tree->depth($iter->node, my $D = V(depth));

    $t->find($iter->key);
    $t->found->out(' found: '); $t->data->out(' data: '); $D->outNL(' depth: ');
   });

  $t->find(K(key, 0xffff));  $t->found->outNL('Found: ');  # Find some entries
  $t->find(K(key, 0xd));     $t->found->outNL('Found: ');

  If ($t->found,
  Then
   {$t->data->outNL("Data : ");
   });

  ok Assemble(debug => 0, eq => <<END);
key: 0000 0000 0000 0001 data: 0000 0000 0000 0101 found: 0000 0000 0000 0001 data: 0000 0000 0000 0101 depth: 0000 0000 0000 0002
key: 0000 0000 0000 0002 data: 0000 0000 0000 0102 found: 0000 0000 0000 0001 data: 0000 0000 0000 0102 depth: 0000 0000 0000 0002
key: 0000 0000 0000 0003 data: 0000 0000 0000 0103 found: 0000 0000 0000 0001 data: 0000 0000 0000 0103 depth: 0000 0000 0000 0002
key: 0000 0000 0000 0004 data: 0000 0000 0000 0104 found: 0000 0000 0000 0001 data: 0000 0000 0000 0104 depth: 0000 0000 0000 0002
key: 0000 0000 0000 0005 data: 0000 0000 0000 0105 found: 0000 0000 0000 0001 data: 0000 0000 0000 0105 depth: 0000 0000 0000 0002
key: 0000 0000 0000 0006 data: 0000 0000 0000 0106 found: 0000 0000 0000 0001 data: 0000 0000 0000 0106 depth: 0000 0000 0000 0002
key: 0000 0000 0000 0007 data: 0000 0000 0000 0107 found: 0000 0000 0000 0001 data: 0000 0000 0000 0107 depth: 0000 0000 0000 0002
key: 0000 0000 0000 0008 data: 0000 0000 0000 0108 found: 0000 0000 0000 0001 data: 0000 0000 0000 0108 depth: 0000 0000 0000 0002
key: 0000 0000 0000 0009 data: 0000 0000 0000 0109 found: 0000 0000 0000 0001 data: 0000 0000 0000 0109 depth: 0000 0000 0000 0002
key: 0000 0000 0000 000A data: 0000 0000 0000 010A found: 0000 0000 0000 0001 data: 0000 0000 0000 010A depth: 0000 0000 0000 0002
key: 0000 0000 0000 000B data: 0000 0000 0000 010B found: 0000 0000 0000 0001 data: 0000 0000 0000 010B depth: 0000 0000 0000 0002
key: 0000 0000 0000 000C data: 0000 0000 0000 010C found: 0000 0000 0000 0001 data: 0000 0000 0000 010C depth: 0000 0000 0000 0002
key: 0000 0000 0000 000D data: 0000 0000 0000 0201 found: 0000 0000 0000 0001 data: 0000 0000 0000 0201 depth: 0000 0000 0000 0001
key: 0000 0000 0000 000E data: 0000 0000 0000 0202 found: 0000 0000 0000 0001 data: 0000 0000 0000 0202 depth: 0000 0000 0000 0002
key: 0000 0000 0000 000F data: 0000 0000 0000 0203 found: 0000 0000 0000 0001 data: 0000 0000 0000 0203 depth: 0000 0000 0000 0002
key: 0000 0000 0000 0010 data: 0000 0000 0000 0204 found: 0000 0000 0000 0001 data: 0000 0000 0000 0204 depth: 0000 0000 0000 0002
key: 0000 0000 0000 0011 data: 0000 0000 0000 0205 found: 0000 0000 0000 0001 data: 0000 0000 0000 0205 depth: 0000 0000 0000 0002
key: 0000 0000 0000 0012 data: 0000 0000 0000 0206 found: 0000 0000 0000 0001 data: 0000 0000 0000 0206 depth: 0000 0000 0000 0002
key: 0000 0000 0000 0013 data: 0000 0000 0000 0207 found: 0000 0000 0000 0001 data: 0000 0000 0000 0207 depth: 0000 0000 0000 0002
key: 0000 0000 0000 0014 data: 0000 0000 0000 0208 found: 0000 0000 0000 0001 data: 0000 0000 0000 0208 depth: 0000 0000 0000 0002
key: 0000 0000 0000 0015 data: 0000 0000 0000 0209 found: 0000 0000 0000 0001 data: 0000 0000 0000 0209 depth: 0000 0000 0000 0002
key: 0000 0000 0000 0016 data: 0000 0000 0000 020A found: 0000 0000 0000 0001 data: 0000 0000 0000 020A depth: 0000 0000 0000 0002
key: 0000 0000 0000 0017 data: 0000 0000 0000 020B found: 0000 0000 0000 0001 data: 0000 0000 0000 020B depth: 0000 0000 0000 0002
key: 0000 0000 0000 0018 data: 0000 0000 0000 020C found: 0000 0000 0000 0001 data: 0000 0000 0000 020C depth: 0000 0000 0000 0002
Found: 0000 0000 0000 0000
Found: 0000 0000 0000 0001
Data : 0000 0000 0000 0201
END

=head4 Quarks held in an arena

Quarks replace unique strings with unique numbers and in doing so unite all
that is best and brightest in dynamic trees, arrays, strings and short
strings, all written in X86 assembler, all generated by Perl:

  my $N = 5;
  my $a = CreateArena;                      # Arena containing quarks
  my $Q = $a->CreateQuarks;                 # Quarks

  my $s = CreateShortString(0);             # Short string used to load and unload quarks
  my $d = Rb(1..63);

  for my $i(1..$N)                          # Load a set of quarks
   {my $j = $i - 1;
    $s->load(K(address, $d), K(size, 4+$i));
    my $q = $Q->quarkFromShortString($s);
    $q->outNL("New quark    $j: ");         # New quark, new number
   }
  PrintOutNL;

  for my $i(reverse 1..$N)                  # Reload a set of quarks
   {my $j = $i - 1;
    $s->load(K(address, $d), K(size, 4+$i));
    my $q = $Q->quarkFromShortString($s);
    $q->outNL("Old quark    $j: ");         # Old quark, old number
   }
  PrintOutNL;

  for my $i(1..$N)                          # Dump quarks
   {my $j = $i - 1;
     $s->clear;
    $Q->shortStringFromQuark(K(quark, $j), $s);
    PrintOutString "Quark string $j: ";
    PrintOutRegisterInHex xmm0;
   }

  ok Assemble(debug => 0, trace => 0, eq => <<END);
  New quark    0: 0000 0000 0000 0000
  New quark    1: 0000 0000 0000 0001
  New quark    2: 0000 0000 0000 0002
  New quark    3: 0000 0000 0000 0003
  New quark    4: 0000 0000 0000 0004

  Old quark    4: 0000 0000 0000 0004
  Old quark    3: 0000 0000 0000 0003
  Old quark    2: 0000 0000 0000 0002
  Old quark    1: 0000 0000 0000 0001
  Old quark    0: 0000 0000 0000 0000

  Quark string 0:   xmm0: 0000 0000 0000 0000   0000 0504 0302 0105
  Quark string 1:   xmm0: 0000 0000 0000 0000   0006 0504 0302 0106
  Quark string 2:   xmm0: 0000 0000 0000 0000   0706 0504 0302 0107
  Quark string 3:   xmm0: 0000 0000 0000 0008   0706 0504 0302 0108
  Quark string 4:   xmm0: 0000 0000 0000 0908   0706 0504 0302 0109
  END

=head3 Recursion with stack and parameter tracing

Call a subroutine recursively and get a trace back showing the procedure calls
and parameters passed to each call. Parameters are passed by reference not
value.

  my $d = V depth => 3;                                                         # Create a variable on the stack

  my $s = Subroutine
   {my ($p, $s) = @_;                                                           # Parameters, subroutine descriptor
    PrintOutTraceBack;

    my $d = $$p{depth}->copy($$p{depth} - 1);                                   # Modify the variable referenced by the parameter

    If ($d > 0,
    Then
     {$s->call($d);                                                             # Recurse
     });

    PrintOutTraceBack;
   } [qw(depth)], name => 'ref';

  $s->call($d);                                                                 # Call the subroutine

  ok Assemble(debug => 0, eq => <<END);

  Subroutine trace back, depth:  1
  0000 0000 0000 0003    ref


  Subroutine trace back, depth:  2
  0000 0000 0000 0002    ref
  0000 0000 0000 0002    ref


  Subroutine trace back, depth:  3
  0000 0000 0000 0001    ref
  0000 0000 0000 0001    ref
  0000 0000 0000 0001    ref


  Subroutine trace back, depth:  3
  0000 0000 0000 0000    ref
  0000 0000 0000 0000    ref
  0000 0000 0000 0000    ref


  Subroutine trace back, depth:  2
  0000 0000 0000 0000    ref
  0000 0000 0000 0000    ref


  Subroutine trace back, depth:  1
  0000 0000 0000 0000    ref

  END

=head2 Installation

The Intel Software Development Emulator will be required if you do not have a
computer with the avx512 instruction set and wish to execute code containing
these instructions. For details see:

L<https://software.intel.com/content/dam/develop/external/us/en/documents/downloads/sde-external-8.63.0-2021-01-18-lin.tar.bz2>


The Networkwide Assembler is required to assemble the code produced  For full
details see:

L<https://github.com/philiprbrenan/NasmX86/blob/main/.github/workflows/main.yml>

=head2 Execution Options

The L</Assemble(%)> function takes the keywords described below to
control assembly and execution of the assembled code:

L</Assemble(%)> runs the generated program after a successful assembly
unless the B<keep> option is specified. The output on B<stdout> is captured in
file B<zzzOut.txt> and that on B<stderr> is captured in file B<zzzErr.txt>.

The amount of output displayed is controlled by the B<debug> keyword.

The B<eq> keyword can be used to test that the output by the run.

The output produced by the program execution is returned as the result of the
L</Assemble(%)> function.

=head3 Keep

To produce a named executable without running it, specify:

 keep=>"executable file name"

=head3 Library

To produce a shared library file:

 library=>"library.so"

=head3 Emulator

To run the executable produced by L</Assemble(%)> without the Intel
emulator, which is used by default if it is present, specify:

 emulator=>0

=head3 eq

The B<eq> keyword supplies the expected output from the execution of the
assembled program.  If the expected output is not obtained on B<stdout> then we
confess and stop further testing. Output on B<stderr> is ignored for test
purposes.

The point at which the wanted output diverges from the output actually got is
displayed to assist debugging as in:

  Comparing wanted with got failed at line: 4, character: 22
  Start:
      k7: 0000 0000 0000 0001
      k6: 0000 0000 0000 0003
      k5: 0000 0000 0000 0007
      k4: 0000 0000 000
  Want ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
  1 0002
      k3: 0000 0000 0000 0006
      k2: 0000 0000 0000 000E
      k1: 0000 0000
  Got  ________________________________________________________________________________
  0 0002
      k3: 0000 0000 0000 0006
      k2: 0000 0000 0000 000E
      k1: 0000 0000


=head3 Debug

The debug keyword controls how much output is printed after each assemble and
run.

  debug => 0

produces no output unless the B<eq> keyword was specified and the actual output
fails to match the expected output. If such a test fails we L<Carp::confess>.

  debug => 1

shows all the output produces and conducts the test specified by the B<eq> is
present. If the test fails we L<Carp::confess>.

  debug => 2

shows all the output produces and conducts the test specified by the B<eq> is
present. If the test fails we continue rather than calling L<Carp::confess>.

=head1 Description

=cut



# Tests and documentation

sub test
 {my $p = __PACKAGE__;
  binmode($_, ":utf8") for *STDOUT, *STDERR;
  return if eval "eof(${p}::DATA)";
  my $s = eval "join('', <${p}::DATA>)";
  $@ and die $@;
  eval $s;
  $@ and die $@;
  1
 }

test unless caller;

1;
# podDocumentation
__DATA__
use Time::HiRes qw(time);
use Test::Most;

bail_on_fail;

my $localTest = ((caller(1))[0]//'Nasm::X86') eq "Nasm::X86";                   # Local testing mode

Test::More->builder->output("/dev/null") if $localTest;                         # Reduce number of confirmation messages during testing

if ($^O =~ m(bsd|linux|cygwin)i)                                                # Supported systems
 {if (confirmHasCommandLineCommand(q(nasm)) and LocateIntelEmulator)            # Network assembler and Intel Software Development emulator
   {#plan tests => 158;
   }
  else
   {plan skip_all => qq(Nasm or Intel 64 emulator not available);
   }
 }
else
 {plan skip_all => qq(Not supported on: $^O);
 }

my $start = time;                                                               # Tests

eval {goto latest} if !caller(0) and -e "/home/phil";                           # Go to latest test if specified

if (1) {                                                                        #TPrintOutStringNL #TPrintErrStringNL #TAssemble
  PrintOutStringNL "Hello World";
  PrintOutStringNL "Hello\nWorld";
  PrintErrStringNL "Hello World";

  ok Assemble(debug => 0, eq => <<END);
Hello World
Hello
World
END
 }

#latest:;
if (1) {                                                                        #TMov #TComment #TRs #TPrintOutMemory #TExit
  Comment "Print a string from memory";
  my $s = "Hello World";
  Mov rax, Rs($s);
  Mov rdi, length $s;
  PrintOutMemory;
  Exit(0);

  ok Assemble =~ m(Hello World);
 }

#latest:;
if (1) {                                                                        #TPrintOutMemoryNL #TStringLength
  my $s = Rs("Hello World\n\nHello Skye");
  my $l = StringLength(my $t = V string => $s);
  $t->setReg(rax);
  $l->setReg(rdi);
  PrintOutMemoryNL;

  ok Assemble(debug => 0, eq => <<END);
Hello World

Hello Skye
END
 }

#latest:;
if (1) {                                                                        #TPrintOutRaxInHex #TPrintOutNL #TPrintOutString
  my $q = Rs('abababab');
  Mov(rax, "[$q]");
  PrintOutString "rax: ";
  PrintOutRaxInHex;
  PrintOutNL;
  Xor rax, rax;
  PrintOutString "rax: ";
  PrintOutRaxInHex;
  PrintOutNL;

  ok Assemble =~ m(rax: 6261 6261 6261 6261.*rax: 0000 0000 0000 0000)s;
 }

#latest:;
if (1) {                                                                        #TPrintOutRegistersInHex #TRs
  my $q = Rs('abababab');
  Mov(rax, 1);
  Mov(rbx, 2);
  Mov(rcx, 3);
  Mov(rdx, 4);
  Mov(r8,  5);
  Lea r9,  "[rax+rbx]";
  PrintOutRegistersInHex;

  my $r = Assemble;
  ok $r =~ m( r8: 0000 0000 0000 0005.* r9: 0000 0000 0000 0003.*rax: 0000 0000 0000 0001)s;
  ok $r =~ m(rbx: 0000 0000 0000 0002.*rcx: 0000 0000 0000 0003.*rdx: 0000 0000 0000 0004)s;
 }

#latest:;
if (1) {                                                                        #TDs TRs
  my $q = Rs('a'..'z');
  Mov rax, Ds('0'x64);                                                          # Output area
  Vmovdqu32(xmm0, "[$q]");                                                      # Load
  Vprolq   (xmm0,   xmm0, 32);                                                  # Rotate double words in quad words
  Vmovdqu32("[rax]", xmm0);                                                     # Save
  Mov rdi, 16;
  PrintOutMemory;

  ok Assemble =~ m(efghabcdmnopijkl)s;
 }

#latest:;
if (1) {
  my $q = Rs(('a'..'p')x2);
  Mov rax, Ds('0'x64);
  Vmovdqu32(ymm0, "[$q]");
  Vprolq   (ymm0,   ymm0, 32);
  Vmovdqu32("[rax]", ymm0);
  Mov rdi, 32;
  PrintOutMemory;

  ok Assemble =~ m(efghabcdmnopijklefghabcdmnopijkl)s;
 }

#latest:;
if (1) {
  my $q = Rs my $s = join '', ('a'..'p')x4;                                     # Sample string
  Mov rax, Ds('0'x128);

  Vmovdqu64 zmm0, "[$q]";                                                       # Load zmm0 with sample string
  Vprolq    zmm1, zmm0, 32;                                                     # Rotate left 32 bits in lanes
  Vmovdqu64 "[rax]", zmm1;                                                      # Save results

  Mov rdi, length $s;                                                           # Print results
  PrintOutMemoryNL;

  is_deeply "$s\n", <<END;                                                      # Initial string
abcdefghijklmnopabcdefghijklmnopabcdefghijklmnopabcdefghijklmnop
END

  ok Assemble(debug => 0, eq => <<END);                                         # Assemble and run
efghabcdmnopijklefghabcdmnopijklefghabcdmnopijklefghabcdmnopijkl
END
 }

#latest:;
if (1) {                                                                        #TPrintOutRegisterInHex
  my $q = Rs(('a'..'p')x4);
  Mov r8,"[$q]";
  PrintOutRegisterInHex r8;

  ok Assemble(debug => 0, eq => <<END);
    r8: 6867 6665 6463 6261
END
 }

#latest:;
if (1) {
  my $q = Rs('a'..'p');
  Vmovdqu8 xmm0, "[$q]";
  PrintOutRegisterInHex xmm0;

  ok Assemble =~ m(xmm0: 706F 6E6D 6C6B 6A69   6867 6665 6463 6261)s;
 }

#latest:
if (1) {
  my $q = Rs('a'..'p', 'A'..'P', );
  Vmovdqu8 ymm0, "[$q]";
  PrintOutRegisterInHex ymm0;

  ok Assemble =~ m(ymm0: 504F 4E4D 4C4B 4A49   4847 4645 4443 4241   706F 6E6D 6C6B 6A69   6867 6665 6463 6261)s;
 }

#latest:
if (1) {
  my $q = Rs(('a'..'p', 'A'..'P') x 2);
  Vmovdqu8 zmm0, "[$q]";
  PrintOutRegisterInHex zmm0;

  ok Assemble =~ m(zmm0: 504F 4E4D 4C4B 4A49   4847 4645 4443 4241   706F 6E6D 6C6B 6A69   6867 6665 6463 6261   504F 4E4D 4C4B 4A49   4847 4645 4443 4241   706F 6E6D 6C6B 6A69   6867 6665 6463 6261)s;
 }

#latest:
if (1) {                                                                        #TNasm::X86::Variable::copyZF #TNasm::X86::Variable::copyZFInverted
  Mov r15, 1;
  my $z = V(zf);
  Cmp r15, 1; $z->copyZF;         $z->outNL;
  Cmp r15, 2; $z->copyZF;         $z->outNL;
  Cmp r15, 1; $z->copyZFInverted; $z->outNL;
  Cmp r15, 2; $z->copyZFInverted; $z->outNL;

  ok Assemble(debug => 0, eq => <<END);
zf: 0000 0000 0000 0001
zf: 0000 0000 0000 0000
zf: 0000 0000 0000 0000
zf: 0000 0000 0000 0001
END
 }

#latest:
if (1) {                                                                        #TPrintOutRightInHexNL
  my $N = K number => 0x12345678;

  for my $i(reverse 1..16)
   {PrintOutRightInHexNL($N, K width => $i);
   }
  ok Assemble(debug => 0, trace => 0, eq => <<END);
        12345678
       12345678
      12345678
     12345678
    12345678
   12345678
  12345678
 12345678
12345678
2345678
345678
45678
5678
678
78
8
END
 }

#latest:
if (1) {                                                                        #TPrintOutRightInBinNL
  K(count => 64)->for(sub
   {my ($index, $start, $next, $end) = @_;
    PrintOutRightInBinNL K(number => 0x99), K(max => 64) - $index;
   });
  ok Assemble(debug => 0, eq => <<END);
                                                        10011001
                                                       10011001
                                                      10011001
                                                     10011001
                                                    10011001
                                                   10011001
                                                  10011001
                                                 10011001
                                                10011001
                                               10011001
                                              10011001
                                             10011001
                                            10011001
                                           10011001
                                          10011001
                                         10011001
                                        10011001
                                       10011001
                                      10011001
                                     10011001
                                    10011001
                                   10011001
                                  10011001
                                 10011001
                                10011001
                               10011001
                              10011001
                             10011001
                            10011001
                           10011001
                          10011001
                         10011001
                        10011001
                       10011001
                      10011001
                     10011001
                    10011001
                   10011001
                  10011001
                 10011001
                10011001
               10011001
              10011001
             10011001
            10011001
           10011001
          10011001
         10011001
        10011001
       10011001
      10011001
     10011001
    10011001
   10011001
  10011001
 10011001
10011001
0011001
011001
11001
1001
001
01
1
END
 }

#latest:
if (1) {                                                                        #TAllocateMemory #TNasm::X86::Variable::freeMemory
  my $N = K size => 2048;
  my $q = Rs('a'..'p');
  my $address = AllocateMemory $N;

  Vmovdqu8 xmm0, "[$q]";
  $address->setReg(rax);
  Vmovdqu8 "[rax]", xmm0;
  Mov rdi, 16;
  PrintOutMemory;
  PrintOutNL;

  FreeMemory $address, $N;

  ok Assemble(debug => 0, eq => <<END);
abcdefghijklmnop
END
 }

#latest:
if (1) {                                                                        #TReadTimeStampCounter
  for(1..10)
   {ReadTimeStampCounter;
    PrintOutRegisterInHex rax;
   }

  my @s = split /\n/, Assemble;
  my @S = sort @s;
  is_deeply \@s, \@S;
 }

#latest:
if (1) {                                                                        #TIf
  my $c = K(one,1);
  If ($c == 0,
  Then
   {PrintOutStringNL "1 == 0";
   },
  Else
   {PrintOutStringNL "1 != 0";
   });

  ok Assemble(debug => 0, eq => <<END);
1 != 0
END
 }

if (1) {                                                                        #TIfNz
  Mov rax, 0;
  Test rax,rax;
  IfNz
  Then
   {PrintOutRegisterInHex rax;
   },
  Else
   {PrintOutRegisterInHex rbx;
   };
  Mov rax, 1;
  Test rax,rax;
  IfNz
  Then
   {PrintOutRegisterInHex rcx;
   },
  Else
   {PrintOutRegisterInHex rdx;
   };

  ok Assemble =~ m(rbx.*rcx)s;
 }

if (1) {                                                                        #TFork #TGetPid #TGetPPid #TWaitPid
  Fork;                                                                         # Fork

  Test rax,rax;
  IfNz                                                                          # Parent
  Then
   {Mov rbx, rax;
    WaitPid;
    GetPid;                                                                     # Pid of parent as seen in parent
    Mov rcx,rax;
    PrintOutRegisterInHex rax, rbx, rcx;
   },
  Else                                                                          # Child
   {Mov r8,rax;
    GetPid;                                                                     # Child pid as seen in child
    Mov r9,rax;
    GetPPid;                                                                    # Parent pid as seen in child
    Mov r10,rax;
    PrintOutRegisterInHex r8, r9, r10;
   };

  my $r = Assemble;

#    r8: 0000 0000 0000 0000   #1 Return from fork as seen by child
#    r9: 0000 0000 0003 0C63   #2 Pid of child
#   r10: 0000 0000 0003 0C60   #3 Pid of parent from child
#   rax: 0000 0000 0003 0C63   #4 Return from fork as seen by parent
#   rbx: 0000 0000 0003 0C63   #5 Wait for child pid result
#   rcx: 0000 0000 0003 0C60   #6 Pid of parent

  if ($r =~ m(r8:( 0000){4}.*r9:(.*)\s{5,}r10:(.*)\s{5,}rax:(.*)\s{5,}rbx:(.*)\s{5,}rcx:(.*)\s{2,})s)
   {ok $2 eq $4;
    ok $2 eq $5;
    ok $3 eq $6;
    ok $2 gt $6;
   }
 }

if (1) {                                                                        #TGetUid
  GetUid;                                                                       # Userid
  PrintOutRegisterInHex rax;

  my $r = Assemble;
  ok $r =~ m(rax:( 0000){3});
 }

if (1) {                                                                        #TStatSize
  Mov rax, Rs($0);                                                              # File to stat
  StatSize;                                                                     # Stat the file
  PrintOutRegisterInHex rax;

  my $r = Assemble =~ s( ) ()gsr;
  if ($r =~ m(rax:([0-9a-f]{16}))is)                                            # Compare file size obtained with that from fileSize()
   {is_deeply $1, sprintf("%016X", fileSize($0));
   }
 }

if (1) {                                                                        #TOpenRead #TCloseFile #TOpenWrite
  Mov rax, Rs($0);                                                              # File to read
  OpenRead;                                                                     # Open file
  PrintOutRegisterInHex rax;
  CloseFile;                                                                    # Close file
  PrintOutRegisterInHex rax;

  Mov rax, Rs(my $f = "zzzTemporaryFile.txt");                                  # File to write
  OpenWrite;                                                                    # Open file
  CloseFile;                                                                    # Close file

  ok Assemble(debug => 0, eq => <<END);
   rax: 0000 0000 0000 0003
   rax: 0000 0000 0000 0000
END
  ok -e $f;                                                                     # Created file
  unlink $f;
 }

if (1) {                                                                        #TFor
  For
   {my ($start, $end, $next) = @_;
    Cmp rax, 3;
    Jge $end;
    PrintOutRegisterInHex rax;
   } rax, 16, 1;

  ok Assemble(debug => 0, eq => <<END);
   rax: 0000 0000 0000 0000
   rax: 0000 0000 0000 0001
   rax: 0000 0000 0000 0002
END
 }

if (1) {                                                                        #TAndBlock #TFail
  Mov rax, 1; Mov rdx, 2;
  AndBlock
   {my ($fail, $end, $start) = @_;
    Cmp rax, 1;
    Jne $fail;
    Cmp rdx, 2;
    Jne $fail;
    PrintOutStringNL "Pass";
   }
  Fail
   {my ($end, $fail, $start) = @_;
    PrintOutStringNL "Fail";
   };

  ok Assemble(debug => 0, eq => <<END);
Pass
END
 }

if (1) {                                                                        #TOrBlock #TPass
  Mov rax, 1;
  OrBlock
   {my ($pass, $end, $start) = @_;
    Cmp rax, 1;
    Je  $pass;
    Cmp rax, 2;
    Je  $pass;
    PrintOutStringNL "Fail";
   }
  Pass
   {my ($end, $pass, $start) = @_;
    PrintOutStringNL "Pass";
   };

  ok Assemble(debug => 0, eq => <<END);
Pass
END
 }

if (1) {                                                                        #TPrintOutRaxInReverseInHex #TPrintOutMemoryInHex
  Mov rax, 0x07654321;
  Shl rax, 32;
  Or  rax, 0x07654321;
  PushR rax;

  PrintOutRaxInHex;
  PrintOutNL;
  PrintOutRaxInReverseInHex;
  PrintOutNL;

  Mov rax, rsp;
  Mov rdi, 8;
  PrintOutMemoryInHex;
  PrintOutNL;
  PopR rax;

  Mov rax, 4096;
  PushR rax;
  Mov rax, rsp;
  Mov rdi, 8;
  PrintOutMemoryInHex;
  PrintOutNL;
  PopR rax;

  ok Assemble(debug => 0, eq => <<END);
0765 4321 0765 4321
2143 6507 2143 6507
2143 6507 2143 6507
0010 0000 0000 0000
END
 }

if (1) {                                                                        #TPushR #TPopR
  Mov rax, 0x11111111;
  Mov rbx, 0x22222222;
  PushR my @save = (rax, rbx);
  Mov rax, 0x33333333;
  PopR;
  PrintOutRegisterInHex rax;
  PrintOutRegisterInHex rbx;

  ok Assemble(debug => 0, eq => <<END);
   rax: 0000 0000 1111 1111
   rbx: 0000 0000 2222 2222
END
 }

#latest:;
if (1) {                                                                        #TClearMemory
  K(loop, 8+1)->for(sub
   {my ($index, $start, $next, $end) = @_;
    $index->setReg(r15);
    Push r15;
   });

  Mov rax, rsp;
  Mov rdi, 8*9;
  PrintOutMemory_InHexNL;
  ClearMemory(V(address, rax), K(size, 8*9));
  PrintOutMemory_InHexNL;

  ok Assemble(debug => 0, eq => <<END);
08__ ____ ____ ____  07__ ____ ____ ____  06__ ____ ____ ____  05__ ____ ____ ____  04__ ____ ____ ____  03__ ____ ____ ____  02__ ____ ____ ____  01__ ____ ____ ____  ____ ____ ____ ____
____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
END
 }

#latest:;
if (1) {                                                                        #TAllocateMemory #TFreeMemory #TClearMemory
  my $N = K size => 4096;                                                       # Size of the initial allocation which should be one or more pages

  my $A = AllocateMemory $N;

  ClearMemory($A, $N);

  $A->setReg(rax);
  Mov rdi, 128;
  PrintOutMemory_InHexNL;

  FreeMemory $A, $N;

  ok Assemble(debug => 0, eq => <<END);
____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
END
 }

#latest:;
if (1) {
  Mov rax, 0x44332211;
  PrintOutRegisterInHex rax;

  my $s = Subroutine2
   {PrintOutRegisterInHex rax;
    Inc rax;
    PrintOutRegisterInHex rax;
   } name => "printIncPrint";

  $s->call;

  PrintOutRegisterInHex rax;

  my $r = Assemble;
  ok $r =~ m(0000 0000 4433 2211.*2211.*2212.*0000 0000 4433 2212)s;
 }

#latest:;
if (1) {                                                                        #TReadFile #TPrintMemory
  my $file = V(file => Rs $0);
  my ($address, $size) = ReadFile $file;                                        # Read file into memory
  $address->setReg(rax);                                                        # Address of file in memory
  $size   ->setReg(rdi);                                                        # Length  of file in memory
  PrintOutMemory;                                                               # Print contents of memory to stdout

  my $r = Assemble;                                                             # Assemble and execute
  ok stringMd5Sum($r) eq fileMd5Sum($0);                                        # Output contains this file
 }

#latest:;
if (1) {                                                                        #TCreateArena #TArena::clear #TArena::outNL #TArena::copy #TArena::nl
  my $a = CreateArena;
  $a->q('aa');
  $a->outNL;
  ok Assemble(debug => 0, eq => <<END);
aa
END
 }

#latest:
if (1) {                                                                        #TArena::dump
  my $a = CreateArena;
  my $b = CreateArena;
  $a->q("aaaa");
  $a->dump("aaaaa");
  $b->q("bbbb");
  $b->dump("bbbb");

  ok Assemble(debug => 0, trace => 0, eq => <<END);
aaaaa
Arena     Size:     4096    Used:       68
0000 0000 0000 0000 | __10 ____ ____ ____  44__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | 6161 6161 ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
bbbb
Arena     Size:     4096    Used:       68
0000 0000 0000 0000 | __10 ____ ____ ____  44__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | 6262 6262 ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
END
 }

if (1) {                                                                        #TCreateArena #TArena::clear #TArena::out #TArena::copy #TArena::nl
  my $a = CreateArena;
  my $b = CreateArena;
  $a->q('aa');
  $b->q('bb');
  $a->out;
  PrintOutNL;
  $b->out;
  PrintOutNL;
  ok Assemble(debug => 0, eq => <<END);
aa
bb
END
 }

if (1) {                                                                        #TCreateArena #TArena::clear #TArena::out #TArena::copy #TArena::nl
  my $a = CreateArena;
  my $b = CreateArena;
  $a->q('aa');
  $a->q('AA');
  $a->out;
  PrintOutNL;
  ok Assemble(debug => 0, eq => <<END);
aaAA
END
 }

if (1) {                                                                        #TCreateArena #TArena::clear #TArena::out #TArena::copy #TArena::nl
  my $a = CreateArena;
  my $b = CreateArena;
  $a->q('aa');
  $b->q('bb');
  $a->q('AA');
  $b->q('BB');
  $a->q('aa');
  $b->q('bb');
  $a->out;
  $b->out;
  PrintOutNL;
  ok Assemble(debug => 0, eq => <<END);
aaAAaabbBBbb
END
 }

#latest:
if (1) {                                                                        #TCreateArena #TArena::length  #TArena::clear #TArena::out #TArena::copy #TArena::nl
  my $a = CreateArena;
  $a->q('ab');
  my $b = CreateArena;
  $b->append($a);
  $b->append($a);
  $a->append($b);
  $b->append($a);
  $a->append($b);
  $b->append($a);
  $b->append($a);
  $b->append($a);
  $b->append($a);


  $a->out;   PrintOutNL;
  $b->out;   PrintOutNL;
  my $sa = $a->length; $sa->outNL;
  my $sb = $b->length; $sb->outNL;
  $a->clear;
  my $sA = $a->length; $sA->outNL;
  my $sB = $b->length; $sB->outNL;

  ok Assemble(debug => 0, eq => <<END);
abababababababab
ababababababababababababababababababababababababababababababababababababab
size: 0000 0000 0000 0010
size: 0000 0000 0000 004A
size: 0000 0000 0000 0000
size: 0000 0000 0000 004A
END
 }

#latest:
if (0) {    # NEED Y                                                                      #TNasm::X86::Arena::allocZmmBlock #TNasm::X86::Arena::freeZmmBlock #TNasm::X86::Arena::getZmmBlock #TNasm::X86::Arena::putZmmBlock #TNasm::X86::Arena::clearBlock
  my $a = CreateArena;
  LoadZmm(31, 0..63);
  LoadZmm(30,    64..127);
  my $b = $a->allocZmmBlock;
  my $c = $a->allocZmmBlock;
  my $d = $a->allocZmmBlock;
  $a->putZmmBlock($b, 31);
  $a->putZmmBlock($c, 30);
  $a->putZmmBlock($d, 31);
  $a->dump("Put Block");

  $a->clearZmmBlock($c);
  $a->dump("Clear Block");

  $a->getZmmBlock($b, 29);
  PrintOutRegisterInHex zmm29;

  $a->freeZmmBlock($b);
  $a->dump("Free Block");
  $a->freeZmmBlock($c);
  $a->dump("Free Block");

  $a->getZmmBlock($d, 28);
  PrintOutRegisterInHex zmm28;

  $a->freeZmmBlock($d);
  $a->dump("Free Block");

  ok Assemble(debug => 0, eq => <<END);
Put Block
Arena     Size:     4096    Used:      256
0000 0000 0000 0000 | __10 ____ ____ ____  __01 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | __01 0203 0405 0607  0809 0A0B 0C0D 0E0F  1011 1213 1415 1617  1819 1A1B 1C1D 1E1F  2021 2223 2425 2627  2829 2A2B 2C2D 2E2F  3031 3233 3435 3637  3839 3A3B 3C3D 3E3F
0000 0000 0000 0080 | 4041 4243 4445 4647  4849 4A4B 4C4D 4E4F  5051 5253 5455 5657  5859 5A5B 5C5D 5E5F  6061 6263 6465 6667  6869 6A6B 6C6D 6E6F  7071 7273 7475 7677  7879 7A7B 7C7D 7E7F
0000 0000 0000 00C0 | __01 0203 0405 0607  0809 0A0B 0C0D 0E0F  1011 1213 1415 1617  1819 1A1B 1C1D 1E1F  2021 2223 2425 2627  2829 2A2B 2C2D 2E2F  3031 3233 3435 3637  3839 3A3B 3C3D 3E3F
Clear Block
Arena     Size:     4096    Used:      256
0000 0000 0000 0000 | __10 ____ ____ ____  __01 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | __01 0203 0405 0607  0809 0A0B 0C0D 0E0F  1011 1213 1415 1617  1819 1A1B 1C1D 1E1F  2021 2223 2425 2627  2829 2A2B 2C2D 2E2F  3031 3233 3435 3637  3839 3A3B 3C3D 3E3F
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | __01 0203 0405 0607  0809 0A0B 0C0D 0E0F  1011 1213 1415 1617  1819 1A1B 1C1D 1E1F  2021 2223 2425 2627  2829 2A2B 2C2D 2E2F  3031 3233 3435 3637  3839 3A3B 3C3D 3E3F
 zmm29: 3F3E 3D3C 3B3A 3938   3736 3534 3332 3130   2F2E 2D2C 2B2A 2928   2726 2524 2322 2120   1F1E 1D1C 1B1A 1918   1716 1514 1312 1110   0F0E 0D0C 0B0A 0908   0706 0504 0302 0100
Free Block
Arena     Size:     4096    Used:      384
0000 0000 0000 0000 | __10 ____ ____ ____  8001 ____ ____ ____  __01 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | __01 0203 0405 0607  0809 0A0B 0C0D 0E0F  1011 1213 1415 1617  1819 1A1B 1C1D 1E1F  2021 2223 2425 2627  2829 2A2B 2C2D 2E2F  3031 3233 3435 3637  3839 3A3B 3C3D 3E3F
Free Block
Arena     Size:     4096    Used:      384
0000 0000 0000 0000 | __10 ____ ____ ____  8001 ____ ____ ____  __01 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 00C0 | __01 0203 0405 0607  0809 0A0B 0C0D 0E0F  1011 1213 1415 1617  1819 1A1B 1C1D 1E1F  2021 2223 2425 2627  2829 2A2B 2C2D 2E2F  3031 3233 3435 3637  3839 3A3B 3C3D 3E3F
 zmm28: 3F3E 3D3C 3B3A 3938   3736 3534 3332 3130   2F2E 2D2C 2B2A 2928   2726 2524 2322 2120   1F1E 1D1C 1B1A 1918   1716 1514 1312 1110   0F0E 0D0C 0B0A 0908   0706 0504 0302 0100
Free Block
Arena     Size:     4096    Used:      384
0000 0000 0000 0000 | __10 ____ ____ ____  8001 ____ ____ ____  __01 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 80__ ____
END
 }

if (1) {                                                                        #TReorderSyscallRegisters #TUnReorderSyscallRegisters
  Mov rax, 1;  Mov rdi, 2;  Mov rsi,  3;  Mov rdx,  4;
  Mov r8,  8;  Mov r9,  9;  Mov r10, 10;  Mov r11, 11;

  ReorderSyscallRegisters   r8,r9;                                              # Reorder the registers for syscall
  PrintOutRegisterInHex rax;
  PrintOutRegisterInHex rdi;

  UnReorderSyscallRegisters r8,r9;                                              # Unreorder the registers to recover their original values
  PrintOutRegisterInHex rax;
  PrintOutRegisterInHex rdi;

  ok Assemble =~ m(rax:.*08.*rdi:.*9.*rax:.*1.*rdi:.*2.*)s;
 }

if (1) {                                                                        # Mask register instructions #TClearRegisters
  Mov rax,1;
  Kmovq k0,  rax;
  Kaddb k0,  k0, k0;
  Kaddb k0,  k0, k0;
  Kaddb k0,  k0, k0;
  Kmovq rax, k0;
  PushR k0;
  ClearRegisters k0;
  Kmovq k1, k0;
  PopR  k0;
  PrintOutRegisterInHex k0;
  PrintOutRegisterInHex k1;

  ok Assemble =~ m(k0: 0000 0000 0000 0008.*k1: 0000 0000 0000 0000)s;
 }

if (1) {                                                                        # Count leading zeros
  Mov   rax, 8;                                                                 # Append a constant to the arena
  Lzcnt rax, rax;                                                               # New line
  PrintOutRegisterInHex rax;

  Mov   rax, 8;                                                                 # Append a constant to the arena
  Tzcnt rax, rax;                                                               # New line
  PrintOutRegisterInHex rax;

  ok Assemble =~ m(rax: 0000 0000 0000 003C.*rax: 0000 0000 0000 0003)s;
 }

#latest:;
if (1) {                                                                        #TArena::nl
  my $s = CreateArena;
  $s->q("A");
  $s->nl;
  $s->q("B");
  $s->out;
  PrintOutNL;

  ok Assemble(debug => 0, eq => <<END);
A
B
END
 }

#latest:;
if (1) {                                                                        # Print this file  #TArena::read #TArena::z #TArena::q
  my $s = CreateArena;                                                          # Create a string
  $s->read(K(file, Rs($0)));
  $s->out;

  my $r = Assemble(emulator => 0);
  is_deeply stringMd5Sum($r), fileMd5Sum($0);                                   # Output contains this file
 }

#latest:;
if (1) {                                                                        # Print rdi in hex into an arena #TGetPidInHex
  GetPidInHex;
  PrintOutRegisterInHex rax;

  ok Assemble =~ m(rax: 00);
 }

#latest:;
if (1) {                                                                        # Execute the content of an arena #TexecuteFileViaBash #TArena::write #TArena::out #TunlinkFile #TArena::ql
  my $s = CreateArena;                                                          # Create a string
  $s->ql(<<END);                                                                # Write code to execute
#!/usr/bin/bash
whoami
ls -la
pwd
END
  $s->write         (my $f = V('file', Rs("zzz.sh")));                          # Write code to a file
  executeFileViaBash($f);                                                       # Execute the file
  unlinkFile        ($f);                                                       # Delete the file

  my $u = qx(whoami); chomp($u);
  ok Assemble(emulator => 0) =~ m($u);                                          # The Intel Software Development Emulator is way too slow on these operations.
 }

#latest:;
if (1) {                                                                        # Make an arena readonly
  my $s = CreateArena;                                                          # Create an arena
  $s->q("Hello");                                                               # Write code to arena
  $s->makeReadOnly;                                                             # Make arena read only
  $s->q(" World");                                                              # Try to write to arena

  ok Assemble(debug=>2) =~ m(SDE ERROR: DEREFERENCING BAD MEMORY POINTER.*mov byte ptr .rax.rdx.1., r8b);
 }

#latest:;
if (1) {                                                                        # Make a read only arena writable  #TArena::makeReadOnly #TArena::makeWriteable
  my $s = CreateArena;                                                          # Create an arena
  $s->q("Hello");                                                               # Write data to arena
  $s->makeReadOnly;                                                             # Make arena read only - tested above
  $s->makeWriteable;                                                            # Make arena writable again
  $s->q(" World");                                                              # Try to write to arena
  $s->out;

  ok Assemble =~ m(Hello World);
 }

#latest:;
if (1) {                                                                        # Allocate some space in arena #TArena::allocate
  my $s = CreateArena;                                                          # Create an arena
  my $o1 = $s->allocate(V(size, 0x20));                                         # Allocate space wanted
  my $o2 = $s->allocate(V(size, 0x30));
  my $o3 = $s->allocate(V(size, 0x10));
  $o1->outNL;
  $o2->outNL;
  $o3->outNL;

  ok Assemble(debug => 0, eq => <<END);
offset: 0000 0000 0000 0040
offset: 0000 0000 0000 0060
offset: 0000 0000 0000 0090
END
 }

#latest:;
if (0) {  # NEED Y                                                                       #TNasm::X86::Arena::checkYggdrasilCreated #TNasm::X86::Arena::establishYggdrasil #TNasm::X86::Arena::firstFreeBlock #TNasm::X86::Arena::setFirstFreeBlock
  my $A = CreateArena;
  my $t = $A->checkYggdrasilCreated;
     $t->found->outNL;
  my $y = $A->establishYggdrasil;
  my $T = $A->checkYggdrasilCreated;
     $T->found->outNL;

  my $f = $A->firstFreeBlock; $f->outNL;

  $A->setFirstFreeBlock(V('first', 0xcc));

  my $F = $A->firstFreeBlock; $F->outNL;

  ok Assemble(debug => 0, eq => <<END);
found: 0000 0000 0000 0000
found: 0000 0000 0000 0001
free: 0000 0000 0000 0000
free: 0000 0000 0000 00CC
END
 }

# It is one of the happiest characteristics of this glorious country that official utterances are invariably regarded as unanswerable

#latest:;
if (1) {                                                                        #TPrintOutZF #TSetZF #TClearZF #TIfC #TIfNc #TIfZ #IfNz
  SetZF;
  PrintOutZF;
  ClearZF;
  PrintOutZF;
  SetZF;
  PrintOutZF;
  SetZF;
  PrintOutZF;
  ClearZF;
  PrintOutZF;

  SetZF;
  IfZ  Then {PrintOutStringNL "Zero"},     Else {PrintOutStringNL "NOT zero"};
  ClearZF;
  IfNz Then {PrintOutStringNL "NOT zero"}, Else {PrintOutStringNL "Zero"};

  Mov r15, 5;
  Shr r15, 1; IfC  Then {PrintOutStringNL "Carry"}   , Else {PrintOutStringNL "NO carry"};
  Shr r15, 1; IfC  Then {PrintOutStringNL "Carry"}   , Else {PrintOutStringNL "NO carry"};
  Shr r15, 1; IfNc Then {PrintOutStringNL "NO carry"}, Else {PrintOutStringNL "Carry"};
  Shr r15, 1; IfNc Then {PrintOutStringNL "NO carry"}, Else {PrintOutStringNL "Carry"};

  ok Assemble(debug => 0, eq => <<END);
ZF=1
ZF=0
ZF=1
ZF=1
ZF=0
Zero
NOT zero
Carry
NO carry
Carry
NO carry
END
 }

if (1) {                                                                        #TSetLabel #TRegisterSize #TSaveFirstFour #TSaveFirstSeven #TRestoreFirstFour #TRestoreFirstSeven #TRestoreFirstFourExceptRax #TRestoreFirstSevenExceptRax #TRestoreFirstFourExceptRaxAndRdi #TRestoreFirstSevenExceptRaxAndRdi #TReverseBytesInRax
  Mov rax, 1;
  Mov rdi, 1;
  SaveFirstFour;
  Mov rax, 2;
  Mov rdi, 2;
  SaveFirstSeven;
  Mov rax, 3;
  Mov rdi, 4;
  PrintOutRegisterInHex rax, rdi;
  RestoreFirstSeven;
  PrintOutRegisterInHex rax, rdi;
  RestoreFirstFour;
  PrintOutRegisterInHex rax, rdi;

  SaveFirstFour;
  Mov rax, 2;
  Mov rdi, 2;
  SaveFirstSeven;
  Mov rax, 3;
  Mov rdi, 4;
  PrintOutRegisterInHex rax, rdi;
  RestoreFirstSevenExceptRax;
  PrintOutRegisterInHex rax, rdi;
  RestoreFirstFourExceptRax;
  PrintOutRegisterInHex rax, rdi;

  SaveFirstFour;
  Mov rax, 2;
  Mov rdi, 2;
  SaveFirstSeven;
  Mov rax, 3;
  Mov rdi, 4;
  PrintOutRegisterInHex rax, rdi;
  RestoreFirstSevenExceptRaxAndRdi;
  PrintOutRegisterInHex rax, rdi;
  RestoreFirstFourExceptRaxAndRdi;
  PrintOutRegisterInHex rax, rdi;

  Bswap rax;
  PrintOutRegisterInHex rax;

  my $l = Label;
  Jmp $l;
  SetLabel $l;

  ok Assemble(debug => 0, eq => <<END);
   rax: 0000 0000 0000 0003
   rdi: 0000 0000 0000 0004
   rax: 0000 0000 0000 0002
   rdi: 0000 0000 0000 0002
   rax: 0000 0000 0000 0001
   rdi: 0000 0000 0000 0001
   rax: 0000 0000 0000 0003
   rdi: 0000 0000 0000 0004
   rax: 0000 0000 0000 0003
   rdi: 0000 0000 0000 0002
   rax: 0000 0000 0000 0003
   rdi: 0000 0000 0000 0001
   rax: 0000 0000 0000 0003
   rdi: 0000 0000 0000 0004
   rax: 0000 0000 0000 0003
   rdi: 0000 0000 0000 0004
   rax: 0000 0000 0000 0003
   rdi: 0000 0000 0000 0004
   rax: 0300 0000 0000 0000
END

  ok 8 == RegisterSize rax;
 }

#latest:
if (1) {                                                                        #TRb #TRd #TRq #TRw #TDb #TDd #TDq #TDw #TCopyMemory
  my $s = Rb 0; Rb 1; Rw 2; Rd 3;  Rq 4;
  my $t = Db 0; Db 1; Dw 2; Dd 3;  Dq 4;

  Vmovdqu8 xmm0, "[$s]";
  Vmovdqu8 xmm1, "[$t]";
  PrintOutRegisterInHex xmm0;
  PrintOutRegisterInHex xmm1;
  Sub rsp, 16;

  Mov rax, rsp;                                                                 # Copy memory, the target is addressed by rax, the length is in rdi, the source is addressed by rsi
  Mov rdi, 16;
  Mov rsi, $s;
  CopyMemory(V(source, rsi), V(target, rax), V(size, rdi));
  PrintOutMemory_InHexNL;

  ok Assemble(debug => 0, eq => <<END);
  xmm0: 0000 0000 0000 0004   0000 0003 0002 0100
  xmm1: 0000 0000 0000 0004   0000 0003 0002 0100
__01 02__ 03__ ____  04__ ____ ____ ____
END
 }

#latest:
if (1) {
  my $a = V(a => 1);
  my $b = V(b => 2);
  my $c = $a + $b;
  Mov r15, 22;
  $a->getReg(r15);
  $b->copy($a);
  $b = $b + 1;
  $b->setReg(r14);
  $a->outNL;
  $b->outNL;
  $c->outNL;
  PrintOutRegisterInHex r14, r15;

  ok Assemble(debug => 0, eq => <<END);
a: 0000 0000 0000 0016
(b add 1): 0000 0000 0000 0017
(a add b): 0000 0000 0000 0003
   r14: 0000 0000 0000 0017
   r15: 0000 0000 0000 0016
END
 }

#latest:
if (1) {                                                                        #TV #TK #TG #TNasm::X86::Variable::copy
  my $s = Subroutine
   {my ($p) = @_;
    $$p{v}->copy($$p{v} + $$p{k} + $$p{g} + 1);
   } [qw(v k g)], name => 'add';

  my $v = V(v, 1);
  my $k = K(k, 2);
  my $g = V(g, 3);
  $s->call($v, $k, $g);
  $v->outNL;

  ok Assemble(debug => 0, eq => <<END);
v: 0000 0000 0000 0007
END
 }

#latest:
if (1) {                                                                        #TV #TK #TG #TNasm::X86::Variable::copy
  my $g = V g => 0;
  my $s = Subroutine
   {my ($p) = @_;
    $$p{g}->copy(K value, 1);
   } [qw(g)], name => 'ref2';

  my $t = Subroutine
   {my ($p) = @_;
    $s->call($$p{g});
   } [qw(g)], name => 'ref';

  $t->call($g);
  $g->outNL;

  ok Assemble(debug => 0, eq => <<END);
g: 0000 0000 0000 0001
END
 }

#latest:
if (1) {                                                                        #TSubroutine
  my $g = V g => 3;
  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;
    my $g = $$p{g};
    $g->copy($g - 1);
    $g->outNL;
    If ($g > 0,
    Then
     {$sub->call(parameters=>{g => $g});
     });
   } parameters=>[qw(g)], name => 'ref';

  $s->call(parameters=>{g => $g});

  ok Assemble(debug => 0, eq => <<END);
g: 0000 0000 0000 0002
g: 0000 0000 0000 0001
g: 0000 0000 0000 0000
END
 }

#latest:
if (0) {                                                                        #TPrintOutTraceBack
  my $d = V depth => 3;                                                         # Create a variable on the stack

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine descriptor

    my $d = $$p{depth}->copy($$p{depth} - 1);                                   # Modify the variable referenced by the parameter

    If $d > 0,
    Then
     {$sub->call(parameters => {depth => $d});                                     # Recurse
     };

    #PrintOutTraceBack 'AAAA';
   } parameters =>[qw(depth)], name => 'ref';

  $s->call(parameters=>{depth => V depth => 0});

  ok Assemble(debug => 0, eq => <<END);

Subroutine trace back, depth:  3
0000 0000 0000 0001    ref
0000 0000 0000 0001    ref
0000 0000 0000 0001    ref
END
 }

#latest:
if (0) {                                                                        #TSubroutine
  my $g = V g, 2;
  my $u = Subroutine
   {my ($p, $s) = @_;
    $$p{g}->copy(K gg, 1);
    PrintOutTraceBack '';
   } [qw(g)], name => 'uuuu';
  my $t = Subroutine
   {my ($p, $s) = @_;
    $u->call($$p{g});
   } [qw(g)], name => 'tttt';
  my $s = Subroutine
   {my ($p, $s) = @_;
    $t->call($$p{g});
   } [qw(g)], name => 'ssss';

  $g->outNL;
  $s->call($g);
  $g->outNL;

  ok Assemble(debug => 0, eq => <<END);
Subroutine trace back, depth:  3
0000 0000 0000 0002    uuuu
0000 0000 0000 0002    tttt
0000 0000 0000 0002    ssss
END
 }

#latest:
if (0) {                                                                        #TSubroutine
  my $r = V r, 2;

  my $u = Subroutine
   {my ($p, $s) = @_;
    $$p{u}->copy(K gg, 1);
    PrintOutTraceBack '';
   } [qw(u)], name => 'uuuu';

  my $t = Subroutine
   {my ($p, $s) = @_;
    $u->call(u => $$p{t});
   } [qw(t)], name => 'tttt';

  my $s = Subroutine
   {my ($p, $s) = @_;
   $t->call(t => $$p{s});
   } [qw(s)], name => 'ssss';

  $r->outNL;
  $s->call(s=>$r);
  $r->outNL;

  ok Assemble(debug => 0, eq => <<END);
r: 0000 0000 0000 0002

Subroutine trace back, depth:  3
0000 0000 0000 0002    uuuu
0000 0000 0000 0002    tttt
0000 0000 0000 0002    ssss


Subroutine trace back, depth:  3
0000 0000 0000 0001    uuuu
0000 0000 0000 0001    tttt
0000 0000 0000 0001    ssss

r: 0000 0000 0000 0001
END
 }

#latest:;
if (1) {                                                                        #TAllocateMemory #TPrintOutMemoryInHexNL #TCopyMemory
  my $N = 256;
  my $s = Rb 0..$N-1;
  my $a = AllocateMemory K size => $N;
  CopyMemory(V(source => $s), $a, K(size => $N));

  my $b = AllocateMemory K size => $N;
  CopyMemory($a, $b, K size => $N);

  $b->setReg(rax);
  Mov rdi, $N;
  PrintOutMemory_InHexNL;

  ok Assemble(debug=>0, eq => <<END);
__01 0203 0405 0607  0809 0A0B 0C0D 0E0F  1011 1213 1415 1617  1819 1A1B 1C1D 1E1F  2021 2223 2425 2627  2829 2A2B 2C2D 2E2F  3031 3233 3435 3637  3839 3A3B 3C3D 3E3F  4041 4243 4445 4647  4849 4A4B 4C4D 4E4F  5051 5253 5455 5657  5859 5A5B 5C5D 5E5F  6061 6263 6465 6667  6869 6A6B 6C6D 6E6F  7071 7273 7475 7677  7879 7A7B 7C7D 7E7F  8081 8283 8485 8687  8889 8A8B 8C8D 8E8F  9091 9293 9495 9697  9899 9A9B 9C9D 9E9F  A0A1 A2A3 A4A5 A6A7  A8A9 AAAB ACAD AEAF  B0B1 B2B3 B4B5 B6B7  B8B9 BABB BCBD BEBF  C0C1 C2C3 C4C5 C6C7  C8C9 CACB CCCD CECF  D0D1 D2D3 D4D5 D6D7  D8D9 DADB DCDD DEDF  E0E1 E2E3 E4E5 E6E7  E8E9 EAEB ECED EEEF  F0F1 F2F3 F4F5 F6F7  F8F9 FAFB FCFD FEFF
END
 }

if (1) {                                                                        # Variable length shift
  Mov rax, -1;
  Mov cl, 30;
  Shl rax, cl;
  Kmovq k0, rax;
  PrintOutRegisterInHex k0;

  ok Assemble =~ m(k0: FFFF FFFF C000 0000)s;
 }

if (1) {                                                                        # Expand
  ClearRegisters rax;
  Bts rax, 14;
  Not rax;
  PrintOutRegisterInHex rax;
  Kmovq k1, rax;
  PrintOutRegisterInHex k1;

  Mov rax, 1;
  Vpbroadcastb zmm0, rax;
  PrintOutRegisterInHex zmm0;

  Vpexpandd "zmm1{k1}", zmm0;
  PrintOutRegisterInHex zmm1;

  ok Assemble(debug => 0, eq => <<END);
   rax: FFFF FFFF FFFF BFFF
    k1: FFFF FFFF FFFF BFFF
  zmm0: 0101 0101 0101 0101   0101 0101 0101 0101   0101 0101 0101 0101   0101 0101 0101 0101   0101 0101 0101 0101   0101 0101 0101 0101   0101 0101 0101 0101   0101 0101 0101 0101
  zmm1: 0101 0101 0000 0000   0101 0101 0101 0101   0101 0101 0101 0101   0101 0101 0101 0101   0101 0101 0101 0101   0101 0101 0101 0101   0101 0101 0101 0101   0101 0101 0101 0101
END
 }

#latest:;
if (1) {
  my $P = "2F";                                                                 # Value to test for
  my $l = Rb 0;  Rb $_ for 1..RegisterSize zmm0;                                # The numbers 0..63
  Vmovdqu8 zmm0, "[$l]";                                                        # Load data to test
  PrintOutRegisterInHex zmm0;

  Mov rax, "0x$P";                                                              # Broadcast the value to be tested
  Vpbroadcastb zmm1, rax;
  PrintOutRegisterInHex zmm1;

  for my $c(0..7)                                                               # Each possible test
   {my $m = "k$c";
    Vpcmpub $m, zmm1, zmm0, $c;
    PrintOutRegisterInHex $m;
   }

  Kmovq rax, k0;                                                                # Count the number of trailing zeros in k0
  Tzcnt rax, rax;
  PrintOutRegisterInHex rax;

  is_deeply [split //, Assemble], [split //, <<END];                            # Assemble and test
  zmm0: 3F3E 3D3C 3B3A 3938   3736 3534 3332 3130   2F2E 2D2C 2B2A 2928   2726 2524 2322 2120   1F1E 1D1C 1B1A 1918   1716 1514 1312 1110   0F0E 0D0C 0B0A 0908   0706 0504 0302 0100
  zmm1: 2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F
    k0: 0000 8000 0000 0000
    k1: FFFF 0000 0000 0000
    k2: FFFF 8000 0000 0000
    k3: 0000 0000 0000 0000
    k4: FFFF 7FFF FFFF FFFF
    k5: 0000 FFFF FFFF FFFF
    k6: 0000 7FFF FFFF FFFF
    k7: FFFF FFFF FFFF FFFF
   rax: 0000 0000 0000 00$P
END
#   0 eq    1 lt    2 le    4 ne    5 ge    6 gt   comparisons
 }

#latest:;
if (1) {
  my $P = "2F";                                                                 # Value to test for
  my $l = Rb 0;  Rb $_ for 1..RegisterSize zmm0;                                # The numbers 0..63
  Vmovdqu8 zmm0, "[$l]";                                                        # Load data to test

  Mov rax, "0x$P";                                                              # Broadcast the value to be tested
  Vpbroadcastb zmm1, rax;

  for my $c(0..7)                                                               # Each possible test
   {my $m = "k$c";
    Vpcmpub $m, zmm1, zmm0, $c;
   }

  Kmovq rax, k0;                                                                # Count the number of trailing zeros in k0
  Tzcnt rax, rax;

  is_deeply [split //, Assemble], [split //, <<END];                            # Assemble and test
END
 }

#latest:;
if (1) {                                                                        #TStringLength
  StringLength(V(string, Rs("abcd")))->outNL;
  Assemble(debug => 0, eq => <<END);
size: 0000 0000 0000 0004
END
 }

#latest:;
if (0) {                                                                        # Hash a string #THash
  Mov rax, "[rbp+24]";                                                          # Address of string as parameter
  StringLength(V string => rax)->setReg(rdi);                                   # Length of string to hash
  Hash();                                                                       # Hash string

  PrintOutRegisterInHex r15;

  my $e = Assemble keep => 'hash';                                              # Assemble to the specified file name
  say STDERR qx($e "");
  say STDERR qx($e "a");
  ok qx($e "")  =~ m(r15: 0000 3F80 0000 3F80);                                 # Test well known hashes
  ok qx($e "a") =~ m(r15: 0000 3F80 C000 45B2);

  if (0)                                                                        # Hash various strings
   {my %r; my %f; my $count = 0;
    my $N = RegisterSize zmm0;

    if (1)                                                                      # Fixed blocks
     {for my $l(qw(a ab abc abcd), 'a a', 'a  a')
       {for my $i(1..$N)
         {my $t = $l x $i;
          last if $N < length $t;
          my $s = substr($t.(' ' x $N), 0, $N);
          next if $f{$s}++;
          my $r = qx($e "$s");
          say STDERR "$count  $r";
          if ($r =~ m(^.*r15:\s*(.*)$)m)
           {push $r{$1}->@*, $s;
            ++$count;
           }
         }
       }
     }

    if (1)                                                                      # Variable blocks
     {for my $l(qw(a ab abc abcd), '', 'a a', 'a  a')
       {for my $i(1..$N)
         {my $t = $l x $i;
          next if $f{$t}++;
          my $r = qx($e "$t");
          say STDERR "$count  $r";
          if ($r =~ m(^.*r15:\s*(.*)$)m)
           {push $r{$1}->@*, $t;
            ++$count;
           }
         }
       }
     }
    for my $r(keys %r)
     {delete $r{$r} if $r{$r}->@* < 2;
     }

    say STDERR dump(\%r);
    say STDERR "Keys hashed: ", $count;
    confess "Duplicates : ",  scalar keys(%r);
   }

  unlink 'hash';
 }

if (1) {                                                                        #TIfEq #TIfNe #TIfLe #TIfLt #TIfGe #TIfGt
  my $cmp = sub
   {my ($a, $b) = @_;

    for my $op(qw(eq ne lt le gt ge))
     {Mov rax, $a;
      Cmp rax, $b;
      my $Op = ucfirst $op;
      eval qq(If$Op Then {PrintOutStringNL("$a $op $b")}, Else {PrintOutStringNL("$a NOT $op $b")});
      $@ and confess $@;
     }
   };
  &$cmp(1,1);
  &$cmp(1,2);
  &$cmp(3,2);
  Assemble(debug => 0, eq => <<END);
1 eq 1
1 NOT ne 1
1 NOT lt 1
1 le 1
1 NOT gt 1
1 ge 1
1 NOT eq 2
1 ne 2
1 lt 2
1 le 2
1 NOT gt 2
1 NOT ge 2
3 NOT eq 2
3 ne 2
3 NOT lt 2
3 NOT le 2
3 gt 2
3 ge 2
END
 }

if (1) {                                                                        #TSetMaskRegister
  Mov rax, 8;
  Mov rsi, -1;
  Inc rsi; SetMaskRegister(0, rax, rsi); PrintOutRegisterInHex k0;
  Inc rsi; SetMaskRegister(1, rax, rsi); PrintOutRegisterInHex k1;
  Inc rsi; SetMaskRegister(2, rax, rsi); PrintOutRegisterInHex k2;
  Inc rsi; SetMaskRegister(3, rax, rsi); PrintOutRegisterInHex k3;
  Inc rsi; SetMaskRegister(4, rax, rsi); PrintOutRegisterInHex k4;
  Inc rsi; SetMaskRegister(5, rax, rsi); PrintOutRegisterInHex k5;
  Inc rsi; SetMaskRegister(6, rax, rsi); PrintOutRegisterInHex k6;
  Inc rsi; SetMaskRegister(7, rax, rsi); PrintOutRegisterInHex k7;

  ok Assemble(debug => 0, eq => <<END);
    k0: 0000 0000 0000 0000
    k1: 0000 0000 0000 0100
    k2: 0000 0000 0000 0300
    k3: 0000 0000 0000 0700
    k4: 0000 0000 0000 0F00
    k5: 0000 0000 0000 1F00
    k6: 0000 0000 0000 3F00
    k7: 0000 0000 0000 7F00
END
 }

#latest:;
if (1) {                                                                        #TNasm::X86::Variable::dump  #TNasm::X86::Variable::print #TThen #TElse #TV #TK
  my $a = V(a, 3);  $a->outNL;
  my $b = K(b, 2);  $b->outNL;
  my $c = $a +  $b; $c->outNL;
  my $d = $c -  $a; $d->outNL;
  my $g = $a *  $b; $g->outNL;
  my $h = $g /  $b; $h->outNL;
  my $i = $a %  $b; $i->outNL;

  If ($a == 3,
  Then
   {PrintOutStringNL "a == 3"
   },
  Else
   {PrintOutStringNL "a != 3"
   });

  ++$a; $a->outNL;
  --$a; $a->outNL;

  ok Assemble(debug => 0, eq => <<END);
a: 0000 0000 0000 0003
b: 0000 0000 0000 0002
(a add b): 0000 0000 0000 0005
((a add b) sub a): 0000 0000 0000 0002
(a times b): 0000 0000 0000 0006
((a times b) / b): 0000 0000 0000 0003
(a % b): 0000 0000 0000 0001
a == 3
a: 0000 0000 0000 0004
a: 0000 0000 0000 0003
END
 }

#latest:;
if (1) {                                                                        #TNasm::X86::Variable::for
  V(limit,10)->for(sub
   {my ($i, $start, $next, $end) = @_;
    $i->outNL;
   });

  ok Assemble(debug => 0, eq => <<END);
index: 0000 0000 0000 0000
index: 0000 0000 0000 0001
index: 0000 0000 0000 0002
index: 0000 0000 0000 0003
index: 0000 0000 0000 0004
index: 0000 0000 0000 0005
index: 0000 0000 0000 0006
index: 0000 0000 0000 0007
index: 0000 0000 0000 0008
index: 0000 0000 0000 0009
END
 }

#latest:;
if (1) {                                                                        #TNasm::X86::Variable::min #TNasm::X86::Variable::max
  my $a = V("a", 1);
  my $b = V("b", 2);
  my $c = $a->min($b);
  my $d = $a->max($b);
  $a->outNL;
  $b->outNL;
  $c->outNL;
  $d->outNL;

  ok Assemble(debug => 0, eq => <<END);
a: 0000 0000 0000 0001
b: 0000 0000 0000 0002
min: 0000 0000 0000 0001
max: 0000 0000 0000 0002
END
 }

if (1) {                                                                        #TNasm::X86::Variable::setMask
  my $start  = V("Start",  7);
  my $length = V("Length", 3);
  $start->setMask($length, k7);
  PrintOutRegisterInHex k7;

  ok Assemble(debug => 0, eq => <<END);
    k7: 0000 0000 0000 0380
END
 }

if (1) {                                                                        #TNasm::X86::Variable::setZmm
  my $s = Rb(0..128);
  my $source = V(Source, $s);

  if (1)                                                                        # First block
   {my $offset = V(Offset, 7);
    my $length = V(Length, 3);
    $source->setZmm(0, $offset, $length);
   }

  if (1)                                                                        # Second block
   {my $offset = V(Offset, 33);
    my $length = V(Length, 12);
    $source->setZmm(0, $offset, $length);
   }

  PrintOutRegisterInHex zmm0;

  ok Assemble(debug => 0, eq => <<END);
  zmm0: 0000 0000 0000 0000   0000 0000 0000 0000   0000 000B 0A09 0807   0605 0403 0201 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0201   0000 0000 0000 0000
END
 }

#latest:;
if (1) {                                                                        #TLoadZmm #Tzmm
  LoadZmm 0, 0..63;
  PrintOutRegisterInHex zmm 0;

  ok Assemble(debug => 0, eq => <<END);
  zmm0: 3F3E 3D3C 3B3A 3938   3736 3534 3332 3130   2F2E 2D2C 2B2A 2928   2726 2524 2322 2120   1F1E 1D1C 1B1A 1918   1716 1514 1312 1110   0F0E 0D0C 0B0A 0908   0706 0504 0302 0100
END
 }

#latest:;
if (1) {                                                                        #TgetDFromZmm #TNasm::X86::Variable::dIntoZ
  my $s = Rb(0..8);
  my $c = V("Content",   "[$s]");
     $c->bIntoZ(0,  4);
     $c->putWIntoZmm(0,  6);
     $c->dIntoZ(0, 10);
     $c->qIntoZ(0, 16);
  PrintOutRegisterInHex zmm0;
  bFromZ(0, 12)->outNL;
  wFromZ(0, 12)->outNL;
  dFromZ(0, 12)->outNL;
  qFromZ(0, 12)->outNL;

  ok Assemble(debug => 0, eq => <<END);
  zmm0: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0706 0504 0302 0100   0000 0302 0100 0000   0100 0000 0000 0000
b at offset 12 in zmm0: 0000 0000 0000 0002
w at offset 12 in zmm0: 0000 0000 0000 0302
d at offset 12 in zmm0: 0000 0000 0000 0302
q at offset 12 in zmm0: 0302 0100 0000 0302
END
 }

#latest:;
if (1) {                                                                        #TCreateString
  my $s = Rb(0..255);
  my $a =     CreateArena;
  my $b = $a->CreateString;
  $b->append(V(source, $s), V(size,  3)); $b->dump;
  $b->append(V(source, $s), V(size,  4)); $b->dump;
  $b->append(V(source, $s), V(size,  5)); $b->dump;

  my $S = CreateShortString(0);
  $b->saveToShortString($S);
  PrintOutRegisterInHex zmm0;

  ok Assemble(debug => 0, eq => <<END);
String Dump      Total Length:        3
Offset: 0000 0000 0000 0040  Length:  3  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0201 0003

String Dump      Total Length:        7
Offset: 0000 0000 0000 0040  Length:  7  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0302 0100 0201 0007

String Dump      Total Length:       12
Offset: 0000 0000 0000 0040  Length: 12  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0004 0302 0100   0302 0100 0201 000C

  zmm0: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0004 0302 0100   0302 0100 0201 000C
END
 }

#latest:;
if (1) {
  my $s = Rb(0..255);
  my $a =     CreateArena;
  my $b = $a->CreateString;
  $b->append(V(source, $s), V(size, 165)); $b->dump;
  $b->append(V(source, $s), V(size,   2)); $b->dump;

  ok Assemble(debug => 0, eq => <<END);
String Dump      Total Length:      165
Offset: 0000 0000 0000 0040  Length: 55  0000 0080 0000 00C0   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0037
Offset: 0000 0000 0000 0080  Length: 55  0000 00C0 0000 0040   6D6C 6B6A 6968 6766   6564 6362 6160 5F5E   5D5C 5B5A 5958 5756   5554 5352 5150 4F4E   4D4C 4B4A 4948 4746   4544 4342 4140 3F3E   3D3C 3B3A 3938 3737
Offset: 0000 0000 0000 00C0  Length: 55  0000 0040 0000 0080   A4A3 A2A1 A09F 9E9D   9C9B 9A99 9897 9695   9493 9291 908F 8E8D   8C8B 8A89 8887 8685   8483 8281 807F 7E7D   7C7B 7A79 7877 7675   7473 7271 706F 6E37

String Dump      Total Length:      167
Offset: 0000 0000 0000 0040  Length: 55  0000 0080 0000 0100   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0037
Offset: 0000 0000 0000 0080  Length: 55  0000 00C0 0000 0040   6D6C 6B6A 6968 6766   6564 6362 6160 5F5E   5D5C 5B5A 5958 5756   5554 5352 5150 4F4E   4D4C 4B4A 4948 4746   4544 4342 4140 3F3E   3D3C 3B3A 3938 3737
Offset: 0000 0000 0000 00C0  Length: 55  0000 0100 0000 0080   A4A3 A2A1 A09F 9E9D   9C9B 9A99 9897 9695   9493 9291 908F 8E8D   8C8B 8A89 8887 8685   8483 8281 807F 7E7D   7C7B 7A79 7877 7675   7473 7271 706F 6E37
Offset: 0000 0000 0000 0100  Length:  2  0000 0040 0000 00C0   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0001 0002

END
 }

#latest:;
if (1) {
  my $s = Rb(0..255);
  my $B =     CreateArena;
  my $b = $B->CreateString;
  $b->append(V(source, $s), V(size,  56)); $b->dump;
  $b->append(V(source, $s), V(size,   4)); $b->dump;
  $b->append(V(source, $s), V(size,   5)); $b->dump;
  $b->append(V(source, $s), V(size,   0)); $b->dump;
  $b->append(V(source, $s), V(size, 256)); $b->dump;

  ok Assemble(debug => 0, eq => <<END);
String Dump      Total Length:       56
Offset: 0000 0000 0000 0040  Length: 55  0000 0080 0000 0080   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0037
Offset: 0000 0000 0000 0080  Length:  1  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 3701

String Dump      Total Length:       60
Offset: 0000 0000 0000 0040  Length: 55  0000 0080 0000 0080   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0037
Offset: 0000 0000 0000 0080  Length:  5  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0302 0100 3705

String Dump      Total Length:       65
Offset: 0000 0000 0000 0040  Length: 55  0000 0080 0000 0080   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0037
Offset: 0000 0000 0000 0080  Length: 10  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0004 0302   0100 0302 0100 370A

String Dump      Total Length:       65
Offset: 0000 0000 0000 0040  Length: 55  0000 0080 0000 0080   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0037
Offset: 0000 0000 0000 0080  Length: 10  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0004 0302   0100 0302 0100 370A

String Dump      Total Length:      321
Offset: 0000 0000 0000 0040  Length: 55  0000 0080 0000 0180   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0037
Offset: 0000 0000 0000 0080  Length: 55  0000 00C0 0000 0040   2C2B 2A29 2827 2625   2423 2221 201F 1E1D   1C1B 1A19 1817 1615   1413 1211 100F 0E0D   0C0B 0A09 0807 0605   0403 0201 0004 0302   0100 0302 0100 3737
Offset: 0000 0000 0000 00C0  Length: 55  0000 0100 0000 0080   6362 6160 5F5E 5D5C   5B5A 5958 5756 5554   5352 5150 4F4E 4D4C   4B4A 4948 4746 4544   4342 4140 3F3E 3D3C   3B3A 3938 3736 3534   3332 3130 2F2E 2D37
Offset: 0000 0000 0000 0100  Length: 55  0000 0140 0000 00C0   9A99 9897 9695 9493   9291 908F 8E8D 8C8B   8A89 8887 8685 8483   8281 807F 7E7D 7C7B   7A79 7877 7675 7473   7271 706F 6E6D 6C6B   6A69 6867 6665 6437
Offset: 0000 0000 0000 0140  Length: 55  0000 0180 0000 0100   D1D0 CFCE CDCC CBCA   C9C8 C7C6 C5C4 C3C2   C1C0 BFBE BDBC BBBA   B9B8 B7B6 B5B4 B3B2   B1B0 AFAE ADAC ABAA   A9A8 A7A6 A5A4 A3A2   A1A0 9F9E 9D9C 9B37
Offset: 0000 0000 0000 0180  Length: 46  0000 0040 0000 0140   0000 0000 0000 0000   00FF FEFD FCFB FAF9   F8F7 F6F5 F4F3 F2F1   F0EF EEED ECEB EAE9   E8E7 E6E5 E4E3 E2E1   E0DF DEDD DCDB DAD9   D8D7 D6D5 D4D3 D22E

END
 }

#latest:;
if (0) {  # NEED Y                                                                       #TNasm::X86::Arena::length #TNasm::X86::Arena::clear
  my $t = Rb(0..255);
  my $a = CreateArena;
  my $s = $a->CreateString;
  V(loop => 5)->for(sub
   {$s->append(V(source => $t), K(size => 256));
    $s->clear;
    $a->length->outNL;
   });

  ok Assemble(debug => 0, eq => <<END);
size: 0000 0000 0000 01C0
size: 0000 0000 0000 01C0
size: 0000 0000 0000 01C0
size: 0000 0000 0000 01C0
size: 0000 0000 0000 01C0
END
 }

#latest:;
if (0) {  # NEED Y                                                                       #TNasm::X86::Arena::free
  my $t = Rb(0..255);
  my $a = CreateArena;

  V(loop => 5)->for(sub
   {my $s = $a->CreateString;
    $s->append(K(source => $t), K size => 256);
    $s->free;
    $a->length->outNL;
   });

  ok Assemble(debug => 0, eq => <<END);
size: 0000 0000 0000 01C0
size: 0000 0000 0000 01C0
size: 0000 0000 0000 01C0
size: 0000 0000 0000 01C0
size: 0000 0000 0000 01C0
END
 }

#latest:;
if (1) {                                                                        #TNasm::X86::String::concatenate
  my $c = Rb(0..255);
  my $S = CreateArena;   my $s = $S->CreateString;
  my $T = CreateArena;   my $t = $T->CreateString;

  $s->append(V(source => $c), K size => 256);
  $t->concatenate($s);
  $t->dump;

  ok Assemble(debug => 0, eq => <<END);
String Dump      Total Length:      256
Offset: 0000 0000 0000 0040  Length:  0  0000 0080 0000 0180   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
Offset: 0000 0000 0000 0080  Length: 55  0000 00C0 0000 0040   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0037
Offset: 0000 0000 0000 00C0  Length: 55  0000 0100 0000 0080   6D6C 6B6A 6968 6766   6564 6362 6160 5F5E   5D5C 5B5A 5958 5756   5554 5352 5150 4F4E   4D4C 4B4A 4948 4746   4544 4342 4140 3F3E   3D3C 3B3A 3938 3737
Offset: 0000 0000 0000 0100  Length: 55  0000 0140 0000 00C0   A4A3 A2A1 A09F 9E9D   9C9B 9A99 9897 9695   9493 9291 908F 8E8D   8C8B 8A89 8887 8685   8483 8281 807F 7E7D   7C7B 7A79 7877 7675   7473 7271 706F 6E37
Offset: 0000 0000 0000 0140  Length: 55  0000 0180 0000 0100   DBDA D9D8 D7D6 D5D4   D3D2 D1D0 CFCE CDCC   CBCA C9C8 C7C6 C5C4   C3C2 C1C0 BFBE BDBC   BBBA B9B8 B7B6 B5B4   B3B2 B1B0 AFAE ADAC   ABAA A9A8 A7A6 A537
Offset: 0000 0000 0000 0180  Length: 36  0000 0040 0000 0140   0000 0000 0000 0000   0000 0000 0000 0000   0000 00FF FEFD FCFB   FAF9 F8F7 F6F5 F4F3   F2F1 F0EF EEED ECEB   EAE9 E8E7 E6E5 E4E3   E2E1 E0DF DEDD DC24

END
 }

#latest:;
if (1) {                                                                        # Strings doubled
  my $s1 = Rb(0..63);
  my $s2 = Rb(64..127);
  my $S = CreateArena;   my $s = $S->CreateString;
  my $T = CreateArena;   my $t = $T->CreateString;

  $s->append(V(source => $s1), K size => 64);
  $t->append(V(source => $s2), K size => 64);
  $s->append(V(source => $s1), K size => 64);
  $t->append(V(source => $s2), K size => 64);

  $s->dump;
  $t->dump;

  ok Assemble(debug => 0, eq => <<END);
String Dump      Total Length:      128
Offset: 0000 0000 0000 0040  Length: 55  0000 0080 0000 00C0   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0037
Offset: 0000 0000 0000 0080  Length: 55  0000 00C0 0000 0040   2D2C 2B2A 2928 2726   2524 2322 2120 1F1E   1D1C 1B1A 1918 1716   1514 1312 1110 0F0E   0D0C 0B0A 0908 0706   0504 0302 0100 3F3E   3D3C 3B3A 3938 3737
Offset: 0000 0000 0000 00C0  Length: 18  0000 0040 0000 0080   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 003F 3E3D   3C3B 3A39 3837 3635   3433 3231 302F 2E12

String Dump      Total Length:      128
Offset: 0000 0000 0000 0040  Length: 55  0000 0080 0000 00C0   7675 7473 7271 706F   6E6D 6C6B 6A69 6867   6665 6463 6261 605F   5E5D 5C5B 5A59 5857   5655 5453 5251 504F   4E4D 4C4B 4A49 4847   4645 4443 4241 4037
Offset: 0000 0000 0000 0080  Length: 55  0000 00C0 0000 0040   6D6C 6B6A 6968 6766   6564 6362 6160 5F5E   5D5C 5B5A 5958 5756   5554 5352 5150 4F4E   4D4C 4B4A 4948 4746   4544 4342 4140 7F7E   7D7C 7B7A 7978 7737
Offset: 0000 0000 0000 00C0  Length: 18  0000 0040 0000 0080   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 007F 7E7D   7C7B 7A79 7877 7675   7473 7271 706F 6E12

END
 }

#latest:;
if (1) {                                                                        # Insert char in a string
  my $c = Rb(0..255);
  my $S = CreateArena;
  my $s = $S->CreateString;

  $s->append     (V(source => $c),   K size => 3); $s->dump;
   $s->insertChar(V(source => 0x44), K size => 2); $s->dump;
   $s->insertChar(V(source => 0x88), K size => 2); $s->dump;

  ok Assemble(debug => 0, eq => <<END);
String Dump      Total Length:        3
Offset: 0000 0000 0000 0040  Length:  3  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0201 0003

String Dump      Total Length:        4
Offset: 0000 0000 0000 0040  Length:  4  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0002 4401 0004

String Dump      Total Length:        5
Offset: 0000 0000 0000 0040  Length:  5  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0244 8801 0005

END
 }

#latest:;
if (1) {                                                                        # Insert char in a multi string at position 22
  my $c = Rb(0..255);
  my $S = CreateArena;   my $s = $S->CreateString;

  $s->append    (V(source => $c),       K size     => 58);  $s->dump;
  $s->insertChar(V(character  => 0x44), K position => 22);  $s->dump;
  $s->insertChar(V(character  => 0x88), K position => 22);  $s->dump;

  ok Assemble(debug => 0, eq => <<END);
String Dump      Total Length:       58
Offset: 0000 0000 0000 0040  Length: 55  0000 0080 0000 0080   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0037
Offset: 0000 0000 0000 0080  Length:  3  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 3938 3703

String Dump      Total Length:       59
Offset: 0000 0000 0000 0040  Length: 22  0000 00C0 0000 00C0   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0016
Offset: 0000 0000 0000 00C0  Length: 34  0000 0080 0000 0080   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 8036 3534   3332 3130 2F2E 2D2C   2B2A 2928 2726 2524   2322 2120 1F1E 1D1C   1B1A 1918 1716 4422
Offset: 0000 0000 0000 0080  Length:  3  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 3938 3703

String Dump      Total Length:       60
Offset: 0000 0000 0000 0040  Length: 23  0000 00C0 0000 00C0   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   8815 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0017
Offset: 0000 0000 0000 00C0  Length: 34  0000 0080 0000 0080   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 8036 3534   3332 3130 2F2E 2D2C   2B2A 2928 2726 2524   2322 2120 1F1E 1D1C   1B1A 1918 1716 4422
Offset: 0000 0000 0000 0080  Length:  3  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 3938 3703

END
 }

#latest:;
if (1) {                                                                        #TNasm::X86::String::insertChar
  my $c = Rb(0..255);
  my $S = CreateArena;
  my $s = $S->CreateString;

  $s->append    (V(source => $c),      K size     => 54);  $s->dump;

  $s->insertChar(V(character => 0x77), K position =>  4);  $s->dump;
  $s->insertChar(V(character => 0x88), K position =>  5);  $s->dump;
  $s->insertChar(V(character => 0x99), K position =>  6);  $s->dump;
  $s->insertChar(V(character => 0xAA), K position =>  7);  $s->dump;
  $s->insertChar(V(character => 0xBB), K position =>  8);  $s->dump;
  $s->insertChar(V(character => 0xCC), K position =>  9);  $s->dump;
  $s->insertChar(V(character => 0xDD), K position => 10);  $s->dump;
  $s->insertChar(V(character => 0xEE), K position => 11);  $s->dump;
  $s->insertChar(V(character => 0xFF), K position => 12);  $s->dump;

  ok Assemble(debug => 0, eq => <<END);
String Dump      Total Length:       54
Offset: 0000 0000 0000 0040  Length: 54  0000 0040 0000 0040   0035 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0036

String Dump      Total Length:       55
Offset: 0000 0000 0000 0040  Length: 55  0000 0040 0000 0040   3534 3332 3130 2F2E   2D2C 2B2A 2928 2726   2524 2322 2120 1F1E   1D1C 1B1A 1918 1716   1514 1312 1110 0F0E   0D0C 0B0A 0908 0706   0504 7703 0201 0037

String Dump      Total Length:       56
Offset: 0000 0000 0000 0040  Length:  5  0000 0080 0000 0080   3534 3332 3130 2F2E   2D2C 2B2A 2928 2726   2524 2322 2120 1F1E   1D1C 1B1A 1918 1716   1514 1312 1110 0F0E   0D0C 0B0A 0908 0706   0504 7703 0201 0005
Offset: 0000 0000 0000 0080  Length: 51  0000 0040 0000 0040   0000 0040 3534 3332   3130 2F2E 2D2C 2B2A   2928 2726 2524 2322   2120 1F1E 1D1C 1B1A   1918 1716 1514 1312   1110 0F0E 0D0C 0B0A   0908 0706 0504 8833

String Dump      Total Length:       57
Offset: 0000 0000 0000 0040  Length:  5  0000 0080 0000 0080   3534 3332 3130 2F2E   2D2C 2B2A 2928 2726   2524 2322 2120 1F1E   1D1C 1B1A 1918 1716   1514 1312 1110 0F0E   0D0C 0B0A 0908 0706   0504 7703 0201 0005
Offset: 0000 0000 0000 0080  Length: 52  0000 0040 0000 0040   0000 0035 3433 3231   302F 2E2D 2C2B 2A29   2827 2625 2423 2221   201F 1E1D 1C1B 1A19   1817 1615 1413 1211   100F 0E0D 0C0B 0A09   0807 0605 0499 8834

String Dump      Total Length:       58
Offset: 0000 0000 0000 0040  Length:  5  0000 0080 0000 0080   3534 3332 3130 2F2E   2D2C 2B2A 2928 2726   2524 2322 2120 1F1E   1D1C 1B1A 1918 1716   1514 1312 1110 0F0E   0D0C 0B0A 0908 0706   0504 7703 0201 0005
Offset: 0000 0000 0000 0080  Length: 53  0000 0040 0000 0040   0000 3534 3332 3130   2F2E 2D2C 2B2A 2928   2726 2524 2322 2120   1F1E 1D1C 1B1A 1918   1716 1514 1312 1110   0F0E 0D0C 0B0A 0908   0706 0504 AA99 8835

String Dump      Total Length:       59
Offset: 0000 0000 0000 0040  Length:  5  0000 0080 0000 0080   3534 3332 3130 2F2E   2D2C 2B2A 2928 2726   2524 2322 2120 1F1E   1D1C 1B1A 1918 1716   1514 1312 1110 0F0E   0D0C 0B0A 0908 0706   0504 7703 0201 0005
Offset: 0000 0000 0000 0080  Length: 54  0000 0040 0000 0040   0035 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 04BB AA99 8836

String Dump      Total Length:       60
Offset: 0000 0000 0000 0040  Length:  5  0000 0080 0000 0080   3534 3332 3130 2F2E   2D2C 2B2A 2928 2726   2524 2322 2120 1F1E   1D1C 1B1A 1918 1716   1514 1312 1110 0F0E   0D0C 0B0A 0908 0706   0504 7703 0201 0005
Offset: 0000 0000 0000 0080  Length: 55  0000 0040 0000 0040   3534 3332 3130 2F2E   2D2C 2B2A 2928 2726   2524 2322 2120 1F1E   1D1C 1B1A 1918 1716   1514 1312 1110 0F0E   0D0C 0B0A 0908 0706   0504 CCBB AA99 8837

String Dump      Total Length:       61
Offset: 0000 0000 0000 0040  Length:  5  0000 0080 0000 0080   3534 3332 3130 2F2E   2D2C 2B2A 2928 2726   2524 2322 2120 1F1E   1D1C 1B1A 1918 1716   1514 1312 1110 0F0E   0D0C 0B0A 0908 0706   0504 7703 0201 0005
Offset: 0000 0000 0000 0080  Length:  5  0000 00C0 0000 00C0   3534 3332 3130 2F2E   2D2C 2B2A 2928 2726   2524 2322 2120 1F1E   1D1C 1B1A 1918 1716   1514 1312 1110 0F0E   0D0C 0B0A 0908 0706   0504 CCBB AA99 8805
Offset: 0000 0000 0000 00C0  Length: 51  0000 0040 0000 0040   0000 0040 3534 3332   3130 2F2E 2D2C 2B2A   2928 2726 2524 2322   2120 1F1E 1D1C 1B1A   1918 1716 1514 1312   1110 0F0E 0D0C 0B0A   0908 0706 0504 DD33

String Dump      Total Length:       62
Offset: 0000 0000 0000 0040  Length:  5  0000 0080 0000 0080   3534 3332 3130 2F2E   2D2C 2B2A 2928 2726   2524 2322 2120 1F1E   1D1C 1B1A 1918 1716   1514 1312 1110 0F0E   0D0C 0B0A 0908 0706   0504 7703 0201 0005
Offset: 0000 0000 0000 0080  Length:  5  0000 00C0 0000 00C0   3534 3332 3130 2F2E   2D2C 2B2A 2928 2726   2524 2322 2120 1F1E   1D1C 1B1A 1918 1716   1514 1312 1110 0F0E   0D0C 0B0A 0908 0706   0504 CCBB AA99 8805
Offset: 0000 0000 0000 00C0  Length: 52  0000 0040 0000 0040   0000 0035 3433 3231   302F 2E2D 2C2B 2A29   2827 2625 2423 2221   201F 1E1D 1C1B 1A19   1817 1615 1413 1211   100F 0E0D 0C0B 0A09   0807 0605 04EE DD34

String Dump      Total Length:       63
Offset: 0000 0000 0000 0040  Length:  5  0000 0080 0000 0080   3534 3332 3130 2F2E   2D2C 2B2A 2928 2726   2524 2322 2120 1F1E   1D1C 1B1A 1918 1716   1514 1312 1110 0F0E   0D0C 0B0A 0908 0706   0504 7703 0201 0005
Offset: 0000 0000 0000 0080  Length:  5  0000 00C0 0000 00C0   3534 3332 3130 2F2E   2D2C 2B2A 2928 2726   2524 2322 2120 1F1E   1D1C 1B1A 1918 1716   1514 1312 1110 0F0E   0D0C 0B0A 0908 0706   0504 CCBB AA99 8805
Offset: 0000 0000 0000 00C0  Length: 53  0000 0040 0000 0040   0000 3534 3332 3130   2F2E 2D2C 2B2A 2928   2726 2524 2322 2120   1F1E 1D1C 1B1A 1918   1716 1514 1312 1110   0F0E 0D0C 0B0A 0908   0706 0504 FFEE DD35

END
 }

#latest:;
if (1) {
  my $c = Rb(0..255);
  my $S = CreateArena;   my $s = $S->CreateString;

  $s->append    (V(source    => $c),   K size     => 4); $s->dump;
  $s->insertChar(V(character => 0xFF), K position => 4); $s->dump;
  $s->insertChar(V(character => 0xEE), K position => 4); $s->dump;
  $s->len->outInDecNL;

  ok Assemble(debug => 0, eq => <<END);
String Dump      Total Length:        4
Offset: 0000 0000 0000 0040  Length:  4  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0003 0201 0004

String Dump      Total Length:        5
Offset: 0000 0000 0000 0040  Length:  5  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 FF03 0201 0005

String Dump      Total Length:        6
Offset: 0000 0000 0000 0040  Length:  6  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   00FF EE03 0201 0006

size: 6
END
 }

#latest:;
if (1) {                                                                        #TNasm::X86::String::deleteChar #TNasm::X86::String::len
  my $c = Rb(0..255);
  my $S = CreateArena;   my $s = $S->CreateString;

  $s->append    (V(source   => $c),  K size => 165); $s->dump;
  $s->deleteChar(V(position => 0x44));               $s->dump;
  $s->len->outInDecNL;

  ok Assemble(debug => 0, eq => <<END);
String Dump      Total Length:      165
Offset: 0000 0000 0000 0040  Length: 55  0000 0080 0000 00C0   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0037
Offset: 0000 0000 0000 0080  Length: 55  0000 00C0 0000 0040   6D6C 6B6A 6968 6766   6564 6362 6160 5F5E   5D5C 5B5A 5958 5756   5554 5352 5150 4F4E   4D4C 4B4A 4948 4746   4544 4342 4140 3F3E   3D3C 3B3A 3938 3737
Offset: 0000 0000 0000 00C0  Length: 55  0000 0040 0000 0080   A4A3 A2A1 A09F 9E9D   9C9B 9A99 9897 9695   9493 9291 908F 8E8D   8C8B 8A89 8887 8685   8483 8281 807F 7E7D   7C7B 7A79 7877 7675   7473 7271 706F 6E37

String Dump      Total Length:      164
Offset: 0000 0000 0000 0040  Length: 55  0000 0080 0000 00C0   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0037
Offset: 0000 0000 0000 0080  Length: 54  0000 00C0 0000 0040   406D 6C6B 6A69 6867   6665 6463 6261 605F   5E5D 5C5B 5A59 5857   5655 5453 5251 504F   4E4D 4C4B 4A49 4847   4645 4342 4140 3F3E   3D3C 3B3A 3938 3736
Offset: 0000 0000 0000 00C0  Length: 55  0000 0040 0000 0080   A4A3 A2A1 A09F 9E9D   9C9B 9A99 9897 9695   9493 9291 908F 8E8D   8C8B 8A89 8887 8685   8483 8281 807F 7E7D   7C7B 7A79 7877 7675   7473 7271 706F 6E37

size: 164
END
 }

#latest:;
if (1) {                                                                        #TNasm::X86::String::getChar
  my $c = Rb(0..255);
  my $S = CreateArena;   my $s = $S->CreateString;

  $s->append      (V(source => $c),  K size => 110); $s->dump;
  $s->getCharacter(K position => 0x44)->outNL;

  ok Assemble(debug => 0, eq => <<END);
String Dump      Total Length:      110
Offset: 0000 0000 0000 0040  Length: 55  0000 0080 0000 0080   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0037
Offset: 0000 0000 0000 0080  Length: 55  0000 0040 0000 0040   6D6C 6B6A 6968 6766   6564 6362 6160 5F5E   5D5C 5B5A 5958 5756   5554 5352 5150 4F4E   4D4C 4B4A 4948 4746   4544 4342 4140 3F3E   3D3C 3B3A 3938 3737

out: 0000 0000 0000 0044
END
 }

#latest:;
if (1) {                                                                        #TNasm::X86::String::appendVar
  my $c = Rb(0..255);
  my $a = CreateArena;   my $s = $a->CreateString;

  $s->append(V(source => Rb(1)), V(size => 1));
  Mov r15, -1;  $s->appendVar(V value => r15);
  Mov r15, +1;  $s->appendVar(V value => r15);

  Mov r15, -2;  $s->appendVar(V value => r15);
  Mov r15, +2;  $s->appendVar(V value => r15);

  Mov r15, -3;  $s->appendVar(V value => r15);

  $s->dump;

  ok Assemble(debug => 0, eq => <<END);
String Dump      Total Length:       41
Offset: 0000 0000 0000 0040  Length: 41  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 FFFF   FFFF FFFF FFFD 0000   0000 0000 0002 FFFF   FFFF FFFF FFFE 0000   0000 0000 0001 FFFF   FFFF FFFF FFFF 0129

END
 }

#latest:;
if (1) {                                                                        #TNasm::X86::Variable::setMask
  my $z = V('zero', 0);
  my $o = V('one',  1);
  my $t = V('two',  2);
  $z->setMask($o,       k7); PrintOutRegisterInHex k7;
  $z->setMask($t,       k6); PrintOutRegisterInHex k6;
  $z->setMask($o+$t,    k5); PrintOutRegisterInHex k5;
  $o->setMask($o,       k4); PrintOutRegisterInHex k4;
  $o->setMask($t,       k3); PrintOutRegisterInHex k3;
  $o->setMask($o+$t,    k2); PrintOutRegisterInHex k2;

  $t->setMask($o,       k1); PrintOutRegisterInHex k1;
  $t->setMask($t,       k0); PrintOutRegisterInHex k0;

  ok Assemble(debug => 0, eq => <<END);
    k7: 0000 0000 0000 0001
    k6: 0000 0000 0000 0003
    k5: 0000 0000 0000 0007
    k4: 0000 0000 0000 0002
    k3: 0000 0000 0000 0006
    k2: 0000 0000 0000 000E
    k1: 0000 0000 0000 0004
    k0: 0000 0000 0000 000C
END
 }

#latest:;
if (0) {                                                                        #TNasm::X86::Array::size
  my $N = 15;
  my $A = CreateArena;
  my $a = $A->CreateArray;

  $a->push(V(element, 1));  $a->pop()->outInDecNL;
  $a->push(V(element, 2));  $a->pop()->outInDecNL;
  $a->size()->outInDecNL;

  ok Assemble(debug => 0, eq => <<END);
element: 1
element: 2
size: 0
END
 }

#latest:;
if (0) {                                                                        #TNasm::X86::Array::size
  my $N = 15;
  my $A = CreateArena;
  my $a = $A->CreateArray;
  my $b = $A->CreateArray;

  my $push = sub                                                                # Push an element onto an array
   {my ($array, $element) = @_;                                                 # Array, Element
    my $s = Subroutine2
     {my ($p, $s, $sub) = @_;                                                   # Parameters, structures, subroutine definition
      $$s{array}->push($$p{element});
     } parameters=>[qw(element)], structures=>{array=>$array}, name=>"push";

    $s->call(parameters=>{element=>$element}, structures=>{array=>$array});
   };

  my $pop = sub                                                                 # Push an element onto an array
   {my ($array) = @_;                                                           # Array, Element
    my $s = Subroutine2
     {my ($p, $s, $sub) = @_;                                                   # Parameters, structures, subroutine definition
      $$p{element}->copy($$s{array}->pop);
     } parameters=>[qw(element)], structures=>{array=>$b}, name=>"pop";

    $s->call(parameters => {element => my $e = V(element => 0)},
             structures => {array   => $array});
    $e
   };

  &$push($a, K element => 1);
  &$push($a, K element => 3);
  &$push($b, K element => 2);
  &$push($b, K element => 4);
  &$push($a, K element => 5);

  $a->size()->outInDecNL;
  $b->size()->outInDecNL;

  &$pop($a)->outNL;
  &$pop($b)->outNL;
  &$pop($a)->outNL;
  &$pop($b)->outNL;
  &$pop($a)->outNL;

  ok Assemble(debug => 0, eq => <<END);
size: 3
size: 2
element: 0000 0000 0000 0005
element: 0000 0000 0000 0004
element: 0000 0000 0000 0003
element: 0000 0000 0000 0002
element: 0000 0000 0000 0001
END
 }

#latest:;
if (0) {                                                                        #TNasm::X86::Array::size
  my $N = 15;
  my $A = CreateArena;
  my $a = $A->CreateArray;

  $a->push(V(element, $_)) for 1..$N;

  $a->size()->outInDecNL;

  K(loop, $N)->for(sub
   {my ($start, $end, $next) = @_;
    my $l = $a->size;
    If $l == 0, Then {Jmp $end};
    my $e = $a->pop;
    $e->outNL;
   });

  ok Assemble(debug => 0, eq => <<END);
size: 15
element: 0000 0000 0000 000F
element: 0000 0000 0000 000E
element: 0000 0000 0000 000D
element: 0000 0000 0000 000C
element: 0000 0000 0000 000B
element: 0000 0000 0000 000A
element: 0000 0000 0000 0009
element: 0000 0000 0000 0008
element: 0000 0000 0000 0007
element: 0000 0000 0000 0006
element: 0000 0000 0000 0005
element: 0000 0000 0000 0004
element: 0000 0000 0000 0003
element: 0000 0000 0000 0002
element: 0000 0000 0000 0001
END
 }

#latest:;
if (0) {                                                                        # Arrays doubled
  my $A = CreateArena;  my $a = $A->CreateArray;
  my $B = CreateArena;  my $b = $B->CreateArray;

  $a->push(V(element, $_)), $b->push(K element, $_ + 0x11) for 1..15;
  $a->push(V(element, $_)), $b->push(K element, $_ + 0x11) for 0xff;
  $a->push(V(element, $_)), $b->push(K element, $_ + 0x11) for 17..31;
  $a->push(V(element, $_)), $b->push(K element, $_ + 0x11) for 0xee;
  $a->push(V(element, $_)), $b->push(K element, $_ + 0x11) for 33..36;

  $A->dump("AAAA");
  $B->dump("BBBB");

  $_->size()->outInDecNL for $a, $b;

  ok Assemble(debug => 0, eq => <<END);
AAAA
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | 24__ ____ 80__ ____  C0__ ____ __01 ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | 01__ ____ 02__ ____  03__ ____ 04__ ____  05__ ____ 06__ ____  07__ ____ 08__ ____  09__ ____ 0A__ ____  0B__ ____ 0C__ ____  0D__ ____ 0E__ ____  0F__ ____ FF__ ____
0000 0000 0000 00C0 | 11__ ____ 12__ ____  13__ ____ 14__ ____  15__ ____ 16__ ____  17__ ____ 18__ ____  19__ ____ 1A__ ____  1B__ ____ 1C__ ____  1D__ ____ 1E__ ____  1F__ ____ EE__ ____
BBBB
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | 24__ ____ 80__ ____  C0__ ____ __01 ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | 12__ ____ 13__ ____  14__ ____ 15__ ____  16__ ____ 17__ ____  18__ ____ 19__ ____  1A__ ____ 1B__ ____  1C__ ____ 1D__ ____  1E__ ____ 1F__ ____  20__ ____ 1001 ____
0000 0000 0000 00C0 | 22__ ____ 23__ ____  24__ ____ 25__ ____  26__ ____ 27__ ____  28__ ____ 29__ ____  2A__ ____ 2B__ ____  2C__ ____ 2D__ ____  2E__ ____ 2F__ ____  30__ ____ FF__ ____
size: 36
size: 36
END
 }

#latest:;
if (0) {                                                                        #TNasm::X86::Array::push #TNasm::X86::Array::pop #TNasm::X86::Array::put #TNasm::X86::Array::get
  my $c = Rb(0..255);
  my $A = CreateArena;  my $a = $A->CreateArray;
  my $l = V(limit, 15);
  my $L = $l + 5;

  my sub put                                                                    # Put a constant or a variable
   {my ($e) = @_;
    $a->push(ref($e) ? $e : V($e, $e));
   };

  my sub get                                                                    # Get a constant or a variable
   {my ($i) = @_;
    my $e = $a->get(my $v = ref($i) ? $i : K('index', $i));
    $v->out("index: ", "  "); $e->outNL;
   };

  $l->for(sub                                                                   # Loop to the limit pushing
   {my ($index, $start, $next, $end) = @_;
    put($index+1);
   });

  $l->for(sub                                                                   # Loop to the limit getting
   {my ($index, $start, $next, $end) = @_;
    get($index);
   });

  put(16);
  get(15);

  $L->for(sub
   {my ($index, $start, $next, $end) = @_;
    put($index+$l+2);
   });

  $L->for(sub
   {my ($index, $start, $next, $end) = @_;
    get($index + $l + 1);
   });

  if (1)
   {$a->put(my $i = V('index',  9), my $e = V(element, 0xFFF9));
    get(9);
   }

  if (1)
   {$a->put(my $i = V('index', 19), my $e = V(element, 0xEEE9));
    get(19);
   }

  ($l+$L+1)->for(sub
   {my ($i, $start, $next, $end) = @_;
    my $e = $a->pop;
    $e->outNL;
   });

  V(limit, 38)->for(sub                                                         # Push using a loop and reusing the freed space
   {my ($index, $start, $next, $end) = @_;
    $a->push($index*2);
   });

  V(limit, 38)->for(sub                                                         # Push using a loop and reusing the freed space
   {my ($index, $start, $next, $end) = @_;
    $a->pop->outNL;
   });

  $a->dump;

  ok Assemble(debug => 0, eq => <<END);
index: 0000 0000 0000 0000  element: 0000 0000 0000 0001
index: 0000 0000 0000 0001  element: 0000 0000 0000 0002
index: 0000 0000 0000 0002  element: 0000 0000 0000 0003
index: 0000 0000 0000 0003  element: 0000 0000 0000 0004
index: 0000 0000 0000 0004  element: 0000 0000 0000 0005
index: 0000 0000 0000 0005  element: 0000 0000 0000 0006
index: 0000 0000 0000 0006  element: 0000 0000 0000 0007
index: 0000 0000 0000 0007  element: 0000 0000 0000 0008
index: 0000 0000 0000 0008  element: 0000 0000 0000 0009
index: 0000 0000 0000 0009  element: 0000 0000 0000 000A
index: 0000 0000 0000 000A  element: 0000 0000 0000 000B
index: 0000 0000 0000 000B  element: 0000 0000 0000 000C
index: 0000 0000 0000 000C  element: 0000 0000 0000 000D
index: 0000 0000 0000 000D  element: 0000 0000 0000 000E
index: 0000 0000 0000 000E  element: 0000 0000 0000 000F
index: 0000 0000 0000 000F  element: 0000 0000 0000 0010
index: 0000 0000 0000 0010  element: 0000 0000 0000 0011
index: 0000 0000 0000 0011  element: 0000 0000 0000 0012
index: 0000 0000 0000 0012  element: 0000 0000 0000 0013
index: 0000 0000 0000 0013  element: 0000 0000 0000 0014
index: 0000 0000 0000 0014  element: 0000 0000 0000 0015
index: 0000 0000 0000 0015  element: 0000 0000 0000 0016
index: 0000 0000 0000 0016  element: 0000 0000 0000 0017
index: 0000 0000 0000 0017  element: 0000 0000 0000 0018
index: 0000 0000 0000 0018  element: 0000 0000 0000 0019
index: 0000 0000 0000 0019  element: 0000 0000 0000 001A
index: 0000 0000 0000 001A  element: 0000 0000 0000 001B
index: 0000 0000 0000 001B  element: 0000 0000 0000 001C
index: 0000 0000 0000 001C  element: 0000 0000 0000 001D
index: 0000 0000 0000 001D  element: 0000 0000 0000 001E
index: 0000 0000 0000 001E  element: 0000 0000 0000 001F
index: 0000 0000 0000 001F  element: 0000 0000 0000 0020
index: 0000 0000 0000 0020  element: 0000 0000 0000 0021
index: 0000 0000 0000 0021  element: 0000 0000 0000 0022
index: 0000 0000 0000 0022  element: 0000 0000 0000 0023
index: 0000 0000 0000 0023  element: 0000 0000 0000 0024
index: 0000 0000 0000 0009  element: 0000 0000 0000 FFF9
index: 0000 0000 0000 0013  element: 0000 0000 0000 EEE9
element: 0000 0000 0000 0024
element: 0000 0000 0000 0023
element: 0000 0000 0000 0022
element: 0000 0000 0000 0021
element: 0000 0000 0000 0020
element: 0000 0000 0000 001F
element: 0000 0000 0000 001E
element: 0000 0000 0000 001D
element: 0000 0000 0000 001C
element: 0000 0000 0000 001B
element: 0000 0000 0000 001A
element: 0000 0000 0000 0019
element: 0000 0000 0000 0018
element: 0000 0000 0000 0017
element: 0000 0000 0000 0016
element: 0000 0000 0000 0015
element: 0000 0000 0000 EEE9
element: 0000 0000 0000 0013
element: 0000 0000 0000 0012
element: 0000 0000 0000 0011
element: 0000 0000 0000 0010
element: 0000 0000 0000 000F
element: 0000 0000 0000 000E
element: 0000 0000 0000 000D
element: 0000 0000 0000 000C
element: 0000 0000 0000 000B
element: 0000 0000 0000 FFF9
element: 0000 0000 0000 0009
element: 0000 0000 0000 0008
element: 0000 0000 0000 0007
element: 0000 0000 0000 0006
element: 0000 0000 0000 0005
element: 0000 0000 0000 0004
element: 0000 0000 0000 0003
element: 0000 0000 0000 0002
element: 0000 0000 0000 0001
element: 0000 0000 0000 004A
element: 0000 0000 0000 0048
element: 0000 0000 0000 0046
element: 0000 0000 0000 0044
element: 0000 0000 0000 0042
element: 0000 0000 0000 0040
element: 0000 0000 0000 003E
element: 0000 0000 0000 003C
element: 0000 0000 0000 003A
element: 0000 0000 0000 0038
element: 0000 0000 0000 0036
element: 0000 0000 0000 0034
element: 0000 0000 0000 0032
element: 0000 0000 0000 0030
element: 0000 0000 0000 002E
element: 0000 0000 0000 002C
element: 0000 0000 0000 002A
element: 0000 0000 0000 0028
element: 0000 0000 0000 0026
element: 0000 0000 0000 0024
element: 0000 0000 0000 0022
element: 0000 0000 0000 0020
element: 0000 0000 0000 001E
element: 0000 0000 0000 001C
element: 0000 0000 0000 001A
element: 0000 0000 0000 0018
element: 0000 0000 0000 0016
element: 0000 0000 0000 0014
element: 0000 0000 0000 0012
element: 0000 0000 0000 0010
element: 0000 0000 0000 000E
element: 0000 0000 0000 000C
element: 0000 0000 0000 000A
element: 0000 0000 0000 0008
element: 0000 0000 0000 0006
element: 0000 0000 0000 0004
element: 0000 0000 0000 0002
element: 0000 0000 0000 0000
array
Size: 0000 0000 0000 0000   zmm31: 0000 001C 0000 001A   0000 0018 0000 0016   0000 0014 0000 0012   0000 0010 0000 000E   0000 000C 0000 000A   0000 0008 0000 0006   0000 0004 0000 0002   0000 0000 0000 0000
END
 }

#latest:;
if (0) {                                                                        #TNasm::X86::Arena::allocBlock #TNasm::X86::Arena::freeZmmBlock
  my $a = CreateArena;
  for (1..4)
   {my $b1 = $a->allocZmmBlock; $a->dump("AAAA");
    my $b2 = $a->allocZmmBlock; $a->dump("BBBB");
    $a->freeZmmBlock($b2);      $a->dump("CCCC");
    $a->freeZmmBlock($b1);      $a->dump("DDDD");
   }
  ok Assemble(debug => 0, eq => <<END);
AAAA
Arena     Size:     4096    Used:      128
0000 0000 0000 0000 | __10 ____ ____ ____  80__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
BBBB
Arena     Size:     4096    Used:      192
0000 0000 0000 0000 | __10 ____ ____ ____  C0__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
CCCC
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  C0__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ __01 ____
DDDD
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  C0__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 80__ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ __01 ____
AAAA
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  C0__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ __01 ____
BBBB
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  C0__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ __01 ____
CCCC
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  C0__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ __01 ____
DDDD
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  C0__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 80__ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ __01 ____
AAAA
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  C0__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ __01 ____
BBBB
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  C0__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ __01 ____
CCCC
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  C0__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ __01 ____
DDDD
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  C0__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 80__ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ __01 ____
AAAA
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  C0__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ __01 ____
BBBB
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  C0__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ __01 ____
CCCC
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  C0__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ __01 ____
DDDD
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  C0__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 80__ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ __01 ____
END
 }

#latest:;

if (0) {                                                                        #TNasm::X86::Array::push
  my $c = Rb(0..255);
  my $A = CreateArena;  my $a = $A->CreateArray;

  my sub put
   {my ($e) = @_;
    $a->push(V($e, $e));
   };

  my sub get
   {my ($i) = @_;                                                               # Parameters
    my $e = $a->get(my $v = V('index', $i));
    $v->out; PrintOutString "  "; $e->outNL;
   };

  put($_) for 1..15;  get(15);

  ok Assemble(debug => 2, eq => <<END);
Index out of bounds on get from array, Index: 0000 0000 0000 000F  Size: 0000 0000 0000 000F
END
 }

#latest:
if (1) {                                                                        #TExtern #TLink #TCallC
  my $format = Rs "Hello %s\n";
  my $data   = Rs "World";

  Extern qw(printf exit malloc strcpy); Link 'c';

  CallC 'malloc', length($format)+1;
  Mov r15, rax;
  CallC 'strcpy', r15, $format;
  CallC 'printf', r15, $data;
  CallC 'exit', 0;

  ok Assemble eq => <<END;
Hello World
END
 }

#latest:
if (1) {
  my $a = Rb((reverse 0..16)x16);
  my $b = Rb((        0..16)x16);
  Mov rax, $a;  Vmovdqu8 zmm0, "[rax]";
  Mov rax, $b;  Vmovdqu8 zmm1, "[rax]";
  Vpcmpeqb k0, zmm0, zmm1;

  Kmovq rax, k0; Popcnt rax, rax;
  PrintOutRegisterInHex zmm0, zmm1, k0, rax;

  ok Assemble eq => <<END;
  zmm0: 0405 0607 0809 0A0B   0C0D 0E0F 1000 0102   0304 0506 0708 090A   0B0C 0D0E 0F10 0001   0203 0405 0607 0809   0A0B 0C0D 0E0F 1000   0102 0304 0506 0708   090A 0B0C 0D0E 0F10
  zmm1: 0C0B 0A09 0807 0605   0403 0201 0010 0F0E   0D0C 0B0A 0908 0706   0504 0302 0100 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0010   0F0E 0D0C 0B0A 0908   0706 0504 0302 0100
    k0: 0800 0400 0200 0100
   rax: 0000 0000 0000 0004
END
 }

#latest:
if (1) {                                                                        # Insert key for Tree
# 0000000001111111 A Length    = k7
# .........1111000 B Greater   = k6
# 0000000001111000 C =  A&B    = k5
# 0000000000000111 D = !C&A    = k4
# 0000000011110000 E Shift left 1 C = K5
# 0000000011110111 F Want expand mask =   E&D =  k5&K4 ->k5
# 0000000000001000 G Want broadcast mask !F&A =  K5!&k7->k6

  Mov eax, 0x007f; Kmovw k7, eax;
  Mov esi, 0x0F78; Kmovw k6, esi;
  Kandw    k5, k6, k7;
  Kandnw   k4, k5, k7;
  Kshiftlw k5, k5, 1;
  Korw     k5, k4, k5;
  Kandnw   k6, k5, k7;
  PrintOutRegisterInHex k7, k5, k6;

  ok Assemble eq => <<END;
    k7: 0000 0000 0000 007F
    k5: 0000 0000 0000 00F7
    k6: 0000 0000 0000 0008
END
 }

#latest:
if (1) {                                                                        #TConvertUtf8ToUtf32
  my ($out, $size, $fail) = (V(out), V(size), V('fail'));

  my $Chars = Rb(0x24, 0xc2, 0xa2, 0xc9, 0x91, 0xE2, 0x82, 0xAC, 0xF0, 0x90, 0x8D, 0x88);
  my $chars = V(chars, $Chars);

  GetNextUtf8CharAsUtf32 $chars+0, $out, $size, $fail;                          # Dollar               UTF-8 Encoding: 0x24                UTF-32 Encoding: 0x00000024
  $out->out('out1 : ');     $size->outNL(' size : ');

  GetNextUtf8CharAsUtf32 $chars+1, $out, $size, $fail;                          # Cents                UTF-8 Encoding: 0xC2 0xA2           UTF-32 Encoding: 0x000000a2
  $out->out('out2 : ');     $size->outNL(' size : ');

  GetNextUtf8CharAsUtf32 $chars+3, $out, $size, $fail;                          # Alpha                UTF-8 Encoding: 0xC9 0x91           UTF-32 Encoding: 0x00000251
  $out->out('out3 : ');     $size->outNL(' size : ');

  GetNextUtf8CharAsUtf32 $chars+5, $out, $size, $fail;                          # Euro                 UTF-8 Encoding: 0xE2 0x82 0xAC      UTF-32 Encoding: 0x000020AC
  $out->out('out4 : ');     $size->outNL(' size : ');

  GetNextUtf8CharAsUtf32 $chars+8, $out, $size, $fail;                          # Gothic Letter Hwair  UTF-8 Encoding  0xF0 0x90 0x8D 0x88 UTF-32 Encoding: 0x00010348
  $out->out('out5 : ');     $size->outNL(' size : ');

  my $statement = qq(𝖺\n 𝑎𝑠𝑠𝑖𝑔𝑛 【【𝖻 𝐩𝐥𝐮𝐬 𝖼】】\nAAAAAAAA);                        # A sample sentence to parse

  my $s = K(statement, Rutf8($statement));
  my $l = StringLength $s;

  my $address = AllocateMemory $l;                                              # Allocate enough memory for a copy of the string
  CopyMemory($s, $address, $l);

  GetNextUtf8CharAsUtf32 $address, $out, $size, $fail;
  $out->out('outA : ');     $size->outNL(' size : ');

  GetNextUtf8CharAsUtf32 $address+4, $out, $size, $fail;
  $out->out('outB : ');     $size->outNL(' size : ');

  GetNextUtf8CharAsUtf32 $address+5, $out, $size, $fail;
  $out->out('outC : ');     $size->outNL(' size : ');

  GetNextUtf8CharAsUtf32 $address+30, $out, $size, $fail;
  $out->out('outD : ');     $size->outNL(' size : ');

  GetNextUtf8CharAsUtf32 $address+35, $out, $size, $fail;
  $out->out('outE : ');     $size->outNL(' size : ');

  $address->printOutMemoryInHexNL($l);

  ok Assemble(debug => 0, eq => <<END);
out1 : 0000 0000 0000 0024 size : 0000 0000 0000 0001
out2 : 0000 0000 0000 00A2 size : 0000 0000 0000 0002
out3 : 0000 0000 0000 0251 size : 0000 0000 0000 0002
out4 : 0000 0000 0000 20AC size : 0000 0000 0000 0003
out5 : 0000 0000 0001 0348 size : 0000 0000 0000 0004
outA : 0000 0000 0001 D5BA size : 0000 0000 0000 0004
outB : 0000 0000 0000 000A size : 0000 0000 0000 0001
outC : 0000 0000 0000 0020 size : 0000 0000 0000 0001
outD : 0000 0000 0000 0020 size : 0000 0000 0000 0001
outE : 0000 0000 0000 0010 size : 0000 0000 0000 0002
F09D 96BA 0A20 F09D  918E F09D 91A0 F09D  91A0 F09D 9196 F09D  9194 F09D 919B 20E3  8090 E380 90F0 9D96  BB20 F09D 90A9 F09D  90A5 F09D 90AE F09D  90AC 20F0 9D96 BCE3  8091 E380 910A 4141  4141 4141 4141 0000
END
 }

#latest:
if (1) {                                                                        #TLoadBitsIntoMaskRegister
  for (0..7)
   {ClearRegisters "k$_";
    K($_,$_)->setMaskBit("k$_");
    PrintOutRegisterInHex "k$_";
   }

  ClearRegisters k7;
  LoadBitsIntoMaskRegister(7, '1010', -4, +4, -2, +2, -1, +1, -1, +1);
  PrintOutRegisterInHex "k7";

  ok Assemble(debug => 0, eq => <<END);
    k0: 0000 0000 0000 0001
    k1: 0000 0000 0000 0002
    k2: 0000 0000 0000 0004
    k3: 0000 0000 0000 0008
    k4: 0000 0000 0000 0010
    k5: 0000 0000 0000 0020
    k6: 0000 0000 0000 0040
    k7: 0000 0000 0000 0080
    k7: 0000 0000 000A 0F35
END
 }

#latest:
if (1) {                                                                        #TInsertZeroIntoRegisterAtPoint #TInsertOneIntoRegisterAtPoint
  Mov r15, 0x100;                                                               # Given a register with a single one in it indicating the desired position,
  Mov r14, 0xFFDC;                                                              # Insert a zero into the register at that position shifting the bits above that position up left one to make space for the new zero.
  Mov r13, 0xF03F;
  PrintOutRegisterInHex         r14, r15;
  InsertZeroIntoRegisterAtPoint r15, r14;
  PrintOutRegisterInHex r14;
  Or r14, r15;                                                                  # Replace the inserted zero with a one
  PrintOutRegisterInHex r14;
  InsertOneIntoRegisterAtPoint r15, r13;
  PrintOutRegisterInHex r13;
  ok Assemble(debug => 0, eq => <<END);
   r14: 0000 0000 0000 FFDC
   r15: 0000 0000 0000 0100
   r14: 0000 0000 0001 FEDC
   r14: 0000 0000 0001 FFDC
   r13: 0000 0000 0001 E13F
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::setOrClearTreeBits
  my $b = CreateArena;
  my $t = $b->CreateTree;

  Mov r15, 8;
  $t->setTreeBit  (31, r15); PrintOutRegisterInHex 31;
  $t->isTree      (31, r15); PrintOutZF;

  Mov r15, 16;
  $t->isTree      (31, r15); PrintOutZF;
  $t->setTreeBit  (31, r15); PrintOutRegisterInHex 31;
  $t->clearTreeBit(31, r15); PrintOutRegisterInHex 31;
  $t->isTree      (31, r15); PrintOutZF;

  ok Assemble(debug => 0, eq => <<END);
 zmm31: 0000 0000 0008 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
ZF=0
ZF=1
 zmm31: 0000 0000 0018 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
 zmm31: 0000 0000 0008 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
ZF=0
END
 }

#latest:
if (00) {                                                                        #TNasm::X86::Tree::insertTreeAndReload #TNasm::X86::Tree::Reload  #TNasm::X86::Tree::findAndReload
  my $L = K(loop, 4);
  my $b = CreateArena;
  my $T = $b->CreateTree;
  my $t = $T->describeTreereload;

  $L->for(sub
   {my ($i, $start, $next, $end) = @_;
    $t->insertTreeAndReload($i);
    $t->first->outNL;
   });

  $t->insert($L, $L*2);

  my $f = $T->reload;
  $L->for(sub
   {my ($i, $start, $next, $end) = @_;
    $f->findAndReload($i);
    $i->out('i: '); $f->found->out('  f: '); $f->data->out('  d: '); $f->subTree->outNL('  s: ');
   });
  $f->find($L);
  $L->out('N: '); $f->found->out('  f: '); $f->data->out('  d: ');   $f->subTree->outNL('  s: ');

  ok Assemble(debug => 0, eq => <<END);
first: 0000 0000 0000 0098
first: 0000 0000 0000 0118
first: 0000 0000 0000 0198
first: 0000 0000 0000 0218
i: 0000 0000 0000 0000  f: 0000 0000 0000 0001  d: 0000 0000 0000 0098  s: 0000 0000 0000 0001
i: 0000 0000 0000 0001  f: 0000 0000 0000 0001  d: 0000 0000 0000 0118  s: 0000 0000 0000 0001
i: 0000 0000 0000 0002  f: 0000 0000 0000 0001  d: 0000 0000 0000 0198  s: 0000 0000 0000 0001
i: 0000 0000 0000 0003  f: 0000 0000 0000 0001  d: 0000 0000 0000 0218  s: 0000 0000 0000 0001
N: 0000 0000 0000 0004  f: 0000 0000 0000 0001  d: 0000 0000 0000 0008  s: 0000 0000 0000 0000
END
 }

#latest:
if (1) {                                                                        # Print empty tree
  my $b = CreateArena;
  my $t = $b->CreateTree;
  $t->dump("AAAA");

  ok Assemble(debug => 0, eq => <<END);
AAAA
- empty
END
 }

#latest:
if (0) {                                                                        # An example of using sigaction in x86 and x64 assembler code.  Linux on x86 requires not only a signal handler but a signal trampoline.  The following code shows how to set up a signal and its associated trampoline using sigaction or rt_sigaction.
  my $end   = Label;
  Jmp $end;                                                                     # Jump over subroutine definition
  my $start = SetLabel;
  Enter 0, 0;                                                                   # Inline code of signal handler
  Mov r15, rbp;                                                                 # Preserve the new stack frame
  Mov rbp, "[rbp]";                                                             # Restore our last stack frame
  PrintOutTraceBack '';                                                         # Print our trace back
  Mov rbp, r15;                                                                 # Restore supplied stack frame
  Exit(0);                                                                      # Exit so we do not trampoline. Exit with code zero to show that the program is functioning correctly, else L<Assemble> will report an error.
  Leave;
  Ret;
  SetLabel $end;

  Mov r15, 0;                                                                   # Push sufficient zeros onto the stack to make a struct sigaction as described in: https://www.man7.org/linux/man-pages/man2/sigaction.2.html
  Push r15 for 1..16;

  Mov r15, $start;                                                              # Actual signal handler
  Mov "[rsp]", r15;                                                             # Show as signal handler
  Mov "[rsp+0x10]", r15;                                                        # Add as trampoline as well - which is fine because we exit in the handler so this will never be called
  Mov r15, 0x4000000;                                                           # Mask to show we have a trampoline which is, apparently, required on x86
  Mov "[rsp+0x8]", r15;                                                         # Confirm we have a trampoline

  Mov rax, 13;                                                                  # Sigaction from "kill -l"
  Mov rdi, 11;                                                                  # Confirmed SIGSEGV = 11 from kill -l and tracing with sde64
  Mov rsi, rsp;                                                                 # Sigaction structure on stack
  Mov rdx, 0;                                                                   # Confirmed by trace
  Mov r10, 8;                                                                   # Found by tracing "signal.c" with sde64 it is the width of the signal set and mask. "signal.c" is reproduced below.
  Syscall;
  Add rsp, 128;

  my $s = Subroutine                                                            # Subroutine that will cause an error to occur to force a trace back to be printed
   {Mov r15, 0;
    Mov r15, "[r15]";                                                           # Try to read an unmapped memory location
   } [qw(in)], name => 'sub that causes a segv';                                # The name that will appear in the trace back

  $s->call(K(in, 42));

  ok Assemble(debug => 0, keep2 => 'signal', emulator=>0, eq => <<END);         # Cannot use the emulator because it does not understand signals

Subroutine trace back, depth:  1
0000 0000 0000 002A    sub that causes a segv

END

# /var/isde/sde64 -mix -ptr-check -debugtrace -- ./signal
##include <stdlib.h>
##include <stdio.h>
##include <signal.h>
##include <string.h>
##include <unistd.h>
#
#void handle_sigint(int sig)
# {exit(sig);
# }
#
#int main(void)
# {struct sigaction s;
#  memset(&s, 0, sizeof(s));
#  s.sa_sigaction = (void *)handle_sigint;
#
#  long a = 0xabcdef;
#  sigaction(SIGSEGV, &s, 0);
#  long *c = 0; *c = a;
# }
#
# gcc -finput-charset=UTF-8 -fmax-errors=7 -rdynamic -Wall -Wextra -Wno-unused-function -o signal signal.c  && /var/isde/sde64 -mix -ptr-check -debugtrace  -- ./signal; echo $?;
 }

#latest:
if (0) {                                                                        #TOnSegv
  OnSegv();                                                                     # Request a trace back followed by exit on a segv signal.

  my $t = Subroutine                                                            # Subroutine that will cause an error to occur to force a trace back to be printed
   {Mov r15, 0;
    Mov r15, "[r15]";                                                           # Try to read an unmapped memory location
   } [qw(in)], name => 'sub that causes a segv';                                # The name that will appear in the trace back

  $t->call(K(in, 42));

  ok Assemble(debug => 0, keep2 => 'signal', emulator=>0, eq => <<END);         # Cannot use the emulator because it does not understand signals

Subroutine trace back, depth:  1
0000 0000 0000 002A    sub that causes a segv

END
 }

#latest:
if (1) {                                                                        # R11 being disturbed by syscall 1
  Push 0x0a61;                                                                  # A followed by new line on the stack
  Mov  rax, rsp;
  Mov  rdx, 2;                                                                  # Length of string
  Mov  rsi, rsp;                                                                # Address of string
  Mov  rax, 1;                                                                  # Write
  Mov  rdi, 1;                                                                  # File descriptor
  Syscall;
  Pushfq;
  Pop rax;
  PrintOutRegisterInHex rax, r11;
  ok Assemble(debug => 0, keep2=>'z', emulator => 0, eq => <<END);
a
   rax: 0000 0000 0000 0202
   r11: 0000 0000 0000 0212
END
 }

#latest:
if (1) {                                                                        # Print the utf8 string corresponding to a lexical item
  PushR zmm0, zmm1, rax, r14, r15;
  Sub rsp, RegisterSize xmm0;;
  Mov "dword[rsp+0*4]", 0x0600001A;
  Mov "dword[rsp+1*4]", 0x0600001B;
  Mov "dword[rsp+2*4]", 0x05000001;
  Mov "dword[rsp+3*4]", 0x0600001B;
  Vmovdqu8 zmm0, "[rsp]";
  Add rsp, RegisterSize zmm0;

  Pextrw rax,  xmm0, 1;                                                         # Extract lexical type of first element
  Vpbroadcastw zmm1, ax;                                                        # Broadcast
  Vpcmpeqw k0, zmm0, zmm1;                                                      # Check extent of first lexical item up to 16
  Shr rax, 8;                                                                   # Lexical type in lowest byte

  Mov r15, 0x55555555;                                                          # Set odd positions to one where we know the match will fail
  Kmovq k1, r15;
  Korq k2, k0, k1;                                                              # Fill in odd positions

  Kmovq r15, k2;
  Not r15;                                                                      # Swap zeroes and ones
  Tzcnt r14, r15;                                                               # Trailing zero count is a factor two too big
  Shr r14, 1;                                                                   # Normalized count of number of characters int name

  Mov r15, 0xffff;                                                              # Zero out lexical type
  Vpbroadcastd zmm1, r15d;                                                      # Broadcast
  Vpandd zmm1, zmm0, zmm1;                                                      # Remove lexical type to leave index into alphabet

  Cmp rax, 6;                                                                   # Test for variable
  IfEq
  Then
   {my $va = Rutf8 "\x{1D5D4}\x{1D5D5}\x{1D5D6}\x{1D5D7}\x{1D5D8}\x{1D5D9}\x{1D5DA}\x{1D5DB}\x{1D5DC}\x{1D5DD}\x{1D5DE}\x{1D5DF}\x{1D5E0}\x{1D5E1}\x{1D5E2}\x{1D5E3}\x{1D5E4}\x{1D5E5}\x{1D5E6}\x{1D5E7}\x{1D5E8}\x{1D5E9}\x{1D5EA}\x{1D5EB}\x{1D5EC}\x{1D5ED}\x{1D5EE}\x{1D5EF}\x{1D5F0}\x{1D5F1}\x{1D5F2}\x{1D5F3}\x{1D5F4}\x{1D5F5}\x{1D5F6}\x{1D5F7}\x{1D5F8}\x{1D5F9}\x{1D5FA}\x{1D5FB}\x{1D5FC}\x{1D5FD}\x{1D5FE}\x{1D5FF}\x{1D600}\x{1D601}\x{1D602}\x{1D603}\x{1D604}\x{1D605}\x{1D606}\x{1D607}\x{1D756}\x{1D757}\x{1D758}\x{1D759}\x{1D75A}\x{1D75B}\x{1D75C}\x{1D75D}\x{1D75E}\x{1D75F}\x{1D760}\x{1D761}\x{1D762}\x{1D763}\x{1D764}\x{1D765}\x{1D766}\x{1D767}\x{1D768}\x{1D769}\x{1D76A}\x{1D76B}\x{1D76C}\x{1D76D}\x{1D76E}\x{1D76F}\x{1D770}\x{1D771}\x{1D772}\x{1D773}\x{1D774}\x{1D775}\x{1D776}\x{1D777}\x{1D778}\x{1D779}\x{1D77A}\x{1D77B}\x{1D77C}\x{1D77D}\x{1D77E}\x{1D77F}\x{1D780}\x{1D781}\x{1D782}\x{1D783}\x{1D784}\x{1D785}\x{1D786}\x{1D787}\x{1D788}\x{1D789}\x{1D78A}\x{1D78B}\x{1D78C}\x{1D78D}\x{1D78E}\x{1D78F}";
    PushR zmm1;
    V(loop)->getReg(r14)->for(sub                                               # Write each letter out from its position on the stack
     {my ($index, $start, $next, $end) = @_;                                    # Execute body
      $index->setReg(r14);                                                      # Index stack
      ClearRegisters r15;
      Mov r15b, "[rsp+4*r14]";                                                  # Load alphabet offset from stack
      Shl r15, 2;                                                               # Each letter is 4 bytes wide in utf8
      Mov r14, $va;                                                             # Alphabet address
      Mov r14d, "[r14+r15]";                                                    # Alphabet letter as utf8
      PushR r14;                                                                # Utf8 is on the stack and it is 4 bytes wide
      Mov rax, rsp;
      Mov rdi, 4;
      PrintOutMemory;                                                           # Print letter from stack
      PopR;
     });
    PrintOutNL;
   };

  PopR;

  ok Assemble(debug => 0, eq => "𝗮𝗯\n");
 }

#latest:
if (1) {                                                                        #TPrintOutUtf8Char
  my $u = Rd(convertUtf32ToUtf8LE(ord('α')));
  Mov rax, $u;
  PrintOutUtf8Char;
  PrintOutNL;

  ok Assemble(debug => 0, trace => 0, eq => <<END);
α
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Variable::outZeroString
  my $s = Rutf8 '𝝰𝝱𝝲𝝳';
  V(address, $s)->outCStringNL;

  ok Assemble(debug => 0, trace => 0, eq => <<END);
𝝰𝝱𝝲𝝳
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Variable::printOutMemoryInHexNL
  my $u = Rd(ord('𝝰'), ord('𝝱'), ord('𝝲'), ord('𝝳'));
  Mov rax, $u;
  my $address = V(address)->getReg(rax);
  $address->printOutMemoryInHexNL(K(size, 16));

  ok Assemble(debug => 0, trace => 0, eq => <<END);
70D7 0100 71D7 0100  72D7 0100 73D7 0100
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Variable::printOutMemoryInHexNL
  my $v = V(var, 2);

  If  $v == 0, Then {Mov rax, 0},
  Ef {$v == 1} Then {Mov rax, 1},
  Ef {$v == 2} Then {Mov rax, 2},
               Else {Mov rax, 3};
  PrintOutRegisterInHex rax;
  ok Assemble(debug => 0, trace => 0, eq => <<END);
   rax: 0000 0000 0000 0002
END
 }

#latest:
if (1) {                                                                        #TloadRegFromMm #TsaveRegIntoMm
  Mov rax, 1; SaveRegIntoMm(zmm0, 0, rax);
  Mov rax, 2; SaveRegIntoMm(zmm0, 1, rax);
  Mov rax, 3; SaveRegIntoMm(zmm0, 2, rax);
  Mov rax, 4; SaveRegIntoMm(zmm0, 3, rax);

  LoadRegFromMm(zmm0, 0, r15);
  LoadRegFromMm(zmm0, 1, r14);
  LoadRegFromMm(zmm0, 2, r13);
  LoadRegFromMm(zmm0, 3, r12);

  PrintOutRegisterInHex ymm0, r15, r14, r13, r12;
  ok Assemble(debug => 0, trace => 1, eq => <<END);
  ymm0: 0000 0000 0000 0004   0000 0000 0000 0003   0000 0000 0000 0002   0000 0000 0000 0001
   r15: 0000 0000 0000 0001
   r14: 0000 0000 0000 0002
   r13: 0000 0000 0000 0003
   r12: 0000 0000 0000 0004
END
 }

#latest:
if (0) {                                                                        #TCreateShortString #TNasm::X86::ShortString::load #TNasm::X86::ShortString::append #TNasm::X86::ShortString::getLength #TNasm::X86::ShortString::setLength #TNasm::X86::ShortString::appendVar
  my $s = CreateShortString(0);
  my $d = Rb(1..63);
  $s->load(K(address, $d), K(size, 9));
  PrintOutRegisterInHex xmm0;

  $s->len->outNL;

  $s->setLength(K(size, 7));
  PrintOutRegisterInHex xmm0;
  $s->len->outNL;

  if (my $r = $s->append($s))
   {PrintOutRegisterInHex ymm0;
    $r->outNL;
    $s->len->outNL;
   }

  if (my $r = $s->appendByte(V append => 0xaa))
   {PrintOutRegisterInHex ymm0;
    $r->outNL;
    $s->len->outNL;
   }

  if (my $r = $s->appendByte(V append => 0xbb))
   {PrintOutRegisterInHex ymm0;
    $r->outNL;
    $s->len->outNL;
   }

  if (my $r = $s->appendVar(V value => -2))
   {PrintOutRegisterInHex ymm0;
    $r->outNL;
    $s->len->outNL;
   }

  if (my $r = $s->append($s))
   {PrintOutRegisterInHex zmm0;
    $r->outNL;
    $s->len->outNL;
   }

  if (my $r = $s->append($s))
   {PrintOutRegisterInHex zmm0;
    $r->outNL;
    $s->len->outNL;
   }

  ok Assemble(debug => 0, trace => 0, eq => <<END);
  xmm0: 0000 0000 0000 0908   0706 0504 0302 0109
size: 0000 0000 0000 0009
  xmm0: 0000 0000 0000 0908   0706 0504 0302 0107
size: 0000 0000 0000 0007
  ymm0: 0000 0000 0000 0000   0000 0000 0000 0000   0007 0605 0403 0201   0706 0504 0302 010E
result: 0000 0000 0000 0001
size: 0000 0000 0000 000E
  ymm0: 0000 0000 0000 0000   0000 0000 0000 0000   AA07 0605 0403 0201   0706 0504 0302 010F
result: 0000 0000 0000 0001
size: 0000 0000 0000 000F
  ymm0: 0000 0000 0000 0000   0000 0000 0000 00BB   AA07 0605 0403 0201   0706 0504 0302 0110
result: 0000 0000 0000 0001
size: 0000 0000 0000 0010
  ymm0: 0000 0000 0000 00FF   FFFF FFFF FFFF FEBB   AA07 0605 0403 0201   0706 0504 0302 0118
result: 0000 0000 0000 0001
size: 0000 0000 0000 0018
  zmm0: 0000 0000 0000 0000   0000 0000 0000 00FF   FFFF FFFF FFFF FEBB   AA07 0605 0403 0201   0706 0504 0302 01FF   FFFF FFFF FFFF FEBB   AA07 0605 0403 0201   0706 0504 0302 0130
result: 0000 0000 0000 0001
size: 0000 0000 0000 0030
  zmm0: 0000 0000 0000 0000   0000 0000 0000 00FF   FFFF FFFF FFFF FEBB   AA07 0605 0403 0201   0706 0504 0302 01FF   FFFF FFFF FFFF FEBB   AA07 0605 0403 0201   0706 0504 0302 0130
result: 0000 0000 0000 0000
size: 0000 0000 0000 0030
END
 }

#latest:
if (0) {                                                                        #TNasm::X86::String::appendShortString
  my $a = CreateArena;
  my $S = $a->CreateString;

  my $s = CreateShortString(0);
  my $d = Rb(1..63);
  $s->load(K(address, $d), K(size, 9));
  $s->append($s);

  $S->appendShortString($s);

  $S->dump;

  ok Assemble(debug => 0, trace => 0, eq => <<END);
String Dump      Total Length:       18
Offset: 0000 0000 0000 0040  Length: 18  0000 0040 0000 0040   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0009 0807   0605 0403 0201 0908   0706 0504 0302 0112

END
 }

#latest:
if (0) {                                                                        #TNasm::X86::Tree::insertShortString
  my $a = CreateArena;
  my $t = $a->CreateTree;

  my $s = CreateShortString(0);
  my $d = Rb(1..63);
  $s->load(K (address=>$d), K size => 9);

  $t->insertShortString($s, K(data,42));

  $t->dump;

  ok Assemble(debug => 0, trace => 0, eq => <<END);
Tree at:  0000 0000 0000 0018  length: 0000 0000 0000 0001
  Keys: 0000 0058 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0403 0201
  Data: 0000 0000 0000 0002   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0098
  Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
    index: 0000 0000 0000 0000   key: 0000 0000 0403 0201   data: 0000 0000 0000 0098 subTree
  Tree at:  0000 0000 0000 0098  length: 0000 0000 0000 0001
    Keys: 0000 00D8 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0807 0605
    Data: 0000 0000 0000 0002   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0118
    Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
      index: 0000 0000 0000 0000   key: 0000 0000 0807 0605   data: 0000 0000 0000 0118 subTree
    Tree at:  0000 0000 0000 0118  length: 0000 0000 0000 0001
      Keys: 0000 0158 0000 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0009
      Data: 0000 0000 0000 0002   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 002A
      Node: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
        index: 0000 0000 0000 0000   key: 0000 0000 0000 0009   data: 0000 0000 0000 002A
    end
  end
end
END
 }

#latest:
if (0) {                                                                        #TNasm::X86::Arena::CreateQuarks #TNasm::X86::Quarks::quarkFromShortString #TNasm::X86::Quarks::shortStringFromQuark
  my $N = 5;
  my $a = CreateArena;                                                          # Arena containing quarks
  my $Q = $a->CreateQuarks;                                                     # Quarks

  my $s = CreateShortString(0);                                                 # Short string used to load and unload quarks
  my $d = Rb(1..63);

  for my $i(1..$N)                                                              # Load a set of quarks
   {my $j = $i - 1;
    $s->load(K(address, $d), K(size, 4+$i));
    my $q = $Q->quarkFromShortString($s);
    $q->outNL("New quark    $j: ");                                             # New quark, new number
   }
  PrintOutNL;

  for my $i(reverse 1..$N)                                                      # Reload a set of quarks
   {my $j = $i - 1;
    $s->load(K(address, $d), K(size, 4+$i));
    my $q = $Q->quarkFromShortString($s);
    $q->outNL("Old quark    $j: ");                                             # Old quark, old number
   }
  PrintOutNL;

  for my $i(1..$N)                                                              # Dump quarks
   {my $j = $i - 1;
     $s->clear;
    $Q->shortStringFromQuark(K(quark, $j), $s);
    PrintOutString "Quark string $j: ";
    PrintOutRegisterInHex xmm0;
   }

  ok Assemble(debug => 0, trace => 0, eq => <<END);
New quark    0: 0000 0000 0000 0000
New quark    1: 0000 0000 0000 0001
New quark    2: 0000 0000 0000 0002
New quark    3: 0000 0000 0000 0003
New quark    4: 0000 0000 0000 0004

Old quark    4: 0000 0000 0000 0004
Old quark    3: 0000 0000 0000 0003
Old quark    2: 0000 0000 0000 0002
Old quark    1: 0000 0000 0000 0001
Old quark    0: 0000 0000 0000 0000

Quark string 0:   xmm0: 0000 0000 0000 0000   0000 0504 0302 0105
Quark string 1:   xmm0: 0000 0000 0000 0000   0006 0504 0302 0106
Quark string 2:   xmm0: 0000 0000 0000 0000   0706 0504 0302 0107
Quark string 3:   xmm0: 0000 0000 0000 0008   0706 0504 0302 0108
Quark string 4:   xmm0: 0000 0000 0000 0908   0706 0504 0302 0109
END
 }

#latest:
if (0) {                                                                        #TNasm::X86::Arena::CreateQuarks #TNasm::X86::Quarks::quarkFromShortString #TNasm::X86::Quarks::shortStringFromQuark
  my $N  = 5;
  my $a  = CreateArena;                                                         # Arena containing quarks
  my $Q1 = $a->CreateQuarks;                                                    # Quarks
  my $Q2 = $a->CreateQuarks;                                                    # Quarks

  my $s = CreateShortString(0);                                                 # Short string used to load and unload quarks
  my $d = Rb(1..63);

  for my $i(1..$N)                                                              # Load first set of quarks
   {my $j = $i - 1;
    $s->load(K(address, $d), K(size, 4+$i));
    my $q = $Q1->quarkFromShortString($s);
    $q->outNL("Q1 $j: ");
   }
  PrintOutNL;

  for my $i(1..$N)                                                              # Load second set of quarks
   {my $j = $i - 1;
    $s->load(K(address, $d), K(size, 5+$i));
    my $q = $Q2->quarkFromShortString($s);
    $q->outNL("Q2 $j: ");
   }
  PrintOutNL;

  $Q1->quarkToQuark(K(three,3), $Q1)->outNL;
  $Q1->quarkToQuark(K(three,3), $Q2)->outNL;
  $Q2->quarkToQuark(K(two,  2), $Q1)->outNL;
  $Q2->quarkToQuark(K(two,  2), $Q2)->outNL;

  ok Assemble(debug => 0, trace => 0, eq => <<END);
Q1 0: 0000 0000 0000 0000
Q1 1: 0000 0000 0000 0001
Q1 2: 0000 0000 0000 0002
Q1 3: 0000 0000 0000 0003
Q1 4: 0000 0000 0000 0004

Q2 0: 0000 0000 0000 0000
Q2 1: 0000 0000 0000 0001
Q2 2: 0000 0000 0000 0002
Q2 3: 0000 0000 0000 0003
Q2 4: 0000 0000 0000 0004

found: 0000 0000 0000 0003
found: 0000 0000 0000 0002
found: 0000 0000 0000 0003
found: 0000 0000 0000 0002
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Arena::CreateQuarks #TNasm::X86::Quarks::quarkFromShortString #TNasm::X86::Quarks::shortStringFromQuark
  my $s = CreateShortString(0);                                                 # Short string used to load and unload quarks
  my $d = Rb(1..63);
  $s->loadDwordBytes(0, K(address, $d), K(size, 9));
  PrintOutRegisterInHex xmm0;

  ok Assemble(debug => 0, trace => 0, eq => <<END);
  xmm0: 0000 0000 0000 211D   1915 110D 0905 0109
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Arena::CreateQuarks #TNasm::X86::Quarks::quarkFromShortString #TNasm::X86::Quarks::shortStringFromQuark
  my $s = CreateShortString(0);                                                 # Short string used to load and unload quarks
  my $d = Rb(1..63);
  $s->loadDwordWords(0, K(address, $d), K(size, 9));
  PrintOutRegisterInHex ymm0;

  ok Assemble(debug => 0, trace => 0, eq => <<END);
  ymm0: 0000 0000 0000 0000   0000 0000 0022 211E   1D1A 1916 1512 110E   0D0A 0906 0502 0112
END
 }

#latest:
if (1) {                                                                        #TNasm::Variable::copy  #TNasm::Variable::copyRef
  my $a = V('a', 1);
  my $r = R('r')->copyRef($a);
  my $R = R('R')->copyRef($r);

  $a->outNL;
  $r->outNL;
  $R->outNL;

  $a->copy(2);

  $a->outNL;
  $r->outNL;
  $R->outNL;

  $r->copy(3);

  $a->outNL;
  $r->outNL;
  $R->outNL;

  $R->copy(4);

  $a->outNL;
  $r->outNL;
  $R->outNL;

  ok Assemble(debug => 0, trace => 0, eq => <<END);
a: 0000 0000 0000 0001
r: 0000 0000 0000 0001
R: 0000 0000 0000 0001
a: 0000 0000 0000 0002
r: 0000 0000 0000 0002
R: 0000 0000 0000 0002
a: 0000 0000 0000 0003
r: 0000 0000 0000 0003
R: 0000 0000 0000 0003
a: 0000 0000 0000 0004
r: 0000 0000 0000 0004
R: 0000 0000 0000 0004
END
 }

#latest:
if (0) {                                                                        #TNasm::X86::String::getQ1
  my $a  = CreateArena;

  my $s = $a->CreateString;
  my $i = Rb(0..255);
  $s->append(V(source => $i), V(size => 63)); $s->dump;

  my $q = $s->getQ1;
  $q->outNL;

  ok Assemble(debug => 0, trace => 0, eq => <<END);
String Dump      Total Length:       63
Offset: 0000 0000 0000 0018  Length: 55  0000 0058 0000 0058   3635 3433 3231 302F   2E2D 2C2B 2A29 2827   2625 2423 2221 201F   1E1D 1C1B 1A19 1817   1615 1413 1211 100F   0E0D 0C0B 0A09 0807   0605 0403 0201 0037
Offset: 0000 0000 0000 0058  Length:  8  0000 0018 0000 0018   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 003E   3D3C 3B3A 3938 3708

q1: 0706 0504 0302 0100
END
 }

#latest:
if (0) {                                                                        #TNasm::X86::Quarks::quarkFromSub #TNasm::X86::Quarks::subFromQuark #TNasm::X86::Quarks::loadConstantString
  my $s1 = Subroutine
   {PrintOutStringNL "11111";
   } [], name => 'test1';

  my $s2 = Subroutine
   {PrintOutStringNL "22222";
   } [], name => 'test2';

  my $s  = CreateShortString(0);

  my $a  = CreateArena;
  my $q  = $a->CreateQuarks;

  $s->loadConstantString("add");
  my $n1 = $q->quarkFromSub($s1->V, $s);

  $s->loadConstantString("assign");
  my $n2 = $q->quarkFromSub($s2->V, $s);

  $s->loadConstantString("add");
  my $S1 = $q->subFromQuark($n1);
  my $T1 = $q->subFromShortString($s);
  $s1->V->outNL;
  $S1   ->outNL(" sub: ");
  $T1   ->outNL(" sub: ");

  $s->loadConstantString("assign");
  my $S2 = $q->subFromQuark($n2);
  my $T2 = $q->subFromShortString($s);
  $s2->V->outNL;
  $S2   ->outNL(" sub: ");
  $T2   ->outNL(" sub: ");

  $q->call($n1);
  $q->call($n2);

  ok Assemble(debug => 0, trace => 0, eq => <<END);
call: 0000 0000 0040 1009
 sub: 0000 0000 0040 1009
 sub: 0000 0000 0040 1009
call: 0000 0000 0040 10B9
 sub: 0000 0000 0040 10B9
 sub: 0000 0000 0040 10B9
11111
22222
END
 }

#latest:
if (1) {                                                                        # Register expressions in parameter lists
  my $s = Subroutine
   {my ($p) = @_;
    $$p{p}->outNL;
   } [qw(p)], name => 'test';

  $s->call(p => 221);
  Mov r15, 0xcc;
  $s->call(p => r15);

  ok Assemble(debug => 0, trace => 0, eq => <<END);
p: 0000 0000 0000 00DD
p: 0000 0000 0000 00CC
END
 }

#latest:
if (1) {                                                                        # Consolidated parameter lists
  my $s = Subroutine
   {my ($p, $s) = @_;

    my $t = Subroutine
     {my ($p) = @_;
      $$p{p}->outNL;
      $$p{q}->outNL;
     } [], name => 'tttt', with => $s;

    $t->call(q => 0xcc);

   } [qw(p q)], name => 'ssss';

  $s->call(p => 0xee, q => 0xdd);

  ok Assemble(debug => 0, trace => 0, eq => <<END);
p: 0000 0000 0000 00EE
q: 0000 0000 0000 00CC
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Sub::dispatch
  my $p = Subroutine                                                            # Prototype subroutine to establish parameter list
   {} [qw(p)], name => 'prototype';

  my $a = Subroutine                                                            # Subroutine we are actually going to call
   {$p->variables->{p}->outNL;
   } [], name => 'actual', with => $p;

  my $d = Subroutine                                                            # Dispatcher
   {my ($p, $s) = @_;
    $a->dispatch;
    PrintOutStringNL "This should NOT happen!";
   } [], name => 'dispatch', with => $p;

  $d->call(p => 0xcc);
  PrintOutStringNL "This should happen!";

  ok Assemble(debug => 0, trace => 0, eq => <<END);
p: 0000 0000 0000 00CC
This should happen!
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Sub::dispatchV
  my $s = Subroutine                                                            # Containing sub
   {my ($parameters, $sub) = @_;

    my $p = Subroutine                                                          # Prototype subroutine with cascading parameter lists
     {} [qw(q)], with => $sub, name => 'prototype';

    my $a = Subroutine                                                          # Subroutine we are actually going to call with extended parameter list
     {$p->variables->{p}->outNL;
      $p->variables->{q}->outNL;
     } [], name => 'actual', with => $p;

    my $d = Subroutine                                                          # Dispatcher
     {my ($p, $s) = @_;
      $a->dispatchV($a->V);
      PrintOutStringNL "This should NOT happen!";
     } [], name => 'dispatch', with => $p;

    $d->call(q => 0xdd) ;                                                       # Extend cascading parameter list
   } [qw(p)], name => 'outer';

  $s->call(p => 0xcc);                                                          # Start cascading parameter list
  PrintOutStringNL "This should happen!";

  ok Assemble(debug => 0, trace => 0, eq => <<END);
p: 0000 0000 0000 00CC
q: 0000 0000 0000 00DD
This should happen!
END
 }

#latest:
if (0) {                                                                        #TNasm::X86::CreateQuarks #TNasm::X86::Quarks::put #TNasm::X86::Quarks::putSub #TNasm::X86::Quarks::dump #TNasm::X86::Quarks::subFromQuarkViaQuarks #TNasm::X86::Quarks::subFromQuarkNumber #TNasm::X86::Quarks::subFromShortString #TNasm::X86::Quarks::callSubFromShortString
  my $s = Subroutine
   {my ($p, $s) = @_;
    PrintOutString "SSSS";
    $$p{p}->setReg(r15);
    PrintOutRegisterInHex r15;
   } [qw(p)], name => 'ssss';

  my $t = Subroutine
   {my ($p, $s) = @_;
    PrintOutString "TTTT";
    $$p{p}->setReg(r15);
    PrintOutRegisterInHex r15;
   } [], name => 'tttt', with => $s;

  my $A = CreateArena;

  my $Q  = $A->CreateQuarks;
           $Q->put('aaaa');
           $Q->put('bbbb');
  my $Qs = $Q->put('ssss');
  my $Qt = $Q->put('tttt');

  my $q  = $A->CreateQuarks;
  my $qs = $q->putSub('ssss', $s);
  my $qt = $q->putSub('tttt', $t);

  PrintOutStringNL "Quarks";   $Q->dump;
  PrintOutStringNL "Subs";     $q->dump;

  $q->subFromQuarkViaQuarks($Q, $Qs)->outNL;
  $q->subFromQuarkViaQuarks($Q, $Qt)->outNL;
  $q->subFromQuarkNumber($qs)->outNL;
  $q->subFromQuarkNumber($qt)->outNL;

  my $cs = $q->subFromQuarkNumber($qs);
  $s->via($cs, p => 1);
  my $ct = $q->subFromQuarkNumber($qt);
  $s->via($ct, p => 2);

  $q->callSubFromQuarkNumber   (    $s, $qs, p => 0x11);
  $q->callSubFromQuarkNumber   (    $s, $qt, p => 0x22);
  $q->callSubFromQuarkViaQuarks($Q, $s, $Qs, p => 0x111);
  $q->callSubFromQuarkViaQuarks($Q, $s, $Qt, p => 0x222);

  if (1)
   {my $s = CreateShortString(0);
       $s->loadConstantString("ssss");
    $q->subFromShortString($s)->outNL;
   }

  if (1)
   {my $s = CreateShortString(0);
       $s->loadConstantString("ssss");
    $q->callSubFromShortString($t, $s, p => 3);
   }

  ok Assemble(debug => 0, trace => 0, eq => <<END);
Quarks
Quark : 0000 0000 0000 0000 => 0000 0000 0000 00D8 == 0000 00D8 0000 00D8   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0061 6161 6104
Quark : 0000 0000 0000 0001 => 0000 0000 0000 0198 == 0000 0198 0000 0198   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0062 6262 6204
Quark : 0000 0000 0000 0002 => 0000 0000 0000 01D8 == 0000 01D8 0000 01D8   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0073 7373 7304
Quark : 0000 0000 0000 0003 => 0000 0000 0000 0218 == 0000 0218 0000 0218   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0074 7474 7404
Subs
Quark : 0000 0000 0000 0000 => 0000 0000 0000 0318 == 0000 0318 0000 0318   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0073 7373 7300   0000 0000 4010 090C
Quark : 0000 0000 0000 0001 => 0000 0000 0000 03D8 == 0000 03D8 0000 03D8   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0074 7474 7400   0000 0000 4013 870C
sub: 0000 0000 0040 1009
sub: 0000 0000 0040 1387
sub: 0000 0000 0040 1009
sub: 0000 0000 0040 1387
SSSS   r15: 0000 0000 0000 0001
TTTT   r15: 0000 0000 0000 0002
SSSS   r15: 0000 0000 0000 0011
TTTT   r15: 0000 0000 0000 0022
SSSS   r15: 0000 0000 0000 0111
TTTT   r15: 0000 0000 0000 0222
sub: 0000 0000 0040 1009
SSSS   r15: 0000 0000 0000 0003
END
 }

#latest:
if (11) {                                                                       #TNasm::X86::Variable::clone
  my $a = V('a', 1);
  my $b = $a->clone('a');

  $_->outNL for $a, $b;

  ok Assemble(debug => 0, trace => 0, eq => <<END);
a: 0000 0000 0000 0001
a: 0000 0000 0000 0001
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::ClassifyWithInRangeAndSaveWordOffset Nasm::X86::Variable::loadZmm
  my $l = V('low',   Rd(2, 7, (0) x 14));
  my $h = V('high' , Rd(3, 9, (0) x 14));
  my $o = V('off',   Rd(2, 5, (0) x 14));
  my $u = V('utf32', Dd(2, 3, 7, 8, 9, (0) x 11));


  $l->loadZmm(0);
  $h->loadZmm(1);
  $o->loadZmm(2);

  ClassifyWithInRangeAndSaveWordOffset($u, V('size', 5), V('classification', 7));
  $u->loadZmm(3);

  PrintOutRegisterInHex zmm 0..3;

  ok Assemble(debug => 0, trace => 0, eq => <<END);
  zmm0: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0007 0000 0002
  zmm1: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0009 0000 0003
  zmm2: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0005 0000 0002
  zmm3: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0700 0004   0700 0003 0700 0002   0700 0001 0700 0000
END
 }

#latest:
if (1) {                                                                        #TPrintOutRaxInDecNL #TPrintOutRaxRightInDec
  my $w = V width => 12;

  Mov rax, 0;
  PrintOutRaxRightInDecNL $w;

  Mov rax, 0x2a;
  PrintOutRaxRightInDecNL $w;

  Mov rax, 1;
  PrintOutRaxRightInDecNL $w;

  Mov rax, 255;
  PrintOutRaxRightInDecNL $w;

  Mov rax, 123456;
  PrintOutRaxRightInDecNL $w;

  Mov rax, 1234567890;
  PrintOutRaxRightInDecNL $w;

  Mov rax, 0x2;
  Shl rax, 16;
  Mov rdx, 0xdfdc;
  Or rax, rdx;
  Shl rax, 16;
  Mov rdx, 0x1c35;
  Or rax, rdx;
  PrintOutRaxRightInDecNL $w;

# 1C BE99 1A14
  Mov rax, 0x1c;
  Shl rax, 16;
  Mov rdx, 0xbe99;
  Or rax, rdx;
  Shl rax, 16;
  Mov rdx, 0x1a14;
  Or rax, rdx;
  PrintOutRaxInDecNL;

# 2 EE33 3961
  Mov rax, 0x2;
  Shl rax, 16;
  Mov rdx, 0xee33;
  Or rax, rdx;
  Shl rax, 16;
  Mov rdx, 0x3961;
  Or rax, rdx;
  PrintOutRaxRightInDecNL $w;

  ok Assemble eq => <<END;
           0
          42
           1
         255
      123456
  1234567890
 12345678901
123456789012
 12586269025
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Variable::call Create a library file and call the code in the library file.
  my $l = "aaa.so";
  Mov rax, 0x12345678;
  Ret;

  ok Assemble library => $l;                                                    # Create the library file
  ok -e $l;

  my ($address, $size) = ReadFile $l;                                           # Read library file into memory

  Mov rax, 0;
  PrintOutRaxInHexNL;

  $address->call;                                                               # Call code in memory loaded from library file

  PrintOutRaxInHexNL;                                                           # Print value set in library

  ok Assemble eq =><<END;
0000 0000 0000 0000
0000 0000 1234 5678
END
  unlink $l;
 }

#latest:
if (1) {
  unlink my $l = "aaa.so";

  PrintOutRaxInDecNL;
  Ret;
  ok Assemble library => $l;                                                    # Create the library file

  my ($address, $size) = ReadFile $l;                                           # Read library file into memory

  Mov rax, 42;
  $address->call;                                                               # Call code in memory loaded from library file

  ok Assemble eq =><<END;
42
END
  unlink $l;
 }

#latest:
if (1) {
  unlink my $l = "aaa.so";

  PrintOutRaxInHexNL;
  Ret;
  ok Assemble library => $l;                                                    # Create the library file

  my ($address, $size) = ReadFile $l;                                           # Read library file into memory

  Mov rax, 42;
  $address->call;                                                               # Call code in memory loaded from library file

  ok Assemble(eq =><<END);
0000 0000 0000 002A
END
  unlink $l;
 }

#latest:
if (1) {
  unlink my $l = "aaa.so";
  my $N = 11;
  V(n => $N)->for(sub
   {my ($index, $start, $next, $end) = @_;
    $index->outNL;
    Inc rax;
   });
  Ret;
  ok Assemble library => $l;                                                    # Create the library file


  my ($address, $size) = ReadFile $l;                                           # Read library file into memory
  Mov rax, 0;
  $address->call;                                                               # Call code in memory loaded from library file
  PrintOutRaxInDecNL;

  ok Assemble eq => <<END;
index: 0000 0000 0000 0000
index: 0000 0000 0000 0001
index: 0000 0000 0000 0002
index: 0000 0000 0000 0003
index: 0000 0000 0000 0004
index: 0000 0000 0000 0005
index: 0000 0000 0000 0006
index: 0000 0000 0000 0007
index: 0000 0000 0000 0008
index: 0000 0000 0000 0009
index: 0000 0000 0000 000A
11
END
  unlink $l;
 }

#latest:
if (1) {
  unlink my $l = "aaa.so";
  my $N = 21;
  my $q = Rq($N);
  Mov rax, "[$q]";
  Ret;
  ok Assemble library => $l;                                                    # Create the library file


  my ($address, $size) = ReadFile $l;                                           # Read library file into memory
  Mov rax, 0;
  $address->call;                                                               # Call code in memory loaded from library file
  PrintOutRaxInDecNL;

  ok Assemble eq => <<END;
$N
END
  unlink $l;
 }

#latest:
if (0) {
  unlink my $l = "library";                                                     # The name of the file containing the library

  my @s = qw(inc dup put);                                                      # Subroutine names
  my %s = map
   {my $l = Label;                                                              # Start label for subroutine
    my  $o = "qword[rsp-".(($_+1) * RegisterSize rax)."]";                      # Position of subroutine on stack
    Mov $o, $l.'-$$';                                                           # Put offset of subroutine on stack
    Add $o, r15;                                                                # The library must be called via r15 to convert the offset to the address of each subroutine

    $s[$_] => genHash("NasmX86::Library::Subroutine",                           # Subroutine definitions
      number  => $_ + 1,                                                        # Number of subroutine from 1
      label   => $l,                                                            # Label of subroutine
      name    => $s[$_],                                                        # Name of subroutine
      call    => undef,                                                         # Perl subroutine to call assembler subroutine
   )} keys @s;

  Ret;

  sub NasmX86::Library::Subroutine::gen($$)                                     # Write the code of a subroutine
   {my ($sub, $code) = @_;                                                      # Subroutine definition, asssociated code as a sub
    SetLabel $sub->label;                                                       # Start label
    &$code;                                                                     # Code of subroutine
    Ret;                                                                        # Return from sub routine
   }

  $s{inc}->gen(sub {Inc rax});                                                  # Increment rax
  $s{dup}->gen(sub {Shl rax, 1});                                               # Double rax
  $s{put}->gen(sub {PrintOutRaxInDecNL});                                       # Print rax in decimal

  ok Assemble library => $l;                                                    # Create the library file

  my ($address, $size) = ReadFile $l;                                           # Read library file into memory
  $address->call(r15);                                                          # Load addresses of subroutines onto stack

  for my $s(@s{@s})                                                             # Each subroutine
   {Mov r15, "[rsp-".(($s->number + 1) * RegisterSize rax)."]";                 # Address of subroutine in this process
    $s->call = V $s->name => r15;                                               # Address of subroutine in this process from stack as a variable
   }
  my ($inc, $dup, $put) = map {my $c = $_->call; sub {$c->call}} @s{@s};        # Call subroutine via variable - perl bug because $_ by  itself is not enough

   Mov rax, 1; &$put;
#  &$inc;      &$put;                                                            # Use the subroutines from the library
#  &$dup;      &$put;
#  &$dup;      &$put;
#  &$inc;      &$put;

  ok Assemble eq => <<END;
1
2
4
8
9
END
  unlink $l;
 }

#latest:
if (0) {

  my $library = CreateLibrary                                                   # Library definition
   (subroutines =>                                                              # Sub routines in libray
     {inc => sub {Inc rax},                                                     # Increment rax
      dup => sub {Shl rax, 1},                                                  # Double rax
      put => sub {PrintOutRaxInDecNL},                                          # Print rax in decimal
     },
    file => q(library),
   );

  my ($dup, $inc, $put) = $library->load;                                       # Load the library into memory

  Mov rax, 1; &$put;
  &$inc;      &$put;                                                            # Use the subroutines from the library
  &$dup;      &$put;
  &$dup;      &$put;
  &$inc;      &$put;

  ok Assemble eq => <<END;
1
2
4
8
9
END
  unlink $$library{file};
 }

#latest:
if (1) {                                                                        #TreadChar #TPrintOutRaxAsChar
  my $e = q(readChar);

  ForEver
   {my ($start, $end) = @_;
    ReadChar;
    Cmp rax, 0xa;
    Jle $end;
    PrintOutRaxAsChar;
    PrintOutRaxAsChar;
   };
  PrintOutNL;

  Assemble keep => $e;

  is_deeply qx(echo "ABCDCBA" | ./$e), <<END;
AABBCCDDCCBBAA
END
  unlink $e;
 }

#latest:
if (1) {                                                                        #TPrintOutRaxAsTextNL
  my $t = Rs('abcdefghi');
  Mov rax, $t;
  Mov rax, "[rax]";
  PrintOutRaxAsTextNL;
  ok Assemble eq => <<END;
abcdefgh
END
}

#latest:
if (1) {                                                                        #TNasm::X86::Variable::outCStringNL #TNasm::X86::Variable::outInDecNL;
  my $e = q(parameters);

  (V string => "[rbp+8]")->outInDecNL;
  (V string => "[rbp+16]")->outCStringNL;
  (V string => "[rbp+24]")->outCStringNL;
  (V string => "[rbp+32]")->outCStringNL;
  (V string => "[rbp+40]")->outCStringNL;
  (V string => "[rbp+48]")->outInDecNL;

  (V string => "[rbp+8]")->for(sub
   {my ($index, $start, $next, $end) = @_;
    $index->setReg(rax);
    Inc rax;
    PrintOutRaxInDec;
    Inc rax;
    PrintOutString " : ";
    Shl rax, 3;
    (V string => "[rbp+rax]")->outCStringNL;
   });

  Assemble keep => $e;

  is_deeply scalar(qx(./$e AaAaAaAaAa BbCcDdEe 123456789)), <<END;
string: 4
./parameters
AaAaAaAaAa
BbCcDdEe
123456789
string: 0
1 : ./parameters
2 : AaAaAaAaAa
3 : BbCcDdEe
4 : 123456789
END

  unlink $e;
 }

#latest:
if (1) {                                                                        #TPrintOutRaxAsTextNL
  V( loop => 16)->for(sub
   {my ($index, $start, $next, $end) = @_;
    $index->setReg(rax);
    Add rax, 0xb0;   Shl rax, 16;
    Mov  ax, 0x9d9d; Shl rax, 8;
    Mov  al, 0xf0;
    PrintOutRaxAsText;
   });
  PrintOutNL;

  ok Assemble(debug => 0, trace => 0, eq => <<END);
𝝰𝝱𝝲𝝳𝝴𝝵𝝶𝝷𝝸𝝹𝝺𝝻𝝼𝝽𝝾𝝿
END
 }

#latest:
if (1) {                                                                        #TPrintOutRaxRightInDec #TPrintOutRaxRightInDecNL
  Mov rax, 0x2a;
  PrintOutRaxRightInDec   V width=> 4;
  Shl rax, 1;
  PrintOutRaxRightInDecNL V width=> 6;

  ok Assemble eq => <<END;
  42    84
END
 }

#latest:
if (1) {                                                                        # Fibonacci numbers
  my $N = 11;                                                                   # The number of Fibonacci numbers to generate
  Mov r13, 0;                                                                   # First  Fibonacci number
  Mov r14, 1;                                                                   # Second Fibonacci
  PrintOutStringNL " i   Fibonacci";                                            # The title of the piece

  V(N => $N)->for(sub                                                           # Generate each Fibonacci number by adding the two previous ones together
   {my ($index, $start, $next, $end) = @_;
    $index->outRightInDec(V(width => 2));                                       # Index
    Mov rax, r13;
    PrintOutRaxRightInDecNL V width => 12;                                      # Fibonacci number at this index

    Mov r15, r14;                                                               # Next number is the sum of the two previous ones
    Add r15, r13;

    Mov r13, r14;                                                               # Move up
    Mov r14, r15;
   });

  ok Assemble eq => <<END;
 i   Fibonacci
 0           0
 1           1
 2           1
 3           2
 4           3
 5           5
 6           8
 7          13
 8          21
 9          34
10          55
END
 }

#latest:
if (1) {                                                                        #TReadLine
  my $e = q(readLine);
  my $f = writeTempFile("hello\nworld\n");

  ReadLine;
  PrintOutRaxAsTextNL;
  ReadLine;
  PrintOutRaxAsTextNL;

  Assemble keep => $e;

  is_deeply scalar(qx(./$e < $f)), <<END;
hello
world
END
  unlink $f;
}

#latest:
if (1) {                                                                        #TReadInteger
  my $e = q(readInteger);
  my $f = writeTempFile("11\n22\n");

  ReadInteger;
  Shl rax, 1;
  PrintOutRaxInDecNL;
  ReadInteger;
  Shl rax, 1;
  PrintOutRaxInDecNL;

  Assemble keep => $e;

  is_deeply scalar(qx(./$e < $f)), <<END;
22
44
END

  unlink $e, $f;
 }

#latest:
if (1) {                                                                        #TSubroutine2
  package InnerStructure
   {use Data::Table::Text qw(:all);
    sub new($)                                                                  # Create a new structure
     {my ($value) = @_;                                                         # Value for structure variable
      describe(value => Nasm::X86::V(var => $value))
     };
    sub describe(%)                                                             # Describe the components of a structure
     {my (%options) = @_;                                                       # Options
      genHash(__PACKAGE__,
        value => $options{value},
       );
     }
   }

  package OuterStructure
   {use Data::Table::Text qw(:all);
    sub new($$)                                                                 # Create a new structure
     {my ($valueOuter, $valueInner) = @_;                                       # Value for structure variable
      describe
       (value => Nasm::X86::V(var => $valueOuter),
        inner => InnerStructure::new($valueInner),
       )
     };
    sub describe(%)                                                             # Describe the components of a structure
     {my (%options) = @_;                                                       # Options
      genHash(__PACKAGE__,
        value => $options{value},
        inner => $options{inner},
       );
     }
   }

  my $t = OuterStructure::new(42, 4);

  my $s = Subroutine2
   {my ($parameters, $structures, $sub) = @_;                                   # Variable parameters, structure variables, structure copies, subroutine description

    $$structures{test}->value->setReg(rax);
    Mov r15, 84;
    $$structures{test}->value->getReg(r15);
    Mov r15, 8;
    $$structures{test}->inner->value->getReg(r15);

    $$parameters{p}->setReg(rdx);
   } parameters=>[qw(p)], structures => {test => $t}, name => 'test';

  my $T = OuterStructure::new(42, 4);
  my $V = V parameter => 21;

  $s->call(parameters=>{p => $V}, structures=>{test => $T});

  PrintOutRaxInDecNL;
  Mov rax, rdx;
  PrintOutRaxInDecNL;
  $t->value->outInDecNL;
  $t->inner->value->outInDecNL;
  $T->value->outInDecNL;
  $T->inner->value->outInDecNL;
  ok Assemble(debug => 0, trace => 0, eq => <<END);
42
21
var: 42
var: 4
var: 84
var: 8
END
 }

#latest:
if (1) {
  my $s = Subroutine2                                                           #TSubroutine2
   {my ($p, $s, $sub) = @_;                                                     # Variable parameters, structure variables, structure copies, subroutine description
    $$s{var}->setReg(rax);
    Dec rax;
    $$s{var}->getReg(rax);
   } structures => {var => my $v = V var => 42}, name => 'test', call => 1;

  $v->outNL;

  $s->call(structures => {var => my $V = V var => 2});
  $V->outNL;

  ok Assemble(debug => 0, trace => 0, eq => <<END);
var: 0000 0000 0000 0029
var: 0000 0000 0000 0001
END
 }

#latest:
if (1) {
  my $N = 256;
  my $t = V struct => 33;

  my $s = Subroutine2                                                           #TSubroutine2
   {my ($p, $s, $sub) = @_;                                                     # Variable parameters, structure variables, structure copies, subroutine description
    SaveFirstFour;
    my $v = V var => 0;
    $v->copy($$p{i});
    $$p{o}->copy($v);
    $$p{O}->copy($$s{struct});
    $$s{struct}->copy($$s{struct} + 1);

    my $M = AllocateMemory K size => $N;                                        # Allocate memory and save its location in a variable
    $$p{M}->copy($M);
    $M->setReg(rax);
    Mov "qword[rax]", -1;
    FreeMemory $M, K size => $N;                                                # Free memory
    RestoreFirstFour;
   } structures => {struct => $t}, parameters => [qw(i o O M)], name => 'test';

  $s->call(parameters => {i => (my $i = K i => 22),
                          o => (my $o = V o =>  0),
                          O => (my $O = V O =>  0),
                          M => (my $M = V M =>  0)},
           structures => {struct => $t});
  $i->outInDecNL;
  $o->outInDecNL;
  $O->outInDecNL;
  $t->outInDecNL;

  ok Assemble(debug => 0, trace => 0, eq => <<END);
i: 22
o: 22
O: 33
struct: 34
END
 }

#latest:
if (1) {                                                                        # Split a left node held in zmm28..zmm26 with its parent in zmm31..zmm29 pushing to the right zmm25..zmm23
  my $newRight = K newRight => 0x9119;                                          # Offset of new right block
  my $tree = DescribeTree(length => 3);                                         # Test with a narrow tree
  my ($RN, $RD, $RK, $LN, $LD, $LK, $PN, $PD, $PK) = 23..31;                    # Zmm names
  my $transfer = r8;

  for my $test(0..13)                                                           # Test each key position
   {PrintOutStringNL "Test $test";

    K(PK => Rd(map {($_<<28) +0x9999999} 1..15, 0))->loadZmm($PK);
    K(PD => Rd(map {($_<<28) +0x7777777} 1..15, 0))->loadZmm($PD);
    K(PN => Rd(map {($_<<28) +0x8888888} 1..15, 0))->loadZmm($PN);

    K(LK => Rd(map {($_<<28) +0x6666666} $test..15, 0..($test-1)))->loadZmm($LK);
    K(LD => Rd(map {($_<<28) +0x4444444} $test..15, 0..($test-1)))->loadZmm($LD);
    K(LN => Rd(map {($_<<28) +0x5555555} 0..15))->loadZmm($LN);

    K(RK => Rd(map {($_<<28) +0x3333333} 0..15))->loadZmm($RK);
    K(RD => Rd(map {($_<<28) +0x1111111} 0..15))->loadZmm($RD);
    K(RN => Rd(map {($_<<28) +0x2222222} 0..15))->loadZmm($RN);

    Mov $transfer, 0;                                                           # Test set of tree bits
    wRegIntoZmm $transfer, $PK, $tree->treeBits;

    Mov $transfer, 1;                                                           # Test set of parent length
    wRegIntoZmm $transfer, $PK, $tree->lengthOffset;

    Mov $transfer, 0b11011101;                                                  # Test set of tree bits in node being split
    wRegIntoZmm $transfer, $LK, $tree->treeBits;

    $tree->splitNotRoot($newRight, reverse 23..31);

    PrintOutStringNL "Parent";
    PrintOutRegisterInHex zmm reverse 29..31;

    PrintOutStringNL "Left";
    PrintOutRegisterInHex zmm reverse 26..28;

    PrintOutStringNL "Right";
    PrintOutRegisterInHex zmm reverse 23..25;
   }

  ok Assemble eq => <<END;
Test 0
Parent
 zmm31: 0999 9999 0000 0002   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   1999 9999 1666 6666
 zmm30: 0777 7777 F777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   1777 7777 1444 4444
 zmm29: 0888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 2888 8888   0000 9119 1888 8888
Left
 zmm28: F666 6666 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0666 6666
 zmm27: F444 4444 E444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0444 4444
 zmm26: F555 5555 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   1555 5555 0555 5555
Right
 zmm25: F333 3333 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 2666 6666
 zmm24: F111 1111 E444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 2444 4444
 zmm23: F222 2222 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   3555 5555 2555 5555
Test 1
Parent
 zmm31: 0999 9999 0000 0002   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   2666 6666 1999 9999
 zmm30: 0777 7777 F777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   2444 4444 1777 7777
 zmm29: 0888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 0000 9119   2888 8888 1888 8888
Left
 zmm28: 0666 6666 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 1666 6666
 zmm27: 0444 4444 F444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 1444 4444
 zmm26: F555 5555 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   1555 5555 0555 5555
Right
 zmm25: F333 3333 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 3666 6666
 zmm24: F111 1111 F444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 3444 4444
 zmm23: F222 2222 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   3555 5555 2555 5555
Test 2
Parent
 zmm31: 0999 9999 0000 0002   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   3666 6666 1999 9999
 zmm30: 0777 7777 F777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   3444 4444 1777 7777
 zmm29: 0888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 0000 9119   2888 8888 1888 8888
Left
 zmm28: 1666 6666 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 2666 6666
 zmm27: 1444 4444 0444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 2444 4444
 zmm26: F555 5555 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   1555 5555 0555 5555
Right
 zmm25: F333 3333 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 4666 6666
 zmm24: F111 1111 0444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 4444 4444
 zmm23: F222 2222 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   3555 5555 2555 5555
Test 3
Parent
 zmm31: 0999 9999 0000 0002   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   4666 6666 1999 9999
 zmm30: 0777 7777 F777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   4444 4444 1777 7777
 zmm29: 0888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 0000 9119   2888 8888 1888 8888
Left
 zmm28: 2666 6666 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 3666 6666
 zmm27: 2444 4444 1444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 3444 4444
 zmm26: F555 5555 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   1555 5555 0555 5555
Right
 zmm25: F333 3333 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 5666 6666
 zmm24: F111 1111 1444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 5444 4444
 zmm23: F222 2222 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   3555 5555 2555 5555
Test 4
Parent
 zmm31: 0999 9999 0000 0002   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   5666 6666 1999 9999
 zmm30: 0777 7777 F777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   5444 4444 1777 7777
 zmm29: 0888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 0000 9119   2888 8888 1888 8888
Left
 zmm28: 3666 6666 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 4666 6666
 zmm27: 3444 4444 2444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 4444 4444
 zmm26: F555 5555 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   1555 5555 0555 5555
Right
 zmm25: F333 3333 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 6666 6666
 zmm24: F111 1111 2444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 6444 4444
 zmm23: F222 2222 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   3555 5555 2555 5555
Test 5
Parent
 zmm31: 0999 9999 0000 0002   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   6666 6666 1999 9999
 zmm30: 0777 7777 F777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   6444 4444 1777 7777
 zmm29: 0888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 0000 9119   2888 8888 1888 8888
Left
 zmm28: 4666 6666 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 5666 6666
 zmm27: 4444 4444 3444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 5444 4444
 zmm26: F555 5555 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   1555 5555 0555 5555
Right
 zmm25: F333 3333 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 7666 6666
 zmm24: F111 1111 3444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 7444 4444
 zmm23: F222 2222 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   3555 5555 2555 5555
Test 6
Parent
 zmm31: 0999 9999 0000 0002   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   7666 6666 1999 9999
 zmm30: 0777 7777 F777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   7444 4444 1777 7777
 zmm29: 0888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 0000 9119   2888 8888 1888 8888
Left
 zmm28: 5666 6666 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 6666 6666
 zmm27: 5444 4444 4444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 6444 4444
 zmm26: F555 5555 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   1555 5555 0555 5555
Right
 zmm25: F333 3333 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 8666 6666
 zmm24: F111 1111 4444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 8444 4444
 zmm23: F222 2222 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   3555 5555 2555 5555
Test 7
Parent
 zmm31: 0999 9999 0000 0002   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   8666 6666 1999 9999
 zmm30: 0777 7777 F777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   8444 4444 1777 7777
 zmm29: 0888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 0000 9119   2888 8888 1888 8888
Left
 zmm28: 6666 6666 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 7666 6666
 zmm27: 6444 4444 5444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 7444 4444
 zmm26: F555 5555 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   1555 5555 0555 5555
Right
 zmm25: F333 3333 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 9666 6666
 zmm24: F111 1111 5444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 9444 4444
 zmm23: F222 2222 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   3555 5555 2555 5555
Test 8
Parent
 zmm31: 0999 9999 0000 0002   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   9666 6666 1999 9999
 zmm30: 0777 7777 F777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   9444 4444 1777 7777
 zmm29: 0888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 0000 9119   2888 8888 1888 8888
Left
 zmm28: 7666 6666 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 8666 6666
 zmm27: 7444 4444 6444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 8444 4444
 zmm26: F555 5555 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   1555 5555 0555 5555
Right
 zmm25: F333 3333 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 A666 6666
 zmm24: F111 1111 6444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 A444 4444
 zmm23: F222 2222 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   3555 5555 2555 5555
Test 9
Parent
 zmm31: 0999 9999 0000 0002   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   A666 6666 1999 9999
 zmm30: 0777 7777 F777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   A444 4444 1777 7777
 zmm29: 0888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 0000 9119   2888 8888 1888 8888
Left
 zmm28: 8666 6666 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 9666 6666
 zmm27: 8444 4444 7444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 9444 4444
 zmm26: F555 5555 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   1555 5555 0555 5555
Right
 zmm25: F333 3333 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 B666 6666
 zmm24: F111 1111 7444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 B444 4444
 zmm23: F222 2222 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   3555 5555 2555 5555
Test 10
Parent
 zmm31: 0999 9999 0000 0002   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   B666 6666 1999 9999
 zmm30: 0777 7777 F777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   B444 4444 1777 7777
 zmm29: 0888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 0000 9119   2888 8888 1888 8888
Left
 zmm28: 9666 6666 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 A666 6666
 zmm27: 9444 4444 8444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 A444 4444
 zmm26: F555 5555 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   1555 5555 0555 5555
Right
 zmm25: F333 3333 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 C666 6666
 zmm24: F111 1111 8444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 C444 4444
 zmm23: F222 2222 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   3555 5555 2555 5555
Test 11
Parent
 zmm31: 0999 9999 0000 0002   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   C666 6666 1999 9999
 zmm30: 0777 7777 F777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   C444 4444 1777 7777
 zmm29: 0888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 0000 9119   2888 8888 1888 8888
Left
 zmm28: A666 6666 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 B666 6666
 zmm27: A444 4444 9444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 B444 4444
 zmm26: F555 5555 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   1555 5555 0555 5555
Right
 zmm25: F333 3333 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 D666 6666
 zmm24: F111 1111 9444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 D444 4444
 zmm23: F222 2222 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   3555 5555 2555 5555
Test 12
Parent
 zmm31: 0999 9999 0000 0002   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   D666 6666 1999 9999
 zmm30: 0777 7777 F777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   D444 4444 1777 7777
 zmm29: 0888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 0000 9119   2888 8888 1888 8888
Left
 zmm28: B666 6666 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 C666 6666
 zmm27: B444 4444 A444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 C444 4444
 zmm26: F555 5555 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   1555 5555 0555 5555
Right
 zmm25: F333 3333 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 E666 6666
 zmm24: F111 1111 A444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 E444 4444
 zmm23: F222 2222 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   3555 5555 2555 5555
Test 13
Parent
 zmm31: 0999 9999 0000 0002   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   E666 6666 1999 9999
 zmm30: 0777 7777 F777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   E444 4444 1777 7777
 zmm29: 0888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 0000 9119   2888 8888 1888 8888
Left
 zmm28: C666 6666 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 D666 6666
 zmm27: C444 4444 B444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 D444 4444
 zmm26: F555 5555 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   1555 5555 0555 5555
Right
 zmm25: F333 3333 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 F666 6666
 zmm24: F111 1111 B444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 F444 4444
 zmm23: F222 2222 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   3555 5555 2555 5555
END
 }

#latest:
if (1) {                                                                        # Split a root node held in zmm28..zmm26 into a parent in zmm31..zmm29 and a right node held in zmm25..zmm23
  my $newLeft   = K newLeft  => 0x9119;                                         # Offset of new left  block
  my $newRight  = K newRight => 0x9229;                                         # Offset of new right block
  my $tree      = DescribeTree(length => 7);                                    # Tree definition

  my $transfer  = r8;                                                           # Transfer register
  my ($RN, $RD, $RK, $LN, $LD, $LK, $PN, $PD, $PK) = 23..31;                    # Zmm names

  K(PK => Rd(map {($_<<28) +0x9999999} 0..15))->loadZmm($PK);
  K(PD => Rd(map {($_<<28) +0x7777777} 0..15))->loadZmm($PD);
  K(PN => Rd(map {($_<<28) +0x8888888} 0..15))->loadZmm($PN);

  K(LK => Rd(map {($_<<28) +0x6666666} 0..15))->loadZmm($LK);
  K(LD => Rd(map {($_<<28) +0x4444444} 0..15))->loadZmm($LD);
  K(LN => Rd(map {($_<<28) +0x5555555} 0..15))->loadZmm($LN);

  K(RK => Rd(map {($_<<28) +0x3333333} 0..15))->loadZmm($RK);
  K(RD => Rd(map {($_<<28) +0x1111111} 0..15))->loadZmm($RD);
  K(RN => Rd(map {($_<<28) +0x2222222} 0..15))->loadZmm($RN);

  Mov $transfer, 0b11011101;                                                    # Test set of tree bits
  wRegIntoZmm $transfer, $LK, $tree->treeBits;

  Mov $transfer, 7;                                                             # Test set of length in left keys
  wRegIntoZmm $transfer, $LK, $tree->lengthOffset;
  PrintOutStringNL "Initial Parent";
  PrintOutRegisterInHex zmm reverse 29..31;

  PrintOutStringNL "Initial Left";
  PrintOutRegisterInHex zmm reverse 26..28;

  PrintOutStringNL "Initial Right";
  PrintOutRegisterInHex zmm reverse 23..25;

  $tree->splitRoot($newLeft, $newRight, reverse 23..31);

  PrintOutStringNL "Final Parent";
  PrintOutRegisterInHex zmm reverse 29..31;

  PrintOutStringNL "Final Left";
  PrintOutRegisterInHex zmm reverse 26..28;

  PrintOutStringNL "Final Right";
  PrintOutRegisterInHex zmm reverse 23..25;

  ok Assemble eq => <<END;
Initial Parent
 zmm31: F999 9999 E999 9999   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   1999 9999 0999 9999
 zmm30: F777 7777 E777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   1777 7777 0777 7777
 zmm29: F888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 2888 8888   1888 8888 0888 8888
Initial Left
 zmm28: F666 6666 00DD 0007   D666 6666 C666 6666   B666 6666 A666 6666   9666 6666 8666 6666   7666 6666 6666 6666   5666 6666 4666 6666   3666 6666 2666 6666   1666 6666 0666 6666
 zmm27: F444 4444 E444 4444   D444 4444 C444 4444   B444 4444 A444 4444   9444 4444 8444 4444   7444 4444 6444 4444   5444 4444 4444 4444   3444 4444 2444 4444   1444 4444 0444 4444
 zmm26: F555 5555 E555 5555   D555 5555 C555 5555   B555 5555 A555 5555   9555 5555 8555 5555   7555 5555 6555 5555   5555 5555 4555 5555   3555 5555 2555 5555   1555 5555 0555 5555
Initial Right
 zmm25: F333 3333 E333 3333   D333 3333 C333 3333   B333 3333 A333 3333   9333 3333 8333 3333   7333 3333 6333 3333   5333 3333 4333 3333   3333 3333 2333 3333   1333 3333 0333 3333
 zmm24: F111 1111 E111 1111   D111 1111 C111 1111   B111 1111 A111 1111   9111 1111 8111 1111   7111 1111 6111 1111   5111 1111 4111 1111   3111 1111 2111 1111   1111 1111 0111 1111
 zmm23: F222 2222 E222 2222   D222 2222 C222 2222   B222 2222 A222 2222   9222 2222 8222 2222   7222 2222 6222 2222   5222 2222 4222 2222   3222 2222 2222 2222   1222 2222 0222 2222
Final Parent
 zmm31: F999 9999 0001 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 3666 6666
 zmm30: F777 7777 E777 7777   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 3444 4444
 zmm29: F888 8888 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 9229 0000 9119
Final Left
 zmm28: F666 6666 0005 0003   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 2666 6666   1666 6666 0666 6666
 zmm27: F444 4444 E444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 2444 4444   1444 4444 0444 4444
 zmm26: F555 5555 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   3555 5555 2555 5555   1555 5555 0555 5555
Final Right
 zmm25: F333 3333 0005 0003   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 6666 6666   5666 6666 4666 6666
 zmm24: F111 1111 E444 4444   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 6444 4444   5444 4444 4444 4444
 zmm23: F222 2222 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   7555 5555 6555 5555   5555 5555 4555 5555
END
 }

sub Nasm::X86::Tree::copyNonLoopArea($$$$$$$)                                   # Copy the non loop area of one tree block into another
 {my ($tree, $PK, $PD, $PN, $LK, $LD, $LN) = @_;                                # Tree definition, parent keys zmm, data zmm, nodes zmm, left keys zmm, data zmm, nodes zmm.
  @_ == 7 or confess "Seven parameters required";

  my $transfer  = r8;                                                           # Transfer register

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Variable parameters, structure variables, structure copies, subroutine description

    my $transfer  = r8;                                                         # Transfer register

    PushR $transfer, 7;
    LoadBitsIntoMaskRegister(7, '0', $tree->maxNodesZ);                         # Move non loop area
    Vmovdqu32 zmmM($LK, 7),  zmm($PK);
    Vmovdqu32 zmmM($LD, 7),  zmm($PD);
    Vmovdqu32 zmmM($LN, 7),  zmm($PN);
    PopR;
   }
  name => "Nasm::X86::Tree::copyNonLoopArea($PK, $PD, $PN, $LK, $LD, $LN)";

  $s->call;
 }

#latest:
if (1) {                                                                        # Move non loop bytes from one tree block to another
  my $tree = DescribeTree(length=>3);
  my ($RN, $RD, $RK, $LN, $LD, $LK, $PN, $PD, $PK) = 23..31;                    # Zmm names

  K(PK => Rd(map {($_<<28) +0x9999999} 0..15))->loadZmm($PK);
  K(PD => Rd(map {($_<<28) +0x7777777} 0..15))->loadZmm($PD);
  K(PN => Rd(map {($_<<28) +0x8888888} 0..15))->loadZmm($PN);

  K(LK => Rd(map {($_<<28) +0x6666666} 0..15))->loadZmm($LK);
  K(LD => Rd(map {($_<<28) +0x4444444} 0..15))->loadZmm($LD);
  K(LN => Rd(map {($_<<28) +0x5555555} 0..15))->loadZmm($LN);

  PrintOutStringNL "Initial Parent";
  PrintOutRegisterInHex zmm reverse 29..31;

  PrintOutStringNL "Initial Left";
  PrintOutRegisterInHex zmm reverse 26..28;

  $tree->copyNonLoopArea($PK, $PD, $PN, $LK, $LD, $LN);

  PrintOutStringNL "Final Parent";
  PrintOutRegisterInHex zmm reverse 29..31;

  PrintOutStringNL "Final Left";
  PrintOutRegisterInHex zmm reverse 26..28;

  ok Assemble eq => <<END;
Initial Parent
 zmm31: F999 9999 E999 9999   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   1999 9999 0999 9999
 zmm30: F777 7777 E777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   1777 7777 0777 7777
 zmm29: F888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 2888 8888   1888 8888 0888 8888
Initial Left
 zmm28: F666 6666 E666 6666   D666 6666 C666 6666   B666 6666 A666 6666   9666 6666 8666 6666   7666 6666 6666 6666   5666 6666 4666 6666   3666 6666 2666 6666   1666 6666 0666 6666
 zmm27: F444 4444 E444 4444   D444 4444 C444 4444   B444 4444 A444 4444   9444 4444 8444 4444   7444 4444 6444 4444   5444 4444 4444 4444   3444 4444 2444 4444   1444 4444 0444 4444
 zmm26: F555 5555 E555 5555   D555 5555 C555 5555   B555 5555 A555 5555   9555 5555 8555 5555   7555 5555 6555 5555   5555 5555 4555 5555   3555 5555 2555 5555   1555 5555 0555 5555
Final Parent
 zmm31: F999 9999 E999 9999   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   1999 9999 0999 9999
 zmm30: F777 7777 E777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   1777 7777 0777 7777
 zmm29: F888 8888 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 2888 8888   1888 8888 0888 8888
Final Left
 zmm28: F666 6666 E999 9999   D999 9999 C999 9999   B999 9999 A999 9999   9999 9999 8999 9999   7999 9999 6999 9999   5999 9999 4999 9999   3999 9999 2999 9999   1999 9999 0999 9999
 zmm27: F444 4444 E777 7777   D777 7777 C777 7777   B777 7777 A777 7777   9777 7777 8777 7777   7777 7777 6777 7777   5777 7777 4777 7777   3777 7777 2777 7777   1777 7777 0777 7777
 zmm26: F555 5555 E888 8888   D888 8888 C888 8888   B888 8888 A888 8888   9888 8888 8888 8888   7888 8888 6888 8888   5888 8888 4888 8888   3888 8888 2888 8888   1888 8888 0888 8888
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::setTree  #TNasm::X86::Tree::clearTree #TNasm::X86::Tree::insertZeroIntoTreeBits #TNasm::X86::Tree::insertOneIntoTreeBits #TNasm::X86::Tree::getTreeBits #TNasm::X86::Tree::setTreeBits #TNasm::X86::Tree::isTree

  my $t = DescribeTree;
  Mov r8, 0b100; $t->setTreeBit(31, r8);              PrintOutRegisterInHex 31;
  Mov r8, 0b010; $t->setTreeBit(31, r8);              PrintOutRegisterInHex 31;
  Mov r8, 0b001; $t->setTreeBit(31, r8);              PrintOutRegisterInHex 31;
  Mov r8, 0b010; $t->clearTreeBit(31, r8);            PrintOutRegisterInHex 31;

                                                     $t->getTreeBits(31, r8); V(TreeBits => r8)->outRightInBinNL(K width => 16);
  Mov r8, 0b010; $t->insertZeroIntoTreeBits(31, r8); $t->getTreeBits(31, r8); V(TreeBits => r8)->outRightInBinNL(K width => 16);
  Mov r8, 0b010; $t->insertOneIntoTreeBits (31, r8); $t->getTreeBits(31, r8); V(TreeBits => r8)->outRightInBinNL(K width => 16);

  $t->getTreeBits(31, r8);
  V(TreeBits => r8)->outRightInHexNL(K width => 4);
  PrintOutRegisterInHex 31;

  Mov r8, 1; $t->isTree(31, r8); PrintOutZF;
  Shl r8, 1; $t->isTree(31, r8); PrintOutZF;
  Shl r8, 1; $t->isTree(31, r8); PrintOutZF;
  Shl r8, 1; $t->isTree(31, r8); PrintOutZF;

  Shl r8, 1; $t->isTree(31, r8); PrintOutZF;
  Shl r8, 1; $t->isTree(31, r8); PrintOutZF;
  Shl r8, 1; $t->isTree(31, r8); PrintOutZF;
  Shl r8, 1; $t->isTree(31, r8); PrintOutZF;

  Shl r8, 1; $t->isTree(31, r8); PrintOutZF;
  Shl r8, 1; $t->isTree(31, r8); PrintOutZF;
  Shl r8, 1; $t->isTree(31, r8); PrintOutZF;
  Shl r8, 1; $t->isTree(31, r8); PrintOutZF;

  Shl r8, 1; $t->isTree(31, r8); PrintOutZF;
  Shl r8, 1; $t->isTree(31, r8); PrintOutZF;
  Shl r8, 1; $t->isTree(31, r8); PrintOutZF;
  Shl r8, 1; $t->isTree(31, r8); PrintOutZF;

  Not r8; $t->setTreeBits(31, r8);                   PrintOutRegisterInHex 31;

  ok Assemble eq => <<END;
 zmm31: 0000 0000 0004 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
 zmm31: 0000 0000 0006 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
 zmm31: 0000 0000 0007 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
 zmm31: 0000 0000 0005 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
             101
            1001
           10011
  13
 zmm31: 0000 0000 0013 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
ZF=0
ZF=0
ZF=1
ZF=1
ZF=0
ZF=1
ZF=1
ZF=1
ZF=1
ZF=1
ZF=1
ZF=1
ZF=1
ZF=1
ZF=1
ZF=1
 zmm31: 0000 0000 3FFF 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::allocBlock #TNasm::X86::Tree::putBlock #TNasm::X86::Tree::getBlock #TNasm::X86::Tree::root
  my $a = CreateArena;
  my $t = $a->CreateTree;
  my $b = $t->allocBlock(31, 30, 29);
  K(data => 0x33)->dIntoZ(31, 4);
  $t->lengthIntoKeys(31, K length =>0x9);
  $t->putBlock($b, 31, 30, 29);
  $t->getBlock($b, 25, 24, 23);
  PrintOutRegisterInHex 25;
  $t->lengthFromKeys(25)->outNL;


  $t->firstFromMemory(28);
  $t->incSizeInFirst (28);
  $t->rootIntoFirst  (28, K value => 0x2222);
  $t->root           (28, K value => 0x2222);  PrintOutZF;
  $t->root           (28, K value => 0x2221);  PrintOutZF;
  $t->root           (28, K value => 0x2222);  PrintOutZF;
  $t->firstIntoMemory(28);

  $t->first->outNL;
  $b->outNL;
  $a->dump("1111");
  PrintOutRegisterInHex 31, 30, 29, 28;


  my $l = $t->leafFromNodes(29); If $l > 0, Then {PrintOutStringNL "29 Leaf"}, Else {PrintOutStringNL "29 Branch"};
  my $r = $t->leafFromNodes(28); If $r > 0, Then {PrintOutStringNL "28 Leaf"}, Else {PrintOutStringNL "28 Branch"};


  ok Assemble eq => <<END;
 zmm25: 0000 00C0 0000 0009   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0033 0000 0000
b at offset 56 in zmm25: 0000 0000 0000 0009
ZF=1
ZF=0
ZF=1
first: 0000 0000 0000 0040
address: 0000 0000 0000 0080
1111
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | 2222 ____ ____ ____  01__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ 33__ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  09__ ____ C0__ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ __01 ____
 zmm31: 0000 00C0 0000 0009   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0033 0000 0000
 zmm30: 0000 0100 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
 zmm29: 0000 0040 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
 zmm28: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0001   0000 0000 0000 2222
29 Leaf
28 Branch
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::indexEq
  my $tree = DescribeTree(length => 7);

  my $K = 31;

  K(K => Rd(0..15))->loadZmm($K);
  $tree->lengthIntoKeys($K, K length => 13);

  K(loop => 16)->for(sub
   {my ($index, $start, $next, $end) = @_;
    my $f = $tree->indexEq ($index, $K);
    $index->outRightInDec(K width =>  2);
    $f    ->outRightInBin(K width => 14);
    PrintOutStringNL " |"
   });

  ok Assemble eq => <<END;
 0             1 |
 1            10 |
 2           100 |
 3          1000 |
 4         10000 |
 5        100000 |
 6       1000000 |
 7      10000000 |
 8     100000000 |
 9    1000000000 |
10   10000000000 |
11  100000000000 |
12 1000000000000 |
13               |
14               |
15               |
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::insertionPoint
  my $tree = DescribeTree(length => 7);

  my $K = 31;

  K(K => Rd(map {2*$_} 1..16))->loadZmm($K);
  $tree->lengthIntoKeys($K, K length => 13);

  K(loop => 32)->for(sub
   {my ($index, $start, $next, $end) = @_;
    my $f = $tree->insertionPoint($index, $K);
    $index->outRightInDec(K width =>  2);
    $f    ->outRightInBin(K width => 16);
    PrintOutStringNL " |"
   });

  ok Assemble eq => <<END;
 0               1 |
 1               1 |
 2              10 |
 3              10 |
 4             100 |
 5             100 |
 6            1000 |
 7            1000 |
 8           10000 |
 9           10000 |
10          100000 |
11          100000 |
12         1000000 |
13         1000000 |
14        10000000 |
15        10000000 |
16       100000000 |
17       100000000 |
18      1000000000 |
19      1000000000 |
20     10000000000 |
21     10000000000 |
22    100000000000 |
23    100000000000 |
24   1000000000000 |
25   1000000000000 |
26  10000000000000 |
27  10000000000000 |
28  10000000000000 |
29  10000000000000 |
30  10000000000000 |
31  10000000000000 |
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Variable::dFromPointInZ
  my $tree = DescribeTree(length => 7);

  my $K = 31;

  K(K => Rd(0..15))->loadZmm($K);

  PrintOutRegisterInHex zmm $K;
  K( offset => 1 << 5)->dFromPointInZ($K)->outNL;

  ok Assemble eq => <<END;
 zmm31: 0000 000F 0000 000E   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002   0000 0001 0000 0000
d: 0000 0000 0000 0005
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::indexEq
  my $tree = DescribeTree();
  $tree->maskForFullKeyArea(7);                                                 # Mask for full key area
  PrintOutRegisterInHex k7;
  $tree->maskForFullNodesArea(7);                                               # Mask for full nodes area
  PrintOutRegisterInHex k7;
  ok Assemble eq => <<END;
    k7: 0000 0000 0000 3FFF
    k7: 0000 0000 0000 7FFF
END
 }

#latest:
if (1) {                                                                        # Perform the insertion
  my $tree = DescribeTree();

  my $W1 = r8;
  my $F = 31; my $K  = 30; my $D = 29;
  my $IK = K insert  => 0x44;
  my $ID = K insert  => 0x55;
  my $tb = K treebit => 1;                                                      # Value to insert, tree bit to insert

  K(K => Rd(0..15))->loadZmm($_) for $F, $K, $D;                                # First, keys, data
  $tree->lengthIntoKeys($K, K length => 5);                                     # Set a length
  Mov $W1, 0x3FF0;                                                              # Initial tree bits
  $tree->setTreeBits(31, $W1);                                                  # Save tree bits

  my $point = K point => 1<<3;                                                  # Show insertion point

  PrintOutStringNL "Start";
  PrintOutRegisterInHex $F, $K, $D;

  $tree->insertKeyDataTreeIntoLeaf($point, $F, $K, $D, $IK, $ID, K subTree => 1);

  PrintOutStringNL "Inserted";
  PrintOutRegisterInHex $F, $K, $D;

  $tree->overWriteKeyDataTreeInLeaf($point, $K, $D, $ID, $IK, K subTree => 0);

  PrintOutStringNL "Overwritten";
  PrintOutRegisterInHex $F, $K, $D;

  ok Assemble eq => <<END;                                                      # Once we know the insertion point we can add the key/data/subTree triple, increase the length and update the tree bits
Start
 zmm31: 0000 000F 3FF0 000E   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002   0000 0001 0000 0000
 zmm30: 0000 000F 0000 0005   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002   0000 0001 0000 0000
 zmm29: 0000 000F 0000 000E   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002   0000 0001 0000 0000
Inserted
 zmm31: 0000 000F 3FF0 000E   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0003   0000 0001 0000 0000
 zmm30: 0000 000F 0008 0006   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003   0000 0044 0000 0002   0000 0001 0000 0000
 zmm29: 0000 000F 0000 000E   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003   0000 0055 0000 0002   0000 0001 0000 0000
Overwritten
 zmm31: 0000 000F 3FF0 000E   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0003   0000 0001 0000 0000
 zmm30: 0000 000F 0000 0006   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003   0000 0055 0000 0002   0000 0001 0000 0000
 zmm29: 0000 000F 0000 000E   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003   0000 0044 0000 0002   0000 0001 0000 0000
END
 }

#latest:
if (1) {
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);

  $a->dump("0000", K depth => 6);
  $t->dump("0000");

  $t->put(K(key=>1), K(data=>0x11));
  $a->dump("1111", K depth => 6);
  $t->dump("1111");

  $t->put(K(key=>2), K(data=>0x22));
  $a->dump("2222", K depth => 6);
  $t->dump("2222");

  $t->put(K(key=>3), K(data=>0x33));
  $a->dump("3333", K depth => 6);
  $t->dump("3333");

  $t->splitNode(K offset => 0x80);
  $a->dump("4444", K depth => 11);
  $t->dump("4444");

  ok Assemble eq => <<END;
0000
Arena     Size:     4096    Used:      128
0000 0000 0000 0000 | __10 ____ ____ ____  80__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 00C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0100 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0140 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000
- empty
1111
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | 80__ ____ ____ ____  01__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | 01__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ C0__ ____
0000 0000 0000 00C0 | 11__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ __01 ____
0000 0000 0000 0100 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 0140 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
1111
At:   80                    length:    1,  data:   C0,  nodes:  100,  first:   40, root, leaf
  Index:    0
  Keys :    1
  Data :   17
end
2222
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | 80__ ____ ____ ____  02__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | 01__ ____ 02__ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  02__ ____ C0__ ____
0000 0000 0000 00C0 | 11__ ____ 22__ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ __01 ____
0000 0000 0000 0100 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 0140 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
2222
At:   80                    length:    2,  data:   C0,  nodes:  100,  first:   40, root, leaf
  Index:    0    1
  Keys :    1    2
  Data :   17   34
end
3333
Arena     Size:     4096    Used:      320
0000 0000 0000 0000 | __10 ____ ____ ____  4001 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | 80__ ____ ____ ____  03__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | 01__ ____ 02__ ____  03__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  03__ ____ C0__ ____
0000 0000 0000 00C0 | 11__ ____ 22__ ____  33__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ __01 ____
0000 0000 0000 0100 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 0140 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
3333
At:   80                    length:    3,  data:   C0,  nodes:  100,  first:   40, root, leaf
  Index:    0    1    2
  Keys :    1    2    3
  Data :   17   34   51
end
4444
Arena     Size:     4096    Used:      704
0000 0000 0000 0000 | __10 ____ ____ ____  C002 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | __02 ____ ____ ____  03__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | 01__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ C0__ ____
0000 0000 0000 00C0 | 11__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  __02 ____ __01 ____
0000 0000 0000 0100 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 0140 | 03__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ 8001 ____
0000 0000 0000 0180 | 33__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  __02 ____ C001 ____
0000 0000 0000 01C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 0200 | 02__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ 4002 ____
0000 0000 0000 0240 | 22__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 8002 ____
0000 0000 0000 0280 | 80__ ____ 4001 ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
4444
At:  200                    length:    1,  data:  240,  nodes:  280,  first:   40, root, parent
  Index:    0
  Keys :    2
  Data :   34
  Nodes:   80  140
    At:   80                length:    1,  data:   C0,  nodes:  100,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    1
      Data :   17
    end
    At:  140                length:    1,  data:  180,  nodes:  1C0,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    3
      Data :   51
    end
end
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::put
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);

  $t->put(K(key=>1), K(data=>0x11));
  $t->put(K(key=>2), K(data=>0x22));
  $t->put(K(key=>3), K(data=>0x33));
  $t->put(K(key=>4), K(data=>0x44));
  $a->dump("4444", K depth => 11);
  $t->dump("4444");

  ok Assemble eq => <<END;
4444
Arena     Size:     4096    Used:      704
0000 0000 0000 0000 | __10 ____ ____ ____  C002 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | __02 ____ ____ ____  04__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | 01__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ C0__ ____
0000 0000 0000 00C0 | 11__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  __02 ____ __01 ____
0000 0000 0000 0100 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 0140 | 03__ ____ 04__ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  02__ ____ 8001 ____
0000 0000 0000 0180 | 33__ ____ 44__ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  __02 ____ C001 ____
0000 0000 0000 01C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 0200 | 02__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ 4002 ____
0000 0000 0000 0240 | 22__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 8002 ____
0000 0000 0000 0280 | 80__ ____ 4001 ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
4444
At:  200                    length:    1,  data:  240,  nodes:  280,  first:   40, root, parent
  Index:    0
  Keys :    2
  Data :   34
  Nodes:   80  140
    At:   80                length:    1,  data:   C0,  nodes:  100,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    1
      Data :   17
    end
    At:  140                length:    2,  data:  180,  nodes:  1C0,  first:   40,  up:  200, leaf
      Index:    0    1
      Keys :    3    4
      Data :   51   68
    end
end
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::put
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);

  $t->put(K(key=>1), K(data=>0x11));
  $t->put(K(key=>2), K(data=>0x22));
  $t->put(K(key=>3), K(data=>0x33));
  $t->put(K(key=>4), K(data=>0x44));
  $t->put(K(key=>5), K(data=>0x55));
  $a->dump("5555",   K depth => 11);

  ok Assemble eq => <<END;
5555
Arena     Size:     4096    Used:      704
0000 0000 0000 0000 | __10 ____ ____ ____  C002 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | __02 ____ ____ ____  05__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | 01__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ C0__ ____
0000 0000 0000 00C0 | 11__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  __02 ____ __01 ____
0000 0000 0000 0100 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 0140 | 03__ ____ 04__ ____  05__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  03__ ____ 8001 ____
0000 0000 0000 0180 | 33__ ____ 44__ ____  55__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  __02 ____ C001 ____
0000 0000 0000 01C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 0200 | 02__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ 4002 ____
0000 0000 0000 0240 | 22__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 8002 ____
0000 0000 0000 0280 | 80__ ____ 4001 ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::put
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);

  $t->put(K(key=>1), K(data=>0x11));
  $t->put(K(key=>2), K(data=>0x22));
  $t->put(K(key=>3), K(data=>0x33));
  $t->put(K(key=>4), K(data=>0x44));
  $t->put(K(key=>5), K(data=>0x55));
  $t->splitNode(K split => 0x140);
  $a->dump("6666",   K depth => 14);

  ok Assemble eq => <<END;
6666
Arena     Size:     4096    Used:      896
0000 0000 0000 0000 | __10 ____ ____ ____  8003 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | __02 ____ ____ ____  05__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | 01__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ C0__ ____
0000 0000 0000 00C0 | 11__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  __02 ____ __01 ____
0000 0000 0000 0100 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 0140 | 03__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ 8001 ____
0000 0000 0000 0180 | 33__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  __02 ____ C001 ____
0000 0000 0000 01C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 0200 | 02__ ____ 04__ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  02__ ____ 4002 ____
0000 0000 0000 0240 | 22__ ____ 44__ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 8002 ____
0000 0000 0000 0280 | 80__ ____ 4001 ____  C002 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 02C0 | 05__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ __03 ____
0000 0000 0000 0300 | 55__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  __02 ____ 4003 ____
0000 0000 0000 0340 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::put
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);

  $t->put(K(key=>1), K(data=>0x11));
  $t->put(K(key=>2), K(data=>0x22));
  $t->put(K(key=>3), K(data=>0x33));
  $t->put(K(key=>4), K(data=>0x44));
  $t->put(K(key=>5), K(data=>0x55));
  $t->put(K(key=>6), K(data=>0x66));
  $a->dump("6666",   K depth => 14);

  ok Assemble eq => <<END;
6666
Arena     Size:     4096    Used:      896
0000 0000 0000 0000 | __10 ____ ____ ____  8003 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | __02 ____ ____ ____  06__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | 01__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ C0__ ____
0000 0000 0000 00C0 | 11__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  __02 ____ __01 ____
0000 0000 0000 0100 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 0140 | 03__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ 8001 ____
0000 0000 0000 0180 | 33__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  __02 ____ C001 ____
0000 0000 0000 01C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 0200 | 02__ ____ 04__ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  02__ ____ 4002 ____
0000 0000 0000 0240 | 22__ ____ 44__ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 8002 ____
0000 0000 0000 0280 | 80__ ____ 4001 ____  C002 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 02C0 | 05__ ____ 06__ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  02__ ____ __03 ____
0000 0000 0000 0300 | 55__ ____ 66__ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  __02 ____ 4003 ____
0000 0000 0000 0340 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::put
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);

  $t->put(K(key=>1), K(data=>0x11));
  $t->put(K(key=>2), K(data=>0x22));
  $t->put(K(key=>3), K(data=>0x33));
  $t->put(K(key=>4), K(data=>0x44));
  $t->put(K(key=>5), K(data=>0x55));
  $t->put(K(key=>6), K(data=>0x66));
  $t->put(K(key=>7), K(data=>0x77));
  $a->dump("7777",   K depth => 14);

  ok Assemble eq => <<END;
7777
Arena     Size:     4096    Used:      896
0000 0000 0000 0000 | __10 ____ ____ ____  8003 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0040 | __02 ____ ____ ____  07__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____
0000 0000 0000 0080 | 01__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ C0__ ____
0000 0000 0000 00C0 | 11__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  __02 ____ __01 ____
0000 0000 0000 0100 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 0140 | 03__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  01__ ____ 8001 ____
0000 0000 0000 0180 | 33__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  __02 ____ C001 ____
0000 0000 0000 01C0 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 0200 | 02__ ____ 04__ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  02__ ____ 4002 ____
0000 0000 0000 0240 | 22__ ____ 44__ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 8002 ____
0000 0000 0000 0280 | 80__ ____ 4001 ____  C002 ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
0000 0000 0000 02C0 | 05__ ____ 06__ ____  07__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  03__ ____ __03 ____
0000 0000 0000 0300 | 55__ ____ 66__ ____  77__ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  __02 ____ 4003 ____
0000 0000 0000 0340 | ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ ____ ____  ____ ____ 40__ ____
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::put
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);

  $t->put(K(key=>1), K(data=>0x11));
  $t->put(K(key=>2), K(data=>0x22));
  $t->put(K(key=>3), K(data=>0x33));
  $t->put(K(key=>4), K(data=>0x44));
  $t->put(K(key=>5), K(data=>0x55));
  $t->put(K(key=>6), K(data=>0x66));
  $t->put(K(key=>7), K(data=>0x77));
  $t->put(K(key=>8), K(data=>0x88));
  $t->dump("8888");

  ok Assemble eq => <<END;
8888
At:  500                    length:    1,  data:  540,  nodes:  580,  first:   40, root, parent
  Index:    0
  Keys :    4
  Data :   68
  Nodes:  200  440
    At:  200                length:    1,  data:  240,  nodes:  280,  first:   40,  up:  500, parent
      Index:    0
      Keys :    2
      Data :   34
      Nodes:   80  140
        At:   80            length:    1,  data:   C0,  nodes:  100,  first:   40,  up:  200, leaf
          Index:    0
          Keys :    1
          Data :   17
        end
        At:  140            length:    1,  data:  180,  nodes:  1C0,  first:   40,  up:  200, leaf
          Index:    0
          Keys :    3
          Data :   51
        end
    end
    At:  440                length:    1,  data:  480,  nodes:  4C0,  first:   40,  up:  500, parent
      Index:    0
      Keys :    6
      Data :  102
      Nodes:  2C0  380
        At:  2C0            length:    1,  data:  300,  nodes:  340,  first:   40,  up:  440, leaf
          Index:    0
          Keys :    5
          Data :   85
        end
        At:  380            length:    2,  data:  3C0,  nodes:  400,  first:   40,  up:  440, leaf
          Index:    0    1
          Keys :    7    8
          Data :  119  136
        end
    end
end
END
 }

#latest:
if (1) {
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);

  $t->put(K(key=>2), K(data=>0x22));
  $t->put(K(key=>1), K(data=>0x11));
  $t->dump("2222");

  ok Assemble eq => <<END;
2222
At:   80                    length:    2,  data:   C0,  nodes:  100,  first:   40, root, leaf
  Index:    0    1
  Keys :    1    2
  Data :   17   34
end
END
 }

#latest:
if (1) {
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);

  $t->put(K(key=>8), K(data=>0x88));
  $t->put(K(key=>7), K(data=>0x77));
  $t->put(K(key=>6), K(data=>0x66));
  $t->put(K(key=>5), K(data=>0x55));
  $t->put(K(key=>4), K(data=>0x44));
  $t->put(K(key=>3), K(data=>0x33));
  $t->put(K(key=>2), K(data=>0x22));
  $t->put(K(key=>1), K(data=>0x11));
  $t->dump("8888");

  ok Assemble eq => <<END;
8888
At:  500                    length:    1,  data:  540,  nodes:  580,  first:   40, root, parent
  Index:    0
  Keys :    5
  Data :   85
  Nodes:  200  440
    At:  200                length:    1,  data:  240,  nodes:  280,  first:   40,  up:  500, parent
      Index:    0
      Keys :    3
      Data :   51
      Nodes:   80  380
        At:   80            length:    2,  data:   C0,  nodes:  100,  first:   40,  up:  200, leaf
          Index:    0    1
          Keys :    1    2
          Data :   17   34
        end
        At:  380            length:    1,  data:  3C0,  nodes:  400,  first:   40,  up:  200, leaf
          Index:    0
          Keys :    4
          Data :   68
        end
    end
    At:  440                length:    1,  data:  480,  nodes:  4C0,  first:   40,  up:  500, parent
      Index:    0
      Keys :    7
      Data :  119
      Nodes:  2C0  140
        At:  2C0            length:    1,  data:  300,  nodes:  340,  first:   40,  up:  440, leaf
          Index:    0
          Keys :    6
          Data :  102
        end
        At:  140            length:    1,  data:  180,  nodes:  1C0,  first:   40,  up:  440, leaf
          Index:    0
          Keys :    8
          Data :  136
        end
    end
end
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::put #TNasm::X86::Tree::find
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);
  my $N = K count => 128;

  $N->for(sub
   {my ($index, $start, $next, $end) = @_;
    my $l = $N-$index;
    $t->put($l, $l * 2);
    my $h = $N+$index;
    $t->put($h, $h * 2);
   });
  $t->put(K(zero=>0), K(zero=>0));
  $t->printInOrder("AAAA");

  PrintOutStringNL 'Indx   Found  Offset  Double   Found  Offset    Quad   Found  Offset    Octo   Found  Offset     *16   Found  Offset     *32   Found  Offset     *64   Found  Offset    *128   Found  Offset    *256   Found  Offset    *512';
  $N->for(sub
   {my ($index, $start, $next, $end) = @_;
    my $i = $index;
    my $j = $i * 2;
    my $k = $j * 2;
    my $l = $k * 2;
    my $m = $l * 2;
    my $n = $m * 2;
    my $o = $n * 2;
    my $p = $o * 2;
    my $q = $p * 2;
    $t->find($i); $i->outRightInDec(K width => 4); $t->found->outRightInBin(K width => 8); $t->offset->outRightInHex(K width => 8);  $t->data->outRightInDec  (K width => 8);
    $t->find($j);                                  $t->found->outRightInBin(K width => 8); $t->offset->outRightInHex(K width => 8);  $t->data->outRightInDec  (K width => 8);
    $t->find($k);                                  $t->found->outRightInBin(K width => 8); $t->offset->outRightInHex(K width => 8);  $t->data->outRightInDec  (K width => 8);
    $t->find($l);                                  $t->found->outRightInBin(K width => 8); $t->offset->outRightInHex(K width => 8);  $t->data->outRightInDec  (K width => 8);
    $t->find($m);                                  $t->found->outRightInBin(K width => 8); $t->offset->outRightInHex(K width => 8);  $t->data->outRightInDec  (K width => 8);
    $t->find($n);                                  $t->found->outRightInBin(K width => 8); $t->offset->outRightInHex(K width => 8);  $t->data->outRightInDec  (K width => 8);
    $t->find($o);                                  $t->found->outRightInBin(K width => 8); $t->offset->outRightInHex(K width => 8);  $t->data->outRightInDec  (K width => 8);
    $t->find($p);                                  $t->found->outRightInBin(K width => 8); $t->offset->outRightInHex(K width => 8);  $t->data->outRightInDec  (K width => 8);
    $t->find($q);                                  $t->found->outRightInBin(K width => 8); $t->offset->outRightInHex(K width => 8);  $t->data->outRightInDecNL(K width => 8);
   });

  ok Assemble eq => <<END;
AAAA
 256:    0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F  10  11  12  13  14  15  16  17  18  19  1A  1B  1C  1D  1E  1F  20  21  22  23  24  25  26  27  28  29  2A  2B  2C  2D  2E  2F  30  31  32  33  34  35  36  37  38  39  3A  3B  3C  3D  3E  3F  40  41  42  43  44  45  46  47  48  49  4A  4B  4C  4D  4E  4F  50  51  52  53  54  55  56  57  58  59  5A  5B  5C  5D  5E  5F  60  61  62  63  64  65  66  67  68  69  6A  6B  6C  6D  6E  6F  70  71  72  73  74  75  76  77  78  79  7A  7B  7C  7D  7E  7F  80  81  82  83  84  85  86  87  88  89  8A  8B  8C  8D  8E  8F  90  91  92  93  94  95  96  97  98  99  9A  9B  9C  9D  9E  9F  A0  A1  A2  A3  A4  A5  A6  A7  A8  A9  AA  AB  AC  AD  AE  AF  B0  B1  B2  B3  B4  B5  B6  B7  B8  B9  BA  BB  BC  BD  BE  BF  C0  C1  C2  C3  C4  C5  C6  C7  C8  C9  CA  CB  CC  CD  CE  CF  D0  D1  D2  D3  D4  D5  D6  D7  D8  D9  DA  DB  DC  DD  DE  DF  E0  E1  E2  E3  E4  E5  E6  E7  E8  E9  EA  EB  EC  ED  EE  EF  F0  F1  F2  F3  F4  F5  F6  F7  F8  F9  FA  FB  FC  FD  FE  FF
Indx   Found  Offset  Double   Found  Offset    Quad   Found  Offset    Octo   Found  Offset     *16   Found  Offset     *32   Found  Offset     *64   Found  Offset    *128   Found  Offset    *256   Found  Offset    *512
   0       1      80       0       1      80       0       1      80       0       1      80       0       1      80       0       1      80       0       1      80       0       1      80       0       1      80       0
   1      10      80       2       1     200       4       1     500       8       1     B00      16       1    1700      32       1    2F00      64       1    5F00     128      10    5F00     256               0       0
   2       1     200       4       1     500       8       1     B00      16       1    1700      32       1    2F00      64       1    5F00     128      10    5F00     256               0       0               0       0
   3       1    B540       6       1    B600      12       1    B6C0      24       1    B780      48       1    B840      96       1    B900     192      10    5E40     384               0       0               0       0
   4       1     500       8       1     B00      16       1    1700      32       1    2F00      64       1    5F00     128      10    5F00     256               0       0               0       0               0       0
   5       1    B3C0      10       1    B180      20       1    AC40      40       1    A100      80       1    89C0     160       1    5E40     320               0       0               0       0               0       0
   6       1    B600      12       1    B6C0      24       1    B780      48       1    B840      96       1    B900     192      10    5E40     384               0       0               0       0               0       0
   7       1    B0C0      14       1    AB80      28       1    A040      56       1    8900     112       1    59C0     224      10    8D80     448               0       0               0       0               0       0
   8       1     B00      16       1    1700      32       1    2F00      64       1    5F00     128      10    5F00     256               0       0               0       0               0       0               0       0
   9       1    AF40      18       1    A700      36       1    95C0      72       1    7280     144       1    2E40     288               0       0               0       0               0       0               0       0
  10       1    B180      20       1    AC40      40       1    A100      80       1    89C0     160       1    5E40     320               0       0               0       0               0       0               0       0
  11       1    AAC0      22       1    9F80      44       1    8840      88       1    5900     176       1    5D80     352               0       0               0       0               0       0               0       0
  12       1    B6C0      24       1    B780      48       1    B840      96       1    B900     192      10    5E40     384               0       0               0       0               0       0               0       0
  13       1    A940      26       1    9B00      52       1    7DC0     104       1    4280     208       1    8D80     416               0       0               0       0               0       0               0       0
  14       1    AB80      28       1    A040      56       1    8900     112       1    59C0     224      10    8D80     448               0       0               0       0               0       0               0       0
  15       1    A640      30       1    9500      60       1    71C0     120       1    2A80     240      10    A400     480               0       0               0       0               0       0               0       0
  16       1    1700      32       1    2F00      64       1    5F00     128      10    5F00     256               0       0               0       0               0       0               0       0               0       0
  17       1    A4C0      34       1    9080      68       1    6740     136       1    1640     272               0       0               0       0               0       0               0       0               0       0
  18       1    A700      36       1    95C0      72       1    7280     144       1    2E40     288               0       0               0       0               0       0               0       0               0       0
  19       1    9EC0      38       1    8780      76       1    5840     152       1    2D80     304               0       0               0       0               0       0               0       0               0       0
  20       1    AC40      40       1    A100      80       1    89C0     160       1    5E40     320               0       0               0       0               0       0               0       0               0       0
  21       1    9D40      42       1    8300      84       1    4DC0     168       1    4580     336               0       0               0       0               0       0               0       0               0       0
  22       1    9F80      44       1    8840      88       1    5900     176       1    5D80     352               0       0               0       0               0       0               0       0               0       0
  23       1    9A40      46       1    7D00      92       1    41C0     184       1    5CC0     368               0       0               0       0               0       0               0       0               0       0
  24       1    B780      48       1    B840      96       1    B900     192      10    5E40     384               0       0               0       0               0       0               0       0               0       0
  25       1    98C0      50       1    7880     100       1    3740     200       1    7580     400               0       0               0       0               0       0               0       0               0       0
  26       1    9B00      52       1    7DC0     104       1    4280     208       1    8D80     416               0       0               0       0               0       0               0       0               0       0
  27       1    9440      54       1    7100     108       1    29C0     216       1    8CC0     432               0       0               0       0               0       0               0       0               0       0
  28       1    A040      56       1    8900     112       1    59C0     224      10    8D80     448               0       0               0       0               0       0               0       0               0       0
  29       1    92C0      58       1    6C80     116       1    1F40     232       1    A400     464               0       0               0       0               0       0               0       0               0       0
  30       1    9500      60       1    71C0     120       1    2A80     240      10    A400     480               0       0               0       0               0       0               0       0               0       0
  31       1    8FC0      62       1    6680     124       1    1340     248      10    AE80     496               0       0               0       0               0       0               0       0               0       0
  32       1    2F00      64       1    5F00     128      10    5F00     256               0       0               0       0               0       0               0       0               0       0               0       0
  33       1    8E40      66       1    6200     132       1     A40     264               0       0               0       0               0       0               0       0               0       0               0       0
  34       1    9080      68       1    6740     136       1    1640     272               0       0               0       0               0       0               0       0               0       0               0       0
  35       1    86C0      70       1    5780     140       1    1580     280               0       0               0       0               0       0               0       0               0       0               0       0
  36       1    95C0      72       1    7280     144       1    2E40     288               0       0               0       0               0       0               0       0               0       0               0       0
  37       1    8540      74       1    5300     148       1    2180     296               0       0               0       0               0       0               0       0               0       0               0       0
  38       1    8780      76       1    5840     152       1    2D80     304               0       0               0       0               0       0               0       0               0       0               0       0
  39       1    8240      78       1    4D00     156       1    2CC0     312               0       0               0       0               0       0               0       0               0       0               0       0
  40       1    A100      80       1    89C0     160       1    5E40     320               0       0               0       0               0       0               0       0               0       0               0       0
  41       1    80C0      82       1    4880     164       1    3980     328               0       0               0       0               0       0               0       0               0       0               0       0
  42       1    8300      84       1    4DC0     168       1    4580     336               0       0               0       0               0       0               0       0               0       0               0       0
  43       1    7C40      86       1    4100     172       1    44C0     344               0       0               0       0               0       0               0       0               0       0               0       0
  44       1    8840      88       1    5900     176       1    5D80     352               0       0               0       0               0       0               0       0               0       0               0       0
  45       1    7AC0      90       1    3C80     180       1    5000     360               0       0               0       0               0       0               0       0               0       0               0       0
  46       1    7D00      92       1    41C0     184       1    5CC0     368               0       0               0       0               0       0               0       0               0       0               0       0
  47       1    77C0      94       1    3680     188       1    5C00     376               0       0               0       0               0       0               0       0               0       0               0       0
  48       1    B840      96       1    B900     192      10    5E40     384               0       0               0       0               0       0               0       0               0       0               0       0
  49       1    7640      98       1    3200     196       1    6980     392               0       0               0       0               0       0               0       0               0       0               0       0
  50       1    7880     100       1    3740     200       1    7580     400               0       0               0       0               0       0               0       0               0       0               0       0
  51       1    7040     102       1    2900     204       1    74C0     408               0       0               0       0               0       0               0       0               0       0               0       0
  52       1    7DC0     104       1    4280     208       1    8D80     416               0       0               0       0               0       0               0       0               0       0               0       0
  53       1    6EC0     106       1    2480     212       1    8000     424               0       0               0       0               0       0               0       0               0       0               0       0
  54       1    7100     108       1    29C0     216       1    8CC0     432               0       0               0       0               0       0               0       0               0       0               0       0
  55       1    6BC0     110       1    1E80     220       1    8C00     440               0       0               0       0               0       0               0       0               0       0               0       0
  56       1    8900     112       1    59C0     224      10    8D80     448               0       0               0       0               0       0               0       0               0       0               0       0
  57       1    6A40     114       1    1A00     228       1    9800     456               0       0               0       0               0       0               0       0               0       0               0       0
  58       1    6C80     116       1    1F40     232       1    A400     464               0       0               0       0               0       0               0       0               0       0               0       0
  59       1    65C0     118       1    1280     236       1    A340     472               0       0               0       0               0       0               0       0               0       0               0       0
  60       1    71C0     120       1    2A80     240      10    A400     480               0       0               0       0               0       0               0       0               0       0               0       0
  61       1    6440     122       1     E00     244       1    AE80     488               0       0               0       0               0       0               0       0               0       0               0       0
  62       1    6680     124       1    1340     248      10    AE80     496               0       0               0       0               0       0               0       0               0       0               0       0
  63       1    6140     126       1     800     252      10    B300     504               0       0               0       0               0       0               0       0               0       0               0       0
  64       1    5F00     128      10    5F00     256               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  65       1    5FC0     130       1     440     260               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  66       1    6200     132       1     A40     264               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  67       1    56C0     134       1     980     268               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  68       1    6740     136       1    1640     272               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  69       1    5540     138       1     F80     276               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  70       1    5780     140       1    1580     280               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  71       1    5240     142       1    14C0     284               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  72       1    7280     144       1    2E40     288               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  73       1    50C0     146       1    1B80     292               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  74       1    5300     148       1    2180     296               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  75       1    4C40     150       1    20C0     300               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  76       1    5840     152       1    2D80     304               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  77       1    4AC0     154       1    2600     308               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  78       1    4D00     156       1    2CC0     312               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  79       1    47C0     158       1    2C00     316               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  80       1    89C0     160       1    5E40     320               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  81       1    4640     162       1    3380     324               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  82       1    4880     164       1    3980     328               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  83       1    4040     166       1    38C0     332               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  84       1    4DC0     168       1    4580     336               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  85       1    3EC0     170       1    3E00     340               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  86       1    4100     172       1    44C0     344               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  87       1    3BC0     174       1    4400     348               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  88       1    5900     176       1    5D80     352               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  89       1    3A40     178       1    4A00     356               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  90       1    3C80     180       1    5000     360               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  91       1    35C0     182       1    4F40     364               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  92       1    41C0     184       1    5CC0     368               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  93       1    3440     186       1    5480     372               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  94       1    3680     188       1    5C00     376               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  95       1    3140     190       1    5B40     380               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  96       1    B900     192      10    5E40     384               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  97       1    2FC0     194       1    6380     388               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  98       1    3200     196       1    6980     392               0       0               0       0               0       0               0       0               0       0               0       0               0       0
  99       1    2840     198       1    68C0     396               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 100       1    3740     200       1    7580     400               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 101       1    26C0     202       1    6E00     404               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 102       1    2900     204       1    74C0     408               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 103       1    23C0     206       1    7400     412               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 104       1    4280     208       1    8D80     416               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 105       1    2240     210       1    7A00     420               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 106       1    2480     212       1    8000     424               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 107       1    1DC0     214       1    7F40     428               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 108       1    29C0     216       1    8CC0     432               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 109       1    1C40     218       1    8480     436               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 110       1    1E80     220       1    8C00     440               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 111       1    1940     222       1    8B40     444               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 112       1    59C0     224      10    8D80     448               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 113       1    17C0     226       1    9200     452               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 114       1    1A00     228       1    9800     456               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 115       1    11C0     230       1    9740     460               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 116       1    1F40     232       1    A400     464               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 117       1    1040     234       1    9C80     468               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 118       1    1280     236       1    A340     472               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 119       1     D40     238       1    A280     476               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 120       1    2A80     240      10    A400     480               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 121       1     BC0     242       1    A880     484               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 122       1     E00     244       1    AE80     488               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 123       1     740     246       1    ADC0     492               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 124       1    1340     248      10    AE80     496               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 125       1     5C0     250       1    B300     500               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 126       1     800     252      10    B300     504               0       0               0       0               0       0               0       0               0       0               0       0               0       0
 127       1     2C0     254      10    B480     508               0       0               0       0               0       0               0       0               0       0               0       0               0       0
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::printInOrder
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);
  my $N = K count => 128;

  $N->for(sub
   {my ($index, $start, $next, $end) = @_;
    my $l0 = ($N-$index) / 2;
    my $l1 = ($N+$index) / 2;
    my $h0 =  $N-$index;
    my $h1 =  $N+$index;
    $t->put($l0, $l0 * 2);
    $t->put($h1, $h1 * 2);
    $t->put($l1, $l1 * 2);
    $t->put($h0, $h0 * 2);
   });
  $t->printInOrder("AAAA");

  ok Assemble eq => <<END;
AAAA
 256:    0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F  10  11  12  13  14  15  16  17  18  19  1A  1B  1C  1D  1E  1F  20  21  22  23  24  25  26  27  28  29  2A  2B  2C  2D  2E  2F  30  31  32  33  34  35  36  37  38  39  3A  3B  3C  3D  3E  3F  40  41  42  43  44  45  46  47  48  49  4A  4B  4C  4D  4E  4F  50  51  52  53  54  55  56  57  58  59  5A  5B  5C  5D  5E  5F  60  61  62  63  64  65  66  67  68  69  6A  6B  6C  6D  6E  6F  70  71  72  73  74  75  76  77  78  79  7A  7B  7C  7D  7E  7F  80  81  82  83  84  85  86  87  88  89  8A  8B  8C  8D  8E  8F  90  91  92  93  94  95  96  97  98  99  9A  9B  9C  9D  9E  9F  A0  A1  A2  A3  A4  A5  A6  A7  A8  A9  AA  AB  AC  AD  AE  AF  B0  B1  B2  B3  B4  B5  B6  B7  B8  B9  BA  BB  BC  BD  BE  BF  C0  C1  C2  C3  C4  C5  C6  C7  C8  C9  CA  CB  CC  CD  CE  CF  D0  D1  D2  D3  D4  D5  D6  D7  D8  D9  DA  DB  DC  DD  DE  DF  E0  E1  E2  E3  E4  E5  E6  E7  E8  E9  EA  EB  EC  ED  EE  EF  F0  F1  F2  F3  F4  F5  F6  F7  F8  F9  FA  FB  FC  FD  FE  FF
END
 }

#latest:
if (1) {
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);
  my $N = K count => 128;

  $N->for(sub
   {my ($index, $start, $next, $end) = @_;
    my $l00 = ($N-$index) / 4;
    my $l01 = ($N+$index) / 4;
    my $h00 =  $N-$index  / 2;
    my $h01 =  $N+$index  / 2;
    my $l10 = ($N-$index) / 4 * 3;
    my $l11 = ($N+$index) / 4 * 3;
    my $h10 =  $N-$index ;
    my $h11 =  $N+$index ;
    $t->put($l00, $l00 * 2);
    $t->put($h01, $h01 * 2);
    $t->put($l01, $l01 * 2);
    $t->put($h00, $h00 * 2);
    $t->put($l10, $l10 * 2);
    $t->put($h11, $h11 * 2);
    $t->put($l11, $l11 * 2);
    $t->put($h10, $h10 * 2);
   });
  $t->printInOrder("AAAA");

  ok Assemble eq => <<END;
AAAA
 256:    0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F  10  11  12  13  14  15  16  17  18  19  1A  1B  1C  1D  1E  1F  20  21  22  23  24  25  26  27  28  29  2A  2B  2C  2D  2E  2F  30  31  32  33  34  35  36  37  38  39  3A  3B  3C  3D  3E  3F  40  41  42  43  44  45  46  47  48  49  4A  4B  4C  4D  4E  4F  50  51  52  53  54  55  56  57  58  59  5A  5B  5C  5D  5E  5F  60  61  62  63  64  65  66  67  68  69  6A  6B  6C  6D  6E  6F  70  71  72  73  74  75  76  77  78  79  7A  7B  7C  7D  7E  7F  80  81  82  83  84  85  86  87  88  89  8A  8B  8C  8D  8E  8F  90  91  92  93  94  95  96  97  98  99  9A  9B  9C  9D  9E  9F  A0  A1  A2  A3  A4  A5  A6  A7  A8  A9  AA  AB  AC  AD  AE  AF  B0  B1  B2  B3  B4  B5  B6  B7  B8  B9  BA  BB  BC  BD  BE  BF  C0  C1  C2  C3  C4  C5  C6  C7  C8  C9  CA  CB  CC  CD  CE  CF  D0  D1  D2  D3  D4  D5  D6  D7  D8  D9  DA  DB  DC  DD  DE  DF  E0  E1  E2  E3  E4  E5  E6  E7  E8  E9  EA  EB  EC  ED  EE  EF  F0  F1  F2  F3  F4  F5  F6  F7  F8  F9  FA  FB  FC  FD  FE  FF
END
 }

sub Nasm::X86::Tree::stealFromRight($$$$$$$$$$)                                 # Steal one key from the node on the right where the current left node,parent node and right node are held in zmm registers and return one if the steal was performed, else zero.
 {my ($tree, $PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN) = @_;                 # Tree definition, parent keys zmm, data zmm, nodes zmm, left keys zmm, data zmm, nodes zmm.
  @_ == 10 or confess "Ten parameters required";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Variable parameters, structure variables, structure copies, subroutine description
    my $t  = $$s{tree};
    my $ll = $t->lengthFromKeys($LK);
    my $lr = $t->lengthFromKeys($RK);

    PushR 7;

    $t->found->copy(0);                                                         # Assume we cannot steal

    Block                                                                       # Check that it is possible to steal key a from the node on the right
     {my ($end, $start) = @_;                                                   # Code with labels supplied
      If $ll != $t->lengthLeft,  Then {Jmp $end};                               # Left not minimal
      If $lr == $t->lengthRight, Then {Jmp $end};                               # Right minimal

      $t->found->copy(1);                                                       # Proceed with the steal

      my $pir = (K one => 1);                                                   # Point of right key to steal
      my $pil = $pir << ($ll - 1);                                              # Point of left key to receive key

      my $rk  = $pir->dFromPointInZ($RK);                                       # Right key to rotate left
      my $rd  = $pir->dFromPointInZ($RD);                                       # Right data to rotate left
      my $rn  = $pir->dFromPointInZ($RN);                                       # Right node to rotate left

      my $pip = $t->insertionPoint($rk, $PK);                                   # Point of parent key to insert
      my $pip1= $pip >> K(one=>1);                                              # Point of parent key to merge in
      my $pk  = $pip1->dFromPointInZ($PK);                                       # Parent key to rotate left
      my $pd  = $pip1->dFromPointInZ($PD);                                       # Parent data to rotate left

      my $pb  = $t->getTreeBit($PK, $pip);                                      # Parent tree bit
      my $rb  = $t->getTreeBit($RK, K one => 1);                                # First right tree bit
      $pip1->dIntoPointInZ($PK, $rk);                                            # Right key into parent
      $pip1->dIntoPointInZ($PD, $rd);                                            # Right data into parent
      $t->setOrClearTreeBitToMatchContent($PK, $pip, $rb);                      # Right tree bit into parent
      $pk->dIntoZ($LK, $t->middleOffset);                                       # Parent key into left
      $pd->dIntoZ($LD, $t->middleOffset);                                       # Parent data into left
      $rn->dIntoZ($LN, $t->rightOffset);                                        # Right node into left

      $t->insertIntoTreeBits($LK, K(position => 1 << $t->lengthLeft), $pb);     # Parent tree bit into left

      LoadConstantIntoMaskRegister                                              # Nodes area
       (7, createBitNumberFromAlternatingPattern '00', $t->maxKeysZ-1, -1);
      Vpcompressd zmmM($RK, 7), zmm($RK);                                       # Compress right keys one slot left
      Vpcompressd zmmM($RD, 7), zmm($RD);                                       # Compress right data one slot left

      LoadConstantIntoMaskRegister                                              # Nodes area
       (7, createBitNumberFromAlternatingPattern '0', $t->maxNodesZ-1, -1);
      Vpcompressd zmmM($RN, 7), zmm($RN);                                       # Compress right nodes one slot left

      $t->incLengthInKeys($LK);                                                 # Increment left hand length
      $t->decLengthInKeys($RK);                                                 # Decrement right hand
     };
    PopR;
   }
  name       =>
  "Nasm::X86::Tree::stealFromRight($$tree{length}, $PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN)",
  structures => {tree => $tree},
  parameters => [qw(result)];

  $s->call(structures => {tree   => $tree});

  $tree                                                                         # Chain
 }

sub Nasm::X86::Tree::stealFromLeft($$$$$$$$$$)                                  # Steal one key from the node on the left where the current left node,parent node and right node are held in zmm registers and return one if the steal was performed, else  zero.
 {my ($tree, $PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN) = @_;                 # Tree definition, parent keys zmm, data zmm, nodes zmm, left keys zmm, data zmm, nodes zmm.
  @_ == 10 or confess "Ten parameters required";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Variable parameters, structure variables, structure copies, subroutine description
    my $t  = $$s{tree};
    my $ll = $t->lengthFromKeys($LK);
    my $lr = $t->lengthFromKeys($RK);

    PushR 7;

    $t->found->copy(0);                                                         # Assume we cannot steal

    Block                                                                       # Check that it is possible to steal a key from the node on the left
     {my ($end, $start) = @_;                                                   # Code with labels supplied
      If $lr != $t->lengthRight,  Then {Jmp $end};                              # Right not minimal
      If $ll == $t->lengthLeft,   Then {Jmp $end};                              # Left minimal

      $t->found->copy(1);                                                       # Proceed with the steal

      my $pir = K(one => 1);                                                    # Point of right key
      my $pil = $pir << ($ll - 1);                                              # Point of left key

      my $lk  = $pil->dFromPointInZ($LK);                                       # Left key to rotate right
      my $ld  = $pil->dFromPointInZ($LD);                                       # Left key to rotate right
      my $ln  = $pil->dFromPointInZ($LN);                                       # Left key to rotate right
      my $lb  = $t->getTreeBit($LK, $pil);                                      # Left tree bit to rotate right

      my $pip = $t->insertionPoint($lk, $PK);                                   # Point of parent key to merge in

      my $pk  = $pip->dFromPointInZ($PK);                                       # Parent key to rotate right
      my $pd  = $pip->dFromPointInZ($PD);                                       # Parent data to rotate right
      my $pb  = $t->getTreeBit($PK, $pip);                                      # Parent tree bit

      LoadConstantIntoMaskRegister                                              # Nodes area
       (7, createBitNumberFromAlternatingPattern '00', $t->maxKeysZ-1, -1);
      Vpexpandd zmmM($RK, 7), zmm($RK);                                         # Expand right keys one slot right
      Vpexpandd zmmM($RD, 7), zmm($RD);                                         # Expand right data one slot right

      LoadConstantIntoMaskRegister                                              # Nodes area
       (7, createBitNumberFromAlternatingPattern '0', $t->maxNodesZ-1, -1);
      Vpexpandd zmmM($RN, 7), zmm($RN);                                         # Expand right nodes one slot right

      $pip->dIntoPointInZ($PK, $lk);                                            # Left key into parent
      $pip->dIntoPointInZ($PD, $ld);                                            # Left data into parent
      $t->setOrClearTreeBitToMatchContent($PK, $pip, $lb);                      # Left tree bit into parent

      $pir->dIntoPointInZ($RK, $pk);                                            # Parent key into right
      $pir->dIntoPointInZ($RD, $pd);                                            # Parent data into right
      $pir->dIntoPointInZ($RN, $ln);                                            # Left node into right
      $t->insertIntoTreeBits($RK, $pir, $pb);                                   # Parent tree bit into right

      $t->decLengthInKeys($LK);                                                 # Decrement left hand
      $t->incLengthInKeys($RK);                                                 # Increment right hand
     };
    PopR;
   }
  name       =>
  "Nasm::X86::Tree::stealFromLeft($$tree{length}, $PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN)",
  structures => {tree => $tree};

  $s->call(structures => {tree   => $tree});

  $tree                                                                         # Chain
 }
# Need to change up to point to new parent for merged in node children
sub Nasm::X86::Tree::merge($$$$$$$$$$)                                          # Merge a left and right node if they are at minimum size.
 {my ($tree, $PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN) = @_;                 # Tree definition, parent keys zmm, data zmm, nodes zmm, left keys zmm, data zmm, nodes zmm.
  @_ == 10 or confess "Ten parameters required";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Variable parameters, structure variables, structure copies, subroutine description
    my $t  = $$s{tree};
    my $ll = $t->lengthFromKeys($LK);
    my $lr = $t->lengthFromKeys($RK);

    PushR 7, 14, 15;

    Block                                                                       # Check that it is possible to steal a key from the node on the left
     {my ($end, $start) = @_;                                                   # Code with labels supplied
      If $ll != $t->lengthLeft,  Then {Jmp $end};                               # Left not minimal
      If $lr != $t->lengthRight, Then {Jmp $end};                               # Right not minimal

      my $pil = K(one => 1);                                                    # Point of first left key
      my $lk  = $pil->dFromPointInZ($LK);                                       # First left key
      my $pip = $t->insertionPoint($lk, $PK);                                   # Point of parent key to merge in
      my $pk  = $pip->dFromPointInZ($PK);                                       # Parent key to merge
      my $pd  = $pip->dFromPointInZ($PD);                                       # Parent data to merge
      my $pn  = $pip->dFromPointInZ($PN);                                       # Parent node to merge
      my $pb  = $t->getTreeBit($PK, $pip);                                      # Parent tree bit

      my $m = K(one => 1) << K( shift => $t->lengthLeft);                       # Position of parent key in left
      $m->dIntoPointInZ($LK, $pk);                                              # Position parent key in left
      $m->dIntoPointInZ($LD, $pd);                                              # Position parent data in left
     #$m->dIntoPointInZ($LN, $pn);                                              # Position parent node in left - not needed because the left and right around teh aprent lkey are the left and right node offsets - we should use this fact to update the children of the right node so that their up pointers point to the left node
      $t->insertIntoTreeBits($LK, $m, $pb);                                     # Tree bit for parent data
      LoadConstantIntoMaskRegister                                              # Keys/Data area
       (7, createBitNumberFromAlternatingPattern '00', $t->lengthRight,   -$t->lengthMiddle);
      Vpexpandd zmmM($LK, 7), zmm($RK);                                         # Expand right keys into left
      Vpexpandd zmmM($LD, 7), zmm($RD);                                         # Expand right data into left
      LoadConstantIntoMaskRegister                                              # Nodes area
       (7, createBitNumberFromAlternatingPattern '0',  $t->lengthRight+1, -$t->lengthMiddle);
      Vpexpandd zmmM($LN, 7), zmm($RN);                                         # Expand right data into left

      $pip->setReg(r15);                                                        # Collapse mask for keys/data in parent
      Not r15;
      And r15, $t->treeBitsMask;
      Kmovq k7, r15;
      Vpcompressd zmmM($PK, 7), zmm($PK);                                       # Collapse parent keys
      Vpcompressd zmmM($PD, 7), zmm($PD);                                       # Collapse data keys

      my $one = K(one => 1);                                                    # Collapse mask for keys/data in parent
#     my $np = (!$pip << $one) >> $one;
      my $np = !$pip << $one;                                                   # Move the compression point up one to remove the matching node
      $np->setReg(14);
      Add r14, 1;                                                               # Fill hole left at position 0
      Kmovq k7, r14;                                                            # Node squeeze mask
      Vpcompressd zmmM($PN, 7), zmm($PN);                                       # Collapse nodes

      my $z = $PK == 31 ? 30: 31;                                               # Collapse parent tree bits
      PushR zmm $z;                                                             # Collapse parent tree bits
      $t->getTreeBits($PK, r15);                                                # Get tree bits
      Kmovq k7, r15;                                                            # Tree bits
      Vpmovm2d zmm($z), k7;                                                     # Broadcast the bits into a zmm
      $pip->setReg(r15);                                                        # Parent insertion point
      Kmovq k7, r15;
      Knotq k7, k7;                                                             # Invert parent insertion point
      Vpcompressd zmmM($z, 7), zmm($z);                                         # Compress
      Vpmovd2m k7, zmm $z;                                                      # Recover bits
      Kmovq r15, k7;
      And r15, $t->treeBitsMask;                                                # Clear trailing bits beyond valid tree bits
      $t->setTreeBits($PK, r15);
      PopR;

      $t->getTreeBits($LK, r15);                                                # Append right tree bits to the Left tree bits
      $t->getTreeBits($RK, r14);                                                # Right tree bits
      my $sl = RegisterSize(r15) * $bitsInByte / 4 - $tree->lengthMiddle;       # Clear bits right of the lower left bits
      Shl r15w, $sl;
      Shr r15w, $sl;

      Shl r14, $tree->lengthMiddle;                                             # Move right tree bits into position
      Or  r15, r14;                                                             # And in left tree bits
      And r15, $t->treeBitsMask;                                                # Clear trailing bits beyond valid tree bits
      $t->setTreeBits($LK, r15);                                                # Set tree bits

      $t->decLengthInKeys($PK);                                                 # Parent now has one less
      $t->lengthIntoKeys($LK, K length => $t->length);                          # Left is now full

     };
    PopR;
   }
  name       =>
  "Nasm::X86::Tree::stealFromLeft($$tree{length}, $PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN)",
  structures => {tree => $tree};

  $s->call(structures => {tree=> $tree});

  $tree                                                                         # Chain
 }

sub Nasm::X86::Tree::deleteFirstKeyAndData($$$$)                                # Delete the first element of a leaf mode returning its characteristics in the calling tree descriptor.
 {my ($tree, $K, $D) = @_;                                                      # Tree definition, keys zmm, data zmm
  @_ == 3 or confess "Three parameters";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Variable parameters, structure variables, structure copies, subroutine description
    my $t = $$s{tree};
    my $l = $t->lengthFromKeys($K);

    PushR 7, 14, 15;

    $t->found->copy(0);                                                         # Assume not found

    Block                                                                       # Check that it is possible to steal a key from the node on the left
     {my ($end, $start) = @_;                                                   # Code with labels supplied
      If $l == 0,  Then {Jmp $end};                                             # No elements left

      $t->found->copy(1);                                                       # Show first key and data have been found

      $t->key ->copy(dFromZ $K, 0);                                             # First key
      $t->data->copy(dFromZ $D, 0);                                             # First data
      $t->getTreeBits($K, r15);                                                 # First tree bit

      Mov r14, r15;
      Shr r14, 1;                                                               # Shift tree bits over by 1
      $t->setTreeBits($K, r14);                                                 # Save new tree bits
      And r15, 1;                                                               # Isolate first tree bit
      $t->subTree->copy(r15);                                                   # Save first tree bit

      my $m = (K(one => 1) << K(shift => $t->length)) - 2;                      # Compression mask to remove key/data
      $m->setReg(7);
      Vpcompressd zmmM($K, 7), zmm($K);                                         # Compress out first key
      Vpcompressd zmmM($D, 7), zmm($D);                                         # Compress out first data

      $t->decLengthInKeys($K);                                                  # Reduce length
     };
    PopR;
   }
  name       => "Nasm::X86::Tree::deleteFirstKeyAndData($K, $D)",
  structures => {tree => $tree};

  $s->call(structures => {tree => $tree});

  $tree                                                                         # Chain tree - actual data is in key, data,  subTree, found variables
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::merge
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 13);

  my ($PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN) = reverse 23..31;

  K(PK => Rd(map {16 * $_ }  1..16))->loadZmm($PK);
  K(PD => Rd(map {0x100+$_} 17..32))->loadZmm($PD);
  K(PN => Rd(map {0x100+$_} 33..48))->loadZmm($PN);

  K(LK => Rd(map {48+ $_  }  1..16))->loadZmm($LK);
  K(LD => Rd(map {0x200+$_} 17..32))->loadZmm($LD);
  K(LN => Rd(map {0x200+$_} 33..48))->loadZmm($LN);

  K(RK => Rd(map {64  + $_}  1..16))->loadZmm($RK);
  K(RD => Rd(map {0x300+$_} 17..32))->loadZmm($RD);
  K(RN => Rd(map {0x300+$_} 33..48))->loadZmm($RN);

  $t->lengthIntoKeys($PK, K length => 6);
  $t->lengthIntoKeys($LK, K length => 6);
  $t->lengthIntoKeys($RK, K length => 6);

  Mov r15, 0b11111111111111;
  $t->setTreeBits($PK, r15);
  Mov r15, 0;
  $t->setTreeBits($LK, r15);
  $t->setTreeBits($RK, r15);

  PrintOutStringNL "Start parent";
  PrintOutRegisterInHex reverse 29..31;
  PrintOutStringNL "Start Left";
  PrintOutRegisterInHex reverse 26..28;
  PrintOutStringNL "Start Right";
  PrintOutRegisterInHex reverse 23..25;

  $t->merge($PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN);

  PrintOutStringNL "Finish parent";
  PrintOutRegisterInHex reverse 29..31;
  PrintOutStringNL "Finish Left";
  PrintOutRegisterInHex reverse 26..28;

  ok Assemble eq => <<END;
Start parent
 zmm31: 0000 0100 3FFF 0006   0000 00E0 0000 00D0   0000 00C0 0000 00B0   0000 00A0 0000 0090   0000 0080 0000 0070   0000 0060 0000 0050   0000 0040 0000 0030   0000 0020 0000 0010
 zmm30: 0000 0120 0000 011F   0000 011E 0000 011D   0000 011C 0000 011B   0000 011A 0000 0119   0000 0118 0000 0117   0000 0116 0000 0115   0000 0114 0000 0113   0000 0112 0000 0111
 zmm29: 0000 0130 0000 012F   0000 012E 0000 012D   0000 012C 0000 012B   0000 012A 0000 0129   0000 0128 0000 0127   0000 0126 0000 0125   0000 0124 0000 0123   0000 0122 0000 0121
Start Left
 zmm28: 0000 0040 0000 0006   0000 003E 0000 003D   0000 003C 0000 003B   0000 003A 0000 0039   0000 0038 0000 0037   0000 0036 0000 0035   0000 0034 0000 0033   0000 0032 0000 0031
 zmm27: 0000 0220 0000 021F   0000 021E 0000 021D   0000 021C 0000 021B   0000 021A 0000 0219   0000 0218 0000 0217   0000 0216 0000 0215   0000 0214 0000 0213   0000 0212 0000 0211
 zmm26: 0000 0230 0000 022F   0000 022E 0000 022D   0000 022C 0000 022B   0000 022A 0000 0229   0000 0228 0000 0227   0000 0226 0000 0225   0000 0224 0000 0223   0000 0222 0000 0221
Start Right
 zmm25: 0000 0050 0000 0006   0000 004E 0000 004D   0000 004C 0000 004B   0000 004A 0000 0049   0000 0048 0000 0047   0000 0046 0000 0045   0000 0044 0000 0043   0000 0042 0000 0041
 zmm24: 0000 0320 0000 031F   0000 031E 0000 031D   0000 031C 0000 031B   0000 031A 0000 0319   0000 0318 0000 0317   0000 0316 0000 0315   0000 0314 0000 0313   0000 0312 0000 0311
 zmm23: 0000 0330 0000 032F   0000 032E 0000 032D   0000 032C 0000 032B   0000 032A 0000 0329   0000 0328 0000 0327   0000 0326 0000 0325   0000 0324 0000 0323   0000 0322 0000 0321
Finish parent
 zmm31: 0000 0100 1FFF 0005   0000 00E0 0000 00E0   0000 00D0 0000 00C0   0000 00B0 0000 00A0   0000 0090 0000 0080   0000 0070 0000 0060   0000 0050 0000 0030   0000 0020 0000 0010
 zmm30: 0000 0120 0000 011F   0000 011E 0000 011E   0000 011D 0000 011C   0000 011B 0000 011A   0000 0119 0000 0118   0000 0117 0000 0116   0000 0115 0000 0113   0000 0112 0000 0111
 zmm29: 0000 0130 0000 0130   0000 012F 0000 012E   0000 012D 0000 012C   0000 012B 0000 012A   0000 0129 0000 0128   0000 0127 0000 0126   0000 0124 0000 0123   0000 0122 0000 0121
Finish Left
 zmm28: 0000 0040 0040 000D   0000 003E 0000 0046   0000 0045 0000 0044   0000 0043 0000 0042   0000 0041 0000 0040   0000 0036 0000 0035   0000 0034 0000 0033   0000 0032 0000 0031
 zmm27: 0000 0220 0000 021F   0000 021E 0000 0316   0000 0315 0000 0314   0000 0313 0000 0312   0000 0311 0000 0114   0000 0216 0000 0215   0000 0214 0000 0213   0000 0212 0000 0211
 zmm26: 0000 0230 0000 022F   0000 0327 0000 0326   0000 0325 0000 0324   0000 0323 0000 0322   0000 0321 0000 0227   0000 0226 0000 0225   0000 0224 0000 0223   0000 0222 0000 0221
END
 }

#latest:
if (1) {
  my $N = 13;
  my $a = CreateArena;
  my $t = $a->CreateTree(length => $N);

  my ($K, $D) = (31, 30);

  K(K => Rd( 1..16))->loadZmm($K);
  K(D => Rd(17..32))->loadZmm($D);

  $t->lengthIntoKeys($K, K length => $t->length);

  Mov r15, 0b11001100110011;
  $t->setTreeBits($K, r15);

  PrintOutStringNL "Start";
  PrintOutRegisterInHex $K, $D;

  K(loop => $N)->for(sub
   {my ($index) = @_;                                                           # Parameters
    $t->deleteFirstKeyAndData($K, $D);

    PrintOutNL;
    $index->outNL;
    PrintOutNL;
    PrintOutRegisterInHex $K, $D;
    PrintOutNL;
    $t->key    ->out("k: ", "   "); $t->data->out("d: ", "   ");
    $t->subTree->out("s: ", "   "); $t->found->outNL;
   });

  ok Assemble eq => <<END;
Start
 zmm31: 0000 0010 3333 000D   0000 000E 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003   0000 0002 0000 0001
 zmm30: 0000 0020 0000 001F   0000 001E 0000 001D   0000 001C 0000 001B   0000 001A 0000 0019   0000 0018 0000 0017   0000 0016 0000 0015   0000 0014 0000 0013   0000 0012 0000 0011

index: 0000 0000 0000 0000

 zmm31: 0000 0010 1999 000C   0000 000E 0000 000D   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002
 zmm30: 0000 0020 0000 001F   0000 001E 0000 001D   0000 001D 0000 001C   0000 001B 0000 001A   0000 0019 0000 0018   0000 0017 0000 0016   0000 0015 0000 0014   0000 0013 0000 0012

k: 0000 0000 0000 0001   d: 0000 0000 0000 0011   s: 0000 0000 0000 0001   found: 0000 0000 0000 0001

index: 0000 0000 0000 0001

 zmm31: 0000 0010 0CCC 000B   0000 000E 0000 000D   0000 000D 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003
 zmm30: 0000 0020 0000 001F   0000 001E 0000 001D   0000 001D 0000 001D   0000 001C 0000 001B   0000 001A 0000 0019   0000 0018 0000 0017   0000 0016 0000 0015   0000 0014 0000 0013

k: 0000 0000 0000 0002   d: 0000 0000 0000 0012   s: 0000 0000 0000 0001   found: 0000 0000 0000 0001

index: 0000 0000 0000 0002

 zmm31: 0000 0010 0666 000A   0000 000E 0000 000D   0000 000D 0000 000D   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004
 zmm30: 0000 0020 0000 001F   0000 001E 0000 001D   0000 001D 0000 001D   0000 001D 0000 001C   0000 001B 0000 001A   0000 0019 0000 0018   0000 0017 0000 0016   0000 0015 0000 0014

k: 0000 0000 0000 0003   d: 0000 0000 0000 0013   s: 0000 0000 0000 0000   found: 0000 0000 0000 0001

index: 0000 0000 0000 0003

 zmm31: 0000 0010 0333 0009   0000 000E 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005
 zmm30: 0000 0020 0000 001F   0000 001E 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001C 0000 001B   0000 001A 0000 0019   0000 0018 0000 0017   0000 0016 0000 0015

k: 0000 0000 0000 0004   d: 0000 0000 0000 0014   s: 0000 0000 0000 0000   found: 0000 0000 0000 0001

index: 0000 0000 0000 0004

 zmm31: 0000 0010 0199 0008   0000 000E 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006
 zmm30: 0000 0020 0000 001F   0000 001E 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001C   0000 001B 0000 001A   0000 0019 0000 0018   0000 0017 0000 0016

k: 0000 0000 0000 0005   d: 0000 0000 0000 0015   s: 0000 0000 0000 0001   found: 0000 0000 0000 0001

index: 0000 0000 0000 0005

 zmm31: 0000 0010 00CC 0007   0000 000E 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007
 zmm30: 0000 0020 0000 001F   0000 001E 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001C 0000 001B   0000 001A 0000 0019   0000 0018 0000 0017

k: 0000 0000 0000 0006   d: 0000 0000 0000 0016   s: 0000 0000 0000 0001   found: 0000 0000 0000 0001

index: 0000 0000 0000 0006

 zmm31: 0000 0010 0066 0006   0000 000E 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008
 zmm30: 0000 0020 0000 001F   0000 001E 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001C   0000 001B 0000 001A   0000 0019 0000 0018

k: 0000 0000 0000 0007   d: 0000 0000 0000 0017   s: 0000 0000 0000 0000   found: 0000 0000 0000 0001

index: 0000 0000 0000 0007

 zmm31: 0000 0010 0033 0005   0000 000E 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009
 zmm30: 0000 0020 0000 001F   0000 001E 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001C 0000 001B   0000 001A 0000 0019

k: 0000 0000 0000 0008   d: 0000 0000 0000 0018   s: 0000 0000 0000 0000   found: 0000 0000 0000 0001

index: 0000 0000 0000 0008

 zmm31: 0000 0010 0019 0004   0000 000E 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000C   0000 000B 0000 000A
 zmm30: 0000 0020 0000 001F   0000 001E 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001C   0000 001B 0000 001A

k: 0000 0000 0000 0009   d: 0000 0000 0000 0019   s: 0000 0000 0000 0001   found: 0000 0000 0000 0001

index: 0000 0000 0000 0009

 zmm31: 0000 0010 000C 0003   0000 000E 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000C 0000 000B
 zmm30: 0000 0020 0000 001F   0000 001E 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001C 0000 001B

k: 0000 0000 0000 000A   d: 0000 0000 0000 001A   s: 0000 0000 0000 0001   found: 0000 0000 0000 0001

index: 0000 0000 0000 000A

 zmm31: 0000 0010 0006 0002   0000 000E 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000C
 zmm30: 0000 0020 0000 001F   0000 001E 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001C

k: 0000 0000 0000 000B   d: 0000 0000 0000 001B   s: 0000 0000 0000 0000   found: 0000 0000 0000 0001

index: 0000 0000 0000 000B

 zmm31: 0000 0010 0003 0001   0000 000E 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D
 zmm30: 0000 0020 0000 001F   0000 001E 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D

k: 0000 0000 0000 000C   d: 0000 0000 0000 001C   s: 0000 0000 0000 0000   found: 0000 0000 0000 0001

index: 0000 0000 0000 000C

 zmm31: 0000 0010 0001 0000   0000 000E 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D   0000 000D 0000 000D
 zmm30: 0000 0020 0000 001F   0000 001E 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D   0000 001D 0000 001D

k: 0000 0000 0000 000D   d: 0000 0000 0000 001D   s: 0000 0000 0000 0001   found: 0000 0000 0000 0001
END
 }

#latest:
if (1) {                                                                        #Nasm::X86::Variable::shiftLeft #Nasm::X86::Variable::shiftRight
  K(loop=>16)->for(sub
   {my ($index, $start, $next, $end) = @_;
   (K(one => 1)     << $index)->outRightInBinNL(K width => 16);
   (K(one => 1<<15) >> $index)->outRightInBinNL(K width => 16);
   });

  ok Assemble eq => <<END;
               1
1000000000000000
              10
 100000000000000
             100
  10000000000000
            1000
   1000000000000
           10000
    100000000000
          100000
     10000000000
         1000000
      1000000000
        10000000
       100000000
       100000000
        10000000
      1000000000
         1000000
     10000000000
          100000
    100000000000
           10000
   1000000000000
            1000
  10000000000000
             100
 100000000000000
              10
1000000000000000
               1
END
 }

sub Nasm::X86::Tree::firstNode($$$$)                                            # Return as a variable the last node block in the specified tree node held in a zmm
 {my ($tree, $K, $D, $N) = @_;                                                  # Tree definition, key zmm, data zmm, node zmm for a node block
  @_ == 4 or confess "Four parameters";

  dFromZ($N, 0)
 }

sub Nasm::X86::Tree::lastNode($$$$)                                             # Return as a variable the last node block in the specified tree node held in a zmm
 {my ($tree, $K, $D, $N) = @_;                                                  # Tree definition, key zmm, data zmm, node zmm for a node block
  @_ == 4 or confess "Four parameters";

  dFromZ($N, $tree->lengthFromKeys($K) * $tree->width)
 }

sub Nasm::X86::Tree::relativeNode($$$$)                                         # Return as a variable a node offset relative (specified as ac constant) to another offset in the same node in the specified zmm
 {my ($tree, $offset, $relative, $K, $N) = @_;                                  # Tree definition, offset, relative location, key zmm, node zmm
  @_ == 5 or confess "Five parameters";

  abs($relative) == 1 or confess "Relative must be +1 or -1";

  my $l = $tree->lengthFromKeys($K);                                            # Length of block
  PushR $K, 7, 15;                                                              # Reuse keys for comparison value
  $offset->setReg(r15);
  Vpbroadcastd zmm($K), r15d;                                                   # Load offset to test
  Vpcmpud k7, zmm($N, $K), $Vpcmp->eq;                                          # Check for nodes equal to offset
  Kmovq r15, k7;
  Tzcnt r15, r15;                                                               # Index of offset
  if ($relative < 0)
   {Cmp r15, 0;
    IfEq Then{PrintErrTraceBack "Cannot get offset before first offset"};
    Sub r15, 1;
   }
  if ($relative > 0)
   {Cmp r15, $tree->length;
    IfGt Then{PrintErrTraceBack "Cannot get offset beyond last offset"};
    Add r15, 1;
   }
  my $r = dFromZ $N, V(offset => r15) * $tree->width;                           # Select offset
  PopR;

  $r
 }

sub Nasm::X86::Tree::nextNode($$$)                                              # Return as a variable the next node block offset after the specified one in the specified zmm
 {my ($tree, $offset, $K, $N) = @_;                                             # Tree definition, offset, key zmm, node zmm
  @_ == 4 or confess "Four parameters";
  $tree->relativeNode($offset, +1, $K, $N);
 }

sub Nasm::X86::Tree::prevNode($$$)                                              # Return as a variable the previous node block offset after the specified one in the specified zmm
 {my ($tree, $offset, $K, $N) = @_;                                             # Tree definition, offset, key zmm, node zmm
  @_ == 4 or confess "Four parameters";
  $tree->relativeNode($offset, -1, $K, $N);
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::firstNode #TNasm::X86::Tree::lastNode
  my $L = 13;
  my $a = CreateArena;
  my $t = $a->CreateTree(length => $L);

  my ($K, $D, $N) = (31, 30, 29);

  K(K => Rd( 1..16))->loadZmm($K);
  K(K => Rd( 1..16))->loadZmm($N);

  $t->lengthIntoKeys($K, K length => $t->length);

  PrintOutRegisterInHex 31, 29;
  my $f = $t->firstNode($K, $D, $N);
  my $l = $t-> lastNode($K, $D, $N);
  $f->outNL;
  $l->outNL;

  ok Assemble eq => <<END;
 zmm31: 0000 0010 0000 000D   0000 000E 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003   0000 0002 0000 0001
 zmm29: 0000 0010 0000 000F   0000 000E 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003   0000 0002 0000 0001
d at offset 0 in zmm29: 0000 0000 0000 0001
d at offset (b at offset 56 in zmm31 times 4) in zmm29: 0000 0000 0000 000E
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::firstNode #TNasm::X86::Tree::lastNode
  my $L = 13;
  my $a = CreateArena;
  my $t = $a->CreateTree(length => $L);

  my ($K, $D, $N) = (31, 30, 29);

  K(K => Rd( 1..16))->loadZmm($K);
  K(K => Rd( 1..16))->loadZmm($N);

  $t->lengthIntoKeys($K, K length => $t->length);

  PrintOutRegisterInHex 31, 29;
  my $f = $t->firstNode($K, $D, $N);
  my $l = $t-> lastNode($K, $D, $N);
  $f->outNL;
  $l->outNL;

  ok Assemble eq => <<END;
 zmm31: 0000 0010 0000 000D   0000 000E 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003   0000 0002 0000 0001
 zmm29: 0000 0010 0000 000F   0000 000E 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003   0000 0002 0000 0001
d at offset 0 in zmm29: 0000 0000 0000 0001
d at offset (b at offset 56 in zmm31 times 4) in zmm29: 0000 0000 0000 000E
END
 }

sub Nasm::X86::Tree::indexNode($$$$)                                            # Return, as a variable, the point mask obtained by testing the nodes in a block for specified offset. We have to supply the keys as well so that we can find the number of nodes. We need the number of nodes so that we only search the valid area not all possible node positions in the zmm.
 {my ($tree, $offset, $K, $N) = @_;                                             # Tree definition, key as a variable, zmm containing keys, comparison from B<Vpcmp>
  @_ == 4 or confess "Four parameters";

  my $A = $K == 17 ? 18 : 17;                                                   # The broadcast facility 1 to 16 does not seem to work reliably so we load an alternate zmm
  PushR rcx, r14, r15, k7, $A;                                                  # Registers

  $offset->setReg(r14);                                                         # The offset we are looking for
  Vpbroadcastd zmm($A), r14d;                                                   # Load offset to test
  Vpcmpud k7, zmm($N, $A), $Vpcmp->eq;                                          # Check for nodes equal to offset
  my $l = $tree->lengthFromKeys($K);                                            # Current length of the keys block
  $l->setReg(rcx);                                                              # Create a mask of ones that matches the width of a key node in the current tree.
  Mov   r15, 2;                                                                 # A one in position two because the number of nodes is always one more than the number of keys
  Shl   r15, cl;                                                                # Position the one at end of nodes block
  Dec   r15;                                                                    # Reduce to fill block with ones
  Kmovq r14, k7;                                                                # Matching nodes
  And   r15, r14;                                                               # Matching nodes in mask area
  my $r = V index => r15;                                                       # Save result as a variable
  PopR;

  $r                                                                            # Point of key if non zero, else no match
 }

sub Nasm::X86::Tree::expand($$)                                                 # Expand the node at the specified offset in the specified tree if it needs to be expanded and is not the root node (which cannot be expanded because it has no siblings to take substance from whereas as all other nodes do).  Set tree.found to the offset of the left sibling if the node at the specified offset was merged into it and freed else set tree.found to zero.
 {my ($tree, $offset) = @_;                                                     # Tree descriptor, offset of node block to expand
  @_ == 2 or confess "Two parameters";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $success = Label;                                                        # Short circuit if ladders by jumping directly to the end after a successful push

    PushR 8..15, 22..31;

    my $t = $$s{tree};                                                          # Tree to search
    my $L = $$p{offset};                                                        # Offset of node to expand is currently regarded as left
    my $F = 31;
    my $PK = 30; my $PD = 29; my $PN = 28;
    my $LK = 27; my $LD = 26; my $LN = 25;
    my $RK = 24; my $RD = 23; my $RN = 22;

    $t->found->copy(0);                                                         # Assume the left node will not be freed by the expansion
    $t->firstFromMemory($F);                                                    # Load first block
    my $root = $t->rootFromFirst($F);                                           # Root node block offset
    If $root == 0 || $root == $L, Then {Jmp $success};                          # Empty tree or on root so nothing to do

    Block                                                                       # If not on the root and node has the minimum number of keys then either steal left or steal right or merge left or merge right
     {my ($end, $start) = @_;                                                   # Code with labels supplied
      $t->getBlock($L, $LK, $LD, $LN);                                          # Load node from memory
      my $ll = $t->lengthFromKeys($LK);                                         # Length of node
      If $ll > $t->lengthMin, Then {Jmp $end};                                  # Has more than the bare minimum so does not need to be expanded

      my $P = $t->upFromData($LD);                                              # Parent offset
      $t->getBlock($P, $PK, $PD, $PN);                                          # Get the parent keys/data/nodes
      my $fn = $t->firstNode($PK, $PD, $PN);                                    # Parent first node
      my $ln = $t-> lastNode($PK, $PD, $PN);                                    # Parent last node

      my $R = V right => 0;                                                     # The node on the right
      my $plp = $t->indexNode($L, $PK, $PN);                                    # Position of the left node in the parent

      If $plp == 0,                                                             # Zero implies that the left child is not registered in its parent
      Then
       {PrintErrTraceBack "Cannot find left node in parent";
       };

      If $L == $ln,                                                             # If necessary step one to the let and record the fact that we did is that we can restart the search at the top
      Then                                                                      # Last child and needs merging
       {Vmovdqu64 zmm $RK, $LK;                                                 # Copy the current left node into the right node
        Vmovdqu64 zmm $RD, $LD;
        Vmovdqu64 zmm $RN, $LN;
        $R->copy($L);                                                           # Left becomes right node because it is last
        my $l = $plp >> K(one => 1);                                            # The position of the previous node known to exist because we are currently on the last node
        $L->copy($l->dFromPointInZ($PN));                                       # Load previous sibling as new left keeping old left in right so that left and right now form a pair of siblings
        $t->getBlock($L, $LK, $LD, $LN);                                        # Load the new left
        $t->found->copy($L);                                                    # Show that we created a new left
       },
      Else
       {my $r = $plp << K(one => 1);                                            # The position of the node to tthe right known to exist because we are not currently on the last node
        $R->copy($r->dFromPointInZ($PN));                                       # Load next sibling as right
        $t->getBlock($R, $RK, $RD, $RN);                                        # Load the right sibling
       };

      my $lr = $t->lengthFromKeys($RK);                                         # Length of right
      If $lr == $t->lengthMin,
      Then                                                                      # Merge left and right into left as they are both at minimum size
       {$t->merge($PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN);                 # Tree definition, parent keys zmm, data zmm, nodes zmm, left keys zmm, data zmm, nodes zmm.
        # $t->freeBlock($R, $RK, $RD, $RN);                                       # The right is no longer required because it has been merged away

        my $lp = $t->lengthFromKeys($PK);                                       # New length of parent
        If $lp == 0,
        Then                                                                    # Root now empty
         {$t->rootIntoFirst($F, $L);                                            # Parent is now empty so the left block must be the new root
          $t->firstIntoMemory($F);                                              # Save first block with updated root
          #$t->freeBlock($P, $PK, $PD, $PN);                                     # The parent is no longer required because the left ir the new root
         },
        Else                                                                    # Root not empty
         {$t->putBlock($P, $PK, $PD, $PN);                                      # Write parent back into memory
         };
       },
      Else                                                                      # Steal from right as it is too big to merge and so must have some excess that we can steal
       {$t->stealFromRight($PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN);        # Steal
        $t->putBlock($P, $PK, $PD, $PN);                                        # Save modified parent
        $t->putBlock($R, $RK, $RD, $RN);                                        # Save modified right
       };
      $t->putBlock($L, $LK, $LD, $LN);                                          # Save non minimum left

      my $l = $t->leafFromNodes($LN);                                           # Whether the left block is a leaf
      If $l > 0,                                                                # If the zero Flag is zero then this is not a leaf
      Then
       {PushR $RK, $RD, $RN;                                                    # Save these zmm even though we are not going to need them any more
        ($t->lengthFromKeys($LK) + 1)->for(sub                                  # Reparent the children of the left hand side.  This is not efficient as we load all the children (if there are any) but it is effective.
         {my ($index, $start, $next, $end) = @_;
          my $R = dFromZ $LN, $index * $t->width;                               # Offset of node
          $t->getBlock  ($R, $RK, $RD, $RN);                                    # Get child of right node reusing the left hand set of registers as we no longer need them having written them to memory
          $t->upIntoData($L,      $RD);                                         # Parent for child of right hand side
          $t->putBlock  ($R, $RK, $RD, $RN);                                    # Save block into memory now that its parent pointer has been updated
         });
         PopR;
       };
     };  # Block

    SetLabel $success;                                                          # Find completed successfully
    PopR;
   } parameters=>[qw(offset)],
     structures=>{tree=>$tree},
     name => 'Nasm::X86::Tree::expand';

  $s->call(structures=>{tree => $tree}, parameters=>{offset => $offset});
 } # expand

sub Nasm::X86::Tree::replace($$$$)                                              # Replace the key/data/subTree at the specified point in the specified zmm with the values found in the tree key/data/sub tree fields.
 {my ($tree, $point, $K, $D) = @_;                                              # Tree descriptor, point at which to extract, keys zmm, data zmm
  @_ == 4 or confess "Four parameters";

  $point->dIntoPointInZ($K, $tree->key);                                        # Key
  $point->dIntoPointInZ($D, $tree->data);                                       # Data at point

  $tree->setOrClearTreeBitToMatchContent($K, $point, $tree->subTree);           # Replace tree bit
 } # replace

sub Nasm::X86::Tree::extract($$$$$)                                             # Extract the key/data/node and tree bit at the specified point from the block held in the specified zmm registers.
 {my ($tree, $point, $K, $D, $N) = @_;                                          # Tree descriptor, point at which to extract, keys zmm, data zmm, node zmm
  @_ == 5 or confess "Five parameters";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $success = Label;                                                        # Short circuit if ladders by jumping directly to the end after a successful push

    my $t = $$s{tree};                                                          # Tree to search
    my $l = $t->leafFromNodes($N);                                              # Check for a leaf
    If $l == 0,                                                                 # If the zero Flag is zero then this is not a leaf
    Then                                                                        # We can only perform this operation on a leaf
     {PrintErrTraceBack "Cannot extract from a non leaf node";
     };

#    my $l = $t->lengthFromKeys($K);                                             # Check for a minimal block
#    If $l <= $t->lengthMin,
#    Then                                                                        # Minimal block - extraction not possible
#     {PrintErrTraceBack "Cannot extract from a minimum block";
#     };
#
    PushR 7, 15;

    my $q = $$p{point};                                                         # Point at which to extract
    $t->data->copy($q->dFromPointInZ($D));                                      # Data at point
    $t->subTree->copy($t->getTreeBit($K, $q));                                  # Sub tree or not a sub tree

    $q->setReg(r15);                                                            # Create a compression mask to squeeze out the key/data
    Not r15;                                                                    # Invert point
    Mov rsi, r15;                                                               # Inverted point
    And rsi, $t->keyDataMask;                                                   # Mask for keys area
    Kmovq k7, rsi;
    Vpcompressd zmmM($K, 7), zmm($K);                                           # Compress out the key
    Vpcompressd zmmM($D, 7), zmm($D);                                           # Compress out the data

    PushR 6, 31;
    $t->getTreeBits($K, rsi);                                                   # Tree bits
    Kmovq k6, rsi;
    Vpmovm2d zmm(31), k6;                                                       # Broadcast the tree bits into a zmm
    Vpcompressd zmmM(31, 7), zmm(31);                                           # Compress out the tree bit in question
    Vpmovd2m k6, zmm(31);                                                       # Reform the tree bits minus the squeezed out bit
    Kmovq rsi, k6;                                                              # New tree bits
    $t->setTreeBits($K, rsi);                                                   # Reload tree bits
    PopR;

    Mov rsi, r15;                                                               # Inverted point
    And rsi, $t->nodeMask;                                                      # Mask for node area
    Kmovq k7, rsi;
    Vpcompressd zmmM($N, 7), zmm($N);                                           # Compress out the node

    $t->decLengthInKeys($K);                                                    # Reduce length by  one

    SetLabel $success;                                                          # Find completed successfully
    PopR;
   } parameters=>[qw(point)],
     structures=>{tree=>$tree},
     name => "Nasm::X86::Tree::find($K, $D, $N, $$tree{length})";

  $s->call(structures=>{tree => $tree}, parameters=>{point => $point});
 } # extract

sub Nasm::X86::Tree::extractFirst($$$$)                                         # Extract the first key/data and tree bit at the specified point from the block held in the specified zmm registers and place the extracted data/bit in tree data/subTree.
 {my ($tree, $K, $D, $N) = @_;                                                  # Tree descriptor, keys zmm, data zmm, node zmm
  @_ == 4 or confess "Four parameters";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $success = Label;                                                        # Short circuit if ladders by jumping directly to the end after a successful push

    my $t = $$s{tree};                                                          # Tree to search
    $t->leafFromNodes($N);                                                      # Check for a leaf
    IfNe                                                                        # If the zero Flag is zero then this is not a leaf
    Then                                                                        # We can only perform this operation on a leaf
     {PrintErrTraceBack "Cannot extract first from a non leaf node";
     };

#    my $l = $t->lengthFromKeys($K);                                             # Check for a minimal block
#    If $l <= $t->lengthMin,
#    Then                                                                        # Minimal block - extraction not possible
#     {PrintErrTraceBack "Cannot extract first from a minimum block";
#     };

    $t->data->copy(dFromZ($D, 0));                                              # Save corresponding data into tree data field

    PushR 7;

    Mov rsi, $t->keyDataMask;                                                   # Mask for keys area
    Sub rsi, 1;                                                                 # Mask for keys area with a zero in the first position
    Kmovq k7, rsi;
    Vpcompressd zmmM($K, 7), zmm($K);                                           # Compress out the key
    Vpcompressd zmmM($D, 7), zmm($D);                                           # Compress out the data

    $t->getTreeBits($K, rdi);                                                   # Tree bits
    Mov rsi, rdi;
    And rsi, 1;                                                                 # First tree bit
    $t->subTree->getReg(rsi);                                                   # Save tree bit
    Shr rdi, 1;                                                                 # Remove first tree bit
    $t->setTreeBits($K, rdi);                                                   # Reload tree bits

    $t->decLengthInKeys($K);                                                    # Reduce length by  one

    SetLabel $success;                                                          # Find completed successfully

    PopR;
   } parameters=>[qw(point)],
     structures=>{tree=>$tree},
     name => "Nasm::X86::Tree::find($K, $D, $N, $$tree{length})";

  $s->call(structures=>{tree => $tree});
 } # extractFirst

sub Nasm::X86::Tree::mergeOrSteal($$$)                                          # Merge the block at the specified offset with its right sibling or steal from it. If there is no  right sibling then do the same thing but with the left sibling.  The supplied block must not be the root. The key we ae looking for must be in the tree key field.
 {my ($tree, $offset) = @_;                                                     # Tree descriptor, offset of non root block that might need to merge or steal
  @_ == 2 or confess "Two parameters";

  my $s = Subroutine2
   {my ($parameters, $structures, $sub) = @_;                                   # Parameters, structures, subroutine definition

    my $t  = $$structures{tree};                                                # Tree to search
    my $F  = 31;
    my $PK = 30; my $PD = 29; my $PN = 28;
    my $LK = 27; my $LD = 26; my $LN = 25;
    my $RK = 24; my $RD = 23; my $RN = 22;

    PushR 22..31;

    my $l = $$parameters{offset};                                               # Offset of node that might need merging
    $t->getBlock($l, $LK, $LD, $LN);                                            # Get the keys/data/nodes
    my $p = $t->upFromData($LD);                                                # Parent offset
    If $p == 0,
    Then
     {PrintErrTraceBack "Cannot mergeOrSteal the root";
     };
    $t->getBlock($p, $PK, $PD, $PN);                                            # Get the parent

    If $t->lengthFromKeys($LK) == $t->lengthMin,                                # Has the the bare minimum so must merge or steal
    Then
     {my $r = V r => 0;
      If $l == $t->lastNode($PK, $PD, $PN),
      Then                                                                      # Last child and needs merging
       {Vmovdqu64 zmm $RK, $LK;                                                 # Copy the current left node into the right node
        Vmovdqu64 zmm $RD, $LD;
        Vmovdqu64 zmm $RN, $LN;
        $r->copy($l);                                                           # Current left offset becomes offset of right sibling
        $l->copy($t->prevNode($r, $PK, $PN));                                   # The position of the previous node known to exist because we are currently on the last child
        $t->getBlock($l, $LK, $LD, $LN);                                        # Get the parent keys/data/nodes
       },
      Else
       {$r->copy($t->nextNode($l, $PK, $PN));                                   # Right hand will be next sibling
        $t->getBlock($r, $RK, $RD, $RN);                                        # Get next sibling
       };

      If $t->lengthFromKeys($RK) == $t->lengthMin,
      Then                                                                      # Merge left and right siblings because we now know they are both minimal
       {$t->merge($PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN);                 # Tree definition, parent keys zmm, data zmm, nodes zmm, left keys zmm, data zmm, nodes zmm.
        #$t->freeBlock($r, $RK, $RD, $RN);                                      # Free right
        my $L = $t->lengthFromKeys($PK);
        If $t->lengthFromKeys($PK) == 0,
        Then                                                                    # We just merged in the root so make the left sibling the root
         {$t->firstFromMemory($F);
          $t->rootIntoFirst($F, $l);
          $t->firstIntoMemory($F);
         };
       },
      Else                                                                      # Steal from second child
       {$t->stealFromRight($PK, $PD, $PN, $LK, $LD, $LN, $RK, $RD, $RN);        # Steal
        $t->putBlock($r, $RK, $RD, $RN);                                        # Save modified right
       };
      $t->putBlock($p, $PK, $PD, $PN);                                          # Save modified parent
      $t->putBlock($l, $LK, $LD, $LN);                                          # Save non minimum left
      $$parameters{changed}->copy(1);                                           # Show that we changed the tree layout
     };

    PopR;
   } parameters=>[qw(offset changed)],
     structures=>{tree=>$tree},
     name => "Nasm::X86::Tree::mergeOrSteal($$tree{length})";

  $s->call(structures=>
   {tree       =>  $tree},
    parameters => {offset=> $offset, changed => my $changed = V changed => 0});

  $changed                                                                      # Whether we did a merge or steal
 } # mergeOrSteal

#latest:
if (1) {                                                                        #TNasm::X86::Tree::expand
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);

  my ($PK, $PD, $PN) = (31, 30, 29);
  my ($LK, $LD, $LN) = (28, 27, 26);
  my ($RK, $RD, $RN) = (25, 24, 23);
  my ($lK, $lD, $lN) = (22, 21, 20);
  my ($rK, $rD, $rN) = (19, 18, 17);
  my $F = 16;

  my $P  = $t->allocBlock($PK, $PD, $PN);
  my $L  = $t->allocBlock($LK, $LD, $LN);
  my $R  = $t->allocBlock($RK, $RD, $RN);
  my $l  = $t->allocBlock($lK, $lD, $lN);
  my $r  = $t->allocBlock($rK, $rD, $rN);

  $t->lengthIntoKeys($PK, K length => 1);
  $t->lengthIntoKeys($LK, K length => 1);
  $t->lengthIntoKeys($RK, K length => 1);

  K(key=>1)->dIntoZ($LK, 0);  K(key=>1)->dIntoZ($LD, 0);
  K(key=>2)->dIntoZ($PK, 0);  K(key=>2)->dIntoZ($PD, 0);
  K(key=>3)->dIntoZ($RK, 0);  K(key=>3)->dIntoZ($RD, 0);

  $L->dIntoZ($PN, 0);
  $R->dIntoZ($PN, 4);
  $l->dIntoZ($LN, 0); $l->dIntoZ($LN, 4);
  $r->dIntoZ($RN, 0); $r->dIntoZ($RN, 4);

  $t->upIntoData($P, $LD);
  $t->upIntoData($P, $RD);
  $t->upIntoData($L, $lD);
  $t->upIntoData($R, $rD);

  $t->firstFromMemory($F);
  $t->rootIntoFirst($F, $P);
  $t->sizeIntoFirst(K(size => 3), $F);

  $t->firstIntoMemory($F);
  $t->putBlock($P, $PK, $PD, $PN);
  $t->putBlock($L, $LK, $LD, $LN);
  $t->putBlock($R, $RK, $RD, $RN);
  $t->putBlock($l, $lK, $lD, $lN);
  $t->putBlock($r, $rK, $rD, $rN);

  PrintOutStringNL "Start";
  PrintOutRegisterInHex reverse $F..$PK;

  $t->expand($L);

  $t->firstFromMemory($F);
  $t->getBlock($P, $PK, $PD, $PN);
  $t->getBlock($L, $LK, $LD, $LN);
  $t->getBlock($R, $RK, $RD, $RN);

  PrintOutStringNL "Finish";
  PrintOutRegisterInHex reverse $LN..$LK;

  PrintOutStringNL "Children";
  PrintOutRegisterInHex reverse $LN..$LK;

  ok Assemble eq => <<END;
Start
 zmm31: 0000 00C0 0000 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0002
 zmm30: 0000 0100 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0002
 zmm29: 0000 0040 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0200 0000 0140
 zmm28: 0000 0180 0000 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0001
 zmm27: 0000 01C0 0000 0080   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0001
 zmm26: 0000 0040 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 02C0 0000 02C0
 zmm25: 0000 0240 0000 0001   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0003
 zmm24: 0000 0280 0000 0080   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0003
 zmm23: 0000 0040 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0380 0000 0380
 zmm22: 0000 0300 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
 zmm21: 0000 0340 0000 0140   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
 zmm20: 0000 0040 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
 zmm19: 0000 03C0 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
 zmm18: 0000 0400 0000 0200   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
 zmm17: 0000 0040 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
 zmm16: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0003   0000 0000 0000 0080
Finish
 zmm28: 0000 0180 0000 0003   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0003   0000 0002 0000 0001
 zmm27: 0000 01C0 0000 0080   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0003   0000 0002 0000 0001
 zmm26: 0000 0040 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0380 0000 0380   0000 02C0 0000 02C0
Children
 zmm28: 0000 0180 0000 0003   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0003   0000 0002 0000 0001
 zmm27: 0000 01C0 0000 0080   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0003   0000 0002 0000 0001
 zmm26: 0000 0040 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0380 0000 0380   0000 02C0 0000 02C0
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::replace
  my ($K, $D) = (31, 30);

  K(K => Rd(reverse 1..16))->loadZmm($K);
  K(K => Rd(reverse 1..16))->loadZmm($D);
  PrintOutStringNL "Start";
  PrintOutRegisterInHex $K, $D;

  my $a = CreateArena;
  my $t = $a->CreateTree(length => 13);

  K(loop => 14)->for(sub
   {my ($index, $start, $next, $end) = @_;

    $t->key    ->copy($index);
    $t->data   ->copy($index * 2);
    $t->subTree->copy($index % 2);

    $t->replace(K(one=>1)<<$index, $K, $D);

    $index->outNL;
    PrintOutRegisterInHex $K, $D;
   });

  ok Assemble eq => <<END;
Start
 zmm31: 0000 0001 0000 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 000A   0000 000B 0000 000C   0000 000D 0000 000E   0000 000F 0000 0010
 zmm30: 0000 0001 0000 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 000A   0000 000B 0000 000C   0000 000D 0000 000E   0000 000F 0000 0010
index: 0000 0000 0000 0000
 zmm31: 0000 0001 0000 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 000A   0000 000B 0000 000C   0000 000D 0000 000E   0000 000F 0000 0000
 zmm30: 0000 0001 0000 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 000A   0000 000B 0000 000C   0000 000D 0000 000E   0000 000F 0000 0000
index: 0000 0000 0000 0001
 zmm31: 0000 0001 0002 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 000A   0000 000B 0000 000C   0000 000D 0000 000E   0000 0001 0000 0000
 zmm30: 0000 0001 0000 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 000A   0000 000B 0000 000C   0000 000D 0000 000E   0000 0002 0000 0000
index: 0000 0000 0000 0002
 zmm31: 0000 0001 0002 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 000A   0000 000B 0000 000C   0000 000D 0000 0002   0000 0001 0000 0000
 zmm30: 0000 0001 0000 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 000A   0000 000B 0000 000C   0000 000D 0000 0004   0000 0002 0000 0000
index: 0000 0000 0000 0003
 zmm31: 0000 0001 000A 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 000A   0000 000B 0000 000C   0000 0003 0000 0002   0000 0001 0000 0000
 zmm30: 0000 0001 0000 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 000A   0000 000B 0000 000C   0000 0006 0000 0004   0000 0002 0000 0000
index: 0000 0000 0000 0004
 zmm31: 0000 0001 000A 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 000A   0000 000B 0000 0004   0000 0003 0000 0002   0000 0001 0000 0000
 zmm30: 0000 0001 0000 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 000A   0000 000B 0000 0008   0000 0006 0000 0004   0000 0002 0000 0000
index: 0000 0000 0000 0005
 zmm31: 0000 0001 002A 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 000A   0000 0005 0000 0004   0000 0003 0000 0002   0000 0001 0000 0000
 zmm30: 0000 0001 0000 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 000A   0000 000A 0000 0008   0000 0006 0000 0004   0000 0002 0000 0000
index: 0000 0000 0000 0006
 zmm31: 0000 0001 002A 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002   0000 0001 0000 0000
 zmm30: 0000 0001 0000 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0009 0000 000C   0000 000A 0000 0008   0000 0006 0000 0004   0000 0002 0000 0000
index: 0000 0000 0000 0007
 zmm31: 0000 0001 00AA 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002   0000 0001 0000 0000
 zmm30: 0000 0001 0000 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 000E 0000 000C   0000 000A 0000 0008   0000 0006 0000 0004   0000 0002 0000 0000
index: 0000 0000 0000 0008
 zmm31: 0000 0001 00AA 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002   0000 0001 0000 0000
 zmm30: 0000 0001 0000 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0007 0000 0010   0000 000E 0000 000C   0000 000A 0000 0008   0000 0006 0000 0004   0000 0002 0000 0000
index: 0000 0000 0000 0009
 zmm31: 0000 0001 02AA 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002   0000 0001 0000 0000
 zmm30: 0000 0001 0000 0002   0000 0003 0000 0004   0000 0005 0000 0006   0000 0012 0000 0010   0000 000E 0000 000C   0000 000A 0000 0008   0000 0006 0000 0004   0000 0002 0000 0000
index: 0000 0000 0000 000A
 zmm31: 0000 0001 02AA 0002   0000 0003 0000 0004   0000 0005 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002   0000 0001 0000 0000
 zmm30: 0000 0001 0000 0002   0000 0003 0000 0004   0000 0005 0000 0014   0000 0012 0000 0010   0000 000E 0000 000C   0000 000A 0000 0008   0000 0006 0000 0004   0000 0002 0000 0000
index: 0000 0000 0000 000B
 zmm31: 0000 0001 0AAA 0002   0000 0003 0000 0004   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002   0000 0001 0000 0000
 zmm30: 0000 0001 0000 0002   0000 0003 0000 0004   0000 0016 0000 0014   0000 0012 0000 0010   0000 000E 0000 000C   0000 000A 0000 0008   0000 0006 0000 0004   0000 0002 0000 0000
index: 0000 0000 0000 000C
 zmm31: 0000 0001 0AAA 0002   0000 0003 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002   0000 0001 0000 0000
 zmm30: 0000 0001 0000 0002   0000 0003 0000 0018   0000 0016 0000 0014   0000 0012 0000 0010   0000 000E 0000 000C   0000 000A 0000 0008   0000 0006 0000 0004   0000 0002 0000 0000
index: 0000 0000 0000 000D
 zmm31: 0000 0001 2AAA 0002   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002   0000 0001 0000 0000
 zmm30: 0000 0001 0000 0002   0000 001A 0000 0018   0000 0016 0000 0014   0000 0012 0000 0010   0000 000E 0000 000C   0000 000A 0000 0008   0000 0006 0000 0004   0000 0002 0000 0000
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::extractFirst
  my ($K, $D, $N) = (31, 30, 29);

  K(K => Rd( 1..16))       ->loadZmm($K);
  K(K => Rd( 1..16))       ->loadZmm($D);
  K(K => Rd(map {0} 1..16))->loadZmm($N);

  my $a = CreateArena;
  my $t = $a->CreateTree(length => 13);

  my $p = K(one => 1) << K three => 3;
  Mov r15, 0xAAAA;
  $t->setTreeBits($K, r15);

  PrintOutStringNL "Start";
  PrintOutRegisterInHex 31, 30, 29;

  K(n=>4)->for(sub
   {my ($index, $start, $next, $end) = @_;

    $t->extractFirst($K, $D, $N);

    PrintOutStringNL "-------------";
    $index->outNL;
    PrintOutRegisterInHex 31, 30, 29;

    $t->data->outNL;
    $t->subTree->outNL;
    $t->lengthFromKeys($K)->outNL;
   });

  ok Assemble eq => <<END;
Start
 zmm31: 0000 0010 2AAA 000F   0000 000E 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003   0000 0002 0000 0001
 zmm30: 0000 0010 0000 000F   0000 000E 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003   0000 0002 0000 0001
 zmm29: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
-------------
index: 0000 0000 0000 0000
 zmm31: 0000 0010 1555 000E   0000 000E 0000 000E   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002
 zmm30: 0000 0010 0000 000F   0000 000E 0000 000E   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004   0000 0003 0000 0002
 zmm29: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
data: 0000 0000 0000 0001
subTree: 0000 0000 0000 0000
b at offset 56 in zmm31: 0000 0000 0000 000E
-------------
index: 0000 0000 0000 0001
 zmm31: 0000 0010 0AAA 000D   0000 000E 0000 000E   0000 000E 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003
 zmm30: 0000 0010 0000 000F   0000 000E 0000 000E   0000 000E 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003
 zmm29: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
data: 0000 0000 0000 0002
subTree: 0000 0000 0000 0001
b at offset 56 in zmm31: 0000 0000 0000 000D
-------------
index: 0000 0000 0000 0002
 zmm31: 0000 0010 0555 000C   0000 000E 0000 000E   0000 000E 0000 000E   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004
 zmm30: 0000 0010 0000 000F   0000 000E 0000 000E   0000 000E 0000 000E   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0004
 zmm29: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
data: 0000 0000 0000 0003
subTree: 0000 0000 0000 0000
b at offset 56 in zmm31: 0000 0000 0000 000C
-------------
index: 0000 0000 0000 0003
 zmm31: 0000 0010 02AA 000B   0000 000E 0000 000E   0000 000E 0000 000E   0000 000E 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005
 zmm30: 0000 0010 0000 000F   0000 000E 0000 000E   0000 000E 0000 000E   0000 000E 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005
 zmm29: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
data: 0000 0000 0000 0004
subTree: 0000 0000 0000 0001
b at offset 56 in zmm31: 0000 0000 0000 000B
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::extract
  my ($K, $D, $N) = (31, 30, 29);

  K(K => Rd( 1..16))->loadZmm($K);
  K(K => Rd( 1..16))->loadZmm($D);
  K(K => Rd(map {0} 1..16))->loadZmm($N);

  my $a = CreateArena;
  my $t = $a->CreateTree(length => 13);

  my $p = K(one => 1) << K three => 3;
  Mov r15, 0xAAAA;
  $t->setTreeBits($K, r15);

  PrintOutStringNL "Start";
  PrintOutRegisterInHex 31, 30, 29;

  $t->extract($p, $K, $D, $N);

  PrintOutStringNL "Finish";
  PrintOutRegisterInHex 31, 30, 29;

  ok Assemble eq => <<END;
Start
 zmm31: 0000 0010 2AAA 000F   0000 000E 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003   0000 0002 0000 0001
 zmm30: 0000 0010 0000 000F   0000 000E 0000 000D   0000 000C 0000 000B   0000 000A 0000 0009   0000 0008 0000 0007   0000 0006 0000 0005   0000 0004 0000 0003   0000 0002 0000 0001
 zmm29: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
Finish
 zmm31: 0000 0010 2AAA 000E   0000 000E 0000 000E   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0003   0000 0002 0000 0001
 zmm30: 0000 0010 0000 000F   0000 000E 0000 000E   0000 000D 0000 000C   0000 000B 0000 000A   0000 0009 0000 0008   0000 0007 0000 0006   0000 0005 0000 0003   0000 0002 0000 0001
 zmm29: 0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000   0000 0000 0000 0000
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::mergeOrSteal
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);
  $t->put(   K(k=>1), K(d=>11));
  $t->put(   K(k=>2), K(d=>22));
  $t->put(   K(k=>3), K(d=>33));
  $t->put(   K(k=>4), K(d=>44));
  $t->put(   K(k=>5), K(d=>55));
  $t->put(   K(k=>6), K(d=>56));

  $t->getBlock(K(o=>0x2C0), 31, 30, 29);
  $t->lengthIntoKeys(31, K 1 => 1);
  $t->putBlock(K(o=>0x2C0), 31, 30, 29);
  $t->dump("6");

  $t->key->copy(K k => 4);
  $t->mergeOrSteal(K o => 0x140);
  $t->dump("5");

  ok Assemble eq => <<END;
6
At:  200                    length:    2,  data:  240,  nodes:  280,  first:   40, root, parent
  Index:    0    1
  Keys :    2    4
  Data :   22   44
  Nodes:   80  140  2C0
    At:   80                length:    1,  data:   C0,  nodes:  100,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    1
      Data :   11
    end
    At:  140                length:    1,  data:  180,  nodes:  1C0,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    3
      Data :   33
    end
    At:  2C0                length:    1,  data:  300,  nodes:  340,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    5
      Data :   55
    end
end
5
At:  200                    length:    1,  data:  240,  nodes:  280,  first:   40, root, parent
  Index:    0
  Keys :    2
  Data :   22
  Nodes:   80  140
    At:   80                length:    1,  data:   C0,  nodes:  100,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    1
      Data :   11
    end
    At:  140                length:    3,  data:  180,  nodes:  1C0,  first:   40,  up:  200, leaf
      Index:    0    1    2
      Keys :    3    4    5
      Data :   33   44   55
    end
end
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::nextNode #TNasm::X86::Tree::prevNode
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 13);

  K(loop => 66)->for(sub
   {my ($index, $start, $next, $end) = @_;
    $t->put($index, 2 * $index);
   });
  $t->getBlock(K(offset=>0x200), 31, 30, 29);
  $t->nextNode(K(offset=>0x440), 31, 29)->outRightInHexNL(K width => 3);
  $t->prevNode(K(offset=>0x440), 31, 29)->outRightInHexNL(K width => 3);

  ok Assemble eq => <<END;
500
380
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::mergeOrSteal
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);
  $t->put(   K(k=>1), K(d=>11));
  $t->put(   K(k=>2), K(d=>22));
  $t->put(   K(k=>3), K(d=>33));
  $t->put(   K(k=>4), K(d=>44));
  $t->put(   K(k=>5), K(d=>55));
  $t->put(   K(k=>6), K(d=>56));

  $t->getBlock(K(o=>0x2C0), 31, 30, 29);
  $t->lengthIntoKeys(31, K 1 => 1);
  $t->putBlock(K(o=>0x2C0), 31, 30, 29);
  $t->dump("6");

  $t->key->copy(K k => 4);
  $t->mergeOrSteal(K o => 0x140);
  $t->dump("5");

  ok Assemble eq => <<END;
6
At:  200                    length:    2,  data:  240,  nodes:  280,  first:   40, root, parent
  Index:    0    1
  Keys :    2    4
  Data :   22   44
  Nodes:   80  140  2C0
    At:   80                length:    1,  data:   C0,  nodes:  100,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    1
      Data :   11
    end
    At:  140                length:    1,  data:  180,  nodes:  1C0,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    3
      Data :   33
    end
    At:  2C0                length:    1,  data:  300,  nodes:  340,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    5
      Data :   55
    end
end
5
At:  200                    length:    1,  data:  240,  nodes:  280,  first:   40, root, parent
  Index:    0
  Keys :    2
  Data :   22
  Nodes:   80  140
    At:   80                length:    1,  data:   C0,  nodes:  100,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    1
      Data :   11
    end
    At:  140                length:    3,  data:  180,  nodes:  1C0,  first:   40,  up:  200, leaf
      Index:    0    1    2
      Keys :    3    4    5
      Data :   33   44   55
    end
end
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::mergeOrSteal
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);
  $t->put(   K(k=>1), K(d=>11));
  $t->put(   K(k=>2), K(d=>22));
  $t->put(   K(k=>3), K(d=>33));
  $t->put(   K(k=>4), K(d=>44));
  $t->put(   K(k=>5), K(d=>55));
  $t->put(   K(k=>6), K(d=>56));

  $t->getBlock(K(o=>0x2C0), 31, 30, 29);
  $t->lengthIntoKeys(31, K 1 => 1);
  $t->putBlock(K(o=>0x2C0), 31, 30, 29);
  $t->dump("6");

  $t->key->copy(K k => 2);
  $t->mergeOrSteal(K o => 0x80);
  $t->dump("5");

  ok Assemble eq => <<END;
6
At:  200                    length:    2,  data:  240,  nodes:  280,  first:   40, root, parent
  Index:    0    1
  Keys :    2    4
  Data :   22   44
  Nodes:   80  140  2C0
    At:   80                length:    1,  data:   C0,  nodes:  100,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    1
      Data :   11
    end
    At:  140                length:    1,  data:  180,  nodes:  1C0,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    3
      Data :   33
    end
    At:  2C0                length:    1,  data:  300,  nodes:  340,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    5
      Data :   55
    end
end
5
At:  200                    length:    1,  data:  240,  nodes:  280,  first:   40, root, parent
  Index:    0
  Keys :    4
  Data :   44
  Nodes:   80  2C0
    At:   80                length:    3,  data:   C0,  nodes:  100,  first:   40,  up:  200, leaf
      Index:    0    1    2
      Keys :    1    2    3
      Data :   11   22   33
    end
    At:  2C0                length:    1,  data:  300,  nodes:  340,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    5
      Data :   55
    end
end
END
 }
sub Nasm::X86::Tree::delete($$)                                                 # Find a key in a tree and delete it
 {my ($tree, $key) = @_;                                                        # Tree descriptor, key field to delete
  @_ == 2 or confess "Two parameters";
  ref($key) =~ m(Variable) or confess "Variable required";

  my $s = Subroutine2
   {my ($p, $s, $sub) = @_;                                                     # Parameters, structures, subroutine definition
    my $success = Label;                                                        # Short circuit if ladders by jumping directly to the end after a successful push

    my $t = $$s{tree};                                                          # Tree to search
    my $k = $$p{key};                                                           # Key to find

    $t->found  ->copy(0);                                                       # Key not found
    $t->data   ->copy(0);                                                       # Data not yet found
    $t->subTree->copy(0);                                                       # Not yet a sub tree
    $t->offset ->copy(0);                                                       # Offset not known
    $t->key->copy($k);                                                          # Copy in key so we know what was searched for

    $t->find($k);                                                               # See if we can find the key
    If $t->found == 0, Then {Jmp $success};                                     # Key not present so we cannot delete

    PushR 28..31;

    my $F = 31; my $K = 30; my $D = 29; my $N = 28;

    my $startDescent = SetLabel();                                              # Start descent at root
    $t->firstFromMemory         ($F);                                           # Load first block
    my $root = $t->rootFromFirst($F);                                           # Start the search from the root to locate the  key to be deleted
    If $root == 0, Then{Jmp $success};                                          # Empty tree so we have not found the key and nothing needs to be done

    my $size = $t->sizeFromFirst($F);                                           # Size of tree
    If $size == 1,                                                              # Delete the last element which must be the matching element
    Then
     {$t->sizeIntoFirst(K(z=>0), $F);
      $t->rootIntoFirst($F, K z=>0);                                            # Empty the tree
      $t->firstIntoMemory($F);                                                  # The position of the key in the root node
      Jmp $success
     };

    $t->getBlock($root, $K, $D, $N);                                            # Load root block
    If $t->leafFromNodes($N) > 0,                                               # Element must be in the root as the root is a leaf and we know the key can be found
    Then
     {my $eq = $t->indexEq($k, $K);                                             # Key must be in this leaf as we know it can be found and this is the last opportunity to find it
      $t->extract($eq, $K, $D, $N);                                             # Extract from root
      $t->decSizeInFirst($F);
      $t->firstIntoMemory($F);
      $t->putBlock($root, $K, $D, $N);
      Jmp $success
     };

    my $P = $root->clone('position');                                           # Position in tree
    K(loop, 99)->for(sub                                                        # Step down through tree looking for the key
     {my ($index, $start, $next, $end) = @_;
      my $eq = $t->indexEq($k, $K);                                             # The key might still be in the parent now known not be a leaf
      If $eq > 0, Then {Jmp $end};                                              # We have found the key so now we need to find the next leaf unless this node is in fact a leaf

      my $i = $t->insertionPoint($k, $K);                                       # The insertion point if we were inserting is the next node to visit
      $P->copy($i->dFromPointInZ($N));                                          # Get the corresponding data

      $t->getBlock($P, $K, $D, $N);                                             # Get the keys/data/nodes

      my $l = $t->lengthFromKeys($K);                                           # Length of node

      If $l == $t->lengthMin,                                                   # Has the the bare minimum so must be merged.
      Then
       {$t->mergeOrSteal($P);                                                   # The position of the previous node known to exist because we are currently on the last node
        Jmp $startDescent;                                                      # Restart descent with this block merged
       };
     });

# The following code should be inserted above at eq
# At this point we have found the item in the left set because we know that it is there in the tree waiting to be found.  Did we find it on a leaf where we cans afely remove it or do we need to go to a leaf and find a replacement?

    If $t->leafFromNodes($N) > 0,                                               # We found the item in a leaf so it can be deleted immediately
    Then
     {my $eq = $t->indexEq($k, $K);                                             # Key must be in this leaf as we know it can be found and this is the last opportunity to find it
      $t->extract($eq, $K, $D, $N);                                             # Remove from block
      $t->putBlock($P, $K, $D, $N);                                             # Save block
      $t->decSizeInFirst($F);                                                   # Decrease size of tree
      $t->firstIntoMemory($F);                                                  # Save first block describing tree back into memory
      Jmp $success;                                                             # Leaf removed
     };

    my $eq = $t->indexEq($k, $K);                                               # Location of key
    my $Q = ($eq << K(one=>1))->dFromPointInZ($N);                              # Go right to the next level down

    PushR $K, $D, $N;
    K(loop, 99)->for(sub                                                        # Find the left most leaf
     {my ($index, $start, $next, $end) = @_;
      If $tree->mergeOrSteal($Q) > 0, Then {Jmp $startDescent};                 # Restart entire process because we might have changed the position of the key being deleted by merging in its vicinity
      $t->getBlock($Q, $K, $D, $N);                                             # Next block down
      If $t->leafFromNodes($N) > 0,                                             # We must hit a leaf eventually
      Then
       {my $key     = dFromZ($K, 0);                                            # Record details of leaf
        my $data    = dFromZ($D, 0);
        my $subTree = $t->getTreeBit($K, K one => 1);
        PopR;
        $sub->call(structures=>{tree=>$t}, parameters=>{key=>$key});            # Delete leaf

        $t->key    ->copy($key);
        $t->data   ->copy($data);
        $t->subTree->copy($subTree);

        $t->replace($eq, $K, $D);
        $t->putBlock($P, $K, $D, $N);                                           # Save block
        $t->decSizeInFirst($F);                                                 # Decrease size of tree
        $t->firstIntoMemory($F);                                                # Save first block describing tree back into memory
        Jmp $success;
       };

      my $i = $t->insertionPoint($k, $K);                                       # The insertion point if we were inserting is the next node to visit
      $Q->copy($i->dFromPointInZ($N));                                          # Get the corresponding offset of the the next block down

      $t->getBlock($Q, $K, $D, $N);                                             # Get the keys/data/nodes
     });
    PrintErrTraceBack "Stuck looking for leaf";

    SetLabel $success;                                                          # Find completed successfully
    PopR;
   } parameters=>[qw(key)],
     structures=>{tree=>$tree},
     name => "Nasm::X86::Tree::delete($$tree{length})";

  $s->call(structures=>{tree => $tree}, parameters=>{key => $key});
 } # delete

#latest:
if (1) {                                                                        #TNasm::X86::Tree::delete
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);
  $t->put(   K(k=>1), K(d=>11));
  $t->put(   K(k=>2), K(d=>22));
  $t->put(   K(k=>3), K(d=>33));
  $t->delete(K k=>1);
  $t->dump("1");
  $t->delete(K k=>3);
  $t->dump("3");
  $t->delete(K k=>2);
  $t->dump("2");
  ok Assemble eq => <<END;
1
At:   80                    length:    2,  data:   C0,  nodes:  100,  first:   40, root, leaf
  Index:    0    1
  Keys :    2    3
  Data :   22   33
end
3
At:   80                    length:    1,  data:   C0,  nodes:  100,  first:   40, root, leaf
  Index:    0
  Keys :    2
  Data :   22
end
2
- empty
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::delete
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);
  $t->put(   K(k=>1), K(d=>11));
  $t->put(   K(k=>2), K(d=>22));
  $t->put(   K(k=>3), K(d=>33));
  $t->put(   K(k=>4), K(d=>44));
  $t->dump("0");
  $t->delete(K k=>1);
  $t->dump("1");
  $t->delete(K k=>2);
  $t->dump("2");
  $t->delete(K k=>3);
  $t->dump("3");
  $t->delete(K k=>4);
  $t->dump("4");
  ok Assemble eq => <<END;
0
At:  200                    length:    1,  data:  240,  nodes:  280,  first:   40, root, parent
  Index:    0
  Keys :    2
  Data :   22
  Nodes:   80  140
    At:   80                length:    1,  data:   C0,  nodes:  100,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    1
      Data :   11
    end
    At:  140                length:    2,  data:  180,  nodes:  1C0,  first:   40,  up:  200, leaf
      Index:    0    1
      Keys :    3    4
      Data :   33   44
    end
end
1
At:  200                    length:    1,  data:  240,  nodes:  280,  first:   40, root, parent
  Index:    0
  Keys :    3
  Data :   33
  Nodes:   80  140
    At:   80                length:    1,  data:   C0,  nodes:  100,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    2
      Data :   22
    end
    At:  140                length:    1,  data:  180,  nodes:  1C0,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    4
      Data :   44
    end
end
2
At:   80                    length:    2,  data:   C0,  nodes:  100,  first:   40, root, leaf
  Index:    0    1
  Keys :    3    4
  Data :   33   44
end
3
At:   80                    length:    1,  data:   C0,  nodes:  100,  first:   40, root, leaf
  Index:    0
  Keys :    4
  Data :   44
end
4
- empty
END
 }

#latest:
if (1) {                                                                        #TNasm::X86::Tree::delete
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);
  $t->put(   K(k=>1), K(d=>11));
  $t->put(   K(k=>2), K(d=>22));
  $t->put(   K(k=>3), K(d=>33));
  $t->put(   K(k=>4), K(d=>44));
  $t->dump("0");
  $t->delete(K k=>3);
  $t->dump("3");
  $t->delete(K k=>4);
  $t->dump("4");
  $t->delete(K k=>2);
  $t->dump("2");
  $t->delete(K k=>1);
  $t->dump("1");
  ok Assemble eq => <<END;
0
At:  200                    length:    1,  data:  240,  nodes:  280,  first:   40, root, parent
  Index:    0
  Keys :    2
  Data :   22
  Nodes:   80  140
    At:   80                length:    1,  data:   C0,  nodes:  100,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    1
      Data :   11
    end
    At:  140                length:    2,  data:  180,  nodes:  1C0,  first:   40,  up:  200, leaf
      Index:    0    1
      Keys :    3    4
      Data :   33   44
    end
end
3
At:  200                    length:    1,  data:  240,  nodes:  280,  first:   40, root, parent
  Index:    0
  Keys :    2
  Data :   22
  Nodes:   80  140
    At:   80                length:    1,  data:   C0,  nodes:  100,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    1
      Data :   11
    end
    At:  140                length:    1,  data:  180,  nodes:  1C0,  first:   40,  up:  200, leaf
      Index:    0
      Keys :    4
      Data :   44
    end
end
4
At:   80                    length:    2,  data:   C0,  nodes:  100,  first:   40, root, leaf
  Index:    0    1
  Keys :    1    2
  Data :   11   22
end
2
At:   80                    length:    1,  data:   C0,  nodes:  100,  first:   40, root, leaf
  Index:    0
  Keys :    1
  Data :   11
end
1
- empty
END
 }

latest:
if (1) {                                                                        #TNasm::X86::Tree::delete
  my $a = CreateArena;
  my $t = $a->CreateTree(length => 3);
  my $N = K max => 100;

  $N->for(sub                                                                   # Load tree
   {my ($index, $start, $next, $end) = @_;
    $t->put($index, 2 * $index);
    If $t->size != $index + 1,
    Then
     {PrintOutStringNL "SSSS"; $index->outNL; Exit(0);
     };
   });

  $N->for(sub                                                                   # Check elements
   {my ($i) = @_;
    $t->find($i);
    If $t->found == 0,
    Then
     {PrintOutStringNL "AAAA"; $i->outNL; Exit(0);
     };
   });

  $N->for(sub                                                                   # Delete elements
   {my ($i) = @_;
    $t->delete($i);

    If $t->size != $N - $i - 1,
    Then
     {PrintOutStringNL "TTTT"; $i->outNL; Exit(0);
     };

    $N->for(sub                                                                 # Check elements
     {my ($j) = @_;
      $t->find($j);
      If $t->found == 0,
      Then
       {If $j > $i,
        Then
         {PrintOutStringNL "BBBBB"; $j->outNL; Exit(0);                         # Not deleted yet so it should be findable
         };
       },
      Else
       {If $j <= $i,
        Then
         {PrintOutStringNL "CCCCC"; $j->outNL; Exit(0);                         # Deleted so should not be findable
         };
       };
     });
   });

  ok Assemble eq => <<END;
END
 }

#latest:
if (0) {                                                                        #
  ok Assemble eq => <<END;
END
 }

done_testing;

=pod

Status:

Need to make a subroutine out of the insert into key/data/node block

=cut

#unlink $_ for qw(hash print2 sde-log.txt sde-ptr-check.out.txt z.txt);         # Remove incidental files
#unlink $_ for qw(hash print2 pin-log.txt pin-tool-log.txt sde-footprint.txt sde-log.txt clear hash signal z.o);
unlink $_ for qw(sde-footprint.txt sde-log.txt z.txt);

say STDERR sprintf("# Time: %.2fs, bytes: %s, execs: %s",
  time - $start,
  map {numberWithCommas $_} totalBytesAssembled, $instructionsExecuted);
