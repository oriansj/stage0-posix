## Copyright (C) 2020 Jeremiah Orians
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

	.text
	.global _start

# Where the ELF Header is going to hit
# Simply jump to _start
# Our main function
_start:
	pop {r0}                        @ Get the number of arguments
	pop {r0}                        @ Get the program name
	pop {r0}                        @ Get the actual input name
	cmp r0, #0                      @ Check for missing input
	bne _start_out                  @ Have real input
	push {r0}                       @ Need to adjust stack
	ldr r0, default_file_address    @ Use "kaem.run"

_start_out:
	mov r1, #0                      @ prepare read_only
	mov r7, #5                      @ the syscall number for open()
	svc #0                          @ Now open that damn file

	cmp r0, #0                      @ IF NULL We couldn't open the file
	ble Exit_Failure                @ Abort hard
	ldr r8, script_address
	str r0, [r8]                    @ Set input pointer

	pop {r0}                        @ Get start of envp
	mov r12, r13                    @ Protect envp

	mov r7, #45                     @ the Syscall # for SYS_BRK
	mov r0, #0                      @ Get current brk
	svc #0                          @ Let the kernel do the work
	ldr r8, MALLOC_address
	str r0, [r8]                    @ Set our malloc pointer

	## Where the main work gets done
	## Using R1 for tokens and R2 for tokens[i]
main_loop:
	ldr r8, max_args_address
	ldr r0, [r8]                    @ Using 256 char* of space
	push {r14}
	bl malloc                       @ get it
	pop {r14}
	mov r1, r0                      @ set tokens

	mov r2, r1                      @ I = 0
	mov r0, #0                      @ Using 0
	ldr r8, status_address
	str r0, [r8]                    @ status = 0
	ldr r8, command_done_address
	str r0, [r8]                    @ command_done = 0

	## Using R0 for result and R1 for tokens[i]
collect_command:
	push {r14}
	bl collect_token                @ Get another token
	pop {r14}
	cmp r0, #0                      @ if NULL == result
	beq collect_command_comment     @ It is a comment, don't store

	str r0, [r2]                    @ tokens[i] = result
	add r2, #4                      @ i = i + 1 (adjusted for char* size)

collect_command_comment:
	ldr r8, command_done_address
	ldr r0, [r8]                    @ Using command_done
	cmp r0, #0                      @ IF 0 == command_done
	beq collect_command             @ keep looping

	## Deal with line comments
	cmp r2, r1                      @ if 0 < i
	beq main_loop                   @ It was a comment

	push {r14}
	bl print_command                @ print the command
	pop {r14}
	ldr r0, [r1]                    @ program = tokens[0]
	cmp r0, #0                      @ IF NULL == program
	beq Exit_Failure                @ Some shit went down, abort

	push {r1}                       @ Protect Tokens
	mov r7, #2                      @ FORKing
	svc #0                          @ int f = FORK()
	pop {r1}                        @ Restore Tokens

	cmp r0, #0                      @ Check fork
	blt Exit_Failure                @ IF f == -1 abort hard
	bne collect_command_parent      @ IF f == 0 it is child

	## Deal with child case
	mov r7, #11                     @ EXECVE
	mov r2, r12                     @ third arg = envp
	# R1 aready has tokens          @ second arg = tokens
	ldr r0, [r1]                    @ program = tokens[0]
	svc #0                          @ execve(program, tokens, envp);
	b Exit_Failure                  @ return error

collect_command_parent:
	# R0 already has f              @ first arg = f
	ldr r1, status_address          @ second arg = &status
	mov r2, #0                      @ third arg = NULL
	mov r7, #114                    @ WAITPID
	svc #0                          @ waitpid(f, &status, 0);

	ldr r8, status_address
	ldr r0, [r8]                    @ Using status
	cmp r0, #0                      @ IF 0 == status
	beq main_loop                   @ Loop forever

	## Deal with very unhappy case
	ldr r0, hard_address            @ Using "Subprocess error\nABORTING HARD\n"
	push {r14}
	bl File_Print                   @ Print it
	pop {r14}

## Exit_Failure function
## Receives nothing
## And aborts hard
## Does NOT return
Exit_Failure:
	mov r0, #1                      @ All is wrong
	mov r7, #1                      @ put the exit syscall number in r7
	svc #0                          @ Call it a bad day


## print_command function
## Recieves tokens[j] in R1 and tokens[i] in R2
## Modifies R0
print_command:
	push {r1}                       @ Protect R1
	ldr r0, prefix_address          @ using " +> "
	push {r14}
	bl File_Print                   @ print it
	pop {r14}
print_command_loop:
	ldr r0, [r1]                    @ using tokens[j]
	push {r14}
	bl File_Print                   @ print it
	pop {r14}
	add r1, #4                      @ j = j + 1
	mov r0, #32                     @ using ' '
	push {r14}
	bl fputc                        @ print it
	pop {r14}
	cmp r1, r2                      @ IF j < i
	bne print_command_loop          @ otherwise keep looping

	mov r0, #10                     @ using '\n'
	push {r14}
	bl fputc                        @ print it
	pop {r14}
	pop {r1}                        @ Restore R1
	bx r14


## collect_token function
## Recieves nothing
## Overwrites R0
## Uses R0 as C, R1 as token and R2 as token[i]
collect_token:
	push {r1}                       @ Protect R1
	push {r2}                       @ Protect R2
	ldr r8, max_string_address
	ldr r0, [r8]                    @ Using max_string
	push {r14}
	bl malloc                       @ allocate space
	pop {r14}
	mov r1, r0                      @ token = malloc(max_string);
	mov r2, r0                      @ i = 0; set token[i]

collect_token_loop:
	push {r14}
	bl fgetc                        @ c = fgetc(input);
	pop {r14}
	cmp r0, #-4                     @ if C == EOF
	beq Done                        @ We are done

	cmp r0, #32                     @ IF C == ' '
	beq collect_token_done          @ Space terminates token

	cmp r0, #9                      @ IF C == '\t'
	beq collect_token_done          @ tab terminates token

	cmp r0, #10                     @ IF C == '\n'
	bne collect_token_string        @ otherwise check next

	## It is a newline
	mov r0, #1                      @ Using 1
	ldr r8, command_done_address
	str r0, [r8]                    @ Set command_done = TRUE
	b collect_token_done            @ Be done

collect_token_string:
	cmp r0, #34                     @ IF C == '\"'
	bne collect_token_comment       @ otherwise check next

	## It is a RAW STRING
	push {r14}
	bl collect_string               @ Get the rest of the string
	pop {r14}
	b collect_token_done            @ Be done

collect_token_comment:
	cmp r0, #35                     @ IF C == '#'
	bne collect_token_escape        @ otherwise check next

	## It is a line comment
	push {r14}
	bl collect_comment              @ Read it all
	pop {r14}
	mov r0, #1                      @ Using 1
	ldr r8, command_done_address
	str r0, [r8]                    @ Set command_done = TRUE
	b collect_token_done            @ Be done

collect_token_escape:
	cmp r0, #92                     @ IF C == '\\'
	bne collect_token_other         @ otherwise just store it

	## It is an escape char
	push {r14}
	bl fgetc                        @ Read the char to drop
	pop {r14}
	b collect_token_done            @ Be done

collect_token_other:
	strb r0, [r2]                   @ token[i] = C
	add r2, #1                      @ i = i + 1
	b collect_token_loop            @ Keep going

collect_token_done:
	cmp r1, r2                      @ IF i == 0
	bne collect_token_good          @ otherwise return the token
	mov r1, #0                      @ token = NULL

collect_token_good:
	mov r0, r1                      @ Return token
	pop {r2}                        @ Restore R2
	pop {r1}                        @ Restore R1
	bx r14


## collect_string function
## Recieves target[index] in R2
## Modifies R0
## Uses R0 as C
collect_string:
	push {r14}
	bl fgetc                        @ C = fgetc(input)
	pop {r14}
	cmp r0, #-4                     @ if C == EOF
	beq Exit_Failure                @ Something went horriably wrong

	cmp r0, #34                     @ IF C == '\"'
	beq collect_string_done         @ be done

	## deal with inside of string
	strb r0, [r2]                   @ target[index] = C
	add r2, #1                      @ index = index + 1
	b collect_string                @ Keep going

collect_string_done:
	bx r14


## collect_comment function
## Recieves nothing
## Modifies R0
## uses R0 as Int C
## Just throws away everything it reads
collect_comment:
	push {r14}
	bl fgetc                        @ C = fgetc(input)
	pop {r14}
	cmp r0, #-4                     @ IF C == EOF
	beq Exit_Failure                @ abort hard

	cmp r0, #10                     @ IF C == '\n'
	bne collect_comment             @ otherwise keep looping
	bx r14


## Malloc isn't actually required if the program being built fits in the initial memory
## However, it doesn't take much to add it.
## Requires [MALLOC] to be initialized and R0 to have the number of desired bytes
malloc:
	push {r1}                       @ Protect R1
	push {r2}                       @ Protect R2
	push {r3}                       @ Protect R3
	ldr r8, MALLOC_address
	ldr r1, [r8]                    @ Using the current pointer
	add r0, r1                      @ Request the number of desired bytes
	mov r7, #45                     @ the Syscall # for SYS_BRK
	svc #0                          @ call the Kernel
	ldr r1, [r8]                    @ get old pointer
	str r0, [r8]                    @ Update pointer
	mov r0, r1                      @ Return pointer
	pop {r3}                        @ Restore R3
	pop {r2}                        @ Restore R2
	pop {r1}                        @ Restore R1
	bx r14


## fgetc function
## Loads FILE* from [script]
## Returns -4 (EOF) or char in R0
fgetc:
	push {r3}                       @ Protect R3
	push {r2}                       @ Protect R2
	push {r1}                       @ Protect R1
	mov r0, #-4                     @ Put EOF in r0
	push {r0}                       @ Assume bad (If nothing read, value will remain EOF)
	mov r1, r13                     @ Get stack address
	ldr r8, script_address
	ldr r0, [r8]                    @ Where are we reading from
	mov r7, #3                      @ the syscall number for read
	mov r2, #1                      @ set the size of chars we want
	svc #0                          @ call the Kernel
	pop {r0}                        @ Get either char or EOF
	cmp r0, #-4
	andne r0, #0xFF                 @ truncate to byte if not EOF
	pop {r1}                        @ Restore R1
	pop {r2}                        @ Restore R2
	pop {r3}                        @ Restore R3
	bx r14


## File_Print function
## Receives CHAR* in R0
## calls fputc for every non-null char
File_Print:
	push {r1}                       @ Protect R1
	push {r2}                       @ Protect R2
	mov r1, r0                      @ Protect S
	cmp r0, #0                      @ Protect against nulls
	beq File_Print_Done             @ Simply don't try to print them
File_Print_Loop:
	ldrb r0, [r1]                   @ Read byte
	cmp r0, #0                      @ Check for NULL
	beq File_Print_Done             @ Stop at NULL

	push {r14}
	bl fputc                        @ write it
	pop {r14}
	add r1, #1                      @ S = S + 1
	b File_Print_Loop               @ Keep going

File_Print_Done:
	pop {r2}                        @ Restore R2
	pop {r1}                        @ Restore R1
	bx r14


## fputc function
## receives CHAR in R0 and load FILE* from stdout
## writes char and returns
fputc:
	push {r3}                       @ Protect R3
	push {r2}                       @ protect R2
	push {r1}                       @ protect R1
	push {r0}                       @ We are writing r0
	mov r1, r13                     @ Get stack address
	mov r0, #1                      @ Write to target file
	mov r7, #4                      @ the syscall number for write
	mov r2, #1                      @ set the size of chars we want
	svc #0                          @ call the Kernel
	pop {r0}                        @ Restore stack
	pop {r1}                        @ Restore R1
	pop {r2}                        @ Restore R2
	pop {r3}                        @ Restore R3
	bx r14


Done:
	# program completed Successfully
	mov r0, #0                      @ All is well
	mov r7, #1                      @ put the exit syscall number in r0
	svc #0                          @ Call it a good day

## Because ARM doesn't support loading/storing directly to different segments in a single instruction
.balign 4
default_file_address: .word default_file
prefix_address: .word prefix
hard_address: .word hard
script_address: .word script
tokens_address: .word tokens
command_done_address: .word command_done
max_args_address: .word max_args
max_string_address: .word max_string
MALLOC_address: .word MALLOC
status_address: .word status

.data
default_file: .asciz "kaem.run"
prefix: .asciz " +> "
hard: .asciz "Subprocess error\nABORTING HARD\n"
script: .word 0
tokens: .word 0
command_done: .word 0
max_args: .word 1024               @ 256 * sizeof(char*)
max_string: .word 4096             @ 4096 * sizeof(char)
MALLOC: .word 0
status: .word 0
