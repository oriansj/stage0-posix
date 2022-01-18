## Copyright (C) 2021 Ekaitz Zarraga
## Copyright (C) 2021 Andrius Štikonas
## Copyright (C) 2022 Gabriel Wicki
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
# Compile this thing with -nostdlib


# Register use:
# s2: input fd
# s3: output fd
# s4: toggle
# s5: hold

# Uses top of the stack as i/o buffer

.text
.global _start
_start:
    li s4, 0              # Initialize to 0
    ld a1, 16(sp)         # Input file name

    # Open input file and store FD in s2
    li a7, 56             # sys_openat
    li a0, -100           # AT_FDCWD
    li a2, 0              # read only
    ecall
    mv s2, a0             # Save fd in s2 for later

    # Open output file and store the FD in s3
    li a0, -100           # AT_FDCWD
    ld a1, 24(sp)         # Output file (argument 3)
    li a2, 00001101
    # O_TRUNC   00001000
    # O_CREAT   00000100
    # O_WRONLY  00000001
    # OCTAL!
    li a3, 00700          # Set read, write, execute permission on user
    # S_IRWXU  00700
    # OCTAL!
    ecall
    mv s3, a0             # Save fd in s3 for later

next_byte:
    li a7, 63             # sys_read
    mv a0, s2             # File descriptor
    mv a1, sp             # Buffer
    li a2, 1              # Size of what we want to read (set for all subsequent syscalls)
    ecall

    # If the file ended (0 bytes read) terminate
    beqz a0, terminate

    # Check if it's a comment
    lb a0, (sp)
    li t0, 0x23
    beq a0, t0, loop             # a0 eq to '#'
    li t0, 0x3B
    beq a0, t0, loop             # a0 eq to ';'
    j not_comment
    loop:
        mv a0, s2             # File descriptor
        ecall                 # sys_read

        # If the file ended (0 bytes read) terminate
        beqz a0, terminate
        # Check if read byte is the end of the comment (i.e. a newline character),
        # in that case we continue processing
        lb a0, (sp)
        li t0, 0xA
        beq a0, t0, next_byte      # a0 eq to \n
        li t0, 0xD
        beq a0, t0, next_byte      # a0 eq to \r
    j loop

not_comment:
    # Check if it's a hex character:
    # in the case it's not, ignores and reads next byte
    lb a0, (sp)

    # Is it between '0' and '9'?
    li t0, 48  # '0' character
    blt a0, t0, 1f
    li t0, 57  # '9' character
    bgt a0, t0, 1f
    addi a0, a0, -48
    j hex_read
1:
    # Is it between 'A' and 'F'?
    li t0, 65  # 'A' character
    blt a0, t0, 1f
    li t0, 70  # 'F' character
    bgt a0, t0, 1f
    addi a0, a0, -55
    j hex_read
1:
    # Is it between 'a' and 'f'?
    li t0, 97  # 'a' character
    blt a0, t0, next_byte           # Not hex, continue reading
    li t0, 102 # 'f' character
    bgt a0, t0, next_byte           # Not hex, continue reading
    addi a0, a0, -87
hex_read:
    # END check hex -- leaves the half byte in a0

    bnez s4, combine    # if toggle != 0 -> combine
    # Toggle == 0, we need to prepare for later
    mv s5, a0           # Load hold
    li s4, 1            # Set toggle
    j next_byte         # Read next byte

combine:
    # Combine half bytes
    slli a1, s5, 4      # Shift logical left 4 times
    add  a0, a0, a1     # Combine two half bytes
    # Leaves the full byte in a0

    # Values are combined, now we write in the file
    sb a0, 0(sp)          # Store prepared byte in buffer
    li a7, 64             # sys_write
    mv a0, s3             # file descriptor (stdout)
    mv a1, sp             # string address
    ecall

    # Update globals
    li s4, 0              # Clear toggle
    li s5, 0              # Clear hold

    # Read next byte
    j next_byte

terminate:
    # Terminate program with 0 return code
    li a7, 93             # sys_exit
    ecall
# PROGRAM END
