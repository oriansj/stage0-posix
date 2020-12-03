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

    // Our flag for byte processing
    mov x15, #-1

    //  temp storage for the sum
    mov x14, #0

loop:
    // Read a byte
    bl Read_byte

    // process byte
    bl hex

    // Deal with -1 values
    cmp x0, #0
    b.lt loop

    // deal with toggle
    cmp x15, #0
    b.ge print

    // process first byte of pair
    mov x14, x0
    mov x15, #0
    b loop

// process second byte of pair
print:
    // update the sum and store in output
    add x0, x0, x14, lsl #4
    adr x1, output
    strb w0, [x1]

    // flip the toggle
    mov x15, #-1

    bl write_byte

    b loop

hex:
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
    str lr, [sp,#-8]            // push lr

loop0:
    // Read a byte
    bl Read_byte

    // Loop if not LF
    cmp x0, #10
    b.ne loop0

    // Otherwise return -1
    mov x0, #-1

    ldr lr, [sp, #-8]           // pop lr
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

Done:
    // program completed Successfully
    mov x0, #0                  // All is well
    mov x8, #93                 // put the exit syscall number in x8
    svc #0

write_byte:
    // Print our Hex
    mov x0, x10                 // Where are we writing to
    adr x1, output              // What we are writing
    mov x2, #1                  // set the size of chars we want
    mov x8, #64                 // the syscall number for write
    svc #0                      // call the Kernel
    ret

Read_byte:
    // Attempt to read 1 byte from input file
    mov x0, x9                  // Where are we reading from
    adr x1, input               // Where to put it
    mov x2, #1                  // set the size of chars we want
    mov x8, #63                 // the syscall number for read
    svc #0                      // call the Kernel

    cbz x0, Done                // Got EOF call it done

    // load byte
    adr x0, input
    ldrb w0, [x0]               // load char, unsigned so zero-extended already
    ret

    .section .data
ELF_end:
// Where we are putting our output
output:
    // Reserve 8bytes of Zeros
    .quad 0

// Where we get our input
input:
    // Reserve 8bytes of Zeros
    .quad 0
