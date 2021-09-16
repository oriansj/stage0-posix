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

	## Register usage:
	## R0 => Temps
	## R8 => address scratch register because ARM can't handle 12bit immediates/offsets correctly or have a swap/xchg instruction
	## R11 => function_address
	## R12 => global_token_address

	## Struct TYPE format: (size 28)
	## NEXT => 0
	## SIZE => 4
	## OFFSET => 8
	## INDIRECT => 12
	## MEMBERS => 16
	## TYPE => 20
	## NAME => 24

	## Struct TOKEN_LIST format: (size 20)
	## NEXT => 0
	## LOCALS/PREV => 4
	## S => 8
	## TYPE => 12
	## ARGS/DEPTH => 16

# Where the ELF Header is going to hit
# Simply jump to _start
# Our main function
_start:
	pop {r0}                            @ Get the number of arguments
	pop {r0}                            @ Get the program name
	pop {r0}                            @ Get the actual input name
	mov r1, #0                          @ prepare read_only
	mov r7, #5                          @ the syscall number for open()
	svc #0                              @ Now open that damn file
	ldr r8, Input_file_address
	str r0, [r8]                        @ Preserve the file pointer we were given

	pop {r0}                            @ Get the actual output name
	mov r1, #577                        @ Prepare file as O_WRONLY|O_CREAT|O_TRUNC
	mov r2, #384                        @ Prepare file as RW for owner only (600 in octal)
	mov r7, #5                          @ the syscall number for open()
	svc #0                              @ Now open that damn file
	cmp r0, #0                          @ Check for missing output
	bgt _start_out                      @ Have real input
	mov r0, #1                          @ Use stdout

_start_out:
	ldr r8, Output_file_address
	str r0, [r8]                        @ Preserve the file pointer we were given

	mov r7, #45                         @ the Syscall # for SYS_BRK
	mov r0, #0                          @ Get current brk
	svc #0                              @ Let the kernel do the work
	ldr r8, MALLOC_address
	str r0, [r8]                        @ Set our malloc pointer
	mov r0, #0                          @ HEAD = NULL
	push {r14}
	bl read_all_tokens                  @ Read all tokens
	bl Reverse_List                     @ Reverse order
#	bl debug_list                       @ Try to figure out what is wrong
	pop {r14}
	ldr r11, function_address           @ initialize r11
	ldr r12, global_token_address       @ initialize r12
	str r0, [r12]                       @ Set global_token
	push {r14}
	bl program                          @ Convert into program
	pop {r14}
	adr r0, header_string1              @ Our header string
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	ldr r8, output_list_address_0
	ldr r0, [r8]                        @ Our output_list
	push {r14}
	bl recursive_output                 @ Print core program
	pop {r14}
#	adr r0, header_string2              @ Our Enable debug
#	bl File_Print                       @ Print it
	adr r0, header_string3              @ Our second label
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	ldr r8, globals_list_address
	ldr r0, [r8]                        @ Our globals
	push {r14}
	bl recursive_output                 @ Get them
	pop {r14}
	adr r0, header_string4              @ Our final header
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	ldr r8, strings_list_address_0
	ldr r0, [r8]                        @ Our strings
	push {r14}
	bl recursive_output                 @ Get them
	pop {r14}
	adr r0, header_string5              @ Make this a bare assembly
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}

Done:
	# program completed Successfully
	mov r0, #0                          @ All is well
	mov r7, #1                          @ put the exit syscall number in r7
	svc #0                              @ Call it a good day

header_string1: .asciz "\n# Core program\n"
.balign 4
header_string2: .asciz "\n:ELF_data\n"
.balign 4
header_string3: .asciz "\n# Program global variables\n"
.balign 4
header_string4: .asciz "\n# Program strings\n"
.balign 4
header_string5: .asciz "\n:ELF_end\n"
.balign 4
global_token_address: .word global_token
output_list_address_0: .word output_list
strings_list_address_0: .word strings_list
function_address: .word function


## read_all_tokens function
## Receives Token_List* in R0
## Tokenizes all input and returns updated list in R0
## Returns TOKEN in R0
## Uses R0 for C
read_all_tokens:
	ldr r8, Token_address
	str r0, [r8]
	push {r14}
	bl fgetc
	pop {r14}
read_all_tokens_loop:
	cmp r0, #-4                         @ Check for EOF
	beq read_all_tokens_done            @ Stop if found
	push {r14}
	bl get_token                        @ Read all tokens
	pop {r14}
	b read_all_tokens_loop              @ Loop
read_all_tokens_done:
	ldr r8, Token_address
	ldr r0, [r8]
	bx r14

Token_address: .word Token

## get_token function
## Receives INT in R0
## Makes a list of TOKEN_LIST
## C and STRING_INDEX are stored in memory, R2 is used for S and R3 is used for current
## Returns C in R0
get_token:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3

	ldr r8, C_address
	str r0, [r8]                        @ Set C

	mov r0, #20                         @ Malloc CURRENT
	push {r14}
	bl malloc                           @ Get Pointer
	pop {r14}
	mov r3, r0                          @ Set CURRENT

	mov r0, #256                        @ Malloc the string
	push {r14}
	bl malloc                           @ Get pointer to S
	pop {r14}
	mov r2, r0                          @ Set S
	str r2, [r3, #8]                    @ CURRENT->S = S
reset:
	ldr r8, string_index_address
	str r2, [r8]                        @ S[0]
	ldr r8, C_address
	ldr r0, [r8]                        @ Using C

	push {r14}
	bl clear_white_space                @ Clear WhiteSpace
	pop {r14}
	ldr r8, C_address
	str r0, [r8]                        @ Set C

	cmp r0, #-4                         @ Check for EOF
	beq get_token_abort                 @ if EOF abort

	cmp r0, #35                         @ Check for '#'
	bne get_token_alpha                 @ Nope

	## Deal with # line comments
	push {r14}
	bl purge_macro                      @ Let it handle it
	pop {r14}
	ldr r8, C_address
	str r0, [r8]                        @ Set C
	b reset                             @ Try again

get_token_alpha:
	ldr r8, C_address
	ldr r0, [r8]                        @ Send C
	adr r1, alphas                      @ Get alphanumerics
	push {r14}
	bl In_Set                           @ See if in set
	pop {r14}
	cmp r0, #1                          @ IF TRUE
	bne get_token_symbol                @ Otherwise

	## Store keywords
	ldr r8, C_address
	ldr r0, [r8]                        @ Send C
	push {r14}
	bl preserve_keyword                 @ Store
	pop {r14}
	ldr r8, C_address
	str r0, [r8]                        @ Set C
	b get_token_done                    @ Be done with this token

get_token_symbol:
	ldr r8, C_address
	ldr r0, [r8]                        @ Send C
	adr r1, symbols                     @ Get symbols
	push {r14}
	bl In_Set                           @ See if in set
	pop {r14}
	cmp r0, #1                          @ IF TRUE
	bne get_token_strings               @ Otherwise

	## Store symbols
	ldr r8, C_address
	ldr r0, [r8]                        @ Send C
	push {r14}
	bl preserve_symbol                  @ Store
	pop {r14}
	ldr r8, C_address
	str r0, [r8]                        @ Set C
	b get_token_done                    @ Be done with this token

get_token_strings:
	ldr r8, C_address
	ldr r0, [r8]                        @ Send C
	adr r1, strings                     @ Get strings
	push {r14}
	bl In_Set                           @ See if in set
	pop {r14}
	cmp r0, #1                          @ IF TRUE
	bne get_token_comment               @ Otherwise

	## Store String
	ldr r8, C_address
	ldr r0, [r8]                        @ Send C
	push {r14}
	bl consume_word                     @ Store
	pop {r14}
	ldr r8, C_address
	str r0, [r8]                        @ Set C
	b get_token_done                    @ Be done with this token

get_token_comment:
	ldr r8, C_address
	ldr r0, [r8]                        @ Send C
	cmp r0, #47                         @ IF '/' == C
	bne get_token_else                  @ Otherwise

	push {r14}
	bl consume_byte                     @ Hope it just is '/'
	pop {r14}
	ldr r8, C_address
	str r0, [r8]                        @ Set C

	cmp r0, #42                         @ IF '*' we have "/*"
	bne get_token_comment_line          @ Check for '//'

	## Deal with /* block comments */
	push {r14}
	bl fgetc                            @ get next C
	pop {r14}
	ldr r8, C_address
	str r0, [r8]                        @ Set C
get_token_comment_block_outer:
	ldr r8, C_address
	ldr r0, [r8]                        @ Using C
	cmp r0, #47                         @ IF '/' != C
	beq get_token_comment_block_done    @ be done

get_token_comment_block_inner:
	ldr r8, C_address
	ldr r0, [r8]                        @ Using C
	cmp r0, #42                         @ IF '*' != C
	beq get_token_comment_block_iter    @ jump over

	## Deal with inner loop
	push {r14}
	bl fgetc                            @ get next C
	pop {r14}
	ldr r8, C_address
	str r0, [r8]                        @ Set C
	b get_token_comment_block_inner     @ keep going

get_token_comment_block_iter:
	push {r14}
	bl fgetc                            @ get next C
	pop {r14}
	ldr r8, C_address
	str r0, [r8]                        @ Set C
	b get_token_comment_block_outer

get_token_comment_block_done:
	push {r14}
	bl fgetc                            @ get next C
	pop {r14}
	ldr r8, C_address
	str r0, [r8]                        @ Set C
	b reset                             @ throw away, try again

get_token_comment_line:
	cmp r0, #47                         @ IF '/' we have //
	bne get_token_done                  @ keep if just '/'

	## Deal with // line comment
	push {r14}
	bl fgetc                            @ drop to match
	pop {r14}
	ldr r8, C_address
	str r0, [r8]                        @ Set C
	b reset                             @ throw away, try again

get_token_else:
	ldr r8, C_address
	ldr r0, [r8]                        @ Send C
	push {r14}
	bl consume_byte
	pop {r14}
	ldr r8, C_address
	str r0, [r8]                        @ Set C

get_token_done:
	ldr r8, Token_address
	ldr r0, [r8]                        @ TOKEN
	str r0, [r3, #4]                    @ CURRENT->PREV = TOKEN
	str r0, [r3]                        @ CURRENT->NEXT = TOKEN
	str r3, [r8]                        @ TOKEN = CURRENT

get_token_abort:
	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	ldr r8, C_address
	ldr r0, [r8]                        @ Return C
	bx r14

C_address: .word C


## Malloc isn't actually required if the program being built fits in the initial memory
## However, it doesn't take much to add it.
## Requires [MALLOC] to be initialized and R0 to have the number of desired bytes
malloc:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3
	ldr r8, MALLOC_address
	ldr r1, [r8]                        @ Using the current pointer
	add r0, r1                          @ Request the number of desired bytes
	mov r7, #45                         @ the Syscall # for SYS_BRK
	svc #0                              @ call the Kernel
	ldr r8, MALLOC_address
	ldr r1, [r8]
	str r0, [r8]                        @ Update pointer
	mov r0, r1                          @ Return pointer
	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

MALLOC_address: .word MALLOC


## clear_white_space function
## Receives INT C in R0
## Returns first non-whitespace char in R0
clear_white_space:
	cmp r0, #32                         @ Check for ' '
	beq clear_white_space_wipe          @ wipe it out

	cmp r0, #10                         @ Check for '\n'
	beq clear_white_space_wipe          @ wipe it out

	cmp r0, #9                          @ Check for '\t'
	bne clear_white_space_done          @ looks like non-whitespace

clear_white_space_wipe:
	push {r14}
	bl fgetc                            @ Read a new byte
	pop {r14}
	cmp r0, #-4                         @ Check for EOF
	beq clear_white_space_done          @ Short circuit
	b clear_white_space                 @ iterate

clear_white_space_done:
	bx r14


## In_Set function
## Receives Char C in R0 and CHAR* in R1
## Returns 1 if true, zero if false in R0
In_Set:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
In_Set_loop:
	ldrb r2, [r1]                       @ Read char

	cmp r0, r2                          @ See if they match
	beq In_Set_True                     @ return true

	cmp r2, #0                          @ Check for NULL
	beq In_Set_False                    @ return false

	add r1, #1                          @ s = s + 1
	b In_Set_loop                       @ Keep looping

In_Set_True:
	mov r0, #1                          @ Set True
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

In_Set_False:
	mov r0, #0                          @ Set FALSE
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

alphas: .asciz "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"
.balign 4
symbols: .asciz "<=>|&!-"
.balign 4
strings: .asciz "\"'"
.balign 4


## purge_macro function
## Receives CH in R0
## Reads chars until Line feed is read
## returns line feed
purge_macro:
	push {r14}
	bl fgetc                            @ read next char
	pop {r14}
	cmp r0, #10                         @ Check for '\n'
	bne purge_macro                     @ Keep going
	bx r14


## preserve_keyword function
## Receives INT C in R0
## collects all chars in keyword
## Returns C in R0
## Uses R2 for INT C
preserve_keyword:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	mov r2, r0                          @ Setup C
	adr r1, alphas                      @ Concerning ourselves with "abc.."
preserve_keyword_loop:
	push {r14}
	bl In_Set                           @ Check if alphanumerics
	pop {r14}
	cmp r0, #1                          @ IF TRUE
	bne preserve_keyword_label          @ Otherwise check for label

	mov r0, r2                          @ Pass C
	push {r14}
	bl consume_byte                     @ consume that byte
	pop {r14}
	mov r2, r0                          @ Update C
	b preserve_keyword_loop             @ keep looping

preserve_keyword_label:
	mov r0, r2                          @ Fix return
	cmp r0, #58                         @ Check for ':'
	bne preserve_keyword_done           @ be done

	## Fix our goto label
	push {r14}
	bl fixup_label                      @ Fix the label
	pop {r14}
	mov r0, #32                         @ Return Whitespace

preserve_keyword_done:
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14


## preserve_symbol function
## Receives INT C in R0
## collects all chars in symbol
## Returns C in R0
## Uses R2 for INT C
preserve_symbol:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	mov r2, r0                          @ Setup C
	adr r1, symbols                     @ Concerning ourselves with "<=>.."
preserve_symbol_loop:
	push {r14}
	bl In_Set                           @ Check if symbol
	pop {r14}
	cmp r0, #1                          @ IF TRUE
	bne preserve_symbol_done            @ Otherwise be done

	mov r0, r2                          @ Pass C
	push {r14}
	bl consume_byte                     @ consume that byte
	pop {r14}
	mov r2, r0                          @ Update C
	b preserve_symbol_loop              @ keep looping

preserve_symbol_done:
	mov r0, r2                          @ Fix return
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14


## consume_word function
## receives INT C in R0
## returns INT C in R0
## Uses R0 for C, R1 for FREQ and R2 for ESCAPE
consume_word:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	mov r1, r0                          @ FREQ = C
	mov r2, #0                          @ ESCAPE = FALSE
consume_word_loop:
	cmp r2, #0                          @ IF !ESCAPE
	bne consume_word_escape             @ Enable escape

	cmp r0, #92                         @ if '\\'
	bne consume_word_iter               @ keep state

	mov r2, #1                          @ ESCAPE = TRUE
	b consume_word_iter                 @ keep going

consume_word_escape:
	mov r2, #0                          @ ESCAPE = FALSE

consume_word_iter:
	push {r14}
	bl consume_byte                     @ read next char
	pop {r14}

	cmp r2, #0                          @ IF ESCAPE
	bne consume_word_loop               @ keep looping

	cmp r0, r1                          @ IF C != FREQ
	bne consume_word_loop               @ keep going

	push {r14}
	bl fgetc                            @ return next char
	pop {r14}
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14


## consume_byte function
## Receives INT C in R0
## Inserts C into string S, updates String S
## Returns Next char in R0
consume_byte:
	push {r1}                           @ Protect R1
	ldr r8, string_index_address
	ldr r1, [r8]                        @ S[0]
	strb r0, [r1]                       @ S[0] = C
	add r1, #1                          @ S = S + 1
	str r1, [r8]                        @ Update S
	push {r14}
	bl fgetc
	pop {r14}
	pop {r1}                            @ Restore R1
	bx r14

string_index_address: .word string_index


## fixup_label function
## Receives S in R2
## prepends ':' to string and returns registers un changed
## Uses R0 for HOLD, R1 for PREV and R2 for S[0]
fixup_label:
	push {r0}                           @ Protect R0
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	mov r0, #58                         @ HOLD = ':'
	ldr r2, [r3, #8]                    @ HOLD_STRING[0]
fixup_label_loop:
	mov r1, r0                          @ PREV = HOLD
	ldrb r0, [r2]                       @ HOLD = HOLD_STRING[I]
	strb r1, [r2]                       @ HOLD_STRING[I] = PREV
	add r2, #1                          @ I = I + 1
	cmp r0, #0                          @ IF NULL == HOLD
	bne fixup_label_loop                @ Keep looping

	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	pop {r0}                            @ Restore R0
	bx r14


## fgetc function
## Loads FILE* from [INPUT_FILE]
## Returns -4 (EOF) or char in R0
fgetc:
	push {r3}                           @ Protect R3
	push {r2}                           @ Protect R2
	push {r1}                           @ Protect R1
	mov r0, #-4                         @ Put EOF in r0
	push {r0}                           @ Assume bad (If nothing read, value will remain EOF)
	mov r1, r13                         @ Get stack address
	ldr r8, Input_file_address
	ldr r0, [r8]                        @ Where are we reading from
	mov r7, #3                          @ the syscall number for read
	mov r2, #1                          @ set the size of chars we want
	svc #0                              @ call the Kernel
	pop {r0}                            @ Get either char or EOF
	cmp r0, #-4
	andne r0, #0xFF                     @ truncate to byte if not EOF
	pop {r1}                            @ Restore R1
	pop {r2}                            @ Restore R2
	pop {r3}                            @ Restore R3
	bx r14

Input_file_address: .word Input_file


## Reverse_List function
## Receives List in R0
## Returns the list reversed in R0
Reverse_List:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	mov r1, r0                          @ Set HEAD
	mov r0, #0                          @ ROOT = NULL
Reverse_List_Loop:
	cmp r1, #0                          @ WHILE HEAD != NULL
	beq Reverse_List_Done               @ Stop otherwise

	ldr r2, [r1]                        @ NEXT = HEAD->NEXT
	str r0, [r1]                        @ HEAD->NEXT = ROOT
	mov r0, r1                          @ ROOT = HEAD
	mov r1, r2                          @ HEAD = NEXT
	b Reverse_List_Loop                 @ Keep Going

Reverse_List_Done:
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14


## recursive_output function
## Receives list in R0
## walks the list and prints the I->S for all nodes backwards
## Uses R1 for I
recursive_output:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	cmp r0, #0                          @ Check for NULL
	beq recursive_output_done           @ Skip the work
	mov r1, r0                          @ I = Head

	ldr r0, [r1]                        @ Iterate to next Token
	push {r14}
	bl recursive_output                 @ Recurse
	pop {r14}

	ldr r0, [r1, #8]                    @ Using S
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}

recursive_output_done:
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14


## File_Print function
## Receives CHAR* in R0
## calls fputc for every non-null char
File_Print:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	mov r1, r0                          @ Protect S
	cmp r0, #0                          @ Protect against nulls
	beq File_Print_Done                 @ Simply don't try to print them
File_Print_Loop:
	ldrb r0, [r1]                       @ Read byte
	cmp r0, #0                          @ Check for NULL
	beq File_Print_Done                 @ Stop at NULL

	push {r14}
	bl fputc                            @ write it
	pop {r14}
	add r1, #1                          @ S = S + 1
	b File_Print_Loop                   @ Keep going

File_Print_Done:
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14


## fputc function
## receives CHAR in R0 and load FILE* from [OUTPUT_FILE]
## writes char and returns
fputc:
	push {r3}                           @ Protect R3
	push {r2}                           @ protect R2
	push {r1}                           @ protect R1
	push {r0}                           @ We are writing r0
	mov r1, r13                         @ Get stack address
	ldr r8, Output_file_address
	ldr r0, [r8]                        @ Write to target file
	mov r7, #4                          @ the syscall number for write
	mov r2, #1                          @ set the size of chars we want
	svc #0                              @ call the Kernel
	pop {r0}                            @ Restore stack
	pop {r1}                            @ Restore R1
	pop {r2}                            @ Restore R2
	pop {r3}                            @ Restore R3
	bx r14

Output_file_address: .word Output_file


## program function
## receives nothing, returns nothing
## Uses R0 for type_size
program:
	## The binary initialized the globals to null, so we can skip those steps
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2

new_type:
	ldr r0, [r12]                       @ Using global_token
	cmp r0, #0                          @ Check if NULL
	beq program_done                    @ Be done if null

	ldr r1, [r0, #8]                    @ GLOBAL_TOKEN->S
	adr r0, constant                    @ "CONSTANT"
	push {r14}
	bl match                            @ IF GLOBAL_TOKEN->S == "CONSTANT"
	pop {r14}
	cmp r0, #0                          @ If true
	bne program_else                    @ Looks like not a constant

	## Deal with minimal constant case
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->next
	str r0, [r12]                       @ global_token = global_token->next

	ldr r0, [r0, #8]                    @ global_token->S
	mov r1, #0                          @ NULL
	ldr r8, global_constant_list_address
	ldr r2, [r8]                        @ global_constant_list
	push {r14}
	bl sym_declare                      @ Declare that constant
	pop {r14}
	ldr r8, global_constant_list_address
	str r0, [r8]                        @ global_constant_list = sym_declare(global_token->s, NULL, global_constant_list);

	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1]                        @ global_token->next
	str r1, [r0, #16]                   @ global_constant_list->arguments = global_token->next

	ldr r1, [r1]                        @ global_token->next->next
	str r1, [r12]                       @ global_token = global_token->next->next;
	b new_type                          @ go around again

program_else:
	push {r14}
	bl type_name                        @ Figure out the type_size
	pop {r14}
	cmp r0, #0                          @ IF NULL == type_size
	beq new_type                        @ it was a new type

	## Add to global symbol table
	mov r1, r0                          @ put type_size in the right spot
	ldr r0, [r12]                       @ Using global token
	ldr r0, [r0, #8]                    @ global_token->S
	ldr r8, global_symbol_list_address_0
	ldr r2, [r8]                        @ Using global_symbol_list
	push {r14}
	bl sym_declare                      @ Declare symbol
	pop {r14}
	ldr r8, global_symbol_list_address_0
	str r0, [r8]                        @ global_symbol_list = sym_declare(global_token->s, type_size, global_symbol_list);
	ldr r1, [r12]                       @ Using global token
	ldr r1, [r1]                        @ global_token->next
	str r1, [r12]                       @ global_token = global_token->next

	ldr r1, [r12]                       @ Using global token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, semicolon_0                 @ ";"
	push {r14}
	bl match                            @ if(match(";", global_token->s))
	pop {r14}
	cmp r0, #0                          @ If true
	bne program_function                @ looks like not a match

	## Deal with the global variable
	ldr r8, globals_list_address
	ldr r1, [r8]                        @ Using globals_list
	adr r0, program_string_0            @ ":GLOBAL_"
	push {r14}
	bl emit                             @ Emit it
	pop {r14}
	mov r1, r0                          @ update globals_list

	ldr r0, [r12]                       @ Using global token
	ldr r0, [r0, #4]                    @ global token->prev
	ldr r0, [r0, #8]                    @ global token->prev->s
	push {r14}
	bl emit                             @ Emit it
	pop {r14}

	mov r1, r0                          @ update globals_list
	adr r0, program_string_1            @ "\nNULL\n"
	push {r14}
	bl emit                             @ Emit it
	pop {r14}
	ldr r8, globals_list_address
	str r0, [r8]                        @ update globals_list

	ldr r0, [r12]                       @ Using global token
	ldr r0, [r0]                        @ global_token->next
	str r0, [r12]                       @ global_token = global_token->next
	b new_type                          @ go around again

program_function:
	ldr r1, [r12]                       @ Using global token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, open_paren_0                @ "("
	push {r14}
	bl match                            @ if(match(";", global_token->s))
	pop {r14}
	cmp r0, #0                          @ If true
	bne program_error                   @ Otherwise deal with error case

	## Deal with function definition
	push {r14}
	bl declare_function                 @ Lets get the parsing rolling
	pop {r14}
	b new_type                          @ Keep looping through functions

program_error:
	## Deal with the case of something we don't support
	## NOT IMPLEMENTED

program_done:
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

## Strings needed by the program function
program_string_0: .asciz ":GLOBAL_"
.balign 4
program_string_1: .asciz "\nNULL\n"
.balign 4
semicolon_0: .asciz ";"
.balign 4
open_paren_0: .asciz "("
.balign 4
constant: .asciz "CONSTANT"
.balign 4
globals_list_address: .word globals_list
global_constant_list_address: .word global_constant_list
global_symbol_list_address_0: .word global_symbol_list


## declare_function function
## Receives nothing and returns nothing
## Sets current function and adds it to the global function list
declare_function:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	mov r0, #0                          @ Using NULL
	ldr r8, current_count_address_0
	str r0, [r8]                        @ current_count = 0

	ldr r0, [r12]                       @ Using global token
	ldr r0, [r0, #4]                    @ global token->prev
	ldr r0, [r0, #8]                    @ global token->prev->s
	mov r1, #0                          @ NULL
	ldr r8, global_function_list_address_0
	ldr r2, [r8]                        @ global_function_list
	push {r14}
	bl sym_declare                      @ sym_declare(global_token->prev->s, NULL, global_function_list);
	pop {r14}
	str r0, [r11]                       @ function = sym_declare(global_token->prev->s, NULL, global_function_list);
	ldr r8, global_function_list_address_0
	str r0, [r8]                        @ global_function_list = function

	push {r14}
	bl collect_arguments                @ collect all of the function arguments
	pop {r14}

	ldr r0, [r12]                       @ Using global token
	ldr r0, [r0, #8]                    @ global token->s
	adr r1, semicolon_1                 @ ";"
	push {r14}
	bl match                            @ IF global token->s == ";"
	pop {r14}
	cmp r0, #0                          @ If true
	bne declare_function_full           @ It was a prototype

	## Deal with prototypes
	ldr r0, [r12]                       @ Using global token
	ldr r0, [r0]                        @ global token->next
	str r0, [r12]                       @ global token = global token->next
	b declare_function_done             @ Move on

declare_function_full:
	## Deal with full function definitions
	adr r0, declare_function_string_0   @ "# Defining function "
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	ldr r0, [r11]                       @ function
	ldr r0, [r0, #8]                    @ function->s
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	adr r0, declare_function_string_1   @ "\n:FUNCTION_"
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	ldr r0, [r11]                       @ function
	ldr r0, [r0, #8]                    @ function->s
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	adr r0, declare_function_string_3   @ "\n"
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	push {r14}
	bl statement                        @ Recursively get the function pieces
	pop {r14}

	ldr r8, output_list_address_1
	ldr r0, [r8]                        @ output
	ldr r0, [r0, #8]                    @ output->s
	adr r1, declare_function_string_2   @ "RETURN\n"
	push {r14}
	bl match                            @ IF output->s == "RETURN\n"
	pop {r14}
	cmp r0, #0                          @ If true we can skip adding it
	beq declare_function_done           @ otherwise we need to add it

	## Add the return to the end of a function lacking a return;
	adr r0, declare_function_string_2   @ "RETURN\n"
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

declare_function_done:
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

declare_function_string_0: .asciz "# Defining function "
.balign 4
declare_function_string_1: .asciz "\n:FUNCTION_"
.balign 4
declare_function_string_2: .asciz "RETURN\n"
.balign 4
declare_function_string_3: .asciz "\n"
.balign 4
semicolon_1: .asciz ";"
.balign 4
output_list_address_1: .word output_list
current_count_address_0: .word current_count
global_function_list_address_0: .word global_function_list


## collect_arguments function
## Receives nothing
## Returns Nothing
## Adds arguments to the function definition
## holds struct type* type_size in R2, then replace with struct token_list* a in R2 when type_size is used
collect_arguments:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->next
	str r0, [r12]                       @ global_token = global_token->next
collect_arguments_loop:
	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, close_paren_0               @ ")"
	push {r14}
	bl match                            @ IF global_token->S == ")"
	pop {r14}
	cmp r0, #0                          @ we reached the end
	beq collect_arguments_done          @ be done

	## deal with the case of there are arguments
	push {r14}
	bl type_name                        @ Get the type
	pop {r14}
	mov r2, r0                          @ put type_size safely out of the way

	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, close_paren_0               @ ")"
	push {r14}
	bl match                            @ IF global_token->S == ")"
	pop {r14}
	cmp r0, #0                          @ is a foo(int, char,void) case
	beq collect_arguments_common        @ deal with commas

	## Trying second else
	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, comma                       @ ","
	push {r14}
	bl match                            @ IF global_token->S == ","
	pop {r14}
	cmp r0, #0                          @ then deal with the common
	beq collect_arguments_common        @ case of commas between arguments

	## deal with foo(int a, char b)
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	mov r1, r2                          @ put type_size in the right place
	ldr r2, [r11]                       @ Using function
	ldr r2, [r2, #16]                   @ function->args
	push {r14}
	bl sym_declare                      @ sym_declare(global_token->s, type_size, function->arguments);
	pop {r14}
	mov r2, r0                          @ put a in a safe place

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #16]                   @ function->args
	cmp r0, #0                          @ IF function->args == NULL
	bne collect_arguments_another       @ otherwise it isn't the first

	## Deal with the case of first argument in the function
	mov r0, #-4                         @ -4
	str r0, [r2, #16]                   @ a->depth = -4
	b collect_arguments_next            @ get to next

collect_arguments_another:
	## deal with the case of non-first arguments
	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #16]                   @ function->args
	ldr r0, [r0, #16]                   @ function->args->depth
	sub r0, #4                          @ function->args->depth - 4
	str r0, [r2, #16]                   @ a->depth = function->args->depth - 4

collect_arguments_next:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->next
	str r0, [r12]                       @ global_token = global_token->next

	ldr r0, [r11]                       @ Using function
	str r2, [r0, #16]                   @ function->args = a

collect_arguments_common:
	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, comma                       @ ","
	push {r14}
	bl match                            @ IF global_token->S == ","
	pop {r14}
	cmp r0, #0                          @ then deal with the comma
	bne collect_arguments_loop          @ otherwise loop

	## keep foo(bar(), #1) expressions working
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->next
	str r0, [r12]                       @ global_token = global_token->next
	b collect_arguments_loop            @ keep going

collect_arguments_done:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->next
	str r0, [r12]                       @ global_token = global_token->next
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

close_paren_0: .asciz ")"
.balign 4
comma: .asciz ","
.balign 4


## statement function
## Receives nothing
## Returns nothing
## Walks down global_token recursively to collect the contents of the function
statement:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2

	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, open_curly_brace_0          @ "{"
	push {r14}
	bl match                            @ IF global_token->S == "{"
	pop {r14}
	bne statement_label                 @ otherwise try label

	## deal with { statement }
	push {r14}
	bl recursive_statement              @ Statements inside of statements for days
	pop {r14}
	b statement_done                    @ Be done

statement_label:
	ldrb r0, [r1]                       @ global_token->S[0]
	cmp r0, #58                         @ IF global_token->S == ':'
	bne statement_local                 @ otherwise try locals

	## deal with labels
	mov r0, r1                          @ put global_token->S in the right spot
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	adr r0, statement_string_0          @ Using "\t#C goto label\n"
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->next
	str r0, [r12]                       @ global_token = global_token->next
	b statement_done                    @ be done

statement_local:
	mov r0, r1                          @ put global_token->S in the right place
	ldr r1, prim_types_address          @ pointer to primative types
	push {r14}
	bl lookup_type                      @ See if found
	pop {r14}
	cmp r0, #0                          @ IF NULL == lookup_type(global_token->S, prim_types)
	bne statement_local_success         @ Sweet a new local

	## Second chance
	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, struct_0                    @ "struct"
	push {r14}
	bl match                            @ IF global_token->S == "struct"
	pop {r14}
	cmp r0, #0                          @ then we are a local
	bne statement_if                    @ otherwise try IF

statement_local_success:
	push {r14}
	bl collect_local                    @ Grab those locals
	pop {r14}
	b statement_done                    @ be done

statement_if:
	adr r0, if_string                   @ Using "if"
	push {r14}
	bl match                            @ IF global_token->S == "if"
	pop {r14}
	cmp r0, #0                          @ then we have an if statement
	bne statement_do                    @ otherwise try DO

	## Deal with IF statement
	push {r14}
	bl process_if                       @ DO IT
	pop {r14}
	b statement_done                    @ be done

statement_do:
	adr r0, do_string                   @ Using "do"
	push {r14}
	bl match                            @ IF global_token->S == "do"
	pop {r14}
	cmp r0, #0                          @ then we have a do statement
	bne statement_while                 @ otherwise try WHILE

	## Deal with DO statement
	push {r14}
	bl process_do                       @ DO IT
	pop {r14}
	b statement_done                    @ be done

statement_while:
	adr r0, while_string_0              @ Using "while"
	push {r14}
	bl match                            @ IF global_token->S == "while"
	pop {r14}
	cmp r0, #0                          @ then we have a while statement
	bne statement_for                   @ otherwise try FOR

	## Deal with WHILE statement
	push {r14}
	bl process_while                    @ DO IT
	pop {r14}
	b statement_done                    @ be done

statement_for:
	adr r0, for_string                  @ Using "for"
	push {r14}
	bl match                            @ IF global_token->S == "for"
	pop {r14}
	cmp r0, #0                          @ then we have a for statement
	bne statement_asm                   @ otherwise try ASM

	## Deal with FOR statement
	push {r14}
	bl process_for                      @ DO IT
	pop {r14}
	b statement_done                    @ be done

statement_asm:
	adr r0, asm_string                  @ Using "asm"
	push {r14}
	bl match                            @ IF global_token->S == "asm"
	pop {r14}
	cmp r0, #0                          @ then we have an asm statement
	bne statement_goto                  @ otherwise try GOTO

	## Deal with ASM statement
	push {r14}
	bl process_asm                      @ Hit it
	pop {r14}
	b statement_done                    @ be done

statement_goto:
	adr r0, goto_string                 @ Using "goto"
	push {r14}
	bl match                            @ IF global_token->S == "goto"
	pop {r14}
	cmp r0, #0                          @ then we have a goto statement
	bne statement_return                @ Otherwise try RETURN

	## Deal with GOTO statement
	adr r0, statement_string_1          @ Using "JUMP %"
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->next
	str r0, [r12]                       @ global_token = global_token->next

	ldr r0, [r0, #8]                    @ global_token->S
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	adr r0, statement_string_2          @ Using "\n"
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->next
	str r0, [r12]                       @ global_token = global_token->next

	adr r0, statement_string_4          @ Using "ERROR in statement\nMissing ;\n"
	adr r1, semicolon_2                 @ Using ";"
	push {r14}
	bl require_match                    @ Make sure it has the required
	pop {r14}
	b statement_done                    @ Be done

statement_return:
	adr r0, return_string               @ Using "return"
	push {r14}
	bl match                            @ IF global_token->S == "return"
	pop {r14}
	cmp r0, #0                          @ then we have a return statement
	bne statement_break                 @ Otherwise try BREAK

	## Deal with RETURN Statement
	push {r14}
	bl return_result                    @ Return anything they want
	pop {r14}
	b statement_done                    @ be done

statement_break:
	adr r0, break_string                @ Using "break"
	push {r14}
	bl match                            @ IF global_token->S == "break"
	pop {r14}
	cmp r0, #0                          @ then we have a break statement
	bne statement_continue              @ Otherwise try CONTINUE

	## Deal with BREAK statement
	push {r14}
	bl process_break                    @ Lets do some damage
	pop {r14}
	b statement_done                    @ be done

statement_continue:
	adr r0, continue_string             @ Using "continue"
	push {r14}
	bl match                            @ IF global_token->S == "continue"
	pop {r14}
	cmp r0, #0                          @ then we have a continue statement
	bne statement_else                  @ Otherwise we are punting to an expression

	## Deal with CONTINUE statement
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->next
	str r0, [r12]                       @ global_token = global_token->next

	adr r0, statement_string_3          @ Using "\n#continue statement\n"
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	adr r0, statement_string_4          @ Using "ERROR in statement\nMissing ;\n"
	adr r1, semicolon_2                 @ Using ";"
	push {r14}
	bl require_match                    @ Don't forget the ";"
	pop {r14}
	b statement_done                    @ Be done

statement_else:
	push {r14}
	bl expression                       @ Collect expression
	pop {r14}
	adr r0, statement_string_4          @ Using "ERROR in statement\nMissing ;\n"
	adr r1, semicolon_2                 @ Using ";"
	push {r14}
	bl require_match                    @ make sure we have it
	pop {r14}

statement_done:
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

semicolon_2: .asciz ";"
.balign 4
struct_0: .asciz "struct"
.balign 4
open_curly_brace_0: .asciz "{"
.balign 4
if_string: .asciz "if"
.balign 4
do_string: .asciz "do"
.balign 4
while_string_0: .asciz "while"
.balign 4
for_string: .asciz "for"
.balign 4
asm_string: .asciz "asm"
.balign 4
goto_string: .asciz "goto"
.balign 4
return_string: .asciz "return"
.balign 4
break_string: .asciz "break"
.balign 4
continue_string: .asciz "continue"
.balign 4
statement_string_0: .asciz "\t#C goto label\n"
.balign 4
statement_string_1: .asciz "JUMP %"
.balign 4
statement_string_2: .asciz "\n"
.balign 4
statement_string_3: .asciz "\n#continue statement\n"
.balign 4
statement_string_4: .asciz "ERROR in statement\nMissing ;\n"
.balign 4
prim_types_address: .word prim_types


## recursive_statement function
## Receives nothing
## Returns nothing
## Walks the global_token list to build the contents of statements
## Uses struct token_list* frame in R2
recursive_statement:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->next
	str r0, [r12]                       @ global_token = global_token->next

	ldr r2, [r11]                       @ Using function
	ldr r2, [r2, #4]                    @ frame = function->locals

recursive_statement_loop:
	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, close_curly_brace           @ Using "}"
	push {r14}
	bl match                            @ IF global_token->S == "}"
	pop {r14}
	cmp r0, #0                          @ Then we are done recursing
	beq recursive_statement_cleanup     @ and then we clean up

	## Deal with the recursive calls
	push {r14}
	bl statement                        @ Deal with another statement
	pop {r14}
	b recursive_statement_loop          @ loop some more

recursive_statement_cleanup:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->next
	str r0, [r12]                       @ global_token = global_token->next

	adr r0, recursive_statement_string_0 @ Using "RETURN\n"
	ldr r8, output_list_address_2
	ldr r1, [r8]                        @ Using output
	ldr r1, [r1, #8]                    @ output->S
	push {r14}
	bl match                            @ IF output->S == "RETURN\n"
	pop {r14}
	cmp r0, #0                          @ Then we can skip the clean up
	beq recursive_statement_done        @ and be done

	## Deal with cleanup
	ldr r1, [r11]                       @ Using function
	ldr r1, [r1, #4]                    @ i = function->locals
	adr r0, recursive_statement_string_1 @ Using "POP_ebx\t# _recursive_statement_locals\n"

recursive_statement_locals:
	cmp r1, r2                          @ IF frame != i
	beq recursive_statement_done        @ Otherwise be done

	## Lets emit
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}
	ldr r1, [r1]                        @ i = i->next
	b recursive_statement_locals        @ keep going

recursive_statement_done:
	ldr r0, [r11]                       @ Using function
	str r2, [r0, #4]                    @ function->locals = frame
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

recursive_statement_string_0: .asciz "RETURN\n"
.balign 4
recursive_statement_string_1: .asciz "POP_ebx\t# _recursive_statement_locals\n"
.balign 4
close_curly_brace: .asciz "}"
.balign 4
output_list_address_2: .word output_list


## return_result function
## Receives nothing
## Returns nothing
## Cleans up function and generates return
## Also handles returning expressions
return_result:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->next
	str r0, [r12]                       @ global_token = global_token->next

	ldr r0, [r0, #8]                    @ global_token->S
	ldrb r0, [r0]                       @ global_token->S[0]
	cmp r0, #59                         @ If global_token->S[0] == ';'
	beq return_result_cleanup           @ Go straight to cleanup

	push {r14}
	bl expression                       @ get the expression we are returning
	pop {r14}

return_result_cleanup:
	adr r0, return_result_string_0      @ Using "ERROR in return_result\nMISSING ;\n"
	adr r1, semicolon_3                 @ Using ";"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	ldr r1, [r11]                       @ Using function
	ldr r1, [r1, #4]                    @ function->locals
	adr r0, return_result_string_1      @ Using "POP_ebx\t# _return_result_locals\n"
return_result_locals:
	cmp r1, #0                          @ IF NULL == i
	beq return_result_done              @ Be done

	push {r14}
	bl emit_out                         @ Emit out pop
	pop {r14}
	ldr r1, [r1]                        @ i = i->NEXT
	b return_result_locals              @ Keep going

return_result_done:
	adr r0, return_result_string_2      @ Using "RETURN\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

return_result_string_0: .asciz "ERROR in return_result\nMISSING ;\n"
.balign 4
return_result_string_1: .asciz "POP_ebx\t# _return_result_locals\n"
.balign 4
return_result_string_2: .asciz "RETURN\n"
.balign 4
semicolon_3: .asciz ";"
.balign 4


## collect_local function
## Receives nothing
## Returns nothing
## Walks global_token list to create function locals
## Uses R2 for struct token_list* A
collect_local:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r14}
	bl type_name                        @ Get the local's type
	pop {r14}

	mov r1, r0                          @ Put struct type* type_size in the right place
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	ldr r2, [r11]                       @ Using function
	ldr r2, [r2, #4]                    @ function->locals
	push {r14}
	bl sym_declare                      @ Declare it
	pop {r14}
	mov r2, r0                          @ put it away safely

	## Try for main
	adr r0, main_string                 @ Using "main"
	ldr r1, [r11]                       @ Using function
	ldr r1, [r1, #8]                    @ function->S
	push {r14}
	bl match                            @ IF match("main", function->s)
	pop {r14}
	cmp r0, #0                          @ possible
	bne collect_local_fresh             @ try to see if fresh function

	## Ok we are in main, now to see if main is fresh
	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #4]                    @ function->locals
	cmp r0, #0                          @ IF NULL == function->locals
	bne collect_local_fresh             @ try to see if fresh function

	## Sweet we are in a fresh main
	mov r0, #-20                        @ We start at -20
	str r0, [r2, #16]                   @ a->DEPTH = -20
	b collect_local_common              @ Go to the commons

collect_local_fresh:
	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #16]                   @ function->args
	cmp r0, #0                          @ IF NULL == function->locals
	bne collect_local_first             @ Otherwise see if first

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #4]                    @ function->locals
	cmp r0, #0                          @ IF NULL == function->locals
	bne collect_local_first             @ Otherwise try first

	## Sweet we are in a fresh function
	mov r0, #-8                         @ We start at -8
	str r0, [r2, #16]                   @ a->DEPTH = -8
	b collect_local_common              @ Go to the commons

collect_local_first:
	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #4]                    @ function->locals
	cmp r0, #0                          @ IF NULL == function->locals
	bne collect_local_else              @ Looks like we are just another local

	## Ok we are the first local
	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #16]                   @ function->args
	ldr r0, [r0, #16]                   @ function->args->depth
	sub r0, #8                          @ function->arguments->depth - 8
	str r0, [r2, #16]                   @ a->DEPTH = function->arguments->depth - 8
	b collect_local_common              @ Go to the commons

collect_local_else:
	## Always the last to know
	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #4]                    @ function->locals
	ldr r0, [r0, #16]                   @ function->locals->depth
	sub r0, #4                          @ function->locals->depth - 4
	str r0, [r2, #16]                   @ a->DEPTH = function->locals->depth - 4

collect_local_common:
	ldr r0, [r11]                       @ Using function

	str r2, [r0, #4]                    @ function->locals = a
	ldr r2, [r2, #8]                    @ a->S

	adr r0, collect_local_string_0      @ Using "# Defining local "
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	adr r0, collect_local_string_1      @ Using "\n"
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	ldr r1, [r0, #8]                    @ global_token->S
	adr r0, equal_0                     @ Using "="
	push {r14}
	bl match                            @ IF match("=", global_token->s)
	pop {r14}
	cmp r0, #0                          @ Deal with assignment
	bne collect_local_done              @ Otherwise finish it

	## Deal with assignment
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	push {r14}
	bl expression                       @ Recurse
	pop {r14}

collect_local_done:
	adr r0, collect_local_string_2      @ Using "ERROR in collect_local\nMissing ;\n"
	adr r1, semicolon_4                 @ Using ";"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	adr r0, collect_local_string_3      @ Using "PUSH_eax\t#"
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	mov r0, r2                          @ put A->S where it belongs
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	adr r0, collect_local_string_1      @ Using "\n"
	push {r14}
	bl emit_out                         @ emit it
	pop {r14}

	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

collect_local_string_0: .asciz "# Defining local "
.balign 4
collect_local_string_1: .asciz "\n"
.balign 4
collect_local_string_2: .asciz "ERROR in collect_local\nMissing ;\n"
.balign 4
collect_local_string_3: .asciz "PUSH_eax\t#"
.balign 4
semicolon_4: .asciz ";"
.balign 4
equal_0: .asciz "="
.balign 4
main_string: .asciz "main"
.balign 4


## process_asm function
## Receives nothing
## Returns nothing
## Simply inlines the asm statements
## Uses R1 for global_token temp storage
process_asm:
	push {r1}                           @ Protect R1
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	adr r0, process_asm_string_0        @ Using "ERROR in process_asm\nMISSING (\n"
	adr r1, open_paren_1                @ Using "("
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	ldr r1, [r12]                       @ Using global_token
process_asm_iter:
	ldr r0, [r1, #8]                    @ global_token->S
	ldrb r0, [r0]                       @ global_token->S[0]
	cmp r0, #34                         @ IF global_token->S[0] == '\"'
	bne process_asm_done                @ Otherwise be done

	ldr r0, [r1, #8]                    @ global_token->S
	add r0, #1                          @ global_token->S + 1
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, process_asm_string_1        @ Using "\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r1, [r1]                        @ global_token->NEXT
	str r1, [r12]                       @ global_token = global_token->NEXT
	b process_asm_iter                  @ keep going

process_asm_done:
	adr r0, process_asm_string_2        @ Using "ERROR in process_asm\nMISSING )\n"
	adr r1, close_paren_1               @ Using ")"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	adr r0, process_asm_string_3        @ Using "ERROR in process_asm\nMISSING ;\n"
	adr r1, semicolon_5                 @ Using ";"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	pop {r1}                            @ Restore R1
	bx r14

process_asm_string_0: .asciz "ERROR in process_asm\nMISSING (\n"
.balign 4
process_asm_string_1: .asciz "\n"
.balign 4
process_asm_string_2: .asciz "ERROR in process_asm\nMISSING )\n"
.balign 4
process_asm_string_3: .asciz "ERROR in process_asm\nMISSING ;\n"
.balign 4
semicolon_5: .asciz ";"
.balign 4
open_paren_1: .asciz "("
.balign 4
close_paren_1: .asciz ")"
.balign 4


## process_if function
## Receives nothing
## Returns Nothing
## Increments current_count recurses into expression + statement
## Uses R2 for char* NUMBER_STRING
process_if:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	ldr r8, current_count_address_1
	ldr r0, [r8]                        @ Using current count
	mov r1, r0                          @ Preparing for update
	add r1, #1                          @ current_count + 1
	ldr r8, current_count_address_1
	str r1, [r8]                        @ current_count = current_count + 1
	push {r14}
	bl numerate_number                  @ convert to string
	pop {r14}
	mov r2, r0                          @ put NUMBER_STRING in place

	adr r0, process_if_string_0         @ Using "# IF_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	adr r0, process_if_string_1         @ Using "ERROR in process_if\nMISSING (\n"
	adr r1, open_paren_2                @ Using "("
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	push {r14}
	bl expression                       @ Recurse to get the IF(...) part
	pop {r14}

	adr r0, process_if_string_2         @ Using "TEST\nJUMP_EQ %ELSE_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	adr r0, process_if_string_3         @ Using "ERROR in process_if\nMISSING )\n"
	adr r1, close_paren_2               @ Using ")"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	push {r14}
	bl statement                        @ Recursive to get the IF(){...} part
	pop {r14}

	adr r0, process_if_string_4         @ Using "JUMP %_END_IF_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	adr r0, process_if_string_5         @ Using ":ELSE_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, else_string                 @ Using "else"
	push {r14}
	bl match                            @ IF global_token->S == "else"
	pop {r14}
	cmp r0, #0                          @ Then we need to collect the else too
	bne process_if_done                 @ Otherwise finish up

	## deal with else statement
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	push {r14}
	bl statement                        @ Recurse to get the ELSE {...} part
	pop {r14}

process_if_done:
	adr r0, process_if_string_6         @ Using ":_END_IF_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

process_if_string_0: .asciz "# IF_"
.balign 4
process_if_string_1: .asciz "ERROR in process_if\nMISSING (\n"
.balign 4
process_if_string_2: .asciz "TEST\nJUMP_EQ %ELSE_"
.balign 4
process_if_string_3: .asciz "ERROR in process_if\nMISSING )\n"
.balign 4
process_if_string_4: .asciz "JUMP %_END_IF_"
.balign 4
process_if_string_5: .asciz ":ELSE_"
.balign 4
process_if_string_6: .asciz ":_END_IF_"
.balign 4
open_paren_2: .asciz "("
.balign 4
close_paren_2: .asciz ")"
.balign 4
else_string: .asciz "else"
.balign 4
current_count_address_1: .word current_count


## save_break_frame microfunction
## Overwrites R0 and R1
## Saves break frame on stack
## Returns to caller
save_break_frame:
	ldr r8, break_frame_address
	ldr r0, [r8]                        @ Get break_frame
	push {r0}                           @ Store as nested_locals
	ldr r8, break_target_head_address
	ldr r0, [r8]                        @ Get break_target_head
	push {r0}                           @ Store as nested_break_head
	ldr r8, break_target_func_address
	ldr r0, [r8]                        @ Get break_target_func
	push {r0}                           @ Store as nested_break_func
	ldr r8, break_target_num_address
	ldr r0, [r8]                        @ Get break_target_num
	push {r0}                           @ Store as nested_break_num
	bx r14                              @ Return to caller

break_frame_address: .word break_frame
break_target_func_address: .word break_target_func
break_target_head_address: .word break_target_head
break_target_num_address: .word break_target_num


## restore_break_frame microfunction
## Overwrites R0 and R1
## Restores break frame from stack
## Returns to caller
restore_break_frame:
	pop {r0}                            @ Get nested_break_num
	ldr r8, break_target_num_address
	str r0, [r8]                        @ Restore break_target_num
	pop {r0}                            @ Get nested_break_func
	ldr r8, break_target_func_address
	str r0, [r8]                        @ Restore break_target_func
	pop {r0}                            @ Get nested_break_head
	ldr r8, break_target_head_address
	str r0, [r8]                        @ Restore break_target_head
	pop {r0}                            @ Get nested_locals
	ldr r8, break_frame_address
	str r0, [r8]                        @ Restore break_frame
	bx r14                              @ Return to caller


## set_break_frame microfunction
## Receives char* head in R0 and char* num in R1
## Overwrites R0 and R1
## Returns to calling function
set_break_frame:
	ldr r8, break_target_head_address
	str r0, [r8]                        @ update break_target_head
	ldr r8, break_target_num_address
	str r1, [r8]                        @ update break_target_num
	ldr r1, [r11]                       @ Using function
	ldr r0, [r1, #4]                    @ function->LOCALS
	ldr r8, break_frame_address
	str r0, [r8]                        @ break_frame = function->LOCALS
	ldr r0, [r1, #8]                    @ function->S
	ldr r8, break_target_func_address
	str r0, [r8]                        @ break_target_func = function->S
	bx r14                              @ Return to sender


## process_do function
## Receives Nothing
## Returns Nothing
## Increments current_count and leverages save/restore_break_frame pieces
## Uses R2 for char* NUMBER_STRING
process_do:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r14}
	bl save_break_frame                 @ Save the frame
	pop {r14}

	ldr r8, current_count_address_2
	ldr r0, [r8]                        @ Using current count
	mov r1, r0                          @ Preparing for update
	add r1, #1                          @ current_count + 1
	ldr r8, current_count_address_2
	str r1, [r8]                        @ current_count = current_count + 1
	push {r14}
	bl numerate_number                  @ convert to string
	pop {r14}
	mov r2, r0                          @ put NUMBER_STRING in place

	adr r0, process_do_string_0         @ Using "DO_END_"
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl set_break_frame                  @ Set the frame
	pop {r14}

	adr r0, process_do_string_1         @ Using ":DO_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	push {r14}
	bl statement                        @ Do the DO {...} part
	pop {r14}

	adr r0, process_do_string_2         @ Using "ERROR in process_do\nMISSING while\n"
	adr r1, while_string_1              @ Using "while"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	adr r0, process_do_string_3         @ Using "ERROR in process_do\nMISSING (\n"
	adr r1, open_paren_3                @ Using "("
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	push {r14}
	bl expression                       @ Do the WHILE (...) part
	pop {r14}

	adr r0, process_do_string_4         @ Using "ERROR in process_do\nMISSING )\n"
	adr r1, close_paren_3               @ Using ")"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	adr r0, process_do_string_5         @ Using "ERROR in process_do\nMISSING ;\n"
	adr r1, semicolon_6                 @ Using ";"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	adr r0, process_do_string_6         @ Using "TEST\nJUMP_NE %DO_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	adr r0, process_do_string_7         @ Using ":DO_END_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	push {r14}
	bl restore_break_frame              @ Restore the old break frame
	pop {r14}

	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

process_do_string_0: .asciz "DO_END_"
.balign 4
process_do_string_1: .asciz ":DO_"
.balign 4
process_do_string_2: .asciz "ERROR in process_do\nMISSING while\n"
.balign 4
process_do_string_3: .asciz "ERROR in process_do\nMISSING (\n"
.balign 4
process_do_string_4: .asciz "ERROR in process_do\nMISSING )\n"
.balign 4
process_do_string_5: .asciz "ERROR in process_do\nMISSING ;\n"
.balign 4
process_do_string_6: .asciz "TEST\nJUMP_NE %DO_"
.balign 4
process_do_string_7: .asciz ":DO_END_"
.balign 4
semicolon_6: .asciz ";"
.balign 4
open_paren_3: .asciz "("
.balign 4
close_paren_3: .asciz ")"
.balign 4
while_string_1: .asciz "while"
.balign 4
current_count_address_2: .word current_count


## process_while function
## Receives nothing
## Returns nothing
## Increments current_count and leverages save/restore_break_frame pieces
## Uses R2 for char* NUMBER_STRING
process_while:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r14}
	bl save_break_frame                 @ Save break_frame
	pop {r14}

	ldr r8, current_count_address_2
	ldr r0, [r8]                        @ Using current count
	mov r1, r0                          @ Preparing for update
	add r1, #1                          @ current_count + 1
	str r1, [r8]                        @ current_count = current_count + 1
	push {r14}
	bl numerate_number                  @ convert to string
	pop {r14}
	mov r2, r0                          @ put NUMBER_STRING in place

	adr r0, process_while_string_0      @ Using "END_WHILE_"
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl set_break_frame                  @ Set it and forget it
	pop {r14}

	adr r0, process_while_string_1      @ Using ":WHILE_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	adr r0, process_while_string_2      @ Using "ERROR in process_while\nMISSING (\n"
	adr r1, open_paren_4                @ Using "("
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	push {r14}
	bl expression                       @ Deal with the WHILE (...) part
	pop {r14}

	adr r0, process_while_string_3      @ Using "TEST\nJUMP_EQ %END_WHILE_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	adr r0, process_while_string_4      @ Using "# THEN_while_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	adr r0, process_while_string_5      @ Using "ERROR in process_while\nMISSING )\n"
	adr r1, close_paren_4               @ Using ")"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	push {r14}
	bl statement                        @ Deal with the {....} part
	pop {r14}

	adr r0, process_while_string_6      @ Using "JUMP %WHILE_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	adr r0, process_while_string_7      @ Using ":END_WHILE_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	push {r14}
	bl restore_break_frame              @ Restore the old break frame
	pop {r14}

	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

process_while_string_0: .asciz "END_WHILE_"
.balign 4
process_while_string_1: .asciz ":WHILE_"
.balign 4
process_while_string_2: .asciz "ERROR in process_while\nMISSING (\n"
.balign 4
process_while_string_3: .asciz "TEST\nJUMP_EQ %END_WHILE_"
.balign 4
process_while_string_4: .asciz "# THEN_while_"
.balign 4
process_while_string_5: .asciz "ERROR in process_while\nMISSING )\n"
.balign 4
process_while_string_6: .asciz "JUMP %WHILE_"
.balign 4
process_while_string_7: .asciz ":END_WHILE_"
.balign 4
open_paren_4: .asciz "("
.balign 4
close_paren_4: .asciz ")"
.balign 4


## process_for function
## Receives Nothing
## Returns Nothing
## Increments current_count and leverages save/restore_break_frame pieces
## Uses R2 for char* NUMBER_STRING
process_for:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r14}
	bl save_break_frame                 @ Save the frame
	pop {r14}

	ldr r8, current_count_address_3
	ldr r0, [r8]                        @ Using current count
	mov r1, r0                          @ Preparing for update
	add r1, #1                          @ current_count + 1
	str r1, [r8]                        @ current_count = current_count + 1
	push {r14}
	bl numerate_number                  @ convert to string
	pop {r14}
	mov r2, r0                          @ put NUMBER_STRING in place

	adr r0, process_for_string_0        @ Using "FOR_END_"
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl set_break_frame                  @ Set it and forget it
	pop {r14}

	adr r0, process_for_string_1        @ Using "# FOR_initialization_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	adr r0, process_for_string_2        @ Using "ERROR in process_for\nMISSING (\n"
	adr r1, open_paren_5                @ Using "("
	push {r14}
	bl require_match                    @ Make Sure we have it
	pop {r14}

	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, semicolon_7                 @ Using ";"
	push {r14}
	bl match                            @ IF global_token->S == ";"
	pop {r14}
	cmp r0, #0                          @ Then no initializer
	beq process_for_terminator          @ And skip getting the expression

	## Deal with FOR (...; case
	push {r14}
	bl expression                       @ Get the FOR ( ... ; part
	pop {r14}

process_for_terminator:
	adr r0, process_for_string_3        @ Using ":FOR_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	adr r0, process_for_string_4        @ Using "ERROR in process_for\nMISSING ;1\n"
	adr r1, semicolon_7                 @ Using ";"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	push {r14}
	bl expression                       @ Get the FOR ( ; ... ; Part
	pop {r14}

	adr r0, process_for_string_5        @ Using "TEST\nJUMP_EQ %FOR_END_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	adr r0, process_for_string_6        @ Using "JUMP %FOR_THEN_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	adr r0, process_for_string_7        @ Using ":FOR_ITER_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	adr r0, process_for_string_8        @ Using "ERROR in process_for\nMISSING ;2\n"
	adr r1, semicolon_7                 @ Using ";"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	push {r14}
	bl expression                       @ Get the FOR (;;...) part
	pop {r14}

	adr r0, process_for_string_9        @ Using "JUMP %FOR_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	adr r0, process_for_string_10       @ Using ":FOR_THEN_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	adr r0, process_for_string_11       @ Using "ERROR in process_for\nMISSING )\n"
	adr r1, close_paren_5               @ Using ")"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	push {r14}
	bl statement                        @ Get FOR (;;) {...} part
	pop {r14}

	adr r0, process_for_string_12       @ Using "JUMP %FOR_ITER_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	mov r1, r2                          @ Passing NUMBER_STRING
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	adr r0, process_for_string_13       @ Using ":FOR_END_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	push {r14}
	bl uniqueID_out                     @ uniqueID_out(function->s, number_string)
	pop {r14}

	push {r14}
	bl restore_break_frame              @ Restore the old break frame
	pop {r14}

	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

process_for_string_0: .asciz "FOR_END_"
.balign 4
process_for_string_1: .asciz "# FOR_initialization_"
.balign 4
process_for_string_2: .asciz "ERROR in process_for\nMISSING (\n"
.balign 4
process_for_string_3: .asciz ":FOR_"
.balign 4
process_for_string_4: .asciz "ERROR in process_for\nMISSING ;1\n"
.balign 4
process_for_string_5: .asciz "TEST\nJUMP_EQ %FOR_END_"
.balign 4
process_for_string_6: .asciz "JUMP %FOR_THEN_"
.balign 4
process_for_string_7: .asciz ":FOR_ITER_"
.balign 4
process_for_string_8: .asciz "ERROR in process_for\nMISSING ;2\n"
.balign 4
process_for_string_9: .asciz "JUMP %FOR_"
.balign 4
process_for_string_10: .asciz ":FOR_THEN_"
.balign 4
process_for_string_11: .asciz "ERROR in process_for\nMISSING )\n"
.balign 4
process_for_string_12: .asciz "JUMP %FOR_ITER_"
.balign 4
process_for_string_13: .asciz ":FOR_END_"
.balign 4
semicolon_7: .asciz ";"
.balign 4
open_paren_5: .asciz "("
.balign 4
close_paren_5: .asciz ")"
.balign 4
current_count_address_3: .word current_count


## process_break function
## Receives nothing
## Returns nothing
## Handles the break out of loops case
## Uses R1 for struct token_list* break_frame and R2 for struct token_list* I
process_break:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	ldr r8, break_target_head_address
	ldr r0, [r8]                        @ Catch big error
	cmp r0, #0                          @ IF(NULL == break_target_head)
	beq process_break_bad               @ I'm sorry Mr White but you have stage-3 lung cancer

	ldr r0, [r11]                       @ Using function
	ldr r2, [r0, #4]                    @ I = function->LOCALS
	ldr r8, break_frame_address
	ldr r1, [r8]                        @ Put break_frame in the right spot
	adr r0, process_break_string_1      @ Using "POP_ebx\t# break_cleanup_locals\n"

process_break_iter:
	cmp r2, #0                          @ IF (NULL == I)
	beq process_break_cleaned           @ We are done

	cmp r2, r1                          @ IF I != break_frame
	beq process_break_cleaned           @ We are done

	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}
	ldr r2, [r2]                        @ I = I->NEXT
	b process_break_iter                @ Keep looping

process_break_cleaned:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	adr r0, process_break_string_2      @ Using "JUMP %"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r8, break_target_head_address
	ldr r0, [r8]                        @ Get what we are in
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r8, break_target_func_address
	ldr r0, [r8]                        @ Get what function we are in
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, underline_0                 @ Using "_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r8, break_target_num_address
	ldr r0, [r8]                        @ Get dem digits
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, process_break_string_3      @ Using "\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, process_break_string_4      @ Using "ERROR in break statement\nMissing ;\n"
	adr r1, semicolon_8                 @ Using ";"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

process_break_bad:
	## Breaking badly
	mov r0, #2                          @ Using standard error
	ldr r8, Output_file_address_0
	str r0, [r8]                        @ write to standard error
#	bl line_error                       @ Write useful debug info
	mov r0, r2                          @ put S in the right place
	push {r14}
	bl File_Print                       @ print it
	pop {r14}

	adr r0, process_break_string_0      @ Ending string
	push {r14}
	bl File_Print                       @ print it
	pop {r14}
	b Exit_Failure                      @ Abort Hard

process_break_string_0: .asciz "Not inside of a loop or case statement"
.balign 4
process_break_string_1: .asciz "POP_ebx\t# break_cleanup_locals\n"
.balign 4
process_break_string_2: .asciz "JUMP %"
.balign 4
process_break_string_3: .asciz "\n"
.balign 4
process_break_string_4: .asciz "ERROR in break statement\nMissing ;\n"
.balign 4
semicolon_8: .asciz ";"
.balign 4
underline_0: .asciz "_"
.balign 4
Output_file_address_0: .word Output_file


## expression function
## Receives Nothing
## Returns Nothing
## Walks global_token and updates output_list
## Uses R0 and R1 for match and R2 for char* store
expression:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r14}
	bl bitwise_expr                     @ Collect bitwise expressions
	pop {r14}

	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, equal_1                     @ "="
	push {r14}
	bl match                            @ IF global_token->S == "="
	pop {r14}
	cmp r0, #0                          @ We have to deal with assignment
	bne expression_done                 @ Looks like nope

	## Deal with possible assignment
	adr r2, expression_string_1         @ Assume "STORE_CHAR\n" by default
	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #4]                    @ global_token->PREV
	ldr r1, [r1, #8]                    @ global_token->PREV->S
	adr r0, close_bracket_0             @ Using "]"
	push {r14}
	bl match                            @ IF global_token->S == "]"
	pop {r14}
	cmp r0, #0                          @ Then we might have a char
	bne expression_int                  @ Otherwise INT

	ldr r8, current_target_address
	ldr r1, [r8]                        @ Using current_target
	ldr r1, [r1, #24]                   @ current_target->NAME
	ldr r0, type_char_indirect_name_address @ Using "char*"
	push {r14}
	bl match                            @ Intentional inefficiency because I feel like it
	pop {r14}
	cmp r0, #0                          @ IF current_target->NAME == "char*"
	bne expression_int                  @ Do char anyway

	b expression_common                 @ Looks like we have to use "STORE_CHAR\n"

expression_int:
	adr r2, expression_string_0         @ Use "STORE_INTEGER\n"

expression_common:
	adr r0, expression                  @ Passing expression
	push {r14}
	bl common_recursion                 @ Recurse
	pop {r14}
	mov r0, r2                          @ Using Store
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}
	mov r0, #0                          @ Using NULL
	ldr r8, current_target_address
	str r0, [r8]                        @ current_target = NULL

expression_done:
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

expression_string_0: .asciz "STORE_INTEGER\n"
.balign 4
expression_string_1: .asciz "STORE_CHAR\n"
.balign 4
close_bracket_0: .asciz "]"
.balign 4
equal_1: .asciz "="
.balign 4
type_char_indirect_name_address: .word type_char_indirect_name
.balign 4


## bitwise_expr function
## Receives nothing
## Returns nothing
## Walks global_token list and updates output list
## Just calls other functions
bitwise_expr:
	push {r14}
	bl relational_expr                  @ Walk up the tree
	bl bitwise_expr_stub                @ Let general recursion do the work
	pop {r14}
	bx r14


## bitwise_expr_stub function
## Receives nothing
## Returns Nothing
## Just calls general_recursion a bunch
## Uses R0, R1, R2 and R3 for passing constants to general recursion
bitwise_expr_stub:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3

	adr r0, relational_expr             @ Using relational_expr
	adr r1, bitwise_expr_stub_string_0  @ Using "AND_eax_ebx\n"
	adr r2, bitwise_and                 @ Using "&"
	adr r3, bitwise_expr_stub           @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	adr r0, relational_expr             @ Using relational_expr
	adr r1, bitwise_expr_stub_string_0  @ Using "AND_eax_ebx\n"
	adr r2, logical_and                 @ Using "&&"
	adr r3, bitwise_expr_stub           @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	adr r0, relational_expr             @ Using relational_expr
	adr r1, bitwise_expr_stub_string_1  @ Using "OR_eax_ebx\n"
	adr r2, bitwise_or                  @ Using "|"
	adr r3, bitwise_expr_stub           @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	adr r0, relational_expr             @ Using relational_expr
	adr r1, bitwise_expr_stub_string_1  @ Using "OR_eax_ebx\n"
	adr r2, logical_or                  @ Using "||"
	adr r3, bitwise_expr_stub           @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	adr r0, relational_expr             @ Using relational_expr
	adr r1, bitwise_expr_stub_string_2  @ Using "XOR_ebx_eax_into_eax\n"
	adr r2, bitwise_xor                 @ Using "^"
	adr r3, bitwise_expr_stub           @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

bitwise_expr_stub_string_0: .asciz "AND_eax_ebx\n"
.balign 4
bitwise_expr_stub_string_1: .asciz "OR_eax_ebx\n"
.balign 4
bitwise_expr_stub_string_2: .asciz "XOR_ebx_eax_into_eax\n"
.balign 4
bitwise_and: .asciz "&"
.balign 4
logical_and: .asciz "&&"
.balign 4
bitwise_or: .asciz "|"
.balign 4
logical_or: .asciz "||"
.balign 4
bitwise_xor: .asciz "^"
.balign 4


## relational_expr function
## Receives nothing
## Returns Nothing
## Walks global_token list and updates output list
## just calls other function
relational_expr:
	push {r14}
	bl additive_expr                    @ Walk up the tree
	bl relational_expr_stub             @ Recurse
	pop {r14}
	bx r14


## relational_expr_stub function
## Receives nothing
## Returns Nothing
## Just calls general_recursion a bunch
## Uses R0, R1, R2 and R3 for passing constants to general recursion
relational_expr_stub:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3

	adr r0, additive_expr               @ Using additive_expr
	adr r1, relational_expr_stub_string_0 @ Using "CMP\nSETL\nMOVEZBL\n"
	adr r2, less_than_string            @ Using "<"
	adr r3, relational_expr_stub        @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	adr r0, additive_expr               @ Using additive_expr
	adr r1, relational_expr_stub_string_1 @ Using "CMP\nSETLE\nMOVEZBL\n"
	adr r2, less_than_equal_string      @ Using "<="
	adr r3, relational_expr_stub        @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	adr r0, additive_expr               @ Using additive_expr
	adr r1, relational_expr_stub_string_2 @ Using "CMP\nSETGE\nMOVEZBL\n"
	adr r2, greater_than_equal_string   @ Using ">="
	adr r3, relational_expr_stub        @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	adr r0, additive_expr               @ Using additive_expr
	adr r1, relational_expr_stub_string_3 @ Using "CMP\nSETG\nMOVEZBL\n"
	adr r2, greater_than_string         @ Using ">"
	adr r3, relational_expr_stub        @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	adr r0, additive_expr               @ Using additive_expr
	adr r1, relational_expr_stub_string_4 @ Using "CMP\nSETE\nMOVEZBL\n"
	adr r2, equal_to_string             @ Using "=="
	adr r3, relational_expr_stub        @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	adr r0, additive_expr               @ Using additive_expr
	adr r1, relational_expr_stub_string_5 @ Using "CMP\nSETNE\nMOVEZBL\n"
	adr r2, not_equal_string            @ Using "!="
	adr r3, relational_expr_stub        @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

relational_expr_stub_string_0: .asciz "CMP\nSETL\nMOVEZBL\n"
.balign 4
relational_expr_stub_string_1: .asciz "CMP\nSETLE\nMOVEZBL\n"
.balign 4
relational_expr_stub_string_2: .asciz "CMP\nSETGE\nMOVEZBL\n"
.balign 4
relational_expr_stub_string_3: .asciz "CMP\nSETG\nMOVEZBL\n"
.balign 4
relational_expr_stub_string_4: .asciz "CMP\nSETE\nMOVEZBL\n"
.balign 4
relational_expr_stub_string_5: .asciz "CMP\nSETNE\nMOVEZBL\n"
.balign 4
less_than_string: .asciz "<"
.balign 4
less_than_equal_string: .asciz "<="
.balign 4
greater_than_equal_string: .asciz ">="
.balign 4
greater_than_string: .asciz ">"
.balign 4
equal_to_string: .asciz "=="
.balign 4
not_equal_string: .asciz "!="
.balign 4


## additive_expr function
## Receives nothing
## Returns Nothing
## Walks global_token list and updates output list
## just calls other function
additive_expr:
	push {r14}
	bl postfix_expr                     @ Walk up the tree
	bl additive_expr_stub               @ Recurse
	pop {r14}
	bx r14


## additive_expr_stub function
## Receives nothing
## Returns Nothing
## Just calls general_recursion a bunch
## Uses R0, R1, R2 and R3 for passing constants to general recursion
additive_expr_stub:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3

	adr r0, postfix_expr                @ Using postfix_expr
	adr r1, additive_expr_stub_string_0 @ Using "ADD_ebx_to_eax\n"
	adr r2, plus_string                 @ Using "+"
	adr r3, additive_expr_stub          @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	adr r0, postfix_expr                @ Using postfix_expr
	adr r1, additive_expr_stub_string_1 @ Using "SUBTRACT_eax_from_ebx_into_ebx\nMOVE_ebx_to_eax\n"
	adr r2, minus_string                @ Using "-"
	adr r3, additive_expr_stub          @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	adr r0, postfix_expr                @ Using postfix_expr
	adr r1, additive_expr_stub_string_2 @ Using "MULTIPLY_eax_by_ebx_into_eax\n"
	adr r2, multiply_string             @ Using "*"
	adr r3, additive_expr_stub          @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	adr r0, postfix_expr                @ Using postfix_expr
	adr r1, additive_expr_stub_string_3 @ Using "XCHG_eax_ebx\nLOAD_IMMEDIATE_edx %0\nDIVIDE_eax_by_ebx_into_eax\n"
	adr r2, divide_string               @ Using "/"
	adr r3, additive_expr_stub          @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	adr r0, postfix_expr                @ Using postfix_expr
	adr r1, additive_expr_stub_string_4 @ Using "XCHG_eax_ebx\nLOAD_IMMEDIATE_edx %0\nMODULUS_eax_from_ebx_into_ebx\nMOVE_edx_to_eax\n"
	adr r2, modulus_string              @ Using "%"
	adr r3, additive_expr_stub          @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	adr r0, postfix_expr                @ Using postfix_expr
	adr r1, additive_expr_stub_string_5 @ Using "COPY_eax_to_ecx\nCOPY_ebx_to_eax\nSAL_eax_cl\n"
	adr r2, left_shift_string           @ Using "<<"
	adr r3, additive_expr_stub          @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	adr r0, postfix_expr                @ Using postfix_expr
	adr r1, additive_expr_stub_string_6 @ Using "COPY_eax_to_ecx\nCOPY_ebx_to_eax\nSAR_eax_cl\n"
	adr r2, right_shift_string          @ Using ">>"
	adr r3, additive_expr_stub          @ And recurse
	push {r14}
	bl general_recursion                @ Hit it
	pop {r14}

	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

additive_expr_stub_string_0: .asciz "ADD_ebx_to_eax\n"
.balign 4
additive_expr_stub_string_1: .asciz "SUBTRACT_eax_from_ebx_into_ebx\nMOVE_ebx_to_eax\n"
.balign 4
additive_expr_stub_string_2: .asciz "MULTIPLY_eax_by_ebx_into_eax\n"
.balign 4
additive_expr_stub_string_3: .asciz "XCHG_eax_ebx\nLOAD_IMMEDIATE_edx %0\nDIVIDE_eax_by_ebx_into_eax\n"
.balign 4
additive_expr_stub_string_4: .asciz "XCHG_eax_ebx\nLOAD_IMMEDIATE_edx %0\nMODULUS_eax_from_ebx_into_ebx\nMOVE_edx_to_eax\n"
.balign 4
additive_expr_stub_string_5: .asciz "COPY_eax_to_ecx\nCOPY_ebx_to_eax\nSAL_eax_cl\n"
.balign 4
additive_expr_stub_string_6: .asciz "COPY_eax_to_ecx\nCOPY_ebx_to_eax\nSAR_eax_cl\n"
.balign 4
plus_string: .asciz "+"
.balign 4
minus_string: .asciz "-"
.balign 4
multiply_string: .asciz "*"
.balign 4
divide_string: .asciz "/"
.balign 4
modulus_string: .asciz "%"
.balign 4
left_shift_string: .asciz "<<"
.balign 4
right_shift_string: .asciz ">>"
.balign 4


## postfix_expr function
## Receives nothing
## Returns Nothing
## Walks global_token list and updates output list
## just calls other function
postfix_expr:
	push {r14}
	bl primary_expr                     @ Walk up the tree
	bl postfix_expr_stub                @ Recurse
	pop {r14}
	bx r14


## postfix_expr_stub function
## Receives nothing
## Returns Nothing
## Checks for "[" and "->" and deals with them otherwise does nothing
## Uses R0, R1, R2 and R3 for passing constants to general recursion
postfix_expr_stub:
	push {r1}                           @ Protect R1
	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, open_bracket_0              @ Using "["
	push {r14}
	bl match                            @ IF global_token->S == "["
	pop {r14}
	cmp r0, #0                          @ then we have an array
	bne postfix_expr_stub_arrow         @ Otherwise try arrow

	## Deal with array
	push {r14}
	bl postfix_expr_array               @ Get it
	bl postfix_expr_stub                @ Recurse
	pop {r14}

postfix_expr_stub_arrow:
	adr r0, arrow_string_0              @ Using "->"
	push {r14}
	bl match                            @ IF global_token->S == "->"
	pop {r14}
	cmp r0, #0                          @ Then we need to deal with struct offsets
	bne postfix_expr_stub_done          @ Otherwise be done

	## Deal with arrow
	push {r14}
	bl postfix_expr_arrow               @ Get it
	bl postfix_expr_stub                @ Recurse
	pop {r14}

postfix_expr_stub_done:
	pop {r1}                            @ Restore R1
	bx r14

open_bracket_0: .asciz "["
.balign 4
arrow_string_0: .asciz "->"
.balign 4


## unary_expr_sizeof function
## Receives nothing
## Returns nothing
## Uses R2 for A->SIZE
unary_expr_sizeof:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	adr r0, unary_expr_sizeof_string_0  @ Using "ERROR in unary_expr\nMissing (\n"
	adr r1, open_paren_6                @ Using "("
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	push {r14}
	bl type_name                        @ Get the type
	pop {r14}
	ldr r2, [r0, #4]                    @ Set A->TYPE

	adr r0, unary_expr_sizeof_string_1  @ Using "ERROR in unary_expr\nMissing )\n"
	adr r1, close_paren_6               @ Using ")"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	adr r0, unary_expr_sizeof_string_2  @ Using "LOAD_IMMEDIATE_eax %"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	mov r0, r2                          @ Put A->SIZE in the right place
	push {r14}
	bl numerate_number                  @ Turn into string
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, unary_expr_sizeof_string_3  @ Using "\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

unary_expr_sizeof_string_0: .asciz "ERROR in unary_expr\nMissing (\n"
.balign 4
unary_expr_sizeof_string_1: .asciz "ERROR in unary_expr\nMissing )\n"
.balign 4
unary_expr_sizeof_string_2: .asciz "LOAD_IMMEDIATE_eax %"
.balign 4
unary_expr_sizeof_string_3: .asciz "\n"
.balign 4
open_paren_6: .asciz "("
.balign 4
close_paren_6: .asciz ")"
.balign 4


## postfix_expr_array function
## Receives Nothing
## Returns Nothing
## Uses R1 for struct type* ARRAY and R2 for char* ASSIGN
postfix_expr_array:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	ldr r8, current_target_address
	ldr r0, [r8]                        @ ARRAY = current_target
	push {r0}                           @ Protect it

	ldr r0, expression_address          @ Using expression
	push {r14}
	bl common_recursion                 @ Recurse
	pop {r14}

	pop {r1}                            @ Restore array
	ldr r8, current_target_address
	str r1, [r8]                        @ current_target = ARRAY

	adr r2, postfix_expr_array_string_0 @ ASSIGN = "LOAD_INTEGER\n"

	ldr r0, type_char_indirect_name_address @ Using "char*"
	ldr r1, [r1, #24]                   @ current_target->NAME
	push {r14}
	bl match                            @ IF current_target->NAME == "char*"
	pop {r14}
	cmp r0, #0                          @ load a byte
	bne postfix_expr_array_large        @ Otherwise adjust

	## Deal with loading byte
	adr r2, postfix_expr_array_string_1 @ ASSIGN = "LOAD_BYTE\n"
	b postfix_expr_array_common         @ Do the next bit

postfix_expr_array_large:
	## deal with arrays made of things other than chars
	adr r0, postfix_expr_array_string_2 @ Using "SAL_eax_Immediate8 !"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r8, current_target_address
	ldr r0, [r8]                        @ Using current_target
	ldr r0, [r0, #12]                   @ current_target->INDIRECT
	ldr r0, [r0, #4]                    @ current_target->INDIRECT->SIZE
	push {r14}
	bl ceil_log2                        @ ceil_log2(current_target->indirect->size)
	bl numerate_number                  @ numerate_number(ceil_log2(current_target->indirect->size))
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, postfix_expr_array_string_3 @ Using "\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

postfix_expr_array_common:
	adr r0, postfix_expr_array_string_4 @ Using "ADD_ebx_to_eax\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, postfix_expr_array_string_5 @ Using "ERROR in postfix_expr\nMissing ]\n"
	adr r1, close_bracket_1             @ Using "]"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, equal_2                     @ Using "="
	push {r14}
	bl match                            @ IF global_token->S == "="
	pop {r14}
	cmp r0, #0                          @ We need to preserve address
	bne postfix_expr_array_done         @ Otherwise be done

	## Clearing out assign
	adr r2, postfix_expr_array_string_6 @ ASSIGN = ""

postfix_expr_array_done:
	mov r0, r2                          @ Using ASSIGN
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

postfix_expr_array_string_0: .asciz "LOAD_INTEGER\n"
.balign 4
postfix_expr_array_string_1: .asciz "LOAD_BYTE\n"
.balign 4
postfix_expr_array_string_2: .asciz "SAL_eax_Immediate8 !"
.balign 4
postfix_expr_array_string_3: .asciz "\n"
.balign 4
postfix_expr_array_string_4: .asciz "ADD_ebx_to_eax\n"
.balign 4
postfix_expr_array_string_5: .asciz "ERROR in postfix_expr\nMissing ]\n"
.balign 4
postfix_expr_array_string_6: .asciz ""
.balign 4
close_bracket_1: .asciz "]"
.balign 4
equal_2: .asciz "="
.balign 4
expression_address: .word expression


## ceil_log2 function
## Receives int a in R0
## Performs log2 on A and
## Returns result in R0
## Uses R1 for INT A and R2 for INT RESULT
ceil_log2:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	mov r2, #0                          @ RESULT = 0

	mov r1, r0                          @ put A in right place
	sub r0, #1                          @ (A - 1)
	and r0, r1                          @ A & (A - 1)
	cmp r0, #0                          @ IF 0 == (A & (A - 1))
	bne ceil_log2_iter                  @ Starting from -1

	mov r2, #-1                         @ RESULT = -1

ceil_log2_iter:
	cmp r1, #0                          @ IF A > 0
	ble ceil_log2_done                  @ Otherwise be done

	add r2, #1                          @ RESULT = RESULT + 1
	asr r1, #1                          @ A = A >> 1
	b ceil_log2_iter                    @ Keep looping

ceil_log2_done:
	mov r0, r2                          @ Return RESULT
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14


## postfix_expr_arrow function
## Receives nothing
## Returns nothing
## Emits a bunch and updates current_target
## Uses R1 for struct type* I
postfix_expr_arrow:
	push {r1}                           @ Protect R1
	adr r0, postfix_expr_arrow_string_0 @ Using "# looking up offset\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	ldr r1, [r0, #8]                    @ Using global_token->S
	ldr r8, current_target_address
	ldr r0, [r8]                        @ Using current_target
	push {r14}
	bl lookup_member                    @ lookup_member(current_target, global_token->s)
	pop {r14}
	mov r1, r0                          @ struct type* I = lookup_member(current_target, global_token->s)

	ldr r0, [r0, #20]                   @ I->TYPE
	ldr r8, current_target_address
	str r0, [r8]                        @ current_target = I->TYPE

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	ldr r0, [r1, #8]                    @ I->OFFSET
	cmp r0, #0                          @ IF 0 != I->OFFSET
	beq postfix_expr_arrow_first        @ Then we don't need to do an offset

	## Deal with needing an offset
	adr r0, postfix_expr_arrow_string_1 @ Using "# -> offset calculation\nLOAD_IMMEDIATE_ebx %"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r1, #8]                    @ I->OFFSET
	push {r14}
	bl numerate_number                  @ Convert to string
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, postfix_expr_arrow_string_2 @ Using "\nADD_ebx_to_eax\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

postfix_expr_arrow_first:
	ldr r0, [r1, #4]                    @ I->SIZE
	cmp r0, #4                          @ IF I->SIZE >= 4
	blt postfix_expr_arrow_done         @ Otherwise be done

	## Last chance for load
	ldr r0, [r12]                       @ Using global_token
	ldr r1, [r0, #8]                    @ global_token->S
	adr r0, equal_3                     @ Using "="
	push {r14}
	bl match                            @ IF global_token->S == "="
	pop {r14}
	cmp r0, #0                          @ Then we have assignment and should not load
	beq postfix_expr_arrow_done         @ Be done

	## Deal with load case
	adr r0, postfix_expr_arrow_string_3 @ Using "LOAD_INTEGER\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

postfix_expr_arrow_done:
	pop {r1}                            @ Restore R1
	bx r14

postfix_expr_arrow_string_0: .asciz "# looking up offset\n"
.balign 4
postfix_expr_arrow_string_1: .asciz "# -> offset calculation\nLOAD_IMMEDIATE_ebx %"
.balign 4
postfix_expr_arrow_string_2: .asciz "\nADD_ebx_to_eax\n"
.balign 4
postfix_expr_arrow_string_3: .asciz "LOAD_INTEGER\n"
.balign 4
equal_3: .asciz "="
.balign 4
current_target_address: .word current_target


## primary_expr function
## Receives nothing
## Returns nothing
primary_expr:
	push {r1}                           @ Protect R1

	ldr r0, [r12]                       @ Using global_token
	ldr r1, [r0, #8]                    @ global_token->S
	adr r0, sizeof_string               @ Using "sizeof"
	push {r14}
	bl match                            @ See if match
	pop {r14}
	cmp r0, #0                          @ IF match
	bne primary_expr_neg                @ Otherwise try negatives

	## Deal with sizeof
	push {r14}
	bl unary_expr_sizeof                @ Lets do this
	pop {r14}
	b primary_expr_done                 @ Be done

primary_expr_neg:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	ldrb r0, [r0]                       @ global_token->S[0]
	cmp r0, #45                         @ IF global_token->S[0] == "-"
	bne primary_expr_not                @ Otherwise try logical NOT

	## Deal with negative numbers
	adr r0, primary_expr_string_0       @ Using "LOAD_IMMEDIATE_eax %0\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, postfix_expr_address        @ Passing postfix_expr
	push {r14}
	bl common_recursion                 @ Get what it is notting
	pop {r14}

	adr r0, primary_expr_string_1       @ Using "SUBTRACT_eax_from_ebx_into_ebx\nMOVE_ebx_to_eax\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}
	b primary_expr_done                 @ Be done

primary_expr_not:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	ldrb r0, [r0]                       @ global_token->S[0]
	cmp r0, #33                         @ IF global_token->S[0] == "!"
	bne primary_expr_bin                @ Otherwise try '~'

	## Deal with logical not
	adr r0, primary_expr_string_2       @ Using "LOAD_IMMEDIATE_eax %1\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, postfix_expr_address        @ Passing postfix_expr
	push {r14}
	bl common_recursion                 @ Get what it is notting
	pop {r14}

	adr r0, primary_expr_string_3       @ Using "XOR_ebx_eax_into_eax\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}
	b primary_expr_done                 @ Be done

primary_expr_bin:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	ldrb r0, [r0]                       @ global_token->S[0]
	cmp r0, #126                        @ IF global_token->S[0] == "~"
	bne primary_expr_paren              @ Otherwise try paren

	## Deal with binary NOT
	ldr r0, postfix_expr_address        @ Passing postfix_expr
	push {r14}
	bl common_recursion                 @ Get what it is notting
	pop {r14}
	adr r0, primary_expr_string_4       @ Using "NOT_eax\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}
	b primary_expr_done                 @ Be done

primary_expr_paren:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	ldrb r0, [r0]                       @ global_token->S[0]
	cmp r0, #40                         @ IF global_token->S[0] == "("
	bne primary_expr_ch                 @ Otherwise try char

	## deal with nesting
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT
	push {r14}
	bl expression                       @ Lets recurse
	pop {r14}
	adr r0, primary_expr_string_5       @ Using "Error in Primary expression\nDidn't get )\n"
	adr r1, close_paren_7               @ Using ")"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}
	b primary_expr_done                 @ Be done

primary_expr_ch:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	ldrb r0, [r0]                       @ global_token->S[0]
	cmp r0, #39                         @ Using "'"
	bne primary_expr_str                @ Otherwise try string

	## Deal with chars
	push {r14}
	bl primary_expr_char                @ Handle that char
	pop {r14}
	b primary_expr_done                 @ Be done

primary_expr_str:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	ldrb r0, [r0]                       @ global_token->S[0]
	cmp r0, #34                         @ Using '\"'
	bne primary_expr_var                @ Otherwise try a variable

	## Deal with strings
	push {r14}
	bl primary_expr_string              @ Handle that string
	pop {r14}
	b primary_expr_done                 @ Be done

primary_expr_var:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	ldrb r0, [r0]                       @ global_token->S[0]
	adr r1, primary_expr_string_6       @ Using "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
	push {r14}
	bl In_Set                           @ See if we have a match
	pop {r14}
	cmp r0, #1                          @ IF match
	bne primary_expr_num                @ otherwise try number

	## Deal with variables
	push {r14}
	bl primary_expr_variable            @ Deal with variable
	pop {r14}
	b primary_expr_done                 @ Be done

primary_expr_num:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	ldrb r0, [r0]                       @ global_token->S[0]
	adr r1, primary_expr_string_7       @ Using "0123456789"
	push {r14}
	bl In_Set                           @ See if we have a match
	pop {r14}
	cmp r0, #1                          @ IF match
	bne primary_expr_fail               @ otherwise we failed hard

	## Deal with numbers
	push {r14}
	bl primary_expr_number              @ Collect the number
	pop {r14}
	b primary_expr_done                 @ Be done

primary_expr_fail:
	## looks like we hit bad input
	## abort before it gets bad
	push {r14}
	bl primary_expr_failure             @ No match means failure
	pop {r14}
primary_expr_done:
	pop {r1}                            @ Restore R1
	bx r14

primary_expr_string_0: .asciz "LOAD_IMMEDIATE_eax %0\n"
.balign 4
primary_expr_string_1: .asciz "SUBTRACT_eax_from_ebx_into_ebx\nMOVE_ebx_to_eax\n"
.balign 4
primary_expr_string_2: .asciz "LOAD_IMMEDIATE_eax %1\n"
.balign 4
primary_expr_string_3: .asciz "XOR_ebx_eax_into_eax\n"
.balign 4
primary_expr_string_4: .asciz "NOT_eax\n"
.balign 4
primary_expr_string_5: .asciz "Error in Primary expression\nDidn't get )\n"
.balign 4
primary_expr_string_6: .asciz "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
.balign 4
primary_expr_string_7:.asciz "0123456789"
.balign 4
close_paren_7: .asciz ")"
.balign 4
sizeof_string: .asciz "sizeof"
.balign 4
postfix_expr_address: .word postfix_expr


## primary_expr_variable function
## Receives nothing
## Returns nothing
## Walks global and updates output
## Uses R0 for struct token_list* a and R2 for char* S
primary_expr_variable:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	ldr r0, [r12]                       @ Using global_token
	ldr r2, [r0, #8]                    @ S = global_token->S
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	mov r0, r2                          @ Using S
	ldr r8, global_constant_list_address_0
	ldr r1, [r8]                        @ Using global_constant_list
	push {r14}
	bl sym_lookup                       @ sym_lookup(s, global_constant_list)
	pop {r14}
	cmp r0, #0                          @ IF NULL == sym_lookup(s, global_constant_list)
	beq primary_expr_variable_local     @ Try locals next

	## Deal with constant load
	ldr r1, [r0, #16]                   @ a->ARGS
	adr r0, primary_expr_variable_string_2 @ Using "LOAD_IMMEDIATE_eax %"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r1, #8]                    @ a->ARGS->S
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, primary_expr_variable_string_1 @ Using "\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}
	b primary_expr_variable_done        @ Be done

primary_expr_variable_local:
	mov r0, r2                          @ Using S
	ldr r1, [r11]                       @ Using function
	ldr r1, [r1, #4]                    @ function->locals
	push {r14}
	bl sym_lookup                       @ sym_lookup(s, function->locals)
	pop {r14}
	cmp r0, #0                          @ IF NULL == sym_lookup(s, function->locals)
	beq primary_expr_variable_arguments @ try arguments next

	## Deal with local load
	push {r14}
	bl variable_load                    @ Collect it
	pop {r14}
	b primary_expr_variable_done        @ Be done

primary_expr_variable_arguments:
	mov r0, r2                          @ Using S
	ldr r1, [r11]                       @ Using function
	ldr r1, [r1, #16]                   @ function->args
	push {r14}
	bl sym_lookup                       @ sym_lookup(s, function->args)
	pop {r14}
	cmp r0, #0                          @ IF NULL == sym_lookup(s, global_constant_list)
	beq primary_expr_variable_function  @ try functions next

	## Deal with argument load
	push {r14}
	bl variable_load                    @ Collect it
	pop {r14}
	b primary_expr_variable_done        @ Be done

primary_expr_variable_function:
	mov r0, r2                          @ Using S
	ldr r8, global_function_list_address_1
	ldr r1, [r8]                        @ Using global_function_list
	push {r14}
	bl sym_lookup                       @ sym_lookup(s, global_function_list)
	pop {r14}
	cmp r0, #0                          @ IF NULL == sym_lookup(s, global_function_list)
	beq primary_expr_variable_global    @ try globals next

	## Deal with functions
	push {r14}
	bl function_load                    @ Deal with the function
	pop {r14}
	b primary_expr_variable_done        @ Be done

primary_expr_variable_global:
	mov r0, r2                          @ Using S
	ldr r8, global_symbol_list_address_1
	ldr r1, [r8]                        @ Using global_symbol_list
	push {r14}
	bl sym_lookup                       @ sym_lookup(s, global_symbol_list)
	pop {r14}
	cmp r0, #0                          @ IF NULL == sym_lookup(s, global_symbol_list)
	beq primary_expr_variable_error     @ Give up

	## Deal with globals
	push {r14}
	bl global_load                      @ Collect that global
	pop {r14}
	b primary_expr_variable_done        @ Be done

primary_expr_variable_error:
	mov r0, #2                          @ Using standard error
	ldr r8, Output_file_address_1
	str r0, [r8]                        @ write to standard error
#	bl line_error                       @ Write useful debug info
	mov r0, r2                          @ put S in the right place
	push {r14}
	bl File_Print                       @ print it
	pop {r14}

	adr r0, primary_expr_variable_string_0 @ Ending string
	push {r14}
	bl File_Print                       @ print it
	pop {r14}
	b Exit_Failure                      @ Abort Hard

primary_expr_variable_done:
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

primary_expr_variable_string_0: .asciz " is not a defined symbol\n"
.balign 4
primary_expr_variable_string_1: .asciz "\n"
.balign 4
primary_expr_variable_string_2: .asciz "LOAD_IMMEDIATE_eax %"
.balign 4
global_constant_list_address_0: .word global_constant_list
Output_file_address_1: .word Output_file
global_symbol_list_address_1: .word global_symbol_list
global_function_list_address_1: .word global_function_list


## function_call function
## Receives char* S in R0 and int BOOL in R1
## Builds stack frames before and tears them down after function calls
## Uses R2 for char* S, R3 for int BOOL, R4 for PASSED
function_call:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3
	push {r4}                           @ Protect R4
	mov r2, r0                          @ Put S in place
	mov r3, r1                          @ Put BOOL in place
	mov r4, #0                          @ PASSED = 0

	adr r0, function_call_string_0      @ Using "ERROR in process_expression_list\nNo ( was found\n"
	adr r1, open_paren_7                @ Using "("
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	adr r0, function_call_string_1      @ Using "PUSH_edi\t# Prevent overwriting in recursion\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, function_call_string_2      @ Using "PUSH_ebp\t# Protect the old base pointer\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, function_call_string_3      @ Using "COPY_esp_to_edi\t# Copy new base pointer\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	ldrb r0, [r0]                       @ global_token->S[0]
	cmp r0, #41                         @ IF global_token->S[0] == ")"
	beq function_call_gen_done          @ Then no arguments to send

	## looks like we have arguments to collect
	push {r14}
	bl expression                       @ Collect the argument
	pop {r14}

	adr r0, function_call_string_4      @ Using "PUSH_eax\t#_process_expression1\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}
	mov r4, #1                          @ PASSED = 1

function_call_gen_iter:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	ldrb r0, [r0]                       @ global_token->S[0]
	cmp r0, #44                         @ IF global_token->S[0] == ","
	bne function_call_gen_done          @ Otherwise we are done

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	push {r14}
	bl expression                       @ Collect the argument
	pop {r14}

	adr r0, function_call_string_5      @ Using "PUSH_eax\t#_process_expression2\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}
	add r4, #1                          @ PASSED = PASSED + 1
	b function_call_gen_iter            @ Keep trying

function_call_gen_done:
	## All is collected
	adr r0, function_call_string_6      @ Using "ERROR in process_expression_list\nNo ) was found\n"
	adr r1, close_paren_8               @ Using ")"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	cmp r3, #0                          @ IF(BOOL == TRUE)
	bne function_call_static            @ Otherwise it is a static call

	## Deal with a passed function pointer
	adr r0, function_call_string_7      @ Using "LOAD_BASE_ADDRESS_eax %"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	mov r0, r2                          @ Using S
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, function_call_string_8      @ Using "\nLOAD_INTEGER\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, function_call_string_9      @ Using "COPY_edi_to_ebp\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, function_call_string_10     @ Using "CALL_eax\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, function_call_string_13     @ Using "POP_ebx\t# _process_expression_locals\n"
	b function_call_cleanup             @ Clean up

function_call_static:
	## Deal with fixed function name
	adr r0, function_call_string_9      @ Using "COPY_edi_to_ebp\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, function_call_string_11     @ Using "CALL_IMMEDIATE %FUNCTION_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	mov r0, r2                          @ Using S
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, function_call_string_12     @ Using "\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, function_call_string_13     @ Using "POP_ebx\t# _process_expression_locals\n"

function_call_cleanup:
	cmp r4, #0                          @ IF PASSED > 0
	ble function_call_done              @ Otherwise be done

	## The desired string is already in R0
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	sub r4, #1                          @ PASSED = PASSED - 1
	b function_call_cleanup             @ Keep going

function_call_done:
	adr r0, function_call_string_14     @ Using "POP_ebp\t# Restore old base pointer\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, function_call_string_15     @ Using "POP_edi\t# Prevent overwrite\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	pop {r4}                            @ Restore R4
	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

function_call_string_0: .asciz "ERROR in process_expression_list\nNo ( was found\n"
.balign 4
function_call_string_1: .asciz "PUSH_edi\t# Prevent overwriting in recursion\n"
.balign 4
function_call_string_2: .asciz "PUSH_ebp\t# Protect the old base pointer\n"
.balign 4
function_call_string_3: .asciz "COPY_esp_to_edi\t# Copy new base pointer\n"
.balign 4
function_call_string_4: .asciz "PUSH_eax\t#_process_expression1\n"
.balign 4
function_call_string_5: .asciz "PUSH_eax\t#_process_expression2\n"
.balign 4
function_call_string_6: .asciz "ERROR in process_expression_list\nNo ) was found\n"
.balign 4
function_call_string_7: .asciz "LOAD_BASE_ADDRESS_eax %"
.balign 4
function_call_string_8: .asciz "\nLOAD_INTEGER\n"
.balign 4
function_call_string_9: .asciz "COPY_edi_to_ebp\n"
.balign 4
function_call_string_10: .asciz "CALL_eax\n"
.balign 4
function_call_string_11: .asciz "CALL_IMMEDIATE %FUNCTION_"
.balign 4
function_call_string_12: .asciz "\n"
.balign 4
function_call_string_13: .asciz "POP_ebx\t# _process_expression_locals\n"
.balign 4
function_call_string_14: .asciz "POP_ebp\t# Restore old base pointer\n"
.balign 4
function_call_string_15: .asciz "POP_edi\t# Prevent overwrite\n"
.balign 4
open_paren_7: .asciz "("
.balign 4
close_paren_8: .asciz ")"
.balign 4


## variable_load function
## Receives struct token_list* A in R0
## Returns nothing
## Updates output and current_target
## Uses R2 for A
variable_load:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	mov r2, r0                          @ Protect A

	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, open_paren_7                @ Using "("
	push {r14}
	bl match                            @ IF global_token->S == "("
	pop {r14}
	cmp r0, #0                          @ Then it might be a function
	bne variable_load_regular           @ Otherwise it is regular

	ldr r1, [r2, #12]                   @ A->TYPE
	ldr r1, [r1, #24]                   @ A->TYPE->NAME
	ldr r0, type_function_name_address  @ Using "FUNCTION"
	push {r14}
	bl match                            @ IF A->TYPE->NAME == "FUNCTION"
	pop {r14}
	cmp r0, #0                          @ Then it must be a function
	bne variable_load_regular           @ otherwise just another regular

	## deal with function
	ldr r0, [r2, #16]                   @ A->DEPTH
	push {r14}
	bl numerate_number                  @ Convert to string
	pop {r14}
	mov r1, #0                          @ pass 0 for true
	push {r14}
	bl function_call                    @ Create the function call
	pop {r14}
	b variable_load_done                @ Be done

variable_load_regular:
	ldr r0, [r2, #12]                   @ A->TYPE
	ldr r8, current_target_address
	str r0, [r8]                        @ current_target = A->TYPE

	adr r0, variable_load_string_0      @ Using "LOAD_BASE_ADDRESS_eax %"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r2, #16]                   @ A->DEPTH
	push {r14}
	bl numerate_number                  @ Convert to string
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, variable_load_string_1      @ Using "\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	## Check for special case of assignment
	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, equal_4                     @ Using "="
	push {r14}
	bl match                            @ IF global_token->S == "="
	pop {r14}
	cmp r0, #0                          @ Then we skip loading
	beq variable_load_done              @ And be done

	## Deal with common case
	adr r0, variable_load_string_2      @ Using "LOAD_INTEGER\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

variable_load_done:
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

variable_load_string_0: .asciz "LOAD_BASE_ADDRESS_eax %"
.balign 4
variable_load_string_1: .asciz "\n"
.balign 4
variable_load_string_2: .asciz "LOAD_INTEGER\n"
.balign 4
equal_4: .asciz "="
.balign 4
type_function_name_address: .word type_function_name
.balign 4


## function_load function
## Receives struct token_list* a in R0
## Returns nothing
## Uses R2 to hold A->S
function_load:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	ldr r0, [r0, #8]                    @ A->S
	mov r2, r0                          @ Protect A->S
	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, open_paren_8                @ Using "("
	push {r14}
	bl match                            @ IF global_token->S == "("
	pop {r14}
	cmp r0, #0                          @ The we need to do a function call
	bne function_load_regular           @ Otherwise just load it's address

	## Deal with function call
	mov r0, r2                          @ Using A->S
	mov r1, #1                          @ Using FALSE
	push {r14}
	bl function_call                    @ Deal with it
	pop {r14}
	b function_load_done                @ Be done

function_load_regular:
	adr r0, function_load_string_0      @ Using "LOAD_IMMEDIATE_eax &FUNCTION_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	mov r0, r2                          @ Using A->S
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, function_load_string_1      @ Using "\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

function_load_done:
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

function_load_string_0: .asciz "LOAD_IMMEDIATE_eax &FUNCTION_"
.balign 4
function_load_string_1: .asciz "\n"
.balign 4
open_paren_8: .asciz "("
.balign 4


## global_load function
## Receives struct token_list* A in R0
## Returns nothing
## Uses R1 to hold A->S
global_load:
	push {r1}                           @ Protect R1
	mov r1, r0                          @ Set as A
	ldr r1, [r1, #8]                    @ Set as A->S

	ldr r0, [r0, #12]                   @ A->TYPE
	ldr r8, current_target_address
	str r0, [r8]                        @ current_target = A->TYPE

	adr r0, global_load_string_0        @ Using "LOAD_IMMEDIATE_eax &GLOBAL_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	mov r0, r1                          @ Using A->S
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, global_load_string_1        @ Using "\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, equal_5                     @ "="
	push {r14}
	bl match                            @ IF global_token->S == "="
	pop {r14}
	cmp r0, #0                          @ We need to skip for assignment
	beq global_load_done                @ and be done

	## Otherwise we are loading the contents
	adr r0, global_load_string_2        @ Using "LOAD_INTEGER\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

global_load_done:
	pop {r1}                            @ Restore R1
	bx r14

global_load_string_0: .asciz "LOAD_IMMEDIATE_eax &GLOBAL_"
.balign 4
global_load_string_1: .asciz "\n"
.balign 4
global_load_string_2: .asciz "LOAD_INTEGER\n"
.balign 4
equal_5: .asciz "="
.balign 4


## sym_lookup function
## Receives char* S in R0 and struct token_list* symbol_list in R1
## Uses I->S in R0, S in R1 and I in R2
## Returns match or NULL
sym_lookup:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	mov r2, r1                          @ I = symbol_list
	mov r1, r0                          @ Put S in the right place
sym_lookup_iter:
	cmp r2, #0                          @ IF NULL == I
	beq sym_lookup_done                 @ We failed to find match

	ldr r0, [r2, #8]                    @ Using I->S
	push {r14}
	bl match                            @ IF I->S == S
	pop {r14}
	cmp r0, #0                          @ then be done
	beq sym_lookup_done                 @ Failed

	ldr r2, [r2]                        @ I = I->NEXT
	b sym_lookup_iter                   @ otherwise keep looping

sym_lookup_done:
	mov r0, r2                          @ Return I
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14


## primary_expr_number function
## Receives nothing
## Returns nothing
## Simply uses current global token to update output and then steps to next global_token
primary_expr_number:
	adr r0, primary_expr_number_string_0 @ Using "LOAD_IMMEDIATE_eax %"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	adr r0, primary_expr_number_string_1 @ Using "\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT
	bx r14

primary_expr_number_string_0: .asciz "LOAD_IMMEDIATE_eax %"
.balign 4
primary_expr_number_string_1: .asciz "\n"
.balign 4


## primary_expr_string function
## receives nothing
## Returns nothing
## creates entries for string and calls to generate string output
## uses R2 for char* number_string
primary_expr_string:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	ldr r8, current_count_address_4
	ldr r1, [r8]                        @ Using current_count
	mov r0, r1                          @ And putting it in the right place
	push {r14}
	bl numerate_number                  @ Get the string
	pop {r14}
	mov r2, r0                          @ protect number_string

	add r1, #1                          @ current_count + 1
	ldr r8, current_count_address_4
	str r1, [r8]                        @ current_count = current_count + 1

	adr r0, primary_expr_string_string_0 @ Using "LOAD_IMMEDIATE_eax &STRING_"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	mov r1, r2                          @ Put number_string in the right place
	push {r14}
	bl uniqueID_out                     @ Make it unique
	pop {r14}

	## Generate the target
	adr r0, primary_expr_string_string_1 @ Using ":STRING_"
	ldr r8, strings_list_address_1
	ldr r1, [r8]                        @ Using strings_list
	push {r14}
	bl emit                             @ Emit it
	pop {r14}
	mov r1, r0                          @ put new strings_list in place

	ldr r0, [r11]                       @ Using function
	ldr r0, [r0, #8]                    @ function->S
	push {r14}
	bl uniqueID                         @ Make it unique
	pop {r14}
	mov r1, r0                          @ put new strings_list in place

	## Parse the string
	ldr r0, [r12]                       @ Using global token
	ldr r0, [r0, #8]                    @ global_token->S
	push {r14}
	bl parse_string                     @ convert to useful form
	bl emit                             @ Emit it
	pop {r14}
	ldr r8, strings_list_address_1
	str r0, [r8]                        @ Update Strings _list

	ldr r0, [r12]                       @ Using global token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

primary_expr_string_string_0: .asciz "LOAD_IMMEDIATE_eax &STRING_"
.balign 4
primary_expr_string_string_1: .asciz ":STRING_"
.balign 4
strings_list_address_1: .word strings_list
current_count_address_4: .word current_count


## primary_expr_char function
## Receives nothing
## Returns nothing
## Updates output_list using global_token
primary_expr_char:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	adr r0, primary_expr_char_string_0  @ Using "LOAD_IMMEDIATE_eax %"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r12]                       @ Using global token
	ldr r0, [r0, #8]                    @ global_token->S
	add r0, #1                          @ global_token->S + 1
	push {r14}
	bl escape_lookup                    @ Get the char
	bl numerate_number                  @ Convert to string
	bl emit_out                         @ emit it
	pop {r14}

	adr r0, primary_expr_char_string_1  @ Using "\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r12]                       @ Using global token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

primary_expr_char_string_0: .asciz "LOAD_IMMEDIATE_eax %"
.balign 4
primary_expr_char_string_1: .asciz "\n"
.balign 4


## primary_expr_failure function
## Receives nothing
## Does not return but aborts hard
## Complains about the bad input
primary_expr_failure:
#	bl line_error                       @ Get line of issue
	mov r0, #2                          @ Using Standard error
	ldr r8, Output_file_address_2
	str r0, [r8]                        @ write to standard error
	adr r0, primary_expr_failure_string_0 @ Using "Received "
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}

	adr r0, primary_expr_failure_string_1 @ Using " in primary_expr\n"
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	b Exit_Failure                      @ Abort Hard

primary_expr_failure_string_0: .asciz "Received "
.balign 4
primary_expr_failure_string_1: .asciz " in primary_expr\n"
.balign 4
Output_file_address_2: .word Output_file


## general_recursion function
## Receives FUNCTION F in R0, char* S in R1, char* name in R2 and FUNCTION iterate in R3
## Returns nothing
## Uses R2 for char* S, R3 for FUNCTION iterate and R6 for FUNCTION F
## But generally recurses a shitload
general_recursion:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3
	push {r6}                           @ Protect R6
	mov r6, r0                          @ Protect F
	mov r0, r2                          @ Put name in the right place
	mov r2, r1                          @ Protect S

	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	push {r14}
	bl match                            @ IF match(name, global_token->s)
	pop {r14}
	cmp r0, #0                          @ If true we do
	bne general_recursion_done          @ Otherwise skip it

	## Deal with the recursion
	mov r0, r6                          @ Put F in the right place
	push {r14}
	bl common_recursion                 @ Recurse
	pop {r14}

	mov r0, r2                          @ Put S in the right place
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	mov r0, r3                          @ Put iterate in the right place
	push {r14}
	blx r0                              @ Down the rabbit hole
	pop {r14}

general_recursion_done:
	pop {r6}                            @ Restore R6
	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14


## promote_type function
## Receives struct type* a in R0 and struct type* b in R1
## Returns the most recent type in R0
## Uses R0 for struct type* I, R2 for struct type* A and R3 for struct type* B
promote_type:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3
	cmp r1, #0                          @ IF NULL == B
	beq promote_type_done               @ Just return A

	mov r2, r0                          @ Put A in place
	mov r3, r1                          @ Put B in place
	mov r0, r1                          @ IF NULL == A
	cmp r2, #0                          @ Then we just return B
	beq promote_type_done               @ Be done

	## Looks like we need to walk the list
	ldr r2, [r2, #24]                   @ A->NAME
	ldr r3, [r3, #24]                   @ B->NAME
	ldr r8, global_types_address
	ldr r0, [r8]                        @ I = global_types
promote_type_iter:
	cmp r0, #0                          @ IF NULL == I
	beq promote_type_done               @ Just be done

	ldr r1, [r0, #24]                   @ I->NAME
	cmp r1, r2                          @ IF(A->NAME == I->NAME)
	beq promote_type_done               @ Be done

	cmp r1, r3                          @ IF(B->NAME == I->NAME)
	beq promote_type_done               @ Be done

	ldr r1, [r0, #12]                   @ I->INDIRECT
	ldr r1, [r1, #24]                   @ I->INDIRECT->NAME

	cmp r1, r2                          @ IF(A->NAME == I->INDIRECT->NAME)
	beq promote_type_done               @ Be done

	cmp r1, r3                          @ IF(B->NAME == I->INDIRECT->NAME)
	beq promote_type_done               @ Be done

	ldr r0, [r0]                        @ I = I->NEXT
	b promote_type_iter                 @ Keep going

promote_type_done:
	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14


## common_recursion function
## Receives FUNCTION F in R0
## Returns Nothing
## Walks global_token list and update output_list
## Updates current_target
## Uses R1 to hold FUNCTION F and struct type* last_type
common_recursion:
	push {r1}                           @ Protect R1
	mov r1, r0                          @ Put FUNCTION F safely out of the way
	adr r0, common_recursion_string_0   @ Using "PUSH_eax\t#_common_recursion\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	mov r0, r1                          @ Prepare for function call
	ldr r8, current_target_address
	ldr r1, [r8]                        @ Get last type
	push {r14}
	blx r0                              @ F();
	pop {r14}
	ldr r8, current_target_address
	ldr r0, [r8]                        @ Get current_target
	push {r14}
	bl promote_type                     @ get the right type
	pop {r14}
	ldr r8, current_target_address
	str r0, [r8]                        @ Set new current_target

	adr r0, common_recursion_string_1   @ Using "POP_ebx\t# _common_recursion\n"
	push {r14}
	bl emit_out                         @ Emit it
	pop {r14}
	pop {r1}                            @ Restore R1
	bx r14

common_recursion_string_0: .asciz "PUSH_eax\t#_common_recursion\n"
.balign 4
common_recursion_string_1: .asciz "POP_ebx\t# _common_recursion\n"
.balign 4


## require_match function
## Receives char* message in R0 and char* required in R1
## Returns nothing
## Uses R2 to hold message and updates global_token
require_match:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	mov r2, r0                          @ put the message somewhere safe
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	push {r14}
	bl match                            @ IF required == global_token->S
	pop {r14}
	cmp r0, #0                          @ we are fine
	beq require_match_good              @ otherwise pain

	## Deal will bad times
#	bl line_error                       @ Tell user what went wrong
	mov r0, #2                          @ Using standard error
	ldr r8, Output_file_address_3
	str r0, [r8]                        @ write to standard error
	mov r0, r2                          @ using our message
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	b Exit_Failure                      @ Abort HARD

require_match_good:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->next
	str r0, [r12]                       @ global_token = global_token->next
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

Output_file_address_3: .word Output_file


## uniqueID Function
## Receives char *S in R0, struct token_list* l in R1 and char* num in R2
## Returns updated struct token_list* L in R0
uniqueID:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r14}
	bl emit                             @ emit(s, l)
	pop {r14}
	mov r1, r0                          @ Put L in correct place
	adr r0, underline_1                 @ Using "_"
	push {r14}
	bl emit                             @ emit("_", l)
	pop {r14}
	mov r1, r0                          @ Put L in correct place
	mov r0, r2                          @ Put num in correct place
	push {r14}
	bl emit                             @ emit(num, l)
	pop {r14}
	mov r1, r0                          @ Put L in correct place
	adr r0, uniqueID_string_0           @ Using "\n"
	push {r14}
	bl emit                             @ emit("\n", l)
	pop {r14}
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

uniqueID_string_0: .asciz "\n"
.balign 4
underline_1: .asciz "_"
.balign 4


## uniqueID_out function
## Receives char* S in R0 and char* num in R1
## Returns nothing
uniqueID_out:
	push {r0}                           @ Protect R0
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	mov r2, r1                          @ Put num in right spot
	ldr r8, output_list_address_3
	ldr r1, [r8]                        @ Using output_list
	push {r14}
	bl uniqueID                         @ Get updated list
	pop {r14}
	ldr r8, output_list_address_3
	str r0, [r8]                        @ output_list = uniqueID(s, output_list, num)
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	pop {r0}                            @ Restore R0
	bx r14

output_list_address_3: .word output_list


## emit_out function
## Receives char* S in R0
## Returns nothing
## Updates output_list
## MUST NOT ALTER REGISTERS
emit_out:
	push {r0}                           @ Protect R0
	push {r1}                           @ Protect R1
	ldr r8, output_list_address_3
	ldr r1, [r8]                        @ Using output_list
	push {r14}
	bl emit                             @ emit it
	pop {r14}
	ldr r8, output_list_address_3
	str r0, [r8]                        @ update it
	pop {r1}                            @ Restore R1
	pop {r0}                            @ Restore R0
	bx r14


## emit function
## Receives char *s in R0 and struct token_list* head in R1
## Returns struct token_list* T in R0
emit:
	push {r2}                           @ Protect R2
	mov r2, r0                          @ put S out of the way
	mov r0, #20                         @ sizeof(struct token_list)
	push {r14}
	bl malloc                           @ get T
	pop {r14}
	str r1, [r0]                        @ t->next = head;
	str r2, [r0, #8]                    @ t->s = s;
	pop {r2}                            @ Restore R2
	bx r14


## escape_lookup function
## Receives char* c in R0
## Returns integer value of char in R0
## Aborts hard if unknown escape is received
## Uses R2 to hold char* C
escape_lookup:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	mov r2, r0                          @ Put char* C in safe place
	ldrb r0, [r2]                       @ Load c[0]
	cmp r0, #92                         @ If '\\' != c[0]
	bne escape_lookup_done              @ Be done

	mov r1, r2                          @ Prepare for walk
	add r1, #1                          @ increment
	ldrb r1, [r1]                       @ load c[1]

	cmp r1, #120                        @ Check if \x??
	beq escape_lookup_hex               @ Deal with hex

	## Deal with \? escapes
	mov r0, #10                         @ Guess "\n"
	cmp r1, #110                        @ If n
	beq escape_lookup_done              @ Be done

	mov r0, #9                          @ Guess "\t"
	cmp r1, #116                        @ If t
	beq escape_lookup_done              @ Be done

	mov r0, r1                          @ "\\", "'" and '\"' all encode as themselves
	cmp r1, #92                         @ If "\\"
	beq escape_lookup_done              @ Be done
	cmp r1, #39                         @ IF "'"
	beq escape_lookup_done              @ Be done
	cmp r1, #34                         @ IF '\"'
	beq escape_lookup_done              @ Be done

	mov r0, #13                         @ Guess "\r"
	cmp r1, #114                        @ IF r
	beq escape_lookup_done              @ Be done

	## Looks like we have no clue what we are doing
	## Aborting hard
	mov r0, #2                          @ Using Standard error
	ldr r8, Output_file_address_4
	str r0, [r8]                        @ write to standard error
	adr r0, escape_lookup_string_0      @ Using "Unknown escape received: "
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	mov r0, r2                          @ Using C
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	adr r0, escape_lookup_string_1      @ Using " Unable to process\n"
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	b Exit_Failure                      @ Abort Hard

escape_lookup_done:
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

escape_lookup_hex:
	## Give up on C and just assume they know what they are doing
	add r2, #2                          @ increment
	ldrb r0, [r2]                       @ c[2]
	add r2, #1                          @ increment
	push {r14}
	bl char2hex                         @ Get the hex value
	pop {r14}
	lsl r0, #4                          @ c << 4
	ldrb r1, [r2]                       @ c[3]
	mov r8, r0
	mov r0, r1                          @ protect c << 4
	mov r1, r8
	push {r14}
	bl char2hex                         @ Get the hex value
	pop {r14}
	add r0, r1                          @ hex(c[2]) << 4 + hex(c[3])
	b escape_lookup_done                @ Be done

escape_lookup_string_0: .asciz "Unknown escape received: "
.balign 4
escape_lookup_string_1: .asciz " Unable to process\n"
.balign 4
Output_file_address_4: .word Output_file


## char2hex function
## Receives char in R0
## Returns hex or aborts hard
char2hex:
	sub r0, #48                         @ Try 0-9
	cmp r0, #10                         @ Otherwise fun times
	blt char2hex_done                   @ Be done

	## Deal with A-F
	and r0, #0xDF                       @ Unset High bit turning a-f into A-F
	sub r0, #7                          @ Shift down into position
	cmp r0, #10                         @ Everything below A is bad
	blt char2hex_fail                   @ And should fail
	cmp r0, #16                         @ Make sure we are below F
	blt char2hex_done                   @ If so be done

char2hex_fail:
	## Time to fail hard
	mov r0, #2                          @ Using Standard error
	ldr r8, Output_file_address_4
	str r0, [r8]                        @ write to standard error
	adr r0, char2hex_string_0           @ Using "Tried to print non-hex number\n"
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	b Exit_Failure                      @ Abort Hard

char2hex_done:
	bx r14

char2hex_string_0: .asciz "Tried to print non-hex number\n"
.balign 4


## parse_string function
## Receives char* string in R0
## Returns cleaned up string
## Protects char* string in R1
parse_string:
	push {r1}                           @ Protect R1
	mov r1, r0                          @ Protect char* string
	push {r14}
	bl weird                            @ Determine if we have a weird string
	pop {r14}
	cmp r0, #0                          @ If weird
	beq parse_string_weird              @ Deal with it

	## Dealing with regular string
	mov r0, r1                          @ Passing Char* string
	push {r14}
	bl collect_regular_string           @ Collect it
	pop {r14}
	b parse_string_done                 @ Be done

parse_string_weird:
	mov r0, r1                          @ Passing Char* string
	push {r14}
	bl collect_weird_string             @ Collect it
	pop {r14}

parse_string_done:
	pop {r1}                            @ Restore R1
	bx r14


## weird function
## Receives char* string in R0
## Returns true(0) or false(1) in R0
## Uses R2 to hold char* string
weird:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	mov r2, r0                          @ Place string in safe place
	add r2, #1                          @ increment past the '\"'
weird_reset:
	ldrb r0, [r2]                       @ Load a char
	cmp r0, #0                          @ IF NULL == C
	beq weird_false                     @ Nothing weird found

	cmp r0, #92                         @ IF '\\'
	bne weird_escaped                   @ Deal with escaping

	## Deal with escape
	mov r0, r2                          @ We are passing the string
	push {r14}
	bl escape_lookup                    @ to look it up
	pop {r14}

	add r2, #1                          @ string = string + 1
	ldrb r1, [r2]                       @ get string[1]
	cmp r1, #120                        @ IF 'x' == string[1]
	bne weird_escaped                   @ otherwise skip the gap

	add r2, #2                          @ string = string + 2

weird_escaped:
	push {r0}                           @ Protect C in case we need it
	adr r1, weird_string_0              @ Use "\t\n !#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
	push {r14}
	bl In_Set                           @ To find if weird
	pop {r14}
	cmp r0, #1                          @ IF TRUE
	pop {r0}                            @ Restore C
	bne weird_true                      @ Then not weird

	add r2, #1                          @ string = string + 1

	## Last chance for weird
	adr r1, weird_string_1              @ Use "\t\n\r "
	push {r14}
	bl In_Set                           @ Check for special case
	pop {r14}
	cmp r0, #1                          @ IF TRUE
	bne weird_reset                     @ Otherwise not in the special case

	## Deal with possible special case
	ldrb r0, [r2]                       @ Load string[1]
	cmp r0, #58                         @ IF string[1] == ":"
	beq weird_true                      @ Then we hit the special case
	b weird_reset                       @ Keep trying

weird_done:
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

weird_true:
	mov r0, #0                          @ Return true
	b weird_done                        @ Be done

weird_false:
	mov r0, #1                          @ Return false
	b weird_done                        @ Be done

weird_string_0: .asciz "\t\n !#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
.balign 4
weird_string_1: .asciz "\t\n\r "
.balign 4


## collect_regular_string function
## Receives char* string in R0
## Malloc and creates new string to return in R0
## Uses R2 for return string and R3 for passed string
collect_regular_string:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3
	mov r3, r0                          @ Protect our passed string
	mov r0, #256                        @ We need 256bytes of storage
	push {r14}
	bl malloc                           @ Get our new pointer
	pop {r14}
	mov r2, r0                          @ put it in place
	push {r0}                           @ protect until done
collect_regular_string_reset:
	ldrb r0, [r3]                       @ string[0]
	cmp r0, #0                          @ See if we hit the end
	beq collect_regular_string_done     @ And be done

	cmp r0, #92                         @ IF string[0] == '\\'
	beq collect_regular_string_escaped  @ Deal with that mess

	## deal with boring char
	strb r0, [r2]                       @ hold_string[index] = string[0]
	add r2, #1                          @ Increment it
	add r3, #1                          @ Increment it
	b collect_regular_string_reset      @ And keep going

collect_regular_string_escaped:
	mov r0, r3                          @ Using string
	push {r14}
	bl escape_lookup                    @ Get the char
	pop {r14}
	strb r0, [r2]                       @ hold_string[index] = escape_lookup(string)
	add r3, #1                          @ Increment it
	add r2, #1                          @ Increment it
	ldrb r0, [r3]                       @ string[0]
	add r3, #1                          @ Increment it
	cmp r0, #120                        @ IF 'x' == string[1]
	bne collect_regular_string_reset    @ Otherwise keep going

	add r3, #2                          @ Increment it
	b collect_regular_string_reset      @ Keep going

collect_regular_string_done:
	mov r0, #34                         @ Using '\"'
	strb r0, [r2]                       @ hold_string[index] = '\"'
	add r2, #1                          @ Increment it
	mov r0, #10                         @ Using "\n"
	strb r0, [r2]                       @ hold_string[index] = '\n'
	pop {r0}                            @ Return our new string
	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14


## collect_weird_string function
## Receives char* string in R0
## Mallocs and returns char* hold in R0
## Uses R2 for char* hold and R3 for char* string
collect_weird_string:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3
	mov r3, r0                          @ Protect our passed string
	mov r0, #512                        @ We need 512bytes of storage
	push {r14}
	bl malloc                           @ Get our new pointer
	pop {r14}
	mov r2, r0                          @ put it in place
	push {r0}                           @ protect until done

	mov r0, #39                         @ Using "'"
	strb r0, [r2]                       @ hold_string[index] = "'"
	add r2, #1                          @ Increment it
	add r3, #1                          @ Increment it
collect_weird_string_reset:
	ldrb r0, [r3]                       @ Read a byte
	cmp r0, #0                          @ IF NULL == string[0]
	beq collect_weird_string_done       @ Be done

	mov r0, #32                         @ Using ' '
	strb r0, [r2]                       @ hold_string[index] = ' '
	add r2, #1                          @ Increment it

	mov r0, r3                          @ Using string
	push {r14}
	bl escape_lookup                    @ Get the char
	bl hex8                             @ Update R2
	pop {r14}

	ldrb r0, [r3]                       @ Read a byte
	add r3, #1                          @ Increment it
	cmp r0, #92                         @ IF string[0] == '\\'
	bne collect_weird_string_reset      @ Otherwise keep going

	ldrb r0, [r3]                       @ Read a byte
	add r3, #1                          @ Increment it
	cmp r0, #120                        @ IF 'x' == string[1]
	bne collect_weird_string_reset      @ Otherwise keep going

	add r3, #2                          @ Increment it
	b collect_weird_string_reset        @ Keep going

collect_weird_string_done:
	mov r0, #32                         @ Using ' '
	strb r0, [r2]                       @ hold_string[index] = ' '
	add r2, #1                          @ Increment it
	mov r0, #48                         @ Using '0'
	strb r0, [r2]                       @ hold_string[index] = '0'
	add r2, #1                          @ Increment it
	strb r0, [r2]                       @ hold_string[index] = '0'
	add r2, #1                          @ Increment it
	mov r0, #39                         @ Using "'"
	strb r0, [r2]                       @ hold_string[index] = "'"
	add r2, #1                          @ Increment it
	mov r0, #10                         @ Using "\n"
	strb r0, [r2]                       @ hold_string[index] = '\n'
	pop {r0}                            @ Return our new string
	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14


## HEX to ascii routine
## Receives INT in R0 and CHAR* in R2
## Stores ascii of INT in CHAR*
## Returns only modifying R0 and R2
hex8:
	push {r0}                           @ Protect bottom nibble
	asr r0, #4                          @ do high nibble first
	push {r14}
	bl hex4                             @ Store it
	pop {r14}
	pop {r0}                            @ do low nibble
hex4:
	and r0, #0xf                        @ isolate nibble
	add r0, #'0'                        @ convert to ascii
	cmp r0, #'9'                        @ valid digit?
	ble hex1                            @ yes
	add r0, #7                          @ use alpha range
hex1:
	strb r0, [r2]                       @ store result
	add r2, #1                          @ next position
	bx r14


## type_name function
## Receives nothing
## Returns type_size in R0
## Uses R2 for STRUCT TYPE* RET
type_name:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1, #8]                    @ global_token->S
	adr r0, struct                      @ Using "struct"
	push {r14}
	bl match                            @ IF global_token->S == "struct"
	pop {r14}
	mov r2, r0                          @ Protect structure
	cmp r0, #0                          @ need to skip over "struct"
	bne type_name_native                @ otherwise keep going

	## Deal with possible STRUCTs
	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1]                        @ global_token->next
	str r1, [r12]                       @ global_token = global_token->next
	ldr r0, [r1, #8]                    @ global_token->S
	ldr r8, global_types_address
	ldr r1, [r8]                        @ get all known types
	push {r14}
	bl lookup_type                      @ Find type if possible
	pop {r14}
	mov r2, r0                          @ Set ret

	cmp r0, #0                          @ IF NULL == ret
	bne type_name_common                @ We have to create struct

	## Create a struct
	push {r14}
	bl create_struct                    @ Create a new struct
	pop {r14}
	mov r2, #0                          @ We wish to return NULL
	b type_name_done                    @ be done

type_name_native:
	## Deal only with native types
	mov r0, r1                          @ Put global_token->S in the right place
	ldr r8, global_types_address
	ldr r1, [r8]                        @ get all known types
	push {r14}
	bl lookup_type                      @ Find the type if possible
	pop {r14}
	mov r2, r0                          @ Set ret

	cmp r0, #0                          @ IF NULL == ret
	bne type_name_common                @ We need to abort hard

	## Aborting hard
	mov r0, #2                          @ Using Standard error
	ldr r8, Output_file_address_5
	str r0, [r8]                        @ write to standard error
	adr r0, type_name_string_0          @ Print header
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}

	ldr r0, [r12]                       @ Using global token
	ldr r0, [r0, #8]                    @ global_token->S
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}

	adr r0, type_name_string_1          @ Print footer
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}

#	bl line_error                       @ Give details
	b Exit_Failure                      @ Abort

type_name_common:
	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1]                        @ global_token->next
	str r1, [r12]                       @ global_token = global_token->next

type_name_iter:
	ldr r0, [r1, #8]                    @ global_token->S
	ldrb r0, [r0]                       @ global_token->S[0]
	cmp r0, #42                         @ IF global_token->S[0] == '*'
	bne type_name_done                  @ recurse

	## Deal with char**
	ldr r2, [r2, #12]                   @ ret = ret->indirect
	ldr r1, [r12]                       @ Using global_token
	ldr r1, [r1]                        @ global_token->next
	str r1, [r12]                       @ global_token = global_token->next
	b type_name_iter                    @ keep looping

type_name_done:
	mov r0, r2                          @ put ret in the right place
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

type_name_string_0: .asciz "Unknown type "
.balign 4
type_name_string_1: .asciz "\n"
.balign 4
struct: .asciz "struct"
.balign 4
global_types_address: .word global_types
Output_file_address_5: .word Output_file


## lookup_type function
## Receives char* s in R0 and struct type* start in R1
## Returns struct type* in R0
## Uses R1 for S and R2 for I
lookup_type:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	mov r2, r1                          @ I = Start
	mov r1, r0                          @ Put S in place
lookup_type_iter:
	cmp r2, #0                          @ Check if I == NULL
	beq lookup_type_done                @ return NULL

	ldr r0, [r2, #24]                   @ I->NAME
	push {r14}
	bl match                            @ Check if matching
	pop {r14}
	cmp r0, #0                          @ IF I->NAME == S
	beq lookup_type_done                @ return it

	ldr r2, [r2]                        @ Otherwise I = I->NEXT
	b lookup_type_iter                  @ And keep looping

lookup_type_done:
	mov r0, r2                          @ return either I or NULL
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14


## create_struct function
## Receives nothing
## Returns nothing
## Uses global_token to malloc a struct's definition
## Uses R2 for int OFFSET, R3 for struct type* head, R6 for struct type* I,
## R5 for member_size (Which is passed) and R4 for LAST
## R0 and R1 are used for scratch
create_struct:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3
	push {r6}                           @ Protect R6
	push {r5}                           @ Protect R5
	push {r4}                           @ Protect R4
	mov r2, #0                          @ OFFSET = 0
	mov r5, #0                          @ member_size = 0

	mov r0, #28                         @ sizeof(struct type)
	push {r14}
	bl malloc                           @ malloc(sizeof(struct type))
	pop {r14}
	mov r3, r0                          @ Set HEAD

	mov r0, #28                         @ sizeof(struct type)
	push {r14}
	bl malloc                           @ malloc(sizeof(struct type))
	pop {r14}
	mov r6, r0                          @ Set I

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	str r0, [r3, #24]                   @ HEAD->NAME = global_token->S
	str r0, [r6, #24]                   @ I->NAME = global_token->S

	str r6, [r3, #12]                   @ HEAD->INDIRECT = I
	str r3, [r6, #12]                   @ I->INDIRECT = HEAD

	ldr r8, global_types_address
	ldr r0, [r8]                        @ Using global_types
	str r0, [r3]                        @ HEAD->NEXT = global_types
	str r3, [r8]                        @ global_types = HEAD

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	mov r0, #4                          @ Using register size
	str r0, [r6, #4]                    @ I->SIZE = register size

	adr r0, create_struct_string_0      @ Using "ERROR in create_struct\n Missing {\n"
	adr r1, open_curly_brace_1          @ Using "{"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	mov r4, #0                          @ LAST = NULL

create_struct_iter:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	ldrb r0, [r0]                       @ global_token->S[0]
	cmp r0, #125                        @ IF global_token->S[0] == "}"
	beq create_struct_done              @ be done

	## Looks like we are adding members
	## Lets see if it is a union
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	adr r1, union                       @ Using "union"
	push {r14}
	bl match                            @ IF match(global_token->s, "union")
	pop {r14}
	cmp r0, #0                          @ Deal with union
	bne create_struct_single            @ Otherwise deal with singles

	## Deal with union
	mov r0, r4                          @ Put last in right place
	mov r1, r2                          @ put offset in right place
	push {r14}
	bl build_union                      @ ASSEMBLE
	pop {r14}
	mov r4, r0                          @ last = build_union(last, offset)
	add r2, r5                          @ offset = offset + member_size

	adr r0, create_struct_string_1      @ Using "ERROR in create_struct\n Missing ;\n"
	adr r1, semicolon_9                 @ Using ";"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}
	b create_struct_iter                @ keep going

create_struct_single:
	## deal with singles
	mov r0, r4                          @ Put last in right place
	mov r1, r2                          @ put offset in right place
	push {r14}
	bl build_member                     @ ASSEMBLE
	pop {r14}
	mov r4, r0                          @ last = build_union(last, offset)
	add r2, r5                          @ offset = offset + member_size

	adr r0, create_struct_string_1      @ Using "ERROR in create_struct\n Missing ;\n"
	adr r1, semicolon_9                 @ Using ";"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}
	b create_struct_iter                @ keep going

create_struct_done:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	adr r0, create_struct_string_1      @ Using "ERROR in create_struct\n Missing ;\n"
	adr r1, semicolon_9                 @ Using ";"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

	str r2, [r3, #4]                    @ HEAD->SIZE = OFFSET
	str r4, [r3, #16]                   @ HEAD->MEMBERS = LAST
	str r4, [r6, #16]                   @ I->MEMBERS = LAST

	pop {r4}                            @ Restore R4
	pop {r5}                            @ Restore R5
	pop {r6}                            @ Restore R6
	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

create_struct_string_0: .asciz "ERROR in create_struct\n Missing {\n"
.balign 4
create_struct_string_1: .asciz "ERROR in create_struct\n Missing ;\n"
.balign 4
semicolon_9: .asciz ";"
.balign 4
union: .asciz "union"
.balign 4
open_curly_brace_1: .asciz "{"
.balign 4


## lookup_member function
## Receives struct type* parent in R0 and char* name in R1
## Returns struct type* I in R0
## Uses char* NAME in R1, R2 for struct type* I and R3 to hold parent for errors
## Aborts hard if not found
lookup_member:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3
	mov r3, r0                          @ Protect Parent
	ldr r2, [r0, #16]                   @ struct type* I = parent->MEMBERS
lookup_member_iter:
	cmp r2, #0                          @ IF I == NULL
	beq lookup_member_fail              @ Abort HARD

	ldr r0, [r2, #24]                   @ Using I->NAME
	push {r14}
	bl match                            @ IF I->NAME == NAME
	pop {r14}
	cmp r0, #0                          @ Then we have found the member
	mov r0, r2                          @ Prepare for return
	ldr r2, [r2, #16]                   @ Prepare for loop I = I->MEMBERS
	bne lookup_member_iter              @ Looks like we are looping

	## I is already in R0
	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

lookup_member_fail:
	mov r0, #2                          @ Using Standard error
	ldr r8, Output_file_address_6
	str r0, [r8]                        @ write to standard error
	adr r0, lookup_member_string_0      @ Using "ERROR in lookup_member "
	push {r14}
	bl File_Print                       @ print it
	pop {r14}

	ldr r0, [r3, #24]                   @ PARENT->NAME
	push {r14}
	bl File_Print                       @ print it
	pop {r14}

	adr r0, arrow_string_1              @ Using "->"
	push {r14}
	bl File_Print                       @ print it
	pop {r14}

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	push {r14}
	bl File_Print                       @ print it
	pop {r14}

	adr r0, lookup_member_string_1      @ Using " does not exist\n"
	push {r14}
	bl File_Print                       @ print it
	pop {r14}

#	bl line_error                       @ Write useful debug info

	adr r0, lookup_member_string_2      @ Using "\n"
	push {r14}
	bl File_Print                       @ print it
	pop {r14}
	b Exit_Failure                      @ Abort Hard

lookup_member_string_0: .asciz "ERROR in lookup_member "
.balign 4
lookup_member_string_1: .asciz " does not exist\n"
.balign 4
lookup_member_string_2: .asciz "\n"
.balign 4
arrow_string_1: .asciz "->"
.balign 4
Output_file_address_6: .word Output_file


## build_member function
## Receives struct type* last in R0, int offset in R1 and global member_size in R5
## Updates member_size in R5 and returns struct type* I in R0
## Uses R2 for struct type* member_type and R3 for struct type* I
build_member:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3
	mov r3, r0                          @ Put last out of the way
	mov r0, #28                         @ Allocate type
	push {r14}
	bl malloc                           @ Get I
	pop {r14}
	str r3, [r0, #16]                   @ I->MEMBERS = LAST
	str r1, [r0, #8]                    @ I->OFFSET = OFFSET
	mov r3, r0                          @ Put I in place

	push {r14}
	bl type_name                        @ Get member_type
	pop {r14}
	mov r2, r0                          @ Put in place
	str r2, [r3, #20]                   @ I->TYPE = MEMBER_TYPE
	ldr r0, [r12]                       @ Using global_token
	ldr r1, [r0, #8]                    @ global_token->S
	str r1, [r3, #24]                   @ I->NAME = global_token->S
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	## Check if we have an array
	ldr r1, [r0, #8]                    @ global_token->S
	adr r0, open_bracket_1              @ Using "["
	push {r14}
	bl match                            @ IF global_token->S == "["
	pop {r14}
	cmp r0, #0                          @ Then we have to deal with arrays in our structs
	beq build_member_array              @ So deal with that pain

	## Deal with non-array case
	ldr r0, [r2, #4]                    @ member_type->SIZE
	str r0, [r3, #4]                    @ I->SIZE = member_type->SIZE
	b build_member_done                 @ Be done

build_member_array:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	ldr r0, [r0, #8]                    @ global_token->S
	push {r14}
	bl numerate_string                  @ convert number
	pop {r14}
	ldr r1, [r2, #20]                   @ member_type->TYPE
	ldr r1, [r1, #4]                    @ member_type->TYPE->SIZE
	mul r0, r1                          @ member_type->type->size * numerate_string(global_token->s)
	str r0, [r3, #4]                    @ I->SIZE = member_type->type->size * numerate_string(global_token->s)

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	adr r0, build_member_string_0       @ Using "Struct only supports [num] form\n"
	adr r1, close_bracket_2             @ Using "]"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

build_member_done:
	ldr r5, [r3, #4]                    @ MEMBER_SIZE = I->SIZE
	str r2, [r3, #20]                   @ I->TYPE = MEMBER_TYPE
	mov r0, r3                          @ Return I

	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

build_member_string_0: .asciz "Struct only supports [num] form\n"
.balign 4
open_bracket_1: .asciz "["
.balign 4
close_bracket_2: .asciz "]"
.balign 4


## build_union function
## Receives struct type* last in R0, int offset in R1 and global member_size in R5
## Updates member_size in R5 and returns struct type* LAST in R0
## Uses R2 for struct type* last, R3 for int offset, R4 for int size and R5 for int member_size
build_union:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3
	push {r4}                           @ Protect R4
	mov r2, r0                          @ Put LAST in right spot
	mov r3, r1                          @ Put OFFSET in right spot
	mov r4, #0                          @ SIZE = 0

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	adr r0, build_union_string_0        @ Using "ERROR in build_union\nMissing {\n"
	adr r1, open_curly_brace_2          @ Using "{"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}

build_union_iter:
	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0, #8]                    @ global_token->S
	ldrb r0, [r0]                       @ global_token->S[0]
	cmp r0, #125                        @ IF global_token->S[0] == "}"
	beq build_union_done                @ Be done

	## Collect union member
	mov r0, r2                          @ Passing LAST
	mov r1, r3                          @ Passing offset
	push {r14}
	bl build_member                     @ build_member(last, offset)
	pop {r14}
	mov r2, r0                          @ last = build_member(last, offset)

	cmp r4, r5                          @ IF member_size > size
	bgt build_union_size                @ Then update size

	## deal with member_size > size
	mov r4, r5                          @ SIZE = MEMBER_SIZE

build_union_size:
	adr r0, build_union_string_1        @ Using "ERROR in build_union\nMissing ;\n"
	adr r1, semicolon_10                @ Using ";"
	push {r14}
	bl require_match                    @ Make sure we have it
	pop {r14}
	b build_union_iter                  @ Keep going

build_union_done:
	mov r5, r4                          @ MEMBER_SIZE = SIZE

	ldr r0, [r12]                       @ Using global_token
	ldr r0, [r0]                        @ global_token->NEXT
	str r0, [r12]                       @ global_token = global_token->NEXT

	mov r0, r2                          @ Return last

	pop {r4}                            @ Restore R4
	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

build_union_string_0: .asciz "ERROR in build_union\nMissing {\n"
.balign 4
build_union_string_1: .asciz "ERROR in build_union\nMissing ;\n"
.balign 4
semicolon_10: .asciz ";"
.balign 4
open_curly_brace_2: .asciz "{"
.balign 4


## sym_declare function
## Receives char *s in R0, struct type* t in R1, and struct token_list* list in R2
## Returns struct token_list* in R0
## Uses R0 for A
sym_declare:
	push {r3}                           @ Protect R3
	mov r3, r0                          @ Get char *S safely out of the way
	mov r0, #20                         @ Using sizeof(struct token_list)
	push {r14}
	bl malloc                           @ Get pointer to A
	pop {r14}
	str r2, [r0]                        @ A->NEXT = LIST
	str r3, [r0, #8]                    @ A->S = S
	str r1, [r0, #12]                   @ A->TYPE = T
	pop {r3}                            @ Restore R3
	bx r14


## match function
## Receives CHAR* in R0 and CHAR* in R1
## Returns 0 (TRUE) or 1 (FALSE) in R0
match:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3
	mov r2, r0                          @ S1 in place
	mov r3, r1                          @ S2 in place
match_Loop:
	ldrb r0, [r2]                       @ S1[0]
	ldrb r1, [r3]                       @ S2[0]
	cmp r0, r1                          @ See if they match
	bne match_False                     @ If not

	add r2, #1                          @ S1 = S1 + 1
	add r3, #1                          @ S2 = S2 + 1
	cmp r0, #0                          @ If reached end of string
	beq match_Done                      @ Perfect match
	b match_Loop                        @ Otherwise keep looping

match_False:
	mov r0, #1                          @ Return false
match_Done:
	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14


## numerate_number function
## Receives an INT A in R0
## Returns char* result in R0
## Allocates 16 bytes of memory
## Behaves badly when given a negative number too large
## Uses R0 for temp, R1 for DIVISOR, R3 for mod/0, R4 for result[i] and R6 for A
numerate_number:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3
	push {r4}                           @ Protect R4
	push {r6}                           @ Protect R6
	mov r6, r0                          @ Protect A

	mov r0, #16                         @ 16bytes
	push {r14}
	bl malloc                           @ Get our pointer
	pop {r14}
	push {r0}                           @ Protect our pointer
	mov r4, r0                          @ put pointer in right place
	adr r8, numerate_big
	ldr r1, [r8]                        @ Set divisor to largest positive number that fits in 32bits

	cmp r6, #0                          @ Deal with 0 case
	beq numerate_number_ZERO            @ If it is
	bgt numerate_number_positive        @ If it is positive

	## Deal with negative case
	mov r0, #45                         @ Using "-"
	strb r0, [r4]                       @ Write it
	add r4, #1                          @ increment
	mov r8, #-1
	mul r6, r8                          @ A = A * -1

numerate_number_positive:
	mov r0, r6                          @ Using A as bottom
	push {r1}                           @ protect our divisor
	push {r14}
	bl divides                          @ r0 / r1 -> r0 + r0 % r1 -> r1 [since I have to implement division manually]
	pop {r14}
	pop {r1}                            @ restore our divisor
	cmp r0, #0                          @ IF 0 == (a / divisor)
	bne numerate_number_iter            @ Clean up those leading Zeros

	mov r0, r1                          @ Using Divisor for bottom
	mov r1, #10                         @ Make this shit work because idiv 10 doesn't work
	push {r14}
	bl divides                          @ r0 / r1 -> r0 + r0 % r1 -> r1 [since I have to implement division manually]
	pop {r14}
	mov r1, r0                          @ Update divisor
	b numerate_number_positive          @ Keep collecting

numerate_number_iter:
	cmp r1, #0                          @ IF DIVISOR < 0
	ble numerate_number_done            @ Be done

	mov r0, r6                          @ Using A as bottom
	push {r1}                           @ protect our divisor
	push {r14}
	bl divides                          @ r0 / r1 -> r0 + r0 % r1 -> r1 [since I have to implement division manually]
	pop {r14}
	mov r6, r1                          @ a = a % divisor
	pop {r1}                            @ restore our divisor
	add r0, #48                         @ ((a / divisor) + 48)
	strb r0, [r4]                       @ Write it

	mov r0, r1                          @ Using Divisor for bottom
	mov r1, #10                         @ Make this shit work because idiv 10 doesn't work
	push {r14}
	bl divides                          @ r0 / r1 -> r0 + r0 % r1 -> r1 [since I have to implement division manually]
	pop {r14}
	mov r1, r0                          @ Update divisor

	add r4, #1                          @ increment
	b numerate_number_iter              @ Keep going

numerate_number_done:
	pop {r0}                            @ Restore our result
	pop {r6}                            @ Restore R6
	pop {r4}                            @ Restore R4
	pop {r3}                            @ Restore EDX
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14

numerate_number_ZERO:
	mov r0, #48                         @ Using '0'
	strb r0, [r4]                       @ Write it
	add r4, #1                          @ increment
	b numerate_number_done              @ Be done

numerate_big: .word 0x3B9ACA00

## numerate_string function
## Receives CHAR* in R0
## Returns value of CHAR* in R0
## Uses R0 for VALUE, R1 for S, R2 for CH and R4 for NEGATIVE?
numerate_string:
	push {r1}                           @ Protect R1
	push {r2}                           @ Protect R2
	push {r3}                           @ Protect R3
	push {r4}                           @ Protect R4
	mov r1, r0                          @ put S in correct place
	mov r0, #0                          @ Initialize to Zero
numerate_string_loop:
	ldrb r2, [r1, #1]                   @ S[1]
	cmp r2, #120                        @ IF 'x' == S[1]
	beq numerate_hex                    @ Deal with hex input

	## Assume decimal input
	mov r4, #0                          @ Assume no negation
	ldrb r2, [r1]                       @ S[0]
	cmp r2, #45                         @ IF '-' == S[0]
	bne numerate_decimal                @ Skip negation

	mov r4, #1                          @ Set FLAG
	add r1, #1                          @ S = S + 1

numerate_decimal:
	ldrb r2, [r1]                       @ S[0]
	cmp r2, #0                          @ IF NULL == S[0]
	beq numerate_decimal_done           @ We are done

	mov r8, #10
	mul r0, r8                          @ VALUE = VALUE * 10
	sub r2, #48                         @ CH = CH - '0'
	cmp r2, #9                          @ Check for illegal
	bgt numerate_string_fail            @ If CH > '9'
	cmp r2, #0                          @ Check for illegal
	blt numerate_string_fail            @ IF CH < 0
	add r0, r2                          @ VALUE = VALUE + CH
	add r1, #1                          @ S = S + 1
	b numerate_decimal                  @ Keep looping

numerate_decimal_done:
	cmp r4, #1                          @ Check if need to negate
	bne numerate_string_done            @ Nope

	mov r8, #-1
	mul r0, r8                          @ VALUE = VALUE * -1
	b numerate_string_done              @ Done

numerate_hex:
	add r1, #2                          @ S = S + 2
numerate_hex_loop:
	ldrb r2, [r1]                       @ S[0]
	cmp r2, #0                          @ IF NULL == S[0]
	beq numerate_string_done            @ We are done

	lsl r0, #4                          @ VALUE = VALUE << 4
	sub r2, #48                         @ CH = CH - '0'
	cmp r2, #10                         @ IF 10 >= CH
	blt numerate_hex_digit              @ NO
	sub r2, #7                          @ Push A-F into range
numerate_hex_digit:
	cmp r2, #15                         @ Check for illegal
	bgt numerate_string_fail            @ If CH > 'F'
	cmp r2, #0                          @ Check for illegal
	blt numerate_string_fail            @ IF CH < 0
	add r0, r2                          @ VALUE = VALUE + CH
	add r1, #1                          @ S = S + 1
	b numerate_hex_loop                 @ Keep looping

numerate_string_fail:
	mov r0, #0                          @ return ZERO

numerate_string_done:
	pop {r4}                            @ Restore R4
	pop {r3}                            @ Restore R3
	pop {r2}                            @ Restore R2
	pop {r1}                            @ Restore R1
	bx r14


## divides function
## Recieves number in R0 and divisor in R1
## Returns R0/R1 in R0 and R0 % R1 in R1
divides:
	push {r4}                           @ Protect R4
	push {r3}                           @ Protect R3
	push {r2}                           @ Protect R2

	# Swap the below to number in R1 and divisor in R0
	mov r2, r0
	mov r3, r1

	mov r0, #0
	cmp r2, #0
#	rsblt r2, r2,  #0                   @ Uncomment for signed
	sublt r0, r0,  #1
	cmp r3, #0
	rsblt r3, r3, #0
	mvnlt r0, r0
	mov r4, r0

	mov  r0,  #32
	mov  r1,  #0
divides_loop:
	adds r2, r2, r2
	adcs r1, r1, r1
	cmp  r1, r3
	subge  r1, r1, r3
	addge  r2, r2, #1
	sub  r0, r0, #1
	cmp  r0, #0
	bne  divides_loop

#	cmp r4, #0                          @ Uncomment for signed
#	rsbne r2, r2, #0                    @ Uncomment for signed
	mov r0, r2

	pop {r2}                            @ Restore R2
	pop {r3}                            @ Restore R3
	pop {r4}                            @ Restore R4
	bx r14


## Exit_Failure function
## Receives nothing
## And aborts hard
## Does NOT return
Exit_Failure:
	mov r0, #1                          @ All is wrong
	mov r7, #1                          @ put the exit syscall number in r7
	svc #0                              @ Call it a bad day


## debug_list function
## Receives struct token_list* in R0
## Prints contents of list and exits
## Does NOT return
debug_list:
	mov r6, r0                          @ Protect the list pointer
	mov r0, #2                          @ Using Standard error
	ldr r8, Output_file_address_7
	str r0, [r8]                        @ write to standard error

debug_list_iter:
	## Header
	adr r0, debug_list_string0          @ Using our first string
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	mov r0, r6                          @ Use address of pointer
	push {r14}
	bl numerate_number                  @ Convert it into string
	bl File_Print                       @ Print it
	pop {r14}

	## NEXT
	adr r0, debug_list_string1          @ Using our second string
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	ldr r0, [r6]                        @ Use address of pointer
	push {r14}
	bl numerate_number                  @ Convert it into string
	bl File_Print                       @ Print it
	pop {r14}

	## PREV
	adr r0, debug_list_string2          @ Using our third string
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	ldr r0, [r6, #4]                    @ Use address of pointer
	push {r14}
	bl numerate_number                  @ Convert it into string
	bl File_Print                       @ Print it
	pop {r14}

	## S
	adr r0, debug_list_string3          @ Using our fourth string
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	ldr r0, [r6, #8]                    @ Use address of pointer
	push {r14}
	bl numerate_number                  @ Convert it into string
	bl File_Print                       @ Print it
	pop {r14}

	## S Contents
	adr r0, debug_list_string4          @ Using our fifth string
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	ldr r0, [r6, #8]                    @ Use address of string
	cmp r0, #0                          @ IF NULL Pointer
	bne debug_list_null                 @ otherwise display
	adr r0, debug_list_string_null      @ Give meaningful message instead
debug_list_null:
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}

	## TYPE
	adr r0, debug_list_string5          @ Using our sixth string
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	ldr r0, [r6, #12]                   @ Use address of pointer
	push {r14}
	bl numerate_number                  @ Convert it into string
	bl File_Print                       @ Print it
	pop {r14}

	## ARGS/DEPTH
	adr r0, debug_list_string6          @ Using our seventh string
	push {r14}
	bl File_Print                       @ Print it
	pop {r14}
	ldr r0, [r6, #16]                   @ Use address of pointer
	push {r14}
	bl numerate_number                  @ Convert it into string
	bl File_Print                       @ Print it
	pop {r14}

	mov r0, #10                         @ Add "\n"
	push {r14}
	bl fputc                            @ print it
	bl fputc                            @ print it
	pop {r14}

	ldr r6, [r6]                        @ TOKEN = TOKEN->NEXT
	cmp r6, #0                          @ Check if NULL
	bne debug_list_iter                 @ iterate otherwise

	mov r0, #666                        @ All is HELL
	mov r7, #1                          @ put the exit syscall number in r7
	svc #0                              @ Call it a bad day

debug_list_string0: .asciz "Token_list node at address: "
.balign 4
debug_list_string1: .asciz "\nNEXT address: "
.balign 4
debug_list_string2: .asciz "\nPREV address: "
.balign 4
debug_list_string3: .asciz "\nS address: "
.balign 4
debug_list_string4: .asciz "\nThe contents of S are: "
.balign 4
debug_list_string5: .asciz "\nTYPE address: "
.balign 4
debug_list_string6: .asciz "\nARGUMENTS address: "
.balign 4
debug_list_string_null: .asciz ">::<NULL>::<"
.balign 4
Output_file_address_7: .word Output_file


.data
prim_types:
type_void:
	.word type_int                      @ NEXT
	.word 4                             @ SIZE
	.word 0                             @ OFFSET
	.word type_void                     @ INDIRECT
	.word 0                             @ MEMBERS
	.word type_void                     @ TYPE
	.word type_void_name                @ NAME
type_void_name: .asciz "void"

type_int:
	.word type_char                     @ NEXT
	.word 4                             @ SIZE
	.word 0                             @ OFFSET
	.word type_int                      @ INDIRECT
	.word 0                             @ MEMBERS
	.word type_int                      @ TYPE
	.word type_int_name                 @ NAME
type_int_name: .asciz "int"

type_char:
	.word type_file                     @ NEXT
	.word 1                             @ SIZE
	.word 0                             @ OFFSET
	.word type_char_indirect            @ INDIRECT
	.word 0                             @ MEMBERS
	.word type_char                     @ TYPE
	.word type_char_name                @ NAME
type_char_name: .asciz "char"

type_char_indirect:
	.word type_file                     @ NEXT
	.word 4                             @ SIZE
	.word 0                             @ OFFSET
	.word type_char_double_indirect     @ INDIRECT
	.word 0                             @ MEMBERS
	.word type_char_indirect            @ TYPE
	.word type_char_indirect_name       @ NAME
type_char_indirect_name: .asciz "char*"

type_char_double_indirect:
	.word type_file                     @ NEXT
	.word 4                             @ SIZE
	.word 0                             @ OFFSET
	.word type_char_double_indirect     @ INDIRECT
	.word 0                             @ MEMBERS
	.word type_char_indirect            @ TYPE
	.word type_char_double_indirect_name @ NAME
type_char_double_indirect_name: .asciz "char**"

type_file:
	.word type_function                 @ NEXT
	.word 4                             @ SIZE
	.word 0                             @ OFFSET
	.word type_file                     @ INDIRECT
	.word 0                             @ MEMBERS
	.word type_file                     @ TYPE
	.word type_file_name                @ NAME
type_file_name: .asciz "FILE"

type_function:
	.word type_unsigned                 @ NEXT
	.word 4                             @ SIZE
	.word 0                             @ OFFSET
	.word type_function                 @ INDIRECT
	.word 0                             @ MEMBERS
	.word type_function                 @ TYPE
	.word type_function_name            @ NAME
type_function_name: .asciz "FUNCTION"

type_unsigned:
	.word type_long                     @ NEXT
	.word 4                             @ SIZE
	.word 0                             @ OFFSET
	.word type_unsigned                 @ INDIRECT
	.word 0                             @ MEMBERS
	.word type_unsigned                 @ TYPE
	.word type_unsigned_name            @ NAME
type_unsigned_name: .asciz "unsigned"

type_long:
	.word 0                             @ NEXT
	.word 4                             @ SIZE
	.word 0                             @ OFFSET
	.word type_long                     @ INDIRECT
	.word 0                             @ MEMBERS
	.word type_long                     @ TYPE
	.word type_long_name                @ NAME
type_long_name: .asciz "long"

C: .word 0
Input_file: .word 0
MALLOC: .word 0
Output_file: .word 0
Token: .word 0
break_frame: .word 0
break_target_func: .word 0
break_target_head: .word 0
break_target_num: .word 0
current_count: .word 0
current_target: .word 0
function: .word 0
global_constant_list: .word 0
global_function_list: .word 0
global_symbol_list: .word 0
global_token: .word 0
global_types: .word prim_types
globals_list: .word 0
output_list: .word 0
string_index: .word 0
strings_list: .word 0
