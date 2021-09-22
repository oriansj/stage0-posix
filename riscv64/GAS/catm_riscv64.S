## Copyright (C) 2021 Andrius Štikonas
## This file is part of stage0.
##
## stage0 is free software: you can redistribute it and/or modify
## it under the terms of the GNU General Public License as published by
## the Free Software Foundation, either version 3 of the License, or
## (at your option) any later version.
##
## stage0 is distributed in the hope that it will be useful,
## but WITHOUT ANY WARRANTY# without even the implied warranty of
## MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
## GNU General Public License for more details.
##
## You should have received a copy of the GNU General Public License
## along with stage0.  If not, see <http://www.gnu.org/licenses/>.

# Register use:
# s1: output file descriptor
# s2: buffer
# s3: input file descriptor
# s4: number of bytes read

.text
.global _start
_start:

# Open output file and store the FD in s1
    li a7, 56                         # sys_openat
    li a0, -100                       # AT_FDCWD
    addi sp, sp, 16                   # Prepare stack for reading output file
    ld a1, (sp)                       # Output file (argument 1)
    li a2, 00001101                   # Prepare file as O_WRONLY|O_CREAT|O_TRUNC
    li a3, 0600                       # Prepare file as RW for owner only (600 in octal)
    ecall                             # syscall
    mv s1, a0                         # Save fd in for later

    # Prepare heap memory
    li a7, 214                        # sys_brk
    mv a0, zero                       # Get current brk
    ecall                             # syscall
    mv s2, a0                         # Set our malloc pointer

    li a1, 0x100000
    add a0, a0, a1                    # Allocate 1MiB
    ecall                             # syscall

core:
    addi sp, sp, 8                    # Move stack pointer to next input file
    ld a1, (sp)                       # Get the input file name
    beqz a1, Done                     # This was the last file, we are done

    li a7, 56                         # sys_openat
    li a0, -100                       # AT_FDCWD
    li a2, 0                          # read only
    ecall                             # syscall
    mv s3, a0                         # protect input fd

keep:
    li a7, 63                         # sys_read
    mv a0, s3                         # input fd
    mv a1, s2                         # read into buffer
    li a2, 0x100000                   # read 1MiB
    ecall                             # syscall
    mv s4, a0                         # actual number of bytes read

    li a7, 64                         # sys_write
    mv a0, s1                         # output fd
    mv a1, s2                         # write from buffer
    mv a2, s4                         # number of bytes to write
    ecall                             # syscall

    li a2, 0x100000                   # 1MiB
    beq s4, a2, keep                  # keep looping if buffer was full
    j core                            # otherwise move to next file

Done:
    # Terminate program with 0 return code
    li a7, 93                         # sys_exit
    mv a0, zero                       # Return code 0
    ecall                             # exit(0)
