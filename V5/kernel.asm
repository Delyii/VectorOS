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
    call init_fs
    sti
    call draw_taskbar
    call print_banner
    call print_prompt


.main_loop:
    hlt

    ; Handle character echo
    cmp byte [echo_needed], 1
    jne .check_backspace
    mov byte [echo_needed], 0
    ; Get last character from buffer and echo it
    mov eax, [cmd_len]
    dec eax
    mov al, [cmd_buffer + eax]
    call putc

.check_backspace:
    cmp byte [backspace_needed], 1
    jne .check_newline
    mov byte [backspace_needed], 0
    mov al, 8
    call putc

.check_newline:
    cmp byte [newline_needed], 1
    jne .check_command
    mov byte [newline_needed], 0
    mov al, 10
    call putc

.check_command:
    ; Check for pending command
    cmp byte [cmd_pending], 1
    jne .main_loop

    ; Execute command (outside interrupt context!)
    mov byte [cmd_pending], 0

    ; Terminate the command string
    mov eax, [cmd_len]
    mov byte [cmd_buffer + eax], 0

    call execute_command
    mov dword [cmd_len], 0
    call print_prompt

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
    cmp byte [app_running], 1
    je .no_draw

    call draw_taskbar

.no_draw:
    mov al, 0x20
    out 0x20, al
    popa
    iret


keyboard_handler:
    pusha
    in al, 0x60            ; Read scancode from hardware
    mov ah, al             ; Store scancode in AH

    test al, 0x80          ; Is it a key release?
    jnz .eoi               ; If yes, just finish

    movzx ebx, al
    mov al, [scancode_us + ebx] ; Convert to ASCII

    ; --- SHARED KEY SYSTEM ---
    mov [last_key], al
    mov [last_scancode], ah
    mov byte [key_ready], 1
    ; -------------------------

    ; If we are inside VED or another app, we stop here.
    cmp byte [app_running], 1
    je .eoi

    ; --- NORMAL TTY / SHELL LOGIC ---
    test al, al
    jz .eoi

    cmp al, 10             ; Enter
    je .enter
    cmp al, 8              ; Backspace
    je .kb_backspace

    mov ecx, [cmd_len]
    cmp ecx, 63
    jge .eoi

    ; Store in buffer
    mov edi, cmd_buffer
    add edi, ecx
    mov [edi], al
    inc dword [cmd_len]

    ; DO NOT call putc here - we'll echo in main loop
    ; Just set a flag for echo
    mov byte [echo_needed], 1

    jmp .eoi

.kb_backspace:
    cmp dword [cmd_len], 0
    je .eoi
    dec dword [cmd_len]
    ; Set backspace flag
    mov byte [backspace_needed], 1
    jmp .eoi

.enter:
    ; Mark that we have a command to execute
    mov byte [cmd_pending], 1
    ; Set newline flag for echo
    mov byte [newline_needed], 1
    ; Fall through to .eoi

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
    mov edi, cmd_rmf
    call strcmp_prefix
    jc .rmf
    mov edi, cmd_rmd
    call strcmp_prefix
    jc .rmd
    mov edi, cmd_format
    call strcmp
    jc .format_total
    mov edi, cmd_run
    call strcmp_prefix
    jc .run
    mov edi, cmd_edit
    call strcmp_prefix
    jc .edit

    mov edi, cmd_compile
    call strcmp_prefix
    jc .compile


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

.edit:
    add esi, 5          ; Skip "edit "
    call ved            ; Call the editor with ESI pointing to filename
    call clear_screen   ; When editor exits, clean up the screen
    jmp .done

.compile:
    add esi, 8  ; Skip "compile "
    ; Parse input and output filenames
    ; For now: compile script.vec output.vec
    call vec_compile
    jmp .done



.format_total:
    mov esi, msg_total_wipe
    call puts

    ; We will wipe from LBA 1 up to LBA 500 (adjust as needed)
    mov dword [current_search_lba], 1

.wipe_loop:
    ; 1. Manually zero out the 512-byte scratchpad
    mov edi, fs_scratchpad
    mov ecx, 512
    xor al, al
    rep stosb            ; Fill EDI with 0s for ECX bytes

    ; 2. Write the empty buffer to the current sector
    mov eax, [current_search_lba]
    mov cl, 1            ; Write 1 sector at a time
    mov esi, fs_scratchpad
    cli                  ; Disable interrupts for disk stability
    call disk_write      ; Write the zeros to hardware
    sti

    ; 3. Visual feedback (print a dot every 10 sectors)
    mov eax, [current_search_lba]
    test al, 0x0F
    jnz .no_dot
    mov al, '.'
    call putc
.no_dot:

    ; 4. Increment and check limit
    inc dword [current_search_lba]
    cmp dword [current_search_lba], 500 ; How many sectors to wipe total
    jl .wipe_loop

    mov esi, fs_msg_done
    call puts
    jmp .done

.run:
    add esi, 4
    call vec_run
    jc .run_err
    jmp .done

.run_err:
    mov esi, fs_err_nf
    call puts
    jmp .done


.rmf:
    add esi, 4          ; Skip "rmf "
    call fs_delete_file
    jmp .done

.rmd:
    add esi, 4          ; Skip "rmd "
    call fs_delete_dir
    jmp .done

.mkdir:
    add esi, 6
    mov al, 'd'
    call fs_create_prefixed_entry
    jmp .done

.write:
    add esi, 6              ; skip "write "
.skip_pre_name:
    cmp byte [esi], ' '
    jne .get_name
    inc esi
    jmp .skip_pre_name

.get_name:
    mov ebx, esi            ; EBX = filename start

.find_div:
    lodsb
    test al, al
    jz .write_error
    cmp al, ' '
    jne .find_div

    ; terminate filename
    mov byte [esi-1], 0

    ; ESI now points to content
    mov [fs_ptr_content], esi

    ; -----------------------------
    ; Compute content length → temp_size
    ; -----------------------------
    xor ecx, ecx
.len_loop:
    mov al, [esi + ecx]
    test al, al
    jz .len_done
    inc ecx
    jmp .len_loop
.len_done:
    mov [temp_size], ecx

    ; -----------------------------
    ; Create file entry
    ; -----------------------------
    mov esi, ebx            ; filename
    mov al, 'f'
    call fs_create_prefixed_entry
    jmp .done

.write_error:
    mov esi, write_err_msg
    call puts
    jmp .done


.read:
    add esi, 5          ; Skip "read "

    ; Check if it ends with .vec
    push esi
    call is_vec_extension
    pop esi
    jz .read_vec

    ; Not a .vec file, treat as regular file
    mov al, 'f'
    call fs_read_entry
    jmp .done

.read_vec:
    ; It's a .vec file, show info
    call fs_read_entry
    jmp .done
.cd:
    add esi, 3
    mov al, 'd'
    call fs_change_dir
    jmp .done

.dump:
    call cmd_dump_file      ; Jump to the standalone routine
    jmp .done

.done:
    popa
    ret

; ==================================================
; MODULE 4: UNIFIED PHYSICAL FILESYSTEM (32-BYTE)
; ==================================================

%include "disk_driver.asm"


; --- fs_write_file (ESI=Name, EDI=Content) ---
; --------------------------------------------------
; fs_write_file
; IN:
;   ESI = filename
;   EDI = content pointer
;   [temp_size] = size (bytes)
; --------------------------------------------------
fs_write_file:
    pusha

    mov [fs_ptr_content], edi     ; content pointer
    mov al, 'f'
    call fs_create_prefixed_entry
    jc .error

    popa
    ret

.error:
    mov esi, fs_err_full
    call puts
    popa
    ret


init_fs:
    mov byte [current_dir], 0xFF ; Start at Root
    ret

; --- INTERNAL HELPER: FIND ENTRY ---
; Inputs: ESI = Name, AL = Type ('f' or 'd')
; Outputs: EAX = metadata LBA, EBX = Ptr in fs_scratchpad (slot), ECX = Slot Index, CF=0 if found
fs_find_entry:
    push esi
    mov [temp_type], al
    mov dword [current_search_lba], 100

.sector_loop:
    mov eax, [current_search_lba]
    mov cl, 1
    mov edi, fs_scratchpad
    call disk_read

    mov ebx, fs_scratchpad
    xor ecx, ecx                ; slot index

.slot_loop:
    mov al, [ebx]               ; type
    cmp al, [temp_type]
    jne .next_slot

    mov al, [ebx + 13]          ; parent id
    cmp al, [current_dir]
    jne .next_slot

    push esi
    push ebx
    lea edi, [ebx + 1]          ; name pointer
    call strcmp
    pop ebx
    pop esi
    jc .found

.next_slot:
    add ebx, 32                 ; 32-byte stride
    inc ecx
    cmp ecx, 16
    jl .slot_loop

    inc dword [current_search_lba]
    cmp dword [current_search_lba], 120
    jl .sector_loop

    pop esi
    stc                         ; CF = 1 -> not found
    ret

.found:
    pop esi
    mov eax, [current_search_lba] ; metadata LBA
    clc
    ret

; --- FS_CREATE_PREFIXED_ENTRY ---
; IN: AL = 'f'/'d', ESI -> filename, [fs_ptr_content] -> content ptr (for files)
; OUT: EAX = metadata LBA, ECX = slot index, CF=0 success
fs_create_prefixed_entry:
    pusha
    mov [temp_type], al
    mov [temp_name_ptr], esi
    mov dword [current_search_lba], 100

.next_sector:
    mov eax, [current_search_lba]
    mov cl, 1
    mov edi, fs_scratchpad
    call disk_read

    mov ebx, fs_scratchpad
    xor ecx, ecx                ; slot index

.loop_slots:
    cmp byte [ebx], 0           ; empty slot?
    je .found_slot
    add ebx, 32
    inc ecx
    cmp ecx, 16
    jl .loop_slots

    inc dword [current_search_lba]
    cmp dword [current_search_lba], 120
    jl .next_sector
    jmp .err

.found_slot:
    ; -----------------------------
    ; Write METADATA into scratchpad
    ; -----------------------------
    mov edi, ebx
    mov al, [temp_type]
    stosb                       ; Offset 0: type

    mov esi, [temp_name_ptr]
    mov edx, ecx                ; save slot index
    mov ecx, 11
    rep movsb                   ; Offset 1–11: name
    mov ecx, edx                ; restore slot index

    mov al, [temp_perms]
    mov [ebx + 12], al          ; perms
    mov al, [current_dir]
    mov [ebx + 13], al          ; parent
    mov al, [temp_owner]
    mov [ebx + 14], al          ; owner

    ; Size: only meaningful for files — use temp_size (may be zero)
    mov eax, [temp_size]
    mov [ebx + 16], eax         ; Offset 16: Size (4 bytes)

    ; -----------------------------
    ; Commit METADATA sector to disk
    ; -----------------------------
    mov eax, [current_search_lba]
    mov cl, 1
    mov esi, fs_scratchpad
    call disk_write

    ; -----------------------------
    ; If FILE → write DATA sector
    ; -----------------------------
    mov al, [temp_type]
    cmp al, 'f'
    jne .done

    ; if temp_size == 0, compute length from [fs_ptr_content]
    mov eax, [temp_size]
    test eax, eax
    jnz .have_size
    ; compute strlen of [fs_ptr_content]
    mov esi, [fs_ptr_content]
    xor ecx, ecx
.slen_loop:
    mov al, [esi + ecx]
    test al, al
    jz .slen_done
    inc ecx
    jmp .slen_loop
.slen_done:
    mov eax, ecx
    mov [temp_size], eax
.have_size:

    ; Prepare a zeroed 512-byte sector in fs_scratchpad
    mov edi, fs_scratchpad
    mov ecx, 512
    xor al, al
    rep stosb

    ; Copy file content into scratchpad (up to 512)
    mov esi, [fs_ptr_content]
    mov ecx, [temp_size]
    cmp ecx, 512
    jbe .copy_ok
    mov ecx, 512
.copy_ok:
    mov edi, fs_scratchpad
    rep movsb

    ; Data LBA = 200 + ((meta_lba - 100) * 16) + slot
    mov eax, [current_search_lba]
    sub eax, 100
    imul eax, 16
    add eax, edx        ; edx was saved slot index
    add eax, 200

    mov cl, 1
    mov esi, fs_scratchpad
    call disk_write

.done:
    mov eax, [current_search_lba] ; return metadata LBA
    mov ecx, edx                  ; return slot index in ECX
    clc
    mov esi, fs_msg_ok
    call puts
    popa
    ret

.err:
    stc
    mov esi, fs_err_full
    call puts
    popa
    ret

; --- FS_LIST_ALL (Handles 'ls') ---
fs_list_all:
    pusha
    mov dword [current_search_lba], 100
.sector_loop:
    mov eax, [current_search_lba]
    mov cl, 1
    mov edi, fs_scratchpad
    call disk_read

    mov ebx, fs_scratchpad
    mov ecx, 16
.slot_loop:
    cmp byte [ebx], 0       ; Empty?
    je .next
    mov al, [ebx + 13]      ; Parent ID
    cmp al, [current_dir]
    jne .next

    ; Print Entry Info
    lea esi, [ebx + 1]      ; Name
    call puts
    mov esi, msg_tab
    call puts
    mov al, '['
    call putc
    mov al, [ebx]           ; Type
    call putc
    mov al, ']'
    call putc

    mov esi, msg_parent
    call puts
    movzx eax, byte [ebx + 13]
    call print_int

    mov al, 10
    call putc
.next:
    add ebx, 32
    loop .slot_loop
    inc dword [current_search_lba]
    cmp dword [current_search_lba], 110
    jl .sector_loop
    popa
    ret

; --- FS_CHANGE_DIR ---
fs_change_dir:
    pusha

    ; -------------------------
    ; Handle "cd .."
    ; -------------------------
    cmp byte [esi], '.'
    jne .cd_into

    ; If already at root, stay there
    mov al, [current_dir]
    cmp al, 0xFF
    je .ok

    ; current_dir = global slot ID
    ; Compute sector and slot of current directory
    movzx eax, byte [current_dir]
    xor edx, edx
    mov ebx, 16
    div ebx                ; EAX = sector_index, EDX = slot_in_sector

    add eax, 100           ; metadata base LBA
    mov cl, 1
    mov edi, fs_scratchpad
    call disk_read

    ; EBX = pointer to this directory’s slot
    mov eax, edx
    shl eax, 5             ; *32
    add eax, fs_scratchpad

    ; Load parent ID
    mov al, [eax + 13]
    mov [current_dir], al
    jmp .ok

    ; -------------------------
    ; Handle "cd <name>"
    ; -------------------------
.cd_into:
    mov al, 'd'
    call fs_find_entry
    jc .nf

    ; ID = (LBA - 100) * 16 + slot
    sub eax, 100
    imul eax, 16
    add eax, ecx
    mov [current_dir], al

.ok:
    mov esi, fs_msg_ok
    call puts
    popa
    ret

.nf:
    mov esi, fs_err_nf
    call puts
    popa
    ret


; --- FS_READ_ENTRY ---
; Finds file metadata, reads its data sector and prints exactly size bytes
fs_read_entry:
    pusha
    mov al, 'f'
    call fs_find_entry
    jc .nf

    ; EBX -> pointer to metadata in fs_scratchpad, ECX = slot index, EAX = metadata LBA
    ; Read file size from metadata (offset +16)
    mov eax, [ebx + 16]
    mov [temp_size], eax

    ; Compute Data LBA: 200 + ((meta_lba - 100) * 16) + slot
    mov eax, [current_search_lba]
    sub eax, 100
    imul eax, 16
    add eax, ecx
    add eax, 200

    mov cl, 1
    mov edi, fs_scratchpad
    call disk_read

    ; Print exactly temp_size bytes (cap at 512)
    mov ecx, [temp_size]
    cmp ecx, 512
    jbe .print_ok
    mov ecx, 512
.print_ok:
    test ecx, ecx
    jz .print_done
    mov esi, fs_scratchpad
.print_loop:
    lodsb
    call putc
    loop .print_loop
.print_done:
    mov al, 10
    call putc
    popa
    ret

.nf:
    mov esi, fs_err_nf
    call puts
    popa
    ret

is_vec_extension:
    pusha
    mov edi, esi

    ; Find the null terminator
.find_end:
    lodsb
    test al, al
    jnz .find_end

    ; Move back 4 characters (length of ".vec")
    sub esi, 5          ; ESI was at NULL+1, so -5 puts us at the '.'

    ; Compare with ".vec"
    mov edi, vec_ext_str
    mov ecx, 4
.check:
    lodsb
    scasb
    jne .not_vec
    loop .check

    popa
    cmp eax, eax        ; Set ZF=1
    ret

.not_vec:
    popa
    or eax, 1           ; Clear ZF
    ret

vec_ext_str db ".vec"

; --- fs_load_silent ---
; IN: ESI = filename
; OUT: EDI = fs_scratchpad (loaded), CF=1 on error
fs_load_silent:
    pusha
    mov al, 'f'
    call fs_find_entry
    jc .err_silent

    ; Compute Data LBA
    mov eax, [current_search_lba]
    sub eax, 100
    imul eax, 16
    add eax, ecx
    add eax, 200

    mov cl, 1
    mov edi, fs_scratchpad
    call disk_read
    popa
    clc
    ret

.err_silent:
    popa
    stc
    ret

; --- FS_DELETE_FILE ---
fs_delete_file:
    pusha
    mov al, 'f'
    call .do_del
    popa
    ret

.do_del:
    call fs_find_entry
    jc .nf_err

    ; EBX -> metadata ptr, ECX -> slot, EAX -> meta LBA
    mov byte [ebx], 0       ; Mark metadata slot empty

    ; Write metadata sector back
    mov eax, [current_search_lba]
    mov cl, 1
    mov esi, fs_scratchpad
    call disk_write

    ; Also zero the data sector (so old data doesn't leak on reuse)
    mov eax, [current_search_lba]
    sub eax, 100
    imul eax, 16
    add eax, ecx
    add eax, 200

    ; zero scratchpad
    mov edi, fs_scratchpad
    mov ecx, 512
    xor al, al
    rep stosb

    mov cl, 1
    mov esi, fs_scratchpad
    call disk_write

    mov esi, fs_msg_ok
    call puts
    ret

.nf_err:
    mov esi, fs_err_nf
    call puts
    ret

; --- FS_DELETE_DIR ---
fs_delete_dir:
    pusha
    mov al, 'd'
    call .do_del_dir
    popa
    ret

.do_del_dir:
    call fs_find_entry
    jc .nf_err_dir

    mov byte [ebx], 0       ; Mark metadata slot empty

    mov eax, [current_search_lba]
    mov cl, 1
    mov esi, fs_scratchpad
    call disk_write

    ; Zero data sector (for consistency)
    mov eax, [current_search_lba]
    sub eax, 100
    imul eax, 16
    add eax, ecx
    add eax, 200

    mov edi, fs_scratchpad
    mov ecx, 512
    xor al, al
    rep stosb

    mov cl, 1
    mov esi, fs_scratchpad
    call disk_write

    mov esi, fs_msg_ok
    call puts
    ret

.nf_err_dir:
    mov esi, fs_err_nf
    call puts
    ret


;==================================================
; MODULE VECTOR APPLICATIONS
;==================================================

%include "vector.asm"

is_vec_file:
    push esi
    push eax

    ; Find the end of the string
.find_end:
    lodsb
    test al, al
    jnz .find_end

    ; ESI now points 1 byte past the null terminator.
    ; We need to go back 5 bytes to check ".vec" (4 chars + null)
    sub esi, 5

    ; Check ".vec"
    cmp byte [esi], '.'
    jne .no
    cmp byte [esi+1], 'v'
    jne .no
    cmp byte [esi+2], 'e'
    jne .no
    cmp byte [esi+3], 'c'
    jne .no

    pop eax
    pop esi
    test eax, eax       ; Set ZF=1 (Success)
    ret

.no:
    pop eax
    pop esi
    cmp eax, -1         ; Clear ZF (Fail)
    ret

;COMPILER FOR VECTOR SCRIPT
%include "veccompiler.asm"




; ==================================================
; VED - VECTOR EDITOR 2.0 (ENHANCED VERSION)
; ==================================================

ved:
    pusha

    ; ---------------------------------
    ; Save filename (ESI already valid)
    ; ---------------------------------
    mov [filename_ptr], esi

    ; ---------------------------------
    ; Mark editor active
    ; ---------------------------------
    mov byte [app_running], 1

    ; ---------------------------------
    ; Reset editor state
    ; ---------------------------------
    mov dword [buffer_size], 0

    ; ---------------------------------
    ; Clear screen using shell
    ; ---------------------------------
    call clear_screen

    ; ---------------------------------
    ; Print editor header
    ; ---------------------------------
    mov esi, ved_title
    call puts

    ; ---------------------------------
    ; Move cursor to row 2 (after header)
    ; ---------------------------------
    mov dword [cursor_pos], 160    ; row 2, col 0
    call update_cursor

.header:
    lodsb
    test al, al
    jz .editor_loop
    stosw
    jmp .header

.editor_loop:
    hlt

    cmp byte [key_ready], 1
    jne .editor_loop

    mov al, [last_key]
    mov ah, [last_scancode]
    mov byte [key_ready], 0

    ; ESC → save + exit
    cmp ah, 0x01
    je .exit

    ; Enter
    cmp al, 10
    je .enter

    ; Backspace
    cmp al, 8
    je .backspace

    ; Ignore non-printables
    cmp al, 32
    jl .editor_loop

    ; Store character
    mov ecx, [buffer_size]
    cmp ecx, 4095
    jge .editor_loop

    mov [file_buffer + ecx], al
    inc dword [buffer_size]

    ; Render using shell
    call putc
    jmp .editor_loop

.enter:
    mov al, 10
    mov ecx, [buffer_size]
    mov [file_buffer + ecx], al
    inc dword [buffer_size]

    call putc
    jmp .editor_loop


.backspace:
    cmp dword [buffer_size], 0
    je .editor_loop

    dec dword [buffer_size]

    mov al, 8
    call putc
    jmp .editor_loop



.exit:
    ; -----------------------------
    ; SAVE FILE ON EXIT
    ; -----------------------------
    mov eax, [buffer_size]
    mov [temp_size], eax
    mov esi, [filename_ptr]
    mov edi, file_buffer
    call fs_write_file

    ; -----------------------------
    ; Restore shell
    ; -----------------------------
    mov byte [app_running], 0
    call clear_screen
    popa
    ret


; ==================================================
; VED HELPERS
; ==================================================
; --- getc: Shared Flag Consumer ---
ved_putc:
    pusha
    mov eax, [editor_y]
    imul eax, 80
    add eax, [editor_x]
    shl eax, 1
    add eax, 0xB8000
    mov ah, 0x07
    mov [eax], ax

    inc dword [editor_x]
    cmp dword [editor_x], 80
    jl .done
    mov dword [editor_x], 0
    inc dword [editor_y]
.done:
    popa
    ret


ved_erase_char:
    pusha
    mov eax, [editor_y]
    imul eax, 80
    add eax, [editor_x]
    shl eax, 1
    add eax, 0xB8000
    mov word [eax], 0x0720
    popa
    ret


; ==================================================
; MODULE 5: UTILS
; ==================================================


; --------------------------------------------------
; clear_command_line - Clears the current command line
; --------------------------------------------------
clear_command_line:
    pusha

    ; Calculate where the command started (after the prompt)
    ; cursor_pos - cmd_len = start position
    mov eax, [cursor_pos]
    sub eax, [cmd_len]

    ; Clear cmd_len characters
    mov ecx, [cmd_len]
    test ecx, ecx
    jz .done

.clear_loop:
    ; Calculate screen position
    mov ebx, eax
    shl ebx, 1
    mov word [0xB8000 + ebx], 0x0F20  ; White space
    inc eax
    loop .clear_loop

.done:
    ; Reset cursor to beginning of cleared area
    mov eax, [cursor_pos]
    sub eax, [cmd_len]
    mov [cursor_pos], eax
    call update_cursor

    popa
    ret


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

    movzx eax, byte [current_dir]   ; EAX = current_dir (global slot index)
    cmp al, 0xFF
    je .print_root

    ; EAX = slot_index (0..N)
    ; Compute: sector_index = slot_index / 16
    ;          slot_in_sector = slot_index % 16
    xor edx, edx
    mov ebx, 16
    div ebx                ; now: EAX = sector_index, EDX = slot_in_sector

    add eax, 100           ; sector LBA = 100 + sector_index
    mov [current_search_lba], eax
    mov cl, 1
    mov edi, fs_scratchpad
    call disk_read         ; read that sector into fs_scratchpad

    ; Compute pointer = fs_scratchpad + (slot_in_sector * 32) + 1
    mov eax, edx           ; EAX = slot_in_sector
    shl eax, 5             ; *32 (slot stride is 32)
    add eax, fs_scratchpad
    add eax, 1             ; skip type byte, point at name

    mov esi, eax
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

; --- Helper: Print Integer in EAX ---
print_int:
    pusha
    mov ecx, 0              ; Digit counter
    mov ebx, 10             ; Divisor
.div_loop:
    xor edx, edx
    div ebx                 ; EAX / 10, remainder in EDX
    push edx                ; Save digit
    inc ecx
    test eax, eax
    jnz .div_loop
.print_loop:
    pop eax
    add al, '0'             ; Convert to ASCII
    call putc
    loop .print_loop
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

; --------------------------------------------------
; buffer_flip - Blasts the backbuffer to the screen
; --------------------------------------------------

buffer_flip:
    pusha
    mov esi, backbuffer
    mov edi, 0xB8000
    mov ecx, 2000        ; WORDS not DWORDS
    rep movsw
    popa
    ret


; --------------------------------------------------
; clear_backbuffer - Wipes the RAM buffer
; --------------------------------------------------
clear_backbuffer:
    pusha
    mov edi, backbuffer
    mov ax, 0x0720      ; Light gray (07) space (20)
    mov ecx, 2000
    rep stosw
    popa
    ret



; ==================================================
; CMD_DUMP_FILE — Generate FS metadata dump
; ==================================================
cmd_dump_file:
    pusha

    ; ----------------------------------
    ; Step 1: Find free filename dump, dump1...
    ; ----------------------------------
    xor ecx, ecx                  ; suffix counter

.find_name:
    mov edi, dump_name_buf
    mov esi, dump_base
    call strcpy                   ; copies "dump", EDI advanced

    test ecx, ecx
    jz .name_ready

    mov eax, ecx
    add al, '0'
    mov [dump_name_buf + 4], al
    mov byte [dump_name_buf + 5], 0

.name_ready:
    mov esi, dump_name_buf
    mov al, 'f'
    call fs_find_entry
    jc .name_free

    inc ecx
    cmp ecx, 10
    jl .find_name

.name_free:
    ; ----------------------------------
    ; Step 2: Build ASCII dump text
    ; ----------------------------------
    mov edi, fs_scratchpad
    mov dword [current_search_lba], 100

.sector_loop:
    mov eax, [current_search_lba]
    mov cl, 1
    mov edi, disk_buffer
    call disk_read

    mov ebx, disk_buffer
    mov ecx, 16                  ; slots

.slot_loop:
    cmp byte [ebx], 0
    je .next_slot

    ; Type
    mov al, [ebx]
    stosb
    mov al, ' '
    stosb

    ; Name
    lea esi, [ebx + 1]
.copy_name:
    lodsb
    test al, al
    jz .name_done
    stosb
    jmp .copy_name
.name_done:

    ; Parent ID
    mov al, ' '
    stosb
    mov al, 'P'
    stosb
    mov al, ':'
    stosb

    movzx eax, byte [ebx + 13]
    call write_dec_edi

    mov al, 10
    stosb

.next_slot:
    add ebx, 32
    loop .slot_loop

    inc dword [current_search_lba]
    cmp dword [current_search_lba], 101
    jl .sector_loop

    mov byte [edi], 0            ; null terminate

    ; ----------------------------------
    ; Step 3: Write dump file
    ; ----------------------------------
    mov eax, edi
    sub eax, fs_scratchpad
    mov [temp_size], eax

    mov esi, dump_name_buf
    mov edi, fs_scratchpad
    call fs_write_file

    popa
    ret

; --------------------------------------------------
; write_dec_edi
; IN : EAX = unsigned int
; OUT: writes ASCII decimal at [EDI], advances EDI
; PRESERVES: EBX, ECX, EDX, ESI
; --------------------------------------------------
write_dec_edi:
    push ebx
    push ecx
    push edx

    mov ebx, 10
    xor ecx, ecx

    cmp eax, 0
    jne .div_loop
    mov al, '0'
    stosb
    jmp .done

.div_loop:
    xor edx, edx
    div ebx
    push edx
    inc ecx
    test eax, eax
    jnz .div_loop

.write_loop:
    pop eax
    add al, '0'
    stosb
    loop .write_loop

.done:
    pop edx
    pop ecx
    pop ebx
    ret

; --------------------------------------------------
; strcpy
; IN : ESI = source, EDI = destination
; OUT: EDI advanced past null terminator
; --------------------------------------------------
strcpy:
.copy:
    lodsb
    stosb
    test al, al
    jnz .copy
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

taskbar_text db " Vector OS V5 | STATUS: ACTIVE | TIME: ", 0
banner       db "Vector Kernel Loaded.", 10, "Welcome devy.", 10, 0
root_name   db "root", 0
prompt_end  db ") > ", 0
cmd_lsd     db "lsd", 0      ; Add this so lsd works!
unknown      db "Unknown command.", 10, 0
cmd_rmf     db "rmf ", 0
cmd_rmd     db "rmd ", 0
help_msg    db "Commands: help, ls, lsd, mkdir, write, read, cd, rmf, rmd, clear",10, 0
cmd_help   db "help", 0
cmd_ls     db "ls", 0
cmd_mkdir  db "mkdir ", 0
cmd_write  db "write ", 0
cmd_read   db "read ", 0
cmd_cd     db "cd ", 0
dump_base   db "dump", 0
cmd_dump db "dump", 0
cmd_clear  db "clear", 0
msg_dump_header db "--- Physical Metadata LBA 100 ---", 10, 0
msg_owner_tag db "  OWNER:",0
cmd_run db "run ", 0
minimal_msg db "MINIMAL VED - Press ESC to exit", 0

; Filesystem Messages

msg_dumping     db "Reading Physical Metadata (LBA 100)...", 10, 0

; Table Formatting
msg_tab         db "    ", 0
msg_parent       db "  PARENT:", 0
msg_parent_tag  db "  P:", 0
msg_size        db "  SIZE:", 0
msg_perms       db "  PERMS:", 0
cmd_vwrite db "vwrite ",0
cmd_compile db "compile ", 0
cmd_format     db "format", 0
msg_total_wipe db "INITIATING TOTAL DISK WIPE...", 10, 0
fs_msg_done    db 10, "Disk Clean. Filesystem reset.", 10, 0
last_key      db 0
last_scancode db 0
key_ready     db 0
write_err_msg db "Usage: write name content", 10, 0
fs_err_nf     db "Not found.", 10, 0
fs_msg_ok     db "Success.", 10, 0
fs_err_full   db "Disk full!", 10, 0
cmd_edit  db "edit ", 0  ; Add this with your other command strings
vec_info_msg db "VEC file: entry offset = ",0
vec_bad_msg  db "Not a valid .vec file",10,0
buffer_size    dd 0

editor_x dd 0
editor_y dd 0
edit_buffer times 4096 db 0
app_running   db 0
ved_title db "Vector Editor (ESC to exit, F5 to save)", 10, "---------------------------------------", 10, 0
save_msg db 10, "File saved.", 10, 0
saved_cursor dd 0
saved_esp dd 0
cursor_x dd 0
cursor_y dd 0
debug_header db "VEC Editor Debug - Press keys, ESC to exit", 10, "Scancodes shown in hex", 10, 0
scancode_msg db "Last scancode: 0x", 0
ascii_msg db "  ASCII: 0x", 0
got_scancode_msg db "Got scancode: 0x", 0
got_ascii_msg db "  ASCII: 0x", 0

ved_cursor dd 0
MAX_LINES     equ 100
LINE_LENGTH   equ 80

    ; Editor strings
ved_header      db "Vector Editor 2.0 | F1: Help | ESC: Save & Exit", 0
ved_status_prefix db "Pos: ", 0
ved_help        db "Arrows: Move | Enter: New line | Backspace: Delete | Tab: Indent | ESC: Exit", 0

    ; Syntax highlighting keywords
syntax_keywords:
    db "print", 0
    db "set", 0
    db "add", 0
    db "sub", 0
    db "sleep", 0
    db "if", 0
    db "else", 0
    db "while", 0
    db "for", 0
    db "input", 0
    db 0  ; End marker



align 4096
idt resb 2048

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

cmd_buffer      resb 128
fs_ptr_content  resd 1
;temp data
fs_scratchpad      resb 1024    ; The 512-byte buffer for disk I/O
current_search_lba resd 1      ; To store the current LBA being searched
temp_owner         resb 1      ; Metadata storage
temp_perms         resb 1      ; Metadata storage
temp_size          resd 1      ; Metadata storage
temp_type          resb 1      ; Metadata storage
temp_name_ptr      resd 1      ; Pointer to the filename string
temp_content_ptr resb 1
dump_name_buf resb 16
disk_buffer      resb 512
ram_disk_file_map resb 512
ram_disk_dir_map  resb 512
ram_disk_data     resb 8192
backbuffer     resb 4000
cmd_pending resb 1
file_buffer    resb 4096
echo_needed     resb 1
backspace_needed resb 1
newline_needed  resb 1

line_buffer      resb MAX_LINES * LINE_LENGTH
line_lengths     resb MAX_LINES
total_lines      resd 1
current_line     resd 1
cursor_col       resd 1
cursor_row       resd 1
screen_top_line  resd 1
dirty_flag       resb 1

    ; Colors
color_normal     resb 1
color_status     resb 1
color_line_num   resb 1
color_cursor     resb 1

    ; File operations
filename_ptr     resd 1

ved_stack resb 4096
ved_stack_top:

stack           resb 8192
stack_top:
