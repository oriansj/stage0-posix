## Copyright (C) 2021 Andrius Štikonas
## Copyright (C) 2021 Ekaitz Zarraga
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


# Register use:
# s2: input fd
# s3: output fd
# s4: toggle
# s5: hold
# s6: ip

# s7-11: return addresses
# Can be replaced with stack but for hex1 we have enough spare registers

.text
.global _start
_start:
    ld a0, 0(sp)         # Get number of the args
    ld a1, 8(sp)         # Get program name
    ld a2, 16(sp)        # Input file name

    # Initialize globals
    li s4, -1             # Toggle
    li s5, 0              # Hold
    li s6, 0              # Instruction Pointer

    # Open input file and store FD in s2
    li a7, 56             # sys_openat
    li a0, -100           # AT_FDCWD
    mv a1, a2             # input file
    li a2, 0              # read only
    ecall
    mv s2, a0             # Save fd in for later


    # Set default FD for output file to stdout
    li s3, 1

    # If we only have 2 arguments, don't use the third (it's not set)
    li t0, 2
    ld a0, 0(sp)              # Get number of the args
    blt a0, t0, Fail          # No input file provided 
    beq a0, t0, after_open    # No output file provided. Use stdout

    # Open output file and store the FD in s3
    li a7, 56                 # sys_openat
    li a0, -100               # AT_FDCWD
    ld a1, 24(sp)             # Output file (argument 3)
    li a2, 00001101
    # O_TRUNC   00001000
    # O_CREAT   00000100
    # O_WRONLY  00000001
    # OCTAL!
    li a3, 00700              # Set read, write, execute permission on user
    # S_IRWXU  00700
    # OCTAL!
    ecall
    mv s3, a0                 # Save fd in for later

after_open:
    jal s7, First_pass

    # Rewind input file
    li a7, 62                 # sys_lseek
    mv a0, s2                 # Input file descriptor
    mv a1, zero               # Set offset to zero
    mv a2, zero               # Set whence to zero
    ecall

    # Initialize globals
    li s4, -1                 # Toggle
    li s5, 0                  # Hold
    li s6, 0                  # Instruction Pointer

    jal s7, Second_pass
    
    j Done

First_pass:
    jal s9, Read_byte

    # Deal with EOF
    li a1, -4
    beq a0, a1, First_pass_done

    # Check for :
    lb a0, table
    li a1, 0x3a
    bne a0, a1, First_pass_0
    jal StoreLabel

First_pass_0:
    # Check for %
    li a1, 0x25
    beq a0, a1, First_pass_pointer

    # Deal with everything else
    jal s8,hex

    # Deal with EOF
    li a1, -4
    beq a0, a1, First_pass_done

    # deal with -1 values
    blt a0, zero, First_pass

    # Deal with toggle
    beqz s4, First_pass_1
    addi s6, s6, 1            # Increment IP

First_pass_1:
    not s4, s4                # Toggle = !Toggle
    j First_pass

First_pass_pointer:
    # Deal with Pointer to label
    jal s9, Read_byte         # Drop the char
    addi s6, s6, 4            # Increment IP
    j First_pass              # Loop again

First_pass_done:
    jr s7

Second_pass:
    jal s9, Read_byte

    # Deal with EOF
    li a1, -4
    beq a0, a1, Second_pass_done

    # Drop the label
    li a1, 0x3a
    bne a0, a1, Second_pass_0

    jal s9, Read_byte
    j Second_pass

Second_pass_0:
    li a1, 0x25
    bne a0, a1, Second_pass_1

    jal StorePointer
    j Second_pass

Second_pass_1:
    # Deal with everything else
    jal s8,hex           # Process our char

    # Deal with EOF
    li a1, -4
    beq a0, a1, Second_pass_done

    # deal with -1 values
    blt a0, zero, Second_pass

    # deal with toggle
    beqz s4, print

    # process first byte of pair
    mv s5, a0            # Move byte to hold
    mv s4, zero          # Flip the toggle
    j Second_pass

Second_pass_done:
    jr s7

hex:
    # Deal with EOF
    li a1, -4
    beq a0, a1, EOF

    # deal with line comments starting with #
    li a1, 0x23
    beq a0, a1, ascii_comment    # a0 eq to '#'

    # deal with line comments starting with ;
    li a1, 0x3b
    beq a0, a1, ascii_comment    # a0 eq to ';'

    # deal all ascii less than 0
    li a1, 0x30
    blt a0, a1, ascii_other

    # deal with 0-9
    li a1, 0x3a
    blt a0, a1, ascii_num

    # deal with all ascii less than A
    li a1, 0x41
    blt a0, a1, ascii_other

    # deal with A-F
    li a1, 0x47
    blt a0, a1, ascii_high

    # deal with all ascii less than a
    li a1, 0x61
    blt a0, a1, ascii_other

    # deal with a-f
    li a1, 0x67
    blt a0, a1, ascii_low

    # The rest that remains needs to be ignored
    j ascii_other

ascii_num:
    li a1, 0x30                   # '0' -> 0
    sub a0, a0, a1
    jr s8
ascii_low:
    li a1, 0x57                   # 'a' -> 0xA
    sub a0, a0, a1
    jr s8
ascii_high:
    li a1, 0x37                   # 'A' -> 0xA
    sub a0, a0, a1
    jr s8
ascii_other:
    li a0, -1
    jr s8
ascii_comment:
    jal s9, Read_byte
    li a1, 0xd
    beq a0, a1, ascii_comment_cr
    li a1, 0xa
    bne a0, a1, ascii_comment
ascii_comment_cr:
    li a0, -1
    jr s8
EOF:
    jr s8

Read_byte:
    li a7, 63                 # sys_read
    mv a0, s2                 # File descriptor
    la a1, table              # Buffer
    li a2, 1                  # Size of what we want to read
    ecall

    beqz a0, Read_byte_1
    lbu a0, table
    jr s9

Read_byte_1:
    li a0, -4                 # Put EOF in a0
    jr s9

Get_table_target:
    jal s9, Read_byte         # Get single char label
    slli a0, a0, 3            # Each label in table takes 8 bytes to store
    la t0, table
    add a0, a0, t0            # Calculate offset
    jr s10

StoreLabel:
    jal s10, Get_table_target
    sd s6, (a0)
    ret

StorePointer:
    addi s6, s6, 4            # Increment IP
    jal s10, Get_table_target # Get address of pointer
    ld t0, (a0)
    mv a0, t0                 # Get pointer
    sub a0, a0, s6            # target - ip

    la t0, table
    sd a0, (t0)               # put value in output
    li a2, 4                  # set the size of chars we want
    jal s11, print_chars
    ret

print:
    # update the sum and store in output
    slli s5, s5, 4
    add a0, a0, s5
    la t0, table
    sb a0, (t0)

    not s4, s4                # Flip the toggle

    li a2, 1                  # length of the string
    jal s11, print_chars

    addi s6, s6, 1            # Increment IP
    j Second_pass

print_chars:
    li a7, 64                 # sys_write
    mv a0, s3                 # file descriptor (stdout)
    la a1, table              # string address
    ecall

    jr s11

Done:
    # Terminate program with 0 return code
    li a7, 93                 # sys_exit
    li a0, 0                  # Return code 0
    ecall
Fail:
    # Terminate program with 1 return code
    li a7, 93                 # sys_exit
    li a0, 1                  # Return code 1
    ecall
# PROGRAM END

.data
.align 4

table:
    .skip 1
