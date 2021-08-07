## Copyright (C) 2021 Andrius Štikonas
## This file is part of stage0.
##
## stage0 is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## stage0 is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY; without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with stage0.  If not, see <http://www.gnu.org/licenses/>.

# This is not a real kaem but instead a small hardcoded script to build
# and launch kaem-minimal.
# It first uses hex0-seed to build hex0.
# Then uses hex0 to build kaem-minimal and starts it.

# It expects hex0_riscv64.hex0 and kaem-minimal.hex0 files to be in the current directory.
# Path to hex0-seed is assumed to be ../bootstrap-seeds/POSIX/riscv64/hex0-seed
# However it is the last thing in the binary, so updating it is trivial and
# does not affect anything else in the file.

# Register use:
# s1: address to pointer array of program and arguments to be executed
# s2: have_hex0

.text
.global _start
_start:
    la s1, argv_hex0                  # hex0-seed hex0_riscv64.hex0 hex0
    j clone                           # jump to clone

kaem_minimal:
    la s1, argv_kaem                  # hex0 kaem-minimal.hex0 kaem
    not s2, s2                        # s2 = !s2

clone:
    li a7, 220                        # sys_clone
    li a0, 17                         # SIGCHLD flag
    ecall                             # syscall

    bnez a0, parent                   # if f == 0 it is child

    # Deal with child case
execve:
    ld a0, (s1)                       # program

    li a7, 221                        # sys_execve
    mv a1, s1                         # argv
    ecall                             # execve(program, argv)

    # Terminate child program (only happens on error)
    li a7, 93                         # sys_exit
    ecall                             # exit(1)

parent:
    li a7, 260                        # sys_wait4
    ecall                             # syscall
    beqz s2, kaem_minimal             # Now build kaem

start_kaem:
    la s1, argv_kaem_minimal          # argv
    j execve                          # execve into kaem-minimal

# PROGRAM END

argv_hex0:
    .quad hex0_seed
    .quad hex0_source
    .quad hex0_out
    .quad 0

argv_kaem:
    .quad hex0_out
    .quad kaem_source
argv_kaem_minimal:
    .quad kaem_out
    .quad 0

hex0_seed: .asciz "../bootstrap-seeds/POSIX/riscv64/hex0-seed"
hex0_source: .asciz "hex0_riscv64.hex0"
hex0_out: .asciz "hex0"
kaem_source: .asciz "kaem-minimal.hex0"
kaem_out: .asciz "kaem"
