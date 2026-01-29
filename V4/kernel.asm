; ==================================================
; MODULE 0: SYSTEM HEADERS & BOOT
; ==================================================
BITS 32
ORG 0x1000

start:
    cli
    cld
    mov esp, stack_top

    call clear_screen
    call pic_remap
    call idt_init

    sti
    call draw_taskbar
    call print_banner
    call print_prompt

.main_loop:
    hlt
    jmp .main_loop

; ==================================================
; MODULE 1: VGA & UI (Screen, Cursor, Taskbar)
; ==================================================

clear_screen:
    mov edi, 0xB8000 + 160
    mov ecx, 80 * 24
    mov ax, 0x0F20
    rep stosw
    mov dword [cursor_pos], 80
    call update_cursor
    ret

scroll_screen:
    mov esi, 0xB8000 + (160 * 2)
    mov edi, 0xB8000 + 160
    mov ecx, 80 * 23
    rep movsw
    mov edi, 0xB8000 + (160 * 24)
    mov ecx, 80
    mov ax, 0x0F20
    rep stosw
    ret

putc:
    pusha
    mov ebx, [cursor_pos]
    cmp al, 10
    je .newline
    cmp al, 8
    je .backspace
    shl ebx, 1
    mov edi, 0xB8000
    add edi, ebx
    mov ah, 0x0F
    mov [edi], ax
    inc dword [cursor_pos]
    jmp .check_scroll
.newline:
    mov eax, [cursor_pos]
    xor edx, edx
    mov ecx, 80
    div ecx
    inc eax
    mul ecx
    mov [cursor_pos], eax
    jmp .check_scroll
.backspace:
    cmp dword [cursor_pos], 80
    jbe .done
    dec dword [cursor_pos]
    mov ebx, [cursor_pos]
    shl ebx, 1
    mov word [0xB8000 + ebx], 0x0F20
    jmp .done
.check_scroll:
    cmp dword [cursor_pos], 2000
    jl .done
    call scroll_screen
    mov dword [cursor_pos], 1920
.done:
    call update_cursor
    popa
    ret

update_cursor:
    pusha
    mov ebx, [cursor_pos]
    mov dx, 0x3D4
    mov al, 0x0F
    out dx, al
    inc dx
    mov al, bl
    out dx, al
    dec dx
    mov al, 0x0E
    out dx, al
    inc dx
    mov al, bh
    out dx, al
    popa
    ret

draw_taskbar:
    pusha
    mov edi, 0xB8000
    mov ah, 0x70
    mov esi, taskbar_text
.text_loop:
    lodsb
    test al, al
    jz .draw_time
    stosw
    jmp .text_loop
.draw_time:
    mov edi, 0xB8000 + 144
    mov al, 0x02            ; Minutes
    call read_rtc
    call bcd_to_bin
    add al, 30
    xor bl, bl
    cmp al, 60
    jl .save_mins
    sub al, 60
    mov bl, 1
.save_mins:
    push eax
    mov al, 0x04            ; Hours
    call read_rtc
    call bcd_to_bin
    add al, 5
    add al, bl
    cmp al, 24
    jl .save_hours
    sub al, 24
.save_hours:
    call bin_to_bcd
    call print_bcd
    mov al, ':'
    mov ah, 0x70
    stosw
    pop eax
    call bin_to_bcd
    call print_bcd
    mov al, ':'
    mov ah, 0x70
    stosw
    mov al, 0x00            ; Seconds
    call read_rtc
    call print_bcd
    popa
    ret

; ==================================================
; MODULE 2: INTERRUPTS & RTC
; ==================================================

read_rtc:
    out 0x70, al
    in al, 0x71
    ret

print_bcd:
    push eax
    shr al, 4
    add al, '0'
    mov ah, 0x70
    stosw
    pop eax
    and al, 0x0F
    add al, '0'
    mov ah, 0x70
    stosw
    ret

timer_handler:
    pusha
    call draw_taskbar
    mov al, 0x20
    out 0x20, al
    popa
    iret

keyboard_handler:
    pusha
    in al, 0x60
    test al, 0x80
    jnz .eoi
    movzx ebx, al
    mov al, [scancode_us + ebx]
    test al, al
    jz .eoi
    cmp al, 10
    je .enter
    cmp al, 8
    je .kb_backspace
    mov ecx, [cmd_len]
    cmp ecx, 63
    jge .eoi
    call putc
    mov edi, cmd_buffer
    add edi, ecx
    mov [edi], al
    inc dword [cmd_len]
    jmp .eoi
.kb_backspace:
    cmp dword [cmd_len], 0
    je .eoi
    dec dword [cmd_len]
    mov al, 8
    call putc
    jmp .eoi
.enter:
    mov eax, [cmd_len]
    mov byte [cmd_buffer + eax], 0
    mov al, 10
    call putc
    call execute_command
    mov dword [cmd_len], 0
    call print_prompt
.eoi:
    mov al, 0x20
    out 0x20, al
    popa
    iret

; ==================================================
; MODULE 3: COMMAND HANDLER
; ==================================================

execute_command:
    pusha
    mov esi, cmd_buffer
.skip_spaces:
    cmp byte [esi], ' '
    jne .check
    inc esi
    jmp .skip_spaces
.check:
    cmp byte [esi], 0
    je .done

    mov edi, cmd_help
    call strcmp
    jc .help
    mov edi, cmd_clear
    call strcmp
    jc .clear
    mov edi, cmd_info
    call strcmp
    jc .info
    mov edi, cmd_ls
    call strcmp
    jc .ls
    mov edi, cmd_touch
    call strcmp_prefix
    jc .touch
    mov edi, cmd_echo
    call strcmp_prefix
    jc .echo
    mov edi, cmd_write
    call strcmp_prefix
    jc .write
    mov edi, cmd_read
    call strcmp_prefix
    jc .read
    mov edi, cmd_debug
    call strcmp
    jc .debug
    mov edi, cmd_dump
    call strcmp
    jc .dump

    mov esi, unknown
    call puts
    jmp .done

.help:
    mov esi, help_msg
    call puts
    jmp .done
.clear:
    call clear_screen
    jmp .done
.info:
    mov esi, info_msg
    call puts
    xor eax, eax
    cpuid
    mov [cpu_str], ebx
    mov [cpu_str+4], edx
    mov [cpu_str+8], ecx
    mov esi, cpu_str
    call puts
    mov al, 10
    call putc
    jmp .done
.ls:
    call fs_list_files
    jmp .done
.touch:
    add esi, 6
    mov edi, placeholder_content
    call fs_create_file
    jmp .done

.read:
    add esi, 5              ; Skip "read "
    push esi                ; SAVE pointer to filename
    call fs_read_file
    pop esi                 ; RESTORE pointer
    jmp .done

.skip_read_spaces:
    cmp byte [esi], ' '
    jne .do_read
    inc esi
    jmp .skip_read_spaces
.do_read:
    call fs_read_file
    jmp .done
.read_skip:                 ; Skip any extra spaces
    cmp byte [esi], ' '
    jne .read_do
    inc esi
    jmp .read_skip
.read_do:
    call fs_read_file
    jmp .done
.write:
    add esi, 6              ; Skip "write "
.skip_pre_name:
    cmp byte [esi], ' '
    jne .get_name
    inc esi
    jmp .skip_pre_name

.get_name:
    mov ebx, esi            ; EBX = start of filename (no leading spaces!)
.find_div:
    lodsb
    test al, al
    jz .write_error
    cmp al, ' '
    jne .find_div

    mov byte [esi-1], 0     ; Null-terminate name

.skip_pre_content:
    cmp byte [esi], ' '
    jne .set_content
    inc esi
    jmp .skip_pre_content

.set_content:
    mov [fs_ptr_content], esi
    mov esi, ebx            ; ESI = Filename
    call fs_create_file
    jmp .done              ; Skip "write "
.write_skip_name:           ; Skip spaces before the filename
    cmp byte [esi], ' '
    jne .write_start
    inc esi
    jmp .write_skip_name

.write_start:
    mov ebx, esi            ; EBX = Clean start of filename
.find_space:
    lodsb
    test al, al
    jz .write_error
    cmp al, ' '
    jne .find_space

    ; Found the divider space!
    mov byte [esi-1], 0     ; Null-terminate filename

.write_skip_content:        ; Skip spaces before the content
    cmp byte [esi], ' '
    jne .write_set_content
    inc esi
    jmp .write_skip_content

.write_set_content:
    mov [fs_ptr_content], esi
    mov esi, ebx            ; ESI = Clean Filename
    call fs_create_file
    jmp .done

.found_divider:
    mov byte [esi-1], 0     ; Terminate filename
    mov [fs_ptr_content], esi
    mov esi, ebx            ; ESI = Filename
    call fs_create_file
    jmp .done


.find_quote:
    lodsb
    test al, al
    jz .write_error         ; Reached end of string without quote
    cmp al, ' '
    jne .find_quote

    ; Found the first quote!
    mov byte [esi-1], 0     ; Null-terminate the filename at the space/quote
    mov edi, esi            ; EDI now points to the content after the first "

.find_end_quote:
    lodsb
    test al, al
    jz .write_save          ; If no closing quote, just take the rest
    cmp al, '"'
    jne .find_end_quote
    mov byte [esi-1], 0     ; Null-terminate the content

.write_save:
    mov esi, ebx            ; ESI = Filename
    ; EDI already points to content
    call fs_create_file
    jmp .done

.write_error:             ; EBX points to start of filename
    mov esi, write_err_msg
    call puts
    jmp .done

.dump:
    mov esi, ram_disk_map
    mov ecx, 48             ; 16 bytes * 3 files
.dump_loop:
    lodsb
    test al, al
    jnz .print_it
    mov al, '-'             ; Show nulls as dashes
.print_it:
    call putc
    loop .dump_loop
    mov al, 10
    call putc
    jmp .done

.debug:
    mov esi, ram_disk_map
    call puts               ; This will print raw names in the map
    mov al, 10
    call putc
    jmp .done

.echo:
    add esi, 4
.echo_skip:
    cmp byte [esi], ' '
    jne .echo_print
    inc esi
    jmp .echo_skip
.echo_print:
    call puts
    mov al, 10
    call putc
.done:
    popa
    ret

; ==================================================
; MODULE 4: FILESYSTEM (RAMFS)
; ==================================================

fs_create_file:
    pusha
    mov ebp, esi
    mov ebx, ram_disk_map
    xor edx, edx            ; FILE INDEX (SAFE)

.find_slot:
    cmp byte [ebx], 0
    je .found
    add ebx, 16
    inc edx
    cmp edx, 16
    jl .find_slot
    mov esi, fs_err_full
    call puts
    popa
    ret

.found:
    ; clear slot
    mov edi, ebx
    mov ecx, 16
    xor al, al
    rep stosb

    ; copy filename
    mov esi, ebp
    mov edi, ebx
    mov ecx, 12
.copy_n:
    lodsb
    test al, al
    jz .name_done
    stosb
    loop .copy_n
.name_done:

    ; ✅ CORRECT DATA ADDRESS
    mov eax, edx
    shl eax, 8
    add eax, ram_disk_data

    ; copy content
    mov edi, eax
    mov esi, [fs_ptr_content]
.copy_d:
    lodsb
    stosb
    test al, al
    jnz .copy_d

    mov esi, fs_msg_ok
    call puts
    popa
    ret



fs_list_files:
    pusha
    mov ebx, ram_disk_map
.loop:
    cmp byte [ebx], 0
    je .next
    mov esi, ebx
    call puts
    mov al, ' '
    call putc
.next:
    add ebx, 16
    cmp ebx, ram_disk_map + 256
    jl .loop
    mov al, 10
    call putc
    popa
    ret

fs_read_file:
    pusha
    mov ebp, esi            ; User input (e.g., "dev2")
    mov ebx, ram_disk_map
    xor edx, edx            ; Index 0-15

.loop:
    cmp byte [ebx], 0       ; Is slot empty?
    je .next

    ; --- DIAGNOSTIC PRINT ---
    ;mov esi, ebx          ; (Optional) Uncomment these 2 lines
    ;call puts             ; to see every file the OS "sees" during search

    mov esi, ebp
    mov edi, ebx
    call strcmp
    jc .found_it

.next:
    add ebx, 16             ; Jump to next slot
    inc edx
    cmp edx, 16
    jl .loop

    mov esi, fs_err_nf
    call puts
    popa
    ret

.found_it:
    mov eax, edx            ; Use the index we just found
    shl eax, 8              ; Multiply by 256
    add eax, ram_disk_data

    mov esi, eax
    call puts
    mov al, 10
    call putc
    popa
    ret

; ==================================================
; MODULE 5: UTILS & SYSTEM SETUP
; ==================================================

puts:
    pusha
.loop:
    lodsb
    test al, al
    jz .done
    call putc
    jmp .loop
.done:
    popa
    ret

print_banner:
    mov esi, banner
    call puts
    ret

print_prompt:
    mov esi, prompt
    call puts
    ret

strcmp:
    push esi                ; Save all
    push edi
    push eax
    push ebx

.loop:
    mov al, [esi]
    mov bl, [edi]
    cmp al, bl
    jne .fail
    test al, al
    jz .success
    inc esi
    inc edi
    jmp .loop

.fail:
    pop ebx                 ; Restore all
    pop eax
    pop edi
    pop esi
    clc                     ; No match
    ret

.success:
    pop ebx
    pop eax
    pop edi
    pop esi
    stc                     ; Match!
    ret

strcmp_prefix:
    push esi
    push edi
.loop:
    mov bl, [edi]
    test bl, bl
    jz .success
    mov al, [esi]
    cmp al, bl
    jne .fail
    inc esi
    inc edi
    jmp .loop
.fail:
    pop edi
    pop esi
    clc
    ret
.success:
    pop edi
    pop esi
    stc
    ret

pic_remap:
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 0x04
    out 0x21, al
    mov al, 0x02
    out 0xA1, al
    mov al, 0x01
    out 0x21, al
    out 0xA1, al
    mov al, 0xFC
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al
    ret

idt_init:
    mov edi, idt
    mov ecx, 256 * 8
    xor al, al
    rep stosb
    mov eax, timer_handler
    mov edi, idt + (0x20 * 8)
    call set_idt_gate
    mov eax, keyboard_handler
    mov edi, idt + (0x21 * 8)
    call set_idt_gate
    lidt [idtr]
    ret

set_idt_gate:
    mov [edi], ax
    mov word [edi + 2], 0x08
    mov byte [edi + 5], 0x8E
    shr eax, 16
    mov [edi + 6], ax
    ret

bcd_to_bin:
    push ebx
    movzx ebx, al
    and al, 0x0F
    shr bl, 4
    imul ebx, 10
    add al, bl
    pop ebx
    ret

bin_to_bcd:
    push ebx
    movzx ax, al
    mov bl, 10
    div bl
    shl al, 4
    or al, ah
    pop ebx
    ret

; ==================================================
; MODULE 6: DATA & STORAGE
; ==================================================

cursor_pos dd 80
cmd_len    dd 0

taskbar_text db " Vector OS V4 | STATUS: ACTIVE | TIME: ", 0
banner       db "Vector Kernel Loaded.", 10, "Welcome devy.", 10, 0
prompt       db "> ", 0
unknown      db "Unknown command.", 10, 0
help_msg     db "Commands: help, clear, info, echo, ls, touch, write", 10, 0
info_msg     db "Vector OS v4.0 (x86 ASM) - CPU: ", 0
placeholder_content db "New File Content", 0
cmd_dump   db "dump", 0
cmd_help   db "help", 0
cmd_clear  db "clear", 0
cmd_echo   db "echo", 0
cmd_info   db "info", 0
cmd_ls     db "ls", 0
cmd_touch  db "touch ", 0
cmd_write     db "write ", 0
cmd_read      db "read ", 0
cmd_debug  db "debug", 0
write_err_msg db "Usage: write name ", 34, "text", 34, 10, 0 ; 34 is ASCII for "
fs_err_nf     db "File not found.", 10, 0
fs_msg_ok   db "Success.", 10, 0
fs_err_full db "Disk full!", 10, 0
scancode_us:
    db 0, 27, '1','2','3','4','5','6','7','8','9','0','-','=', 8
    db 9, 'q','w','e','r','t','y','u','i','o','p','[',']', 10
    db 0, 'a','s','d','f','g','h','j','k','l',';',"'", '`', 0
    db '\','z','x','c','v','b','n','m',',','.','/', 0
    db 0, 0, ' '
    times 128-($-scancode_us) db 0

idtr:
    dw 256*8 - 1
    dd idt

; ==================================================
; MODULE 7: BSS AREA (Uninitialized RAM)
; ==================================================
section .bss
align 16
idt             resb 2048
cmd_buffer      resb 128
cpu_str         resb 16
fs_ptr_content  resd 1

; STORAGE AREA (The "Disk")
ram_disk_map    resb 1024   ; More than enough space
ram_disk_data   resb 8192   ; 8KB of data space

; STACK AREA (Must be at the very bottom)
stack           resb 8192
stack_top:
