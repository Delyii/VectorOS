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
    mov edi, cmd_ls
    call strcmp
    jc .ls
    mov edi, cmd_lsd
    call strcmp
    jc .lsd
    mov edi, cmd_mkdir
    call strcmp_prefix
    jc .mkdir
    mov edi, cmd_write
    call strcmp_prefix
    jc .write
    mov edi, cmd_read
    call strcmp_prefix
    jc .read
    mov edi, cmd_cd
    call strcmp_prefix
    jc .cd
    mov edi, cmd_dump
    call strcmp
    jc .dump
    mov edi, cmd_clear
    call strcmp
    jc .clear

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
.ls:
    mov ebx, ram_disk_file_map
    call fs_list_all
    jmp .done
.lsd:
    mov ebx, ram_disk_dir_map
    call fs_list_all
    jmp .done

.mkdir:
    add esi, 6
    mov al, 'd'
    call fs_create_prefixed_entry
    jmp .done

.write:
    add esi, 6
.skip_pre_name:
    cmp byte [esi], ' '
    jne .get_name
    inc esi
    jmp .skip_pre_name
.get_name:
    mov ebx, esi
.find_div:
    lodsb
    test al, al
    jz .write_error
    cmp al, ' '
    jne .find_div
    mov byte [esi-1], 0
    mov [fs_ptr_content], esi
    mov esi, ebx
    mov al, 'f'
    call fs_create_prefixed_entry
    jmp .done
.write_error:
    mov esi, write_err_msg
    call puts
    jmp .done

.read:
    add esi, 5
    mov al, 'f'
    call fs_read_entry
    jmp .done

.cd:
    add esi, 3
    mov al, 'd'
    call fs_change_dir
    jmp .done

.dump:
    mov esi, ram_disk_file_map
    mov ecx, 64
    call .do_dump
    mov esi, ram_disk_dir_map
    mov ecx, 64
    call .do_dump
    jmp .done
.do_dump:
.l: lodsb
    test al, al
    jnz .p
    mov al, '-'
.p: call putc
    loop .l
    mov al, 10
    call putc
    ret

.done:
    popa
    ret

; ==================================================
; MODULE 4: SIGMA FILESYSTEM (SPLIT MAPS)
; ==================================================

; ESI = Name, AL = 'f' or 'd'
; ESI = Name, AL = 'f' or 'd'
fs_create_prefixed_entry:
    pusha
    mov dl, al              ; DL = Prefix
    mov ebp, esi            ; EBP = User Name

    mov ebx, ram_disk_file_map
    cmp dl, 'd'
    jne .find
    mov ebx, ram_disk_dir_map

.find:
    xor ecx, ecx
.loop:
    cmp byte [ebx], 0       ; Is slot empty?
    je .found
    add ebx, 16
    inc ecx
    cmp ecx, 32
    jl .loop
    mov esi, fs_err_full
    call puts
    popa
    ret

.found:
    ; 1. Clean slot
    push edi
    mov edi, ebx
    mov ecx, 4
    xor eax, eax
    rep stosd
    pop edi

    ; 2. Write Prefix and Name
    mov edi, ebx
    mov al, dl
    stosb                   ; Store 'f' or 'd'
    mov esi, ebp
    mov ecx, 11
.copy:
    lodsb
    test al, al
    jz .done_name
    stosb
    loop .copy
.done_name:

    ; 3. Stamp with CURRENT Parent ID
    mov al, [current_dir]
    mov [ebx + 13], al      ; Byte 13 is the "Home" of this file/dir

    ; 4. If file, copy content to data area
    cmp dl, 'f'
    jne .finish
    mov eax, ecx
    mov eax, ebx
    sub eax, ram_disk_file_map
    shr eax, 4              ; Get Index (Offset / 16)
    shl eax, 8              ; Data Offset (Index * 256)
    add eax, ram_disk_data
    mov edi, eax
    mov esi, [fs_ptr_content]
.copy_data:
    lodsb
    stosb
    test al, al
    jnz .copy_data

.finish:
    mov esi, fs_msg_ok
    call puts
    popa
    ret

fs_change_dir:
    pusha
    mov ebp, esi            ; Target name

    ; Handle "cd .."
    cmp byte [esi], '.'
    jne .search

    movzx eax, byte [current_dir]
    cmp al, 0xFF
    je .done                ; Already at root

    ; Get parent of current dir
    shl eax, 4
    add eax, ram_disk_dir_map
    mov al, [eax + 13]      ; Parent ID
    mov [current_dir], al
    mov esi, fs_msg_ok
    call puts
    popa
    ret

.search:
    mov ebx, ram_disk_dir_map
    xor ecx, ecx
.l:
    cmp byte [ebx], 'd'     ; Is it a directory?
    jne .n
    mov al, [ebx + 13]      ; Is it INSIDE our current folder?
    cmp al, [current_dir]
    jne .n

    lea edi, [ebx + 1]      ; Compare name
    mov esi, ebp
    call strcmp
    jc .found
.n:
    add ebx, 16
    inc ecx
    cmp ecx, 32
    jl .l
    mov esi, fs_err_nf
    call puts
    popa
    ret
.found:
    mov [current_dir], cl   ; Move into this directory (its ID is its index)
    mov esi, fs_msg_ok
    call puts
.done:
    popa
    ret

fs_list_all:
    pusha
    xor ecx, ecx
.l:
    cmp byte [ebx], 0
    je .n
    mov al, [ebx + 13]
    cmp al, [current_dir]
    jne .n
    lea esi, [ebx + 1]      ; Skip prefix ('f' or 'd')
    call puts
    mov al, ' '
    call putc
.n:
    add ebx, 16
    inc ecx
    cmp ecx, 32
    jl .l
    mov al, 10
    call putc
    popa
    ret

fs_read_entry:
    pusha
    mov ebp, esi            ; User Name
    mov ebx, ram_disk_file_map
    xor ecx, ecx
.l:
    cmp byte [ebx], 'f'
    jne .n
    mov al, [ebx + 13]
    cmp al, [current_dir]
    jne .n
    lea edi, [ebx + 1]
    mov esi, ebp
    call strcmp
    jc .found
.n:
    add ebx, 16
    inc ecx
    cmp ecx, 32
    jl .l
    mov esi, fs_err_nf
    call puts
    popa
    ret
.found:
    mov eax, ecx
    shl eax, 8
    add eax, ram_disk_data
    mov esi, eax
    call puts
    mov al, 10
    call putc
    popa
    ret



; ==================================================
; MODULE 5: UTILS
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
    pusha
    mov al, '('
    call putc

    movzx eax, byte [current_dir]
    cmp al, 0xFF            ; Check if we are in Root
    je .print_root

    ; If not root, look up name
    movzx ebx, al
    shl ebx, 4              ; index * 16
    add ebx, ram_disk_dir_map
    inc ebx                 ; skip 'd'
    mov esi, ebx
    call puts
    jmp .finish_prompt

.print_root:
    mov esi, root_name      ; "root"
    call puts

.finish_prompt:
    mov esi, prompt_end     ; ") > "
    call puts
    popa
    ret


strcmp:
    pusha
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
.success:
    popa
    stc
    ret
.fail:
    popa
    clc
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
; MODULE 6: DATA
; ==================================================

cursor_pos dd 80
cmd_len    dd 0
current_dir db 0xFF

taskbar_text db " Vector OS V4 | STATUS: ACTIVE | TIME: ", 0
banner       db "Vector Kernel Loaded.", 10, "Welcome devy.", 10, 0
root_name   db "root", 0
prompt_end  db ") > ", 0
cmd_lsd     db "lsd", 0      ; Add this so lsd works!
unknown      db "Unknown command.", 10, 0
help_msg     db "Commands: help, ls, lsd, mkdir, write, read, cd, dump, clear", 10, 0
cmd_help   db "help", 0
cmd_ls     db "ls", 0
cmd_mkdir  db "mkdir ", 0
cmd_write  db "write ", 0
cmd_read   db "read ", 0
cmd_cd     db "cd ", 0
cmd_dump   db "dump", 0
cmd_clear  db "clear", 0

write_err_msg db "Usage: write name content", 10, 0
fs_err_nf     db "Not found.", 10, 0
fs_msg_ok     db "Success.", 10, 0
fs_err_full   db "Disk full!", 10, 0

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
; MODULE 7: BSS
; ==================================================
section .bss
align 16
idt             resb 2048
cmd_buffer      resb 128
fs_ptr_content  resd 1

ram_disk_file_map resb 512
ram_disk_dir_map  resb 512
ram_disk_data     resb 8192

stack           resb 8192
stack_top:
