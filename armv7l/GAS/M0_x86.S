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
	## R0, R2, R1 => Temps
	## R5 => MALLOC
	## R6 => HEAD
	## [Output] => Output_file
	## [Input] => Input_file

	## Struct format: (size 32)
	## NEXT => 0
	## TYPE => 8
	## TEXT => 16
	## EXPRESSION => 24

	## Types
	## None => 0
	## MACRO => 1
	## STRING => 2

# Where the ELF Header is going to hit
# Simply jump to _start
# Our main function
_start:
	pop {r0}                    @ Get the number of arguments
	pop {r0}                    @ Get the program name
	pop {r0}                    @ Get the actual input name
	mov r1, #0                  @ prepare read_only
	mov r7, #5                  @ the syscall number for open()
	svc #0                      @ Now open that damn file
	ldr r8, Input_address
	str r0, [r8]                @ Preserve the file pointer we were given

	pop {r0}                    @ Get the actual output name
	mov r1, #577                @ Prepare file as O_WRONLY|O_CREAT|O_TRUNC
	mov r2, #384                @ Prepare file as RW for owner only (600 in octal)
	mov r7, #5                  @ the syscall number for open()
	svc #0                      @ Now open that damn file
	cmp r0, #0                  @ Check for missing output
	bgt _start_out              @ Have real input
	mov r0, #1                  @ Use stdout

_start_out:
	ldr r8, Output_address
	str r0, [r8]                @ Preserve the file pointer we were given

	mov r7, #45                 @ the Syscall # for SYS_BRK
	mov r0, #0                  @ Get current brk
	svc #0                      @ Let the kernel do the work
	mov r5, r0                  @ Set our malloc pointer

	push {r14}
	bl Tokenize_Line            @ Get all lines
	mov r0, r6                  @ prepare for Reverse_List
	bl Reverse_List             @ Correct order
	mov r6, r0                  @ Update HEAD
	bl Identify_Macros          @ Find the DEFINEs
	bl Line_Macro               @ Apply the DEFINEs
	bl Process_String           @ Handle strings
	bl Eval_Immediates          @ Handle Numbers
	bl Preserve_Other           @ Collect the remaining
	bl Print_Hex                @ Output our results
	pop {r14}

Done:
	# program completed Successfully
	mov r0, #0                  @ All is well
	mov r7, #1                  @ put the exit syscall number in r7
	svc #0                      @ Call it a good day


## Tokenize_Line Function
## Using input file [Input] and Head R6
## Creates a linked list of structs
## Uses R1 for in_set strings, R2 for Int C and R3 for Struct Token* p
Tokenize_Line:
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	push {r3}                   @ Protect R3
restart:
	push {r14}
	bl fgetc                    @ Read a char
	pop {r14}
	cmp r0, #-4                 @ Check for EOF
	beq done                    @ File is collected

	mov r2, r0                  @ Protect C

	adr r1, comments            @ Get pointer to "#;"
	push {r14}
	bl In_Set                   @ Check for comments
	pop {r14}
	cmp r0, #1                  @ If comments
	beq Purge_LineComment       @ try again

	mov r0, r2                  @ put C in place for check
	adr r1, terminators         @ Get pointer to "\n\t "
	push {r14}
	bl In_Set                   @ Check for terminators
	pop {r14}
	cmp r0, #1                  @ If terminator
	beq restart                 @ try again

	mov r0, #32                 @ Malloc the struct P
	push {r14}
	bl malloc                   @ Get pointer to P
	mov r3, r0                  @ Protect P
	str r6, [r3]                @ P->NEXT = HEAD
	mov r6, r3                  @ HEAD = P

	mov r0, r2                  @ put C in place for check
	adr r1, string_char         @ Get pointer to "\"'"
	bl In_Set                   @ Check for string chars
	pop {r14}
	cmp r0, #1                  @ If string char
	beq Store_String            @ Get string

	push {r14}
	bl Store_Atom               @ Get whole token
	pop {r14}
	b restart

done:
	pop {r3}                    @ Restore R3
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	bx r14


## fgetc function
## Receives FILE* in [Input]
## Returns -4 (EOF) or char in R0
fgetc:
	push {r3}                   @ Protect R3
	push {r2}                   @ Protect R2
	push {r1}                   @ Protect R1
	mov r0, #-4                 @ Put EOF in r0
	push {r0}                   @ Assume bad (If nothing read, value will remain EOF)
	mov r1, r13                 @ Get stack address
	ldr r8, Input_address
	ldr r0, [r8]                @ Where are we reading from
	mov r7, #3                  @ the syscall number for read
	mov r2, #1                  @ set the size of chars we want
	svc #0                      @ call the Kernel
	pop {r0}                    @ Get either char or EOF
	cmp r0, #-4
	andne r0, #0xFF
	pop {r1}                    @ Restore R1
	pop {r2}                    @ Restore R2
	pop {r3}                    @ Restore R3
	bx r14


## Malloc isn't actually required if the program being built fits in the initial memory
## However, it doesn't take much to add it.
## Requires R5 to be initialized and R0 to have the number of desired bytes
malloc:
	push {r3}                   @ Protect R3
	push {r2}                   @ Protect R2
	push {r1}                   @ Protect R1

	mov r1, r5                  @ Using the current pointer
	add r0, r5                  @ Request the number of desired bytes
	mov r7, #45                 @ the Syscall # for SYS_BRK
	svc #0                      @ call the Kernel
	mov r5, r0                  @ Update pointer
	mov r0, r1                  @ Return pointer

	pop {r1}                    @ Restore R1
	pop {r2}                    @ Restore R2
	pop {r3}                    @ Restore R3
	bx r14


## Purge_LineComment function
## Reads chars until LF and jumps to restart
Purge_LineComment:
	push {r14}
	bl fgetc                    @ Get a char
	pop {r14}
	cmp r0, #10                 @ While not LF
	bne Purge_LineComment       @ Keep reading
	b restart


## Store_String Function
## Receives C in R2, HEAD in R3 and Input file in [Output]
## Uses R1 for terminator, R2 for C and R3 for string
Store_String:
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	push {r3}                   @ Protect R3

	mov r0, #2                  @ Using TYPE STRING
	str r0, [r3, #8]            @ HEAD->TYPE = STRING
	mov r0, #256                @ Malloc the string
	push {r14}
	bl malloc                   @ Get pointer to P
	pop {r14}
	str r0, [r3, #16]           @ HEAD->TEXT = STRING
	mov r1, r2                  @ Protect terminator
	mov r3, r0                  @ Protect string pointer
Store_String_Loop:
	strb r2, [r3]               @ write byte
	push {r14}
	bl fgetc                    @ read next char
	pop {r14}
	mov r2, r0                  @ Update C
	add r3, #1                  @ STRING = STRING + 1
	cmp r2, r1                  @ See if we hit terminator
	bne Store_String_Loop       @ Otherwise keep looping

	pop {r3}                    @ Restore R3
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	mov r0, r3                  @ return HEAD
	b restart


## Store_Atom Function
## Receives C in R2, HEAD in R3 and Input file in [Input]
## Uses R1 for in_set strings, R2 for C and R3 for string
Store_Atom:
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	push {r3}                   @ Protect R3

	mov r0, #256                @ Malloc the string
	push {r14}
	bl malloc                   @ Get pointer to P
	pop {r14}
	str r0, [r3, #16]           @ HEAD->TEXT = STRING
	adr r1, terminators         @ Get pointer to "\n\t "
	mov r3, r0                  @ Protect string pointer
Store_Atom_loop:
	strb r2, [r3]               @ write byte
	push {r14}
	bl fgetc                    @ read next char
	pop {r14}
	mov r2, r0                  @ Update C
	add r3, #1                  @ STRING = STRING + 1
	push {r14}
	bl In_Set                   @ Check for terminators
	pop {r14}
	cmp r0, #0                  @ Check for "\n\t "
	beq Store_Atom_loop         @ Loop otherwise

	pop {r3}                    @ Restore R3
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	mov r0, r3                  @ return HEAD
	bx r14


## In_Set function
## Receives Char C in R0 and CHAR* in R1
## Returns 1 if true, zero if false in R0
In_Set:
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
In_Set_loop:
	ldrb r2, [r1]               @ Read char

	cmp r0, r2                  @ See if they match
	beq In_Set_True             @ return true

	cmp r2, #0                  @ Check for NULL
	beq In_Set_False            @ return false

	add r1, #1                  @ s = s + 1
	b In_Set_loop               @ Keep looping

In_Set_True:
	mov r0, #1                  @ Set True
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	bx r14

In_Set_False:
	mov r0, #0                  @ Set FALSE
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	bx r14

# Char sets
terminators:
	.byte 10, 9, 32, 0

comments:
	.byte 35, 59, 0, 0

string_char:
	.byte 34, 39, 0, 0


## Reverse_List function
## Receives List in R0
## Returns the list reversed in R0
Reverse_List:
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	mov r1, r0                  @ Set HEAD
	mov r0, #0                  @ ROOT = NULL
Reverse_List_Loop:
	cmp r1, #0                  @ WHILE HEAD != NULL
	beq Reverse_List_Done       @ Stop otherwise

	ldr r2, [r1]                @ NEXT = HEAD->NEXT
	str r0, [r1]                @ HEAD->NEXT = ROOT
	mov r0, r1                  @ ROOT = HEAD
	mov r1, r2                  @ HEAD = NEXT
	b Reverse_List_Loop         @ Keep Going

Reverse_List_Done:
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	bx r14


## Identify_Macros function
## Receives List in R0
## Updates the list in place; does not modify registers
## Uses R1 for DEFINE, R2 for I
Identify_Macros:
	push {r0}                   @ Protect R0
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	push {r3}                   @ Protect R3
	adr r1, DEFINE_str          @ Setup define string
	mov r2, r0                  @ I = HEAD
Identify_Macros_Loop:
	ldr r0, [r2, #16]           @ I->TEXT
	push {r14}
	bl match                    @ IF "DEFINE" == I->TEXT
	pop {r14}
	cmp r0, #0                  @ Check if match
	bne Identify_Macros_Next    @ Skip the work

	## Deal with MACRO
	mov r0, #1                  @ Using MACRO
	str r0, [r2, #8]            @ I->TYPE = MACRO

	ldr r0, [r2]                @ I->NEXT
	ldr r0, [r0, #16]           @ I->NEXT->TEXT
	str r0, [r2, #16]           @ I->TEXT = I->NEXT->TEXT

	ldr r0, [r2]                @ I->NEXT
	ldr r0, [r0]                @ I->NEXT->NEXT
	ldr r0, [r0, #16]           @ I->NEXT->NEXT->TEXT
	str r0, [r2, #24]           @ I->EXPRESSION = I->NEXT->NEXT->TEXT

	ldr r0, [r2]                @ I->NEXT
	ldr r0, [r0]                @ I->NEXT->NEXT
	ldr r0, [r0]                @ I->NEXT->NEXT->NEXT
	str r0, [r2]                @ I->NEXT = I->NEXT->NEXT->NEXT

Identify_Macros_Next:
	ldr r2, [r2]                @ I = I->NEXT
	cmp r2, #0                  @ Check for NULL
	bne Identify_Macros_Loop    @ Keep looping otherwise

	pop {r3}                    @ Restore R3
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	pop {r0}                    @ Restore R0
	bx r14

DEFINE_str:
	.byte 68, 69, 70, 73, 78, 69, 0, 0


## match function
## Receives CHAR* in R0 and CHAR* in R1
## Returns 0 (TRUE) or 1 (FALSE) in R0
match:
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	push {r3}                   @ Protect R3
	mov r2, r0                  @ S1 in place
	mov r3, r1                  @ S2 in place
match_Loop:
	ldrb r0, [r2]               @ S1[0]
	ldrb r1, [r3]               @ S2[0]
	cmp r0, r1                  @ See if they match
	bne match_False             @ If not

	add r2, #1                  @ S1 = S1 + 1
	add r3, #1                  @ S2 = S2 + 1
	cmp r0, #0                  @ If reached end of string
	beq match_Done              @ Perfect match
	b match_Loop                @ Otherwise keep looping

match_False:
	mov r0, #1                  @ Return false
match_Done:
	pop {r3}                    @ Restore R3
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	bx r14


## Line_Macro function
## Receives List in R0
## Updates the list in place; does not modify registers
## Uses R0 for I, R1 for I->TEXT, R2 for I->EXPRESSION
Line_Macro:
	push {r0}                   @ Protect R0
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	push {r3}                   @ Protect R3
Line_Macro_Loop:
	ldr r1, [r0, #8]            @ I->TYPE
	cmp r1, #1                  @ IF MACRO == I->TYPE
	bne Line_Macro_Next         @ Otherwise move on

	# Is a macro apply
	ldr r1, [r0, #16]           @ I->TEXT
	ldr r2, [r0, #24]           @ I->EXPRESSION
	ldr r0, [r0]                @ I->NEXT
	push {r14}
	bl Set_Expression           @ Apply it
	pop {r14}
	b Line_Macro_Loop           @ Move on to next

Line_Macro_Next:
	ldr r0, [r0]                @ I->NEXT
	cmp r0, #0                  @ Check for NULL
	bne Line_Macro_Loop         @ Keep going

	pop {r3}                    @ Restore R3
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	pop {r0}                    @ Restore R0
	bx r14


## Set_Expression function
## Receives List in R0, CHAR* in R1 and CHAR* in R2
## Updates the list in place; does not modify registers
## Uses R1 for C, R2 for EXP and R3 for I
Set_Expression:
	push {r0}                   @ Protect R0
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	push {r3}                   @ Protect R3
	mov r3, r0                  @ Set I
Set_Expression_Loop:
	ldr r0, [r3, #8]            @ I->TYPE
	cmp r0, #1                  @ IF MACRO == I->TYPE
	beq Set_Expression_Next     @ Ignore and move on

	ldr r0, [r3, #16]           @ I->TEXT
	push {r14}
	bl match                    @ Check for match
	pop {r14}
	cmp r0, #0                  @ If match
	bne Set_Expression_Next     @ Otherwise next

	# We have a non-macro match
	str r2, [r3, #24]           @ I->EXPRESSION = EXP

Set_Expression_Next:
	ldr r3, [r3]                @ I = I->NEXT
	cmp r3, #0                  @ IF NULL == I
	bne Set_Expression_Loop     @ Otherwise keep looping

	pop {r3}                    @ Restore R3
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	pop {r0}                    @ Restore R0
	bx r14


## Process_String function
## Receives List in R0
## Update the list in place; does not modify registers
## Uses R1 for I->TEXT, R2 for I and R3 for S
Process_String:
	push {r0}                   @ Protect R0
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	push {r3}                   @ Protect R3
	mov r2, r0                  @ I = HEAD
Process_String_loop:
	ldr r0, [r2, #8]            @ I->TYPE
	cmp r0, #2                  @ IF STRING == I->TYPE
	bne Process_String_Next     @ Skip to next

	ldr r1, [r2, #16]           @ I->TEXT
	ldrb r0, [r1]               @ I->TEXT[0]
	cmp r0, #39                 @ IF '\'' == I->TEXT[0]
	bne Process_String_Raw      @ Deal with '\"'

	# Deal with '\''
	add r1, #1                  @ I->TEXT + 1
	str r1, [r2, #24]           @ I->EXPRESSION = I->TEXT + 1
	b Process_String_Next       @ Move on to next

Process_String_Raw:
	mov r0, r1                  @ Get length of I->TEXT
	push {r14}
	bl string_length            @ Do it
	asr r0, #2                  @ LENGTH = LENGTH >> 2
	add r0, #1                  @ LENGTH = LENGTH + 1
	lsl r0, #3                  @ LENGTH = LENGTH << 3
	bl malloc                   @ Get string
	pop {r14}
	mov r3, r1                  @ S = I->TEXT
	add r3, #1                  @ S = S + 1
	str r0, [r2, #24]           @ I->EXPRESSION = hexify
	mov r1, r0                  @ Put hexify buffer in r1

Process_String_Raw_Loop:
	ldrb r0, [r3]               @ Read 1 chars
	add r3, #1                  @ S = S + 1
	cmp r0, #0                  @ Check for NULL
	mrs r8, cpsr
	push {r8}                   @ Protect condition
	push {r14}
	bl hex8                     @ write them all
	pop {r14}
	pop {r8}                    @ restore condition
	msr cpsr, r8
	bne Process_String_Raw_Loop @ Keep looping

Process_String_Next:
	ldr r2, [r2]                @ I = I->NEXT
	cmp r2, #0                  @ IF NULL == I
	bne Process_String_loop     @ Otherwise keep looping

	pop {r3}                    @ Restore R3
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	pop {r0}                    @ Restore R0
	bx r14


## string_length function
## Receives CHAR* in R0
## Returns INT in R0
## Uses R0 for CH, R1 for S and R2 for INDEX
string_length:
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	mov r1, r0                  @ Set S
	mov r2, #0                  @ INDEX = 0
string_length_loop:
	ldrb r0, [r1, r2]           @ S[0]
	cmp r0, #0                  @ IF NULL == S[0]
	beq string_length_done      @ Stop

	add r2, #1                  @ INDEX = INDEX + 1
	b string_length_loop        @ Keep going

string_length_done:
	mov r0, r2                  @ RETURN INDEX
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	bx r14


## Eval_Immediates function
## Receives List in R0
## Updates the list in place; does not modify registers
## Uses R1 for I->TEXT[0], R2 for I->TEXT[1] and R3 for I
Eval_Immediates:
	push {r0}                   @ Protect R0
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	push {r3}                   @ Protect R3
	mov r3, r0                  @ I = HEAD
Eval_Immediates_Loop:
	# Check for MACRO
	ldr r0, [r3, #8]            @ I->TYPE
	cmp r0, #1                  @ IF MACRO == I-TYPE
	beq Eval_Immediates_Next    @ Skip to next

	# Check for NULL EXPRESSION
	ldr r0, [r3, #24]           @ I->EXPRESSION
	cmp r0, #0                  @ IF NULL == I->EXPRESSION
	bne Eval_Immediates_Next    @ Skip to next

	# Check if number
	ldr r0, [r3, #16]           @ I->TEXT
	ldrb r1, [r0]               @ I->TEXT[0]
	add r0, #1                  @ I->TEXT + 1
	ldrb r2, [r0]               @ I->TEXT[1]
	push {r14}
	bl numerate_string          @ Convert string to INT
	pop {r14}
	cmp r0, #0                  @ IF 0 == numerate_number(I->TEXT + 1)
	bne Eval_Immediates_value   @ Has a value

	# Last chance for Immediate
	cmp r2, #48                 @ If '0' == I->TEXT[1]
	bne Eval_Immediates_Next    @ Skip to next

Eval_Immediates_value:
	push {r14}
	bl express_number           @ Convert value to hex string
	pop {r14}
	str r0, [r3, #24]           @ I->EXPRESSION = express_number(value, I-TEXT[0])

Eval_Immediates_Next:
	ldr r3, [r3]                @ I = I->NEXT
	cmp r3, #0                  @ IF NULL == I
	bne Eval_Immediates_Loop    @ Otherwise keep looping

	pop {r3}                    @ Restore R3
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	pop {r0}                    @ Restore R0
	bx r14


## numerate_string function
## Receives CHAR* in R0
## Returns value of CHAR* in R0
## Uses R0 for VALUE, R1 for S, R2 for CH and R5 for NEGATIVE?
numerate_string:
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	push {r3}                   @ Protect R3
	push {r5}                   @ Protect R5
	mov r1, r0                  @ put S in correct place
	mov r0, #0                  @ Initialize to Zero
numerate_string_loop:
	ldrb r2, [r1, #1]           @ S[1]
	cmp r2, #120                @ IF 'x' == S[1]
	beq numerate_hex            @ Deal with hex input

	# Assume decimal input
	mov r2, #0                  @ Assume no negation
	ldrb r2, [r1]               @ S[0]
	cmp r2, #45                 @ IF '-' == S[0]
	bne numerate_decimal        @ Skip negation

	mov r5, #1                  @ Set FLAG
	add r1, #1                  @ S = S + 1

numerate_decimal:
	ldrb r2, [r1]               @ S[0]
	cmp r2, #0                  @ IF NULL == S[0]
	beq numerate_decimal_done   @ We are done

	mov r8, #10
	mul r0, r8                  @ VALUE = VALUE * 10
	sub r2, #48                 @ CH = CH - '0'
	cmp r2, #9                  @ Check for illegal
	bgt numerate_string_fail    @ If CH > '9'
	cmp r2, #0                  @ Check for illegal
	blt numerate_string_fail    @ IF CH < 0
	add r0, r2                  @ VALUE = VALUE + CH
	add r1, #1                  @ S = S + 1
	b numerate_decimal          @ Keep looping

numerate_decimal_done:
	cmp r5, #1                  @ Check if need to negate
	bne numerate_string_done    @ Nope

	mov r8, #-1
	mul r0, r8                  @ VALUE = VALUE * -1
	b numerate_string_done      @ Done

numerate_hex:
	add r1, #2                  @ S = S + 2
numerate_hex_loop:
	ldrb r2, [r1]               @ S[0]
	cmp r2, #0                  @ IF NULL == S[0]
	beq numerate_string_done    @ We are done

	lsl r0, #4                  @ VALUE = VALUE << 4
	sub r2, #48                 @ CH = CH - '0'
	cmp r2, #10                 @ IF 10 >= CH
	blt numerate_hex_digit      @ NO
	sub r2, #7                  @ Push A-F into range
numerate_hex_digit:
	cmp r2, #15                 @ Check for illegal
	bgt numerate_string_fail    @ If CH > 'F'
	cmp r2, #0                  @ Check for illegal
	blt numerate_string_fail    @ IF CH < 0
	add r0, r2                  @ VALUE = VALUE + CH
	add r1, #1                  @ S = S + 1
	b numerate_hex_loop         @ Keep looping

numerate_string_fail:
	mov r0, #0                  @ return ZERO

numerate_string_done:
	pop {r5}                    @ Restore R5
	pop {r3}                    @ Restore R3
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	bx r14


## express_number function
## Receives INT in R0 and CHAR in R1
## Allocates a string and expresses the value in hex
## Returns string in R0
## Uses R0 for VALUE, R1 for S and R2 for CH
express_number:
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	push {r3}                   @ Protect R3
	mov r2, r1                  @ Put CH in right place
	mov r1, r0                  @ Protect VALUE
	cmp r2, #37                 @ IF '%' == CH
	bne express_number2         @ Otherwise try @

	mov r0, #9                  @ We need 3bytes
	push {r14}
	bl malloc                   @ Get S pointer
	pop {r14}
	mov r8, r0
	mov r0, r1                  @ Put S and VALUE in place
	mov r1, r8
	push {r1}                   @ Protect S
	push {r14}
	bl hex32l                   @ Store 32bits
	pop {r14}
	b express_number_done       @ done

express_number2:
	cmp r2, #64                 @ IF '@' == CH
	bne express_number1         @ Othrewise try !

	mov r0, #5                  @ We need 3bytes
	push {r14}
	bl malloc                   @ Get S pointer
	pop {r14}
	mov r8, r0
	mov r0, r1                  @ Put S and VALUE in place
	mov r1, r8
	push {r1}                   @ Protect S
	push {r14}
	bl hex16l                   @ Store 16bits
	pop {r14}
	b express_number_done       @ done

express_number1:
	mov r0, #3                  @ We need 3bytes
	push {r14}
	bl malloc                   @ Get S pointer
	pop {r14}
	mov r8, r0
	mov r0, r1                  @ Put S and VALUE in place
	mov r1, r8
	push {r1}                   @ Protect S
	push {r14}
	bl hex8                     @ Store 8bit
	pop {r14}

express_number_done:
	pop {r0}                    @ Restore S
	pop {r3}                    @ Restore R3
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	bx r14


## HEX to ascii routine
## Receives INT in R0 and CHAR* in R1
## Stores ascii of INT in CHAR*
## Returns only modifying R0
hex64l:
	push {r0}                   @ Protect top 32
	push {r14}
	bl hex32l                   @ Store it
	pop {r14}
	pop {r0}                    @ do top 32
	asr r0, #32                 @ do bottom 32 first
hex32l:
	push {r0}                   @ Protect top 16
	push {r14}
	bl hex16l                   @ Store it
	pop {r14}
	pop {r0}                    @ do top 16
	asr r0, #16                 @ do bottom 16 first
hex16l:
	push {r0}                   @ Protect top byte
	push {r14}
	bl hex8                     @ Store it
	pop {r14}
	pop {r0}                    @ do high byte
	asr r0, #8                  @ do bottom byte first
hex8:
	push {r0}                   @ Protect bottom nibble
	asr r0, #4                  @ do high nibble first
	push {r14}
	bl hex4                     @ Store it
	pop {r14}
	pop {r0}                    @ do low nibble
hex4:
	and r0, #0xf                @ isolate nibble
	add r0, #'0'                @ convert to ascii
	cmp r0, #'9'                @ valid digit?
	ble hex1                    @ yes
	add r0, #7                  @ use alpha range
hex1:
	strb r0, [r1]               @ store result
	add r1, #1                  @ next position
	bx r14


## Preserve_Other function
## Receives List in R0
## Updates the list in place; does not modify registers
## Uses R0 for I, R1 for I->TEXT
Preserve_Other:
	push {r0}                   @ Protect R0
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	push {r3}                   @ Protect R3
Preserve_Other_Loop:
	ldr r1, [r0, #24]           @ I->EXPRESSION
	cmp r1, #0                  @ IF NULL == I->EXPRESSION
	bne Preserve_Other_Next     @ Otherwise next

	# Needs preserving
	ldr r1, [r0, #16]           @ I->TEXT
	str r1, [r0, #24]           @ I->EXPRESSION = I->TEXT

Preserve_Other_Next:
	ldr r0, [r0]                @ I = I->NEXT
	cmp r0, #0                  @ IF NULL == I
	bne Preserve_Other_Loop     @ Otherwise keep looping

	pop {r3}                    @ Restore R3
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	pop {r0}                    @ Restore R0
	bx r14


## Print_Hex function
## Receives list in R0
## walks the list and prints the I->EXPRESSION for all nodes followed by newline
## Uses R1 for I
Print_Hex:
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	mov r1, r6                  @ I = Head
Print_Hex_Loop:
	ldr r0, [r1, #8]            @ I->TYPE
	cmp r0, #1                  @ IF MACRO == I->TYPE
	beq Print_Hex_Next          @ Skip

	ldr r0, [r1 , #24]          @ Using EXPRESSION
	push {r14}
	bl File_Print               @ Print it
	mov r0, #10                 @ NEWLINE
	bl fputc                    @ Append it
	pop {r14}

Print_Hex_Next:
	ldr r1, [r1]                @ Iterate to next Token
	cmp r1, #0                  @ Check for NULL
	bne Print_Hex_Loop          @ Otherwise keep looping

	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	bx r14


## File_Print function
## Receives CHAR* in R0
## calls fputc for every non-null char
File_Print:
	push {r1}                   @ Protect R1
	push {r2}                   @ Protect R2
	mov r1, r0                  @ Protect S
	cmp r0, #0                  @ Protect against nulls
	beq File_Print_Done         @ Simply don't try to print them
File_Print_Loop:
	ldrb r0, [r1]               @ Read byte
	cmp r0, #0                  @ Check for NULL
	beq File_Print_Done         @ Stop at NULL

	push {r14}
	bl fputc                    @ write it
	pop {r14}
	add r1, #1                  @ S = S + 1
	b File_Print_Loop           @ Keep going

File_Print_Done:
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	bx r14


## fputc function
## receives CHAR in R0 and FILE* in [Output]
## writes char and returns
fputc:
	push {r3}                   @ Protect R3
	push {r2}                   @ protect R2
	push {r1}                   @ protect R1
	push {r0}                   @ We are writing r0
	mov r1, r13                 @ Get stack address
	ldr r8, Output_address
	ldr r0, [r8]                @ Write to target file
	mov r7, #4                  @ the syscall number for write
	mov r2, #1                  @ set the size of chars we want
	svc #0                      @ call the Kernel
	pop {r0}                    @ Restore stack
	pop {r1}                    @ Restore R1
	pop {r2}                    @ Restore R2
	pop {r3}                    @ Restore R3
	bx r14

## Because ARM doesn't support loading/storing directly to different segments in a single instruction
.balign 4
Input_address: .word Input
Output_address: .word Output


.data
Input:
	.word 0
Output:
	.word 0
