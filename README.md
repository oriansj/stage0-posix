# stage0-posix

This repository contains all the various parts needed to bootstrap the
following:
- mescc-tools (https://github.com/oriansj/mescc-tools), containing:
  - M1
  - blood-elf
  - get_machine
  - hex2
  - kaem
- mescc-tools-extra (https://github.com/oriansj/mescc-tools-extra), containing:
  - catm
  - cp
  - chmod
  - match
  - mkdir
  - ungz
  - untar
  - sha256sum
- M2-Planet (https://github.com/oriansj/M2-Planet)

It bootstraps all these from a single 256 byte seed (which you will find in the
folder bootstrap-seeds). The ultimate goal is for this to bootstrap all the way
up to GCC. Thanks to the wonderful people on #bootstrappable and their hard work
https://github.com/fosslinux/live-bootstrap it is done. Everything you need to
go from Hex0 to GCC+Guile is just a kaem.run away.

There is only one "missing" part that is not bootstrappable from the hex0 seed; a
kernel. This issue is not yet solved and at the moment the kernel is trusted.
(This issue will ultimately have to be solved on bare metal in stage0)

This repository currently supports AMD64 (x86_64), x86 (i386), AArch64 and RISC-V
(32 and 64-bit) architectures. To run the entire bootstrap process in the safest way,
run the following command matching your architecture:
`bootstrap-seeds/POSIX/AMD64/kaem-optional-seed`
`bootstrap-seeds/POSIX/x86/kaem-optional-seed`
`bootstrap-seeds/POSIX/AArch64/kaem-optional-seed`
`bootstrap-seeds/POSIX/riscv32/kaem-optional-seed`
`bootstrap-seeds/POSIX/riscv64/kaem-optional-seed`
This uses the kaem seed rather then relying on your shell.

At this stage of the bootstrap process we use a very minimal kaem. It does not
support all of the same arguments and features as full kaem.
Does support:
 - Line comments
 - String collection
 - Execution of commands
Does not support:
 - `--verbose` (forced ON)
 - `--strict` (forced ON)
 - `-f` (remove -f file should be first argument if any)
 - cd
 - set
 - etc etc etc
The C code matching its behavior is in "High\ Level\ Prototypes/kaem-minimal.c"
It should only be used for the first stages of the bootstrap process.

The bootstrappable effort is all about trust. You should verify each of these
programs, from the hex0 monitor up to mes-m2, along with the kaem seed and the
kaem.run files if you can. There are some efforts to attempt to make it easier
to verify these binaries. This is done primarily by re-writing the lowest level
programs in assembly, so that you can recompile them, checking the hashes
match. If they do, verify only the higher-level source since you know that
source has the same instructions as the lower-level source.

This repository utilizes submodules, so you need to clone this repository using
`git clone --recursive`. If you have already cloned it run `git submodule update
--init` or after a pull be sure to do: git submodule update --recursive

Note that this README may not answer all your questions. If you are still left
wondering things like What is a kaem.run?, see the other repositories readme's
which might answer some more tool-specific questions.

We hang out on the libera.chat IRC network in the #bootstrappable channel.
And a full summary of all of the tools can be found here:
https://github.com/oriansj/talk-notes/blob/master/bootstrappable.org

## How does this process work?

It is highly recommended that after reading this you go through the kaem.run for
your architecture and see each of these steps in action. Note that the kaem.run
is split into two kaem files to make it simpler to grasp. These two files are
mescc-tools-mini-kaem.kaem for Phase 0-9 (uses the simple kaem),
mescc-tools-full-kaem.kaem for Phase 10-12 (uses the full kaem for the rest of
mescc-tools) and mes-m2.kaem for Phase 13, contained in the same folder as
kaem.run.

ALL of these steps have a NASM or GAS version in the NASM/ or GAS/ subdirectory
of the folder for the architecture.

All of the intermediate build products are in the $ARCH/artifact/ folders (for
inspection and audit purposes)

### Phase 0: Rebuild hex0 from the hex0 seed

This is done to ensure that the hex0 seed is untainted, and that the
hex0 seed matches the compiled hex0 source. You should check these are
identical!

### Phase 1: Build hex1 from the Phase 0 hex0

hex1 is a more advanced version of hex0 with support for single
character labels and a single size of relational jumps (hex0 has no
support for labels or calculated relational jumps).

#### Phase 1b: Build catm from Phase 0 hex0

catm is a program removing the need for cat or redirection by
implementing equivalent functionality; e.g. `cat input1 input2
... inputN > output_file` would be replaced by `catm output_file
input1 input2 ... inputN`

### Phase 2: Build hex2-0 from hex1

hex2 is the final version of the hex* series adding support for long
labels and absolute addresses. This allows it to function as a linker
for later parts of the bootstrap. However for now we are only building
a basic version to make the process simpler, hence the -0 on the end
of the name; as this hex2 only works for the single host architecture
it was built upon.

### Phase 3: Build M0 from Phase 2 hex2-0

M0 is an architecture specific version of M1 which will come later. It
is simply a temporary binary that avoids the need to write a
cross-architecture assembler in hex2, as M0 supports just enough
functionality to build the next few stages.

### Phase 4: Build cc_* from M0

cc\_architecture is a per-architecture C compiler written in the same
architecture's M0. Eg, there is cc\_amd64 for amd64 and cc\_x86 for
x86. It implements only an extremely basic form of C that is used to
bootstrap the next phase.

### Phase 5: Build M2-Planet from cc_*

M2-Planet is another C compiler that implements a slightly larger
subset of C. However this is not an easily debuggable version and is
replaced towards the end.

### Phase 6: Build blood-elf-0 using M2-Planet

blood-elf adds dwarf stubs to a M1 program allowing us to create more
easily debuggable programs. However, this version is not debuggable
(as it is built without dwarf stubs) and is indicated by such with -0
on the end.

From here on in, all the remaining phases are not intermediate binaries and are
used as results. Note that we have been using hex2-0 for the whole time up until
now. Also note that now all binaries are debuggable, can generate stack traces,
etc, thanks to blood-elf.

### Phase 7: Build M1 (bootstrap) implementation in M2-Planet

M1 is a cross-platform version of M0, along with being much more
powerful and faster.

We are doing the bootstrap version because M0 doesn't support octal but M2libc
uses octal in the non-bootstrap stdio.c library.

Note that now we are not using M0; it is replaced with M1.

### Phase 8: Build hex2 (bootstrap) implementation in M2-Planet

This version of hex2 is cross-platform and has a number of outstanding
features which are out of scope here. This is a useful linker that is
used in the next stage of the bootstrap process.

We are doing the bootstrap version because not all architectures implementations
of hex2-0 support all of the features required by the non-bootstrap version.

Note that from now we no longer need catm, as hex2 and M1 have support for
multiple inputs; hex2-0 is replaced with hex2.

### Phase 9: Rebuild M1 to full speed

This is the final debuggable version of M1 with all of the optimizations and
features provided by M2libc and M2-Planet to enable significantly faster builds.

### Phase 10: Rebuild hex2 to full speed

This is the final debuggable version of hex2 with all of the optimizations and
features provided by M2libc and M2-Planet to enable significantly faster builds.

### Phase 11: Build kaem

kaem is what was being used to run kaem.run scripts, and is useful for
later stages of the bootstrap process outside this repository.

### Phase 12: Build blood-elf implementation in M2-Planet

blood-elf was discussed earlier and now can be used properly to create
debuggable programs with ELF headers.

### Phase 13: Build get_machine

get_machine finds the architecture of the system it is running on,
used for architecture dependent scripts used later in the bootstrap
process.

### Phase 14: Build M2-Planet from M2-Planet

This is the same M2-Planet as discussed earlier, it just is built
using itself and so is going to work more quickly and reliably.

### Phase 15: Build sha256sum

sha256sum is used for giving us a cryptographically signed build chain.

### Phase 16: Build match

match compares two strings. This allows to write architecture specific
conditional code in kaem scripts.

### Phase 17: build mkdir

To eliminate the need to premake directories in live-bootstrap.

### Phase 18: Build untar

untar enables stage0-posix to unpack source tarballs so that git submodules are
not needed to further extend stage0-posix to achieve GCC+Linux.

### Phase 19: Build ungz

ungz enables the decompressing of .tar.gz tarballs such as Gnu Mes. Thus
enabling source tarballs on hosts that don't distribute uncompressed tarballs.

### Phase 19: Build unbz2

Similar to ungz, unbz2 enables the decompressing of .tar.bz2 tarballs.

### Phase 21: Build catm

catm is a simple tool that provides the functionality of:
cat file1 file2 ... fileN >| output in environments where pipes and I/O
redirection doesn't exist. With slightly unique syntax:
catm output file1 file2 ... fileN

### Phase 22: build primitive cp

This primitive version of cp simply copies the contents of the file but does NOT
copy the file permissions or any other STAT information.

### Phase 23: build chmod

To fix up the permissions, of any binaries you used the primitive cp command to
move, chmod is included.

### Phase 24: after.kaem

after.kaem exists for you to replace with anything you want to kick off your
bootstrap chain.

Enjoy
