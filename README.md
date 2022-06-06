# Please [help](https://en.wikipedia.org/wiki/Online_help) with this project by getting involved!

Please feel free to join in with this interesting project - we need all the [help](https://en.wikipedia.org/wiki/Online_help) we can get - so much so that as an incentive to do so, we will be pleased
to offer you free Perl and Assembler training to [help](https://en.wikipedia.org/wiki/Online_help) you make useful
contributions to this [module](https://en.wikipedia.org/wiki/Modular_programming). 
# Generate and run [X86-64](https://en.wikipedia.org/wiki/X86-64) [Advanced Vector Extensions](https://en.wikipedia.org/wiki/AVX-512) [assembler](https://en.wikipedia.org/wiki/Assembly_language#Assembler) [programs](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/) 
![Test](https://github.com/philiprbrenan/Nasmx86/workflows/Test/badge.svg)

This [module](https://en.wikipedia.org/wiki/Modular_programming) generates and runs [Intel](https://en.wikipedia.org/wiki/Intel) [X86-64](https://en.wikipedia.org/wiki/X86-64) [Advanced Vector Extensions](https://en.wikipedia.org/wiki/AVX-512) [assembler](https://en.wikipedia.org/wiki/Assembly_language#Assembler) [programs](https://en.wikipedia.org/wiki/Computer_program) using [Perl](http://www.perl.org/) as a powerful macro [preprocessor](https://en.wikipedia.org/wiki/Preprocessor) for [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm). It contains useful methods to debug [programs](https://en.wikipedia.org/wiki/Computer_program) during development making this system an ideal development environment
for any-one who wants to learn how to [program](https://en.wikipedia.org/wiki/Computer_program) quickly with [assembler](https://en.wikipedia.org/wiki/Assembly_language#Assembler) [code](https://en.wikipedia.org/wiki/Computer_program). 
Full documentation is available at
[Nasm::X86](https://metacpan.org/pod/Nasm::X86).


The [GitHub
Action](https://github.com/philiprbrenan/NasmX86/blob/main/.github/workflows/main.yml)
in this repo shows how to [install](https://en.wikipedia.org/wiki/Installation_(computer_programs)) [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and the [Intel Software Development Emulator](https://software.intel.com/content/www/us/en/develop/articles/intel-software-development-emulator.html) used to [assemble](https://en.wikipedia.org/wiki/Assembly_language#Assembler) and
then run the [programs](https://en.wikipedia.org/wiki/Computer_program) generated by this [module](https://en.wikipedia.org/wiki/Modular_programming). 

This [module](https://en.wikipedia.org/wiki/Modular_programming) provides an implementation of 6/13 way [trees](https://en.wikipedia.org/wiki/Tree_(data_structure)) using [Advanced Vector Extensions](https://en.wikipedia.org/wiki/AVX-512) instructions to perform key comparisons in parallel. The efficient
implementation of such [trees](https://en.wikipedia.org/wiki/Tree_(data_structure)) enables the efficient implementation of other
dynamic data structures such as [strings](https://en.wikipedia.org/wiki/String_(computer_science)), stacks, [arrays](https://en.wikipedia.org/wiki/Dynamic_array), maps and functions.


Each such dynamic data structure is held in a [relocatable](https://en.wikipedia.org/wiki/Relocation_%28computing%29) area allowing these
data structures to be created in one [program](https://en.wikipedia.org/wiki/Computer_program) then mapped to files via virtual
paging or to a [socket](https://en.wikipedia.org/wiki/Network_socket) before being reused at a different location in [memory](https://en.wikipedia.org/wiki/Computer_memory) by
another [program](https://en.wikipedia.org/wiki/Computer_program). 

In particular position independent [X86-64](https://en.wikipedia.org/wiki/X86-64) [code](https://en.wikipedia.org/wiki/Computer_program) can be placed in such areas,
indexed by a 6/13 [tree](https://en.wikipedia.org/wiki/Tree_(data_structure)) and then reloaded as a library of functions for reuse
elsewhere at a later date.


Such [relocatable](https://en.wikipedia.org/wiki/Relocation_%28computing%29) areas work well with parallel processing: each child [sub](https://perldoc.perl.org/perlsub.html) [task](http://docs.oasis-open.org/dita/dita/v1.3/errata02/os/complete/part3-all-inclusive/langRef/technicalContent/task.html#task) can run in a separate [process](https://en.wikipedia.org/wiki/Process_management_(computing)) that creates an area of dynamic data structures
describing the results of the child's processing. The resulting areas  can be
easily transmitted to the parent [process](https://en.wikipedia.org/wiki/Process_management_(computing)) through a [file](https://en.wikipedia.org/wiki/Computer_file) or a [socket](https://en.wikipedia.org/wiki/Network_socket) and then
interpreted by the parent regardless of the location in [memory](https://en.wikipedia.org/wiki/Computer_memory) at which the
child [process](https://en.wikipedia.org/wiki/Process_management_(computing)) created the dynamic data structures contained in the transmitted
area.


Other notable features provided by this [module](https://en.wikipedia.org/wiki/Modular_programming) are a parser for B<Unisyn> a
generic, universal, [utf8](https://en.wikipedia.org/wiki/UTF-8) based syntax for constructing programming languages
that can make extensive use of the operators and alphabets provide by the [Unicode](https://en.wikipedia.org/wiki/Unicode) standard.


# Useful links

- [x86 instructions](https://hjlebbink.github.io/x86doc/)

- [Avx512 SIMD x86 instructions](https://www.officedaytime.com/simd512e/)

- [Linux system calls](https://filippo.io/linux-syscall-table/)

- [Linux error codes](https://www-numi.fnal.gov/offline_software/srt_public_context/WebDocs/Errors/unix_system_errors.html)

- [Netwide assembler](https://www.nasm.us/xdoc/2.15.05/html/nasmdoc0.html)

- [Intel emulator](https://software.intel.com/content/dam/develop/external/us/en/documents/downloads/sde-external-8.63.0-2021-01-18-lin.tar.bz2)

- [Ascii table](https://www.asciitable.com/)


# Print some [Fibonacci](https://en.wikipedia.org/wiki/Fibonacci_number) numbers from [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Print the first 11 [Fibonacci](https://en.wikipedia.org/wiki/Fibonacci_number) numbers:

```
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

# Read lines from [stdin](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) and print them out on [stdout](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) from [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Read lines of up to 8 characters delimited by a new line character from [stdin](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) and print them on [stdout](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)): 
```
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

# Read integers in decimal from [stdin](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) and print them out on [stdout](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) in decimal from [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Read integers from 0 to 2**32 from [stdin](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) in decimal and print them out on [stdout](https://en.wikipedia.org/wiki/Standard_streams#Standard_input_(stdin)) in decimal:

```
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

# Write [Unicode](https://en.wikipedia.org/wiki/Unicode) characters from [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Generate and write some [Unicode](https://en.wikipedia.org/wiki/Unicode) [utf8](https://en.wikipedia.org/wiki/UTF-8) characters:

```
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
ð°ð±ð²ð³ð´ðµð¶ð·ð¸ð¹ðºð»ð¼ð½ð¾ð¿
END
```

# Read a [file](https://en.wikipedia.org/wiki/Computer_file) and print it out from [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 

Read this file and print it out:

```
  use Nasm::X86 qw(:all);

  Mov rax, Rs($0);                  # File to read
  ReadFile;                         # Read file

  PrintOutMemory;                   # Print memory

  my $r = Assemble;                 # Assemble and execute
  ok index($r, readFile($0)) > -1;  # Output contains this file
```

# Print numbers in decimal from [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Debug your [programs](https://en.wikipedia.org/wiki/Computer_program) quickly with powerful print statements:

```
  Mov rax, 0x2a;
  PrintOutRaxRightInDec   V width=> 4;
  Shl rax, 1;
  PrintOutRaxRightInDecNL V width=> 6;

  ok Assemble eq => <<END;
  42    84
END
```

# Call functions in Libc from [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Call **C** functions by naming them as external and including their library:

```
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

# Avx512 instructions from [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Use [Advanced Vector Extensions](https://en.wikipedia.org/wiki/AVX-512) instructions to compare 64 bytes at a time using the 512 [bit](https://en.wikipedia.org/wiki/Bit) wide zmm registers from [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
```
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


# Create a library from [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Create a [library](https://en.wikipedia.org/wiki/Library_(computing)) with three routines in it and save the [library](https://en.wikipedia.org/wiki/Library_(computing)) in a [file](https://en.wikipedia.org/wiki/Computer_file): 
```
  my $library = CreateLibrary          # Library definition
   (subroutines =>                     # Sub routines in libray
     {inc => sub {Inc rax},            # Increment rax
      dup => sub {Shl rax, 1},         # Double rax
      put => sub {PrintOutRaxInDecNL}, # Print rax in decimal
     },
    file => q(library),
   );

```

Reuse the [code](https://en.wikipedia.org/wiki/Computer_program) in the [library](https://en.wikipedia.org/wiki/Library_(computing)) in another [assembly](https://en.wikipedia.org/wiki/Assembly_language): 
```
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

# Dynamic [string](https://en.wikipedia.org/wiki/String_(computer_science)) held in an [arena](https://en.wikipedia.org/wiki/Region-based_memory_management) from [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Create a dynamic [string](https://en.wikipedia.org/wiki/String_(computer_science)) within an [arena](https://en.wikipedia.org/wiki/Region-based_memory_management) and add some content to it:

```
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
```

# Dynamic [array](https://en.wikipedia.org/wiki/Dynamic_array) held in an [arena](https://en.wikipedia.org/wiki/Region-based_memory_management) from [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Create a dynamic [array](https://en.wikipedia.org/wiki/Dynamic_array) within an [arena](https://en.wikipedia.org/wiki/Region-based_memory_management), push some content on to it then pop it
off again:
```
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
```

# Create a multi way [tree](https://en.wikipedia.org/wiki/Tree_(data_structure)) in an [arena](https://en.wikipedia.org/wiki/Region-based_memory_management) using SIMD instructions from [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Create a multiway [tree](https://en.wikipedia.org/wiki/Tree_(data_structure)) as in L<Tree::Multi> using B<Avx512> instructions and
iterate through it:

```
  my $N = 12;
  my $b = CreateArena;                       # Resizable memory block
  my $t = $b->CreateTree;                    # Multi way tree in memory block

  K(count, $N)->for(sub                      # Add some entries to the tree
   {my ($index, $start, $next, $end) = @_;
    my $k = $index + 1;
    $t->insert($k,      $k + 0x100);
    $t->insert($k + $N, $k + 0x200);
   });

  $t->by(sub                                 # Iterate through the tree
   {my ($iter, $end) = @_;
    $iter->key ->out('key: ');
    $iter->data->out(' data: ');
    $iter->tree->depth($iter->node, my $D = V(depth));

    $t->find($iter->key);
    $t->found->out(' found: '); $t->data->out(' data: '); $D->outNL(' depth: ');
   });

  $t->find(K(key, 0xffff));  $t->found->outNL('Found: ');
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
```

# Quarks held in an [arena](https://en.wikipedia.org/wiki/Region-based_memory_management) from [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Quarks replace unique [strings](https://en.wikipedia.org/wiki/String_(computer_science)) with unique numbers and in doing so unite all
that is best and brightest in dynamic [trees](https://en.wikipedia.org/wiki/Tree_(data_structure)), [arrays](https://en.wikipedia.org/wiki/Dynamic_array), [strings](https://en.wikipedia.org/wiki/String_(computer_science)) and short [strings](https://en.wikipedia.org/wiki/String_(computer_science)), all written in X86 [assembler](https://en.wikipedia.org/wiki/Assembly_language#Assembler), all generated by Perl:

```
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
```

# Recursion with stack and parameter tracing from [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Call a subroutine [recursively](https://en.wikipedia.org/wiki/Recursion) and get a trace back showing the procedure calls
and parameters passed to each call. Parameters are passed by reference not
value.

```
  my $d = V depth => 3;                       # Create a variable on the stack

  my $s = Subroutine
   {my ($p, $s) = @_;                         # Parameters, subroutine descriptor
    PrintOutTraceBack;

    my $d = $$p{depth}->copy($$p{depth} - 1); # Modify the variable referenced by the parameter

    If ($d > 0,
    Then
     {$s->call($d);                           # Recurse
     });

    PrintOutTraceBack;
   } [qw(depth)], name => 'ref';

  $s->call($d);                               # Call the subroutine

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
```

# Process management from [assembly](https://en.wikipedia.org/wiki/Assembly_language) [code](https://en.wikipedia.org/wiki/Computer_program) using [NASM - the Netwide Assember](https://github.com/netwide-assembler/nasm) and [Perl](http://www.perl.org/): 
Start a child [process](https://en.wikipedia.org/wiki/Process_management_(computing)) and wait for it, printing out the [process](https://en.wikipedia.org/wiki/Process_management_(computing)) identifiers of
each [process](https://en.wikipedia.org/wiki/Process_management_(computing)) involved:


  ```
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
