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
    // X0, X5, X6 => Temps
    // X13 => MALLOC
    // X14 => Output_file
    // X15 => Input_file

    // Struct TYPE format: (size 56)
    // NEXT => 0
    // SIZE => 8
    // OFFSET => 16
    // INDIRECT => 24
    // MEMBERS => 32
    // TYPE => 40
    // NAME => 48

    // Struct TOKEN_LIST format: (size 40)
    // NEXT => 0
    // LOCALS/PREV => 8
    // S => 16
    // TYPE => 24
    // ARGS/DEPTH => 32

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
    ldr x1, [sp,#16]            // Get the actual input name
    mov x0, #-100               // AT_FDCWD, relative to current working directory
    mov x2, 0                   // prepare read_only
    mov x8, #56                 // The syscall number for openat(), aarch64 has no open()
    svc 0                       // Now open that damn file
    mov x15, x0                 // Preserve the file pointer we were given

    ldr x1, [sp,#24]            // Get the output name
    mov x0, #-100               // AT_FDCWD, relative to current working directory
    mov x2, #577                // Prepare file as O_WRONLY|O_CREAT|O_TRUNC
    mov x3, #384                // Prepare file as RW for owner only (600 in octal)
    mov x8, #56                 // The syscall number for openat(), aarch64 has no open()
    svc #0                      // Open file!
    cmp x0, 0                   // Check for missing output
    b.gt _start_out             // Have real input
    mov x0, 1                   // Use stdout

_start_out:
    mov x14, x0                 // Preserve the file pointer we were given

    mov x8, #214                // the Syscall # for SYS_BRK
    mov x0, 0                   // Get current brk
    svc 0                       // Let the kernel do the work
    mov x13, x0                 // Set our malloc pointer
    mov x0, 0                   // HEAD = NULL
    bl read_all_tokens          // Read all tokens
    bl Reverse_List             // Reverse order
//  bl debug_list               // Try to figure out what is wrong
    adr x9, global_token        // Set global_token
    str x0, [x9]
    bl program                  // Convert into program
    adr x0, header_string1      // Our header string
    bl File_Print               // Print it
    adr x9, output_list         // Our output_list
    ldr x0, [x9]
    bl recursive_output         // Print core program
//  adr x0, header_string2      // Our Enable debug
//  call File_Print             // Print it
    adr x0, header_string3      // Our second label
    bl File_Print               // Print it
    adr x9, globals_list        // Our globals
    ldr x0, [x9]
    bl recursive_output         // Get them
    adr x0, header_string4      // Our final header
    bl File_Print               // Print it
    adr x9, strings_list        // Our strings
    ldr x0, [x9]
    bl recursive_output         // Get them
    adr x0, header_string5      // Our final header
    bl File_Print               // Print it

Done:
    // program completed Successfully
    mov x0, 0                   // All is well
    mov x8, #93                 // put the exit syscall number in eax
    svc 0                       // Call it a good day

// read_all_tokens function
// Receives FILE* in X15 and Token_List* in X0
// Tokenizes all input and returns updated list in X0
// Returns TOKEN in X0
// Uses X0 for C
read_all_tokens:
    push x30
    adr x9, Token
    str x0, [x9]
    bl fgetc
read_all_tokens_loop:
    cmn x0, 4                   // Check for EOF
    b.eq read_all_tokens_done   // Stop if found
    bl get_token                // Read all tokens
    b read_all_tokens_loop      // Loop
read_all_tokens_done:
    adr x9, Token
    ldr x0, [x9]
    pop x30
    ret


// get_token function
// Receives INT in X0 and FILE* in X15
// Makes a list of TOKEN_LIST
// C and STRING_INDEX are stored in memory, X2 is used for S and X3 is used for current
// Returns C in X0
get_token:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3

    adr x9, C                   // Set C
    str x0, [x9]

    mov x0, 40                  // Malloc CURRENT
    bl malloc                   // Get Pointer
    mov x3, x0                  // Set CURRENT

    mov x0, 256                 // Malloc the string
    bl malloc                   // Get pointer to S
    mov x2, x0                  // Set S
    str x2, [x3,16]             // CURRENT->S = S
reset:
    adr x9, string_index        // S[0]
    str x2, [x9]
    adr x9, C                   // Using C
    ldr x0, [x9]

    bl clear_white_space        // Clear WhiteSpace
    adr x9, C                   // Set C
    str x0, [x9]

    cmn x0, 4                   // Check for EOF
    b.eq get_token_abort        // if EOF abort

    cmp x0, 35                  // Check for '#'
    b.ne get_token_alpha        // Nope

    // Deal with # line comments
    bl purge_macro              // Let it handle it
    adr x9, C                   // Set C
    str x0, [x9]
    b reset                     // Try again

get_token_alpha:
    adr x9, C                   // Send C
    ldr x0, [x9]
    adr x1, alphas              // Get alphanumerics
    bl In_Set                   // See if in set
    cmp x0, 1                   // IF TRUE
    b.ne get_token_symbol       // Otherwise

    // Store keywords
    adr x9, C                   // Send C
    ldr x0, [x9]
    bl preserve_keyword         // Store
    adr x9, C                   // Set C
    str x0, [x9]
    b get_token_done            // Be done with this token

get_token_symbol:
    adr x9, C                   // Send C
    ldr x0, [x9]
    adr x1, symbols             // Get symbols
    bl In_Set                   // See if in set
    cmp x0, 1                   // IF TRUE
    b.ne get_token_strings      // Otherwise

    // Store symbols
    adr x9, C                   // Send C
    ldr x0, [x9]
    bl preserve_symbol          // Store
    adr x9, C                   // Set C
    str x0, [x9]
    b get_token_done            // Be done with this token

get_token_strings:
    adr x9, C                   // Send C
    ldr x0, [x9]
    adr x1, strings             // Get strings
    bl In_Set                   // See if in set
    cmp x0, 1                   // IF TRUE
    b.ne get_token_comment      // Otherwise

    // Store String
    adr x9, C                   // Send C
    ldr x0, [x9]
    bl consume_word             // Store
    adr x9, C                   // Set C
    str x0, [x9]
    b get_token_done            // Be done with this token

get_token_comment:
    adr x9, C                   // Send C
    ldr x0, [x9]
    cmp x0, 47                  // IF '/' == C
    b.ne get_token_else         // Otherwise

    bl consume_byte             // Hope it just is '/'
    adr x9, C                   // Set C
    str x0, [x9]

    cmp x0, 42                  // IF '*' we have '/*'
    b.ne get_token_comment_line // Check for '//'

    // Deal with /* block comments */
    bl fgetc                    // get next C
    adr x9, C                   // Set C
    str x0, [x9]
get_token_comment_block_outer:
    adr x9, C                   // Using C
    ldr x0, [x9]
    cmp x0, 47                  // IF '/' != C
    b.eq get_token_comment_block_done   // be done

get_token_comment_block_inner:
    adr x9, C                   // Using C
    ldr x0, [x9]
    cmp x0, 42                  // IF '*' != C
    b.eq get_token_comment_block_iter   // jump over

    // Deal with inner loop
    bl fgetc                    // get next C
    adr x9, C                   // Set C
    str x0, [x9]
    b get_token_comment_block_inner     // keep going

get_token_comment_block_iter:
    bl fgetc                    // get next C
    adr x9, C                   // Set C
    str x0, [x9]
    b get_token_comment_block_outer

get_token_comment_block_done:
    bl fgetc                    // get next C
    adr x9, C                   // Set C
    str x0, [x9]
    b reset                     // throw away, try again

get_token_comment_line:
    cmp x0, 47                  // IF '/' we have //
    b.ne get_token_done         // keep if just '/'

    // Deal with // line comment
    bl fgetc                    // drop to match
    adr x9, C                   // Set C
    str x0, [x9]
    b reset                     // throw away, try again

get_token_else:
    adr x9, C                   // Send C
    ldr x0, [x9]
    bl consume_byte
    adr x9, C                   // Set C
    str x0, [x9]

get_token_done:
    adr x9, Token               // TOKEN
    ldr x0, [x9]
    str x0, [x3,8]              // CURRENT->PREV = TOKEN
    str x0, [x3]                // CURRENT->NEXT = TOKEN
    adr x9, Token               // TOKEN = CURRENT
    str x3, [x9]

get_token_abort:
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    adr x9, C                   // Return C
    ldr x0, [x9]
    pop x30
    ret


// Malloc isn't actually required if the program being built fits in the initial memory
// However, it doesn't take much to add it.
// Requires X13 to be initialized and X0 to have the number of desired bytes
malloc:
    push x13                    // save the old pointer
    add x0, x0, x13             // Request the number of desired bytes
    mov x8, #214                // the Syscall # for SYS_BRK
    svc 0

    mov x13, x0
    pop x0                      // return the old pointer
    ret


// clear_white_space function
// Receives INT C in X0 and FILE* in X15
// Returns first non-whitespace char in X0
clear_white_space:
    push x30
clear_white_space_loop:
    cmp x0, 32                  // Check for ' '
    b.eq clear_white_space_wipe // wipe it out

    cmp x0, 10                  // Check for '\n'
    b.eq clear_white_space_wipe // wipe it output

    cmp x0, 9                   // Check for '\t'
    b.ne clear_white_space_done // looks like non-whitespace

clear_white_space_wipe:
    bl fgetc                    // Read a new byte
    cmn x0, 4                   // Check for EOF
    b.eq clear_white_space_done // Short circuit
    b clear_white_space_loop    // iterate

clear_white_space_done:
    pop x30
    ret


// In_Set function
// Receives Char C in X0 and CHAR* in X1
// Returns 1 if true, zero if false in X0
In_Set:
    push x1                     // Protect X1
    push x2                     // Protect X2
In_Set_loop:
    ldrb w2, [x1]               // Read char

    cmp x0, x2                  // See if they match
    b.eq In_Set_True            // return true

    cmp x2, 0                   // Check for NULL
    b.eq In_Set_False           // return false

    add x1, x1, 1               // s = s + 1
    b In_Set_loop               // Keep looping

In_Set_True:
    mov x0, 1                   // Set True
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    ret

In_Set_False:
    mov x0, 0                   // Set FALSE
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    ret

// purge_macro function
// Receives CH in X0
// Reads chars until Line feed is read
// returns line feed
purge_macro:
    push x30
purge_macro_loop:
    bl fgetc                    // read next char
    cmp x0, 10                  // Check for '\n'
    b.ne purge_macro_loop       // Keep going
    pop x30
    ret


// preserve_keyword function
// Receives INT C in X0
// collects all chars in keyword
// Returns C in X0
// Uses X2 for INT C
preserve_keyword:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x2, x0                  // Setup C
    adr x1, alphas              // Concerning ourselves with "abc.."
preserve_keyword_loop:
    bl In_Set                   // Check if alphanumerics
    cmp x0, 1                   // IF TRUE
    b.ne preserve_keyword_label // Otherwise check for label

    mov x0, x2                  // Pass C
    bl consume_byte             // consume that byte
    mov x2, x0                  // Update C
    b preserve_keyword_loop     // keep looping

preserve_keyword_label:
    mov x0, x2                  // Fix return
    cmp x0, 58                  // Check for ':'
    b.ne preserve_keyword_done  // be done

                                // Fix our goto label
    bl fixup_label              // Fix the label
    mov x0, 32                  // Return Whitespace

preserve_keyword_done:
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// preserve_symbol function
// Receives INT C in X0
// collects all chars in symbol
// Returns C in X0
// Uses X2 for INT C
preserve_symbol:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x2, x0                  // Setup C
    adr x1, symbols             // Concerning ourselves with "<=>.."
preserve_symbol_loop:
    bl In_Set                   // Check if symbol
    cmp x0, 1                   // IF TRUE
    b.ne preserve_symbol_done   // Otherwise be done

    mov x0, x2                  // Pass C
    bl consume_byte             // consume that byte
    mov x2, x0                  // Update C
    b preserve_symbol_loop      // keep looping

preserve_symbol_done:
    mov x0, x2                  // Fix return
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// consume_word function
// receives INT C in X0
// returns INT C in X0
// Uses X0 for C, X1 for FREQ and X2 for ESCAPE
consume_word:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x1, x0                  // FREQ = C
    mov x2, 0                   // ESCAPE = FALSE
consume_word_loop:
    cmp x2, 0                   // IF !ESCAPE
    b.ne consume_word_escape    // Enable escape

    cmp x0, 92                  // if '\\'
    b.ne consume_word_iter      // keep state

    mov x2, 1                   // ESCAPE = TRUE
    b consume_word_iter         // keep going

consume_word_escape:
    mov x2, 0                   // ESCAPE = FALSE

consume_word_iter:
    bl consume_byte             // read next char

    cmp x2, 0                   // IF ESCAPE
    b.ne consume_word_loop      // keep looping

    cmp x0, x1                  // IF C != FREQ
    b.ne consume_word_loop      // keep going

    bl fgetc                    // return next char
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// consume_byte function
// Receives INT C in X0
// Inserts C into string S, updates String S
// Returns Next char in X0
consume_byte:
    push x30
    push x1                     // Protect X1
    adr x9, string_index        // S[0]
    ldr x1, [x9]
    strb w0, [x1]               // S[0] = C
    add x1, x1, 1               // S = S + 1
    adr x9, string_index        // Update S
    str x1, [x9]
    bl fgetc
    pop x1                      // Restore X1
    pop x30
    ret


// fixup_label function
// Receives S in X2
// prepends ':' to string and returns registers unchanged
// Uses X0 for HOLD, X1 for PREV and X2 for S[0]
fixup_label:
    push x0                     // Protect X0
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x0, 58                  // HOLD = ':'
    ldr x2, [x3,16]             // HOLD_STRING[0]
fixup_label_loop:
    mov x1, x0                  // PREV = HOLD
    ldrb w0, [x2]               // HOLD = HOLD_STRING[I]
    strb w1, [x2]               // HOLD_STRING[I] = PREV
    add x2, x2, 1               // I = I + 1
    cmp x0, 0                   // IF NULL == HOLD
    b.ne fixup_label_loop       // Keep looping

    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x0                      // Restore X0
    ret


// fgetc function
// Receives FILE* in X15
// Returns -4 (EOF) or char in X0
fgetc:
    push x1
    push x2
    mov x0, -4                  // Put EOF in x0
    push x0                     // Assume bad (If nothing read, value will remain EOF)
    mov x1, sp                  // Get stack addresss
    mov x0, x15                 // Where are we reading from
    mov x8, #63                 // the syscall number for read
    mov x2,  1                  // set the size of chars we want

    svc 0                       // call the Kernel

    pop x0                      // Get either char or EOF
    cmn x0, 4                   // Check for EOF
    b.eq fgetc_done             // Return as is
    and x0, x0, 0xff            // Make it useful
fgetc_done:
    pop x2
    pop x1
    ret


// Reverse_List function
// Receives List in X0
// Returns the list reversed in X0
Reverse_List:
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x1, x0                  // Set HEAD
    mov x0, 0                   // ROOT = NULL
Reverse_List_Loop:
    cmp x1, 0                   // WHILE HEAD != NULL
    b.eq Reverse_List_Done      // Stop otherwise

    ldr x2, [x1]                // NEXT = HEAD->NEXT
    str x0, [x1]                // HEAD->NEXT = ROOT
    mov x0, x1                  // ROOT = HEAD
    mov x1, x2                  // HEAD = NEXT
    b Reverse_List_Loop         // Keep Going

Reverse_List_Done:
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    ret


// recursive_output function
// Receives list in X0
// walks the list and prints the I->S for all nodes backwards
// Uses X1 for I
recursive_output:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    cmp x0, 0                   // Check for NULL
    b.eq recursive_output_done  // Skip the work
    mov x1, x0                  // I = Head

    ldr x0, [x1]                // Iterate to next Token
    bl recursive_output         // Recurse

    ldr x0, [x1,16]             // Using S
    bl File_Print               // Print it

recursive_output_done:
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
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
// receives CHAR in X0 and FILE* in X14
// writes char and returns
fputc:
    push x1
    push x2

    push x0                     // We are writing x0
    mov x1, sp                  // Get stack address
    mov x0, x14                 // Write to target file
    mov x8, #64                 // the syscall number for write
    mov x2, 1                   // set the size of chars we want

    svc 0                       // call the Kernel

    pop x0                      // Restore stack
    pop x2                      // Restore X2
    pop x1
    ret


// program function
// receives nothing, returns nothing
// Uses X0 for type_size
program:
    // The binary initialized the globals to null, so we can skip those steps
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2

new_type:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    cmp x0, 0                   // Check if NULL
    b.eq program_done           // Be done if null

    ldr x1, [x0,16]             // GLOBAL_TOKEN->S
    adr x0, constant            // "CONSTANT"
    bl match                    // IF GLOBAL_TOKEN->S == "CONSTANT"
    cmp x0, 0                   // If true
    b.ne program_else           // Looks like not a constant

    // Deal with minimal constant case
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x0, [x9]

    ldr x0, [x0,16]             // global_token->S
    mov x1, 0                   // NULL
    adr x9, global_constant_list // global_constant_list
    ldr x2, [x9]
    bl sym_declare              // Declare that constant
    adr x9, global_constant_list // global_constant_list = sym_declare(global_token->s, NULL, global_constant_list);
    str x0, [x9]

    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1]                // global_token->next
    str x1, [x0,32]             // global_constant_list->arguments = global_token->next

    ldr x1, [x1]                // global_token->next->next
    adr x9, global_token        // global_token = global_token->next->next;
    str x1, [x9]
    b new_type                  // go around again

program_else:
    bl type_name                // Figure out the type_size
    cmp x0, 0                   // IF NULL == type_size
    b.eq new_type               // it was a new type

    // Add to global symbol table
    mov x1, x0                  // put type_size in the right spot
    adr x9, global_token        // Using global token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    adr x9, global_symbol_list  // Using global_symbol_list
    ldr x2, [x9]
    bl sym_declare              // Declare symbol
    adr x9, global_symbol_list  // global_symbol_list = sym_declare(global_token->s, type_size, global_symbol_list);
    str x0, [x9]
    adr x9, global_token        // Using global token
    ldr x1, [x9]
    ldr x1, [x1]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x1, [x9]

    adr x9, global_token        // Using global token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, semicolon           // ";"
    bl match                    // if(match(";", global_token->s))
    cmp x0, 0                   // If true
    b.ne program_function       // looks like not a match

    // Deal with the global variable
    adr x9, globals_list        // Using globals_list
    ldr x1, [x9]
    adr x0, program_string_0    // ":GLOBAL_"
    bl emit                     // Emit it
    mov x1, x0                  // update globals_list

    adr x9, global_token        // Using global token
    ldr x0, [x9]
    ldr x0, [x0,8]              // global token->prev
    ldr x0, [x0,16]             // global token->prev->s
    bl emit                     // Emit it

    mov x1, x0                  // update globals_list
    adr x0, program_string_1    // "\nNULL\n"
    bl emit                     // Emit it
    adr x9, globals_list        // update globals_list
    str x0, [x9]

    adr x9, global_token        // Using global token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x0, [x9]
    b new_type                  // go around again

program_function:
    adr x9, global_token        // Using global token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, open_paren          // "("
    bl match                    // if(match(";", global_token->s))
    cmp x0, 0                   // If true
    b.ne program_error          // Otherwise deal with error case

    // Deal with function definition
    bl declare_function         // Lets get the parsing rolling
    b new_type                  // Keep looping through functions

program_error:
    // Deal with the case of something we don't support

program_done:
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// declare_function function
// Receives nothing and returns nothing
// Sets current function and adds it to the global function list
declare_function:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x0, 0                   // Using NULL
    adr x9, current_count       // current_count = 0
    str x0, [x9]

    adr x9, global_token        // Using global token
    ldr x0, [x9]
    ldr x0, [x0,8]              // global token->prev
    ldr x0, [x0,16]             // global token->prev->s
    mov x1, 0                   // NULL
    adr x9, global_function_list // global_function_list
    ldr x2, [x9]
    bl sym_declare              // sym_declare(global_token->prev->s, NULL, global_function_list);
    adr x9, function            // function = sym_declare(global_token->prev->s, NULL, global_function_list);
    str x0, [x9]
    adr x9, global_function_list // global_function_list = function
    str x0, [x9]

    bl collect_arguments        // collect all of the function arguments

    adr x9, global_token        // Using global token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global token->s
    adr x1, semicolon           // ";"
    bl match                    // IF global token->s == ";"
    cmp x0, 0                   // If true
    b.ne declare_function_full  // It was a prototype

    // Deal with prototypes
    adr x9, global_token        // Using global token
    ldr x0, [x9]
    ldr x0, [x0]                // global token->next
    adr x9, global_token        // global token = global token->next
    str x0, [x9]
    b declare_function_done     // Move on

declare_function_full:
    // Deal with full function definitions
    adr x0, declare_function_string_0 // "# Defining function "
    bl emit_out                 // emit it

    adr x9, function            // function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->s
    bl emit_out                 // emit it

    adr x0, declare_function_string_1 // "\n:FUNCTION_"
    bl emit_out                 // emit it

    adr x9, function            // function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->s
    bl emit_out                 // emit it

    adr x0, declare_function_string_3 // "\n"
    bl emit_out                 // emit it

    bl statement                // Recursively get the function pieces

    adr x9, output_list         // output
    ldr x0, [x9]
    ldr x0, [x0,16]             // output->s
    adr x1, declare_function_string_2 // "RETURN\n"
    bl match                    // IF output->s == "RETURN\n"
    cmp x0, 0                   // If true we can skip adding it
    b.eq declare_function_done  // otherwise we need to add it

    // Add the return to the end of a function lacking a return;
    adr x0, declare_function_string_2 // "RETURN\n"
    bl emit_out                 // emit it

declare_function_done:
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// collect_arguments function
// Receives nothing
// Returns Nothing
// Adds arguments to the function definition
// holds struct type* type_size in X2, then replace with struct token_list* a in X2 when type_size is used
collect_arguments:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x0, [x9]
collect_arguments_loop:
    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, close_paren         // ")"
    bl match                    // IF global_token->S == ")"
    cmp x0, 0                   // we reached the end
    b.eq collect_arguments_done // be done

    // deal with the case of there are arguments
    bl type_name                // Get the type
    mov x2, x0                  // put type_size safely out of the way

    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, close_paren         // ")"
    bl match                    // IF global_token->S == ")"
    cmp x0, 0                   // is a foo(int, char,void) case
    b.eq collect_arguments_common // deal with commas

    // Trying second else
    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, comma               // ","
    bl match                    // IF global_token->S == ","
    cmp x0, 0                   // then deal with the common
    b.eq collect_arguments_common // case of commas between arguments

    // deal with foo(int a, char b)
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    mov x1, x2                  // put type_size in the right place
    adr x9, function            // Using function
    ldr x2, [x9]
    ldr x2, [x2,32]             // function->args
    bl sym_declare              // sym_declare(global_token->s, type_size, function->arguments);
    mov x2, x0                  // put a in a safe place

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,32]             // function->args
    cmp x0, 0                   // IF function->args == NULL
    b.ne collect_arguments_another // otherwise it isn't the first

    // Deal with the case of first argument in the function
    mov x0, 8                   // 8
    str x0, [x2,32]             // a->depth = 8
    b collect_arguments_next    // get to next

collect_arguments_another:
    // deal with the case of non-first arguments
    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,32]             // function->args
    ldr x0, [x0,32]             // function->args->depth
    add x0, x0, 8               // function->args->depth + 8
    str x0, [x2,32]             // a->depth = function->args->depth + 8

collect_arguments_next:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x0, [x9]

    adr x9, function            // Using function
    ldr x0, [x9]
    str x2, [x0,32]             // function->args = a

collect_arguments_common:
    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, comma               // ","
    bl match                    // IF global_token->S == ","
    cmp x0, 0                   // then deal with the comma
    b.ne collect_arguments_loop // otherwise loop

    // keep foo(bar(), 1) expressions working
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x0, [x9]
    b collect_arguments_loop    // keep going

collect_arguments_done:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x0, [x9]
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// statement function
// Receives nothing
// Returns nothing
// Walks down global_token recursively to collect the contents of the function
statement:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2

    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, open_curly_brace    // "{"
    bl match                    // IF global_token->S == "{"
    b.ne statement_label        // otherwise try label

    // deal with { statement }
    bl recursive_statement      // Statements inside of statements for days
    b statement_done            // Be done

statement_label:
    ldrb w0, [x1]               // global_token->S[0]
    cmp x0, 58                  // IF global_token->S == ':'
    b.ne statement_local        // otherwise try locals

    // deal with labels
    mov x0, x1                  // put global_token->S in the right spot
    bl emit_out                 // emit it

    adr x0, statement_string_0  // Using "\t#C goto label\n"
    bl emit_out                 // emit it

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x0, [x9]
    b statement_done            // be done

statement_local:
    mov x0, x1                  // put global_token->S in the right place
    adr x1, prim_types          // pointer to primative types
    bl lookup_type              // See if found
    cmp x0, 0                   // IF NULL == lookup_type(global_token->S, prim_types)
    b.ne statement_local_success // Sweet a new local

    // Second chance
    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, struct              // "struct"
    bl match                    // IF global_token->S == "struct"
    cmp x0, 0                   // then we are a local
    b.ne statement_if           // otherwise try IF

statement_local_success:
    bl collect_local            // Grab those locals
    b statement_done            // be done

statement_if:
    adr x0, if_string           // Using "if"
    bl match                    // IF global_token->S == "if"
    cmp x0, 0                   // then we have an if statement
    b.ne statement_do           // otherwise try DO

    // Deal with IF statement
    bl process_if               // DO IT
    b statement_done            // be done

statement_do:
    adr x0, do_string           // Using "do
    bl match                    // IF global_token->S == "do"
    cmp x0, 0                   // then we have a do statement
    b.ne statement_while        // otherwise try WHILE

    // Deal with DO statement
    bl process_do               // DO IT
    b statement_done            // be done

statement_while:
    adr x0, while_string        // Using "while"
    bl match                    // IF global_token->S == "while"
    cmp x0, 0                   // then we have a while statement
    b.ne statement_for          // otherwise try FOR

    // Deal with WHILE statement
    bl process_while            // DO IT
    b statement_done            // be done

statement_for:
    adr x0, for_string          // Using "for"
    bl match                    // IF global_token->S == "for"
    cmp x0, 0                   // then we have a for statement
    b.ne statement_asm          // otherwise try ASM

    // Deal with FOR statement
    bl process_for              // DO IT
    b statement_done            // be done

statement_asm:
    adr x0, asm_string          // Using "asm"
    bl match                    // IF global_token->S == "asm"
    cmp x0, 0                   // then we have an asm statement
    b.ne statement_goto         // otherwise try GOTO

    // Deal with ASM statement
    bl process_asm              // Hit it
    b statement_done            // be done

statement_goto:
    adr x0, goto_string             // Using "goto"
    bl match                    // IF global_token->S == "goto"
    cmp x0, 0                   // then we have a goto statement
    b.ne statement_return       // Otherwise try RETURN

    // Deal with GOTO statement
    adr x0, statement_string_1a // Using "LOAD_W16_AHEAD\nSKIP_32_DATA\n&"
    bl emit_out                     // emit it

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x0, [x9]

    ldr x0, [x0,16]             // global_token->S
    bl emit_out                 // emit it

    adr x0, statement_string_1b // Using "\nBR_X16"
    bl emit_out

    adr x0, statement_string_2  // Using "\n"
    bl emit_out                 // emit it

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x0, [x9]

    adr x0, statement_string_4  // Using "ERROR in statement\nMissing ;\n"
    adr x1, semicolon           // Using ";"
    bl require_match            // Make sure it has the required
    b statement_done            // Be done

statement_return:
    adr x0, return_string       // Using "return"
    bl match                    // IF global_token->S == "return"
    cmp x0, 0                   // then we have a return statement
    b.ne statement_break        // Otherwise try BREAK

    // Deal with RETURN Statement
    bl return_result            // Return anything they want
    b statement_done            // be done

statement_break:
    adr x0, break_string        // Using "break"
    bl match                    // IF global_token->S == "break"
    cmp x0, 0                   // then we have a break statement
    b.ne statement_continue     // Otherwise try CONTINUE

    // Deal with BREAK statement
    bl process_break            // Lets do some damage
    b statement_done            // be done

statement_continue:
    adr x0, continue_string         // Using "continue"
    bl match                    // IF global_token->S == "continue"
    cmp x0, 0                   // then we have a continue statement
    b.ne statement_else         // Otherwise we are punting to an expression

    // Deal with CONTINUE statement
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x0, [x9]

    adr x0, statement_string_3  // Using "\n#continue statement\n"
    bl emit_out                     // emit it

    adr x0, statement_string_4  // Using "ERROR in statement\nMissing //\n"
    adr x1, semicolon           // Using ";"
    bl require_match            // Don't forget the ";"
    b statement_done            // Be done

statement_else:
    bl expression               // Collect expression
    adr x0, statement_string_4  // Using "ERROR in statement\nMissing //\n"
    adr x1, semicolon           // Using ";"
    bl require_match            // make sure we have it

statement_done:
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// recursive_statement function
// Receives nothing
// Returns nothing
// Walks the global_token list to build the contents of statements
// Uses struct token_list* frame in X2
recursive_statement:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x0, [x9]

    adr x9, function            // Using function
    ldr x2, [x9]
    ldr x2, [x2,8]              // frame = function->locals

recursive_statement_loop:
    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, close_curly_brace   // Using "}"
    bl match                    // IF global_token->S == "}"
    cmp x0, 0                   // Then we are done recursing
    b.eq recursive_statement_cleanup // and then we clean up

    // Deal with the recursive calls
    bl statement                // Deal with another statement
    b recursive_statement_loop  // loop some more

recursive_statement_cleanup:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x0, [x9]

    adr x0, recursive_statement_string_0 // Using "RETURN\n"
    adr x9, output_list         // Using output
    ldr x1, [x9]
    ldr x1, [x1,16]             // output->S
    bl match                    // IF output->S == "RETURN\n"
    cmp x0, 0                   // Then we can skip the clean up
    b.eq recursive_statement_done // and be done

    // Deal with cleanup
    adr x9, function            // Using function
    ldr x1, [x9]
    ldr x1, [x1,8]              // i = function->locals
    adr x0, recursive_statement_string_1 // Using "POP_X1\t# _recursive_statement_locals\n"

recursive_statement_locals:
    cmp x1, x2                  // IF frame != i
    b.eq recursive_statement_done // Otherwise be done

    // Lets emit
    bl emit_out                 // emit it
    ldr x1, [x1]                // i = i->next
    b recursive_statement_locals // keep going

recursive_statement_done:
    adr x9, function            // Using function
    ldr x0, [x9]
    str x2, [x0,8]              // function->locals = frame
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// return_result function
// Receives nothing
// Returns nothing
// Cleans up function and generates return
// Also handles returning expressions
return_result:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x0, [x9]

    ldr x0, [x0,16]             // global_token->S
    ldrb w0, [x0]               // global_token->S[0]
    cmp x0, 59                  // If global_token->S[0] == ';'
    b.eq return_result_cleanup  // Go straight to cleanup

    bl expression               // get the expression we are returning

return_result_cleanup:
    adr x0, return_result_string_0 // Using "ERROR in return_result\nMISSING //\n"
    adr x1, semicolon           // Using ";"
    bl require_match            // Make sure we have it

    adr x9, function            // Using function
    ldr x1, [x9]
    ldr x1, [x1,8]              // function->locals
    adr x0, return_result_string_1 // Using "POP_X1\t# _return_result_locals\n"
return_result_locals:
    cmp x1, 0                   // IF NULL == i
    b.eq return_result_done     // Be done

    bl emit_out                 // Emit out pop
    ldr x1, [x1]                // i = i->NEXT
    b return_result_locals      // Keep going

return_result_done:
    adr x0, return_result_string_2 // Using "RETURN\n"
    bl emit_out                 // Emit it
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// collect_local function
// Receives nothing
// Returns nothing
// Walks global_token list to create function locals
// Uses X2 for struct token_list* A
collect_local:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    bl type_name                // Get the local's type

    mov x1, x0                  // Put struct type* type_size in the right place
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    adr x9, function            // Using function
    ldr x2, [x9]
    ldr x2, [x2,8]              // function->locals
    bl sym_declare              // Declare it
    mov x2, x0                  // put it away safely

    // Try for main
    adr x0, main_string         // Using "main"
    adr x9, function            // Using function
    ldr x1, [x9]
    ldr x1, [x1,16]             // function->S
    bl match                    // IF match("main", function->s)
    cmp x0, 0                   // possible
    b.ne collect_local_fresh    // try to see if fresh function

    // Ok we are in main, now to see if main is fresh
    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,8]              // function->locals
    cmp x0, 0                   // IF NULL == function->locals
    b.ne collect_local_fresh    // try to see if fresh function

    // Sweet we are in a fresh main
    mov x0, 32                  // We start at 32
    str x0, [x2,32]             // a->DEPTH = 32
    b collect_local_common      // Go to the commons

collect_local_fresh:
    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,32]             // function->args
    cmp x0, 0                   // IF NULL == function->args
    b.ne collect_local_first    // Otherwise see if first

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,8]              // function->locals
    cmp x0, 0                   // IF NULL == function->locals
    b.ne collect_local_first    // Otherwise try first

    // Sweet we are in a fresh function
    mov x0, 8                   // We start at 8
    str x0, [x2,32]             // a->DEPTH = 8
    b collect_local_common      // Go to the commons

collect_local_first:
    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,8]              // function->locals
    cmp x0, 0                   // IF NULL == function->locals
    b.ne collect_local_else     // Looks like we are just another local

    // Ok we are the first local
    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,32]             // function->args
    ldr x0, [x0,32]             // function->args->depth
    add x0, x0, 8               // function->arguments->depth + 8
    str x0, [x2,32]             // a->DEPTH = function->arguments->depth + 8
    b collect_local_common      // Go to the commons

collect_local_else:
    // Always the last to know
    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,8]              // function->locals
    ldr x0, [x0,32]             // function->locals->depth
    add x0, x0, 8               // function->locals->depth + 8
    str x0, [x2,32]             // a->DEPTH = function->locals->depth + 8

collect_local_common:
    adr x9, function            // Using function
    ldr x0, [x9]

    str x2, [x0,8]              // function->locals = a
    ldr x2, [x2,16]             // a->S

    adr x0, collect_local_string_0 // Using "# Defining local "
    bl emit_out                 // emit it

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    bl emit_out                 // emit it

    adr x0, collect_local_string_1 // Using "\n"
    bl emit_out                 // emit it

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    ldr x1, [x0,16]             // global_token->S
    adr x0, equal               // Using "="
    bl match                    // IF match("=", global_token->s)
    cmp x0, 0                   // Deal with assignment
    b.ne collect_local_done     // Otherwise finish it

    // Deal with assignment
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    bl expression               // Recurse

collect_local_done:
    adr x0, collect_local_string_2 // Using "ERROR in collect_local\nMissing ;\n"
    adr x1, semicolon           // Using ";"
    bl require_match            // Make sure we have it

    adr x0, collect_local_string_3 // Using "PUSH_X0\t#"
    bl emit_out                 // emit it

    mov x0, x2                  // put A->S where it belongs
    bl emit_out                 // emit it

    adr x0, collect_local_string_1 // Using "\n"
    bl emit_out                 // emit it

    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// process_asm function
// Receives nothing
// Returns nothing
// Simply inlines the asm statements
// Uses X1 for global_token temp storage
process_asm:
    push x30
    push x1                     // Protect X1
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    adr x0, process_asm_string_0 // Using "ERROR in process_asm\nMISSING (\n"
    adr x1, open_paren          // Using "("
    bl require_match            // Make sure we have it

    adr x9, global_token        // Using global_token
    ldr x1, [x9]
process_asm_iter:
    ldr x0, [x1,16]             // global_token->S
    ldrb w0, [x0]               // global_token->S[0]
    cmp x0, 34                  // IF global_token->S[0] == '"'
    b.ne process_asm_done       // Otherwise be done

    ldr x0, [x1,16]             // global_token->S
    add x0, x0, 1               // global_token->S + 1
    bl emit_out                 // Emit it

    adr x0, process_asm_string_1 // Using "\n"
    bl emit_out                 // Emit it

    ldr x1, [x1]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x1, [x9]
    b process_asm_iter          // keep going

process_asm_done:
    adr x0, process_asm_string_2 // Using "ERROR in process_asm\nMISSING )\n"
    adr x1, close_paren         // Using ")"
    bl require_match            // Make sure we have it

    adr x0, process_asm_string_3 // Using "ERROR in process_asm\nMISSING //\n"
    adr x1, semicolon           // Using ";"
    bl require_match            // Make sure we have it

    pop x1                      // Restore X1
    pop x30
    ret

// process_if function
// Receives nothing
// Returns Nothing
// Increments current_count recurses into expression + statement
// Uses X2 for char* NUMBER_STRING
process_if:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    adr x9, current_count       // Using current count
    ldr x0, [x9]
    mov x1, x0                  // Preparing for update
    add x1, x1, 1               // current_count + 1
    adr x9, current_count       // current_count = current_count + 1
    str x1, [x9]
    bl numerate_number          // convert to string
    mov x2, x0                  // put NUMBER_STRING in place

    adr x0, process_if_string_0 // Using "# IF_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    mov x1, x2                  // Passing NUMBER_STRING
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    adr x0, process_if_string_1 // Using "ERROR in process_if\nMISSING (\n"
    adr x1, open_paren          // Using "("
    bl require_match            // Make sure we have it

    bl expression               // Recurse to get the IF(...) part

    adr x0, process_if_string_2a // Using "CBNZ_X0_PAST_BR\nLOAD_W16_AHEAD\nSKIP_32_DATA\n&ELSE_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    mov x1, x2                  // Passing NUMBER_STRING
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x0, process_if_string_2b // Using "\nBR_X16\n"
    bl emit_out                 // Emit it

    adr x0, process_if_string_3 // Using "ERROR in process_if\nMISSING )\n"
    adr x1, close_paren         // Using ")"
    bl require_match            // Make sure we have it

    bl statement                // Recursive to get the IF(){...} part

    adr x0, process_if_string_4 // Using "LOAD_W16_AHEAD\nSKIP_32_DATA\n&_END_IF_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    mov x1, x2                  // Passing NUMBER_STRING
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x0, process_if_string_5 // Using "\nBR_X16\n:ELSE_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, else_string         // Using "else"
    bl match                    // IF global_token->S == "else"
    cmp x0, 0                   // Then we need to collect the else too
    b.ne process_if_done        // Otherwise finish up

    // deal with else statement
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    bl statement                // Recurse to get the ELSE {...} part

process_if_done:
    adr x0, process_if_string_6 // Using ":_END_IF_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    mov x1, x2                  // Passing NUMBER_STRING
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// save_break_frame microfunction
// Overwrites X0 and X1
// Saves break frame on stack
// Returns to caller
save_break_frame:
    pop x1                      // Save return Address
    adr x9, break_frame         // Get break_frame
    ldr x0, [x9]
    push x0                     // Store as nested_locals
    adr x9, break_target_head   // Get break_target_head
    ldr x0, [x9]
    push x0                     // Store as nested_break_head
    adr x9, break_target_func   // Get break_target_func
    ldr x0, [x9]
    push x0                     // Store as nested_break_func
    adr x9, break_target_num    // Get break_target_num
    ldr x0, [x9]
    push x0                     // Store as nested_break_num
    push x1                     // Put return back in place
    ret                         // Return to caller


// restore_break_frame microfunction
// Overwrites X0 and X1
// Restores break frame from stack
// Returns to caller
restore_break_frame:
    pop x1                      // Save return Address
    pop x0                      // Get nested_break_num
    adr x9, break_target_num    // Restore break_target_num
    str x0, [x9]
    pop x0                      // Get nested_break_func
    adr x9, break_target_func   // Restore break_target_func
    str x0, [x9]
    pop x0                      // Get nested_break_head
    adr x9, break_target_head   // Restore break_target_head
    str x0, [x9]
    pop x0                      // Get nested_locals
    adr x9, break_frame         // Restore break_frame
    str x0, [x9]
    push x1                     // Put return back in place
    ret                         // Return to caller


// set_break_frame microfunction
// Receives char* head in X0 and char* num in X1
// Overwrites X0 and X1
// Returns to calling function
set_break_frame:
    adr x9, break_target_head   // update break_target_head
    str x0, [x9]
    adr x9, break_target_num    // update break_target_num
    str x1, [x9]
    adr x9, function            // Using function
    ldr x1, [x9]
    ldr x0, [x1,8]              // function->LOCALS
    adr x9, break_frame         // break_frame = function->LOCALS
    str x0, [x9]
    ldr x0, [x1,16]             // function->S
    adr x9, break_target_func   // break_target_func = function->S
    str x0, [x9]
    ret                         // Return to sender


// process_do function
// Receives Nothing
// Returns Nothing
// Increments current_count and leverages save/restore_break_frame pieces
// Uses X2 for char* NUMBER_STRING
process_do:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    bl save_break_frame         // Save the frame

    adr x9, current_count       // Using current count
    ldr x0, [x9]
    mov x1, x0                  // Preparing for update
    add x1, x1, 1               // current_count + 1
    adr x9, current_count       // current_count = current_count + 1
    str x1, [x9]
    bl numerate_number          // convert to string
    mov x2, x0                  // put NUMBER_STRING in place

    adr x0, process_do_string_0 // Using "DO_END_"
    mov x1, x2                  // Passing NUMBER_STRING
    bl set_break_frame          // Set the frame

    adr x0, process_do_string_1 // Using ":DO_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    mov x1, x2                  // Passing NUMBER_STRING
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    bl statement                // Do the DO {...} part

    adr x0, process_do_string_2 // Using "ERROR in process_do\nMISSING while\n"
    adr x1, while_string        // Using "while"
    bl require_match            // Make sure we have it

    adr x0, process_do_string_3 // Using "ERROR in process_do\nMISSING (\n"
    adr x1, open_paren          // Using "("
    bl require_match            // Make sure we have it

    bl expression               // Do the WHILE (...) part

    adr x0, process_do_string_4 // Using "ERROR in process_do\nMISSING )\n"
    adr x1, close_paren         // Using ")"
    bl require_match            // Make sure we have it

    adr x0, process_do_string_5 // Using "ERROR in process_do\nMISSING //\n"
    adr x1, semicolon           // Using ";"
    bl require_match            // Make sure we have it

    adr x0, process_do_string_6a // Using "CBZ_X0_PAST_BR\nLOAD_W16_AHEAD\nSKIP_32_DATA\n&DO_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    mov x1, x2                  // Passing NUMBER_STRING
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x0, process_do_string_6b // Using "\nBR_X16\n"
    bl emit_out                 // Emit it

    adr x0, process_do_string_7 // Using ":DO_END_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    bl restore_break_frame      // Restore the old break frame

    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// process_while function
// Receives nothing
// Returns nothing
// Increments current_count and leverages save/restore_break_frame pieces
// Uses X2 for char* NUMBER_STRING
process_while:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    bl save_break_frame         // Save break_frame

    adr x9, current_count       // Using current count
    ldr x0, [x9]
    mov x1, x0                  // Preparing for update
    add x1, x1, 1               // current_count + 1
    adr x9, current_count       // current_count = current_count + 1
    str x1, [x9]
    bl numerate_number          // convert to string
    mov x2, x0                  // put NUMBER_STRING in place

    adr x0, process_while_string_0 // Using "END_WHILE_"
    mov x1, x2                  // Passing NUMBER_STRING
    bl set_break_frame          // Set it and forget it

    adr x0, process_while_string_1 // Using ":WHILE_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    mov x1, x2                  // Passing NUMBER_STRING
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    adr x0, process_while_string_2 // Using "ERROR in process_while\nMISSING (\n"
    adr x1, open_paren          // Using "("
    bl require_match            // Make sure we have it

    bl expression               // Deal with the WHILE (...) part

    adr x0, process_while_string_3a // Using "CBNZ_X0_PAST_BR\nLOAD_W16_AHEAD\nSKIP_32_DATA\n&END_WHILE_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    mov x1, x2                  // Passing NUMBER_STRING
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x0, process_while_string_3b // Using "\nBR_X16\n"
    bl emit_out

    adr x0, process_while_string_4 // Using "# THEN_while_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x0, process_while_string_5 // Using "ERROR in process_while\nMISSING )\n"
    adr x1, close_paren         // Using ")"
    bl require_match            // Make sure we have it

    bl statement                // Deal with the {....} part

    adr x0, process_while_string_6a // Using "LOAD_W16_AHEAD\nSKIP_32_DATA\n&WHILE_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    mov x1, x2                  // Passing NUMBER_STRING
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x0, process_while_string_6b // Using "\nBR_X16\n"
    bl emit_out

    adr x0, process_while_string_7 // Using ":END_WHILE_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    bl restore_break_frame      // Restore the old break frame

    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// process_for function
// Receives Nothing
// Returns Nothing
// Increments current_count and leverages save/restore_break_frame pieces
// Uses X2 for char* NUMBER_STRING
process_for:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    bl save_break_frame         // Save the frame

    adr x9, current_count       // Using current count
    ldr x0, [x9]
    mov x1, x0                  // Preparing for update
    add x1, x1, 1               // current_count + 1
    adr x9, current_count       // current_count = current_count + 1
    str x1, [x9]
    bl numerate_number          // convert to string
    mov x2, x0                  // put NUMBER_STRING in place

    adr x0, process_for_string_0 // Using "FOR_END_"
    mov x1, x2                  // Passing NUMBER_STRING
    bl set_break_frame          // Set it and forget it

    adr x0, process_for_string_1 // Using "# FOR_initialization_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    mov x1, x2                  // Passing NUMBER_STRING
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    adr x0, process_for_string_2 // Using "ERROR in process_for\nMISSING (\n"
    adr x1, open_paren          // Using "("
    bl require_match            // Make Sure we have it

    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, semicolon           // Using ";"
    bl match                    // IF global_token->S == ";"
    cmp x0, 0                   // Then no initializer
    b.eq process_for_terminator // And skip getting the expression

    // Deal with FOR (...; case
    bl expression               // Get the FOR ( ... ; part

process_for_terminator:
    adr x0, process_for_string_3 // Using ":FOR_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    mov x1, x2                  // Passing NUMBER_STRING
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x0, process_for_string_4 // Using "ERROR in process_for\nMISSING ;1\n"
    adr x1, semicolon           // Using ";"
    bl require_match            // Make sure we have it

    bl expression               // Get the FOR ( ; ... ; Part

    adr x0, process_for_string_5a // Using "CBNZ_X0_PAST_BR\nLOAD_W16_AHEAD\nSKIP_32_DATA\n&FOR_END_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    mov x1, x2                  // Passing NUMBER_STRING
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x0, process_for_string_5b // Using "\nBR_X16\n"
    bl emit_out                 // Emit it

    adr x0, process_for_string_6a // Using "LOAD_W16_AHEAD\nSKIP_32_DATA\n&FOR_THEN_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x0, process_for_string_6b // Using "\nBR_X16\n"
    bl emit_out                 // Emit it

    adr x0, process_for_string_7 // Using ":FOR_ITER_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x0, process_for_string_8 // Using "ERROR in process_for\nMISSING ;2\n"
    adr x1, semicolon           // Using ";"
    bl require_match            // Make sure we have it

    bl expression               // Get the FOR (;;...) part

    adr x0, process_for_string_9a // Using "LOAD_W16_AHEAD\nSKIP_32_DATA\n&FOR_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    mov x1, x2                  // Passing NUMBER_STRING
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x0, process_for_string_9b // Using "\nBR_X16\n"
    bl emit_out

    adr x0, process_for_string_10 // Using ":FOR_THEN_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x0, process_for_string_11 // Using "ERROR in process_for\nMISSING )\n"
    adr x1, close_paren         // Using ")"
    bl require_match            // Make sure we have it

    bl statement                // Get FOR (;;) {...} part

    adr x0, process_for_string_12a // Using "LOAD_W16_AHEAD\nSKIP_32_DATA\n&FOR_ITER_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    mov x1, x2                  // Passing NUMBER_STRING
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    adr x0, process_for_string_12b // Using "\nBR_X16\n"
    bl emit_out

    adr x0, process_for_string_13 // Using ":FOR_END_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    bl uniqueID_out             // uniqueID_out(function->s, number_string)

    bl restore_break_frame      // Restore the old break frame

    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// process_break function
// Receives nothing
// Returns nothing
// Handles the break out of loops case
// Uses X1 for struct token_list* break_frame and X2 for struct token_list* I
process_break:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    adr x9, break_target_head   // Catch big error
    ldr x0, [x9]
    cmp x0, 0                   // IF(NULL == break_target_head)
    b.eq process_break_bad      // I'm sorry Mr White but you have stage-3 lung cancer

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x2, [x0,8]              // I = function->LOCALS
    adr x9, break_frame         // Put break_frame in the right spot
    ldr x1, [x9]
    adr x0, process_break_string_1 // Using "POP_X1\t# break_cleanup_locals\n"

process_break_iter:
    cmp x2, 0                   // IF (NULL == I)
    b.eq process_break_cleaned  // We are done

    cmp x2, x1                  // IF I != break_frame
    b.eq process_break_cleaned  // We are done

    bl emit_out                 // Emit it
    ldr x2, [x2]                // I = I->NEXT
    b process_break_iter        // Keep looping

process_break_cleaned:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    adr x0, process_break_string_2a // Using "LOAD_W16_AHEAD\nSKIP_32_DATA\n&"
    bl emit_out                 // Emit it

    adr x9, break_target_head   // Get what we are in
    ldr x0, [x9]
    bl emit_out                 // Emit it

    adr x9, break_target_func   // Get what function we are in
    ldr x0, [x9]
    bl emit_out                 // Emit it

    adr x0, underline           // Using "_"
    bl emit_out                 // Emit it

    adr x9, break_target_num    // Get dem digits
    ldr x0, [x9]
    bl emit_out                 // Emit it

    adr x0, process_break_string_2b // Using "\nBR_X16"
    bl emit_out

    adr x0, process_break_string_3 // Using "\n"
    bl emit_out                 // Emit it

    adr x0, process_break_string_4 // Using "ERROR in break statement\nMissing ;\n"
    adr x1, semicolon           // Using ";"
    bl require_match            // Make sure we have it

    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


process_break_bad:
    // Breaking badly
    mov x14, 2                  // write to standard error
//  bl line_error               // Write useful debug info
    mov x0, x2                  // put S in the right place
    bl File_Print               // print it

    adr x0, process_break_string_0 // Ending string
    bl File_Print               // print it
    b Exit_Failure              // Abort Hard

// expression function
// Receives Nothing
// Returns Nothing
// Walks global_token and updates output_list
// Uses X0 and X1 for match and X2 for char* store
expression:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    bl bitwise_expr             // Collect bitwise expressions

    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, equal               // "="
    bl match                    // IF global_token->S == "="
    cmp x0, 0                   // We have to deal with assignment
    b.ne expression_done        // Looks like nope

    // Deal with possible assignment
    adr x2, expression_string_1 // Assume "STR_BYTE_W0_[X1]\n" by default
    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,8]              // global_token->PREV
    ldr x1, [x1,16]             // global_token->PREV->S
    adr x0, close_bracket       // Using "]"
    bl match                    // IF global_token->S == "]"
    cmp x0, 0                   // Then we might have a char
    b.ne expression_int         // Otherwise INT

    adr x9, current_target      // Using current_target
    ldr x1, [x9]
    ldr x1, [x1,48]             // current_target->NAME
    adr x0, type_char_indirect_name // Using "char*"
    bl match                    // Intentional inefficiency because I feel like it
    cmp x0, 0                   // IF current_target->NAME == "char*"
    b.ne expression_int         // Do char anyway

    b expression_common         // Looks like we have to use "STR_BYTE_W0_[X1]\n"

expression_int:
    adr x2, expression_string_0 // Use "STR_X0_[X1]\n"

expression_common:
    adr x0, expression          // Passing expression
    bl common_recursion         // Recurse
    mov x0, x2                  // Using Store
    bl emit_out                 // Emit it
    mov x0, 0                   // Using NULL
    adr x9, current_target      // current_target = NULL
    str x0, [x9]

expression_done:
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// bitwise_expr function
// Receives nothing
// Returns nothing
// Walks global_token list and updates output list
// Just calls other functions
bitwise_expr:
    push x30
    bl relational_expr          // Walk up the tree
    bl bitwise_expr_stub        // Let general recursion do the work
    pop x30
    ret


// bitwise_expr_stub function
// Receives nothing
// Returns Nothing
// Just calls general_recursion a bunch
// Uses X0, X1, X2 and X3 for passing constants to general recursion
bitwise_expr_stub:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3

    adr x0, relational_expr     // Using relational_expr
    adr x1, bitwise_expr_stub_string_0 // Using "AND_X0_X1_X0\n"
    adr x2, bitwise_and         // Using "&"
    adr x3, bitwise_expr_stub   // And recurse
    bl general_recursion        // Hit it

    adr x0, relational_expr     // Using relational_expr
    adr x1, bitwise_expr_stub_string_0 // Using "AND_X0_X1_X0\n"
    adr x2, logical_and         // Using "&&"
    adr x3, bitwise_expr_stub   // And recurse
    bl general_recursion        // Hit it

    adr x0, relational_expr     // Using relational_expr
    adr x1, bitwise_expr_stub_string_1 // Using "OR_X0_X1_X0\n"
    adr x2, bitwise_or          // Using "|"
    adr x3, bitwise_expr_stub   // And recurse
    bl general_recursion        // Hit it

    adr x0, relational_expr     // Using relational_expr
    adr x1, bitwise_expr_stub_string_1 // Using "OR_X0_X1_X0\n"
    adr x2, logical_or          // Using "||"
    adr x3, bitwise_expr_stub   // And recurse
    bl general_recursion        // Hit it

    adr x0, relational_expr     // Using relational_expr
    adr x1, bitwise_expr_stub_string_2 // Using "XOR_X0_X1_X0\n"
    adr x2, bitwise_xor         // Using "^"
    adr x3, bitwise_expr_stub   // And recurse
    bl general_recursion        // Hit it

    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// relational_expr function
// Receives nothing
// Returns Nothing
// Walks global_token list and updates output list
// just calls other function
relational_expr:
    push x30
    bl additive_expr            // Walk up the tree
    bl relational_expr_stub     // Recurse
    pop x30
    ret


// relational_expr_stub function
// Receives nothing
// Returns Nothing
// Just calls general_recursion a bunch
// Uses X0, X1, X2 and X3 for passing constants to general recursion
relational_expr_stub:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3

    adr x0, additive_expr       // Using additive_expr
    adr x1, relational_expr_stub_string_0 // Using "CMP_X1_X0\nSET_X0_TO_1\nSKIP_INST_LT\nSET_X0_TO_0\n"
    adr x2, less_than_string    // Using "<"
    adr x3, relational_expr_stub // And recurse
    bl general_recursion        // Hit it

    adr x0, additive_expr       // Using additive_expr
    adr x1, relational_expr_stub_string_1 // Using "CMP_X1_X0\nSET_X0_TO_1\nSKIP_INST_LE\nSET_X0_TO_0\n"
    adr x2, less_than_equal_string // Using "<="
    adr x3, relational_expr_stub // And recurse
    bl general_recursion        // Hit it

    adr x0, additive_expr       // Using additive_expr
    adr x1, relational_expr_stub_string_2 // Using "CMP_X1_X0\nSET_X0_TO_1\nSKIP_INST_GE\nSET_X0_TO_0\n"
    adr x2, greater_than_equal_string // Using ">="
    adr x3, relational_expr_stub // And recurse
    bl general_recursion        // Hit it

    adr x0, additive_expr       // Using additive_expr
    adr x1, relational_expr_stub_string_3 // Using "CMP_X1_X0\nSET_X0_TO_1\nSKIP_INST_GT\nSET_X0_TO_0\n"
    adr x2, greater_than_string // Using ">"
    adr x3, relational_expr_stub // And recurse
    bl general_recursion        // Hit it

    adr x0, additive_expr       // Using additive_expr
    adr x1, relational_expr_stub_string_4 // Using "CMP_X1_X0\nSET_X0_TO_1\nSKIP_INST_EQ\nSET_X0_TO_0\n"
    adr x2, equal_to_string     // Using "=="
    adr x3, relational_expr_stub // And recurse
    bl general_recursion        // Hit it

    adr x0, additive_expr       // Using additive_expr
    adr x1, relational_expr_stub_string_5 // Using "CMP_X1_X0\nSET_X0_TO_1\nSKIP_INST_NE\nSET_X0_TO_0\n"
    adr x2, not_equal_string    // Using "!="
    adr x3, relational_expr_stub // And recurse
    bl general_recursion        // Hit it

    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// additive_expr function
// Receives nothing
// Returns Nothing
// Walks global_token list and updates output list
// just calls other function
additive_expr:
    push x30
    bl postfix_expr             // Walk up the tree
    bl additive_expr_stub       // Recurse
    pop x30
    ret


// additive_expr_stub function
// Receives nothing
// Returns Nothing
// Just calls general_recursion a bunch
// Uses X0, X1, X2 and X3 for passing constants to general recursion
additive_expr_stub:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3

    adr x0, postfix_expr        // Using postfix_expr
    adr x1, additive_expr_stub_string_0 // Using "ADD_X0_X1_X0\n"
    adr x2, plus_string         // Using "+"
    adr x3, additive_expr_stub  // And recurse
    bl general_recursion        // Hit it

    adr x0, postfix_expr        // Using postfix_expr
    adr x1, additive_expr_stub_string_1 // Using "SUB_X0_X1_X0\n"
    adr x2, minus_string        // Using "-"
    adr x3, additive_expr_stub  // And recurse
    bl general_recursion        // Hit it

    adr x0, postfix_expr        // Using postfix_expr
    adr x1, additive_expr_stub_string_2 // Using "MUL_X0_X1_X0\n"
    adr x2, multiply_string     // Using "*"
    adr x3, additive_expr_stub  // And recurse
    bl general_recursion        // Hit it

    adr x0, postfix_expr        // Using postfix_expr
    adr x1, additive_expr_stub_string_3 // Using "SDIV_X0_X1_X0\n"
    adr x2, divide_string       // Using "/"
    adr x3, additive_expr_stub  // And recurse
    bl general_recursion        // Hit it

    adr x0, postfix_expr        // Using postfix_expr
    adr x1, additive_expr_stub_string_4 // Using "SDIV_X2_X1_X0\nMSUB_X0_X0_X2_X1\n"
    adr x2, modulus_string      // Using "%"
    adr x3, additive_expr_stub  // And recurse
    bl general_recursion        // Hit it

    adr x0, postfix_expr        // Using postfix_expr
    adr x1, additive_expr_stub_string_5 // Using "LSHIFT_X0_X1_X0\n"
    adr x2, left_shift_string   // Using "<<"
    adr x3, additive_expr_stub  // And recurse
    bl general_recursion        // Hit it

    adr x0, postfix_expr        // Using postfix_expr
    adr x1, additive_expr_stub_string_6 // Using "ARITH_RSHIFT_X0_X1_X0\n"
    adr x2, right_shift_string  // Using ">>"
    adr x3, additive_expr_stub  // And recurse
    bl general_recursion        // Hit it

    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// postfix_expr function
// Receives nothing
// Returns Nothing
// Walks global_token list and updates output list
// just calls other function
postfix_expr:
    push x30
    bl primary_expr             // Walk up the tree
    bl postfix_expr_stub        // Recurse
    pop x30
    ret


// postfix_expr_stub function
// Receives nothing
// Returns Nothing
// Checks for "[" and "->" and deals with them otherwise does nothing
// Uses X0, X1, X2 and X3 for passing constants to general recursion
postfix_expr_stub:
    push x30
    push x1                     // Protect X1
    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, open_bracket        // Using "["
    bl match                    // IF global_token->S == "["
    cmp x0, 0                   // then we have an array
    b.ne postfix_expr_stub_arrow // Otherwise try arrow

    // Deal with array
    bl postfix_expr_array       // Get it
    bl postfix_expr_stub        // Recurse

postfix_expr_stub_arrow:
    adr x0, arrow_string        // Using "->"
    bl match                    // IF global_token->S == "->"
    cmp x0, 0                   // Then we need to deal with struct offsets
    b.ne postfix_expr_stub_done // Otherwise be done

    // Deal with arrow
    bl postfix_expr_arrow       // Get it
    bl postfix_expr_stub        // Recurse

postfix_expr_stub_done:
    pop x1                      // Restore X1
    pop x30
    ret


// unary_expr_sizeof function
// Receives nothing
// Returns nothing
// Uses X2 for A->SIZE
unary_expr_sizeof:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    adr x0, unary_expr_sizeof_string_0 // Using "ERROR in unary_expr\nMissing (\n"
    adr x1, open_paren          // Using "("
    bl require_match            // Make sure we have it

    bl type_name                // Get the type
    ldr x2, [x0,8]              // Set A->TYPE

    adr x0, unary_expr_sizeof_string_1 // Using "ERROR in unary_expr\nMissing )\n"
    adr x1, close_paren         // Using ")"
    bl require_match            // Make sure we have it

    adr x0, unary_expr_sizeof_string_2 // Using "LOAD_W0_AHEAD\nSKIP_32_DATA\n%"
    bl emit_out                 // Emit it

    mov x0, x2                  // Put A->SIZE in the right place
    bl numerate_number          // Turn into string
    bl emit_out                 // Emit it

    adr x0, unary_expr_sizeof_string_3 // Using "\n"
    bl emit_out                 // Emit it

    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// postfix_expr_array function
// Receives Nothing
// Returns Nothing
// Uses X1 for struct type* ARRAY and X2 for char* ASSIGN
postfix_expr_array:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    adr x9, current_target      // ARRAY = current_target
    ldr x0, [x9]
    push x0                     // Protect it

    adr x0, expression          // Using expression
    bl common_recursion         // Recurse

    pop x1                      // Restore array
    adr x9, current_target      // current_target = ARRAY
    str x1, [x9]

    adr x2, postfix_expr_array_string_0 // ASSIGN = "DEREF_X0\n"

    adr x0, type_char_indirect_name // Using "char*"
    ldr x1, [x1,48]             // current_target->NAME
    bl match                    // IF current_target->NAME == "char*"
    cmp x0, 0                   // load a byte
    b.ne postfix_expr_array_large // Otherwise adjust

    // Deal with loading byte
    adr x2, postfix_expr_array_string_1 // ASSIGN = "DEREF_X0_BYTE\n"
    b postfix_expr_array_common // Do the next bit

postfix_expr_array_large:
    // deal with arrays made of things other than chars
    adr x0, postfix_expr_array_string_2 // Using "LOAD_W2_AHEAD\nSKIP_32_DATA\n%"
    bl emit_out                 // Emit it

    adr x9, current_target      // Using current_target
    ldr x0, [x9]
    ldr x0, [x0,24]             // current_target->INDIRECT
    ldr x0, [x0,8]              // current_target->INDIRECT->SIZE
    bl ceil_log2                // ceil_log2(current_target->indirect->size)
    bl numerate_number          // numerate_number(ceil_log2(current_target->indirect->size))
    bl emit_out                 // Emit it

    adr x0, postfix_expr_array_string_3 // Using "\nLSHIFT_X0_X0_X2\n"
    bl emit_out                 // Emit it

postfix_expr_array_common:
    adr x0, postfix_expr_array_string_4 // Using "ADD_X0_X1_X0\n"
    bl emit_out                 // Emit it

    adr x0, postfix_expr_array_string_5 // Using "ERROR in postfix_expr\nMissing ]\n"
    adr x1, close_bracket       // Using "]"
    bl require_match            // Make sure we have it

    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, equal               // Using "="
    bl match                    // IF global_token->S == "="
    cmp x0, 0                   // We need to preserve address
    b.ne postfix_expr_array_done // Otherwise be done

    // Clearing out assign
    adr x2, postfix_expr_array_string_6 // ASSIGN = ""

postfix_expr_array_done:
    mov x0, x2                  // Using ASSIGN
    bl emit_out                 // Emit it

    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// ceil_log2 function
// Receives int a in X0
// Performs log2 on A and
// Returns result in X0
// Uses X1 for INT A and X2 for INT RESULT
ceil_log2:
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x2, 0                   // RESULT = 0

    mov x1, x0                  // put A in right place
    sub x0, x0, 1               // (A - 1)
    and x0, x0, x1              // A & (A - 1)
    cmp x0, 0                   // IF 0 == (A & (A - 1))
    b.ne ceil_log2_iter         // Starting from -1

    mov x2, -1                  // RESULT = -1

ceil_log2_iter:
    cmp x1, 0                   // IF A > 0
    b.le ceil_log2_done         // Otherwise be done

    add x2, x2, 1               // RESULT = RESULT + 1
    asr x1, x1, 1               // A = A >> 1
    b ceil_log2_iter            // Keep looping

ceil_log2_done:
    mov x0, x2                  // Return RESULT
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    ret


// postfix_expr_arrow function
// Receives nothing
// Returns nothing
// Emits a bunch and updates current_target
// Uses X1 for struct type* I
postfix_expr_arrow:
    push x30
    push x1                     // Protect X1
    adr x0, postfix_expr_arrow_string_0 // Using "# looking up offset\n"
    bl emit_out                 // Emit it

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    ldr x1, [x0,16]             // Using global_token->S
    adr x9, current_target      // Using current_target
    ldr x0, [x9]
    bl lookup_member            // lookup_member(current_target, global_token->s)
    mov x1, x0                  // struct type* I = lookup_member(current_target, global_token->s)

    ldr x0, [x0,40]             // I->TYPE
    adr x9, current_target      // current_target = I->TYPE
    str x0, [x9]

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    ldr x0, [x1,16]             // I->OFFSET
    cmp x0, 0                   // IF 0 != I->OFFSET
    b.eq postfix_expr_arrow_first // Then we don't need to do an offset

    // Deal with needing an offset
    adr x0, postfix_expr_arrow_string_1 // Using "# -> offset calculation\nLOAD_W1_AHEAD\nSKIP_32_DATA\n%"
    bl emit_out                 // Emit it

    ldr x0, [x1,16]             // I->OFFSET
    bl numerate_number          // Convert to string
    bl emit_out                 // Emit it

    adr x0, postfix_expr_arrow_string_2 // Using "\nADD_X0_X1_X0\n"
    bl emit_out                 // Emit it

postfix_expr_arrow_first:
    ldr x0, [x1,8]              // I->SIZE
    cmp x0, 4                   // IF I->SIZE >= 4
    b.lt postfix_expr_arrow_done // Otherwise be done

    // Last chance for load
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x1, [x0,16]             // global_token->S
    adr x0, equal               // Using "="
    bl match                    // IF global_token->S == "="
    cmp x0, 0                   // Then we have assignment and should not load
    b.eq postfix_expr_arrow_done // Be done

    // Deal with load case
    adr x0, postfix_expr_arrow_string_3 // Using "DEREF_X0\n"
    bl emit_out                 // Emit it

postfix_expr_arrow_done:
    pop x1                      // Restore X1
    pop x30
    ret

// primary_expr function
// Receives nothing
// Returns nothing
primary_expr:
    push x30
    push x1                     // Protect X1

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x1, [x0,16]             // global_token->S
    adr x0, sizeof_string       // Using "sizeof"
    bl match                    // See if match
    cmp x0, 0                   // IF match
    b.ne primary_expr_neg       // Otherwise try negatives

    // Deal with sizeof
    bl unary_expr_sizeof        // Lets do this
    b primary_expr_done         // Be done

primary_expr_neg:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    ldrb w0, [x0]               // global_token->S[0]
    cmp x0, 45                  // IF global_token->S[0] == "-"
    b.ne primary_expr_not       // Otherwise try logical NOT

    // Deal with negative numbers
    adr x0, primary_expr_string_0 // Using "SET_X0_TO_0\n"
    bl emit_out                 // Emit it

    adr x0, postfix_expr        // Passing postfix_expr
    bl common_recursion         // Get what it is notting

    adr x0, primary_expr_string_1 // Using "SUB_X0_X1_X0\n"
    bl emit_out                 // Emit it
    b primary_expr_done         // Be done

primary_expr_not:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    ldrb w0, [x0]               // global_token->S[0]
    cmp x0, 33                  // IF global_token->S[0] == "!"
    b.ne primary_expr_bin       // Otherwise try '~'

    // Deal with logical not
    adr x0, primary_expr_string_2 // Using "SET_X0_TO_1\n"
    bl emit_out                 // Emit it

    adr x0, postfix_expr        // Passing postfix_expr
    bl common_recursion         // Get what it is notting

    adr x0, primary_expr_string_3 // Using "XOR_X0_X1_X0\n"
    bl emit_out                 // Emit it
    b primary_expr_done         // Be done

primary_expr_bin:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    ldrb w0, [x0]               // global_token->S[0]
    cmp x0, 126                 // IF global_token->S[0] == "~"
    b.ne primary_expr_paren     // Otherwise try paren

    // Deal with binary NOT
    adr x0, postfix_expr        // Passing postfix_expr
    bl common_recursion         // Get what it is notting
    adr x0, primary_expr_string_4 // Using "MVN_X0\n"
    bl emit_out                 // Emit it
    b primary_expr_done         // Be done

primary_expr_paren:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    ldrb w0, [x0]               // global_token->S[0]
    cmp x0, 40                  // IF global_token->S[0] == "("
    b.ne primary_expr_ch        // Otherwise try char

    // deal with nesting
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]
    bl expression               // Lets recurse
    adr x0, primary_expr_string_5 // Using "Error in Primary expression\nDidn't get )\n"
    adr x1, close_paren         // Using ")"
    bl require_match            // Make sure we have it
    b primary_expr_done         // Be done

primary_expr_ch:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    ldrb w0, [x0]               // global_token->S[0]
    cmp x0, 39                  // Using "'"
    b.ne primary_expr_str       // Otherwise try string

    // Deal with chars
    bl primary_expr_char        // Handle that char
    b primary_expr_done         // Be done

primary_expr_str:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    ldrb w0, [x0]               // global_token->S[0]
    cmp x0, 34                  // Using '"'
    b.ne primary_expr_var       // Otherwise try a variable

    // Deal with strings
    bl primary_expr_string      // Handle that string
    b primary_expr_done         // Be done

primary_expr_var:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    ldrb w0, [x0]               // global_token->S[0]
    adr x1, primary_expr_string_6 // Using "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
    bl In_Set                   // See if we have a match
    cmp x0, 1                   // IF match
    b.ne primary_expr_num       // otherwise try number

    // Deal with variables
    bl primary_expr_variable    // Deal with variable
    b primary_expr_done         // Be done

primary_expr_num:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    ldrb w0, [x0]               // global_token->S[0]
    adr x1, primary_expr_string_7 // Using "0123456789"
    bl In_Set                   // See if we have a match
    cmp x0, 1                   // IF match
    b.ne primary_expr_fail      // otherwise we failed hard

    // Deal with numbers
    bl primary_expr_number      // Collect the number
    b primary_expr_done         // Be done

primary_expr_fail:
    // looks like we hit bad input
    // abort before it gets bad
    bl primary_expr_failure     // No match means failure
primary_expr_done:
    pop x1                      // Restore X1
    pop x30
    ret

// primary_expr_variable function
// Receives nothing
// Returns nothing
// Walks global and updates output
// Uses X0 for struct token_list* a and X2 for char* S
primary_expr_variable:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x2, [x0,16]             // S = global_token->S
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    mov x0, x2                  // Using S
    adr x9, global_constant_list // Using global_constant_list
    ldr x1, [x9]
    bl sym_lookup               // sym_lookup(s, global_constant_list)
    cmp x0, 0                   // IF NULL == sym_lookup(s, global_constant_list)
    b.eq primary_expr_variable_local // Try locals next

    // Deal with constant load
    ldr x1, [x0,32]             // a->ARGS
    adr x0, primary_expr_variable_string_2 // Using "LOAD_IMMEDIATE_x0 %"
    bl emit_out                 // Emit it

    ldr x0, [x1,16]             // a->ARGS->S
    bl emit_out                 // Emit it

    adr x0, primary_expr_variable_string_1 // Using "\n"
    bl emit_out                 // Emit it
    b primary_expr_variable_done // Be done

primary_expr_variable_local:
    mov x0, x2                  // Using S
    adr x9, function            // Using function
    ldr x1, [x9]
    ldr x1, [x1,8]              // function->locals
    bl sym_lookup               // sym_lookup(s, function->locals)
    cmp x0, 0                   // IF NULL == sym_lookup(s, function->locals)
    b.eq primary_expr_variable_arguments // try arguments next

    // Deal with local load
    bl variable_load            // Collect it
    b primary_expr_variable_done // Be done

primary_expr_variable_arguments:
    mov x0, x2                  // Using S
    adr x9, function            // Using function
    ldr x1, [x9]
    ldr x1, [x1,32]             // function->args
    bl sym_lookup               // sym_lookup(s, function->args)
    cmp x0, 0                   // IF NULL == sym_lookup(s, function->args)
    b.eq primary_expr_variable_function // try functions next

    // Deal with argument load
    bl variable_load            // Collect it
    b primary_expr_variable_done // Be done

primary_expr_variable_function:
    mov x0, x2                  // Using S
    adr x9, global_function_list // Using global_function_list
    ldr x1, [x9]
    bl sym_lookup               // sym_lookup(s, global_function_list)
    cmp x0, 0                   // IF NULL == sym_lookup(s, global_function_list)
    b.eq primary_expr_variable_global // try globals next

    // Deal with functions
    bl function_load            // Deal with the function
    b primary_expr_variable_done // Be done

primary_expr_variable_global:
    mov x0, x2                  // Using S
    adr x9, global_symbol_list  // Using global_symbol_list
    ldr x1, [x9]
    bl sym_lookup               // sym_lookup(s, global_symbol_list)
    cmp x0, 0                   // IF NULL == sym_lookup(s, global_symbol_list)
    b.eq primary_expr_variable_error // Give up

    // Deal with globals
    bl global_load              // Collect that global
    b primary_expr_variable_done // Be done

primary_expr_variable_error:
    mov x14, 2                  // write to standard error
//  call line_error             // Write useful debug info
    mov x0, x2                  // put S in the right place
    bl File_Print               // print it

    adr x0, primary_expr_variable_string_0 // Ending string
    bl File_Print               // print it
    b Exit_Failure              // Abort Hard

primary_expr_variable_done:
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// function_call function
// Receives char* S in X0 and int BOOL in X1
// Builds stack frames before and tears them down after function calls
// Uses X2 for char* S, X3 for int BOOL, X5 for PASSED
function_call:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    push x5                     // Protect X5
    mov x2, x0                  // Put S in place
    mov x3, x1                  // Put BOOL in place
    mov x5, 0                   // PASSED = 0

    adr x0, function_call_string_0 // Using "ERROR in process_expression_list\nNo ( was found\n"
    adr x1, open_paren          // Using "("
    bl require_match            // Make sure we have it

    adr x0, function_call_string_1 // Using "PUSH_X16\t# Protect a tmp register we're going to use\n"
    bl emit_out                 // Emit it

    adr x0, function_call_string_2 // Using "PUSH_LR\t# Protect the old return pointer (link)\n"
    bl emit_out                 // Emit it

    adr x0, function_call_string_3a // Using "PUSH_BP\t# Protect the old base pointer\n"
    bl emit_out                 // Emit it

    adr x0, function_call_string_3b // Using "SET_X16_FROM_SP\t# The base pointer to-be\n"
    bl emit_out                 // Emit it

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    ldrb w0, [x0]               // global_token->S[0]
    cmp x0, 41                  // IF global_token->S[0] == ")"
    b.eq function_call_gen_done // Then no arguments to send

    // looks like we have arguments to collect
    bl expression               // Collect the argument

    adr x0, function_call_string_4 // Using "PUSH_X0\t#_process_expression1\n"
    bl emit_out                 // Emit it
    mov x5, 1                   // PASSED = 1

function_call_gen_iter:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    ldrb w0, [x0]               // global_token->S[0]
    cmp x0, 44                  // IF global_token->S[0] == ","
    b.ne function_call_gen_done // Otherwise we are done

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    bl expression               // Collect the argument

    adr x0, function_call_string_5 // Using "PUSH_X0\t#_process_expression2\n"
    bl emit_out                 // Emit it
    add x5, x5, 1               // PASSED = PASSED + 1
    b function_call_gen_iter    // Keep trying

function_call_gen_done:
    // All is collected
    adr x0, function_call_string_6 // Using "ERROR in process_expression_list\nNo ) was found\n"
    adr x1, close_paren         // Using ")"
    bl require_match            // Make sure we have it

    cmp x3, 0                   // IF(BOOL == TRUE)
    b.ne function_call_static   // Otherwise it is a static call

    // Deal with a passed function pointer
    adr x0, function_call_string_7a // Using "SET_X0_FROM_BP\n"
    bl emit_out                 // Emit it

    adr x0, function_call_string_7b // Using "LOAD_W1_AHEAD\nSKIP_32_DATA\n%"
    bl emit_out                 // Emit it

    mov x0, x2                  // Using S
    bl emit_out                 // Emit it

    adr x0, function_call_string_8 // Using "\nSUB_X0_X0_X1\n"
    bl emit_out                 // Emit it

    adr x0, function_call_string_9 // Using "DEREF_X0\n"
    bl emit_out                 // Emit it

    adr x0, function_call_string_10a // Using "SET_BP_FROM_X16\n"
    bl emit_out                 // Emit it

    adr x0, function_call_string_10b // Using "SET_X16_FROM_X0\n"
    bl emit_out                 // Emit it

    adr x0, function_call_string_10c // Using "BLR_X16\n"
    bl emit_out                 // Emit it

    adr x0, function_call_string_13 // Using "POP_X1\t# _process_expression_locals\n"
    b function_call_cleanup     // Clean up

function_call_static:
    // Deal with fixed function name
    adr x0, function_call_string_10a // Using "SET_BP_FROM_X16\n"
    bl emit_out                 // Emit it

    adr x0, function_call_string_11 // Using "LOAD_W16_AHEAD\nSKIP_32_DATA\n&FUNCTION_"
    bl emit_out                 // Emit it

    mov x0, x2                  // Using S
    bl emit_out                 // Emit it

    adr x0, function_call_string_12a // Using "\n"
    bl emit_out                 // Emit it

    adr x0, function_call_string_12b // Using "BLR_X16\n"
    bl emit_out                 // Emit it

    adr x0, function_call_string_13 // Using "POP_X1\t# _process_expression_locals\n"

function_call_cleanup:
    cmp x5, 0                   // IF PASSED > 0
    b.le function_call_done     // Otherwise be done

    // The desired string is already in X0
    bl emit_out                 // Emit it

    sub x5, x5, 1               // PASSED = PASSED - 1
    b function_call_cleanup     // Keep going

function_call_done:
    adr x0, function_call_string_14 // Using "POP_BP\t# Restore the old base pointer\n"
    bl emit_out                 // Emit it

    adr x0, function_call_string_15 // Using "POP_LR\t# Restore the old return pointer (link)\n"
    bl emit_out                 // Emit it

    adr x0, function_call_string_16 // Using "POP_X16\t# Restore a register we used as tmp\n"
    bl emit_out                 // Emit it


    pop x5                      // Restore X5
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// variable_load function
// Receives struct token_list* A in X0
// Returns nothing
// Updates output and current_target
// Uses X2 for A
variable_load:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x2, x0                  // Protect A

    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, open_paren          // Using "("
    bl match                    // IF global_token->S == "("
    cmp x0, 0                   // Then it might be a function
    b.ne variable_load_regular  // Otherwise it is regular

    ldr x1, [x2,24]             // A->TYPE
    ldr x1, [x1,48]             // A->TYPE->NAME
    adr x0, type_function_name  // Using "FUNCTION"
    bl match                    // IF A->TYPE->NAME == "FUNCTION"
    cmp x0, 0                   // Then it must be a function
    b.ne variable_load_regular  // otherwise just another regular

    // deal with function
    ldr x0, [x2,32]             // A->DEPTH
    bl numerate_number          // Convert to string
    mov x1, 0                   // pass 0 for true
    bl function_call            // Create the function call
    b variable_load_done        // Be done

variable_load_regular:
    ldr x0, [x2,24]             // A->TYPE
    adr x9, current_target      // current_target = A->TYPE
    str x0, [x9]

    adr x0, variable_load_string_0 // Using "SET_X0_FROM_BP\nLOAD_W1_AHEAD\nSKIP_32_DATA\n%"
    bl emit_out                 // Emit it

    ldr x0, [x2,32]             // A->DEPTH
    bl numerate_number          // Convert to string
    bl emit_out                 // Emit it

    adr x0, variable_load_string_1 // Using "\nSUB_X0_X0_X1\n"
    bl emit_out                 // Emit it

    // Check for special case of assignment
    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, equal               // Using "="
    bl match                    // IF global_token->S == "="
    cmp x0, 0                   // Then we skip loading
    b.eq variable_load_done     // And be done

    // Deal with common case
    adr x0, variable_load_string_2 // Using "DEREF_X0\n"
    bl emit_out                 // Emit it

variable_load_done:
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

// function_load function
// Receives struct token_list* a in X0
// Returns nothing
// Uses X2 to hold A->S
function_load:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    ldr x0, [x0,16]             // A->S
    mov x2, x0                  // Protect A->S
    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, open_paren          // Using "("
    bl match                    // IF global_token->S == "("
    cmp x0, 0                   // The we need to do a function call
    b.ne function_load_regular  // Otherwise just load it's address

    // Deal with function call
    mov x0, x2                  // Using A->S
    mov x1, 1                   // Using FALSE
    bl function_call            // Deal with it
    b function_load_done        // Be done

function_load_regular:
    adr x0, function_load_string_0 // Using "LOAD_W0_AHEAD\nSKIP_32_DATA\n&FUNCTION_"
    bl emit_out                 // Emit it

    mov x0, x2                  // Using A->S
    bl emit_out                 // Emit it

    adr x0, function_load_string_1 // Using "\n"
    bl emit_out                 // Emit it

function_load_done:
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// global_load function
// Receives struct token_list* A in X0
// Returns nothing
// Uses X1 to hold A->S
global_load:
    push x30
    push x1                     // Protect X1
    mov x1, x0                  // Set as A
    ldr x1, [x1,16]             // Set as A->S

    ldr x0, [x0,24]             // A->TYPE
    adr x9, current_target      // current_target = A->TYPE
    str x0, [x9]

    adr x0, global_load_string_0 // Using "LOAD_W0_AHEAD\nSKIP_32_DATA\n&GLOBAL_"
    bl emit_out                 // Emit it

    mov x0, x1                  // Using A->S
    bl emit_out                 // Emit it

    adr x0, global_load_string_1 // Using "\n"
    bl emit_out                 // Emit it

    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, equal               // "="
    bl match                    // IF global_token->S == "="
    cmp x0, 0                   // We need to skip for assignment
    b.eq global_load_done       // and be done

    // Otherwise we are loading the contents
    adr x0, global_load_string_2 // Using "DEREF_X0\n"
    bl emit_out                 // Emit it

global_load_done:
    pop x1                      // Restore X1
    pop x30
    ret


// sym_lookup function
// Receives char* S in X0 and struct token_list* symbol_list in X1
// Uses I->S in X0, S in X1 and I in X2
// Returns match or NULL
sym_lookup:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x2, x1                  // I = symbol_list
    mov x1, x0                  // Put S in the right place
sym_lookup_iter:
    cmp x2, 0                   // IF NULL == I
    b.eq sym_lookup_done        // We failed to find match

    ldr x0, [x2,16]             // Using I->S
    bl match                    // IF I->S == S
    cmp x0, 0                   // then be done
    b.eq sym_lookup_done        // Failed

    ldr x2, [x2]                // I = I->NEXT
    b sym_lookup_iter           // otherwise keep looping

sym_lookup_done:
    mov x0, x2                  // Return I
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// primary_expr_number function
// Receives nothing
// Returns nothing
// Simply uses current global token to update output and then steps to next global_token
primary_expr_number:
    push x30
    adr x0, primary_expr_number_string_0 // Using "LOAD_W0_AHEAD\nSKIP_32_DATA\n%"
    bl emit_out                 // Emit it

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    bl emit_out                 // Emit it

    adr x0, primary_expr_number_string_1 // Using "\n"
    bl emit_out                 // Emit it

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]
    pop x30
    ret


// primary_expr_string function
// receives nothing
// Returns nothing
// creates entries for string and calls to generate string output
// uses X2 for char* number_string
primary_expr_string:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    adr x9, current_count       // Using current_count
    ldr x1, [x9]
    mov x0, x1                  // And putting it in the right place
    bl numerate_number          // Get the string
    mov x2, x0                  // protect number_string

    add x1, x1, 1               // current_count + 1
    adr x9, current_count       // current_count = current_count + 1
    str x1, [x9]

    adr x0, primary_expr_string_string_0 // Using "LOAD_W0_AHEAD\nSKIP_32_DATA\n&STRING_"
    bl emit_out                 // Emit it

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    mov x1, x2                  // Put number_string in the right place
    bl uniqueID_out             // Make it unique

    // Generate the target
    adr x0, primary_expr_string_string_1 // Using ":STRING_"
    adr x9, strings_list        // Using strings_list
    ldr x1, [x9]
    bl emit                     // Emit it
    mov x1, x0                  // put new strings_list in place

    adr x9, function            // Using function
    ldr x0, [x9]
    ldr x0, [x0,16]             // function->S
    bl uniqueID                 // Make it unique
    mov x1, x0                  // put new strings_list in place

    // Parse the string
    adr x9, global_token        // Using global token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    bl parse_string             // convert to useful form
    bl emit                     // Emit it
    adr x9, strings_list        // Update Strings _list
    str x0, [x9]

    adr x9, global_token        // Using global token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// primary_expr_char function
// Receives nothing
// Returns nothing
// Updates output_list using global_token
primary_expr_char:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    adr x0, primary_expr_char_string_0 // Using "LOAD_W0_AHEAD\nSKIP_32_DATA\n%"
    bl emit_out                 // Emit it

    adr x9, global_token        // Using global token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    add x0, x0, 1               // global_token->S + 1
    bl escape_lookup            // Get the char
    bl numerate_number          // Convert to string
    bl emit_out                 // emit it

    adr x0, primary_expr_char_string_1 // Using "\n"
    bl emit_out                 // Emit it

    adr x9, global_token        // Using global token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// primary_expr_failure function
// Receives nothing
// Does not return but aborts hard
// Complains about the bad input
primary_expr_failure:
//  call line_error             // Get line of issue
    mov x14, 2                  // write to standard error
    adr x0, primary_expr_failure_string_0 // Using "Received "
    bl File_Print               // Print it

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    bl File_Print               // Print it

    adr x0, primary_expr_failure_string_1 // Using " in primary_expr\n"
    bl File_Print               // Print it
    b Exit_Failure              // Abort Hard


// general_recursion function
// Receives FUNCTION F in X0, char* S in X1, char* name in X2 and FUNCTION iterate in X3
// Returns nothing
// Uses X2 for char* S, X3 for FUNCTION iterate and X4 for FUNCTION F
// But generally recurses a shitload
general_recursion:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    push x4                     // Protect X4
    mov x4, x0                  // Protect F
    mov x0, x2                  // Put name in the right place
    mov x2, x1                  // Protect S

    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    bl match                    // IF match(name, global_token->s)
    cmp x0, 0                   // If true we do
    b.ne general_recursion_done // Otherwise skip it

    // Deal with the recursion
    mov x0, x4                  // Put F in the right place
    bl common_recursion         // Recurse

    mov x0, x2                  // Put S in the right place
    bl emit_out                 // Emit it

    mov x0, x3                  // Put iterate in the right place
    blr x0                      // Down the rabbit hole

general_recursion_done:
    pop x4                      // Restore X4
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// promote_type function
// Receives struct type* a in X0 and struct type* b in X1
// Returns the most recent type in X0
// Uses X0 for struct type* I, X2 for struct type* A and X3 for struct type* B
promote_type:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    cmp x1, 0                   // IF NULL == B
    b.eq promote_type_done      // Just return A

    mov x2, x0                  // Put A in place
    mov x3, x1                  // Put B in place
    mov x0, x1                  // IF NULL == A
    cmp x2, 0                   // Then we just return B
    b.eq promote_type_done      // Be done

    // Looks like we need to walk the list
    ldr x2, [x2,48]             // A->NAME
    ldr x3, [x3,48]             // B->NAME
    adr x9, global_types        // I = global_types
    ldr x0, [x9]
promote_type_iter:
    cmp x0, 0                   // IF NULL == I
    b.eq promote_type_done      // Just be done

    ldr x1, [x0,48]             // I->NAME
    cmp x1, x2                  // IF(A->NAME == I->NAME)
    b.eq promote_type_done      // Be done

    cmp x1, x3                  // IF(B->NAME == I->NAME)
    b.eq promote_type_done      // Be done

    ldr x1, [x0,24]             // I->INDIRECT
    ldr x1, [x1,48]             // I->INDIRECT->NAME

    cmp x1, x2                  // IF(A->NAME == I->INDIRECT->NAME)
    b.eq promote_type_done      // Be done

    cmp x1, x3                  // IF(B->NAME == I->INDIRECT->NAME)
    b.eq promote_type_done      // Be done

    ldr x0, [x0]                // I = I->NEXT
    b promote_type_iter         // Keep going

promote_type_done:
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// common_recursion function
// Receives FUNCTION F in X0
// Returns Nothing
// Walks global_token list and update output_list
// Updates current_target
// Uses X1 to hold FUNCTION F and struct type* last_type
common_recursion:
    push x30
    push x1                     // Protect X1
    mov x1, x0                  // Put FUNCTION F safely out of the way
    adr x0, common_recursion_string_0 // Using "PUSH_X0\t#_common_recursion\n"
    bl emit_out                 // Emit it

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    mov x0, x1                  // Prepare for function call
    adr x9, current_target      // Get last type
    ldr x1, [x9]
    blr x0                      // F();
    adr x9, current_target      // Get current_target
    ldr x0, [x9]
    bl promote_type             // get the right type
    adr x9, current_target      // Set new current_target
    str x0, [x9]

    adr x0, common_recursion_string_1 // Using "POP_X1\t# _common_recursion\n"
    bl emit_out                 // Emit it
    pop x1                      // Restore X1
    pop x30
    ret


// require_match function
// Receives char* message in X0 and char* required in X1
// Returns nothing
// Uses X2 to hold message and updates global_token
require_match:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x2, x0                  // put the message somewhere safe
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    bl match                    // IF required == global_token->S
    cmp x0, 0                   // we are fine
    b.eq require_match_good     // otherwise pain

    // Deal with bad times
//  call line_error             // Tell user what went wrong
    mov x14, 2                  // write to standard error
    mov x0, x2                  // using our message
    bl File_Print               // Print it
    b Exit_Failure              // Abort HARD

require_match_good:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x0, [x9]
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// uniqueID Function
// Receives char *S in X0, struct token_list* l in X1 and char* num in X2
// Returns updated struct token_list* L in X0
uniqueID:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    bl emit                     // emit(s, l)
    mov x1, x0                  // Put L in correct place
    adr x0, underline           // Using "_"
    bl emit                     // emit("_", l)
    mov x1, x0                  // Put L in correct place
    mov x0, x2                  // Put num in correct place
    bl emit                     // emit(num, l)
    mov x1, x0                  // Put L in correct place
    adr x0, uniqueID_string_0   // Using "\n"
    bl emit                     // emit("\n", l)
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// uniqueID_out function
// Receives char* S in X0 and char* num in X1
// Returns nothing
uniqueID_out:
    push x30
    push x0                     // Protect X0
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x2, x1                  // Put num in right spot
    adr x9, output_list         // Using output_list
    ldr x1, [x9]
    bl uniqueID                 // Get updated list
    adr x9, output_list         // output_list = uniqueID(s, output_list, num)
    str x0, [x9]
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x0                      // Restore X0
    pop x30
    ret

// emit_out function
// Receives char* S in X0
// Returns nothing
// Updates output_list
// MUST NOT ALTER REGISTERS
emit_out:
    push x30
    push x0                     // Protect X0
    push x1                     // Protect X1
    adr x9, output_list         // Using output_list
    ldr x1, [x9]
    bl emit                     // emit it
    adr x9, output_list         // update it
    str x0, [x9]
    pop x1                      // Restore X1
    pop x0                      // Restore X0
    pop x30
    ret


// emit function
// Receives char *s in X0 and struct token_list* head in X1
// Returns struct token_list* T in X0
emit:
    push x30
    push x2                     // Protect X2
    mov x2, x0                  // put S out of the way
    mov x0, 40                  // sizeof(struct token_list)
    bl malloc                   // get T
    str x1, [x0]                // t->next = head;
    str x2, [x0,16]             // t->s = s;
    pop x2                      // Restore X2
    pop x30
    ret


// escape_lookup function
// Receives char* c in X0
// Returns integer value of char in X0
// Aborts hard if unknown escape is received
// Uses X2 to hold char* C
escape_lookup:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x2, x0                  // Put char* C in safe place
    ldrb w0, [x2]               // Load c[0]
    cmp x0, 92                  // If '\\' != c[0]
    b.ne escape_lookup_done     // Be done

    mov x1, x2                  // Prepare for walk
    add x1, x1, 1               // increment
    ldrb w1, [x1]               // load c[1]

    cmp x1, 120                 // Check if \x??
    b.eq escape_lookup_hex      // Deal with hex

    // Deal with \? escapes
    mov x0, 10                  // Guess "\n"
    cmp x1, 110                 // If n
    b.eq escape_lookup_done     // Be done

    mov x0, 9                   // Guess "\t"
    cmp x1, 116                 // If t
    b.eq escape_lookup_done     // Be done

    mov x0, x1                  // "\\", "'" and '"' all encode as themselves
    cmp x1, 92                  // If "\\"
    b.eq escape_lookup_done     // Be done
    cmp x1, 39                  // IF "'"
    b.eq escape_lookup_done     // Be done
    cmp x1, 34                  // IF '"'
    b.eq escape_lookup_done     // Be done

    mov x0, 13                  // Guess "\r"
    cmp x1, 114                 // IF r
    b.eq escape_lookup_done     // Be done

    // Looks like we have no clue what we are doing
    // Aborting hard
    mov x14, 2                  // write to standard error
    adr x0, escape_lookup_string_0 // Using "Unknown escape received: "
    bl File_Print               // Print it
    mov x0, x2                  // Using C
    bl File_Print               // Print it
    adr x0, escape_lookup_string_1 // Using " Unable to process\n"
    bl File_Print               // Print it
    b Exit_Failure              // Abort Hard

escape_lookup_done:
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

escape_lookup_hex:
    // Give up on C and just assume they know what they are doing
    add x2, x2, 2               // increment
    ldrb w0, [x2]               // c[2]
    add x2, x2, 1               // increment
    bl char2hex                 // Get the hex value
    lsl x0, x0, 4               // c << 4
    mov x1, x0                  // protect c << 4
    ldrb w0, [x2]               // c[3]
    bl char2hex                 // Get the hex value
    add x0, x0, x1              // hex(c[2]) << 4 + hex(c[3])
    b escape_lookup_done        // Be done


// char2hex function
// Receives char in X0
// Returns hex or aborts hard
char2hex:
    sub x0, x0, 48              // Try 0-9
    cmp x0, 10                  // Otherwise fun times
    b.lt char2hex_done          // Be done

    // Deal with A-F
    mov x9, 0xDF
    and x0, x0, x9              // Unset High bit turning a-f into A-F
    sub x0, x0, 7               // Shift down into position
    cmp x0, 10                  // Everything below A is bad
    b.lt char2hex_fail          // And should fail
    cmp x0, 16                  // Make sure we are below F
    b.lt char2hex_done          // If so be done

char2hex_fail:
    // Time to fail hard
    mov x14, 2                  // write to standard error
    adr x0, char2hex_string_0   // Using "Tried to print non-hex number\n"
    bl File_Print               // Print it
    b Exit_Failure              // Abort Hard

char2hex_done:
    ret


// parse_string function
// Receives char* string in X0
// Returns cleaned up string
// Protects char* string in X1
parse_string:
    push x30
    push x1                     // Protect X1
    mov x1, x0                  // Protect char* string
    bl weird                    // Determine if we have a weird string
    cmp x0, 0                   // If weird
    b.eq parse_string_weird     // Deal with it

    // Dealing with regular string
    mov x0, x1                  // Passing Char* string
    bl collect_regular_string   // Collect it
    b parse_string_done         // Be done

parse_string_weird:
    mov x0, x1                  // Passing Char* string
    bl collect_weird_string     // Collect it

parse_string_done:
    pop x1                      // Restore X1
    pop x30
    ret


// weird function
// Receives char* string in X0
// Returns true(0) or false(1) in X0
// Uses X2 to hold char* string
weird:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x2, x0                  // Place string in safe place
    add x2, x2, 1               // increment past the "
weird_reset:
    ldrb w0, [x2]               // Load a char
    cmp x0, 0                   // IF NULL == C
    b.eq weird_false            // Nothing weird found

    cmp x0, 92                  // IF '\\'
    b.ne weird_escaped          // Deal with escaping

    // Deal with escape
    mov x0, x2                  // We are passing the string
    bl escape_lookup            // to look it up

    add x2, x2, 1               // string = string + 1
    ldrb w1, [x2]               // get string[1]
    cmp x1, 120                 // IF 'x' == string[1]
    b.ne weird_escaped          // otherwise skip the gap

    add x2, x2, 2               // string = string + 2

weird_escaped:
    push x0                     // Protect C in case we need it
    adr x1, weird_string_0      // Use "\t\n !#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    bl In_Set                   // To find if weird
    cmp x0, 1                   // IF TRUE
    pop x0                      // Restore C
    b.ne weird_true             // Then not weird

    add x2, x2, 1               // string = string + 1

    // Last chance for weird
    adr x1, weird_string_1      // Use "\t\n\r "
    bl In_Set                   // Check for special case
    cmp x0, 1                   // IF TRUE
    b.ne weird_reset            // Otherwise not in the special case

    // Deal with possible special case
    ldrb w0, [x2]               // Load string[1]
    cmp x0, 58                  // IF string[1] == ":"
    b.eq weird_true             // Then we hit the special case
    b weird_reset               // Keep trying

weird_done:
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

weird_true:
    mov x0, 0                   // Return true
    b weird_done                // Be done

weird_false:
    mov x0, 1                   // Return false
    b weird_done                // Be done


// collect_regular_string function
// Receives char* string in X0
// Malloc and creates new string to return in X0
// Uses X2 for return string and X3 for passed string
collect_regular_string:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    mov x3, x0                  // Protect our passed string
    mov x0, 256                 // We need 256bytes of storage
    bl malloc                   // Get our new pointer
    mov x2, x0                  // put it in place
    push x0                     // protect until done
collect_regular_string_reset:
    ldrb w0, [x3]               // string[0]
    cmp x0, 0                   // See if we hit the end
    b.eq collect_regular_string_done // And be done

    cmp x0, 92                  // IF string[0] == '\\'
    b.eq collect_regular_string_escaped // Deal with that mess

    // deal with boring char
    strb w0, [x2]               // hold_string[index] = string[0]
    add x2, x2, 1               // Increment it
    add x3, x3, 1               // Increment it
    b collect_regular_string_reset  // And keep going

collect_regular_string_escaped:
    mov x0, x3                  // Using string
    bl escape_lookup            // Get the char
    strb w0, [x2]               // hold_string[index] = escape_lookup(string)
    add x3, x3, 1               // Increment it
    add x2, x2, 1               // Increment it
    ldrb w0, [x3]               // string[0]
    add x3, x3, 1               // Increment it
    cmp x0, 120                 // IF 'x' == string[1]
    b.ne collect_regular_string_reset // Otherwise keep going

    add x3, x3, 2               // Increment it
    b collect_regular_string_reset // Keep going

collect_regular_string_done:
    mov x0, 34                  // Using '"'
    strb w0, [x2]               // hold_string[index] = '"'
    add x2, x2, 1               // Increment it
    mov x0, 10                  // Using "\n"
    strb w0, [x2]               // hold_string[index] = '\n'
    pop x0                      // Return our new string
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// collect_weird_string function
// Receives char* string in X0
// Mallocs and returns char* hold in X0
// Uses X2 for char* hold and X3 for char* string
collect_weird_string:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    mov x3, x0                  // Protect our passed string
    mov x0, 512                 // We need 512bytes of storage
    bl malloc                   // Get our new pointer
    mov x2, x0                  // put it in place
    push x0                     // protect until done

    mov x0, 39                  // Using "'"
    strb w0, [x2]               // hold_string[index] = "'"
    add x2, x2, 1               // Increment it
    add x3, x3, 1               // Increment it
collect_weird_string_reset:
    ldrb w0, [x3]               // Read a byte
    cmp x0, 0                   // IF NULL == string[0]
    b.eq collect_weird_string_done // Be done

    mov x0, 32                  // Using ' '
    strb w0, [x2]               // hold_string[index] = ' '
    add x2, x2, 1               // Increment it

    mov x0, x3                  // Using string
    bl escape_lookup            // Get the char
    bl hex8                     // Update X2

    ldrb w0, [x3]               // Read a byte
    add x3, x3, 1               // Increment it
    cmp x0, 92                  // IF string[0] == '\\'
    b.ne collect_weird_string_reset // Otherwise keep going

    ldrb w0, [x3]               // Read a byte
    add x3, x3, 1               // Increment it
    cmp x0, 120                 // IF 'x' == string[1]
    b.ne collect_weird_string_reset // Otherwise keep going

    add x3, x3, 2               // Increment it
    b collect_weird_string_reset // Keep going

collect_weird_string_done:
    mov x0, 32                  // Using ' '
    strb w0, [x2]               // hold_string[index] = ' '
    add x2, x2, 1               // Increment it
    mov x0, 48                  // Using '0'
    strb w0, [x2]               // hold_string[index] = '0'
    add x2, x2, 1               // Increment it
    strb w0, [x2]               // hold_string[index] = '0'
    add x2, x2, 1               // Increment it
    mov x0, 39                  // Using "'"
    strb w0, [x2]               // hold_string[index] = "'"
    add x2, x2, 1               // Increment it
    mov x0, 10                  // Using "\n"
    strb w0, [x2]               // hold_string[index] = '\n'
    pop x0                      // Return our new string
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// HEX to ascii routine
// Receives INT in X0 and CHAR* in X2
// Stores ascii of INT in CHAR*
// Returns only modifying X0 and X2
hex8:
    push x30
    push x0                     // Protect bottom nibble
    lsr x0, x0, 4               // do high nibble first
    bl hex4                     // Store it
    pop x0                      // do low nibble
    bl hex4
    pop x30
    ret

hex4:
    and x0, x0, 0xf             // isolate nibble
    add x0, x0,'0'              // convert to ascii
    cmp x0,'9'                  // valid digit?
    b.le hex1                   // yes
    add x0,x0,7                 // use alpha range
hex1:
    strb w0, [x2]               // store result
    add x2, x2, 1               // next position
    ret


// type_name function
// Receives nothing
// Returns type_size in X0
// Uses X2 for STRUCT TYPE* RET
type_name:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1,16]             // global_token->S
    adr x0, struct              // Using "struct"
    bl match                    // IF global_token->S == "struct"
    mov x2, x0                  // Protect structure
    cmp x0, 0                   // need to skip over "struct"
    b.ne type_name_native       // otherwise keep going

    // Deal with possible STRUCTs
    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x1, [x9]
    ldr x0, [x1,16]             // global_token->S
    adr x9, global_types        // get all known types
    ldr x1, [x9]
    bl lookup_type              // Find type if possible
    mov x2, x0                  // Set ret

    cmp x0, 0                   // IF NULL == ret
    b.ne type_name_common       // We have to create struct

    // Create a struct
    bl create_struct            // Create a new struct
    mov x2, 0                   // We wish to return NULL
    b type_name_done            // be done

type_name_native:
    // Deal only with native types
    mov x0, x1                  // Put global_token->S in the right place
    adr x9, global_types        // get all known types
    ldr x1, [x9]
    bl lookup_type              // Find the type if possible
    mov x2, x0                  // Set ret

    cmp x0, 0                   // IF NULL == ret
    b.ne type_name_common       // We need to abort hard

    // Aborting hard
    mov x14, 2                  // write to standard error
    adr x0, type_name_string_0  // Print header
    bl File_Print               // Print it

    adr x9, global_token        // Using global token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    bl File_Print               // Print it

    adr x0, type_name_string_1  // Print footer
    bl File_Print               // Print it

//  call line_error             // Give details
    b Exit_Failure              // Abort

type_name_common:
    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x1, [x9]

type_name_iter:
    ldr x0, [x1,16]             // global_token->S
    ldrb w0, [x0]               // global_token->S[0]
    cmp x0, 42                  // IF global_token->S[0] == '*'
    b.ne type_name_done         // recurse

    // Deal with char**
    ldr x2, [x2,24]             // ret = ret->indirect
    adr x9, global_token        // Using global_token
    ldr x1, [x9]
    ldr x1, [x1]                // global_token->next
    adr x9, global_token        // global_token = global_token->next
    str x1, [x9]
    b type_name_iter            // keep looping

type_name_done:
    mov x0, x2                  // put ret in the right place
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// lookup_type function
// Receives char* s in X0 and struct type* start in X1
// Returns struct type* in X0
// Uses X1 for S and X2 for I
lookup_type:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x2, x1                  // I = Start
    mov x1, x0                  // Put S in place
lookup_type_iter:
    cmp x2, 0                   // Check if I == NULL
    b.eq lookup_type_done       // return NULL

    ldr x0, [x2,48]             // I->NAME
    bl match                    // Check if matching
    cmp x0, 0                   // IF I->NAME == S
    b.eq lookup_type_done       // return it

    ldr x2, [x2]                // Otherwise I = I->NEXT
    b lookup_type_iter          // And keep looping

lookup_type_done:
    mov x0, x2                  // return either I or NULL
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// create_struct function
// Receives nothing
// Returns nothing
// Uses global_token to malloc a struct's definition
// Uses X2 for int OFFSET, X3 for struct type* head, X4 for struct type* I,
// X6 for member_size (Which is passed) and X5 for LAST
// X0 and X1 are used for scratch
create_struct:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    push x4                     // Protect X4
    push x6                     // Protect X6
    push x5                     // Protect X5
    mov x2, 0                   // OFFSET = 0
    mov x6, 0                   // member_size = 0

    mov x0, 56                  // sizeof(struct type)
    bl malloc                   // malloc(sizeof(struct type))
    mov x3, x0                  // Set HEAD

    mov x0, 56                  // sizeof(struct type)
    bl malloc                   // malloc(sizeof(struct type))
    mov x4, x0                  // Set I

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    str x0, [x3,48]             // HEAD->NAME = global_token->S
    str x0, [x4,48]             // I->NAME = global_token->S

    str x4, [x3,24]             // HEAD->INDIRECT = I
    str x3, [x4,24]             // I->INDIRECT = HEAD

    adr x9, global_types        // Using global_types
    ldr x0, [x9]
    str x0, [x3]                // HEAD->NEXT = global_types
    adr x9, global_types        // global_types = HEAD
    str x3, [x9]

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    mov x0, 8                   // Using register size
    str x0, [x4,8]              // I->SIZE = register size

    adr x0, create_struct_string_0 // Using "ERROR in create_struct\n Missing {\n"
    adr x1, open_curly_brace    // Using "{"
    bl require_match            // Make sure we have it

    mov x5, 0                   // LAST = NULL

create_struct_iter:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    ldrb w0, [x0]               // global_token->S[0]
    cmp x0, 125                 // IF global_token->S[0] == "}"
    b.eq create_struct_done     // be done

    // Looks like we are adding members
    // Lets see if it is a union
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    adr x1, union               // Using "union"
    bl match                    // IF match(global_token->s, "union")
    cmp x0, 0                   // Deal with union
    b.ne create_struct_single   // Otherwise deal with singles

    // Deal with union
    mov x0, x5                  // Put last in right place
    mov x1, x2                  // put offset in right place
    bl build_union              // ASSEMBLE
    mov x5, x0                  // last = build_union(last, offset)
    add x2, x2, x6              // offset = offset + member_size

    adr x0, create_struct_string_1 // Using "ERROR in create_struct\n Missing ;\n"
    adr x1, semicolon           // Using ";"
    bl require_match            // Make sure we have it
    b create_struct_iter        // keep going

create_struct_single:
    // deal with singles
    mov x0, x5                  // Put last in right place
    mov x1, x2                  // put offset in right place
    bl build_member             // ASSEMBLE
    mov x5, x0                  // last = build_union(last, offset)
    add x2, x2, x6              // offset = offset + member_size

    adr x0, create_struct_string_1 // Using "ERROR in create_struct\n Missing ;\n"
    adr x1, semicolon           // Using ";"
    bl require_match            // Make sure we have it
    b create_struct_iter        // keep going

create_struct_done:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    adr x0, create_struct_string_1 // Using "ERROR in create_struct\n Missing ;\n"
    adr x1, semicolon           // Using ";"
    bl require_match            // Make sure we have it

    str x2, [x3,8]              // HEAD->SIZE = OFFSET
    str x5, [x3,32]             // HEAD->MEMBERS = LAST
    str x5, [x4,32]             // I->MEMBERS = LAST

    pop x5                      // Restore X5
    pop x6                      // Restore X6
    pop x4                      // Restore X4
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// lookup_member function
// Receives struct type* parent in X0 and char* name in X1
// Returns struct type* I in X0
// Uses char* NAME in X1, X2 for struct type* I and X3 to hold parent for errors
// Aborts hard if not found
lookup_member:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    mov x3, x0                  // Protect Parent
    ldr x2, [x0,32]             // struct type* I = parent->MEMBERS
lookup_member_iter:
    cmp x2, 0                   // IF I == NULL
    b.eq lookup_member_fail     // Abort HARD

    ldr x0, [x2,48]             // Using I->NAME
    bl match                    // IF I->NAME == NAME
    cmp x0, 0                   // Then we have found the member
    mov x0, x2                  // Prepare for return
    ldr x2, [x2,32]             // Prepare for loop I = I->MEMBERS
    b.ne lookup_member_iter     // Looks like we are looping

    // I is already in X0
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

lookup_member_fail:
    mov x14, 2                  // write to standard error
    adr x0, lookup_member_string_0 // Using "ERROR in lookup_member "
    bl File_Print               // print it

    ldr x0, [x3,48]             // PARENT->NAME
    bl File_Print               // print it

    adr x0, arrow_string        // Using "->"
    bl File_Print               // print it

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    bl File_Print               // print it

    adr x0, lookup_member_string_1 // Using " does not exist\n"
    bl File_Print               // print it

//  call line_error             // Write useful debug info

    adr x0, lookup_member_string_2 // Using "\n"
    bl File_Print               // print it
    b Exit_Failure              // Abort Hard


// build_member function
// Receives struct type* last in X0, int offset in X1 and global member_size in X6
// Updates member_size in X6 and returns struct type* I in X0
// Uses X2 for struct type* member_type and X3 for struct type* I
build_member:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    mov x3, x0                  // Put last out of the way
    mov x0, 56                  // Allocate type
    bl malloc                   // Get I
    str x3, [x0,32]             // I->MEMBERS = LAST
    str x1, [x0,16]             // I->OFFSET = OFFSET
    mov x3, x0                  // Put I in place

    bl type_name                // Get member_type
    mov x2, x0                  // Put in place
    str x2, [x3,40]             // I->TYPE = MEMBER_TYPE
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x1, [x0,16]             // global_token->S
    str x1, [x3,48]             // I->NAME = global_token->S
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    // Check if we have an array
    ldr x1, [x0,16]             // global_token->S
    adr x0, open_bracket        // Using "["
    bl match                    // IF global_token->S == "["
    cmp x0, 0                   // Then we have to deal with arrays in our structs
    b.eq build_member_array     // So deal with that pain

    // Deal with non-array case
    ldr x0, [x2,8]              // member_type->SIZE
    str x0, [x3,8]              // I->SIZE = member_type->SIZE
    b build_member_done         // Be done

build_member_array:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    ldr x0, [x0,16]             // global_token->S
    bl numerate_string          // convert number
    ldr x1, [x2,40]             // member_type->TYPE
    ldr x1, [x1,8]              // member_type->TYPE->SIZE
    mul x0, x0, x1              // member_type->type->size * numerate_string(global_token->s)
    str x0, [x3,8]              // I->SIZE = member_type->type->size * numerate_string(global_token->s)

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    adr x0, build_member_string_0 // Using "Struct only supports [num] form\n"
    adr x1, close_bracket       // Using "]"
    bl require_match            // Make sure we have it

build_member_done:
    ldr x6, [x3,8]              // MEMBER_SIZE = I->SIZE
    str x2, [x3,40]             // I->TYPE = MEMBER_TYPE
    mov x0, x3                  // Return I

    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// build_union function
// Receives struct type* last in X0, int offset in X1 and global member_size in X6
// Updates member_size in X6 and returns struct type* LAST in X0
// Uses X2 for struct type* last, X3 for int offset, X5 for int size and X6 for int member_size
build_union:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    push x5                     // Protect X5
    mov x2, x0                  // Put LAST in right spot
    mov x3, x1                  // Put OFFSET in right spot
    mov x5, 0                   // SIZE = 0

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    adr x0, build_union_string_0 // Using "ERROR in build_union\nMissing {\n"
    adr x1, open_curly_brace    // Using "{"
    bl require_match            // Make sure we have it

build_union_iter:
    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0,16]             // global_token->S
    ldrb w0, [x0]               // global_token->S[0]
    cmp x0, 125                 // IF global_token->S[0] == "}"
    b.eq build_union_done       // Be done

    // Collect union member
    mov x0, x2                  // Passing LAST
    mov x1, x3                  // Passing offset
    bl build_member             // build_member(last, offset)
    mov x2, x0                  // last = build_member(last, offset)

    cmp x5, x6                  // IF member_size > size
    b.gt build_union_size       // Then update size

    // deal with member_size > size
    mov x5, x6                  // SIZE = MEMBER_SIZE

build_union_size:
    adr x0, build_union_string_1 // Using "ERROR in build_union\nMissing ;\n"
    adr x1, semicolon           // Using ";"
    bl require_match            // Make sure we have it
    b build_union_iter          // Keep going

build_union_done:
    mov x6, x5                  // MEMBER_SIZE = SIZE

    adr x9, global_token        // Using global_token
    ldr x0, [x9]
    ldr x0, [x0]                // global_token->NEXT
    adr x9, global_token        // global_token = global_token->NEXT
    str x0, [x9]

    mov x0, x2                  // Return last

    pop x5                      // Restore X5
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// sym_declare function
// Receives char *s in X0, struct type* t in X1, and struct token_list* list in X2
// Returns struct token_list* in X0
// Uses X0 for A
sym_declare:
    push x30
    push x3                     // Protect X3
    mov x3, x0                  // Get char *S safely out of the way
    mov x0, 40                  // Using sizeof(struct token_list)
    bl malloc                   // Get pointer to A
    str x2, [x0]                // A->NEXT = LIST
    str x3, [x0,16]             // A->S = S
    str x1, [x0,24]             // A->TYPE = T
    pop x3                      // Restore X3
    pop x30
    ret


// match function
// Receives CHAR* in X0 and CHAR* in X1
// Returns 0 (TRUE) or 1 (FALSE) in X0
match:
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    mov x2, x0                  // S1 in place
    mov x3, x1                  // S2 in place
match_Loop:
    ldrb w0, [x2]               // S1[0]
    ldrb w1, [x3]               // S2[0]
    cmp x0, x1                  // See if they match
    b.ne match_False            // If not

    add x2, x2, 1               // S1 = S1 + 1
    add x3, x3, 1               // S2 = S2 + 1
    cmp x0, 0                   // If reached end of string
    b.eq match_Done             // Perfect match
    b match_Loop                // Otherwise keep looping

match_False:
    mov x0, 1                   // Return false
match_Done:
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    ret


// numerate_number function
// Receives an INT A in X0
// Returns char* result in X0
// Allocates 16 bytes of memory
// Behaves badly when given a negative number too large
// Uses X0 for temp, X1 for DIVISOR, X3 for mod/0, X5 for result[i] and X4 for A
numerate_number:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    push x5                     // Protect X5
    push x4                     // Protect X4
    mov x4, x0                  // Protect A

    mov x0, 16                  // 16bytes
    bl malloc                   // Get our pointer
    push x0                     // Protect our pointer
    mov x5, x0                  // put pointer in right place
    movz x1, 0xCA00
    movk x1, 0x3B9A, lsl 16     // Set divisor to largest positive number that fits in 32bits

    cmp x4, 0                   // Deal with 0 case
    b.eq numerate_number_ZERO   // If it is
    b.gt numerate_number_positive // If it is positive

                                // Deal with negative case
    mov x0, 45                  // Using "-"
    strb w0, [x5]               // Write it
    add x5, x5, 1               // increment
    neg x4, x4                  // A = A * -1

numerate_number_positive:
    mov x3, 0                   // Set top to 0
    mov x0, x4                  // Using A as bottom
    udiv x0, x0, x1
    cmp x0, 0                   // IF 0 == (a / divisor)
    b.ne numerate_number_iter   // Clean up those leading Zeros

    mov x3, 0                   // Set top to 0
    mov x0, x1                  // Using Divisor for bottom
    mov x1, 10                  // Make this shit work because idiv 10 doesn't work
    udiv x0, x0, x1
    mov x1, x0                  // Update divisor
    b numerate_number_positive  // Keep collecting

numerate_number_iter:
    cmp x1, 0                   // IF DIVISOR < 0
    b.le numerate_number_done   // Be done

    mov x3, 0                   // Set top to 0
    mov x0, x4                  // Using A as bottom
    udiv x2, x0, x1
    msub x3, x2, x1, x0
    add x2, x2, 48              // ((a / divisor) + 48)
    strb w2, [x5]               // Write it
    mov x4, x3                  // a = a % divisor

    mov x3, 0                   // Set top to 0
    mov x0, x1                  // Using Divisor for bottom
    mov x1, 10                  // Make this shit work because idiv 10 doesn't work
    udiv x0, x0, x1
    mov x1, x0                  // Update divisor

    add x5, x5, 1               // increment
    b numerate_number_iter      // Keep going

numerate_number_done:
    pop x0                      // Restore our result
    pop x4                      // Restore X4
    pop x5                      // Restore X5
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret

numerate_number_ZERO:
    mov x0, 48                  // Using '0'
    strb w0, [x5]               // Write it
    add x5, x5, 1               // increment
    b numerate_number_done      // Be done


// numerate_string function
// Receives CHAR* in X0
// Returns value of CHAR* in X0
// Uses X0 for VALUE, X1 for S, X2 for CH and X5 for NEGATIVE?
numerate_string:
    push x30
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    push x5                     // Protect X5
    mov x1, x0                  // put S in correct place
    mov x0, 0                   // Initialize to Zero
numerate_string_loop:
    ldrb w2, [x1,1]             // S[1]
    cmp x2, 120                 // IF 'x' == S[1]
    b.eq numerate_hex           // Deal with hex input

    // Assume decimal input
    mov x5, 0                   // Assume no negation
    ldrb w2, [x1]               // S[0]
    cmp x2, 45                  // IF '-' == S[0]
    b.ne numerate_decimal       // Skip negation

    mov x5, 1                   // Set FLAG
    add x1, x1, 1               // S = S + 1

numerate_decimal:
    ldrb w2, [x1]               // S[0]
    cmp x2, 0                   // IF NULL == S[0]
    b.eq numerate_decimal_done  // We are done

    mov x9, 10
    mul x0, x0, x9              // VALUE = VALUE * 10
    sub x2, x2, 48              // CH = CH - '0'
    cmp x2, 9                   // Check for illegal
    b.gt numerate_string_fail   // If CH > '9'
    cmp x2, 0                   // Check for illegal
    b.lt numerate_string_fail   // IF CH < 0
    add x0, x0, x2              // VALUE = VALUE + CH
    add x1, x1, 1               // S = S + 1
    b numerate_decimal          // Keep looping

numerate_decimal_done:
    cmp x5, 1                   // Check if need to negate
    b.ne numerate_string_done   // Nope

    neg x0, x0                  // VALUE = VALUE * -1
    b numerate_string_done      // Done

numerate_hex:
    add x1, x1, 2               // S = S + 2
numerate_hex_loop:
    ldrb w2, [x1]               // S[0]
    cmp x2, 0                   // IF NULL == S[0]
    b.eq numerate_string_done   // We are done

    lsl x0, x0, 4               // VALUE = VALUE << 4
    sub x2, x2, 48              // CH = CH - '0'
    cmp x2, 10                  // IF 10 >= CH
    b.lt numerate_hex_digit     // NO
    sub x2, x2, 7               // Push A-F into range
numerate_hex_digit:
    cmp x2, 15                  // Check for illegal
    b.gt numerate_string_fail   // If CH > 'F'
    cmp x2, 0                   // Check for illegal
    b.lt numerate_string_fail   // IF CH < 0
    add x0, x0, x2              // VALUE = VALUE + CH
    add x1, x1, 1               // S = S + 1
    b numerate_hex_loop         // Keep looping

numerate_string_fail:
    mov x0, 0                   // return ZERO

numerate_string_done:
    pop x5                      // Restore X5
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x30
    ret


// Exit_Failure function
// Receives nothing
// And aborts hard
// Does NOT return
Exit_Failure:
    mov x0, 1                   // All is wrong
    mov x8, #93                 // put the exit syscall number in eax
    svc 0                       // Call it a good day



// debug_list function
// Receives struct token_list* in X0
// Prints contents of list and exits
// Does NOT return
debug_list:
    mov x12, x0                 // Protect the list pointer
    mov x14, 2                  // write to standard error

debug_list_iter:
                                // Header
    adr x0, debug_list_string0  // Using our first string
    bl File_Print               // Print it
    mov x0, x12                 // Use address of pointer
    bl numerate_number          // Convert it into string
    bl File_Print               // Print it

    // NEXT
    adr x0, debug_list_string1  // Using our second string
    bl File_Print               // Print it
    ldr x0, [x12]               // Use address of pointer
    bl numerate_number          // Convert it into string
    bl File_Print               // Print it

    // PREV
    adr x0, debug_list_string2  // Using our third string
    bl File_Print               // Print it
    ldr x0, [x12,8]             // Use address of pointer
    bl numerate_number          // Convert it into string
    bl File_Print               // Print it

    // S
    adr x0, debug_list_string3  // Using our fourth string
    bl File_Print               // Print it
    ldr x0, [x12,16]            // Use address of pointer
    bl numerate_number          // Convert it into string
    bl File_Print               // Print it

    // S Contents
    adr x0, debug_list_string4  // Using our fifth string
    bl File_Print               // Print it
    ldr x0, [x12,16]            // Use address of string
    cmp x0, 0                   // IF NULL Pointer
    b.ne debug_list_null        // otherwise display
    adr x0, debug_list_string_null // Give meaningful message instead
debug_list_null:
    bl File_Print               // Print it

    // TYPE
    adr x0, debug_list_string5  // Using our sixth string
    bl File_Print               // Print it
    ldr x0, [x12,24]            // Use address of pointer
    bl numerate_number          // Convert it into string
    bl File_Print               // Print it

    // ARGS/DEPTH
    adr x0, debug_list_string6  // Using our seventh string
    bl File_Print               // Print it
    ldr x0, [x12,32]            // Use address of pointer
    bl numerate_number          // Convert it into string
    bl File_Print               // Print it

    mov x0, 10                  // Add "\n"
    bl fputc                    // print it
    bl fputc                    // print it

    ldr x12, [x12]              // TOKEN = TOKEN->NEXT
    cmp x12, 0                  // Check if NULL
    b.ne debug_list_iter        // iterate otherwise

    mov x0, 666                 // All is HELL
    mov x8, #93                 // put the exit syscall number in eax
    svc 0                       // Call it a bad day

    .section .data

prim_types:
type_void:
    .quad type_int              // NEXT
    .quad 8                     // SIZE
    .quad 0                     // OFFSET
    .quad type_void             // INDIRECT
    .quad 0                     // MEMBERS
    .quad type_void             // TYPE
    .quad type_void_name        // NAME

type_int:
    .quad type_char             // NEXT
    .quad 8                     // SIZE
    .quad 0                     // OFFSET
    .quad type_int              // INDIRECT
    .quad 0                     // MEMBERS
    .quad type_int              // TYPE
    .quad type_int_name         // NAME

type_char:
    .quad type_file             // NEXT
    .quad 1                     // SIZE
    .quad 0                     // OFFSET
    .quad type_char_indirect    // INDIRECT
    .quad 0                     // MEMBERS
    .quad type_char             // TYPE
    .quad type_char_name        // NAME

type_char_indirect:
    .quad type_file             // NEXT
    .quad 8                     // SIZE
    .quad 0                     // OFFSET
    .quad type_char_double_indirect // INDIRECT
    .quad 0                     // MEMBERS
    .quad type_char_indirect    // TYPE
    .quad type_char_indirect_name // NAME

type_char_double_indirect:
    .quad type_file             // NEXT
    .quad 8                     // SIZE
    .quad 0                     // OFFSET
    .quad type_char_double_indirect // INDIRECT
    .quad 0                     // MEMBERS
    .quad type_char_indirect    // TYPE
    .quad type_char_double_indirect_name // NAME

type_file:
    .quad type_function         // NEXT
    .quad 8                     // SIZE
    .quad 0                     // OFFSET
    .quad type_file             // INDIRECT
    .quad 0                     // MEMBERS
    .quad type_file             // TYPE
    .quad type_file_name        // NAME

type_function:
    .quad type_unsigned         // NEXT
    .quad 8                     // SIZE
    .quad 0                     // OFFSET
    .quad type_function         // INDIRECT
    .quad 0                     // MEMBERS
    .quad type_function         // TYPE
    .quad type_function_name    // NAME

type_unsigned:
    .quad type_long             // NEXT
    .quad 8                     // SIZE
    .quad 0                     // OFFSET
    .quad type_unsigned         // INDIRECT
    .quad 0                     // MEMBERS
    .quad type_unsigned         // TYPE
    .quad type_unsigned_name    // NAME

type_long:
    .quad 0                     // NEXT
    .quad 8                     // SIZE
    .quad 0                     // OFFSET
    .quad type_long             // INDIRECT
    .quad 0                     // MEMBERS
    .quad type_long             // TYPE
    .quad type_long_name        // NAME


Address_of: .quad 0
C: .quad 0
Token: .quad 0
break_frame: .quad 0
break_target_func: .quad 0
break_target_head: .quad 0
break_target_num: .quad 0
current_count: .quad 0
current_target: .quad 0
function: .quad 0
global_constant_list: .quad 0
global_function_list: .quad 0
global_symbol_list: .quad 0
global_token: .quad 0
global_types: .quad prim_types
globals_list: .quad 0
output_list: .quad 0
string_index: .quad 0
strings_list: .quad 0

    .section .rodata
// Keywords
union: .asciz "union"
struct: .asciz "struct"
constant: .asciz "CONSTANT"
main_string: .asciz "main"
argc_string: .asciz "argc"
argv_string: .asciz "argv"
if_string: .asciz "if"
else_string: .asciz "else"
do_string: .asciz "do"
while_string: .asciz "while"
for_string: .asciz "for"
asm_string: .asciz "asm"
goto_string: .asciz "goto"
return_string: .asciz "return"
break_string: .asciz "break"
continue_string: .asciz "continue"
sizeof_string: .asciz "sizeof"
plus_string: .asciz "+"
minus_string: .asciz "-"
multiply_string: .asciz "*"
divide_string: .asciz "/"
modulus_string: .asciz "%"
left_shift_string: .asciz "<<"
right_shift_string: .asciz ">>"
less_than_string: .asciz "<"
less_than_equal_string: .asciz "<="
greater_than_equal_string: .asciz ">="
greater_than_string: .asciz ">"
equal_to_string: .asciz "=="
not_equal_string: .asciz "!="
bitwise_and: .asciz "&"
logical_and: .asciz "&&"
bitwise_or: .asciz "|"
logical_or: .asciz "||"
bitwise_xor: .asciz "^"
arrow_string: .asciz "->"

// Frequently Used strings
// Generally used by require_match
open_curly_brace: .asciz "{"
close_curly_brace: .asciz "}"
open_paren: .asciz "("
close_paren: .asciz ")"
open_bracket: .asciz "["
close_bracket: .asciz "]"
comma: .asciz ","
semicolon: .asciz ";"
equal: .asciz "="
percent: .asciz "%"
newline: .asciz "\n"
underline: .asciz "_"


type_void_name: .asciz "void"
type_int_name: .asciz "int"
type_char_name: .asciz "char"
type_char_indirect_name: .asciz "char*"
type_char_double_indirect_name: .asciz "char**"
type_file_name: .asciz "FILE"
type_function_name: .asciz "FUNCTION"
type_unsigned_name: .asciz "unsigned"
type_long_name: .asciz "long"


header_string1: .asciz "\n# Core program\n"
header_string2: .asciz "\n:ELF_data\n"
header_string3: .asciz "\n# Program global variables\n"
header_string4: .asciz "\n# Program strings\n"
header_string5: .asciz "\n:ELF_end\n"

alphas: .asciz "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"
symbols: .asciz "<=>|&!-"
strings: .byte 34, 39, 0

// Strings needed by the program function
program_string_0: .asciz ":GLOBAL_"
program_string_1: .asciz "\nNULL\n"

declare_function_string_0: .asciz "# Defining function "
declare_function_string_1: .asciz "\n:FUNCTION_"
declare_function_string_2: .asciz "RETURN\n"
declare_function_string_3: .asciz "\n"

statement_string_0: .asciz "\t#C goto label\n"
statement_string_1a: .asciz "LOAD_W16_AHEAD\nSKIP_32_DATA\n&"
statement_string_1b: .asciz "\nBR_X16"
statement_string_2: .asciz "\n"
statement_string_3: .asciz "\n#continue statement\n"
statement_string_4: .asciz "ERROR in statement\nMissing //\n"

recursive_statement_string_0: .asciz "RETURN\n"
recursive_statement_string_1: .asciz "POP_X1\t# _recursive_statement_locals\n"

return_result_string_0: .asciz "ERROR in return_result\nMISSING //\n"
return_result_string_1: .asciz "POP_X1\t# _return_result_locals\n"
return_result_string_2: .asciz "RETURN\n"

collect_local_string_0: .asciz "# Defining local "
collect_local_string_1: .asciz "\n"
collect_local_string_2: .asciz "ERROR in collect_local\nMissing //\n"
collect_local_string_3: .asciz "PUSH_X0\t#"

process_asm_string_0: .asciz "ERROR in process_asm\nMISSING (\n"
process_asm_string_1: .byte 10, 0
process_asm_string_2: .asciz "ERROR in process_asm\nMISSING )\n"
process_asm_string_3: .asciz "ERROR in process_asm\nMISSING //\n"

process_if_string_0: .asciz "# IF_"
process_if_string_1: .asciz "ERROR in process_if\nMISSING (\n"
process_if_string_2a: .asciz "CBNZ_X0_PAST_BR\nLOAD_W16_AHEAD\nSKIP_32_DATA\n&ELSE_"
process_if_string_2b: .asciz "\nBR_X16\n"
process_if_string_3: .asciz "ERROR in process_if\nMISSING )\n"
process_if_string_4: .asciz "LOAD_W16_AHEAD\nSKIP_32_DATA\n&_END_IF_"
process_if_string_5: .asciz "\nBR_X16\n:ELSE_"
process_if_string_6: .asciz ":_END_IF_"

process_do_string_0: .asciz "DO_END_"
process_do_string_1: .asciz ":DO_"
process_do_string_2: .asciz "ERROR in process_do\nMISSING while\n"
process_do_string_3: .asciz "ERROR in process_do\nMISSING (\n"
process_do_string_4: .asciz "ERROR in process_do\nMISSING )\n"
process_do_string_5: .asciz "ERROR in process_do\nMISSING //\n"
process_do_string_6a: .asciz "CBZ_X0_PAST_BR\nLOAD_W16_AHEAD\nSKIP_32_DATA\n&DO_"
process_do_string_6b: .asciz "\nBR_X16\n"
process_do_string_7: .asciz ":DO_END_"

process_while_string_0: .asciz "END_WHILE_"
process_while_string_1: .asciz ":WHILE_"
process_while_string_2: .asciz "ERROR in process_while\nMISSING (\n"
process_while_string_3a: .asciz "CBNZ_X0_PAST_BR\nLOAD_W16_AHEAD\nSKIP_32_DATA\n&END_WHILE_"
process_while_string_3b: .asciz "\nBR_X16\n"
process_while_string_4: .asciz "# THEN_while_"
process_while_string_5: .asciz "ERROR in process_while\nMISSING )\n"
process_while_string_6a: .asciz "LOAD_W16_AHEAD\nSKIP_32_DATA\n&WHILE_"
process_while_string_6b: .asciz "\nBR_X16\n"
process_while_string_7: .asciz ":END_WHILE_"

process_for_string_0: .asciz "FOR_END_"
process_for_string_1: .asciz "# FOR_initialization_"
process_for_string_2: .asciz "ERROR in process_for\nMISSING (\n"
process_for_string_3: .asciz ":FOR_"
process_for_string_4: .asciz "ERROR in process_for\nMISSING //1\n"
process_for_string_5a: .asciz "CBNZ_X0_PAST_BR\nLOAD_W16_AHEAD\nSKIP_32_DATA\n&FOR_END_"
process_for_string_5b: .asciz  "\nBR_X16\n"
process_for_string_6a: .asciz "LOAD_W16_AHEAD\nSKIP_32_DATA\n&FOR_THEN_"
process_for_string_6b: .asciz  "\nBR_X16\n"
process_for_string_7: .asciz ":FOR_ITER_"
process_for_string_8: .asciz "ERROR in process_for\nMISSING //2\n"
process_for_string_9a: .asciz "LOAD_W16_AHEAD\nSKIP_32_DATA\n&FOR_"
process_for_string_9b: .asciz "\nBR_X16\n"
process_for_string_10: .asciz ":FOR_THEN_"
process_for_string_11: .asciz "ERROR in process_for\nMISSING )\n"
process_for_string_12a: .asciz "LOAD_W16_AHEAD\nSKIP_32_DATA\n&FOR_ITER_"
process_for_string_12b: .asciz "\nBR_X16\n"
process_for_string_13: .asciz ":FOR_END_"

process_break_string_0: .asciz "Not inside of a loop or case statement"
process_break_string_1: .asciz "POP_X1\t# break_cleanup_locals\n"
process_break_string_2a: .asciz "LOAD_W16_AHEAD\nSKIP_32_DATA\n&"
process_break_string_2b: .asciz "\nBR_X16"
process_break_string_3: .asciz "\n"
process_break_string_4: .asciz "ERROR in break statement\nMissing //\n"

expression_string_0: .asciz "STR_X0_[X1]\n"
expression_string_1: .asciz "STR_BYTE_W0_[X1]\n"

bitwise_expr_stub_string_0: .asciz "AND_X0_X1_X0\n"
bitwise_expr_stub_string_1: .asciz "OR_X0_X1_X0\n"
bitwise_expr_stub_string_2: .asciz "XOR_X0_X1_X0\n"

relational_expr_stub_string_0: .asciz "CMP_X1_X0\nSET_X0_TO_1\nSKIP_INST_LT\nSET_X0_TO_0\n"
relational_expr_stub_string_1: .asciz "CMP_X1_X0\nSET_X0_TO_1\nSKIP_INST_LE\nSET_X0_TO_0\n"
relational_expr_stub_string_2: .asciz "CMP_X1_X0\nSET_X0_TO_1\nSKIP_INST_GE\nSET_X0_TO_0\n"
relational_expr_stub_string_3: .asciz "CMP_X1_X0\nSET_X0_TO_1\nSKIP_INST_GT\nSET_X0_TO_0\n"
relational_expr_stub_string_4: .asciz "CMP_X1_X0\nSET_X0_TO_1\nSKIP_INST_EQ\nSET_X0_TO_0\n"
relational_expr_stub_string_5: .asciz "CMP_X1_X0\nSET_X0_TO_1\nSKIP_INST_NE\nSET_X0_TO_0\n"

additive_expr_stub_string_0: .asciz "ADD_X0_X1_X0\n"
additive_expr_stub_string_1: .asciz "SUB_X0_X1_X0\n"
additive_expr_stub_string_2: .asciz "MUL_X0_X1_X0\n"
additive_expr_stub_string_3: .asciz "SDIV_X0_X1_X0\n"
additive_expr_stub_string_4: .asciz "SDIV_X2_X1_X0\nMSUB_X0_X0_X2_X1\n"
additive_expr_stub_string_5: .asciz "LSHIFT_X0_X1_X0\n"
additive_expr_stub_string_6: .asciz "ARITH_RSHIFT_X0_X1_X0\n"

unary_expr_sizeof_string_0: .asciz "ERROR in unary_expr\nMissing (\n"
unary_expr_sizeof_string_1: .asciz "ERROR in unary_expr\nMissing )\n"
unary_expr_sizeof_string_2: .asciz "LOAD_W0_AHEAD\nSKIP_32_DATA\n%"
unary_expr_sizeof_string_3: .byte 10, 0

postfix_expr_array_string_0: .asciz "DEREF_X0\n"
postfix_expr_array_string_1: .asciz "DEREF_X0_BYTE\n"
postfix_expr_array_string_2: .asciz "LOAD_W2_AHEAD\nSKIP_32_DATA\n%"
postfix_expr_array_string_3: .asciz "\nLSHIFT_X0_X0_X2\n"
postfix_expr_array_string_4: .asciz "ADD_X0_X1_X0\n"
postfix_expr_array_string_5: .asciz "ERROR in postfix_expr\nMissing ]\n"
postfix_expr_array_string_6: .byte 0

postfix_expr_arrow_string_0: .asciz "# looking up offset\n"
postfix_expr_arrow_string_1: .asciz "# -> offset calculation\nLOAD_W1_AHEAD\nSKIP_32_DATA\n%"
postfix_expr_arrow_string_2: .asciz "\nADD_X0_X1_X0\n"
postfix_expr_arrow_string_3: .asciz "DEREF_X0\n"

primary_expr_string_0: .asciz "SET_X0_TO_0\n"
primary_expr_string_1: .asciz "SUB_X0_X1_X0\n"
primary_expr_string_2: .asciz "SET_X0_TO_1\n"
primary_expr_string_3: .asciz "XOR_X0_X1_X0\n"
primary_expr_string_4: .asciz "MVN_X0\n"
primary_expr_string_5: .asciz "Error in Primary expression\nDidn't get )\n"
primary_expr_string_6: .asciz "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_"
primary_expr_string_7: .asciz "0123456789"

primary_expr_variable_string_0: .asciz " is not a defined symbol\n"
primary_expr_variable_string_1: .asciz "\n"
primary_expr_variable_string_2: .asciz "LOAD_W0_AHEAD\nSKIP_32_DATA\n%"

function_call_string_0: .asciz "ERROR in process_expression_list\nNo ( was found\n"
function_call_string_1: .asciz "PUSH_X16\t# Protect a tmp register we're going to use\n"
function_call_string_2: .asciz "PUSH_LR\t# Protect the old return pointer (link)\n"
function_call_string_3a: .asciz "PUSH_BP\t# Protect the old base pointer\n"
function_call_string_3b: .asciz "SET_X16_FROM_SP\t# The base pointer to-be\n"
function_call_string_4: .asciz "PUSH_X0\t#_process_expression1\n"
function_call_string_5: .asciz "PUSH_X0\t#_process_expression2\n"
function_call_string_6: .asciz "ERROR in process_expression_list\nNo ) was found\n"
function_call_string_7a: .asciz "SET_X0_FROM_BP\n"
function_call_string_7b: .asciz "LOAD_W1_AHEAD\nSKIP_32_DATA\n%"
function_call_string_8: .asciz "\nSUB_X0_X0_X1\n"
function_call_string_9: .asciz "DEREF_X0\n"
function_call_string_10a: .asciz "SET_BP_FROM_X16\n"
function_call_string_10b: .asciz "SET_X16_FROM_X0\n"
function_call_string_10c: .asciz "BLR_X16\n"
function_call_string_11: .asciz "LOAD_W16_AHEAD\nSKIP_32_DATA\n&FUNCTION_"
function_call_string_12a: .asciz "\n"
function_call_string_12b: .asciz "BLR_X16\n"
function_call_string_13: .asciz "POP_X1\t# _process_expression_locals\n"
function_call_string_14: .asciz "POP_BP\t# Restore the old base pointer\n"
function_call_string_15: .asciz "POP_LR\t# Restore the old return pointer (link)\n"
function_call_string_16: .asciz "POP_X16\t# Restore a register we used as tmp\n"

variable_load_string_0: .asciz "SET_X0_FROM_BP\nLOAD_W1_AHEAD\nSKIP_32_DATA\n%"
variable_load_string_1: .asciz "\nSUB_X0_X0_X1\n\n"
variable_load_string_2: .asciz "DEREF_X0\n"

function_load_string_0: .asciz "LOAD_W0_AHEAD\nSKIP_32_DATA\n&FUNCTION_"
function_load_string_1: .byte 10, 0

global_load_string_0: .asciz "LOAD_W0_AHEAD\nSKIP_32_DATA\n&GLOBAL_"
global_load_string_1: .asciz "\n"
global_load_string_2: .asciz "DEREF_X0\n"

primary_expr_number_string_0: .asciz "LOAD_W0_AHEAD\nSKIP_32_DATA\n%"
primary_expr_number_string_1: .byte 10, 0

primary_expr_string_string_0: .asciz "LOAD_W0_AHEAD\nSKIP_32_DATA\n&STRING_"
primary_expr_string_string_1: .asciz ":STRING_"

primary_expr_char_string_0: .asciz "LOAD_W0_AHEAD\nSKIP_32_DATA\n%"
primary_expr_char_string_1: .asciz "\n"

primary_expr_failure_string_0: .asciz "Received "
primary_expr_failure_string_1: .asciz " in primary_expr\n"

common_recursion_string_0: .asciz "PUSH_X0\t#_common_recursion\n"
common_recursion_string_1: .asciz "POP_X1\t# _common_recursion\n"

uniqueID_string_0: .byte 10, 0

escape_lookup_string_0: .asciz "Unknown escape received: "
escape_lookup_string_1: .asciz " Unable to process\n"

char2hex_string_0: .asciz "Tried to print non-hex number\n"

weird_string_0: .asciz "\t\n !#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
weird_string_1: .byte 9, 10, 13, 32, 0

type_name_string_0: .asciz "Unknown type "
type_name_string_1: .byte 10, 0

create_struct_string_0: .asciz "ERROR in create_struct\n Missing {\n"
create_struct_string_1: .asciz "ERROR in create_struct\n Missing //\n"

lookup_member_string_0: .asciz "ERROR in lookup_member "
lookup_member_string_1: .asciz " does not exist\n"
lookup_member_string_2: .byte 10, 0

build_member_string_0: .asciz "Struct only supports [num] form\n"

build_union_string_0: .asciz "ERROR in build_union\nMissing {\n"
build_union_string_1: .asciz "ERROR in build_union\nMissing //\n"

debug_list_string0: .asciz "Token_list node at address: "
debug_list_string1: .asciz "\nNEXT address: "
debug_list_string2: .asciz "\nPREV address: "
debug_list_string3: .asciz "\nS address: "
debug_list_string4: .asciz "\nThe contents of S are: "
debug_list_string5: .asciz "\nTYPE address: "
debug_list_string6: .asciz "\nARGUMENTS address: "
debug_list_string_null: .asciz ">::<NULL>::<"
