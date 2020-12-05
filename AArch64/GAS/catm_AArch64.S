// Copyright (C) 2019 Jeremiah Orians
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
    // X15 => OUTPUT
    // X14 => Buffer
    // X13 => INPUT

// Where the ELF Header is going to hit
// Simply jump to _start
// Our main function
_start:
    ldr x1, [sp,16]!            // Get the actual output name
    mov x0, -100                // AT_FDCWD, relative to current working directory
    mov x2, 577                 // Prepare file as O_WRONLY|O_CREAT|O_TRUNC
    mov x3, 384                 // Prepare file as RW for owner only (600 in octal)
    mov x8, 56                  // The syscall number for openat(), aarch64 has no open()
    svc 0                       // Now open that file
    mov x15, x0                 // Preserve the file pointer we were given

    mov x8, 214                 // the Syscall # for SYS_BRK
    mov x0, 0                   // Get current brk
    svc 0                       // Let the kernel do the work
    mov x14, x0                 // Set our malloc pointer

    mov x8, 214                 // the Syscall # for SYS_BRK
    mov x0, x14                 // Using current pointer
    add x0, x0, 0x100000        // Allocate 1MB
    svc 0                       // Let the kernel do the work

    mov x4, sp
core:
    ldr x1, [x4,8]!             // Get the actual input name
    cmp x1, 0                   // Check for null string
    b.eq done                   // Hit null be done

    mov x0, -100                // AT_FDCWD, relative to current working directory
    mov x2, 0                   // prepare read_only
    mov x3, 0                   // prevent any interactions
    mov x8, 56                  // The syscall number for openat(), aarch64 has no open()
    svc 0                       // Open file!
    mov x13, x0                 // Protect INPUT
keep:
    mov x2, 0x100000            // set the size of chars we want
    mov x1, x14                 // Where to put it
    mov x0, x13                 // Where are we reading from
    mov x8, #63                 // the syscall number for read
    svc 0                       // call the Kernel

    mov x2, x0                  // Number of bytes to write
    mov x1, x14                 // What we are writing
    mov x0, x15                 // Write to target file
    mov x8, #64                 // the syscall number for write
    svc 0                       // call the Kernel

    cmp x0, 0x100000            // Check if buffer was fully used
    b.eq keep                   // Keep looping if was full
    b core                      // Otherwise move to next file

done:
    // program completed Successfully
    mov x0, 0                   // All is well
    mov x8, #93                 // put the exit syscall number in eax
    svc 0                       // Call it a good day
