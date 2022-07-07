# Please get involved with this project!

Please join in with this interesting project - we need all the [help](https://en.wikipedia.org/wiki/Online_help) we can get
to optimize the [code](https://en.wikipedia.org/wiki/Computer_program) base - so much so that as an incentive to do so, we will
be pleased to offer you free Perl and Assembler training to [help](https://en.wikipedia.org/wiki/Online_help) you make such
contributions to this project.

# Generate and run [X86-64](https://en.wikipedia.org/wiki/X86-64) [Advanced Vector Extensions](https://en.wikipedia.org/wiki/AVX-512) [assembler](https://en.wikipedia.org/wiki/Assembly_language#Assembler) [programs](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/) 
![Test](https://github.com/philiprbrenan/Nasmx86/workflows/Test/badge.svg)

Generate and run [Intel](https://en.wikipedia.org/wiki/Intel) [X86-64](https://en.wikipedia.org/wiki/X86-64) [Advanced Vector Extensions](https://en.wikipedia.org/wiki/AVX-512) [assembler](https://en.wikipedia.org/wiki/Assembly_language#Assembler) [programs](https://en.wikipedia.org/wiki/Computer_program) using [Perl](http://www.perl.org/) as a powerful
macro [preprocessor](https://en.wikipedia.org/wiki/Preprocessor) for [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm). The [Perl](http://www.perl.org/) [module](https://en.wikipedia.org/wiki/Modular_programming) contained in this repository
contains useful methods to [help](https://en.wikipedia.org/wiki/Online_help) you quickly write and debug [programs](https://en.wikipedia.org/wiki/Computer_program)  making
this system an ideal development environment for any-one who wants to learn how
to [program](https://en.wikipedia.org/wiki/Computer_program) effectively in [X86-64](https://en.wikipedia.org/wiki/X86-64) [assembler](https://en.wikipedia.org/wiki/Assembly_language#Assembler) [code](https://en.wikipedia.org/wiki/Computer_program). 
Full documentation is available at
[Nasm::X86](https://metacpan.org/pod/Nasm::X86).


The [GitHub
Action](https://github.com/philiprbrenan/NasmX86/blob/main/.github/workflows/main.yml)
in this repo shows how to [install](https://en.wikipedia.org/wiki/Installation_(computer_programs)) [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and the [Intel Software Development Emulator](https://software.intel.com/content/www/us/en/develop/articles/intel-software-development-emulator.html) used to [assemble](https://en.wikipedia.org/wiki/Assembly_language#Assembler) and
then run the [programs](https://en.wikipedia.org/wiki/Computer_program) generated by this [module](https://en.wikipedia.org/wiki/Modular_programming). 
This repository includes an implementation of 6/13 multi-way [trees](https://en.wikipedia.org/wiki/Tree_(data_structure)) using [Advanced Vector Extensions](https://en.wikipedia.org/wiki/AVX-512) instructions to perform key comparisons in parallel and [relocatable](https://en.wikipedia.org/wiki/Relocation_%28computing%29) data [arenas](https://en.wikipedia.org/wiki/Region-based_memory_management) that are used to contain other data structures. The efficient implementation of
such multi-way [trees](https://en.wikipedia.org/wiki/Tree_(data_structure)) and areas enables the efficient implementation of other
dynamic data structures such as [strings](https://en.wikipedia.org/wiki/String_(computer_science)), stacks, [arrays](https://en.wikipedia.org/wiki/Dynamic_array), maps and function
libraries all of which are packed into [relocatable](https://en.wikipedia.org/wiki/Relocation_%28computing%29) areas and addressed via [trees](https://en.wikipedia.org/wiki/Tree_(data_structure)). 

The use of [relocatable](https://en.wikipedia.org/wiki/Relocation_%28computing%29) areas allows data structures to be created in one [program](https://en.wikipedia.org/wiki/Computer_program) then mapped to files via virtual paging or to a [socket](https://en.wikipedia.org/wiki/Network_socket) to enable the
data to be reused at a different location in [memory](https://en.wikipedia.org/wiki/Computer_memory) by another [program](https://en.wikipedia.org/wiki/Computer_program). 

In particular position independent [X86-64](https://en.wikipedia.org/wiki/X86-64) [code](https://en.wikipedia.org/wiki/Computer_program) can be placed in such areas,
indexed by a 6/13 [tree](https://en.wikipedia.org/wiki/Tree_(data_structure)) and then reloaded as a library of functions for reuse
elsewhere at a later date to make [code](https://en.wikipedia.org/wiki/Computer_program) generation efficient.


![5/13 Multiway Tree using avx512](http://prb.appaapps.com/MultiWayTree2.svg)

Such [relocatable](https://en.wikipedia.org/wiki/Relocation_%28computing%29) areas work well with parallel processing: each child [sub](https://perldoc.perl.org/perlsub.html) [task](http://docs.oasis-open.org/dita/dita/v1.3/errata02/os/complete/part3-all-inclusive/langRef/technicalContent/task.html#task) can run in a separate [process](https://en.wikipedia.org/wiki/Process_management_(computing)) that creates an area of dynamic data structures
describing the results of the child's processing. The resulting areas  can be
easily transmitted to the parent [process](https://en.wikipedia.org/wiki/Process_management_(computing)) through a [file](https://en.wikipedia.org/wiki/Computer_file) or a [socket](https://en.wikipedia.org/wiki/Network_socket) and then
interpreted by the parent regardless of the location in [memory](https://en.wikipedia.org/wiki/Computer_memory) at which the
child [process](https://en.wikipedia.org/wiki/Process_management_(computing)) created the dynamic data structures contained in the transmitted
area.

# Unisyn

A parser for the [UniSyn](https://github.com/philiprbrenan/UnisynParse) programming language has been built in [assembler](https://en.wikipedia.org/wiki/Assembly_language#Assembler) using
this software.

**unisyn** implements a generic, universal, [utf8](https://en.wikipedia.org/wiki/UTF-8) based syntax suitable for
constructing programming languages that make extensive use of [infix](https://en.wikipedia.org/wiki/Infix_notation) operators.

**unisyn** enables the definition of new [infix](https://en.wikipedia.org/wiki/Infix_notation) operators using selected [Unicode](https://en.wikipedia.org/wiki/Unicode) points. Each such new [infix](https://en.wikipedia.org/wiki/Infix_notation) operator may have one of 12 precedence levels. The
precedence level for each [infix](https://en.wikipedia.org/wiki/Infix_notation) operator is determined by the alphabet from
within [Unicode](https://en.wikipedia.org/wiki/Unicode) from which its letters are drawn.

For example, the [infix](https://en.wikipedia.org/wiki/Infix_notation) operator: 𝕒𝕟𝕕  would have a priority of 3,
whilst 𝗮𝗻𝗱  would have a priority of 11.

The type of each lexical item in a [UniSyn](https://github.com/philiprbrenan/UnisynParse) [program](https://en.wikipedia.org/wiki/Computer_program) can be determined immediately
by examining any character used in its construction.

The canonical "Hello World" in Unisyn is:

```Hello World```

No quotes are needed because the use of letters drawn from [Ascii](https://en.wikipedia.org/wiki/ASCII) indicate that
these characters are part of a [string](https://en.wikipedia.org/wiki/String_(computer_science)).  [UniSyn](https://github.com/philiprbrenan/UnisynParse) prints such [strings](https://en.wikipedia.org/wiki/String_(computer_science)) on
```stdout``` if they are followed by a statement separator.


# Useful links

- [x86 instructions](https://hjlebbink.github.io/x86doc/)

- [Avx512 SIMD x86 instructions](https://www.officedaytime.com/simd512e/)

- [Linux system calls](https://filippo.io/linux-syscall-table/)

- [Linux error codes](https://www-numi.fnal.gov/offline_software/srt_public_context/WebDocs/Errors/unix_system_errors.html)

- [Netwide assembler](https://www.nasm.us/xdoc/2.15.05/html/nasmdoc0.html)

- [Intel emulator](https://software.intel.com/content/dam/develop/external/us/en/documents/downloads/sde-external-8.63.0-2021-01-18-lin.tar.bz2)

- [Ascii table](https://www.asciitable.com/)


# Examples

## Error tracing with Geany in Perl and Nasm

Get a helpful trace back that translates the location of a failure in a
generated Assembler [program](https://en.wikipedia.org/wiki/Computer_program) with the stack of Perl calls that created the
failing [code](https://en.wikipedia.org/wiki/Computer_program). 
![Trace back](http://prb.appaapps.com/TraceBack.png)

## Parse a Unisyn expression in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Parse a Unisyn expression to create a [parse](https://en.wikipedia.org/wiki/Parsing) [tree](https://en.wikipedia.org/wiki/Tree_(data_structure)) in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
```perl


  my ($s, $l) = constantString "𝗔＝【𝗕＋𝗖】✕𝗗𝐈𝐅𝗘";                                  # Unisyn expression

  my $a = CreateArea;                                                           # Area in which we will do the parse
  my $p = $a->ParseUnisyn($s, $l);                                              # Parse the utf8 string
  $p->tree->dumpParseTree($s);                                                  # Dump the parse tree

  ok Assemble eq => <<END, avx512=>1;
＝
._𝗔
._𝐈𝐅
._._✕
._._._【
._._._._＋
._._._._._𝗕
._._._._._𝗖
._._._𝗗
._._𝗘
END
```

## Print some [Fibonacci](https://en.wikipedia.org/wiki/Fibonacci_number) numbers in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Print the first 11 [Fibonacci](https://en.wikipedia.org/wiki/Fibonacci_number) numbers in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
```perl
  my $N = 11;                         # How many ?
  Mov r13, 0;                         # First  Fibonacci number
  Mov r14, 1;                         # Second Fibonacci
  PrintOutStringNL " i   Fibonacci";  # The title of the piece

  V(N => $N)->for(sub                 # Each Fibonacci number
   {my ($index) = @_;

    $index->outRightInDec(2);         # Print index

    Mov rax, r13;                     # Fibonacci number at this index
    PrintOutRaxRightInDecNL 12;

    Mov r15, r13;                     # Next is the sum of the two previous ones
    Add r15, r14;

    Mov r13, r14;                     # Move up
    Mov r14, r15;
   });

  ok Assemble eq => <<END;            # Assemble and show expected output
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
```

## Binary search in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Search an [array](https://en.wikipedia.org/wiki/Dynamic_array) for a specified double [word](https://en.wikipedia.org/wiki/Doc_(computing)) using binary search in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
```perl
sub BinarySearchD($$)                                                           # Search for an ordered array of double words addressed by r15, of length held in r14 for a double word held in r13 and call the $then routine with the index in rax if found else call the $else routine.
 {my ($then, $else) = @_;                                                       # Routine to call on matchParameters

  my $array = r15, my $length = r14, my $search = r13;                          # Sorted array to search, array length, dword to search for

  my $low = rsi, my $high = rdi, my $loop = rcx, my $range = rdx, my $mid = rax;# Work registers modified by this routine
  Mov $low,  0;                                                                 # Closed start of current range to search
  Mov $high, $length;                                                           # Open end of current range to search

  Cmp $high, 0;                                                                 # Check we have a none empty array to search
  IfEq
  Then                                                                          # Empty array
   {Mov rax, -1;                                                                # Not found
    &$else;
   },
  Else                                                                          # Search non empty array
   {Dec $high;                                                                  # Closed end of current range

    uptoNTimes                                                                  # Search a reasonable number of times
     {my ($end, $start) = @_;                                                   # End, start label
      Mov $mid, $low;                                                           # Find new mid point
      Add $mid, $high;                                                          # Sum of high and low
      Shr $mid, 1;                                                              # Average of high and low is the new mid point.

      Cmp dWordRegister($search), "[$array+$mid*4]";                            # Compare current element of array with search
      Pushfq;                                                                   # Save result of comparison
      IfEq
      Then                                                                      # Found
       {Mov rax, $mid unless rax eq $mid;
        &$then;
        Jmp $end;
       };

      Mov $range, $high;                                                        # Size of remaining range
      Sub $range, $low;
      Cmp $range, 1;

      IfLe
      Then                                                                      # Less than three elements in final range
       {Cmp dWordRegister($search), "[$array+$high*4]";                         # Compare high end of final range with search
        IfEq
        Then                                                                    # Found at high end of final range
         {Mov rax, $high;
          &$then;
          Jmp $end;
         };
        Cmp dWordRegister($search), "[$array+$low*4]";                          # Compare low end of final range with search
        IfEq
        Then                                                                    # Found at low end of final range
         {Mov rax, $low;
          &$then;
          Jmp $end;
         };
        Mov rax, -1;                                                            # Not found in final range
        &$else;
        Jmp $end;
       };

      Popfq;                                                                    # Restore results of comparison
      IfGt                                                                      # Search argument is higher so move up
      Then
       {Mov $low, $mid;                                                         # New lower limit
       },
      Else                                                                      # Search argument is lower so move down
       {Mov $high, $mid;                                                        # New upper limit limit
       };
     } $loop, 999;                                                              # Enough to search all the particles in the universe if they could be ordered by some means
   };
 }

  for my $s(1..17)
   {Mov r15, Rd(2, 4, 6, 8, 10, 12, 14, 16);                                    # Address array to search
    Mov r14, 8;                                                                 # Size of array
    Mov r13, $s;                                                                # Value to search for
    PrintOutString sprintf "%2d:", $s;

    BinarySearchD                                                               # Search
    Then
     {PrintOutString " <= "; PrintOutRaxInDec;  PrintOutNL;                     # Found
     },
    Else
     {PrintOutNL;
     };
   }

  ok Assemble eq => <<END, avx512=>1, mix=>1, trace => 0;
 1:
 2: <= 0
 3:
 4: <= 1
 5:
 6: <= 2
 7:
 8: <= 3
 9:
10: <= 4
11:
12: <= 5
13:
14: <= 6
15:
16: <= 7
17:
END

# Test          Clocks           Bytes    Total Clocks     Total Bytes      Run Time     Assembler          Perl
#    1              42           3_280              42           3_280        0.1425          0.02          0.00
#    2           2_240          41_336           2_282          44_616        0.1062          0.02          0.05
```


# Read lines from [stdin](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) and print them out on [stdout](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Read lines of up to 8 characters delimited by a new line character from [stdin](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) and print them on [stdout](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
```perl
  my $e = q(readWord);
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
```

## Read integers in decimal from [stdin](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) and print them out on [stdout](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) in decimal in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Read integers from 0 to 2**32 from [stdin](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) in decimal and print them out on [stdout](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) in decimal:

```perl
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
```

## Write [Unicode](https://en.wikipedia.org/wiki/Unicode) characters in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Generate and write some [Unicode](https://en.wikipedia.org/wiki/Unicode) [utf8](https://en.wikipedia.org/wiki/UTF-8) characters:

```perl
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
```

## Read a [file](https://en.wikipedia.org/wiki/Computer_file) and print it out in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 

Read this file and print it out in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
```perl
  use Nasm::X86 qw(:all);

  Mov rax, Rs($0);                  # File to read
  ReadFile;                         # Read file

  PrintOutMemory;                   # Print memory

  my $r = Assemble;                 # Assemble and execute
  ok index($r, readFile($0)) > -1;  # Output contains this file
```

## Print numbers in decimal in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Debug your [programs](https://en.wikipedia.org/wiki/Computer_program) quickly with powerful print statements in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
```perl
  Mov rax, 0x2a;
  PrintOutRaxRightInDec   V width=> 4;
  Shl rax, 1;
  PrintOutRaxRightInDecNL V width=> 6;

  ok Assemble eq => <<END;
  42    84
END
```

## Call functions in Libc in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Call **C** functions by naming them as external and including their library in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
```perl
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
```

## Avx512 instructions in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Use [Advanced Vector Extensions](https://en.wikipedia.org/wiki/AVX-512) instructions to compare 64 bytes at a time using the 512 [bit](https://en.wikipedia.org/wiki/Bit) wide zmm registers from [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
```perl
  my $P = "2F";                                   # Value to test for
  my $l = Rb 0;  Rb $_ for 1..RegisterSize zmm0;  # The numbers 0..63
  Vmovdqu8 zmm0, "[$l]";                          # Load data to test
  PrintOutRegisterInHex zmm0;

  Mov rax, "0x$P";                # Broadcast the value to be tested
  Vpbroadcastb zmm1, rax;
  PrintOutRegisterInHex zmm1;

  for my $c(0..7)                 # Each possible test
   {my $m = "k$c";
    Vpcmpub $m, zmm1, zmm0, $c;
    PrintOutRegisterInHex $m;
   }

  Kmovq rax, k0;                  # Count the number of trailing zeros in k0
  Tzcnt rax, rax;
  PrintOutRegisterInHex rax;

  is_deeply [split //, Assemble], [split //, <<END];  # Assemble and test
  zmm0: 3F3E 3D3C 3B3A 3938   3736 3534 3332 3130   2F2E 2D2C 2B2A 2928   2726 2524 2322 2120   1F1E 1D1C 1B1A 1918   1716 1514 1312 1110   0F0E 0D0C 0B0A 0908   0706 0504 0302 0100
  zmm1: 2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F   2F2F 2F2F 2F2F 2F2F
    k0: 0000 8000 0000 0000  # Equals
    k1: FFFF 0000 0000 0000  # Less than
    k2: FFFF 8000 0000 0000  # Less than or equal
    k3: 0000 0000 0000 0000
    k4: FFFF 7FFF FFFF FFFF  # Not equals
    k5: 0000 FFFF FFFF FFFF  # Greater then or equals
    k6: 0000 7FFF FFFF FFFF  # Greater than
    k7: FFFF FFFF FFFF FFFF
   rax: 0000 0000 0000 00$P
END
```


## Create a library in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Create a library with three routines in it and save the library in a [file](https://en.wikipedia.org/wiki/Computer_file) in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
```perl
  my $library = CreateLibrary          # Library definition
   (subroutines =>                     # Sub routines in libray
     {inc => sub {Inc rax},            # Increment rax
      dup => sub {Shl rax, 1},         # Double rax
      put => sub {PrintOutRaxInDecNL}, # Print rax in decimal
     },
    file => q(library),
   );

```

Reuse the [code](https://en.wikipedia.org/wiki/Computer_program) in the library in another [assembly](https://en.wikipedia.org/wiki/Assembly_language): 
```perl
  my ($dup, $inc, $put) = $library->load;  # Load the library into memory

  Mov rax, 1; &$put;
  &$inc;      &$put;                       # Use the subroutines from the library
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
  unlink $l;
```

## Create a 6/13 multi way [tree](https://en.wikipedia.org/wiki/Tree_(data_structure)) in an area using SIMD instructions in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Create a 6/13 multiway [tree](https://en.wikipedia.org/wiki/Tree_(data_structure)) using **Avx512** instructions then iterate through the [tree](https://en.wikipedia.org/wiki/Tree_(data_structure)) each time an element is deleted in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
```perl
  my $a = CreateArea;
  my $t = $a->CreateTree;
  my $N = K loop => 16;
  $N->for(sub
   {my ($i) = @_;
    $t->put($i, $i);
   });
  $t->printInOrder(" 0"); $t->delete(K k =>  0);
  $t->printInOrder(" 2"); $t->delete(K k =>  2);
  $t->printInOrder(" 4"); $t->delete(K k =>  4);
  $t->printInOrder(" 6"); $t->delete(K k =>  6);
  $t->printInOrder(" 8"); $t->delete(K k =>  8);
  $t->printInOrder("10"); $t->delete(K k => 10);
  $t->printInOrder("12"); $t->delete(K k => 12);
  $t->printInOrder("14"); $t->delete(K k => 14);
  $t->printInOrder(" 1"); $t->delete(K k =>  1);
  $t->printInOrder(" 3"); $t->delete(K k =>  3);
  $t->printInOrder(" 5"); $t->delete(K k =>  5);
  $t->printInOrder(" 7"); $t->delete(K k =>  7);
  $t->printInOrder(" 9"); $t->delete(K k =>  9);
  $t->printInOrder("11"); $t->delete(K k => 11);
  $t->printInOrder("13"); $t->delete(K k => 13);
  $t->printInOrder("15"); $t->delete(K k => 15);
  $t->printInOrder("XX");

  ok Assemble eq => <<END, avx512=>1;
 0  16:    0   1   2   3   4   5   6   7   8   9   A   B   C   D   E   F
 2  15:    1   2   3   4   5   6   7   8   9   A   B   C   D   E   F
 4  14:    1   3   4   5   6   7   8   9   A   B   C   D   E   F
 6  13:    1   3   5   6   7   8   9   A   B   C   D   E   F
 8  12:    1   3   5   7   8   9   A   B   C   D   E   F
10  11:    1   3   5   7   9   A   B   C   D   E   F
12  10:    1   3   5   7   9   B   C   D   E   F
14   9:    1   3   5   7   9   B   D   E   F
 1   8:    1   3   5   7   9   B   D   F
 3   7:    3   5   7   9   B   D   F
 5   6:    5   7   9   B   D   F
 7   5:    7   9   B   D   F
 9   4:    9   B   D   F
11   3:    B   D   F
13   2:    D   F
15   1:    F
XX- empty
END
```
# Process management in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Start a child [process](https://en.wikipedia.org/wiki/Process_management_(computing)) and wait for it, printing out the [process](https://en.wikipedia.org/wiki/Process_management_(computing)) identifiers of
each [process](https://en.wikipedia.org/wiki/Process_management_(computing)) involved in [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 

```perl
  use Nasm::X86 qw(:all);

  Fork;                          # Fork

  Test rax,rax;
  If                             # Parent
   {Mov rbx, rax;
    WaitPid;
    PrintOutRegisterInHex rax;
    PrintOutRegisterInHex rbx;
    GetPid;                      # Pid of parent as seen in parent
    Mov rcx,rax;
    PrintOutRegisterInHex rcx;
   }
  sub                            # Child
   {Mov r8,rax;
    PrintOutRegisterInHex r8;
    GetPid;                      # Child pid as seen in child
    Mov r9,rax;
    PrintOutRegisterInHex r9;
    GetPPid;                     # Parent pid as seen in child
    Mov r10,rax;
    PrintOutRegisterInHex r10;
   };

  my $r = Assemble;              # Assemble test and run

  #    r8: 0000 0000 0000 0000   #1 Return from fork as seen by child
  #    r9: 0000 0000 0003 0C63   #2 Pid of child
  #   r10: 0000 0000 0003 0C60   #3 Pid of parent from child
  #   rax: 0000 0000 0003 0C63   #4 Return from fork as seen by parent
  #   rbx: 0000 0000 0003 0C63   #5 Wait for child pid result
  #   rcx: 0000 0000 0003 0C60   #6 Pid of parent
  ```
