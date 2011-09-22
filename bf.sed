#!/bin/sed -f

      ########################################################
      ##                      bf.sed                        ##
      ##                                                    ##
      ##       an optimising compiler for brainfuck         ##
      ##          produces x86 Linux ELF binaries           ##
      ##              written entirely in sed               ##
      ##                                                    ##
      ## usage: bf.sed file.b > prog; chmod +x prog; ./prog ##
      ########################################################

 # slurp in the entire file
:a;$!N;$!ba;

 # remove comments (all characters other than []<>+-.,)
s/[^][,.<>+-]//g;

 # add a dodgy ELF header and some startup/initialisation code
 # see http://www.muppetlabs.com/~breadbox/software/tiny/teensy.html
 # since sed inserts newlines whenever there's a linebreak in the s///
 # command, the program start address is moved to 0x080a8000, which
 # contains a newline character (0x0a).
s/^/\x7fELF\x01\x01\x01zzzzzzzzz\x02z\x03z\x01zzz\x54\x80\
\x08\x34zzzzzzzzzzz\x34z\x20z\x01zzzzzzz\x01zzzzzzzz\x80\n\x08z\x80\
\x08zz\x01zzz\x01z\x05zzzz\x10zz\xfc\x31\xdb\x31\xd2\x42\xb9\x10\x27zz\x04\
\x29\xcc\x89\xe7\x31\xc0\xf3\xaa\x89\xe1/;

 # call exit() at the end of the program. use a direct syscall, it's
 # easier than finding libc.
s/$/\xb0\x01\xb3z\xcd\x80/

 # the registers used are:
 #  ecx - current cell
 #  edx - enable bit (see below)
 #  eax - scratch
 # the memory for the cells is allocated on the stack by the startup code
 # above. sed can't count, so it's difficult to get [ and ] (looping)
 # right. we can't assemble jumps to the end of the loop, so instead of
 # jumping over the loop we set edx to 0 and run the loop's code. all of
 # the instructions used do nothing if edx is zero, so this gets the same
 # effect as a jump over the loop.

 # optimisation: [-] (loop until current cell is zero) is optimised to a
 # "mov byte [ecx], 0" instruction
s/\[-\]/\xc6\x01z/g;

 # +/- come out to add/sub byte [ecx], dl so they inc or dec when edx = 1,
 # and are no-ops when edx = 0
s/[+-]/&\x11/g;

 # optimisation: handle <+>, <->, >+< and >-< specially. these sequences
 # increment or decrement the next or previous cell, and leave the pointer
 # where it is. it's faster to use an addressing mode for this than to move
 # the pointer back and forth. e.g. <+> is compiled to "add [ecx - 1], dl".
s/<\([+-]\)\x11>/\1\x51\xff/g;
s/>\([+-]\)\x11</\1\x51\x01/g;

 # </> come out as add/sub ecx, edx
s/[<>]/&\xd1/g;

 # we optimise sequences of 5 +, -, < or > to perform a single add/sub of
 # edx*5. why edx*5? because multiplication by 5 can be done in an
 # addressing mode (lea eax, [edx + edx * 4]).
s/\(\([<>]\)\xd1\)\1\1\1\1/5\2\xc1/g;
s/\(\([+-]\)\x11\)\1\1\1\1/5\2\x01/g;
s/5/\x8d\x04\x92/g;

 # i/o: , and . invoke the read and write syscalls respectively. due to our
 # not-entirely-random choice of registers, most of the arguments are
 # already in the right locations. in particular, ecx is the buffer to read
 # or write (i.e. points to the current cell), and edx is the length of the
 # buffer (so if edx = 0, the system call's a no-op)
s/[,.]/\xb3&\x8d\x43\x03\xcd\x80/g;

 # looping. [ saves the current edx, pushes its address to the stack, and
 # sets edx to 0 if the current cell is zero. this will run until it hits
 # the corresponding ], which will either jump to the pushed address or
 # restore the old edx and continue, depending on whether the current cell
 # is zero.
s/\[/\x52\x38\x31\x0f\x95\xc2\xe8zzzz/g;
s/\]/\x38\x31\x74\x03\xff\x24\x24\x5a\x5a/g;

 # the above was done treating +/-, </> and ,/. identically, by just
 # setting up addressing modes and parameters. the next line sets up the
 # opcodes to distinguish between add/sub and read/write.
y/+-<>,./z()\x01z\x01/;

 # a bug in gnu sed means y/// can't handle ascii NUL, so we use s///
s/z/\x00/g;

 # the ELF header at the start must include the length of the
 # program. there's no arithmetic in sed, so we can't report this
 # accurately. instead, we append 64k of garbage to the program and mark
 # its length as 64k. as long as the program's actual size is below 64k,
 # the system ignores any data past the end (and it never gets run, because
 # exit() is called first). this won't work if you write a brainfuck
 # program longer than 64k, but if you do that you're even more nuts than
 # me.
p
z
s/.*/aaaaaaaaaaaaaaaa/;
s/.*/&&&&&&&&&&&&&&&&/;
s/.*/&&&&&&&&&&&&&&&&/;
s/.*/&&&&&&&&&&&&&&&&/;
