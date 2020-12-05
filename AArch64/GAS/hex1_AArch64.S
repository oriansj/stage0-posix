// Copyright (C) 2017 Jeremiah Orians
// Copyright (C) 2020 Sanne Wouda
// This file is part of stage0.
//
// stage0 is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// stage0 is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with stage0.  If not, see <http://www.gnu.org/licenses/>.

    .section .text
    .global _start

// Where the ELF Header is going to hit
// Simply jump to _start
// Our main function
    .p2align 3
_start:
    ldr x1, [sp,#16]             // Get the actual input name
    mov x0, #-100                // AT_FDCWD, relative to current working directory
    mov x2, #0                   // Prepare file as read only
    mov x8, #56                  // The syscall number for openat(), aarch64 has no open()
    svc #0                       // Open file!
    mov x9, x0                   // Preserve the file pointer we were given

    ldr x1, [sp,#24]             // Get the output name
    mov x0, #-100                // AT_FDCWD, relative to current working directory
    mov x2, #577                 // Prepare file as O_WRONLY|O_CREAT|O_TRUNC
    mov x3, #448                 // Prepare file as RWX for owner only (700 in octal)
    mov x8, #56                  // The syscall number for openat(), aarch64 has no open()
    svc #0                       // Open file!
    mov x10, x0                  // Preserve the file pointer we were given

    mov x15, #-1                // Our flag for byte processing
    mov x14, #0                 // temp storage for the sum
    mov x13, #0x600000          // Our starting IP
    bl First_pass               // Process it

    // rewind input file
    mov x0, x9                  // Using our input file
    mov x1, #0                  // Offset
    mov x2, #0                  // Whence SEEK_SET
    mov x8, #62                 // lseek
    svc #0

    mov x15, #-1                // Our flag for byte processing
    mov x14, #0                 // temp storage for the sum
    mov x13, #0x600000          // Our starting IP
    bl Second_pass              // Process it

    // program competed Successfully
    mov x0, #0                  // All is well
    mov x8, #93                 // put the exit syscall number in x8
    svc #0

First_pass:
    str x30, [sp,#-16]!          // push lr
First_pass_loop:
    bl Read_byte

    // Deal with EOF
    cmp x0, #-4
    b.eq First_pass_done

    // Check for :
    cmp x0, #0x3a
    b.ne First_pass_0

    // Deal with label
    bl StoreLabel

First_pass_0:
    // Check for $
    cmp x0, #36
    b.eq First_pass_abs16pointer

    // Check for ~
    cmp x0, #126
    b.eq First_pass_rel24pointer

    // Check for &
    cmp x0, #38
    b.eq First_pass_abs32pointer

    // Deal with everything else
    bl hex                      // Process our char

    // Deal with EOF
    cmp x0, #-4
    b.eq First_pass_done

    // deal with -1 values
    cmp x0, #0
    b.lt First_pass_loop

    // deal with toggle
    cmp x15, #0
    b.eq First_pass_1
    add x13, x13, #1            // Increment IP

First_pass_1:
    mvn x15, x15                // Flip toggle
    b First_pass_loop

First_pass_abs16pointer:
    // Deal with 16-bit Pointer to label
    bl Read_byte                // Drop the char
    add x13, x13, #2            // Increment IP
    b First_pass_loop           // Loop again

First_pass_rel24pointer:
    // Deal with 24-bit Pointer to label
    bl Read_byte                // Drop the char
    add x13, x13, #3            // Increment IP
    b First_pass_loop           // Loop again

First_pass_abs32pointer:
    // Deal with 32-bit Pointer to label
    bl Read_byte                // Drop the char
    add x13, x13, #4            // Increment IP
    b First_pass_loop           // Loop again

First_pass_done:
    ldr x30, [sp], #16          // pop lr
    ret

Second_pass:
    str x30, [sp,#-16]!         // push lr

Second_pass_loop:
    bl Read_byte

    // Deal with EOF
    cmp x0, #-4
    b.eq Second_pass_done

    // Simply drop the label
    cmp x0, #0x3a
    b.ne Second_pass_0
    bl Read_byte
    b Second_pass_loop

Second_pass_0:
    // Check for $
    cmp x0, #36
    b.eq Second_pass_abs16pointer

    // Check for ~, assume preceded with ^
    cmp x0, #126
    b.eq Second_pass_rel24pointer

    // Check for &
    cmp x0, #38
    b.eq Second_pass_abs32pointer

    // Deal with everything else
    bl hex                      // Process our char

    // Deal with EOF
    cmp x0, #-4
    b.eq Second_pass_done

    // deal with -1 values
    cmp x0, #0
    b.lt Second_pass_loop

    // deal with toggle
    cmp x15, #0
    b.eq print

    // process first byte of pair
    mov x14, x0
    mov x15, #0
    b Second_pass_loop

Second_pass_abs16pointer:
    bl StoreAbs16Pointer
    b Second_pass_loop

Second_pass_rel24pointer:
    bl StoreRel24Pointer
    b Second_pass_loop

Second_pass_abs32pointer:
    bl StoreAbs32Pointer
    b Second_pass_loop

// process second byte of pair
print:
    // update the sum and store in output
    add x0, x0, x14, lsl #4
    adr x1, table
    strb w0, [x1]

    // flip the toggle
    mov x15, #-1

    // print our first Hex
    mov x2, #1                  // set the size of chars we want
    bl print_chars

    add x13, x13, #1            // Increment IP
    b Second_pass_loop

Second_pass_done:
    ldr x30, [sp], #16          // pop lr
    ret

hex:
    // deal with EOF
    cmp x0, #-4
    b.eq EOF

    // Purge Comment Lines (#)
    cmp x0, #35
    b.eq purge_comment

    // Purge Comment Lines (;)
    cmp x0, #59
    b.eq purge_comment

    // deal all ascii less than 0
    cmp x0, #48
    b.lt ascii_other

    // deal with 0-9
    cmp x0, #58
    b.lt ascii_num

    // deal with all ascii less than A
    cmp x0, #65
    b.lt ascii_other

    // deal with A-F
    cmp x0, #71
    b.lt ascii_high

    // deal with all ascii less than a
    cmp x0, #97
    b.lt ascii_other

    // deal with a-f
    cmp x0, #103
    b.lt ascii_low

    // The rest that remains needs to be ignored
    b ascii_other

purge_comment:
    str x30, [sp,#-16]!         // push lr

loop0:
    // Read a byte
    bl Read_byte

    // Loop if not LF
    cmp x0, #10
    b.ne loop0

    // Otherwise return -1
    mov x0, #-1

    ldr x30, [sp], #16          // pop lr
    ret

ascii_num:
    sub x0, x0, #48
    ret

ascii_low:
    sub x0, x0, #87
    ret

ascii_high:
    sub x0, x0, #55
    ret

ascii_other:
    mov x0, #-1
    ret

EOF:
    ret

Read_byte:
    // Attempt to read 1 byte from input file
    mov x0, x9                  // Where are we reading from
    adr x1, table               // Where to put it
    mov x2, #1                  // set the size of chars we want
    mov x8, #63                 // the syscall number for read
    svc #0                      // call the Kernel

    cmp x0, #0
    b.eq Read_byte_1

    // load byte
    adr x0, table
    ldrb w0, [x0]               // load char, unsigned so zero-extended already
    ret

// Deal with EOF
Read_byte_1:
    mov x0, #-4                 // Put EOF in x0
    ret

print_chars:
    mov x0, x10                 // Write to target file
    adr x1, table               // What we are writing
    mov x8, #64                 // the syscall number for write
    svc #0                      // call the Kernel
    ret

Get_table_target:
    str x30, [sp,#-16]!         // push lr
    bl Read_byte                // Get single char label
    adr x1, table
    add x0, x1, x0, lsl #3      // Each label in table takes 8 bytes to store
    ldr x30, [sp], #16          // pop lr
    ret

StoreLabel:
    str x30, [sp,#-16]!         // push lr
    bl Get_table_target
    str x13, [x0]
    ldr x30, [sp], #16          // pop lr
    ret

StoreAbs16Pointer:
    str x30, [sp,#-16]!         // push lr
    bl Get_table_target         // Get address of pointer
    ldr x0, [x0]                // Get pointer
    adr x1, table
    str x0, [x1]                // put value in output
    add x13, x13, #2            // Increment IP
    mov x2, #2                  // set the size of chars we want
    bl print_chars
    ldr x30, [sp], #16          // pop lr
    ret

StoreRel24Pointer:
    str x30, [sp,#-16]!         // push lr
    bl Get_table_target         // Get address of pointer
    ldr x0, [x0]                // Get pointer
    sub x0, x0, x13             // target - ip
    asr x0, x0, #2              // rel24 pointer is 4-byte aligned
    adr x1, table
    str x0, [x1]                // put value in output
    add x13, x13, #3            // Increment IP
    mov x2, #3                  // set the size of chars we want
    bl print_chars
    ldr x30, [sp], #16          // pop lr
    ret

StoreAbs32Pointer:
    str x30, [sp,#-16]!         // push lr
    bl Get_table_target         // Get address of pointer
    ldr x0, [x0]                // Get pointer
    adr x1, table
    str x0, [x1]                // put value in output
    add x13, x13, #4            // Increment IP
    mov x2, #4                  // set the size of chars we want
    bl print_chars
    ldr x30, [sp], #16          // pop lr
    ret

    .section .data
ELF_end:
table:
    .byte 0
