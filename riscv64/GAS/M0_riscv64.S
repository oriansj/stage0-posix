## Copyright (C) 2017 Jeremiah Orians
## Copyright (C) 2021 Andrius Štikonas
## Copyright (C) 2021 Gabriel Wicki
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

# Building:
# riscv64-unknown-linux-gnu-as M0_riscv64.S -o M0.o
# riscv64-unknown-linux-gnu-ld --no-relax M0.o -o M0

# Register use:
# s1: malloc pointer
# s2: input fd
# s3: output fd
# s4: struct HEAD
# s5: protected char
# s6: scratch

# Struct format: (size 32)
# NEXT => 0                           # Next element in linked list
# TYPE => 8                           # Token type
# TEXT => 16
# EXPRESSION => 24

# Types
# None => 0
# MACRO => 1
# STRING => 2

.text
.global _start

_start:
    li s4, 0                          # Initialize register
    ld a2, 16(sp)                     # Input file name

    # Open input file and store FD in s2
    li a7, 56                         # sys_openat
    li a0, -100                       # AT_FDCWD
    mv a1, a2                         # input file
    li a2, 0                          # read only
    ecall                             # syscall
    bltz a0, Fail                     # Error opening file
    mv s2, a0                         # Save fd in for later

    # Set default FD for output file to stdout
    li s3, 1

    # If we only have 2 arguments, don't use the third (it's not set)
    li t0, 2
    ld a0, 0(sp)                      # Get number of the args
    blt a0, t0, Fail                  # No input file provided
    beq a0, t0, after_open            # No output file provided. Use stdout

    # Open output file and store the FD in s3
    li a7, 56                         # sys_openat
    li a0, -100                       # AT_FDCWD
    ld a1, 24(sp)                     # Output file (argument 3)
    li a2, 00001101                   # decimal 577
    # O_TRUNC   00001000
    # O_CREAT   00000100
    # O_WRONLY  00000001
    # OCTAL!
    li a3, 0600                       # Set read and write permission on user
    ecall                             # syscall
    mv s3, a0                         # Save fd in for later

after_open:
    # Prepare heap memory
    li a7, 214                        # sys_brk
    mv a0, zero                       # Get current brk
    ecall                             # syscall
    mv s1, a0                         # Set our malloc pointer

    li a0, 512                        # Allocate scratch
    jal malloc                        # Get S pointer
    mv s6, a0                         # Save scratch pointer

    jal Tokenize_Line                 # Get all lines
    mv a0, s4                         # Prepare for Reverse_List
    jal Reverse_List                  # Correct order
    mv s4, a0                         # Update HEAD
    jal Identify_Macros               # Find the DEFINEs
    jal Line_Macro                    # Apply the DEFINEs
    jal Process_String                # Handle strings
    jal Eval_Immediates               # Handle numbers
    jal Preserve_Other                # Collect the remaining
    jal Print_Hex                     # Output our results

    # Terminate program with 0 return code
    li a7, 93                         # sys_exit
    li a0, 0                          # Return code 0
    ecall                             # exit(0)

# Tokenize_Line Function
# Using input file s2 and Head s4
# Creates a linked list of structs
# Uses a1 for in_set strings, a2 for Int C and a3 for Struct Token* p
Tokenize_Line:
    addi sp, sp, -8                   # allocate stack
    sd ra, 0(sp)                      # protect ra

restart:
    jal fgetc                         # Read a char
    li t0, -4                         # EOF
    beq a0, t0, done                  # File is collected

    mv a2, a0                         # Protect C

    la a1, comments                   # Get pointer to "#;"
    jal In_Set                        # Check for comments
    li t0, 1                          # If comment
    beq a0, t0, Purge_LineComment     # try again

    mv a0, a2                         # Put C in place for check
    la a1, terminators                # Get pointer to "\n\t "
    jal In_Set                        # Check for terminators
    li t0, 1                          # If terminator
    beq a0, t0, restart               # try again

    li a0, 32                         # malloc struct P
    jal malloc                        # Get pointer to P
    mv a3, a0                         # Protect P
    sd s4, 0(a3)                      # P->NEXT = HEAD
    mv s4, a3                         # HEAD = P

    mv a0, a2                         # Put C in place for check
    la a1, string_char                # Get pointer to "\"'"
    jal In_Set                        # Check for string char
    li t0, 1                          # If string char
    beq a0, t0, Store_String          # Get string

    jal Store_Atom                    # Get whole token
    j restart

done:
    ld ra, 0(sp)                      # restore ra
    addi sp, sp, 8                    # deallocate stack
    ret                               # return


# In_Set function
# Receives char C in a0 and Char* in a1
# Returns 1 if true, zero if false in a0
In_Set:
    addi sp, sp, -8                   # allocate stack
    sd a1, 0(sp)                      # protect a1

In_Set_loop:
    lbu t0, (a1)                      # Read char
    beq a0, t0, In_Set_True           # Return true
    beqz t0, In_Set_False             # Return False if NULL
    addi a1, a1, 1                    # s = s + 1
    j In_Set_loop                     # Continue looping

In_Set_True:
    li a0, 1                          # Set True
    ld a1, 0(sp)                      # restore a1
    addi sp, sp, 8                    # deallocate stack
    ret                               # return

In_Set_False:
    mv a0, zero                       # Set False
    ld a1, 0(sp)                      # restore a1
    addi sp, sp, 8                    # deallocate stack
    ret                               # return


# Purge_LineComment function
# Reads chars until LF and jumps to restart
Purge_LineComment:
    jal fgetc                         # Get a char
    li t0, 10                         # While not LF
    bne a0, t0, Purge_LineComment     # Keep reading
    j restart


# Store_String Function
# Receives C in a2, HEAD in a3 and Input file in s2
# Uses a1 for terminator, a2 for C and a3 for string
Store_String:
    addi sp, sp, -24                  # allocate stack
    sd a1, 0(sp)                      # protect a1
    sd a2, 8(sp)                      # protect a2
    sd a3, 16(sp)                     # protect a3

    li a0, 2                          # Using TYPE STRING
    sd a0, 8(a3)                      # HEAD->TYPE = STRING
    mv a1, a2                         # Protect terminator
    mv a3, s6                         # Protect string pointer
Store_String_Loop:
    sb a2, 0(a3)                      # write byte
    jal fgetc                         # read next char
    mv a2, a0                         # Update C
    addi a3, a3, 1                    # STRING = STRING + 1
    bne a1, a2, Store_String_Loop     # Keep looping unless we hit terminator

    mv a0, s6                         # Prepare the string in scratch
    jal string_length                 # Calculate length
    addi a0, a0, 1                    # Add 1 for 0 terminator
    jal malloc                        # Allocate memory
    ld a3, 16(sp)                     # restore a3 (HEAD)
    sd a0, 16(a3)                     # HEAD->TEXT = STRING
    jal copy_string                   # Copy the string

    ld a1, 0(sp)                      # restore a1
    ld a2, 8(sp)                      # restore a2
    addi sp, sp, 24                   # deallocate stack
    j restart


# copy_string function
# Receives target in a0, and scratch s6 for source
# Uses a0, for target string T, a1 for C, a2 for source string S
# Returns nothing
copy_string:
    addi sp, sp, -24                  # allocate stack
    sd ra, 0(sp)                      # protect ra
    sd a1, 8(sp)                      # protect a1
    sd a2, 16(sp)                     # protect a2

    mv a2, s6                         # Get S

copy_string_loop:
    lbu a1, (a2)                      # S[0]
    beqz a1, copy_string_done         # Check if we are done

    sb a1, (a0)                       # Copy char
    addi a2, a2, 1                    # S = S + 1
    addi a0, a0, 1                    # T = T + 1
    j copy_string_loop                # Keep going

copy_string_done:
    jal ClearScratch                  # Clear scratch

    ld ra, 0(sp)                      # restore ra
    ld a1, 8(sp)                      # restore a1
    ld a2, 16(sp)                     # restore a2
    addi sp, sp, 24                   # deallocate stack
    ret


# Zero scratch area
ClearScratch:
    addi sp, sp, -24                  # allocate stack
    sd ra, 0(sp)                      # protect ra
    sd a0, 8(sp)                      # protect a0
    sd a1, 16(sp)                     # protect a1

    mv a0, s6                         # Prepare scratch

ClearScratch_loop:
    lb a1, (a0)                       # Read current byte: s[i]
    sb zero, (a0)                     # Write zero: s[i] = 0
    addi a0, a0, 1                    # Increment: i = i + 1
    bnez a1, ClearScratch_loop        # Keep looping

    ld ra, 0(sp)                      # restore ra
    ld a0, 8(sp)                      # restore a0
    ld a1, 16(sp)                     # restore a1
    addi sp, sp, 24                   # deallocate stack
    ret                               # return


# Store_Atom Function
# Receives C in a2, HEAD in a3 and Input file in s2
# Uses a1 for in_set strings, a2 for C and a3 for string
Store_Atom:
    addi sp, sp, -32                  # allocate stack
    sd ra, 0(sp)                      # protect ra
    sd a1, 8(sp)                      # protect a1
    sd a2, 16(sp)                     # protect a2
    sd a3, 24(sp)                     # protect a3

    la a1, terminators                # Get pointer to "\n\t "
    mv a3, s6                         # Protect string pointer

Store_Atom_loop:
    sb a2, 0(a3)                      # write byte
    jal fgetc                         # read next char
    mv a2, a0                         # Update C
    addi a3, a3, 1                    # STRING = STRING + 1
    jal In_Set                        # Check for terminators
    beqz a0, Store_Atom_loop          # Loop if not "\n\t "

    mv a0, s6                         # Prepare the string in scratch
    jal string_length                 # Calculate length
    addi a0, a0, 1                    # Add 1 for 0 terminator
    jal malloc                        # Allocate memory
    ld a3, 24(sp)                     # restore a3 (HEAD)
    sd a0, 16(a3)                     # HEAD->TEXT = STRING
    jal copy_string                   # Copy the string

    mv a0, a3                         # Return HEAD
    ld ra, 0(sp)                      # restore ra
    ld a1, 8(sp)                      # restore a1
    ld a2, 16(sp)                     # restore a2
    addi sp, sp, 32                   # deallocate stack
    ret                               # return


# Reverse_List function
# Receives list in a0
# Returns the list reversed in a0
Reverse_List:
    addi sp, sp, -16                  # allocate stack
    sd a1, 0(sp)                      # protect a1
    sd a2, 8(sp)                      # protect a2
    mv a1, a0                         # Set HEAD
    mv a0, zero                       # ROOT = NULL
Reverse_List_Loop:
    beqz a1, Reverse_List_Done        # Stop if HEAD == NULL

    ld a2, (a1)                       # NEXT = HEAD->NEXT
    sd a0, (a1)                       # HEAD->NEXT = ROOT
    mv a0, a1                         # ROOT = HEAD
    mv a1, a2                         # HEAD = NEXT
    j Reverse_List_Loop               # Continue looping

Reverse_List_Done:
    ld a1, 0(sp)                      # restore a1
    ld a2, 8(sp)                      # restore a2
    addi sp, sp, 16                   # deallocate stack
    ret                               # return


# Identify_Macros function
# Receives List in a0
# Updates the list in place; does not modify registers
# Uses a1 for DEFINE, a2 for I
Identify_Macros:
    addi sp, sp, -32                  # allocate stack
    sd ra, 0(sp)                      # protect ra
    sd a0, 8(sp)                      # protect a0
    sd a1, 16(sp)                     # protect a1
    sd a2, 24(sp)                     # protect a2

    la a1, DEFINE_str                 # Setup DEFINE string
    mv a2, a0                         # I = HEAD

Identify_Macros_Loop:
    ld a0, 16(a2)                     # I->TEXT
    jal match                         # IF "DEFINE" == I->TEXT
    bnez a0, Identify_Macros_Next     # Check if we got macro

    # Deal with MACRO
    li a0, 1                          # a0 = MACRO
    sd a0, 8(a2)                      # I->TYPE = MACRO

    ld a0, (a2)                       # I->NEXT
    ld a0, 16(a0)                     # I->NEXT->TEXT
    sd a0, 16(a2)                     # I->TEXT = I->NEXT->TEXT

    ld a0, (a2)                       # I->NEXT
    ld a0, (a0)                       # I->NEXT->NEXT
    ld a0, 16(a0)                     # I->NEXT->NEXT->TEXT
    sd a0, 24(a2)                     # I->EXPRESSION = I->NEXT->NEXT->TEXT

    ld a0, (a2)                       # I->NEXT
    ld a0, (a0)                       # I->NEXT->NEXT
    ld a0, (a0)                       # I->NEXT->NEXT->NEXT
    sd a0, (a2)                       # I->NEXT = I->NEXT->NEXT->NEXT

Identify_Macros_Next:
    ld a2, (a2)                       # I = I->NEXT
    bnez a2, Identify_Macros_Loop     # Check if we are done

    ld ra, 0(sp)                      # restore ra
    ld a0, 8(sp)                      # restore a0
    ld a1, 16(sp)                     # restore a1
    ld a2, 24(sp)                     # restore a2
    addi sp, sp, 32                   # deallocate stack
    ret                               # return


# match function
# Receives CHAR* in a0 and CHAR* in a1
# Returns 0 (TRUE) or 1 (FALSE) in a0
match:
    addi sp, sp, -24                  # allocate stack
    sd a1, 0(sp)                      # protect a1
    sd a2, 8(sp)                      # protect a2
    sd a3, 16(sp)                     # protect a3

    mv a2, a0                         # S1 in place
    mv a3, a1                         # S2 in place

match_Loop:
    lbu a0, (a2)                      # S1[i]
    lbu a1, (a3)                      # S2[i]
    bne a0, a1, match_False           # Check if they match

    addi a2, a2, 1                    # S1 = S1 + 1
    addi a3, a3, 1                    # S2 = S2 + 1
    beqz a0, match_Done               # Match if we reached end of string
    j match_Loop                      # Otherwise keep looping

match_False:
    li a0, 1                          # Return false
match_Done:
    ld a1, 0(sp)                      # restore a1
    ld a2, 8(sp)                      # restore a2
    ld a3, 16(sp)                     # restore a3
    addi sp, sp, 24                   # deallocate stack
    ret                               # return


# Line_Macro function
# Receives List in a0
# Updates the list in place; does not modify registers
# Uses a0 for I, a1 for I->TEXT, a2 for I->EXPRESSION
Line_Macro:
    addi sp, sp, -32                  # allocate stack
    sd ra, 0(sp)                      # protect ra
    sd a0, 8(sp)                      # protect a0
    sd a1, 16(sp)                     # protect a1
    sd a2, 24(sp)                     # protect a2

Line_Macro_Loop:
    ld a1, 8(a0)                      # I->TYPE
    li t0, 1                          # t0 = MACRO
    bne a1, t0, Line_Macro_Next       # Move on unless I->TYPE == MACRO

    # Apply macro
    ld a1, 16(a0)                     # I->TEXT
    ld a2, 24(a0)                     # I->EXPRESSION
    ld a0, (a0)                       # I->NEXT
    jal Set_Expression                # Apply it
    j Line_Macro_Loop                 # Move on to next

Line_Macro_Next:
    ld a0, (a0)                       # I->NEXT
    bnez a0, Line_Macro_Loop          # Check if we are done

    ld ra, 0(sp)                      # restore ra
    ld a0, 8(sp)                      # restore a0
    ld a1, 16(sp)                     # restore a1
    ld a2, 24(sp)                     # restore a2
    addi sp, sp, 32                   # deallocate stack
    ret                               # return

# Set_Expression function
# Receives List in a0, CHAR* in a1 and CHAR* in a2
# Updates the list in place; does not modify registers
# Uses a1 for C, a2 for EXP and a3 for I
Set_Expression:
    addi sp, sp, -40                  # allocate stack
    sd ra, 0(sp)                      # protect ra
    sd a0, 8(sp)                      # protect a0
    sd a1, 16(sp)                     # protect a1
    sd a2, 24(sp)                     # protect a2
    sd a3, 32(sp)                     # protect a3

    mv a3, a0                         # Set I
Set_Expression_Loop:
    ld a0, 8(a3)                      # I->TYPE
    li t0, 1                          # t0 = MACRO
    beq a0, t0, Set_Expression_Next   # If MACRO == I->Type then ignore and move on

    ld a0, 16(a3)                     # I->TEXT
    jal match                         # Check for match
    bnez a0, Set_Expression_Next      # Check next if does not match

    # Non-macro match
    sd a2, 24(a3)                     # I->EXPRESSION = EXP

Set_Expression_Next:
    ld a3, (a3)                       # I = I->NEXT
    bnez a3, Set_Expression_Loop      # Check if we are done

    ld ra, 0(sp)                      # restore ra
    ld a0, 8(sp)                      # restore a0
    ld a1, 16(sp)                     # restore a1
    ld a2, 24(sp)                     # restore a2
    ld a3, 32(sp)                     # restore a3
    addi sp, sp, 40                   # deallocate stack
    ret                               # return

# Process_String function
# Receives List in a0
# Update the list in place; does not modify registers
# Uses a1 for I->TEXT, a2 for I and RDX for S
Process_String:
    addi sp, sp, -40                  # allocate stack
    sd ra, 0(sp)                      # protect ra
    sd a0, 8(sp)                      # protect a0
    sd a1, 16(sp)                     # protect a1
    sd a2, 24(sp)                     # protect a2
    sd a3, 32(sp)                     # protect a3

    mv a2, a0                         # I = HEAD

Process_String_loop:
    ld a0, 8(a2)                      # I->TYPE
    li t0, 2                          # t0 = STRING
    bne a0, t0, Process_String_Next   # Skip to next

    ld a1, 16(a2)                     # I->TEXT
    lbu a0, (a1)                      # I->TEXT[0]
    li t0, 39                         # t0 = \'
    bne a0, t0, Process_String_Raw    # Deal with '"'

    # Deal with \'
    addi a1, a1, 1                    # I->TEXT + 1
    sd a1, 24(a2)                     # I->EXPRESSION = I->TEXT + 1
    j Process_String_Next             # Move on to next

Process_String_Raw:
    mv a0, a1                         # I->TEXT
    jal string_length                 # Get length of I->TEXT
    srli a0, a0, 2                    # LENGTH = LENGTH >> 2
    addi a0, a0, 1                    # LENGTH = LENGTH + 1
    slli a0, a0, 3                    # LENGTH = LENGTH << 3
    jal malloc                        # Get string
    mv a3, a1                         # S = I->TEXT
    addi a3, a3, 1                    # S = S + 1
    sd a0, 24(a2)                     # I->EXPRESSION = hexify
    mv a1, a0                         # Put hexify buffer in a1

Process_String_Raw_Loop:
    lbu a0, (a3)                      # Read 1 character
    addi a3, a3, 1                    # S = S + 1
    mv s5, a0                         # Protect character
    jal hex8                          # write them all
    mv a0, s5                         # Restore character
    bnez a0, Process_String_Raw_Loop  # Keep looping

Process_String_Next:
    ld a2, (a2)                       # I = I->NEXT
    bnez a2, Process_String_loop      # Check if we are done

    ld ra, 0(sp)                      # restore ra
    ld a0, 8(sp)                      # restore a0
    ld a1, 16(sp)                     # restore a1
    ld a2, 24(sp)                     # restore a2
    ld a3, 32(sp)                     # restore a3
    addi sp, sp, 40                   # deallocate stack
    ret                               # return


# string_length function
# Receives CHAR* in a0
# Returns INT in a0
# Uses a0 for CH, a1 for S and a2 for INDEX
string_length:
    addi sp, sp, -16                  # allocate stack
    sd a1, 0(sp)                      # protect a1
    sd a2, 8(sp)                      # protect a2

    mv a1, a0                         # Set S
    mv a2, zero                       # INDEX = 0

string_length_loop:
    add t0, a1, a2                    # S + INDEX
    lbu a0, (t0)                      # S[INDEX]
    beqz a0, string_length_done       # Check if we are done

    addi a2, a2, 1                    # INDEX = INDEX + 1
    j string_length_loop              # Keep going

string_length_done:
    mv a0, a2                         # return INDEX
    ld a1, 0(sp)                      # restore a1
    ld a2, 8(sp)                      # restore a2
    addi sp, sp, 16                   # deallocate stack
    ret                               # return


# Eval_Immediates function
# Receives List in a0
# Updates the list in place; does not modify registers
# Uses a1 for I->TEXT[0], a2 for I->TEXT[1] and a3 for I
Eval_Immediates:
    addi sp, sp, -40                  # allocate stack
    sd ra, 0(sp)                      # protect ra
    sd a0, 8(sp)                      # protect a0
    sd a1, 16(sp)                     # protect a1
    sd a2, 24(sp)                     # protect a2
    sd a3, 32(sp)                     # protect a3

    mv a3, a0                         # I = HEAD

Eval_Immediates_Loop:
    # Check for MACRO
    ld a0, 8(a3)                      # I->TYPE
    li t0, 1                          # t0 = MACRO
    beq a0, t0, Eval_Immediates_Next  # Skip to next if I->TYPE == MACRO

    # Check for NULL EXPRESSION
    ld a0, 24(a3)                     # I->EXPRESSION
    bnez a0, Eval_Immediates_Next     # Skip to next if NULL == I->EXPRESSION

    # Check if number
    ld a0, 16(a3)                     # I->TEXT
    lbu a1, (a0)                      # I->TEXT[0]
    addi a0, a0, 1                    # I->TEXT + 1
    lbu a2, (a0)                      # I->TEXT[1]
    jal numerate_string               # Convert string to INT
    bnez a0, Eval_Immediates_value    # Has a value IF 0 != numerate_string(I->TEXT + 1)

    # Last chance for Immediate
    li t0, 48                         # If '0' = I->TEXT[1]
    bne a2, t0, Eval_Immediates_Next  # Skip to next

Eval_Immediates_value:
    jal express_number                # Convert value to hex string
    sd a0, 24(a3)                     # I->EXPRESSION = express_number(value, I-TEXT[0])

Eval_Immediates_Next:
    ld a3, (a3)                       # I = I->NEXT
    bnez a3, Eval_Immediates_Loop     # Check if we are done

    ld ra, 0(sp)                      # restore ra
    ld a0, 8(sp)                      # restore a0
    ld a1, 16(sp)                     # restore a1
    ld a2, 24(sp)                     # restore a2
    ld a3, 32(sp)                     # restore a3
    addi sp, sp, 40                   # deallocate stack
    ret                               # return


# numerate_string function
# Receives CHAR* in a0
# Returns value of CHAR* in a0
# Uses a0 for VALUE, a1 for S, a2 for CH and a3 for NEGATIVE?
numerate_string:
    addi sp, sp, -24                  # allocate stack
    sd a1, 0(sp)                      # protect a1
    sd a2, 8(sp)                      # protect a2
    sd a3, 16(sp)                     # protect a3

    mv a1, a0                         # put S in correct place
    mv a0, zero                       # Initialize to Zero
numerate_string_loop:
    addi t0, a1, 1                    # S + 1
    lbu a2, (t0)                      # S[1]
    li t0, 120                        # 'x'
    beq a2, t0, numerate_hex          # Deal with hex_input

    # Assume decimal input
    mv a3, zero                       # Assume no negation
    lbu a2, (a1)                      # S[0]
    li t0, 45                         # '-'
    bne a2, t0, numerate_decimal      # Skip negation

    li a3, 1                          # Set FLAG
    addi a1, a1, 1                    # S = S + 1

numerate_decimal:
    lbu a2, (a1)                      # S[i]
    beqz a2, numerate_decimal_done    # We are done if NULL == S[i]

    # a0 = a0 * 10 = (a0 << 3) + (a0 << 1)
    slli t0, a0, 3                    # a0 * 8
    slli t1, a0, 1                    # a0 * 2
    add a0, t0, t1                    # VALUE = VALUE * 10
    addi a2, a2, -48                  # CH = CH - '0'
    li t0, 9                          # t0 = 9
    blt t0, a2, numerate_string_fail  # Check for illegal CH > 9
    bltz a2, numerate_string_fail     # Check for illegal CH < 0
    add a0, a0, a2                    # VALUE = VALUE + CH
    addi a1, a1, 1                    # S = S + 1
    j numerate_decimal

numerate_decimal_done:
    li t0, 1                          # Check for negative FLAG
    bne a3, t0, numerate_string_done  # Nope

    sub a0, zero, a0                  # VALUE = -VALUE
    j numerate_string_done            # Done

numerate_hex:
    addi a1, a1, 2                    # S = S + 2
numerate_hex_loop:
    lbu a2, (a1)                      # S[i]
    beqz a2, numerate_string_done     # We are done if NULL == S[i]

    slli a0, a0, 4                    # VALUE = VALUE << 4
    addi a2, a2, -48                  # CH = CH - '0'
    li t0, 10                         # t0 = 10
    blt a2, t0, numerate_hex_digit    # Check if we are dealing with number or letter
    addi a2, a2, -7                   # Push A-F into range

numerate_hex_digit:
    li t0, 15                         # t0 = 15
    blt t0, a2, numerate_string_fail  # Check for CH > 'F'
    bltz a2, numerate_string_fail     # Check for CH < 0
    add a0, a0, a2                    # VALUE = VALUE + CH
    addi a1, a1, 1                    # S = S + 1
    j numerate_hex_loop               # Keep looping

numerate_string_fail:
    mv a0, zero                       # return ZERO

numerate_string_done:
    ld a1, 0(sp)                      # restore a1
    ld a2, 8(sp)                      # restore a2
    ld a3, 16(sp)                     # restore a3
    addi sp, sp, 24                   # deallocate stack
    ret                               # return


# express_number function
# Receives INT in a0 and CHAR in a1
# Allocates a string and expresses the value in appropriate RISC-V encoding
# Returns string in a0
# Uses a0 for VALUE, a1 for S and a2 for CH
express_number:
    addi sp, sp, -32                  # allocate stack
    sd ra, 0(sp)                      # protect ra
    sd a1, 8(sp)                      # protect a1
    sd a2, 16(sp)                     # protect a2
    sd a3, 24(sp)                     # protect a3

    mv a2, a1                         # Put CH in right place
    mv s5, a0                         # Protect VALUE

    li a0, 10                         # We need 10 bytes
    jal malloc                        # Get S pointer
    mv a1, a0                         # Put S in place
    mv a0, s5                         # Restore VALUE

    # Check for %
    li t0, 0x25
    beq a2, t0, express_number_const

    mv s5, a1                         # Protect S
    li t0, 0x2e                       # t0 = '.'
    sd t0, (a1)                       # S[0] = '.'
    addi a1, a1, 1                    # Next byte

    # Check for !
    li t0, 0x21
    beq a2, t0, express_number_I

    # Check for @
    li t0, 0x40
    beq a2, t0, express_number_S

    # Check for ~
    li t0, 0x7E
    beq a2, t0, express_number_U

    j Fail                            # Error

express_number_const:
    # provides an option for 32-bit immediate constants

    li t0, 0xffffffff
    and a0, a0, t0                    # immediate = value & 0xffffffff

    mv s5, a1                         # Protect S
    jal hex32l                        # Store 32-bits
    j express_number_done             # done

express_number_I:
    # Corresponds to RISC-V S format
    # (value & 0xfff) << 20
    li t0, 0xfff
    and a0, a0, t0                    # value & 0xfff
    slli a0, a0, 20                   # (value & 0xfff) << 20
    jal hex32l                        # Store 32-bits
    j express_number_done             # done

express_number_S:
    # Corresponds to RISC-V S format
    # ((value & 0x1f) << 7) | ((value & 0xfe0) << (31 - 11))
    li t0, 0x1f
    and t1, a0, t0                    # value & 0x1f
    slli t1, t1, 7                    # (value & 0x1f) << 7
    li t0, 0xfe0
    and t0, a0, t0                    # value & 0xfe0
    slli t0, t0, 20                   # (value & 0xfe0) << (31 - 11)
    or a0, t0, t1                     # Combine two parts
    jal hex32l                        # Store 32-bits
    j express_number_done             # done

express_number_U:
    # Corresponds to RISC-V U format
    # if value is 0x800 or more we have to add 11-th bit (0x1000) to compensate for signed extension

    li t0, 0x800
    li t1, 0xfff
    li t2, 0xfffff000
    and t1, a0, t1                    # value & 0xfff
    and a0, a0, t2                    # value & 0xfffff000
    blt t1, t0, express_number_U_small

    # Deal with sign extension: add 0x1000
    li t0, 0x1000
    addw a0, t0, a0                   # (value & 0xfffff000) + 0x1000
express_number_U_small:
    jal hex32l                        # Store 32-bits
    j express_number_done             # done

express_number_done:
    mv a0, s5                         # Restore S
    ld ra, 0(sp)                      # restore ra
    ld a1, 8(sp)                      # restore a1
    ld a2, 16(sp)                     # restore a2
    ld a3, 24(sp)                     # restore a3
    addi sp, sp, 32                   # deallocate stack
    ret                               # return


# HEX to ascii routine
# Receives INT in a0 and CHAR* in a1
# Stores ascii of INT in CHAR*
# Returns only modifying a0
hex32l:
    addi sp, sp, -16                  # allocate stack
    sd ra, 0(sp)                      # Protect ra
    sd a0, 8(sp)                      # Protect top 16 bits
    jal hex16l                        # Store it
    ld a0, 8(sp)                      # do high 16 bits
    srli a0, a0, 16                   # do bottom 16 bits
    jal hex16l                        # Store it
    ld ra, 0(sp)                      # restore ra
    addi sp, sp, 16                   # deallocate stack
    ret                               # return

hex16l:
    addi sp, sp, -16                  # allocate stack
    sd ra, 0(sp)                      # Protect ra
    sd a0, 8(sp)                      # Protect top byte
    jal hex8                          # Store it
    ld a0, 8(sp)                      # do high byte
    srli a0, a0, 8                    # do bottom byte
    jal hex8                          # Store it
    ld ra, 0(sp)                      # restore ra
    addi sp, sp, 16                   # deallocate stack
    ret                               # return

hex8:
    addi sp, sp, -16                  # allocate stack
    sd ra, 0(sp)                      # Protect ra
    sd a0, 8(sp)                      # Protect bottom nibble
    srli a0, a0, 4                    # do high nibble first
    jal hex4                          # Store it
    ld a0, 8(sp)                      # do low nibble
    jal hex4                          # Store it
    ld ra, 0(sp)                      # restore ra
    addi sp, sp, 16                   # deallocate stack
    ret                               # return

hex4:
    li t0, 0xf
    and a0, a0, t0                    # isolate nibble
    addi a0, a0, '0'                  # convert to ascii
    li t0, '9'                        # t0 = '9'
    bge t0, a0, hex1                  # check if valid digit
    addi a0, a0, 7                    # use alpha range
hex1:
    sb a0, (a1)                       # store result
    addi a1, a1, 1                    # next position
    ret                               # return

# Preserve_Other function
# Receives list in a0
# Update the list in place; does not modify registers
# Uses a0 for I, a1 for I->TEXT
Preserve_Other:
    addi sp, sp, -32                  # allocate stack
    sd a1, 0(sp)                      # protect a1
    sd a2, 8(sp)                      # protect a2
    sd a3, 16(sp)                     # protect a3
    sd a4, 24(sp)                     # protect a4
Preserve_Other_Loop:
    ld a1, 24(a0)                     # I->EXPRESSION
    bnez a1, Preserve_Other_Next      # IF NULL == I->EXPRESSION then preserve

    ld a1, 16(a0)                     # I->TEXT
    sd a1, 24(a0)                     # I->EXPRESSION = I->TEXT

Preserve_Other_Next:
    ld a0, (a0)                       # I = I->NEXT
    bnez a0, Preserve_Other_Loop      # Keep looping until I == NULL

    ld a1, 0(sp)                      # restore a1
    ld a2, 8(sp)                      # restore a2
    ld a3, 16(sp)                     # restore a3
    ld a4, 24(sp)                     # restore a4
    addi sp, sp, 32                   # deallocate stack
    ret                               # return


# Print_Hex function
# Receives list in a0
# walks the list and prints the I->EXPRESSION for all nodes followed by newline
# Uses a1 for I
Print_Hex:
    addi sp, sp, -24                  # allocate stack
    sd ra, 0(sp)                      # protect ra
    sd a1, 8(sp)                      # protect a1
    sd a2, 16(sp)                     # protect a2

    mv a1, s4                         # I = HEAD

Print_Hex_Loop:
    ld a0, 8(a1)                      # I->TYPE
    li t0, 1                          # t0 = MACRO
    beq a0, t0, Print_Hex_Next        # Skip if MACRO = I->TYPE

    ld a0, 24(a1)                     # Using EXPRESSION
    jal File_Print                    # Print it
    li a0, 10                         # \n
    jal fputc                         # Print newline

Print_Hex_Next:
    ld a1, (a1)                       # Iterate to next Token
    bnez a1, Print_Hex_Loop           # Stop if NULL, otherwise keep looping

    ld ra, 0(sp)                      # restore ra
    ld a1, 8(sp)                      # restore a1
    ld a2, 16(sp)                     # restore a2
    addi sp, sp, 24                   # deallocate stack
    ret                               # return


# File_Print function
# Receives CHAR* in a0
# calls fputc for every non-null char
File_Print:
    addi sp, sp, -24                  # allocate stack
    sd ra, 0(sp)                      # protect ra
    sd a1, 8(sp)                      # protect a1
    sd a2, 16(sp)                     # protect a2
    mv a1, a0                         # protect a0

    beqz a0, File_Print_Done          # Protect against nulls

File_Print_Loop:
    lbu a0, (a1)                      # Read byte
    beqz a0, File_Print_Done          # Stop at NULL

    jal fputc                         # print it
    addi a1, a1, 1                    # S = S + 1
    j File_Print_Loop                 # Keep printing

File_Print_Done:
    ld ra, 0(sp)                      # restore ra
    ld a1, 8(sp)                      # restore a1
    ld a2, 16(sp)                     # restore a2
    addi sp, sp, 24                   # deallocate stack
    ret                               # return


# fgetc function
# Loads FILE* from s2
# Returns -4 (EOF) or char in a0
fgetc:
    addi sp, sp, -32                  # allocate stack
    sd ra, 8(sp)                      # protect ra
    sd a1, 16(sp)                     # protect a1
    sd a2, 24(sp)                     # protect a2

    li a7, 63                         # sys_read
    mv a1, sp                         # Get stack address for buffer
    mv a0, s2                         # read from input file
    li a2, 1                          # read 1 character
    ecall                             # syscall

    bnez a0, fgetc_done               # Check if nothing was read
    li a2, -4                         # Use -4 as EOF
    sb a2, (a1)                       # Store EOF in *a1

fgetc_done:
    lb a0, (a1)                       # return char in a0
    ld ra, 8(sp)                      # restore ra
    ld a1, 16(sp)                     # restore a1
    ld a2, 24(sp)                     # restore a2
    addi sp, sp, 32                   # deallocate stack
    ret                               # return


# Malloc isn't actually required if the program being built fits in the initial memory
# However, it doesn't take much to add it.
# Requires MALLOC pointer to be initialized and a0 to have the number of desired bytes
malloc:
    addi sp, sp, -16                  # allocate stack
    sd ra, 0(sp)                      # protect ra
    sd a1, 8(sp)                      # protect a1

    mv a1, s1                         # Store the current pointer
    add a0, a0, s1                    # Request the number of desired bytes
    li a7, 214                        # sys_brk
    ecall                             # syscall
    mv s1, a0                         # Set our malloc pointer
    mv a0, a1                         # Return the pointer

    ld ra, 0(sp)                      # restore ra
    ld a1, 8(sp)                      # restore a1
    addi sp, sp, 16                   # deallocate stack
    ret                               # return

# fputc function
# receives CHAR in a0 and load FILE* from s3
# writes char and returns
fputc:
    addi sp, sp, -32                  # allocate stack
    sd a0, 0(sp)                      # protect a0
    sd ra, 8(sp)                      # protect ra
    sd a1, 16(sp)                     # protect a1
    sd a2, 24(sp)                     # protect a2

    li a7, 64                         # sys_write
    mv a0, s3                         # write to output
    mv a1, sp                         # Get stack address
    li a2, 1                          # write 1 character
    ecall                             # syscall

    ld a0, 0(sp)                      # restore a0
    ld ra, 8(sp)                      # restore ra
    ld a1, 16(sp)                     # restore a1
    ld a2, 24(sp)                     # restore a2
    addi sp, sp, 32                   # deallocate stack
    ret                               # return

Fail:
    # Terminate program with 1 return code
    li a7, 93                         # sys_exit
    li a0, 1                          # Return code 1
    ecall                             # exit(1)

# PROGRAM END

.data

terminators:
    .byte 10, 9, 32, 0

comments:
    .byte 35, 59, 0

string_char:
    .byte 34, 39, 0

DEFINE_str:
    .byte 68, 69, 70, 73, 78, 69, 0
