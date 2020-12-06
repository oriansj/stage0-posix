// Copyright (C) 2020 Jeremiah Orians
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

    .macro push r
    str \r, [sp,-16]!
    .endm
    .macro pop r
    ldr \r, [sp], 16
    .endm


// Where the ELF Header is going to hit
// Simply jump to _start
// Our main function
_start:
    ldr x1, [sp,16]             // Get the actual input name
    add x2, sp, 32              // Get envp (hopefullY)
    cmp x1, 0                   // Check for missing output
    b.ne _start_out             // Have real input
    add x2, sp, 24              // Nope, envp is here!
    adr x1, default_file        // Use "kaem.run"

_start_out:
    adr x9, envp
    str x2, [x9]                // Protect envp

    mov x0, -100                // AT_FDCWD, relative to current working directory
    mov x2, 0                   // prepare read_only
    mov x8, 56                  // the syscall number for open()
    svc 0                       // Now open that damn file

    cmp x0, 0                   // IF NULL We couldn't open the file
    b.le Exit_Failure           // Abort hard
    adr x9, script              // Set input pointer
    str x0, [x9]


    mov x8, 214                 // the Syscall # for SYS_BRK
    mov x0, 0                   // Get current brk
    svc 0                       // Let the kernel do the work
    adr x9, MALLOC              // Set our malloc pointer
    str x0, [x9]

    // Where the main work gets done
    // Using X1 for tokens and X2 for tokens[i]
main_loop:
    adr x9, max_args            // Using 256 char* of space
    ldr x0, [x9]
    bl malloc                   // get it
    mov x1, x0                  // set tokens

    mov x2, x1                  // I = 0
    mov x0, 0                   // Using 0
    adr x9, info                // status = 0
    str x0, [x9,24]
    adr x9, command_done        // command_done = 0
    str x0, [x9]

    // Using X0 for result and X1 for tokens[i]
collect_command:
    bl collect_token            // Get another token
    cmp x0, 0                   // if NULL == result
    b.eq collect_command_comment	// It is a comment, don't store

    str x0, [x2]                // tokens[i] = result
    add x2, x2, 8               // i = i + 1 (adjusted for char* size)

collect_command_comment:
    adr x9, command_done        // Using command_done
    ldr x0, [x9]
    cmp x0, 0                   // IF 0 == command_done
    b.eq collect_command        // keep looping

    // Deal with line comments
    cmp x2, x1                  // if 0 < i
    b.eq main_loop              // It was a comment

collect_command_run:
    bl print_command            // print the command
    ldr x0, [x1]                // program = tokens[0]
    cmp x0, 0                   // IF NULL == program
    b.eq Exit_Failure           // Some shit went down, abort

    push x1                     // Protect Tokens
    mov x0, 17                  // flags = SIGCHILD
    mov x1, 0                   // parent_tid
    mov x2, 0                   // tls
    mov x3, 0                   // child_tid
    mov x8, 220                 // FORKing (SYS_clone)
    svc 0                       // int f = clone()
    pop x1                      // Restore Tokens

    cmp x0, 0                   // Check fork
    b.lt Exit_Failure           // IF f == -1 abort hard
    b.ne collect_command_parent // IF f == 0 it is child

    // Deal with child case
    mov x8, 221                 // EXECVE
    adr x9,  envp               // third arg = envp
    ldr x2, [x9]
                                // second arg = tokens, already in x1
    ldr x0, [x1]                // program = tokens[0]
    svc 0                       // execve(program, tokens, envp);
    b Exit_Failure              // return error

collect_command_parent:
    mov x1, x0                  // id = f
    mov x0, 1                   // id_type = P_PID
    adr x2, info                // infop
    mov x3, 4                   //  options = WEXITED

    mov x8, 95                  // WAITID
    svc 0                       // waitid(P_PID, f, &info, 0);

    adr x9, info                // Using status
    ldr x0, [x9,24]
    cmp x0, 0                   // IF 0 == status
    b.eq main_loop              // Loop forever

    // Deal with very unhappy case
    adr x0, hard                // Using "Subprocess error\nABORTING HARD\n"
    bl File_Print               // Print it

// Exit_Failure function
// Receives nothing
// And aborts hard
// DOES NOT RETURN
Exit_Failure:
    mov x1, 1                   // All is wrong
    mov x8, 93                  // put the exit syscall number in x0
    svc 0                       // Call it a bad day


// print_command function
// Recieves tokens[j] in X1 and tokens[i] in X2
// Modifies X0
print_command:
    push x30
    push x1                     // Protect X1
    adr x0, prefix              // using " +> "
    bl File_Print               // print it
print_command_loop:
    ldr x0, [x1]                // using tokens[j]
    bl File_Print               // print it
    add x1, x1, 8               // j = j + 1
    mov x0, 32                  // using ' '
    bl fputc                    // print it
    cmp x1, x2                  // IF j < i
    b.ne print_command_loop     // otherwise keep looping

    mov x0, 10                  // using '\n'
    bl fputc                    // print it
    pop x1                      // Restore X1
    pop x30
    ret


// collect_token function
// Recieves nothing
// Overwrites X0
// Uses X0 as C, X1 as token and X2 as token[i]
collect_token:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    adr x9, max_string          // Using max_string
    ldr x0, [x9]
    bl malloc                   // allocate space
    mov x1, x0                  // token = malloc(max_string);
    mov x2, x0                  // i = 0; set token[i]

collect_token_loop:
    bl fgetc                    // c = fgetc(input);
    cmp x0, -4                  // if C == EOF
    b.eq Done                   // We are done

    cmp x0, 32                  // IF C == ' '
    b.eq collect_token_done     // Space terminates token

    cmp x0, 9                   // IF C == '\t'
    b.eq collect_token_done     // tab terminates token

    cmp x0, 10                  // IF C == '\n'
    b.ne collect_token_string   // otherwise check next

    // It is a newline
    mov x0, 1                   // Using 1
    adr x9, command_done        // Set command_done = TRUE
    str x0, [x9]
    b collect_token_done        // Be done

collect_token_string:
    cmp x0, 34                  // IF C == '"'
    b.ne collect_token_comment  // otherwise check next

    // It is a RAW STRING
    bl collect_string           // Get the rest of the string
    b collect_token_done        // Be done

collect_token_comment:
    cmp x0, 35                  // IF C == '#'
    b.ne collect_token_escape   // otherwise check next

    // It is a line comment
    bl collect_comment          // Read it all
    mov x0, 1                   // Using 1
    adr x9, command_done        // Set command_done = TRUE
    str x0, [x9]
    b collect_token_done        // Be done

collect_token_escape:
    cmp x0, 92                  // IF C == '\\'
    b.ne collect_token_other    // otherwise just store it

    // It is an escape char
    bl fgetc                    // Read the char to drop
    b collect_token_done        // Be done

collect_token_other:
    strb w0, [x2]               // token[i] = C
    add x2, x2, 1               // i = i + 1
    b collect_token_loop        // Keep going

collect_token_done:
    cmp x1, x2                  // IF i == 0
    b.ne collect_token_good     // otherwise return the token
    mov x1, 0                   // token = NULL

collect_token_good:
    mov x0, x1                  // Return token
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// collect_string function
// Recieves target[index] in X2
// Modifies X0
// Uses X0 as C
collect_string:
    push x30
collect_string_loop:
    bl fgetc                    // C = fgetc(input)
    cmp x0, -4                  // if C == EOF
    b.eq Exit_Failure           // Something went horriably wrong

    cmp x0, 34                  // IF C == '"'
    b.eq collect_string_done    // be done

    // deal with inside of string
    strb w0, [x2]               // target[index] = C
    add x2, x2, 1               // index = index + 1
    b collect_string_loop       // Keep going

collect_string_done:
    pop x30
    ret


// collect_comment function
// Recieves nothing
// Modifies X0
// uses X0 as Int C
// Just throws away everything it reads
collect_comment:
    push x30
collect_comment_loop:
    bl fgetc                    // C = fgetc(input)
    cmp x0, -4                  // IF C == EOF
    b.eq Exit_Failure           // abort hard

    cmp x0, 10                  // IF C == '\n'
    b.ne collect_comment_loop   // otherwise keep looping
    pop x30
    ret


// Malloc isn't actually required if the program being built fits in the initial memory
// However, it doesn't take much to add it.
// Requires [MALLOC] to be initialized and X0 to have the number of desired bytes
malloc:
    push x1                     // Protect X1
    adr x9, MALLOC
    ldr x1, [x9]                // Using the current pointer
    push x1                     // Save to return later
    add x0, x0, x1              // Request the number of desired bytes
    mov x8, 214                 // the Syscall # for SYS_BRK
    svc 0                       // call the Kernel
    str x0, [x9]                // Update pointer
    pop x0
    pop x1                      // Restore X1
    ret


// fgetc function
// Loads FILE* from [script]
// Returns -4 (EOF) or char in X0
fgetc:
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x0, -4                  // Put EOF in x0
    push x0                     // Assume bad (If nothing read, value will remain EOF)
    mov x1, sp                  // Get stack address
    adr x9, script              // Where are we reading from
    ldr x0, [x9]
    mov x8, 63                  // the syscall number for read
    mov x2, 1                   // set the size of chars we want

    svc 0                       // call the Kernel

    pop x0                      // Get either char or EOF
    cmp x0, -4                  // Check for EOF
    b.eq fgetc_done             // Return as is
    and x0, x0, 0xff            // Make it useful
fgetc_done:
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    ret


// File_Print function
// Receives CHAR* in X0
// calls fputc for every non-null char
File_Print:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x1, x0                  // Protect S
    cmp x0, 0                   // Protect against nulls
    b.eq File_Print_Done        // Simply don't try to print them
File_Print_Loop:
    ldrb w0, [x1]               // Read byte
    cmp x0, 0                   // Check for NULL
    b.eq File_Print_Done        // Stop at NULL

    bl fputc                    // write it
    add x1, x1, 1               // S = S + 1
    b File_Print_Loop           // Keep going

File_Print_Done:
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// fputc function
// receives CHAR in X0 and load FILE* from stdout
// writes char and returns
fputc:
    push x1                     // Protect X1
    push x2                     // Protect X2

    push x0                     // We are writing x0
    mov x1, sp                  // Get stack address
    mov x0, 1                   // Write to target file
    mov x8, 64                  // the syscall number for write
    mov x2, 1                   // set the size of chars we want
    svc 0                       // call the Kernel
    pop x0                      // Restore stack
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    ret


Done:
    // program completed Successfully
    mov x0, 0                   // All is well
    mov x8, 93                  // put the exit syscall number in x0
    svc 0                       // Call it a good day


.section .data
envp: .quad 0
script: .quad 0
tokens: .quad 0
command_done: .quad 0
max_args: .quad 2048            // 256 * sizeof(char*)
max_string: .quad 4096          // 4096 * sizeof(char)
MALLOC: .quad 0

info:
    .quad 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0

default_file: .asciz "kaem.run"
prefix: .asciz " +> "
hard: .asciz "Subprocess error\nABORTING HARD\n"
