;; Copyright (C) 2020 Jeremiah Orians
;; This file is part of stage0.
;;
;; stage0 is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; stage0 is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with stage0.  If not, see <http://www.gnu.org/licenses/>.

	section .text
	global _start

; Where the ELF Header is going to hit
; Simply jump to _start
; Our main function
_start:
	pop rax                     ; Get the number of arguments
	pop rdi                     ; Get the program name
	pop rdi                     ; Get the actual input name
	cmp rdi, 0                  ; Check for missing output
	jne _start_out              ; Have real input
	push rax                    ; Need to adjust stack
	mov rdi, default_file       ; Use "kaem.run"

_start_out:
	mov rsi, 0                  ; prepare read_only
	mov rax, 2                  ; the syscall number for open()
	syscall                     ; Now open that damn file

	cmp rax, 0                  ; IF NULL We couldn't open the file
	jle Exit_Failure            ; Abort hard
	mov [script], rax           ; Set input pointer

	pop rax                     ; Get start of envp
	mov rbp, rsp                ; Protect envp

	mov rax, 12                 ; the Syscall # for SYS_BRK
	mov rdi, 0                  ; Get current brk
	syscall                     ; Let the kernel do the work
	mov [MALLOC], rax           ; Set our malloc pointer

	;; Where the main work gets done
	;; Using RDI for tokens and RSI for tokens[i]
main_loop:
	mov rax, [max_args]         ; Using 256 char* of space
	call malloc                 ; get it
	mov rdi, rax                ; set tokens

	mov rsi, rdi                ; I = 0
	mov rax, 0                  ; Using 0
	mov [status], rax           ; status = 0
	mov [command_done], rax     ; command_done = 0

	;; Using RAX for result and RDI for tokens[i]
collect_command:
	call collect_token          ; Get another token
	cmp rax, 0                  ; if NULL == result
	je collect_command_comment  ; It is a comment, don't store

	mov [rsi], rax              ; tokens[i] = result
	add rsi, 8                  ; i = i + 1 (adjusted for char* size)

collect_command_comment:
	mov rax, [command_done]     ; Using command_done
	cmp rax, 0                  ; IF 0 == command_done
	je collect_command          ; keep looping

	;; Deal with line comments
	cmp rsi, rdi                ; if 0 < i
	je main_loop                ; It was a comment

	call print_command          ; print the command
	mov rax, [rdi]              ; program = tokens[0]
	cmp rax, 0                  ; IF NULL == program
	je Exit_Failure             ; Some shit went down, abort

	push rdi                    ; Protect Tokens
	mov rax, 57                 ; FORKing
	syscall                     ; int f = FORK()
	pop rdi                     ; Restore Tokens

	cmp rax, 0                  ; Check fork
	jl Exit_Failure             ; IF f == -1 abort hard
	jne collect_command_parent  ; IF f == 0 it is child

	;; Deal with child case
	mov rax, 59                 ; EXECVE
	mov rdx, rbp                ; third arg = envp
	mov rsi, rdi                ; second arg = tokens
	mov rdi, [rdi]              ; program = tokens[0]
	syscall                     ; execve(program, tokens, envp);
	jmp Exit_Failure            ; return error

collect_command_parent:
	mov rdi, rax                ; first arg = f
	mov rsi, status             ; second arg = &status
	mov rdx, 0                  ; third arg = NULL
	mov rax, 61                 ; WAITPID
	syscall                     ; wait4pid(f, &status, 0, 0); [r10 = 0]

	mov rax, [status]           ; Using status
	cmp rax, 0                  ; IF 0 == status
	je main_loop                ; Loop forever

	;; Deal with very unhappy case
	mov rax, hard               ; Using "Subprocess error\nABORTING HARD\n"
	call File_Print             ; Print it

;; Exit_Failure function
;; Receives nothing
;; And aborts hard
;; DOES NOT RETURN
Exit_Failure:
	mov rdi, 1                  ; All is wrong
	mov rax, 60                 ; put the exit syscall number in rax
	syscall                     ; Call it a bad day


;; print_command function
;; Recieves tokens[j] in RDI and tokens[i] in RSI
;; Modifies RAX
print_command:
	push rdi                    ; Protect RDI
	mov rax, prefix             ; using " +> "
	call File_Print             ; print it
print_command_loop:
	mov rax, [rdi]              ; using tokens[j]
	call File_Print             ; print it
	add rdi, 8                  ; j = j + 1
	mov rax, 32                 ; using ' '
	call fputc                  ; print it
	cmp rdi, rsi                ; IF j < i
	jne print_command_loop      ; otherwise keep looping

	mov rax, 10                 ; using '\n'
	call fputc                  ; print it
	pop rdi                     ; Restore RDI
	ret


;; collect_token function
;; Recieves nothing
;; Overwrites RAX
;; Uses RAX as C, RDI as token and RSI as token[i]
collect_token:
	push rdi                    ; Protect RDI
	push rsi                    ; Protect RSI
	mov rax, [max_string]       ; Using max_string
	call malloc                 ; allocate space
	mov rdi, rax                ; token = malloc(max_string);
	mov rsi, rax                ; i = 0; set token[i]

collect_token_loop:
	call fgetc                  ; c = fgetc(input);
	cmp rax, -4                 ; if C == EOF
	je Done                     ; We are done

	cmp rax, 32                 ; IF C == ' '
	je collect_token_done       ; Space terminates token

	cmp rax, 9                  ; IF C == '\t'
	je collect_token_done       ; tab terminates token

	cmp rax, 10                 ; IF C == '\n'
	jne collect_token_string    ; otherwise check next

	;; It is a newline
	mov rax, 1                  ; Using 1
	mov [command_done], rax     ; Set command_done = TRUE
	jmp collect_token_done      ; Be done

collect_token_string:
	cmp rax, 34                 ; IF C == '"'
	jne collect_token_comment   ; otherwise check next

	;; It is a RAW STRING
	call collect_string         ; Get the rest of the string
	jmp collect_token_done      ; Be done

collect_token_comment:
	cmp rax, 35                 ; IF C == '#'
	jne collect_token_escape    ; otherwise check next

	;; It is a line comment
	call collect_comment        ; Read it all
	mov rax, 1                  ; Using 1
	mov [command_done], rax     ; Set command_done = TRUE
	jmp collect_token_done      ; Be done

collect_token_escape:
	cmp rax, 92                 ; IF C == '\\'
	jne collect_token_other     ; otherwise just store it

	;; It is an escape char
	call fgetc                  ; Read the char to drop
	jmp collect_token_done      ; Be done

collect_token_other:
	mov [rsi], al               ; token[i] = C
	add rsi, 1                  ; i = i + 1
	jmp collect_token_loop      ; Keep going

collect_token_done:
	cmp rdi, rsi                ; IF i == 0
	jne collect_token_good      ; otherwise return the token
	mov rdi, 0                  ; token = NULL

collect_token_good:
	mov rax, rdi                ; Return token
	pop rsi                     ; Restore RSI
	pop rdi                     ; Restore RDI
	ret


;; collect_string function
;; Recieves target[index] in RSI
;; Modifies RAX
;; Uses RAX as C
collect_string:
	call fgetc                  ; C = fgetc(input)
	cmp rax, -4                 ; if C == EOF
	je Exit_Failure             ; Something went horriably wrong

	cmp rax, 34                 ; IF C == '"'
	je collect_string_done      ; be done

	;; deal with inside of string
	mov [rsi], al               ; target[index] = C
	add rsi, 1                  ; index = index + 1
	jmp collect_string          ; Keep going

collect_string_done:
	ret


;; collect_comment function
;; Recieves nothing
;; Modifies RAX
;; uses RAX as Int C
;; Just throws away everything it reads
collect_comment:
	call fgetc                  ; C = fgetc(input)
	cmp rax, -4                 ; IF C == EOF
	je Exit_Failure             ; abort hard

	cmp rax, 10                 ; IF C == '\n'
	jne collect_comment         ; otherwise keep looping
	ret


;; Malloc isn't actually required if the program being built fits in the initial memory
;; However, it doesn't take much to add it.
;; Requires [MALLOC] to be initialized and RAX to have the number of desired bytes
malloc:
	push rdi                    ; Protect RDI
	push rsi                    ; Protect RSI
	push rdx                    ; Protect RDX
	mov rdi, [MALLOC]           ; Using the current pointer
	add rdi, rax                ; Request the number of desired bytes
	mov rax, 12                 ; the Syscall # for SYS_BRK
	syscall                     ; call the Kernel
	mov rax, [MALLOC]           ; Return pointer
	mov [MALLOC], rdi           ; Update pointer
	pop rdx                     ; Restore RDX
	pop rsi                     ; Restore RSI
	pop rdi                     ; Restore RDI
	ret


;; fgetc function
;; Loads FILE* from [script]
;; Returns -4 (EOF) or char in RAX
fgetc:
	push rdi                    ; Protect RDI
	push rsi                    ; Protect RSI
	push rdx                    ; Protect RDX
	mov rax, -4                 ; Put EOF in rax
	push rax                    ; Assume bad (If nothing read, value will remain EOF)
	lea rsi, [rsp]              ; Get stack address
	mov rdi, [script]           ; Where are we reading from
	mov rax, 0                  ; the syscall number for read
	mov rdx, 1                  ; set the size of chars we want
	syscall                     ; call the Kernel
	pop rax                     ; Get either char or EOF
	cmp rax, -4                 ; Check for EOF
	je fgetc_done               ; Return as is
	movzx rax, al               ; Make it useful
fgetc_done:
	pop rdx                     ; Restore RDX
	pop rsi                     ; Restore RSI
	pop rdi                     ; Restore RDI
	ret


;; File_Print function
;; Receives CHAR* in RAX
;; calls fputc for every non-null char
File_Print:
	push rdi                    ; Protect RDI
	push rsi                    ; Protect RSI
	mov rdi, rax                ; Protect S
	cmp rax, 0                  ; Protect against nulls
	je File_Print_Done          ; Simply don't try to print them
File_Print_Loop:
	mov al, [rdi]               ; Read byte
	movzx rax, al               ; zero extend
	cmp rax, 0                  ; Check for NULL
	je File_Print_Done          ; Stop at NULL

	call fputc                  ; write it
	add rdi, 1                  ; S = S + 1
	jmp File_Print_Loop         ; Keep going

File_Print_Done:
	pop rsi                     ; Restore RSI
	pop rdi                     ; Restore RDI
	ret


;; fputc function
;; receives CHAR in RAX and load FILE* from stdout
;; writes char and returns
fputc:
	push rdi                    ; Protect RDI
	push rsi                    ; Protect RSI
	push rdx                    ; Protect RDX
	push rax                    ; We are writing rax
	lea rsi, [rsp]              ; Get stack address
	mov rdi, 1                  ; Write to target file
	mov rax, 1                  ; the syscall number for write
	mov rdx, 1                  ; set the size of chars we want
	syscall                     ; call the Kernel
	pop rax                     ; Restore stack
	pop rdx                     ; Restore RDX
	pop rsi                     ; Restore RSI
	pop rdi                     ; Restore RDI
	ret


Done:
	; program completed Successfully
	mov rdi, 0                  ; All is well
	mov rax, 60                 ; put the exit syscall number in rax
	syscall                     ; Call it a good day


section .data
default_file: db "kaem.amd64", 0
prefix: db " +> ", 0
hard: db "Subprocess error", 10, "ABORTING HARD", 10, 0
script: dq 0
tokens: dq 0
command_done: dq 0
max_args: dq 2048               ; 256 * sizeof(char*)
max_string: dq 4096             ; 4096 * sizeof(char)
MALLOC: dq 0
status: dq 0
