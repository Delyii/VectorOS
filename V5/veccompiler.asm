; ==================================================
; VECTOR SCRIPT ENGINE V6 - "THE INTERPRETER ENGINE"
; ==================================================
BITS 32

section .data
    ; --- Command Tokens ---
    token_print     db "print", 0
    token_set       db "set", 0
    token_add       db "add", 0
    token_sub       db "sub", 0
    token_sleep     db "sleep", 0
    token_label     db "label", 0
    token_goto      db "goto", 0
    token_if        db "if", 0
    token_vput      db "vput", 0    ; vput /x /y char
    token_vgetk     db "vgetk", 0   ; vgetk /var
    token_rand      db "rand", 0    ; rand /var max
    token_cls       db "cls", 0     ; clear screen
    token_no_nl     db ",0", 0

    msg_syntax_err  db "Script Error: Unknown Command", 10, 0
    msg_executing_add db "[EXEC ADD]", 10, 0
    msg_executing_if  db "[EXEC IF]", 10, 0
    msg_if_true       db "[IF TRUE - CONTINUE]", 10, 0
    msg_if_false      db "[IF FALSE - SKIP]", 10, 0
    msg_executing_goto db "[EXEC GOTO]", 10, 0
    msg_goto_failed    db "[GOTO FAILED]", 10, 0
    msg_x_value       db "[X=", 0
    msg_bracket       db "]", 10, 0
    msg_found_label   db "[FOUND LABEL AT SLOT ", 0
    msg_close_bracket db "]", 10, 0
    msg_stored_label  db "[STORED LABEL SLOT ", 0
    msg_equals        db " = ", 0
    msg_check_label   db "[CHECKING SLOT ", 0
    msg_if_left       db "[IF LEFT=", 0
    msg_if_right      db " RIGHT=", 0
    msg_goto_success  db "[GOTO SUCCESS]", 10, 0

    ; --- Storage Tables ---
    var_names       times 160 db 0  ; 20 slots * 8 bytes
    var_values      times 20  dd 0  ; 20 slots * 4 bytes
    var_types       times 20  db 0  ; 20 slots * 1 byte (0=int, 1=str)

    label_names     times 160 db 0  ; 20 slots * 8 bytes
    label_addrs     times 20  dd 0  ; 20 slots * 4 bytes (ESI pointers)

    newline_flag    db 1
    num_buffer      times 12 db 0
    temp_val        dd 0

section .text
extern putc
extern puts

extern clear_screen
extern last_key
extern key_ready

global vec_compile
vec_compile:
    pusha
    mov [temp_val], esi             ; Save script start for labels

    ; --- Clear old labels ---
    mov edi, label_names
    mov ecx, 160                    ; Clear all 20 * 8 bytes of label_names
    xor eax, eax
    rep stosb

    mov edi, label_addrs
    mov ecx, 20                     ; Clear all 20 * 4 bytes of label_addrs
    xor eax, eax
    rep stosd

    ; --- Pre-scan for Labels ---
    ; This allows 'goto' to jump forward in the script
    call script_pre_scan

.main_loop:
    call skip_whitespace
    mov al, [esi]
    test al, al
    jz .all_done

    cmp al, 10                      ; Skip extra newlines
    je .next_line

    ; --- Token Matching ---
    mov edi, token_print
    call strcmp_word
    test eax, eax
    je .do_print

    mov edi, token_set
    call strcmp_word
    test eax, eax
    je .do_set

    mov edi, token_vput
    call strcmp_word
    test eax, eax
    je .do_vput

    mov edi, token_vgetk
    call strcmp_word
    test eax, eax
    je .do_vgetk

    mov edi, token_goto
    call strcmp_word
    test eax, eax
    je .do_goto

    mov edi, token_if
    call strcmp_word
    test eax, eax
    je .do_if

    mov edi, token_add
    call strcmp_word
    test eax, eax
    je .do_add

    mov edi, token_sub
    call strcmp_word
    test eax, eax
    je .do_sub

    mov edi, token_rand
    call strcmp_word
    test eax, eax
    je .do_rand

    mov edi, token_sleep
    call strcmp_word
    test eax, eax
    je .do_sleep

    mov edi, token_cls
    call strcmp_word
    test eax, eax
    je .do_cls

    mov edi, token_label            ; Ignore labels during execution
    call strcmp_word
    test eax, eax
    je .skip_line

    jmp .unknown

.next_line:
    inc esi
    jmp .main_loop

.skip_line:
    call skip_to_next_line
    jmp .main_loop

; ---------------- COMMAND HANDLERS ----------------

.do_print:
    add esi,5
    call skip_whitespace

    cmp byte [esi], ';'
    jne .unknown

    inc esi            ; skip first ;

.print_loop:
    lodsb

    cmp al,';'
    je .print_done

    cmp al,'/'
    je .handle_var

    call putc
    jmp .print_loop

.handle_var:
    dec esi          ; restore pointer to '/'
    call find_variable
    test eax,eax
    jz .unknown

    mov eax,[eax]

    ; Check if it's a printable ASCII character (32-126)
    cmp eax, 32
    jl .print_as_number     ; Less than 32, print as number
    cmp eax, 126
    jg .print_as_number     ; Greater than 126, print as number

    ; It's printable ASCII, print as character
    mov bl, al              ; Move to BL for putc
    mov al, bl
    call putc
    jmp .next_var

.print_as_number:
    call print_number

.next_var:
    call skip_to_next_word
    jmp .print_loop

.print_done:
    mov al,10
    call putc
    call skip_to_next_line
    jmp .main_loop
.do_set:
    add esi, 3
    call skip_whitespace
    cmp byte [esi], '/'
    jne .unknown
    inc esi
    call get_or_create_var
    push eax
    call skip_to_next_word
    call get_value
    pop ebx
    mov [ebx], eax
    jmp .main_loop

.do_add:
    add esi, 3
    call skip_whitespace
    cmp byte [esi], '/'
    jne .unknown
    inc esi
    call find_variable
    test eax, eax
    jz .unknown
    push eax
    call skip_to_next_word
    call get_value              ; Get the value to add
    pop ebx
    add [ebx], eax              ; Add it
    jmp .main_loop

.do_sub:
    add esi, 3
    call skip_whitespace
    cmp byte [esi], '/'
    jne .unknown
    inc esi
    call find_variable
    test eax, eax
    jz .unknown
    push eax
    call skip_to_next_word
    call get_value
    pop ebx
    sub [ebx], eax
    jmp .main_loop

.do_vput:
    add esi, 5
    call get_value              ; X
    push eax
    call skip_to_next_word
    call get_value              ; Y
    push eax
    call skip_to_next_word
    lodsb                       ; Character
    pop ebx                     ; Y
    pop ecx                     ; X
    ; Calculate VGA offset: (Y * 80 + X) * 2
    imul ebx, 80
    add ebx, ecx
    shl ebx, 1
    mov edi, 0xB8000
    add edi, ebx
    mov ah, 0x0F                ; Color: White on Black
    mov [edi], ax
    jmp .main_loop

.do_vgetk:
    add esi, 5              ; Skip "vgetk"
    call skip_to_next_word  ; Move to variable name
    call get_or_create_var
    push eax                ; Save variable address

    ; Clear any leftover keys in the buffer
    mov byte [key_ready], 0
    mov byte [last_key], 0

.wait_for_key:
    hlt                     ; Sleep CPU and wait for interrupt
    mov al, [key_ready]     ; Check if keyboard handler set this
    test al, al
    jz .wait_for_key        ; Loop until key is pressed

    mov bl, [last_key]      ; Get the actual key code
    mov byte [key_ready], 0 ; Reset for next vgetk call
    mov byte [last_key], 0  ; Clear the key

    pop eax                 ; Restore variable address
    movzx ebx, bl
    mov [eax], ebx          ; Store key code in variable

    call skip_to_next_line
    jmp .main_loop

.do_goto:
    add esi, 5
    call skip_whitespace
    call find_label
    test eax, eax
    jz .unknown
    mov esi, eax                ; Jump!
    jmp .main_loop

.do_if:
    add esi, 3
    call get_value              ; Left side
    push eax                    ; Save left value
    call skip_to_next_word
    call get_value              ; Right side
    pop ebx                     ; Pop left value into ebx

    ; No debug output - just compare!
    cmp ebx, eax
    jne .if_skip                ; If NOT equal, skip next line
    jmp .main_loop              ; If equal, execute next line
.if_skip:
    call skip_to_next_line
    call skip_to_next_line      ; SKIP TWICE - once for "if" line, once for "goto end" line
    jmp .main_loop

.do_rand:
    add esi, 5
    call get_or_create_var
    push eax
    call skip_to_next_word
    call get_value              ; Max range
    mov ecx, eax
    rdtsc                       ; Read Time Stamp Counter for entropy
    xor edx, edx
    div ecx                     ; EDX = TSC % Max
    pop eax
    mov [eax], edx
    jmp .main_loop

.do_sleep:
    add esi, 5
    call skip_whitespace
    call get_value              ; Value in EAX
    call sleep_ms               ; sleep_ms expects EAX
    call skip_to_next_line
    jmp .main_loop

.do_cls:
    call clear_screen
    add esi, 3
    jmp .main_loop

.unknown:
    mov esi, msg_syntax_err
    call puts
.all_done:
    popa
    ret

; ---------------- HELPERS & SCANNER ----------------

script_pre_scan:
    pusha
.scan_loop:
    call skip_whitespace
    mov al, [esi]
    test al, al
    jz .scan_done

    mov edi, token_label
    call strcmp_word
    test eax, eax
    jnz .not_label

    add esi, 6
    call skip_whitespace
    call create_label           ; Stores current ESI in label table
.not_label:
    call skip_to_next_line
    jmp .scan_loop
.scan_done:
    popa
    ret

create_label:
    mov edx, 0
.find_slot:
    mov edi, label_names
    mov eax, edx
    shl eax, 3
    add edi, eax
    cmp byte [edi], 0
    je .found_slot
    inc edx
    cmp edx, 20
    jl .find_slot
    ret
.found_slot:
    ; Copy name
    mov ecx, 7
.copy:
    mov al, [esi]
    cmp al, 32
    jbe .done_copy
    mov [edi], al
    inc esi
    inc edi
    loop .copy
.done_copy:
    mov byte [edi], 0
    mov eax, label_addrs
    mov [eax + edx*4], esi
    ret

sleep_ms:
    pusha
    mov ecx, eax

.loop:
    push ecx
    mov ecx, 100000
.delay:
    loop .delay
    pop ecx
    dec ecx
    jnz .loop

    popa
    ret


find_label:
    mov edx, 0
.search:
    mov edi, label_names
    mov eax, edx
    shl eax, 3
    add edi, eax
    cmp byte [edi], 0
    je .fail

    ; Save current ESI (script label name position)
    mov ebx, esi

.cmp_loop:
    mov al, [ebx]               ; Get char from script
    mov cl, [edi]               ; Get char from stored label

    ; If stored label ended
    test cl, cl
    jz .check_end

    ; Compare chars
    cmp al, cl
    jne .no_match

    ; Match, advance both
    inc ebx
    inc edi
    jmp .cmp_loop

.check_end:
    ; Stored label is done. Check if script is at word boundary
    cmp al, 32
    jbe .match
    cmp al, 10
    je .match
    cmp al, 0
    je .match

.no_match:
    inc edx
    cmp edx, 20
    jl .search
    jmp .fail

.fail:
    xor eax, eax
    ret

.match:
    mov eax, label_addrs
    mov eax, [eax + edx*4]
    ret

get_value:
    call skip_whitespace
    cmp byte [esi], '/'
    je .from_var
    call atoi
    ret
.from_var:
    inc esi
    call find_variable
    test eax, eax
    jz .val_err
    mov eax, [eax]
    ret
.val_err:
    xor eax, eax
    ret

skip_to_next_line:
    push ebx
.l1:
    lodsb
    test al, al
    jz .l_done
    cmp al, 10
    jne .l1
    ; Now at newline, skip any following newlines or whitespace
    call skip_whitespace
.l_done:
    pop ebx
    ret

skip_to_next_word:
    push ebx
.sw1:
    lodsb
    test al, al
    jz .sw_done
    cmp al, 32
    ja .sw1
    dec esi
    call skip_whitespace
.sw_done:
    pop ebx
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
    cmp al, 0
    je .equal
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

skip_whitespace:
.sw:
    mov al, [esi]
    test al, al
    jz .done
    cmp al, ' '          ; Only space, not other whitespace
    jne .done
    inc esi
    jmp .sw
.done:
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

print_char:
    ; Input: EAX = ASCII code
    ; Output: prints the character
    push eax
    mov al, [eax]           ; Wait, that's wrong - EAX already contains the code
    pop eax
    call putc               ; putc expects the character in AL
    ret
    push eax
    push ebx
    push ecx
    push edx
    push edi
    push esi

print_number:
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

    push esi        ; save script pointer
    mov esi, edi
    call puts
    pop esi         ; restore script pointer

    pop esi
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
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


    ; Variable found! — remove saved original ESI from stack without changing ESI
    add esp, 4
    jmp .found

.next_var:
    pop esi         ; Restore original ESI
    inc edx
    cmp edx, 20
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
    cmp edx, 20
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
