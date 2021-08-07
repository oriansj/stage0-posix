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
# s3: status
# s4: command_done
# s6: malloc pointer

.text
.global _start
_start:
    ld a2, 16(sp)                     # Input file name

    bnez a2, _start_out               # Use input file if specified
    la a2, default_file               # Else use kaem.run

_start_out:

    # Open input file and store FD in s2
    li a7, 56                         # sys_openat
    li a0, -100                       # AT_FDCWD
    mv a1, a2                         # file name
    li a2, 0                          # read only
    ecall                             # syscall
    bltz a0, Fail                     # Error opening file
    mv s2, a0                         # Save fd in for later

    # Prepare heap memory
    li a7, 214                        # sys_brk
    mv a0, zero                       # Get current brk
    ecall                             # syscall
    mv s6, a0                         # Set our malloc pointer

# Using a1 for tokens and a2 for tokens[i]
main_loop:
    li a0, 2048                       # 256 * sizeof(char*)
    jal malloc                        # allocate space
    mv a1, a0                         # set tokens pointer
    mv a2, a0                         # set tokens[i] pointer (i=0)

    mv s3, zero                       # status = 0
    mv s4, zero                       # command_done = 0

collect_command:
    jal collect_token                 # Get another token
    beqz a0, collect_command_comment  # if NULL == result then it is a comment, don't store

    sd a0, (a2)                       # tokens[i] = result
    addi a2, a2, 8                    # i = i + 1 (sizeof(char*) = 8)

collect_command_comment:
    beqz s4, collect_command          # keep looping if 0 == command_done

    # Deal with line comments
    beq a1, a2, main_loop             # keep looping if comment

    jal print_command                 # print the command
    ld a0, (a1)                       # program = tokens[0]
    beqz a0, Fail                     # Error, no program

    addi sp, sp, -8                   # allocate stack
    sd a1, 0(sp)                      # protect tokens

    li a7, 220                        # sys_clone
    li a0, 17                         # SIGCHLD flag
    mv a1, zero                       # Child uses duplicate of parent's stack
    ecall                             # syscall

    ld a1, 0(sp)                      # restore tokens
    addi sp, sp, 8                    # deallocate stack

    bltz a0, Fail                     # if f == -1 no child was created
    bnez a0, collect_command_parent   # if f == 0 it is child

    # Deal with child case
    li a7, 221                        # sys_execve
    ld a0, (a1)                       # program = tokens[0]
    ecall                             # execve(program, tokens)
    jal Fail                          # Exit with an error

collect_command_parent:
    li a7, 260                        # sys_wait4
    mv a2, zero                       # set options = 0
    mv a3, zero                       # set *ruseage = NULL
    ecall                             # syscall

    # wait4 returns wstatus pointer, from which we can extract child's exit status
    # Check if child exited
    ld a1, (a1)                       # Dereference wstatus pointer
    li t0, 0x7f
    and t0, a1, t0                    # WTERMSIG(s) ((s) & 0x7f)
    not t0, t0                        # WIFEXITED(s) = ! WTERMSIG(s)
    beqz t0, Fail                     # Something went wrong, child did not exit

    # Check exit status: WEXITSTATUS(s) (((s) & 0xff00) >> 8)
    li t0, 0xff00
    and t0, a1, t0                    # (s) & 0xff00
    srli s3, t0, 8                    # Shift right by 8 to get status

    beqz s3, main_loop                # Loop if 0 == status

    la a0, hard                       # Get error string
    jal File_Print                    # Print it
    j Fail                            # Exit with failure

# print_command function
# Receives tokens[j] in a1 and tokens[i] in a2
# Modifies a0
print_command:
    addi sp, sp, -24                  # allocate stack
    sd ra, 0(sp)                      # protect ra
    sd a1, 8(sp)                      # protect a1
    sd a2, 16(sp)                     # protect a2

    la a0, prefix                     # Get prefix " +> "
    jal File_Print                    # print it

print_command_loop:
    ld a0, (a1)                       # get tokens[j]
    jal File_Print                    # print it
    addi a1, a1, 8                    # j = j + 1
    li a0, 32                         # a0 = ' '
    jal fputc                         # print it
    bne a1, a2, print_command_loop    # continue if j < i, otherwise keep looping

    li a0, 10                         # a0 = '\n'
    jal fputc                         # print it

    ld ra, 0(sp)                      # restore ra
    ld a1, 8(sp)                      # restore a1
    ld a2, 16(sp)                     # restore a2
    addi sp, sp, 24                   # deallocate stack
    ret                               # return

# collect_token function
# Receives nothing
# Overwrites a0
# Uses a0 as c, a1 as token and a2 as token[i]
collect_token:
    addi sp, sp, -24                  # allocate stack
    sd ra, 0(sp)                      # protect ra
    sd a1, 8(sp)                      # protect a1
    sd a2, 16(sp)                     # protect a2

    li a0, 4096                       # 4096 * sizeof(char)
    jal malloc                        # allocate space
    mv a1, a0                         # token = malloc(max_string)
    mv a2, a0                         # i = 0; set token[i]

collect_token_loop:
    jal fgetc                         # read character
    li t0, -4                         # if character == EOF
    beq a0, t0, Done                  # We are done

    li t0, 32                         # if c == ' '
    beq a0, t0, collect_token_done    # Space terminates token

    li t0, 9                          # if c == '\t'
    beq a0, t0, collect_token_done    # Tab terminates token

    li t0, 10                         # continue if c == '\n'
    bne a0, t0, collect_token_comment # otherwise check next

    # newline
    li s4, 1                          # command_done = true
    j collect_token_done              # We are done with current command

collect_token_comment:
    li t0, 35                         # if c == '#'
    bne a0, t0, collect_token_escape  # otherwise check next

    # It is a line comment
    jal collect_comment               # Read whole comment
    li s4, 1                          # command_done = true
    jal collect_token_done            # Done

collect_token_escape:
    li t0, 92                         # if c == '\'
    bne a0, t0, collect_token_other   # otherwise just store it

    # Escape character
    jal fgetc                         # Read the char to drop
    jal collect_token_done            # We are done

collect_token_other:
    sb a0, (a2)                       # token[i] = c
    addi a2, a2, 1                    # i = i + 1
    j collect_token_loop              # Read another character

collect_token_done:
    bne a1, a2, collect_token_good    # return the token unless
    mv a1, zero                       # i == 0, then token = NULL

collect_token_good:
    mv a0, a1                         # Return token
    ld ra, 0(sp)                      # Restore ra
    ld a1, 8(sp)                      # Restore a1
    ld a2, 16(sp)                     # Restore a2
    addi sp, sp, 24                   # Deallocate stack
    ret                               # return

# collect_comment function
# Receives nothing
# Modifies EAX
# uses EAX as Int C
# Just throws away everything it reads
collect_comment:
    addi sp, sp, -8                   # allocate stack
    sd ra, 0(sp)                      # protect ra

    jal fgetc                         # c = fgetc(input)
    li t0, -4                         # if c == EOF
    beq a0, t0, Fail                  # Abort

    li t0, 10                         # if c == '\n'
    bne a0, t0, collect_comment       # loop

    ld ra, 0(sp)                      # restore ra
    addi sp, sp, 8                    # deallocate stack
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
    mv a1, sp                         # Get stack address
    mv a0, s2                         # read from input file
    li a2, 1                          # read 1 character
    ecall                             # syscall

    bnez a0, fgetc_done               # Check if nothing was read

fgetc_fail:
    li t0, -4                         # Use -4 as EOF
    sb t0, (a1)                       # Put EOF in a0

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

    mv a1, s6                         # Store the current pointer
    add a0, a0, s6                    # Request the number of desired bytes
    li a7, 214                        # sys_brk
    ecall                             # syscall
    mv s6, a0                         # Set our malloc pointer
    mv a0, a1                         # Return the pointer

    ld ra, 0(sp)                      # restore ra
    ld a1, 8(sp)                      # restore a1
    addi sp, sp, 16                   # deallocate stack
    ret                               # return

# File_Print function
# Receives CHAR* in EAX
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

# fputc function
# receives CHAR in a0 and load FILE* from stdout
# writes char and returns
fputc:
    addi sp, sp, -32                  # allocate stack
    sd a0, 0(sp)                      # protect a0
    sd ra, 8(sp)                      # protect ra
    sd a1, 16(sp)                     # protect a1
    sd a2, 24(sp)                     # protect a2

    li a7, 64                         # sys_write
    li a0, 1                          # write to stdout
    mv a1, sp                         # Get stack address
    li a2, 1                          # write 1 character
    ecall                             # syscall

    ld a0, 0(sp)                      # restore a0
    ld ra, 8(sp)                      # restore ra
    ld a1, 16(sp)                     # restore a1
    ld a2, 24(sp)                     # restore a2
    addi sp, sp, 32                   # deallocate stack
    ret                               # return

Done:
    # Terminate program with 0 return code
    li a7, 93                         # sys_exit
    mv a0, zero                       # Return code 0
    ecall                             # syscall

Fail:
    # Terminate program with 1 return code
    li a7, 93                         # sys_exit
    li a0, 1                          # Return code 1
    ecall
# PROGRAM END

.data
.align 4

default_file: .string "kaem.run"
prefix: .string " +> "
hard: .string "Subprocess error\nABORTING HARD\n"
