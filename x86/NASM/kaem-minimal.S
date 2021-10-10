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
	pop eax                     ; Get the number of arguments
	pop ebx                     ; Get the program name
	pop ebx                     ; Get the actual input name
	cmp ebx, 0                  ; Check for missing output
	jne _start_out              ; Have real input
	push eax                    ; Need to adjust stack
	mov ebx, default_file       ; Use "kaem.run"

_start_out:
	mov ecx, 0                  ; prepare read_only
	mov eax, 5                  ; the syscall number for open()
	int 0x80                    ; Now open that damn file

	cmp eax, 0                  ; IF NULL We couldn't open the file
	jle Exit_Failure            ; Abort hard
	mov [script], eax           ; Set input pointer

	pop eax                     ; Get start of envp
	mov ebp, esp                ; Protect envp

	mov eax, 45                 ; the Syscall # for SYS_BRK
	mov ebx, 0                  ; Get current brk
	int 0x80                    ; Let the kernel do the work
	mov [MALLOC], eax           ; Set our malloc pointer

	;; Where the main work gets done
	;; Using EBX for tokens and ECX for tokens[i]
main_loop:
	mov eax, [max_args]         ; Using 256 char* of space
	call malloc                 ; get it
	mov ebx, eax                ; set tokens

	mov ecx, ebx                ; I = 0
	mov eax, 0                  ; Using 0
	mov [status], eax           ; status = 0
	mov [command_done], eax     ; command_done = 0

	;; Using EAX for result and EBX for tokens[i]
collect_command:
	call collect_token          ; Get another token
	cmp eax, 0                  ; if NULL == result
	je collect_command_comment  ; It is a comment, don't store

	mov [ecx], eax              ; tokens[i] = result
	add ecx, 4                  ; i = i + 1 (adjusted for char* size)

collect_command_comment:
	mov eax, [command_done]     ; Using command_done
	cmp eax, 0                  ; IF 0 == command_done
	je collect_command          ; keep looping

	;; Deal with line comments
	cmp ecx, ebx                ; if 0 < i
	je main_loop                ; It was a comment

	call print_command          ; print the command
	mov eax, [ebx]              ; program = tokens[0]
	cmp eax, 0                  ; IF NULL == program
	je Exit_Failure             ; Some shit went down, abort

	push ebx                    ; Protect Tokens
	mov eax, 2                  ; FORKing
	int 0x80                    ; int f = FORK()
	pop ebx                     ; Restore Tokens

	cmp eax, 0                  ; Check fork
	jl Exit_Failure             ; IF f == -1 abort hard
	jne collect_command_parent  ; IF f == 0 it is child

	;; Deal with child case
	mov eax, 11                 ; EXECVE
	mov edx, ebp                ; third arg = envp
	mov ecx, ebx                ; second arg = tokens
	mov ebx, [ebx]              ; program = tokens[0]
	int 0x80                    ; execve(program, tokens, envp);
	jmp Exit_Failure            ; return error

collect_command_parent:
	mov ebx, eax                ; first arg = f
	mov ecx, status             ; second arg = &status
	mov edx, 0                  ; third arg = NULL
	mov eax, 7                  ; WAITPID
	int 0x80                    ; waitpid(f, &status, 0);

	mov eax, [status]           ; Using status
	cmp eax, 0                  ; IF 0 == status
	je main_loop                ; Loop forever

	;; Deal with very unhappy case
	mov eax, hard               ; Using "Subprocess error\nABORTING HARD\n"
	call File_Print             ; Print it

;; Exit_Failure function
;; Receives nothing
;; And aborts hard
;; Does NOT return
Exit_Failure:
	mov ebx, 1                  ; All is wrong
	mov eax, 1                  ; put the exit syscall number in eax
	int 0x80                    ; Call it a bad day


;; print_command function
;; Receives tokens[j] in EBX and tokens[i] in ECX
;; Modifies EAX
print_command:
	push ebx                    ; Protect EBX
	mov eax, prefix             ; using " +> "
	call File_Print             ; print it
print_command_loop:
	mov eax, [ebx]              ; using tokens[j]
	call File_Print             ; print it
	add ebx, 4                  ; j = j + 1
	mov eax, 32                 ; using ' '
	call fputc                  ; print it
	cmp ebx, ecx                ; IF j < i
	jne print_command_loop      ; otherwise keep looping

	mov eax, 10                 ; using '\n'
	call fputc                  ; print it
	pop ebx                     ; Restore EBX
	ret


;; collect_token function
;; Receives nothing
;; Overwrites EAX
;; Uses EAX as C, EBX as token and ECX as token[i]
collect_token:
	push ebx                    ; Protect EBX
	push ecx                    ; Protect ECX
	mov eax, [max_string]       ; Using max_string
	call malloc                 ; allocate space
	mov ebx, eax                ; token = malloc(max_string);
	mov ecx, eax                ; i = 0; set token[i]

collect_token_loop:
	call fgetc                  ; c = fgetc(input);
	cmp eax, -4                 ; if C == EOF
	je Done                     ; We are done

	cmp eax, 32                 ; IF C == ' '
	je collect_token_done       ; Space terminates token

	cmp eax, 9                  ; IF C == '\t'
	je collect_token_done       ; tab terminates token

	cmp eax, 10                 ; IF C == '\n'
	jne collect_token_string    ; otherwise check next

	;; It is a newline
	mov eax, 1                  ; Using 1
	mov [command_done], eax     ; Set command_done = TRUE
	jmp collect_token_done      ; Be done

collect_token_string:
	cmp eax, 34                 ; IF C == '"'
	jne collect_token_comment   ; otherwise check next

	;; It is a RAW STRING
	call collect_string         ; Get the rest of the string
	jmp collect_token_done      ; Be done

collect_token_comment:
	cmp eax, 35                 ; IF C == '#'
	jne collect_token_escape    ; otherwise check next

	;; It is a line comment
	call collect_comment        ; Read it all
	mov eax, 1                  ; Using 1
	mov [command_done], eax     ; Set command_done = TRUE
	jmp collect_token_done      ; Be done

collect_token_escape:
	cmp eax, 92                 ; IF C == '\\'
	jne collect_token_other     ; otherwise just store it

	;; It is an escape char
	call fgetc                  ; Read the char to drop
	jmp collect_token_done      ; Be done

collect_token_other:
	mov [ecx], al               ; token[i] = C
	add ecx, 1                  ; i = i + 1
	jmp collect_token_loop      ; Keep going

collect_token_done:
	cmp ebx, ecx                ; IF i == 0
	jne collect_token_good      ; otherwise return the token
	mov ebx, 0                  ; token = NULL

collect_token_good:
	mov eax, ebx                ; Return token
	pop ecx                     ; Restore ECX
	pop ebx                     ; Restore EBX
	ret


;; collect_string function
;; Recieves target[index] in ECX
;; Modifies EAX
;; Uses EAX as C
collect_string:
	call fgetc                  ; C = fgetc(input)
	cmp eax, -4                 ; if C == EOF
	je Exit_Failure             ; Something went horriably wrong

	cmp eax, 34                 ; IF C == '"'
	je collect_string_done      ; be done

	;; deal with inside of string
	mov [ecx], al               ; target[index] = C
	add ecx, 1                  ; index = index + 1
	jmp collect_string          ; Keep going

collect_string_done:
	ret


;; collect_comment function
;; Receives nothing
;; Modifies EAX
;; uses EAX as Int C
;; Just throws away everything it reads
collect_comment:
	call fgetc                  ; C = fgetc(input)
	cmp eax, -4                 ; IF C == EOF
	je Exit_Failure             ; abort hard

	cmp eax, 10                 ; IF C == '\n'
	jne collect_comment         ; otherwise keep looping
	ret


;; Malloc isn't actually required if the program being built fits in the initial memory
;; However, it doesn't take much to add it.
;; Requires [MALLOC] to be initialized and EAX to have the number of desired bytes
malloc:
	push ebx                    ; Protect EBX
	push ecx                    ; Protect ECX
	push edx                    ; Protect EDX
	mov ebx, [MALLOC]           ; Using the current pointer
	add ebx, eax                ; Request the number of desired bytes
	mov eax, 45                 ; the Syscall # for SYS_BRK
	int 0x80                    ; call the Kernel
	mov eax, [MALLOC]           ; Return pointer
	mov [MALLOC], ebx           ; Update pointer
	pop edx                     ; Restore EDX
	pop ecx                     ; Restore ECX
	pop ebx                     ; Restore EBX
	ret


;; fgetc function
;; Loads FILE* from [script]
;; Returns -4 (EOF) or char in EAX
fgetc:
	push ebx                    ; Protect EBX
	push ecx                    ; Protect ECX
	push edx                    ; Protect EDX
	mov eax, -4                 ; Put EOF in eax
	push eax                    ; Assume bad (If nothing read, value will remain EOF)
	lea ecx, [esp]              ; Get stack address
	mov ebx, [script]           ; Where are we reading from
	mov eax, 3                  ; the syscall number for read
	mov edx, 1                  ; set the size of chars we want
	int 0x80                    ; call the Kernel
	pop eax                     ; Get either char or EOF
	cmp eax, -4                 ; Check for EOF
	je fgetc_done               ; Return as is
	movzx eax, al               ; Make it useful
fgetc_done:
	pop edx                     ; Restore EDX
	pop ecx                     ; Restore ECX
	pop ebx                     ; Restore EBX
	ret


;; File_Print function
;; Receives CHAR* in EAX
;; calls fputc for every non-null char
File_Print:
	push ebx                    ; Protect EBX
	push ecx                    ; Protect ECX
	mov ebx, eax                ; Protect S
	cmp eax, 0                  ; Protect against nulls
	je File_Print_Done          ; Simply don't try to print them
File_Print_Loop:
	mov al, [ebx]               ; Read byte
	movzx eax, al               ; zero extend
	cmp eax, 0                  ; Check for NULL
	je File_Print_Done          ; Stop at NULL

	call fputc                  ; write it
	add ebx, 1                  ; S = S + 1
	jmp File_Print_Loop         ; Keep going

File_Print_Done:
	pop ecx                     ; Restore ECX
	pop ebx                     ; Restore EBX
	ret


;; fputc function
;; receives CHAR in EAX and load FILE* from stdout
;; writes char and returns
fputc:
	push ebx                    ; Protect EBX
	push ecx                    ; Protect ECX
	push edx                    ; Protect EDX
	push eax                    ; We are writing eax
	lea ecx, [esp]              ; Get stack address
	mov ebx, 1                  ; Write to target file
	mov eax, 4                  ; the syscall number for write
	mov edx, 1                  ; set the size of chars we want
	int 0x80                    ; call the Kernel
	pop eax                     ; Restore stack
	pop edx                     ; Restore EDX
	pop ecx                     ; Restore ECX
	pop ebx                     ; Restore EBX
	ret


Done:
	; program completed Successfully
	mov ebx, 0                  ; All is well
	mov eax, 1                  ; put the exit syscall number in eax
	int 0x80                    ; Call it a good day


section .data
default_file: db "kaem.x86", 0
prefix: db " +> ", 0
hard: db "Subprocess error", 10, "ABORTING HARD", 10, 0
script: dd 0
tokens: dd 0
command_done: dd 0
max_args: dd 1024               ; 256 * sizeof(char*)
max_string: dd 4096             ; 4096 * sizeof(char)
MALLOC: dd 0
status: dd 0
