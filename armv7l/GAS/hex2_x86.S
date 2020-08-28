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
	## R0, R3, R2, R1 => Temps
	## R12 => IP
	## R11 => MALLOC
	## R10 => HEAD

	## Struct format: (size 24)
	## NEXT => 0
	## TARGET => 8
	## NAME => 16

# Where the ELF Header is going to hit
# Simply jump to _start
# Our main function
_start:
	mov r0, #0                  @ Get current pointer
	push {r14}
	bl malloc                   @ Get current HEAP
	mov r11, r0                 @ Setup MALLOC
	add r0, #8192000            @ Create space for temp
	bl malloc                   @ Give ourselves 8192000 bytes to work with
	pop {r14}

	pop {r0}                    @ Get the number of arguments
	pop {r0}                    @ Get the program name
	pop {r0}                    @ Get the actual input name
	mov r1, #0                  @ prepare read_only
	mov r2, #0                  @ Really sure
	mov r7, #5                  @ the syscall number for open()
	svc #0                      @ Now open that damn file
	ldr r8, Input_address
	str r0, [r8]                @ Preserve the file pointer we were given

	pop {r0}                    @ Get the actual output name
	mov r1, #577                @ Prepare file as O_WRONLY|O_CREAT|O_TRUNC
	mov r2, #448                @ Prepare file as RWX for owner only (700 in octal)
	mov r7, #5                  @ the syscall number for open()
	svc #0                      @ Now open that damn file
	cmp r0, #0                  @ Check for missing output
	bgt _start_out              @ Have real input
	mov r0, #1                  @ Use stdout

_start_out:
	ldr r8, Output_address
	str r0, [r8]                @ Preserve the file pointer we were given


	push {r14}
	bl ClearScratch             @ Zero scratch
	pop {r14}
	mov r0, #-1                 @ Our flag for byte processing
	ldr r8, Flag_address
	str r0, [r8]                @ Set
	mov r0, #0                  @ temp storage for the sum
	ldr r8, High_address
	str r0, [r8]                @ Set
	ldr r12, start_address      @ Our starting IP
	mov r10, #0                 @ HEAD = NULL
	push {r14}
	bl First_pass               @ Process it
	pop {r14}

	# rewind input file
	ldr r8, Input_address
	ldr r0, [r8]                @ Using our input file
	mov r1, #0                  @ Offset Zero
	mov r2, #0                  @ Whence Zero
	mov r7, #19                 @ lseek
	push {r10}                  @ Protect HEAD
	svc #0
	pop {r10}                   @ Restore HEAD

	mov r0, #-1                 @ Our flag for byte processing
	ldr r8, Flag_address
	str r0, [r8]                @ Set
	mov r0, #0                  @ temp storage for the sum
	ldr r8, High_address
	str r0, [r8]                @ Set
	ldr r12, start_address      @ Our starting IP
	push {r14}
	bl Second_pass              @ Process it
	pop {r14}

	b Done

First_pass:
	push {r14}
	bl Read_byte
	pop {r14}

	# Deal with EOF
	cmp r0, #-4
	beq First_pass_done

	# Check for :
	cmp r0, #0x3a
	bne First_pass_0

	# Deal with label
	b StoreLabel

First_pass_0:
	# Check for !
	cmp r0, #0x21
	beq First_pass_pointer

	# Check for @
	cmp r0, #0x40
	beq First_pass_pointer

	# Check for $
	cmp r0, #0x24
	beq First_pass_pointer

	# Check for %
	cmp r0, #0x25
	beq First_pass_pointer

	# Check for &
	cmp r0, #0x26
	beq First_pass_pointer

	# Deal with everything else
	push {r14}
	bl hex                      @ Process our char
	pop {r14}

	# Deal with EOF
	cmp r0, #-4
	beq First_pass_done

	# deal with -1 values
	cmp r0, #0
	blt First_pass

	# deal with toggle
	ldr r8, Flag_address
	ldr r0, [r8]
	cmp r0, #0
	beq First_pass_1
	add r12, #1                 @ Increment IP

First_pass_1:
	mvn r0, r0
	ldr r8, Flag_address
	str r0, [r8]    @ Set Flag
	b First_pass

Update_Pointer:
	# Check for !
	cmp r0, #0x21
	beq Update_Pointer_1

	# Check for @
	cmp r0, #0x40
	beq Update_Pointer_2

	# Check for $
	cmp r0, #0x24
	beq Update_Pointer_2

	# Check for %
	cmp r0, #0x25
	beq Update_Pointer_4

	# Check for &
	cmp r0, #0x26
	beq Update_Pointer_4

	## deal with bad input
	b fail

Update_Pointer_4:
	add r12, #2                 @ Increment IP
Update_Pointer_2:
	add r12, #1                 @ Increment IP
Update_Pointer_1:
	add r12, #1                 @ Increment IP
	bx r14

First_pass_pointer:
	# Deal with Pointer to label
	push {r14}
	bl Update_Pointer           @ Increment IP
	ldr r1, table_address       @ Using scratch
	bl consume_token            @ Read token
	bl ClearScratch             @ Throw away token
	pop {r14}
	cmp r0, #0x3E               @ check for '>'
	bne First_pass              @ Loop again

	## Deal with %label>label case
	ldr r1, table_address       @ Write to scratch
	push {r14}
	bl consume_token            @ get token
	bl ClearScratch             @ Clean up after ourselves
	pop {r14}
	b First_pass                @ Loop again

First_pass_done:
	bx r14

hex:
	# deal with EOF
	cmp r0, #-4
	beq EOF
	# deal with line comments starting with #
	cmp r0, #0x23
	beq ascii_comment
	# deal with line comments starting with ;
	cmp r0, #0x3b
	beq ascii_comment
	# deal all ascii less than 0
	cmp r0, #0x30
	blt ascii_other
	# deal with 0-9
	cmp r0, #0x3a
	blt ascii_num
	# deal with all ascii less than A
	cmp r0, #0x41
	blt ascii_other
	# deal with A-F
	cmp r0, #0x47
	blt ascii_high
	#deal with all ascii less than a
	cmp r0, #0x61
	blt ascii_other
	#deal with a-f
	cmp r0, #0x67
	blt ascii_low
	# The rest that remains needs to be ignored
	b ascii_other

Second_pass:
	push {r14}
	bl Read_byte
	pop {r14}

	# Deal with EOF
	cmp r0, #-4
	beq Second_pass_done

	# Simply drop the label
	cmp r0, #0x3a
	bne Second_pass_0

	ldr r1, table_address       @ Using scratch
	push {r14}
	bl consume_token            @ Read token
	bl ClearScratch             @ Throw away token
	pop {r14}

	b Second_pass

Second_pass_0:
	# Deal with % pointer
	cmp r0, #0x25
	beq StorePointer_rel4

	# Deal with @ pointer
	cmp r0, #0x40
	beq StorePointer_rel2

	# Deal with ! pointer
	cmp r0, #0x21
	beq StorePointer_rel1

	# Deal with & pointer
	cmp r0, #0x26
	beq StorePointer_abs4

	# Deal with $ pointer
	cmp r0, #0x24
	beq StorePointer_abs2

Second_pass_1:
	# Deal with everything else
	push {r14}
	bl hex                      @ Process our char
	pop {r14}

	# Deal with EOF
	cmp r0, #-4
	beq Second_pass_done

	# deal with -1 values
	cmp r0, #0
	blt Second_pass

	# deal with toggle
	ldr r8, Flag_address
	ldr r1, [r8]
	cmp r1, #0
	beq print

	# process first byte of pair
	lsl r0, #4
	ldr r8, High_address
	str r0, [r8]
	mov r0, #0
	ldr r8, Flag_address
	str r0, [r8]
	b Second_pass

Second_pass_done:
	bx r14

EOF:
	bx r14
ascii_num:
	sub r0, #0x30
	bx r14
ascii_low:
	sub r0, #0x57
	bx r14
ascii_high:
	sub r0, #0x37
	bx r14
ascii_other:
	mov r0, #-1
	bx r14
ascii_comment:
	push {r14}
	bl Read_byte
	pop {r14}
	cmp r0, #0xd
	beq ascii_comment_cr
	cmp r0, #0xa
	bne ascii_comment
ascii_comment_cr:
	mov r0, #-1
	bx r14

# process second byte of pair
print:
	# update the sum and store in output
	ldr r8, High_address
	ldr r8, [r8]
	add r0, r8
	ldr r8, table_address
	strb r0, [r8]

	# flip the toggle
	ldr r8, Flag_address
	ldr r0, [r8]
	mvn r0, r0
	str r0, [r8]

	# Print our first Hex
	mov r2,  #1                 @ set the size of chars we want
	push {r14}
	bl print_chars
	pop {r14}

	add r12, #1                 @ Increment IP
	b Second_pass

Done:
	# program completed Successfully
	mov r0, #0                  @ All is well
	mov r7, #1                  @ put the exit syscall number in r0
	svc #0                      @ Call it a good day


## Malloc isn't actually required if the program being built fits in the initial memory
## However, it doesn't take much to add it.
## Requires a value in R1
malloc:
	mov r7, #45                 @ the Syscall # for SYS_BRK
	push {r10}                  @ Protect r10
	push {r12}                  @ Protect r12
	svc #0                      @ call the Kernel
	pop {r12}                   @ Restore r12
	pop {r10}                   @ Restore r10
	bx r14


Read_byte:
	# Attempt to read 1 byte from STDIN
	push {r10}                  @ Protect r10
	push {r12}                  @ Protect r12
	push {r1}                   @ Protect r1
	push {r2}                   @ Protect r2

	mov r2, #1                  @ set the size of chars we want
	ldr r1, write_address       @ Where to put it
	ldr r8, Input_address
	ldr r0, [r8]                @ Where are we reading from
	mov r7, #3                  @ the syscall number for read
	svc #0                      @ call the Kernel
	pop {r2}                    @ Restore r2
	pop {r1}                    @ Restore r1
	pop {r12}                   @ Restore r12
	pop {r10}                   @ Restore r10

	cmp r0, #0                  @ check what we got
	beq Read_byte_1             @ Got EOF call it done

	# load byte
	ldr r8, write_address
	ldrb r0, [r8]               @ load char
	bx r14

# Deal with EOF
Read_byte_1:
	mov r0, #-4                 @ Put EOF in r0
	bx r14

print_chars:
	push {r10}                  @ Protect r10
	push {r12}                  @ Protect r12
	push {r0}                   @ Protect r0
	push {r1}                   @ Protect r1

	ldr r1, table_address       @ What we are writing
	ldr r8, Output_address
	ldr r0, [r8]                @ Write to target file
	mov r7, #4                  @ the syscall number for write
	svc #0                      @ call the Kernel

	pop {r1}                    @ Restore r1
	pop {r0}                    @ Restore r0
	pop {r12}                   @ Restore r12
	pop {r10}                   @ Restore r10
	bx r14

## Receives pointer in R1
## Writes out char and updates R1
consume_token:
	push {r14}
	bl Read_byte                @ Consume_token
	pop {r14}

	# Check for \t
	cmp r0, #0x09
	beq consume_token_done

	# Check for \n
	cmp r0, #0x0A
	beq consume_token_done

	# Check for ' '
	cmp r0, #0x20
	beq consume_token_done

	# Check for '>'
	cmp r0, #0x3E
	beq consume_token_done

	## Looks like we are still reading token
	strb r0, [r1]               @ Store char
	add r1, #1                  @ Point to next spot
	b consume_token             @ loop until done

consume_token_done:
	mov r2, #0                  @ Padd with nulls
	str r2, [r1]
	add r1, #4
	bx r14

StoreLabel:
	mov r0, r11                 @ ENTRY
	add r11, #24                @ CALLOC
	str r12, [r0, #8]           @ ENTRY->TARGET = IP
	str r10, [r0]               @ ENTRY->NEXT = JUMP_TABLE
	mov r10, r0                 @ JUMP_TABLE = ENTRY
	str r11, [r10, #16]         @ ENTRY->NAME = TOKEN
	mov r1, r11                 @ Write Starting after struct
	push {r14}
	bl consume_token            @ Collect whole string
	pop {r14}
	mov r11, r1                 @ Update HEAP
	b First_pass

GetTarget:
	push {r1}                   @ protect r1
	push {r2}                   @ protect r2
	push {r3}                   @ protect r3
	push {r10}                  @ protect JUMP_TABLE
	ldr r2, table_address       @ Reset scratch
	ldr r3, [r10, #16]          @ I->NAME
GetTarget_loop:
	ldrb r0, [r2]               @ I->NAME[0]
	ldrb r1, [r3]               @ scratch[0]
	cmp r0, r1                  @ IF TOKEN == I->NAME
	bne GetTarget_miss          @ Oops

	add r2, #1
	add r3, #1
	cmp r0, #0
	bne GetTarget_loop          @ Loop until
	b GetTarget_done            @ Match

	## Miss
GetTarget_miss:
	ldr r10, [r10]              @ I = I->NEXT
	cmp r10, #0                 @ IF NULL == I
	beq fail                    @ Abort hard

	ldr r3, [r10, #16]          @ I->NAME
	ldr r2, table_address       @ Reset scratch
	b GetTarget_loop

GetTarget_done:
	ldr r0, [r10, #8]           @ Get address
	pop {r10}                   @ Restore JUMP_TABLE
	pop {r3}                    @ Restore R3
	pop {r2}                    @ Restore R2
	pop {r1}                    @ Restore R1
	bx r14

ClearScratch:
	push {r0}                   @ Protect against changes
	push {r1}                   @ And overwrites
	push {r2}                   @ While we work
	ldr r1, table_address       @ Where our table is
	mov r0, #0                  @ Using null

ClearScratch_loop:
	ldrb r2, [r1]               @ Get current value
	strb r0, [r1]               @ Because we want null
	add r1, #1                  @ Increment
	cmp r2, #0                  @ Check if we hit null
	bne ClearScratch_loop       @ Keep looping

	pop {r2}                    @ Restore
	pop {r1}                    @ Damage
	pop {r0}                    @ Entirely
	bx r14

StorePointer:
	push {r14}
	bl Update_Pointer           @ Increment IP
	ldr r1, table_address       @ Write to scratch
	bl consume_token            @ get token
	pop {r14}
	push {r0}                   @ Protect base_sep_p
	ldr r0, table_address       @ Pointer to scratch
	push {r14}
	bl GetTarget                @ Get address of pointer
	bl ClearScratch             @ Clean up after ourselves
	pop {r14}
	mov r3, r12                 @ base = IP
	pop {r1}                    @ Restore base_sep_p
	cmp r1, #0x3E               @ If base_sep_p == '>'
	bne StorePointer_done       @ If not

	## Deal with %label>label case
	push {r0}                   @ We need to preserve main target
	ldr r1, table_address       @ Write to scratch
	push {r14}
	bl consume_token            @ get token
	ldr r0, table_address       @ Pointer to scratch
	bl GetTarget                @ Get address of pointer
	bl ClearScratch             @ Clean up after ourselves
	pop {r14}
	mov r3, r0                  @ Use our new base
	pop {r0}                    @ Restore main target

StorePointer_done:
	bx r14

StorePointer_rel4:
	push {r14}
	bl StorePointer             @ Do Common
	sub r0, r3                  @ target - ip
	ldr r8, table_address
	str r0, [r8]                @ put value in output
	mov r2, #4                  @ set the size of chars we want
	bl print_chars
	bl ClearScratch             @ Clean up after ourselves
	pop {r14}
	b Second_pass

StorePointer_rel2:
	push {r14}
	bl StorePointer             @ Do Common
	sub r0, r3                  @ target - ip
	ldr r8, table_address
	str r0, [r8]                @ put value in output
	mov r2, #2                  @ set the size of chars we want
	bl print_chars
	bl ClearScratch             @ Clean up after ourselves
	pop {r14}
	b Second_pass

StorePointer_rel1:
	push {r14}
	bl StorePointer             @ Do Common
	sub r0, r3                  @ target - ip
	ldr r8, table_address
	str r0, [r8]                @ put value in output
	mov r2, #1                  @ set the size of chars we want
	bl print_chars
	bl ClearScratch             @ Clean up after ourselves
	pop {r14}
	b Second_pass

StorePointer_abs4:
	push {r14}
	bl StorePointer             @ Do Common
	ldr r8, table_address
	str r0, [r8]                @ put value in output
	mov r2, #4                  @ set the size of chars we want
	bl print_chars
	bl ClearScratch             @ Clean up after ourselves
	pop {r14}
	b Second_pass

StorePointer_abs2:
	push {r14}
	bl StorePointer             @ Do Common
	ldr r8, table_address
	str r0, [r8]                @ put value in output
	mov r2, #2                  @ set the size of chars we want
	bl print_chars
	bl ClearScratch             @ Clean up after ourselves
	pop {r14}
	b Second_pass

fail:
	# Some shit went wrong
	mov r0, #1                  @ All is wrong
	mov r7, #1                  @ put the exit syscall number in r0
	svc #0                      @ Call it a good day

## Because ARM doesn't support loading/storing directly to different segments in a single instruction
.balign 4
High_address: .word High
Flag_address: .word Flag
Input_address: .word Input
Output_address: .word Output
write_address: .word write
table_address: .word table

## Because ARM does't support full size immediates
start_address: .word 0x8048000

.data
ELF_end:
High:
	.word 0
Flag:
	.word 0
Input:
	.word 0
Output:
	.word 0
write:
	.word 0
table:
	.word 66
