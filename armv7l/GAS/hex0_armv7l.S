###  Copyright (C) 2020 Jeremiah Orians
###  This file is part of stage0.
###
###  stage0 is free software: you can redistribute it and/or modify
###  it under the terms of the GNU General Public License as published by
###  the Free Software Foundation, either version 3 of the License, or
###  (at your option) any later version.
###
###  stage0 is distributed in the hope that it will be useful,
###  but WITHOUT ANY WARRANTY; without even the implied warranty of
###  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
###  GNU General Public License for more details.
###
###  You should have received a copy of the GNU General Public License
###  along with stage0.  If not, see <http://www.gnu.org/licenses/>.

	.text
	.global _start

	##  Where the ELF Header is going to hit
	##  Simply jump to _start
	##  Our main function
_start:
	pop {r7}                    @ Get the number of arguments
	pop {r0}                    @ Get the program name
	pop {r0}                    @ Get the actual input name
	mov r1, #0                  @ prepare read_only
	mov r2, #0                  @ Extra sure
	mov r7, #5                  @ the syscall number for open()
	svc #0                      @ Now open that damn file
	ldr r8, fin_address         @ ARMv7l doesn't support offsets in different segments
	str r0, [r8]                @ Preserve the file pointer we were given

	pop {r0}                    @ Get the actual output name
	movw r1, #577               @ Prepare file as O_WRONLY|O_CREAT|O_TRUNC
	movw r2, #448               @ Prepare file as RWX for owner only (700 in octal)
	svc #0                      @ Now open that damn file
	ldr r8, fout_address        @ ARMvl doesn't support offsets in different segments
	str r0, [r8]                @ Preserve the file pointer we were given

	##  Our flag for byte processing
	mvn r12, #0                 @ Because ~0 == -1

	##  temp storage for the sum
	mov r5, #0

loop:
	##  Read a byte
	bl Read_byte

	##  process byte
	bl hex

	##  Deal with -1 values
	cmp r0, #0
	blt loop

	##  deal with toggle
	cmp r12, #0
	bge print

	##  process first byte of pair
	mov r5, r0
	mov r12, #0
	b loop

	##  process second byte of pair
print:
	##  update the sum and store in output
	lsl r5, #4
	add r0, r5, r0
	ldr r8, output_address
	strb r0, [r8]

	##  flip the toggle
	mov r12, #-1

	bl write_byte

	b loop

hex:
	##  Purge Comment Lines (#)
	cmp r0, #35
	beq purge_comment

	##  Purge Comment Lines (;)
	cmp r0, #59
	beq purge_comment

	##  deal all ascii less than 0
	cmp r0, #48
	blt ascii_other

	##  deal with 0-9
	cmp r0, #58
	blt ascii_num

	##  deal with all ascii less than A
	cmp r0, #65
	blt ascii_other

	##  deal with A-F
	cmp r0, #71
	blt ascii_high

	## deal with all ascii less than a
	cmp r0, #97
	blt ascii_other

	## deal with a-f
	cmp r0, #103
	blt ascii_low

	##  The rest that remains needs to be ignored
	b ascii_other

purge_comment:
	##  Read a byte
	push {r14}
	bl Read_byte
	pop {r14}

	##  Loop if not LF
	cmp r0, #10
	bne purge_comment

	##  Otherwise return -1
	mov r0, #-1
	bx r14

ascii_num:
	sub r0, #48
	bx r14

ascii_low:
	sub r0, #87
	bx r14

ascii_high:
	sub r0, #55
	bx r14

ascii_other:
	mov r0, #-1
	bx r14

Done:
	##  program completed Successfully
	mov r0, #0                  @ All is well
	mov r7, #1                  @ put the exit syscall number in r7
	svc #0                      @ Call it a good day

write_byte:
	##  Print our Hex
	mov r2, #1                  @ set the size of chars we want
	ldr r1, output_address      @ What we are writing
	ldr r0, fout_address        @ Where are we writing to
	ldr r0, [r0]
	mov r7, #4                  @ the syscall number for write
	svc #0                      @ call the Kernel
	bx r14

Read_byte:
	##  Attempt to read 1 byte from STDIN
	mov r2, #1                  @ set the size of chars we want
	ldr r1, input_address       @ Where to put it
	ldr r0, fin_address         @ Where are we reading from
	ldr r0, [r0]
	mov r7, #3                  @ the syscall number for read
	svc #0                      @ call the Kernel

	cmp r0, #0                  @ check what we got
	beq Done                    @ Got EOF call it done

	##  load byte
	ldr r0, input_address       @ load char
	ldrb r0, [r0]
	bx r14

## Because ARM doesn't support loading/storing directly to different segments in a single instruction
.balign 4
fin_address: .word fin
fout_address: .word fout
output_address: .word output
input_address: .word input

	.data
ELF_end:
.balign 4
fin:
	.word 0
fout:
	.word 0
output:
	.word 0
input:
	.word 0
