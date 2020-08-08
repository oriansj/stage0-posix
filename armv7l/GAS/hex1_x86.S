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
	mov r2, #0                  @ extra sure
	mov r7, #5                  @ the syscall number for open()
	svc #0                      @ Now open that damn file
	ldr r8, fin_address
	str r0, [r8]                @ Preserve the file pointer we were given

	pop {r0}                    @ Get the actual output name
	movw r1, #577               @ Prepare file as O_WRONLY|O_CREAT|O_TRUNC
	movw r2, #448               @ Prepare file as RWX for owner only (700 in octal)
	mov r7, #5                  @ the syscall number for open()
	svc #0                      @ Now open that damn file
	ldr r8, fout_address
	str r0, [r8]                @ Preserve the file pointer we were given

	mov r9, #-1                 @ Our flag for byte processing
	mov r3, #0                  @ temp storage for the sum
	mov r4, #0                  @ Our starting IP
	bl First_pass               @ Process it

	##  rewind input file
	ldr r0, fin_address
	ldr r0, [r0]                @ Using our input file
	mov r1, #0                  @ Offset Zero
	mov r2, #0                  @ Whence Zero
	mov r7, #19                 @ lseek
	svc #0

	mov r9, #-1                 @ Our flag for byte processing
	mov r3, #0                  @ temp storage for the sum
	mov r4, #0                  @ Our starting IP
	bl Second_pass              @ Process it

	b Done

First_pass:
	push {r14}
	bl Read_byte
	pop {r14}

	##  Deal with EOF
	cmp r0, #-4
	beq First_pass_done

	##  Check for :
	cmp r0, #0x3a
	bne First_pass_0

	##  Deal with label
	push {r14}
	bl StoreLabel
	pop {r14}

First_pass_0:
	##  Check for :
	cmp r0, #0x25
	beq First_pass_pointer

	##  Deal with everything else
	push {r14}
	bl hex                      @ Process our char
	pop {r14}

	##  Deal with EOF
	cmp r0, #-4
	beq First_pass_done

	##  deal with -1 values
	cmp r0, #0
	blt First_pass

	##  deal with toggle
	cmp r9, #0
	beq First_pass_1
	add r4, #1                  @ Increment IP

First_pass_1:
	mvn r9, r9
	b First_pass

First_pass_pointer:
	##  Deal with Pointer to label
	push {r14}
	bl Read_byte                @ Drop the char
	pop {r14}
	add r4, #4                  @ Increment IP
	b First_pass                @ Loop again

First_pass_done:
	BX R14

hex:
	##  deal with EOF
	cmp r0, #-4
	beq EOF
	##  deal with line comments starting with ;
	cmp r0, #0x23
	beq ascii_comment
	##  deal with line comments starting with ;
	cmp r0, #0x3b
	beq ascii_comment
	##  deal all ascii less than 0
	cmp r0, #0x30
	blt ascii_other
	##  deal with 0-9
	cmp r0, #0x3a
	blt ascii_num
	##  deal with all ascii less than A
	cmp r0, #0x41
	blt ascii_other
	##  deal with A-F
	cmp r0, #0x47
	blt ascii_high
	## deal with all ascii less than a
	cmp r0, #0x61
	blt ascii_other
	## deal with a-f
	cmp r0, #0x67
	blt ascii_low
	##  The rest that remains needs to be ignored
	b ascii_other

Second_pass:
	push {r14}
	bl Read_byte
	pop {r14}

	##  Deal with EOF
	cmp r0, #-4
	beq Second_pass_done

	##  Simply drop the label
	cmp r0, #0x3a
	bne Second_pass_0

	push {r14}
	bl Read_byte
	pop {r14}
	b Second_pass

Second_pass_0:
	##  Deal with  pointer
	cmp r0, #0x25
	bne Second_pass_1

	push {r14}
	bl StorePointer
	pop {r14}
	b Second_pass

Second_pass_1:
	##  Deal with everything else
	push {r14}
	bl hex                      @ Process our char
	pop {r14}

	##  Deal with EOF
	cmp r0, #-4
	beq Second_pass_done

	##  deal with -1 values
	cmp r0, #0
	blt Second_pass

	##  deal with toggle
	cmp r9, #0
	beq print

	##  process first byte of pair
	mov r3, r0
	mov r9, #0
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

	##  process second byte of pair
print:
	##  update the sum and store in output
	lsl r3, #4
	add r0, r3
	ldr r8, table_address
	str r0, [r8]

	##  flip the toggle
	mvn r9, r9

	##  Print our first Hex
	mov r2,  #1                 @ set the size of chars we want
	push {r14}
	bl print_chars
	pop {r14}

	add r4, #1                  @ Increment IP
	b Second_pass

Done:
	##  program completed Successfully
	mov r0, #0                  @ All is well
	mov r7, #1                  @ put the exit syscall number in r7
	svc #0                      @ Call it a good day

Read_byte:
	push {r1, r2}
	##  Attempt to read 1 byte from STDIN
	mov r2,  #1                 @ set the size of chars we want
	ldr r1, table_address       @ Where to put it
	ldr r0, fin_address
	ldr r0, [r0]                @ Where are we reading from
	mov r7, #3                  @ the syscall number for read
	svc #0                      @ call the Kernel

	cmp r0, #0                  @ check what we got
	beq Read_byte_1             @ Got EOF call it done

	##  load byte
	ldr r0, table_address
	ldrb r0, [r0]               @ load char
	pop {r1, r2}
	bx r14

	##  Deal with EOF
Read_byte_1:
	mov r0, #-4                 @ Put EOF in r0
	pop {r1, r2}
	bx r14

print_chars:
	push {r1}
	ldr r1, table_address       @ What we are writing
	ldr r0, fout_address
	ldr r0, [r0]                @ Write to target file
	mov r7, #4                  @ the syscall number for write
	svc #0                      @ call the Kernel
	pop {r1}
	bx r14

Get_table_target:
	push {r14}
	bl Read_byte                @ Get single char label
	pop {r14}
	lsl r0, #2                  @ Each label in table takes 4 bytes to store
	ldr r8, table_address
	add r0, r8                  @ Calculate offset
	bx r14

StoreLabel:
	push {r14}
	bl Get_table_target
	pop {r14}
	str r4, [r0]                @ Write out pointer to table
	bx r14

StorePointer:
	add r4, #4                  @ Increment IP
	push {r14}
	bl Get_table_target         @ Get address of pointer
	pop {r14}
	ldr r0, [r0]                @ Get pointer
	sub r0, r4                  @ target - ip
	ldr r8, table_address
	str r0, [r8]                @ put value in output
	mov r2,  #4                 @ set the size of chars we want
	push {r14}
	bl print_chars
	pop {r14}
	bx r14

## Because ARM doesn't support loading/storing directly to different segments in a single instruction
.balign 4
fin_address: .word fin
fout_address: .word fout
table_address: .word table

	.data
ELF_end:
fin:
	.word 0
fout:
	.word 0
table:
	.word 0
