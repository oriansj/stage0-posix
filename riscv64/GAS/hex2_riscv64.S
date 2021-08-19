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
# s1: jump table
# s2: input fd
# s3: output fd
# s4: toggle
# s5: hold
# s6: ip
# s7: tempword
# s8: shiftregister
# s9: malloc pointer
# s10: updates

# Struct format: (size 24)
# next => 0                      # Next element in linked list
# target => 8                    # Target (ip)
# name => 16                     # Label name

.text
.global _start
_start:
    ld a2, 16(sp)                # Input file name

    # Initialize globals
    li s4, -1                    # Toggle
    li s5, 0                     # Hold
    li s6, 0x600000              # Instruction Pointer

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
    # Prepare heap memory
    li a7, 214                   # sys_brk
    mv a0, zero                  # Get current brk
    ecall                        # syscall
    mv s9, a0                    # Set our malloc pointer

    li a1, 0x100000
    add a0, a0, a1               # Request the 1 MiB
    li a7, 214                   # sys_brk
    ecall                        # syscall

    jal ClearScratch             # Zero scratch
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
    li s6, 0x600000              # Instruction Pointer
    li s7, 0                     # tempword
    li s8, 0                     # Shift register

    jal Second_pass              # Now do the second pass

    # Terminate program with 0 return code
    li a7, 93                    # sys_exit
    li a0, 0                     # Return code 0
    ecall                        # exit(0)

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
    beq a0, t1, StoreLabel       # Store this label

    # Check for '.'
    li t1, 0x2e
    beq a0, t1, First_pass_UpdateWord

    # Check for %
    li t1, 0x25
    beq a0, t1, First_pass_pointer

    # Check for &
    li t1, 0x26
    beq a0, t1, First_pass_pointer

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

    # Check for <
    li t1, 0x3c
    li a1, -1                    # write = false
    beq a0, t1, PadToAlign

    li a1, -1                    # write = false
    li a2, -1                    # update = false
    jal DoByte                   # Deal with everything else

    li t1, -4                    # Deal with EOF
    beq a0, t1, First_pass_done

    j First_pass_loop            # Keep looping

Throwaway_token:
    la a1, scratch               # Using scratch
    jal consume_token            # Read token
    jal ClearScratch             # Throw away token
    j First_pass_loop            # Loop again

First_pass_pointer:
    addi s6, s6, 4               # Update ip
    # Deal with Pointer to label
    la a1, scratch               # Using scratch
    jal consume_token            # Read token
    jal ClearScratch             # Throw away token
    li t1, 0x3e                  # Check for '>'
    bne a0, t1, First_pass_loop  # Loop again

    # Deal with %label>label case
    la a1, scratch               # Using scratch
    jal consume_token            # Read token
    jal ClearScratch             # Throw away token
    j First_pass_loop            # Loop again

First_pass_UpdateWord:
    mv s10, zero                 # updates = 0
    mv s7, zero                  # tempword = 0
    li a5, 4                     # a5 = 4
First_pass_UpdateWord_loop:
    jal Read_byte                # Read another byte into a0

    li a1, -1                    # write = false
    li a2, 0                     # update = true
    jal DoByte                   # Process byte
    blt s10, a5, First_pass_UpdateWord_loop # loop 4 times

    addi s6, s6, -4              # ip = ip - 4

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

    la a1, scratch               # Using scratch
    jal consume_token            # Read the label
    jal ClearScratch             # Throw away token

    j Second_pass_loop           # Continue looping

Second_pass_0:
    # Check for '.'
    li t1, 0x2e
    beq a0, t1, Second_pass_UpdateWord

    # Check for %
    li t1, 0x25
    beq a0, t1, StorePointer

    # Check for &
    li t1, 0x26
    beq a0, t1, StorePointer

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

    # Check for <
    li t1, 0x3c
    mv a1, zero                  # write = true
    beq a0, t1, PadToAlign

    # Deal with everything else
    mv a1, zero                  # write = true
    li a2, -1                    # update = false
    jal DoByte                   # Process our char

    # Deal with EOF
    li t1, -4
    beq a0, t1, Second_pass_done # We are done

    j Second_pass_loop           # continue looping

Second_pass_UpdateWord:
    mv s10, zero                 # updates = 0
    mv s7, zero                  # tempword = 0
    li a5, 4                     # a5 = 4

Second_pass_UpdateWord_loop:
    jal Read_byte                # Read another byte into a0

    li a1, -1                    # write = false
    mv a2, zero                  # update = true
    jal DoByte                   # Process byte
    blt s10, a5, Second_pass_UpdateWord_loop # loop 4 times

    mv a0, s7                    # tempword
    j UpdateShiftRegister_DOT    # UpdateShiftRegister('.', tempword)

UpdateShiftRegister:
    mv a2, a0                    # Store label prefix
    la a1, scratch               # Get scratch
    jal ClearScratch             # Clear scratch
    jal consume_token            # Read token
    jal GetTarget                # Get target
    ld a0, (a0)                  # Dereference pointer
    sub a0, a0, s6               # target - ip

    # Check for !
    li t1, 0x21
    beq a2, t1, UpdateShiftRegister_I

    # Check for @
    li t1, 0x40
    beq a2, t1, UpdateShiftRegister_B

    # Check for $
    li t1, 0x24
    beq a2, t1, UpdateShiftRegister_J

    # Check for ~
    li t1, 0x7e
    beq a2, t1, UpdateShiftRegister_U

    j Second_pass_loop           # Continue looping

UpdateShiftRegister_DOT:
    # . before instruction means it has to be added to the final word

    # swap = (((value >> 24) & 0xff) |
    #        ((value << 8) & 0xff0000) |
    #        ((value >> 8) & 0xff00) |
    #        ((value << 24) & 0xff000000))

    srli t2, a0, 24              # value >> 24
    li t1, 0xff                  # t1 = 0xff
    and t0, t1, t2               # (value >> 24) & 0xff

    slli t2, a0, 8               # value << 8
    li t1, 0xff0000              # t1 = 0xff0000
    and t2, t1, t2               # (value << 8) & 0xff0000
    or t0, t0, t2                # logical or with the previous expression

    srli t2, a0, 8               # value >> 8
    li t1, 0xff00                # t1 = 0xff00
    and t2, t1, t2               # (value >> 8) & 0xff00
    or t0, t0, t2                # logical or with the previous expression

    slli t2, a0, 24              # value << 24
    li t1, 0xff000000            # t1 = 0xff000000
    and t2, t1, t2               # (value << 24) & 0xff000000
    or t0, t0, t2                # swap

    xor s8, s8, t0               # shiftregister = shiftregister ^ swap

    addi s6, s6, -4              # ip = ip - 4
    j Second_pass_loop           # continue looping

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

StorePointer:
    addi s6, s6, 4               # Update ip
    mv a2, a0                    # Store label prefix

    la a1, scratch               # Get scratch
    jal ClearScratch             # clear scratch
    jal consume_token            # consume token
    mv a5, a0                    # save char
    jal GetTarget                # Get target
    ld a1, (a0)                  # Dereference pointer

    # If char is > then change relative base address to ip
    li t1, 0x3e
    beq t1, a5, StorePointer_1

    # Check for &
    li t1, 0x26
    beq a2, t1, StorePointer_0

    # Check for %
    li t1, 0x25
    bne a2, t1, Fail
    sub a1, a1, s6               # displacement = target - ip

StorePointer_0:
    # Output pointer
    li a5, 4                     # number of bytes
StorePointer_loop:
    srli t1, a1, 8               # value / 256
    slli a0, t1, 8
    sub a0, a1, a0               # byte = value % 256

    mv a1, t1                    # value = value / 256
    jal fputc                    # write value
    addi a5, a5, -1              # decrease number of bytes to write 
    bnez a5, StorePointer_loop   # continue looping

    j Second_pass_loop           # Continue looping

StorePointer_1:
    mv a2, a1                    # save target
    la a1, scratch               # Get scratch
    jal ClearScratch             # clear scratch
    jal consume_token            # consume token
    jal GetTarget                # Get target
    ld a1, (a0)                  # Dereference pointer
    sub a1, a2, a1               # displacement = target - ip

    j StorePointer_0             # Continue looping

Second_pass_done:
    ld ra, 0(sp)                 # restore ra
    addi sp, sp, 8               # Deallocate stack
    ret                          # return

# Pad with zeros to align to word size
#   bool write in a1
PadToAlign:
    li t1, 1                     # t1 = 1
    and a0, s6, t1               # ip & 0x1
    bne a0, t1, PadToAlign_1     # check if ip & 0x1 == 1
    add s6, s6, t1               # ip = ip + 1

    bnez a1, PadToAlign_1        # check if we have to write
    mv a0, zero                  # a0 = 0
    jal fputc                    # write 0

PadToAlign_1:
    li t1, 2                     # t1 = 2
    and a0, s6, t1               # ip & 0x2
    bne a0, t1, PadToAlign_2     # check if ip & 0x2 == 2
    add s6, s6, t1               # ip = ip + 2

    bnez a1, PadToAlign_2        # check if we have to write
    mv a0, zero                  # a0 = 0
    jal fputc                    # write 0
    mv a0, zero                  # a0 = 0
    jal fputc                    # write 0

PadToAlign_2:
    beqz a1, Second_pass_loop    # return to Second_pass
    j First_pass_loop            # return to First_pass

# Zero scratch area
ClearScratch:
    addi sp, sp, -24             # Allocate stack
    sd ra, 0(sp)                 # protect ra
    sd a0, 8(sp)                 # protect a0
    sd a1, 16(sp)                # protect a1

    la a0, scratch               # Find where our scratch area is

ClearScratch_loop:
    lb a1, (a0)                  # Read current byte: s[i]
    sb zero, (a0)                # Write zero: s[i] = 0
    addi a0, a0, 1               # Increment: i = i + 1
    bnez a1, ClearScratch_loop   # Keep looping

    ld ra, 0(sp)                 # restore ra
    ld a0, 8(sp)                 # restore a0
    ld a1, 16(sp)                # restore a1
    addi sp, sp, 24              # Deallocate stack
    ret                          # return

# Receives pointer in a1
# Writes our token and updates pointer in a1
consume_token:
    addi sp, sp, -8              # Allocate stack
    sd ra, 0(sp)                 # protect ra

consume_token_0:
    jal Read_byte                # Read byte into a0

    # Check for \t
    li t1, 0x09
    beq a0, t1, consume_token_done

    # Check for \n
    li t1, 0x0a
    beq a0, t1, consume_token_done

    # Check for ' '
    li t1, 0x20
    beq a0, t1, consume_token_done

    # Check for >
    li t1, 0x3e
    beq a0, t1, consume_token_done

    sb a0, (a1)                  # Store char
    addi a1, a1, 1               # Point to next spot
    j consume_token_0            # Continue looping

consume_token_done:
    sd zero, (a1)                # Pad with nulls
    addi a1, a1, 8               # Update the pointer

    ld ra, 0(sp)                 # restore ra
    addi sp, sp, 8               # Deallocate stack
    ret                          # return

# DoByte function
# Receives:
#   character in a0
#   bool write in a1
#   bool update in a2
# Does not return anything
DoByte:
    addi sp, sp, -16             # Allocate stack
    sd ra, 0(sp)                 # protect ra
    sd a6, 8(sp)                 # protect a6

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
    beqz a2, DoByte_2            # check if we have to update
DoByte_2b:
    mv s5, zero                  # hold = 0
    j DoByte_FlipToggle          # return

DoByte_NotToggle:
    mv s5, a6                    # hold = hex(c)

DoByte_FlipToggle:
    not s4, s4                   # Flip the toggle

DoByte_Done:
    ld ra, 0(sp)                 # restore ra
    ld a6, 8(sp)                 # restore a6
    addi sp, sp, 16              # Deallocate stack
    ret                          # return

DoByte_2:
    slli t1, s5, 4               # hold * 16
    add s5, t1, a6               # hold = hold * 16 + hex(c)
    slli t1, s7, 8               # tempword << 8
    xor s7, t1, s5               # tempword = (tempword << 8) ^ hold
    addi s10, s10, 1             # updates = updates + 1
    j DoByte_2b

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
    sd a1, 0(sp)                 # protect a1
    sd a2, 8(sp)                 # protect a1

    li a7, 63                    # sys_read
    mv a0, s2                    # File descriptor
    la a1, io                    # Buffer
    li a2, 1                     # Size of what we want to read
    ecall                        # syscall

    beqz a0, Read_byte_1         # Deal with EOF
    lbu a0, (a1)                 # Dereference pointer

    j Read_byte_done             # return

Read_byte_1:
    li a0, -4                    # Put EOF in a0
Read_byte_done:
    ld a1, 0(sp)                 # restore a1
    ld a2, 8(sp)                 # restore a2
    addi sp, sp, 16              # Deallocate stack
    ret                          # return

# Find a label matching pointer in scratch
# Returns a pointer in a0
GetTarget:
    addi sp, sp, -8              # Allocate stack
    sd ra, 0(sp)                 # protect ra

    mv t0, s1                    # grab jump_table

GetTarget_loop_0:
    # Compare the strings
    la t1, scratch               # reset scratch
    ld t2, 16(t0)                # I->name
GetTarget_loop:
    lbu t4, (t2)                 # I->name[i]
    lbu t3, (t1)                 # scratch[i]
    bne t3, t4, GetTarget_miss   # strings don't match

    # Look at the next char
    addi t1, t1, 1
    addi t2, t2, 1
    bnez t4, GetTarget_loop      # Loop until zero (end of string)
    j GetTarget_done             # We have a match

GetTarget_miss:
    ld t0, (t0)                  # I = I->next
    beqz t0, Fail                # Abort, no match found

    j GetTarget_loop_0           # Try another label

GetTarget_done:
    addi a0, t0, 8               # Get target address

    ld ra, 0(sp)                 # restore ra
    addi sp, sp, 8               # Deallocate stack
    ret                          # return

StoreLabel:
    addi sp, sp, -8              # Allocate stack
    sd ra, 0(sp)                 # protect ra

    mv a0, s9                    # struct entry
    addi s9, s9, 24              # calloc
    sd s6, 8(a0)                 # entry->target = ip
    sd s1, (a0)                  # entry->next = jump_table
    mv s1, a0                    # jump_table = entry
    sd s9, 16(a0)                # entry->name = token
    mv a1, s9                    # Write after struct
    jal consume_token            # Collect string
    mv s9, a1                    # update HEAP

    ld ra, 0(sp)                 # restore ra
    addi sp, sp, 8               # Deallocate stack
    j First_pass_loop            # return

# fputc function
# Receives CHAR in a0
# Writes and returns number of bytes written in a0
fputc:
    addi sp, sp, -24             # Allocate stack
    sd ra, 0(sp)                 # protect ra
    sd a1, 8(sp)                 # protect a1
    sd a2, 16(sp)                # protect a2

    la a1, io                    # Get buffer
    sb a0, (a1)                  # Store char

    li a7, 64                    # sys_write
    mv a0, s3                    # file descriptor (stdout)
    mv a1, a1                    # string address
    li a2, 1                     # length of the string
    ecall                        # syscall

    ld ra, 0(sp)                 # restore ra
    ld a1, 8(sp)                 # restore a1
    ld a2, 16(sp)                # restore a2
    addi sp, sp, 24              # Deallocate stack
    ret                          # return


Fail:
    # Terminate program with 1 return code
    li a7, 93                    # sys_exit
    li a0, 1                     # Return code 1
    ecall                        # exit(1)
# PROGRAM END

.data
.align 4

io:
    .quad 0
scratch:
    .byte 0
