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


# Register use:
# s2: input fd
# s3: output fd
# s4: toggle
# s5: hold
# s6: ip
# s7: tempword
# s8: shiftregister

.text
.global _start
_start:
    ld a2, 16(sp)                # Input file name

    # Initialize globals
    li s4, -1                    # Toggle
    li s5, 0                     # Hold
    li s6, 0                     # Instruction Pointer

    # Open input file and store FD in s2
    li a7, 56                    # sys_openat
    li a0, -100                  # AT_FDCWD
    mv a1, a2                    # input file
    li a2, 0                     # read only
    ecall                        # syscall
    bltz a0, Fail                # Error opening file
    mv s2, a0                    # Save fd in for later

    # Set default FD for output file to stdout
    li s3, 1

    # If we only have 2 arguments, don't use the third (it's not set)
    li t0, 2
    ld a0, 0(sp)                 # Get number of the args
    blt a0, t0, Fail             # No input file provided
    beq a0, t0, after_open       # No output file provided. Use stdout

    # Open output file and store the FD in s3
    li a7, 56                    # sys_openat
    li a0, -100                  # AT_FDCWD
    ld a1, 24(sp)                # Output file (argument 3)
    li a2, 00001101              # decimal 577
    # O_TRUNC   00001000
    # O_CREAT   00000100
    # O_WRONLY  00000001
    # OCTAL!
    li a3, 00700                 # Set read, write, execute permission on user
    # S_IRWXU  00700
    # OCTAL!
    ecall                        # syscall
    mv s3, a0                    # Save fd in for later

after_open:
    jal First_pass               # First pass

    # Rewind input file
    li a7, 62                    # sys_lseek
    mv a0, s2                    # Input file descriptor
    mv a1, zero                  # Set offset to zero
    mv a2, zero                  # Set whence to zero
    ecall                        # syscall

    # Initialize globals
    li s4, -1                    # Toggle
    li s5, 0                     # Hold
    li s6, 0                     # Instruction Pointer
    li s7, 0                     # tempword
    li s8, 0                     # Shift register

    jal Second_pass              # Now do the second pass

    j Done                       # We are done

# First pass loop to determine addresses of labels
First_pass:
    addi sp, sp, -8              # Allocate stack
    sd ra, 0(sp)                 # protect ra

First_pass_loop:
    jal Read_byte                # Get another byte

    # Deal with EOF
    li t1, -4
    beq a0, t1, First_pass_done

    # Check for :
    li t1, 0x3a
    bne a0, t1, First_pass_0
    jal StoreLabel               # Store this label

First_pass_0:
    # Check for !
    li t1, 0x21
    beq a0, t1, Throwaway_token

    # Check for @
    li t1, 0x40
    beq a0, t1, Throwaway_token

    # Check for $
    li t1, 0x24
    beq a0, t1, Throwaway_token

    # Check for ~
    li t1, 0x7e
    beq a0, t1, Throwaway_token

    li a1, -1                    # write = false
    jal DoByte                   # Deal with everything else

    li t1, -4                    # Deal with EOF
    beq a0, t1, First_pass_done

    j First_pass_loop            # Keep looping

Throwaway_token:
    # Deal with Pointer to label
    jal Read_byte                # Drop the char
    j First_pass_loop            # Loop again

First_pass_done:
    ld ra, 0(sp)                 # restore ra
    addi sp, sp, 8               # deallocate stack
    ret                          # return

Second_pass:
    addi sp, sp, -8              # Allocate stack
    sd ra, 0(sp)                 # protect ra

Second_pass_loop:
    jal Read_byte                # Read another byte

    # Deal with EOF
    li t1, -4
    beq a0, t1, Second_pass_done

    # Drop the label
    li t1, 0x3a
    bne a0, t1, Second_pass_0

    jal Read_byte                # Read the label
    j Second_pass_loop           # Continue looping

Second_pass_0:
    # Check for !
    li t1, 0x21
    beq a0, t1, UpdateShiftRegister

    # Check for @
    li t1, 0x40
    beq a0, t1, UpdateShiftRegister

    # Check for $
    li t1, 0x24
    beq a0, t1, UpdateShiftRegister

    # Check for ~
    li t1, 0x7e
    beq a0, t1, UpdateShiftRegister

    # Deal with everything else
    mv a1, zero                  # write = true
    jal DoByte                   # Process our char

    # Deal with EOF
    li t1, -4
    beq a0, t1, Second_pass_done # We are done

    j Second_pass_loop           # continue looping

UpdateShiftRegister:
    mv a1, a0                    # Store label prefix
    jal Get_table_target         # Get target
    ld a0, (a0)                  # Dereference pointer
    sub a0, a0, s6               # target - ip

    # Check for !
    li t1, 0x21
    beq a1, t1, UpdateShiftRegister_I

    # Check for @
    li t1, 0x40
    beq a1, t1, UpdateShiftRegister_B

    # Check for $
    li t1, 0x24
    beq a1, t1, UpdateShiftRegister_J

    # Check for ~
    li t1, 0x7e
    beq a1, t1, UpdateShiftRegister_U

    j Second_pass_loop           # Continue looping

UpdateShiftRegister_I:
    # Corresponds to RISC-V I format
    addi a0, a0, 4               # add 4 due to this being 2nd part of AUIPC combo

    li t1, 0xfff
    and t1, a0, t1               # (value & 0xfff)
    slli s7, t1, 20              # tempword = (value & 0xfff) << 20
    xor s8, s8, s7               # shiftregister = shiftregister ^ tempword

    j Second_pass_loop           # Continue looping

UpdateShiftRegister_B:
    # Corresponds to RISC-V B format

    # tempword = ((value & 0x1e) << 7)            ; imm[4:1]
    #          | ((value & 0x7e0) << (31 - 11))   ; imm[10:5]
    #          | ((value & 0x800) >> 4)           ; imm[11]
    #          | ((value & 0x1000) << (31 - 12))  ; imm[12]

    li t1, 0x1e
    and t1, a0, t1               # value & 0x1e
    slli t0, t1, 7               # tempword = (value & 0x1e) << 7

    li t1, 0x7e0
    and t1, a0, t1               # value & 0x7e0
    slli t1, t1, 20              # (value & 0x7e0) << (31 - 11)
    or t0, t0, t1                # logical or with the previous expression

    li t1, 0x800
    and t1, a0, t1               # value & 0x800
    srli t1, t1, 4               # (value & 0x800) >> 4
    or t0, t0, t1                # logical or with the previous expression

    li t1, 0x1000
    and t1, a0, t1               # value & 0x1000
    slli t1, t1, 19              # (value & 0x1000) << (31 - 12)
    or s7, t0, t1                # tempword

    xor s8, s8, s7               # shiftregister = shiftregister ^ tempword

    j Second_pass_loop           # Continue looping

UpdateShiftRegister_J:
    # Corresponds to RISC-V J format

    # tempword = ((value & 0x7fe) << (30 - 10))    ; imm[10:1]
    #          | ((value & 0x800) << (20 - 11))    ; imm[11]
    #          | ((value & 0xff000))               ; imm[19:12]
    #          | ((value & 0x100000) << (31 - 20)) ; imm[20]

    li t1, 0x7fe
    and t1, a0, t1               # value & 0x7fe
    slli t0, t1, 20              # tempword = (value & 0x7fe) << 20

    li t1, 0x800
    and t1, a0, t1               # value & 0x800
    slli t1, t1, 9               # (value & 0x800) << (20 - 11)
    or t0, t0, t1                # logical or with the previous expression

    li t1, 0xff000
    and t1, a0, t1               # value & 0xff000
    or t0, t0, t1                # logical or with the previous expression

    li t1, 0x100000
    and t1, a0, t1               # value & 0x100000
    slli t1, t1, 11              # (value & 0x100000) << (31 - 20)
    or s7, t0, t1                # tempword

    xor s8, s8, s7               # shiftregister = shiftregister ^ tempword

    j Second_pass_loop           # Continue looping

UpdateShiftRegister_U:
    # Corresponds to RISC-V U format
    # if value is 0x800 or more we have to add 11-th bit (0x1000) to compensate for signed extension

    li t0, 0x800
    li t1, 0xfff
    li t2, 0xfffff000
    and t1, a0, t1               # value & 0xfff
    and s7, a0, t2               # value & 0xfffff000
    blt t1, t0, UpdateShiftRegister_U_small

    # Deal with sign extension: add 0x1000
    li t0, 0x1000
    add s7, t0, s7               # (value & 0xfffff000) + 0x1000

UpdateShiftRegister_U_small:
    xor s8, s8, s7               # shiftregister = shiftregister ^ tempword

    j Second_pass_loop           # Continue looping

Second_pass_done:
    ld ra, 0(sp)                 # restore ra
    addi sp, sp, 8               # Deallocate stack
    ret                          # return


# DoByte function
# Receives:
#   character in a0
#   bool write in a1
# Does not return anything
DoByte:
    addi sp, sp, -8              # Allocate stack
    sd ra, 0(sp)                 # protect ra

    jal hex                      # Process hex, store it in a6

    bltz a6, DoByte_Done         # Deal with EOF and unrecognized characters

    bnez s4, DoByte_NotToggle    # Check if toggle is set

    # toggle = true
    bnez a1, DoByte_1            # check if we have to write

    # write = true
    # We calculate (hold * 16) + hex(c) ^ sr_nextb()
    # First, calculate new shiftregister
    li t0, 0xff
    and t0, s8, t0               # sr_nextb = shiftregister & 0xff
    srli s8, s8, 8               # shiftregister >> 8

    xor t0, t0, a6               # hex(c) ^ sr_nextb
    slli t1, s5, 4               # hold * 16
    add a0, t0, t1               # (hold * 16) + hex(c) ^ sr_nextb()
    jal fputc                    # print it
    beqz a0, Fail                # Fail if nothing was written

DoByte_1:
    addi s6, s6, 1               # Increment IP
    mv s5, zero                  # hold = 0
    j DoByte_FlipToggle          # return

DoByte_NotToggle:
    mv s5, a6                    # hold = hex(c)

DoByte_FlipToggle:
    not s4, s4                   # Flip the toggle

DoByte_Done:
    ld ra, 0(sp)                 # restore ra
    addi sp, sp, 8               # Deallocate stack
    ret                          # return

# Convert ASCII hex characters into binary representation, e.g. 'a' -> 0xA
# Receives:
#   character in a0
# Returns:
#   a6 with character's hex value.
hex:
    addi sp, sp, -16             # Allocate stack
    sd ra, 0(sp)                 # protect ra
    sd a1, 8(sp)                 # protect a1

    # Deal with EOF
    li t1, -4
    beq a0, t1, hex_return

    # deal with line comments starting with #
    li t1, 0x23
    beq a0, t1, ascii_comment    # a0 eq to '#'

    # deal with line comments starting with ;
    li t1, 0x3b
    beq a0, t1, ascii_comment    # a0 eq to ';'

    # deal all ascii less than 0
    li t1, 0x30
    blt a0, t1, ascii_other

    # deal with 0-9
    li t1, 0x3a
    blt a0, t1, ascii_num

    # deal with all ascii less than A
    li t1, 0x41
    blt a0, t1, ascii_other

    # deal with A-F
    li t1, 0x47
    blt a0, t1, ascii_high

    # deal with all ascii less than a
    li t1, 0x61
    blt a0, t1, ascii_other

    # deal with a-f
    li t1, 0x67
    blt a0, t1, ascii_low

    # The rest that remains needs to be ignored
    j ascii_other

ascii_num:
    li t1, 0x30                  # '0' -> 0
    sub a6, a0, t1
    j hex_return                 # return
ascii_low:
    li t1, 0x57                  # 'a' -> 0xA
    sub a6, a0, t1
    j hex_return                 # return
ascii_high:
    li t1, 0x37                  # 'A' -> 0xA
    sub a6, a0, t1
    j hex_return                 # return
ascii_other:
    li a6, -1                    # Return -1
    j hex_return                 # return
ascii_comment:                   # Read the comment until newline
    jal Read_byte
    li t1, 0xd                   # CR
    beq a0, t1, ascii_comment_cr
    li t1, 0xa                   # LF
    bne a0, t1, ascii_comment    # Keep reading comment
ascii_comment_cr:
    li a6, -1                    # Return -1
hex_return:
    ld ra, 0(sp)                 # restore ra
    ld a1, 8(sp)                 # restore a1
    addi sp, sp, 16              # Deallocate stack
    ret                          # return

# Read byte into a0
Read_byte:
    addi sp, sp, -16             # Allocate stack
    sd a1, 8(sp)                 # protect a1

    li a7, 63                    # sys_read
    mv a0, s2                    # File descriptor
    mv a1, sp                    # Get stack address for buffer
    nop                          # no operation
    li a2, 1                     # Size of what we want to read
    ecall                        # syscall

    beqz a0, Read_byte_1         # Deal with EOF
    lb a0, (a1)                  # Dereference pointer

    j Read_byte_done             # return

Read_byte_1:
    li a0, -4                    # Put EOF in a0
Read_byte_done:
    ld a1, 8(sp)                 # restore a1
    addi sp, sp, 16              # Deallocate stack
    ret                          # return

# Reads a byte and calculates table address
# Returns a pointer in a0
Get_table_target:
    addi sp, sp, -8              # Allocate stack
    sd ra, 0(sp)                 # protect ra

    jal Read_byte                # Get single char label
    slli a0, a0, 3               # Each label in table takes 8 bytes to store
    la t0, table
    add a0, a0, t0               # Calculate offset

    ld ra, 0(sp)                 # restore ra
    addi sp, sp, 8               # Deallocate stack
    ret                          # return

StoreLabel:
    addi sp, sp, -8              # Allocate stack
    sd ra, 0(sp)                 # protect ra

    jal Get_table_target
    sd s6, (a0)                  # Store ip into table target

    ld ra, 0(sp)                 # restore ra
    addi sp, sp, 8               # Deallocate stack
    ret                          # return

# fputc function
# Receives CHAR in a0
# Writes and returns number of bytes written in a0
fputc:
    addi sp, sp, -32             # allocate stack
    sd a0, 0(sp)                 # protect a0
    sd ra, 8(sp)                 # protect ra
    sd a1, 16(sp)                # protect a1
    sd a2, 24(sp)                # protect a2

    li a7, 64                    # sys_write
    mv a0, s3                    # write to output
    mv a1, sp                    # Get stack address
    li a2, 1                     # write 1 character
    ecall                        # syscall

    ld ra, 8(sp)                 # restore ra
    ld a1, 16(sp)                # restore a1
    ld a2, 24(sp)                # restore a2
    addi sp, sp, 32              # deallocate stack
    ret                          # return

Done:
    # Terminate program with 0 return code
    li a7, 93                    # sys_exit
    li a0, 0                     # Return code 0
    ecall                        # exit(0)
Fail:
    # Terminate program with 1 return code
    li a7, 93                    # sys_exit
    li a0, 1                     # Return code 1
    ecall                        # exit(1)
# PROGRAM END

.data
.align 4

table:
    .skip 1
