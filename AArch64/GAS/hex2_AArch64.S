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

    // Register usage:
    // X0, X1, X2, X3 => Temps
    // X15 => Flag
    // X14 => High bits
    // X13 => IP
    // X12 => MALLOC
    // X11 => HEAD

    // Struct format: (size 24)
    // NEXT => 0
    // TARGET => 8
    // NAME => 16

// Where the ELF Header is going to hit
// Simply jump to _start
// Our main function
_start:
    mov x0, #0                  // Get current pointer
    bl malloc                   // Get current HEAP
    mov x12, x0                 // Setup MALLOC
    add x0, x0, #12582912       // Create space for temp [12MB]
    bl malloc                   // Give ourselves 81920 bytes to work with

    ldr x1, [sp,#16]            // Get the actual input name
    mov x0, #-100               // AT_FDCWD, relative to current working directory
    mov x2, #0                  // Prepare file as read only
    mov x8, #56                 // The syscall number for openat(), aarch64 has no open()
    svc #0                      // Open file!
    mov x9, x0                  // Preserve the file pointer we were given

    ldr x1, [sp,#24]            // Get the output name
    mov x0, #-100               // AT_FDCWD, relative to current working directory
    mov x2, #577                // Prepare file as O_WRONLY|O_CREAT|O_TRUNC
    mov x3, #448                // Prepare file as RWX for owner only (700 in octal)
    mov x8, #56                 // The syscall number for openat(), aarch64 has no open()
    svc #0                      // Open file!
    cmp x0, #0                  // Check for missing output
    b.gt _start_out             // Have real output
    mov x0, #1                  // Use stdout

_start_out:
    mov x10, x0                 // Preserve the file pointer we were given

    bl ClearScratch             // Zero scratch
    mov x15, #-1                // Our flag for byte processing
    mov x14, #0                 // temp storage for the sum
    mov x13, #0x00600000        // Our starting IP
    mov x11, 0                  // HEAD = NULL
    bl First_pass               // Process it

    // rewind input file
    mov x0, x9                  // Using our input file
    mov x1, #0                  // Offset
    mov x2, #0                  // Whence SEEK_SET
    mov x8, #62                 // lseek
    svc #0

    mov x15, #-1                // Our flag for byte processing
    mov x14, #0                 // temp storage for the sum
    mov x13, #0x00600000        // Our starting IP
    bl Second_pass              // Process it

    // program completed Successfully
    mov x0, #0                  // All is well
    mov x8, #93                 // put the exit syscall number in x8
    svc #0


First_pass:
    str x30, [sp,#-16]!         // push lr
First_pass_loop:
    bl Read_byte

    // Deal with EOF
    cmp x0, #-4
    b.eq First_pass_done

    // Check for :
    cmp x0, #0x3a
    b.ne First_pass_0

    // Deal with label
    mov x0, x12                 // ENTRY
    add x12, x12, 24            // CALLOC
    str x12, [x0, 16]           // ENTRY->NAME = TOKEN
    str x13, [x0, 8]            // ENTRY->TARGET = IP
    str x11, [x0]               // ENTRY->NEXT = HEAD
    mov x11, x0                 // HEAD = ENTRY
    mov x1, x12                 // Write Starting after struct
    bl consume_token            // Collect whole string
    mov x12, x1                 // Update HEAP
    b First_pass_loop

First_pass_0:
    // Check for !
    cmp x0, #0x21
    b.eq First_pass_pointer

    // Check for @
    cmp x0, #0x40
    b.eq First_pass_pointer

    // Check for $
    cmp x0, #0x24
    b.eq First_pass_pointer

    // Check for %
    cmp x0, #0x25
    b.eq First_pass_pointer

    // Check for &
    cmp x0, #0x26
    b.eq First_pass_pointer

    // Check for ~
    cmp x0, #126
    b.eq First_pass_pointer

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
    mvn x15, x15
    b First_pass_loop

First_pass_pointer:
    // Deal with Pointer to label
    bl Update_Pointer           // Increment IP
    adr x1, scratch             // Using scratch
    bl consume_token            // Read token
    bl ClearScratch             // Throw away token
    cmp x0, #0x3E               // check for '>'
    b.ne First_pass_loop        // Loop again

    // Deal with %label>label case
    adr x1, scratch             // Write to scratch
    bl consume_token            // get token
    bl ClearScratch             // Clean up after ourselves
    b First_pass_loop           // Loop again

First_pass_done:
    ldr x30, [sp], #16          // pop lr
    ret

Update_Pointer:
    // Check for !
    cmp x0, #0x21
    b.eq Update_Pointer_1

    // Check for @
    cmp x0, #0x40
    b.eq Update_Pointer_2

    // Check for $
    cmp x0, #0x24
    b.eq Update_Pointer_2

    // Check for ~
    cmp x0, #126
    b.eq Update_Pointer_3

    // Check for %
    cmp x0, #0x25
    b.eq Update_Pointer_4

    // Check for &
    cmp x0, #0x26
    b.eq Update_Pointer_4

    // deal with bad input
    b fail

Update_Pointer_4:
    add x13, x13, 1             // Increment IP
Update_Pointer_3:
    add x13, x13, 1             // Increment IP
Update_Pointer_2:
    add x13, x13, 1             // Increment IP
Update_Pointer_1:
    add x13, x13, 1             // Increment IP
    ret


Second_pass:
    str x30, [sp,#-16]!         // push lr

    // x7 marks whether we need to do a word-aligned pointer
Second_pass_loop:
    mov x7, #0
Second_pass_align:
    bl Read_byte

    // Deal with EOF
    cmp x0, -4
    b.eq Second_pass_done

    // Deal with ^
    cmp x0, 94
    b.eq Second_pass_align_0

    // Simply drop the label
    cmp x0, 0x3a
    b.ne Second_pass_0

    adr x1, scratch             // Using scratch
    bl consume_token            // Read token
    bl ClearScratch             // Throw away token

    b Second_pass_loop

Second_pass_align_0:
    mvn x7, x7                  // toggle alignment
    b Second_pass_align

Second_pass_0:
    // Deal with % pointer
    cmp x0, 0x25
    b.eq StorePointer_rel4

    // Deal with ~ pointer
    cmp x0, 126
    b.eq StorePointer_rel3

    // Deal with @ pointer
    cmp x0, 0x40
    b.eq StorePointer_rel2

    // Deal with ! pointer
    cmp x0, 0x21
    b.eq StorePointer_rel1

    // Deal with & pointer
    cmp x0, 0x26
    b.eq StorePointer_abs4

    // Deal with $ pointer
    cmp x0, 0x24
    b.eq StorePointer_abs2

    // Deal with everything else
    bl hex                      // Process our char

    // Deal with EOF
    cmp x0, -4
    b.eq Second_pass_done

    // deal with -1 values
    cmp x0, 0
    b.lt Second_pass_loop

    // deal with toggle
    cmp x15, 0
    b.eq print

    // process first byte of pair
    mov x14, x0
    mov x15, 0
    b Second_pass_loop

// process second byte of pair
print:
    // update the sum and store in output
    add x0, x0, x14, lsl #4

    // Print our first Hex
    mov x2,  1                  // set the size of chars we want
    bl print_chars

    // flip the toggle
    mvn x15, x15

    add x13, x13, 1             // Increment IP
    b Second_pass_loop

StorePointer_rel4:
    bl StorePointer             // Do Common
    sub x0, x0, x2              // target - ip
    cbz x7, StorePointer_rel4_0
    asr x0, x0, #2
StorePointer_rel4_0:
    mov x2,  4                  // set the size of chars we want
    bl print_chars
    bl ClearScratch             // Clean up after ourselves
    b Second_pass_loop

StorePointer_rel3:
    bl StorePointer             // Do Common
    sub x0, x0, x2              // target - ip
    cbz x7, StorePointer_rel3_0
    asr x0, x0, #2
StorePointer_rel3_0:
    mov x2,  3                  // set the size of chars we want
    bl print_chars
    bl ClearScratch             // Clean up after ourselves
    b Second_pass_loop

StorePointer_rel2:
    bl StorePointer             // Do Common
    sub x0, x0, x2              // target - ip
    cbz x7, StorePointer_rel2_0
    asr x0, x0, #2
StorePointer_rel2_0:
    mov x2, 2                   // set the size of chars we want
    bl print_chars
    bl ClearScratch             // Clean up after ourselves
    b Second_pass_loop

StorePointer_rel1:
    bl StorePointer             // Do Common
    sub x0, x0, x2              // target - ip
    cbz x7, StorePointer_rel1_0
    asr x0, x0, #2
StorePointer_rel1_0:
    mov x2, 1                   // set the size of chars we want
    bl print_chars
    bl ClearScratch             // Clean up after ourselves
    b Second_pass_loop

StorePointer_abs4:
    bl StorePointer             // Do Common
    mov x2, 4                   // set the size of chars we want
    bl print_chars
    bl ClearScratch             // Clean up after ourselves
    b Second_pass_loop

StorePointer_abs2:
    bl StorePointer             // Do Common
    mov x2, 2                   // set the size of chars we want
    bl print_chars
    bl ClearScratch             // Clean up after ourselves
    b Second_pass_loop

Second_pass_done:
    ldr x30, [sp], #16          // pop lr
    ret

hex:
    // deal with EOF
    cmp x0, #-4
    b.eq EOF
    // deal with line comments starting with #
    cmp x0, #0x23
    b.eq ascii_comment
    // deal with line comments starting with ;
    cmp x0, #0x3b
    b.eq ascii_comment
    // deal all ascii less than 0
    cmp x0, #0x30
    b.lt ascii_other
    // deal with 0-9
    cmp x0, 0x3a
    b.lt ascii_num
    // deal with all ascii less than A
    cmp x0, 0x41
    b.lt ascii_other
    // deal with A-F
    cmp x0, 0x47
    b.lt ascii_high
    //deal with all ascii less than a
    cmp x0, 0x61
    b.lt ascii_other
    //deal with a-f
    cmp x0, 0x67
    b.lt ascii_low
    // The rest that remains needs to be ignored
ascii_other:
    mov x0, -1
    ret

EOF:
    ret
ascii_num:
    sub x0, x0, 0x30
    ret
ascii_low:
    sub x0, x0, 0x57
    ret
ascii_high:
    sub x0, x0, 0x37
    ret
ascii_comment:
    str x30, [sp,#-16]!          // push lr
ascii_comment_loop:
    bl Read_byte
    cmp x0, 0xd
    b.eq ascii_comment_cr
    cmp x0, 0xa
    b.ne ascii_comment_loop
ascii_comment_cr:
    mov x0, -1
    ldr x30, [sp], #16          // pop lr
    ret


// Malloc isn't actually required if the program being built fits in the initial memory
// However, it doesn't take much to add it.
// Requires a value in X0
malloc:
    mov x8, #214                // the Syscall # for SYS_BRK
    svc #0                      // call the Kernel
    ret


Read_byte:
    str x1, [sp, #-16]!
    mov x0, #-4
    str x0, [sp, #-16]!

    // Attempt to read 1 byte from STDIN
    mov x0, x9                  // Where are we reading from
    mov x2, #1                  // set the size of chars we want
    mov x8, #63                 // the syscall number for read
    mov x1, sp
    svc #0                      // call the Kernel

    ldrsb x0, [sp], #16
    ldr x1, [sp], #16
    ret


print_chars:
    str x0, [sp,#-16]!          // put value in output
    mov x1, sp                  // What we are writing
    mov x0, x10                 // Write to target file
    mov x8, #64                 // the syscall number for write
    svc #0                      // call the Kernel
    ldr x0, [sp], #16
    ret

    // Receives pointer in x1
    // Writes out char and updates x1
    // leaves with x1 8-byte aligned
consume_token:
    str x30, [sp,#-16]!         // push lr
consume_token_loop:
    bl Read_byte                // Consume_token

    cmp x0, -4
    b.eq consume_token_done

    // Check for \t
    cmp x0, 0x09
    b.eq consume_token_done

    // Check for \n
    cmp x0, 0x0A
    b.eq consume_token_done

    // Check for ' '
    cmp x0, 0x20
    b.eq consume_token_done

    // Check for '>'
    cmp x0, 0x3E
    b.eq consume_token_done

    // Looks like we are still reading token
    strb w0, [x1], #1           // store char and update pointer
    b consume_token_loop        // loop until done

consume_token_done:
    mov x3, 0
consume_token_pad:
    strb w3, [x1], #1           // write at least one zero-byte
    tst x1, #7                  // is x1 8-byte aligned?
    b.ne consume_token_pad

    ldr x30, [sp], #16          // pop lr
    ret

    // finds label matching pointer in scratch
    //  clobbers  x1, x3, x4, x5
    //  returns address in x0
GetTarget:
    mov x5, x11                 // Grab HEAD
GetTarget_loop:
    adr x4, scratch             // Reset scratch
    ldr x3, [x5, #16]           // I->NAME
GetTarget_loop_0:   
    ldrb w0, [x3], #1           // I->NAME[0]
    ldrb w1, [x4], #1           // scratch[0]
    cmp x0, x1                  // IF TOKEN == I->NAME
    b.ne GetTarget_miss         // Oops

    cmp x1, 0
    b.ne GetTarget_loop_0       // Loop until
    b GetTarget_done            // Match

    // Miss
GetTarget_miss:
    ldr x5, [x5]                // I = I->NEXT
    cmp x5, 0                   // IF NULL == I
    b.eq fail                   // Abort hard

    b GetTarget_loop

GetTarget_done:
    ldr x0, [x5,#8]             // Get address
    ret

    // clobbers x3, x4
ClearScratch:
    str x0, [sp,-8]
    adr x4, scratch             // Where our table is
    mov x0, 0                   // Using null

ClearScratch_loop:
    ldrb w3, [x4]               // Get current value
    strb w0, [x4, #1]!          // Because we want nuoll
    cmp x3, 0                   // Check if we hit null
    b.ne ClearScratch_loop      // Keep looping

    ldr x0, [sp,-8]
    ret


    // returns target in x0, base in x2
StorePointer:
    str x30, [sp, #-16]!
    mov x6, x13
    bl Update_Pointer           // Increment IP
    adr x1, scratch             // Write to scratch
    bl consume_token            // get token
    str x0, [sp,#-16]!          // Protect base_sep_p
    bl GetTarget                // Get address of pointer
    bl ClearScratch             // Clean up after ourselves
    mov x2, x6                  // base = IP
    ldr x1, [sp], #16           // Restore base_sep_p
    cmp x1, 0x3E                // If base_sep_p == '>'
    b.ne StorePointer_done      // If not

    // Deal with %label>label case
    str x0, [sp,#-16]!          // We need to preserve main target
    adr x1, scratch             // Write to scratch
    bl consume_token            // get token
    bl GetTarget                // Get address of pointer
    bl ClearScratch             // Clean up after ourselves
    mov x2, x0                  // Use our new base
    ldr x0, [sp], #16           // Restore main target

StorePointer_done:
    ldr x30, [sp], #16          // pop lr
    ret


fail:
    // Some shit went wrong
    mov x0, 1                   // All is wrong
    mov x8, #93                 // put the exit syscall number in eax
    svc #0                      // Call it a good day


    .section .data
ELF_end:
scratch:
    .byte 0
