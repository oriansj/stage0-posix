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
	// X0, X8, RSI, RDI => Temps
	// X12 => MALLOC
	// X13 => HEAD
	// X14 => Output_file
	// X15 => Input_file

	// Struct format: (size 32)
	// NEXT => 0
	// TYPE => 8
	// TEXT => 16
	// EXPRESSION => 24

	// Types
	// None => 0
	// MACRO => 1
	// STRING => 2

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
    mov x3, #384                // Prepare file as RWX for owner only (600 in octal)
    mov x8, #56                 // The syscall number for openat(), aarch64 has no open()
    svc #0                      // Open file!
    cmp x0, #0                  // Check for missing output
    b.gt _start_out             // Have real output
    mov x0, #1                  // Use stdout

_start_out:
    mov x14, x0                 // Preserve the file pointer we were given
    mov x8, #214                // the Syscall # for SYS_BRK
    mov x0, 0                   // Get current brk
    svc 0                       // Let the kernel do the work
    mov x12, x0                 // Set our malloc pointer

    bl Tokenize_Line            // Get all lines
    mov x0, x13                 // prepare for Reverse_List
    bl Reverse_List             // Correct order
    mov x13, x0                 // Update HEAD
    bl Identify_Macros          // Find the DEFINEs
    bl Line_Macro               // Apply the DEFINEs
    bl Process_String           // Handle strings
    bl Eval_Immediates          // Handle Numbers
    bl Preserve_Other           // Collect the remaining
    bl Print_Hex                // Output our results

Done:
    // program completed Successfully
    mov x0, 0                   // All is well
    mov x8, #93                 // put the exit syscall number in eax
    svc 0                       // Call it a good day


// Tokenize_Line Function
// Using input file X15 and Head X13
// Creates a linked list of structs
// Uses X1 for in_set strings, X2 for Int C and X3 for Struct Token* p
Tokenize_Line:
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    push x30
restart:
    bl fgetc                    // Read a char
    cmp x0, -4                  // Check for EOF
    b.eq done                   // File is collected

    and x0, x0, 0xff            // We have to zero extend it to use it
    mov x2, x0                  // Protect C

    adr x1, comments            // Get pointer to "#;"
    bl In_Set                   // Check for comments
    cmp x0, 1                   // If comments
    b.eq Purge_LineComment      // try again

    mov x0, x2                  // put C in place for check
    adr x1, terminators         // Get pointer to "\n\t "
    bl In_Set                   // Check for terminators
    cmp x0, 1                   // If terminator
    b.eq restart                // try again

    mov x0, 32                  // Malloc the struct P
    bl malloc                   // Get pointer to P
    mov x3, x0                  // Protect P
    str x13, [x3]               // P->NEXT = HEAD
    mov x13, x3                 // HEAD = P

    mov x0, x2                  // put C in place for check
    adr x1, string_char         // Get pointer to "\"'"
    bl In_Set                   // Check for string chars
    cmp x0, 1                   // If string char
    b.eq Store_String           // Get string

    bl Store_Atom               // Get whole token
    b restart

done:
    pop x30
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
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
    pop x2
    pop x1
    ret


// Malloc isn't actually required if the program being built fits in the initial memory
// However, it doesn't take much to add it.
// Requires X12 to be initialized and X0 to have the number of desired bytes
malloc:
    push x1
    add x0, x0, x12             // Request the number of desired bytes
    mov x8, #214                // the Syscall # for SYS_BRK
    svc 0                       // call the Kernel

    mov x1, x12                 // save return pointer
    mov x12, x0                 // Update pointer
    mov x0, x1                  // Return pointer
    pop x1
    ret


// Purge_LineComment function
// Reads chars until LF and jumps to restart
Purge_LineComment:
    bl fgetc                    // Get a char
    and x0, x0, 0xff            // Zero extend
    cmp x0, 10                  // While not LF
    b.ne Purge_LineComment      // Keep reading
    b restart


// Store_String Function
// Receives C in X2, HEAD in X3 and Input file in X14
// Uses X1 for terminator, X2 for C and X3 for string
Store_String:
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3

    mov x0, 2                   // Using TYPE STRING
    str x0, [x3, 8]             // HEAD->TYPE = STRING
    mov x0, 512                 // Malloc the string
    bl malloc                   // Get pointer to P
    str x0, [x3,16]             // HEAD->TEXT = STRING
    mov x1, x2                  // Protect terminator
    mov x3, x0                  // Protect string pointer
Store_String_Loop:
    strb w2, [x3], 1
    bl fgetc                    // read next char
    and x0, x0, 0xff            // Zero extend it
    mov x2, x0                  // Update C
    cmp x2, x1                  // See if we hit terminator
    b.ne Store_String_Loop      // Otherwise keep looping

    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    mov x0, x3                  // return HEAD
    b restart


// Store_Atom Function
// Receives C in X2, HEAD in X3 and Input file in X15
// Uses X1 for in_set strings, X2 for C and X3 for string
Store_Atom:
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    push x30

    mov x0, 256                 // Malloc the string
    bl malloc                   // Get pointer to P
    str x0, [x3,16]             // HEAD->TEXT = STRING
    adr x1, terminators         // Get pointer to "\n\t "
    mov x3, x0                  // Protect string pointer
Store_Atom_loop:
    strb w2, [x3], 1            // write byte
    bl fgetc                    // read next char
    and x0, x0, 0xff            // Zero extend it
    mov x2, x0                  // Update C
    bl In_Set                   // Check for terminators
    cmp x0, 0                   // Check for "\n\t "
    b.eq Store_Atom_loop        // Loop otherwise

    pop x30
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    mov x0, x3                  // return HEAD
    ret


// In_Set function
// Receives Char C in X0 and CHAR* in X1
// Returns 1 if true, zero if false in X0
In_Set:
    push x1                     // Protect X1
    push x2                     // Protect X2
In_Set_loop:
    ldrb w2, [x1], 1            // Read char

    cmp x0, x2                  // See if they match
    b.eq In_Set_True            // return true

    cmp x2, 0                   // Check for NULL
    b.eq In_Set_False           // return false

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

// Char sets
terminators:
    .byte 10, 9, 32, 0

comments:
    .byte 35, 59, 0

string_char:
    .byte 34, 39, 0

.p2align 2

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


// Identify_Macros function
// Receives List in X0
// Updates the list in place// does not modify registers
// Uses X1 for DEFINE, X2 for I
Identify_Macros:
    push x0                     // Protect X0
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    push x30

    adr x1, DEFINE_str          // Setup define string
    mov x2, x0                  // I = HEAD
Identify_Macros_Loop:
    ldr x0, [x2,16]             // I->TEXT
    bl match                    // IF "DEFINE" == I->TEXT
    cmp x0, 0                   // Check if match
    b.ne Identify_Macros_Next   // Skip the work

    // Deal with MACRO
    mov x0, 1                   // Using MACRO
    str x0, [x2, 8]             // I->TYPE = MACRO

    ldr x0, [x2]                // I->NEXT
    ldr x0, [x0,16]             // I->NEXT->TEXT
    str x0, [x2,16]             // I->TEXT = I->NEXT->TEXT

    ldr x0, [x2]                // I->NEXT
    ldr x0, [x0]                // I->NEXT->NEXT
    ldr x0, [x0,16]             // I->NEXT->NEXT->TEXT
    str x0, [x2,24]             // I->EXPRESSION = I->NEXT->NEXT->TEXT

    ldr x0, [x2]                // I->NEXT
    ldr x0, [x0]                // I->NEXT->NEXT
    ldr x0, [x0]                // I->NEXT->NEXT->NEXT
    str x0, [x2]                // I->NEXT = I->NEXT->NEXT->NEXT

Identify_Macros_Next:
    ldr x2, [x2]                // I = I->NEXT
    cmp x2, 0                   // Check for NULL
    b.ne Identify_Macros_Loop   // Keep looping otherwise

    pop x30
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x0                      // Restore X0
    ret

DEFINE_str:
    .byte 68, 69, 70, 73, 78, 69, 0

.p2align 2

// match function
// Receives CHAR* in X0 and CHAR* in X1
// Returns 0 (TRUE) or 1 (FALSE) in X0
match:
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    push x30

    mov x2, x0                  // S1 in place
    mov x3, x1                  // S2 in place
match_Loop:
    ldrb w0, [x2], 1            // S1[0]
    ldrb w1, [x3], 1            // S2[0]
    cmp x0, x1                  // See if they match
    b.ne match_False            // If not

    cmp x0, 0                   // If reached end of string
    b.eq match_Done             // Perfect match
    b match_Loop                // Otherwise keep looping

match_False:
    mov x0, 1                   // Return false
match_Done:
    pop x30
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    ret


// Line_Macro function
// Receives List in X0
// Updates the list in place// does not modify registers
// Uses X0 for I, X1 for I->TEXT, X2 for I->EXPRESSION
Line_Macro:
    push x0                     // Protect X0
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    push x30
Line_Macro_Loop:
    ldr x1, [x0,8]              // I->TYPE
    cmp x1, 1                   // IF MACRO == I->TYPE
    b.ne Line_Macro_Next        // Otherwise move on

    // Is a macro apply
    ldr x1, [x0,16]             // I->TEXT
    ldr x2, [x0,24]             // I->EXPRESSION
    ldr x0, [x0]                // I->NEXT
    bl Set_Expression           // Apply it
    b Line_Macro_Loop           // Move on to next

Line_Macro_Next:
    ldr x0, [x0]                // I->NEXT
    cmp x0, 0                   // Check for NULL
    b.ne Line_Macro_Loop        // Keep going

    pop x30
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x0                      // Restore X0
    ret


// Set_Expression function
// Receives List in X0, CHAR* in X1 and CHAR* in X2
// Updates the list in place// does not modify registers
// Uses X1 for C, X2 for EXP and X3 for I
Set_Expression:
    push x0                     // Protect X0
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    push x30
    mov x3, x0                  // Set I
Set_Expression_Loop:
    ldr x0, [x3,8]              // I->TYPE
    cmp x0, 1                   // IF MACRO == I->TYPE
    b.eq Set_Expression_Next    // Ignore and move on

    ldr x0, [x3,16]             // I->TEXT
    bl match                    // Check for match
    cmp x0, 0                   // If match
    b.ne Set_Expression_Next    // Otherwise next

    // We have a non-macro match
    str x2, [x3, 24]            // I->EXPRESSION = EXP

Set_Expression_Next:
    ldr x3, [x3]                // I = I->NEXT
    cmp x3, 0                   // IF NULL == I
    b.ne Set_Expression_Loop    // Otherwise keep looping

    pop x30
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x0                      // Restore X0
    ret


// Process_String function
// Receives List in X0
// Update the list in place; does not modify registers
// Uses X1 for I->TEXT, X2 for I and X3 for S
Process_String:
    push x0                    // Protect X0
    push x1                    // Protect X1
    push x2                    // Protect X2
    push x3                    // Protect X3
    push x30

    mov x2, x0                  // I = HEAD
Process_String_loop:
    ldr x0, [x2,8]              // I->TYPE
    cmp x0, 2                   // IF STRING == I->TYPE
    b.ne Process_String_Next    // Skip to next

    ldr x1, [x2,16]             // I->TEXT
    ldrb w0, [x1]               // I->TEXT[0]
    cmp x0, 39                  // IF '\'' == I->TEXT[0]
    b.ne Process_String_Raw     // Deal with '"'

    // Deal with '\''
    add x1, x1, 1               // I->TEXT + 1
    str x1, [x2, 24]            // I->EXPRESSION = I->TEXT + 1
    b Process_String_Next       // Move on to next

Process_String_Raw:
    mov x0, x1                  // Get length of I->TEXT
    bl string_length            // Do it
    lsr x0, x0, 2               // LENGTH = LENGTH >> 2
    add x0, x0, 1               // LENGTH = LENGTH + 1
    lsl x0, x0, 3               // LENGTH = LENGTH << 3
    bl malloc                   // Get string
    mov x3, x1                  // S = I->TEXT
    add x3, x3, 1               // S = S + 1
    str x0, [x2, 24]            // I->EXPRESSION = hexify
    mov x1, x0                  // Put hexify buffer in x1

Process_String_Raw_Loop:
    ldrb w0, [x3], 1            // Read 1 chars
    push x0
    bl hex8                     // write them all
    pop x0
    cmp x0, 0                   // Check for NULL
    b.ne Process_String_Raw_Loop    // Keep looping

Process_String_Next:
    ldr x2, [x2]                // I = I->NEXT
    cmp x2, 0                   // IF NULL == I
    b.ne Process_String_loop    // Otherwise keep looping

    pop x30
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x0                      // Restore X0
    ret


// string_length function
// Receives CHAR* in X0
// Returns INT in X0
// Uses X0 for CH, X1 for S and X2 for INDEX
string_length:
    push x1                     // Protect X1
    push x2                     // Protect X2
    mov x1, x0                  // Set S
    mov x2, 0                   // INDEX = 0
string_length_loop:
    ldrb w0, [x1,x2]            // S[INDEX]
    cmp x0, 0                   // IF NULL == S[INDEX]
    b.eq string_length_done     // Stop

    add x2, x2, 1               // INDEX = INDEX + 1
    b string_length_loop        // Keep going

string_length_done:
    mov x0, x2                  // RETURN INDEX
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    ret


// Eval_Immediates function
// Receives List in X0
// Updates the list in place; does not modify registers
// Uses X1 for I->TEXT[0], X2 for I->TEXT[1] and X3 for I
Eval_Immediates:
    push x0                     // Protect X0
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    push x30
    mov x3, x0                  // I = HEAD
Eval_Immediates_Loop:
    // Check for MACRO
    ldr x0, [x3,8]              // I->TYPE
    cmp x0, 1                   // IF MACRO == I-TYPE
    b.eq Eval_Immediates_Next   // Skip to next

    // Check for NULL EXPRESSION
    ldr x0, [x3,24]             // I->EXPRESSION
    cmp x0, 0                   // IF NULL == I->EXPRESSION
    b.ne Eval_Immediates_Next   // Skip to next

    // Check if number
    ldr x0, [x3,16]             // I->TEXT
    ldrb w1, [x0], 1            // I->TEXT[0]
    ldrb w2, [x0]               // I->TEXT[1]
    bl numerate_string          // Convert string to INT
    cmp x0, 0                   // IF 0 == numerate_number(I->TEXT + 1)
    b.ne Eval_Immediates_value  // Has a value

    // Last chance for Immediate
    cmp x2, 48                  // If '0' == I->TEXT[1]
    b.ne Eval_Immediates_Next   // Skip to next

Eval_Immediates_value:
    bl express_number           // Convert value to hex string
    str x0, [x3, 24]            // I->EXPRESSION = express_number(value, I-TEXT[0])

Eval_Immediates_Next:
    ldr x3, [x3]                // I = I->NEXT
    cmp x3, 0                   // IF NULL == I
    b.ne Eval_Immediates_Loop   // Otherwise keep looping

    pop x30
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x0                      // Restore X0
    ret


// numerate_string function
// Receives CHAR* in X0
// Returns value of CHAR* in X0
// Uses X0 for VALUE, X1 for S, X2 for CH and X4 for NEGATIVE?
numerate_string:
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    push x4
    mov x1, x0                  // put S in correct place
    mov x0, 0                   // Initialize to Zero
numerate_string_loop:
    ldrb w2, [x1,1]             // S[1]
    cmp x2, 120                 // IF 'x' == S[1]
    b.eq numerate_hex           // Deal with hex input

    // Assume decimal input
    mov x4, 0                   // Assume no negation
    ldrb w2, [x1]               // S[0]
    cmp x2, 45                  // IF '-' == S[0]
    b.ne numerate_decimal       // Skip negation

    mov x4, 1                   // Set FLAG
    add x1, x1, 1               // S = S + 1

numerate_decimal:
    ldrb w2, [x1]               // S[0]
    cmp x2, 0                   // IF NULL == S[0]
    b.eq numerate_decimal_done  // We are done

    push x1
    mov x1, 10
    mul x0, x0, x1              // VALUE = VALUE * 10
    pop x1

    sub x2, x2, 48              // CH = CH - '0'
    cmp x2, 9                   // Check for illegal
    b.gt numerate_string_fail   // If CH > '9'
    cmp x2, 0                   // Check for illegal
    b.lt numerate_string_fail   // IF CH < 0
    add x0, x0, x2              // VALUE = VALUE + CH
    add x1, x1, 1               // S = S + 1
    b numerate_decimal          // Keep looping

numerate_decimal_done:
    cmp x4, 1                   // Check if need to negate
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
    pop x4                      // Restore X4
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    ret


// express_number function
// Receives INT in X0 and CHAR in X1
// Allocates a string and expresses the value in hex
// Returns string in X0
// Uses X0 for VALUE, X1 for S and X2 for CH
express_number:
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
    push x30

    mov x2, x1                  // Put CH in right place
    mov x1, x0                  // Protect VALUE
    cmp x2, 37                  // IF '%' == CH
    b.ne express_number2        // Otherwise try @

    mov x0, 9                   // We need 9bytes
    bl malloc                   // Get S pointer
    mov x3, x0                  // Put S and VALUE in place
    mov x0, x1
    mov x1, x3
    push x1                     // Protect S
    bl hex32l                   // Store 32bits
    b express_number_done       // done

express_number2:
    cmp x2, 64                  // IF '@' == CH
    b.ne express_number1        // Othrewise try !

    mov x0, 5                   // We need 5bytes
    bl malloc                   // Get S pointer
    mov x3, x0                  // Put S and VALUE in place
    mov x0, x1
    mov x1, x3
    push x1                     // Protect S
    bl hex16l                   // Store 16bits
    b express_number_done       // done

express_number1:
    mov x0, 3                   // We need 3bytes
    bl malloc                   // Get S pointer
    mov x3, x0                  // Put S and VALUE in place
    mov x0, x1
    mov x1, x3
    push x1                     // Protect S
    bl hex8                     // Store 8bit

express_number_done:
    pop x0                      // Restore S
    pop x30
    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    ret


// HEX to ascii routine
// Receives INT in X0 and CHAR* in X1
// Stores ascii of INT in CHAR*
// Returns only modifying X0
hex64l:
    push x30
    push x0                     // Protect top 32
    bl hex32l                   // Store it
    pop x0                      // do top 32
    lsr x0, x0, 32              // do bottom 32 first
    bl hex32l
    pop x30
    ret

hex32l:
    push x30
    push x0                     // Protect top 16
    bl hex16l                   // Store it
    pop x0                      // do top 16
    lsr x0, x0, 16              // do bottom 16 first
    bl hex16l
    pop x30
    ret

hex16l:
    push x30
    push x0                     // Protect top byte
    bl hex8                     // Store it
    pop x0                      // do high byte
    lsr x0, x0, 8               // do bottom byte first
    bl hex8
    pop x30
    ret

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
    add x0, x0, '0'             // convert to ascii
    cmp x0,'9'                  // valid digit?
    b.le hex1                   // yes
    add x0, x0, 7               // use alpha range
hex1:
    strb w0, [x1], 1            // store result
    ret


// Preserve_Other function
// Receives List in X0
// Updates the list in place; does not modify registers
// Uses X0 for I, X1 for I->TEXT
Preserve_Other:
    push x0                     // Protect X0
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x3                     // Protect X3
Preserve_Other_Loop:
    ldr x1, [x0,24]             // I->EXPRESSION
    cmp x1, 0                   // IF NULL == I->EXPRESSION
    b.ne Preserve_Other_Next    // Otherwise next

    // Needs preserving
    ldr x1, [x0,16]             // I->TEXT
    str x1, [x0,24]             // I->EXPRESSION = I->TEXT

Preserve_Other_Next:
    ldr x0, [x0]                // I = I->NEXT
    cmp x0, 0                   // IF NULL == I
    b.ne Preserve_Other_Loop    // Otherwise keep looping

    pop x3                      // Restore X3
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    pop x0                      // Restore X0
    ret


// Print_Hex function
// Receives list in X0
// walks the list and prints the I->EXPRESSION for all nodes followed by newline
// Uses X1 for I
Print_Hex:
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x30
    mov x1, x13                 // I = Head
Print_Hex_Loop:
    ldr x0, [x1,8]              // I->TYPE
    cmp x0, 1                   // IF MACRO == I->TYPE
    b.eq Print_Hex_Next         // Skip

    ldr x0, [x1,24]             // Using EXPRESSION
    bl File_Print               // Print it
    mov x0, 10                  // NEWLINE
    bl fputc                    // Append it

Print_Hex_Next:
    ldr x1, [x1]                // Iterate to next Token
    cmp x1, 0                   // Check for NULL
    b.ne Print_Hex_Loop         // Otherwise keep looping

    pop x30
    pop x2                      // Restore X2
    pop x1                      // Restore X1
    ret


// File_Print function
// Receives CHAR* in X0
// calls fputc for every non-null char
File_Print:
    push x1                     // Protect X1
    push x2                     // Protect X2
    push x30
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
    pop x30
    pop x2                      // Restore X2
    pop x1                      // Restore X1
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
    pop x2                      // Restore X3
    pop x1
    ret
