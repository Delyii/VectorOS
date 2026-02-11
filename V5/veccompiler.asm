BITS 32

section .data
    ; --- Command Tokens ---
    token_print     db "print", 0
    token_set       db "set", 0
    token_add       db "add", 0
    token_sub       db "sub", 0
    token_sleep     db "sleep", 0
    token_no_nl     db ",0", 0

    msg_syntax_err  db "Syntax Error: Command or variable not found", 10, 0

    var_names       times 80 db 0   ; 10 slots * 8 bytes
    var_values      times 10 dd 0   ; 10 slots * 4 bytes

    newline_flag    db 1
    num_buffer      times 12 db 0

section .text
extern putc
extern puts
extern sleep_ms

global vec_compile
vec_compile:
    pusha

.main_loop:
    call skip_whitespace

    mov al, [esi]
    test al, al
    jz .all_done

    mov byte [newline_flag], 1

    mov edi, token_print
    call strcmp_word
    test eax, eax
    je .do_print

    mov edi, token_set
    call strcmp_word
    test eax, eax
    je .do_set

    mov edi, token_add
    call strcmp_word
    test eax, eax
    je .do_add

    mov edi, token_sub
    call strcmp_word
    test eax, eax
    je .do_sub

    mov edi, token_sleep
    call strcmp_word
    test eax, eax
    je .do_sleep

    jmp .unknown

; ---------------- COMMANDS ----------------

.do_print:
    add esi, 5
    call skip_whitespace

    mov edi, token_no_nl
    mov ecx, 2
    call strcmp_limit
    test eax, eax
    jne .print_engine
    mov byte [newline_flag], 0
    add esi, 2
    call skip_whitespace

.print_engine:
    lodsb
    test al, al
    jz .print_finish
    cmp al, 10
    je .print_finish
    cmp al, 13
    je .print_finish
    cmp al, '/'
    je .handle_var_inline
    call putc
    jmp .print_engine

.handle_var_inline:
    call find_variable
    test eax, eax
    jz .unknown
    mov eax, [eax]
    call print_number
    call skip_to_next_word
    jmp .print_engine

.do_set:
    add esi, 3
    call skip_whitespace

    ; Expect / prefix for variable names
    cmp byte [esi], '/'
    jne .unknown
    inc esi                     ; Skip the /

    call get_or_create_var
    test eax, eax
    jz .unknown
    push eax
    call skip_to_next_word
    call get_value
    pop ebx
    mov [ebx], eax
    jmp .main_loop

.do_add:
    add esi, 3
    call skip_whitespace

    ; Expect / prefix for variable names
    cmp byte [esi], '/'
    jne .unknown
    inc esi                     ; Skip the /

    call find_variable
    test eax, eax
    jz .unknown
    push eax
    call skip_to_next_word
    call get_value
    pop ebx
    add [ebx], eax
    jmp .main_loop

.do_sub:
    add esi, 3
    call skip_whitespace

    ; Expect / prefix for variable names
    cmp byte [esi], '/'
    jne .unknown
    inc esi                     ; Skip the /

    call find_variable
    test eax, eax
    jz .unknown
    push eax
    call skip_to_next_word
    call get_value
    pop ebx
    sub [ebx], eax
    jmp .main_loop

.do_sleep:
    add esi, 5
    call skip_whitespace
    call get_value
    ; push eax
    ; call sleep_ms
    jmp .main_loop

.print_finish:
    cmp byte [newline_flag], 1
    jne .main_loop
    mov al, 10
    call putc
    jmp .main_loop

.unknown:
    mov esi, msg_syntax_err
    call puts
    popa
    ret

.all_done:
    popa
    ret

; ---------------- HELPERS ----------------

skip_to_next_word:
.loop_skip:
    lodsb
    test al, al
    jz .done
    cmp al, 32
    ja .loop_skip

.loop_ws:
    mov al, [esi]
    test al, al
    jz .done
    cmp al, 32
    jbe .skip_char
    jmp .done
.skip_char:
    inc esi
    jmp .loop_ws
.done:
    ret

get_value:
    cmp byte [esi], '/'
    je .from_var
    call atoi
    ret
.from_var:
    inc esi
    call find_variable
    test eax, eax
    jz .err
    mov eax, [eax]
    call skip_to_next_word
    ret
.err:
    xor eax, eax
    ret

strcmp_word:
    push esi
    push edi
.loop:
    mov al, [esi]
    mov bl, [edi]
    test bl, bl
    jz .check_term
    cmp al, bl
    jne .not_equal
    inc esi
    inc edi
    jmp .loop
.check_term:
    cmp al, 32
    jbe .equal
.not_equal:
    pop edi
    pop esi
    mov eax, 1
    ret
.equal:
    pop edi
    pop esi
    xor eax, eax
    ret

skip_whitespace:
.sw:
    mov al, [esi]
    test al, al
    jz .done
    cmp al, 32
    ja .done
    inc esi
    jmp .sw
.done:
    ret

strcmp_limit:
    pusha
.loop:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .bad
    inc esi
    inc edi
    loop .loop
    popa
    xor eax, eax
    ret
.bad:
    popa
    mov eax, 1
    ret

atoi:
    xor eax, eax
.loop:
    movzx ebx, byte [esi]
    cmp bl, '0'
    jl .done
    cmp bl, '9'
    jg .done
    sub bl, '0'
    imul eax, 10
    add eax, ebx
    inc esi
    jmp .loop
.done:
    ret

print_number:
    pusha
    mov edi, num_buffer + 10
    mov byte [edi], 0
    mov ebx, 10
.loop:
    xor edx, edx
    div ebx
    add dl, '0'
    dec edi
    mov [edi], dl
    test eax, eax
    jnz .loop
    mov esi, edi
    call puts
    popa
    ret

find_variable:
    push esi
    push edx
    push ecx
    push ebx
    mov edx, 0

    ; Check for / prefix
    cmp byte [esi], '/'
    jne .search
    inc esi

.search:
    mov edi, var_names
    mov eax, edx
    shl eax, 3
    add edi, eax

    ; Save original ESI position
    push esi

    mov ecx, 0
.cmp:
    mov al, [esi]
    cmp al, 32
    jbe .check_name_end
    cmp al, 0
    je .check_name_end

    mov bl, [edi]
    cmp al, bl
    jne .next_var

    inc esi
    inc edi
    inc ecx
    cmp ecx, 8
    jl .cmp

.check_name_end:
    ; Check if variable name in table also ends
    mov bl, [edi]
    test bl, bl
    jnz .next_var

    ; Variable found!
    pop esi         ; Clean up saved ESI
    jmp .found

.next_var:
    pop esi         ; Restore original ESI
    inc edx
    cmp edx, 10
    jl .search

    ; Not found
    pop ebx
    pop ecx
    pop edx
    pop esi
    xor eax, eax
    ret

.found:
    ; Calculate address in var_values
    mov eax, var_values
    shl edx, 2
    add eax, edx

    pop ebx
    pop ecx
    pop edx
    pop esi
    ret

get_or_create_var:
    ; First try to find existing variable
    call find_variable
    test eax, eax
    jnz .done

    ; Need to create new variable
    mov edx, 0

.find_empty_slot:
    mov edi, var_names
    mov eax, edx
    shl eax, 3
    add edi, eax

    ; Check if slot is empty (first byte is 0)
    cmp byte [edi], 0
    je .claim_slot

    inc edx
    cmp edx, 10
    jl .find_empty_slot

    ; No free slots
    xor eax, eax
    ret

.claim_slot:
    ; Copy variable name into slot
    push edi        ; Save slot address
    push esi        ; Save name pointer

.copy_name:
    mov al, [esi]
    cmp al, 32
    jbe .name_copied
    cmp al, 0
    je .name_copied

    mov [edi], al
    inc esi
    inc edi

    ; Check if we've copied maximum length
    mov eax, esi
    sub eax, [esp]  ; Compare with original
    cmp eax, 7
    jl .copy_name

.name_copied:
    mov byte [edi], 0  ; Null terminate

    pop esi
    pop edi

    ; Now find the variable to get its address
    call find_variable

.done:
    ret
