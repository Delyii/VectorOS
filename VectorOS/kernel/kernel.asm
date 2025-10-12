; VectorOS Kernel with File Creation and Reading
[BITS 16]
[ORG 0x7E00]

kernel_start:
    ; Set up segments
    mov ax, 0
    mov ds, ax
    mov es, ax

    ; Clear screen
    mov ax, 0x0003
    int 0x10

    ; Display welcome message
    mov si, welcome_msg
    call print_string

    ; Initialize filesystem
    call init_vectorfs

    ; Display prompt and start main loop
    call display_prompt
    jmp main_loop

; ==========================================================================
; MAIN COMMAND LOOP
; ==========================================================================

main_loop:
    ; Get input from user
    mov di, input_buffer
    call get_input

    ; Process command
    call process_command

    ; Display prompt again
    call display_prompt
    jmp main_loop

get_input:
    pusha
    mov cx, 0
.input_loop:
    mov ah, 0x00
    int 0x16

    cmp al, 0x0D
    je .input_done
    cmp al, 0x08
    je .backspace
    cmp cx, 63
    jge .input_loop

    mov [di], al
    inc di
    inc cx
    mov ah, 0x0E
    int 0x10
    jmp .input_loop

.backspace:
    cmp cx, 0
    je .input_loop
    dec di
    dec cx
    mov ah, 0x0E
    mov al, 0x08
    int 0x10
    mov al, ' '
    int 0x10
    mov al, 0x08
    int 0x10
    jmp .input_loop

.input_done:
    mov byte [di], 0
    call newline
    popa
    ret

process_command:
    pusha
    mov si, input_buffer

    ; Convert to uppercase
    call to_uppercase

    ; Simple string comparisons - NO function calls in between!
    mov si, input_buffer

    ; HELP command
    mov di, cmd_help
    call compare_string
    jc .help

    ; INFO command
    mov di, cmd_info
    call compare_string
    jc .info

    ; CLEAR command
    mov di, cmd_clear
    call compare_string
    jc .clear

    ; POWEROFF command
    mov di, cmd_poweroff
    call compare_string
    jc .poweroff

    ; LS command
    mov di, cmd_ls
    call compare_string
    jc .ls

    ; VECTOR command
    mov di, cmd_vector
    call compare_string
    jc .vector

    ; VREAD command - check if starts with "VREAD"
    mov di, cmd_vread
    call compare_string_prefix
    jc .vread

    ; UNKNOWN command
    jmp .unknown

.help:
    mov si, help_msg
    call print_string
    jmp .done

.info:
    mov si, info_msg
    call print_string
    jmp .done

.clear:
    mov ax, 0x0003
    int 0x10
    jmp .done

.poweroff:
    mov si, shutdown_msg
    call print_string
    jmp $

.ls:
    call list_vectors
    jmp .done

.vector:
    call parse_vector_create
    jmp .done

.vread:
    call parse_vread_simple
    jmp .done

.unknown:
    mov si, unknown_msg
    call print_string

.done:
    popa
    ret
; ==========================================================================
; COMMAND PARSING
; ==========================================================================

parse_vector_create:
    pusha
    mov si, input_buffer
    add si, 7       ; Skip "VECTOR "

    ; Check if we have a filename
    cmp byte [si], 0
    je .no_filename

    ; Extract filename
    mov di, filename_buffer
    call extract_filename

    ; Look for content (after space)
    call skip_spaces
    cmp byte [si], 0
    je .no_content

    ; We have content!
    mov di, file_content_buffer
    call extract_content

    ; Create file with content
    mov si, filename_buffer
    mov di, file_content_buffer
    call create_vector_with_content
    jmp .done

.no_filename:
    ; Create default file
    mov si, default_filename
    mov di, default_content
    call create_vector_with_content
    jmp .done

.no_content:
    ; Create file with default content
    mov si, filename_buffer
    mov di, default_content
    call create_vector_with_content

.done:
    popa
    ret

parse_vread:
    pusha
    mov si, input_buffer
    add si, 5       ; Skip "VREAD"

    ; Skip space after VREAD
    cmp byte [si], ' '
    jne .no_filename
    inc si

    ; Check if we have a filename
    cmp byte [si], 0
    je .no_filename

    ; Extract filename
    mov di, filename_buffer
    call extract_filename

    ; Check if filename is empty
    cmp byte [filename_buffer], 0
    je .no_filename

    ; Read and display file
    mov si, filename_buffer
    call read_vector
    jmp .done

.no_filename:
    mov si, vread_usage_msg
    call print_string

.done:
    popa
    ret

extract_filename:
    pusha
.loop:
    mov al, [si]
    cmp al, ' '
    je .done
    cmp al, 0
    je .done
    mov [di], al
    inc si
    inc di
    jmp .loop
.done:
    mov byte [di], 0
    popa
    ret

extract_content:
    pusha
    mov cx, 0
.loop:
    mov al, [si]
    cmp al, 0
    je .done
    mov [di], al
    inc si
    inc di
    inc cx
    cmp cx, 128     ; Max content length
    jge .done
    jmp .loop
.done:
    mov byte [di], 0
    popa
    ret

skip_spaces:
    pusha
.loop:
    mov al, [si]
    cmp al, ' '
    jne .done
    inc si
    jmp .loop
.done:
    popa
    ret

; ==========================================================================
; VECTOR FILESYSTEM WITH CONTENT
; ==========================================================================

; File structure with content
struc vector_file
    .name      resb 8
    .size      resw 1
    .sector    resw 1
    .components resb 1
    .content   resb 128  ; File content storage
    .reserved  resb 20
endstruc

init_vectorfs:
    pusha
    mov si, fs_init_msg
    call print_string

    ; Initialize file table
    mov di, file_table
    mov cx, MAX_FILES * vector_file_size
    xor al, al
    rep stosb

    ; Create a welcome file
    mov si, welcome_filename
    mov di, welcome_content
    call create_vector_with_content

    popa
    ret

create_vector_with_content:
    ; SI = filename, DI = content
    pusha
    mov bx, file_table
    mov cx, MAX_FILES

.search_loop:
    cmp byte [bx], 0
    je .found_slot
    add bx, vector_file_size
    loop .search_loop

    mov si, no_space_msg
    call print_string
    popa
    ret

.found_slot:
    ; Copy filename
    push bx
    push di
    mov cx, 8
.copy_name:
    mov al, [si]
    mov [bx], al
    inc si
    inc bx
    loopnz .copy_name
    pop di
    pop bx

    ; Copy content
    push bx
    add bx, vector_file.content
    mov cx, 0
.copy_content:
    mov al, [di]
    mov [bx], al
    inc di
    inc bx
    inc cx
    cmp byte [di], 0
    je .content_done
    cmp cx, 127
    jl .copy_content
.content_done:
    mov byte [bx], 0
    pop bx

    ; Set file properties
    mov word [bx + vector_file.size], cx
    mov ax, [next_sector]
    mov [bx + vector_file.sector], ax
    mov byte [bx + vector_file.components], 1

    ; Update next sector
    inc ax
    mov [next_sector], ax

    mov si, file_created_msg
    call print_string

    ; Print filename
    push bx
    mov si, bx
    call print_string
    mov si, with_content_msg
    call print_string
    pop bx

    popa
    ret

read_vector:
    ; SI = filename to read
    pusha
    mov bx, file_table
    mov cx, MAX_FILES

.search_loop:
    cmp byte [bx], 0
    je .next_file

    ; Compare filenames properly
    push si
    push bx
    push cx
    mov di, bx
    mov cx, 8
.compare_loop:
    mov al, [si]
    cmp al, 0
    je .check_padding
    mov ah, [di]
    cmp al, ah
    jne .not_match
    inc si
    inc di
    loop .compare_loop
    jmp .match_found

.check_padding:
    ; Input filename ended, check if rest is spaces
    mov ah, [di]
    cmp ah, ' '
    jne .not_match
    inc di
    loop .check_padding

.match_found:
    pop cx
    pop bx
    pop si
    jmp .found_file

.not_match:
    pop cx
    pop bx
    pop si

.next_file:
    add bx, vector_file_size
    dec cx
    jnz .search_loop

    ; File not found
    mov si, file_not_found_msg
    call print_string
    jmp .done

.found_file:
    ; Display file content
    mov si, reading_msg
    call print_string
    push bx
    mov si, bx
    call print_string
    mov si, colon_msg
    call print_string
    call newline

    ; Print content
    pop bx
    mov si, bx
    add si, vector_file.content
    call print_string
    call newline

.done:
    popa
    ret

list_vectors:
    pusha
    mov si, vector_header
    call print_string

    mov bx, file_table
    mov cx, MAX_FILES

.list_loop:
    cmp byte [bx], 0
    je .next_file

    ; Print filename
    push bx
    mov si, bx
    call print_string

    ; Print size
    mov si, size_prefix
    call print_string
    mov ax, [bx + vector_file.size]
    call print_decimal

    ; Print preview
    mov si, preview_prefix
    call print_string
    mov si, bx
    add si, vector_file.content
    call print_preview
    call newline
    pop bx

.next_file:
    add bx, vector_file_size
    loop .list_loop

    popa
    ret

print_preview:
    pusha
    mov cx, 20    ; Preview length
.preview_loop:
    mov al, [si]
    cmp al, 0
    je .done
    mov ah, 0x0E
    int 0x10
    inc si
    loop .preview_loop
    mov si, ellipsis_msg
    call print_string
.done:
    popa
    ret

read_vector_direct:
    ; BX = file entry
    pusha
    mov si, reading_msg
    call print_string
    mov si, bx
    call print_string
    mov si, colon_msg
    call print_string
    call newline

    mov si, bx
    add si, vector_file.content
    call print_string
    call newline
    popa
    ret

; ==========================================================================
; UTILITY FUNCTIONS
; ==========================================================================

print_string:
    pusha
    mov ah, 0x0E
.loop:
    lodsb
    cmp al, 0
    je .done
    int 0x10
    jmp .loop
.done:
    popa
    ret

print_decimal:
    pusha
    mov bx, 10
    mov cx, 0
.convert:
    xor dx, dx
    div bx
    push dx
    inc cx
    test ax, ax
    jnz .convert
.print:
    pop ax
    add al, '0'
    mov ah, 0x0E
    int 0x10
    loop .print
    popa
    ret

newline:
    pusha
    mov ah, 0x0E
    mov al, 0x0D
    int 0x10
    mov al, 0x0A
    int 0x10
    popa
    ret

display_prompt:
    pusha
    mov si, prompt
    call print_string
    popa
    ret

to_uppercase:
    pusha
.loop:
    mov al, [si]
    cmp al, 0
    je .done
    cmp al, 'a'
    jb .next
    cmp al, 'z'
    ja .next
    sub byte [si], 0x20
.next:
    inc si
    jmp .loop
.done:
    popa
    ret

compare_string:
    pusha
.loop:
    mov al, [si]
    mov bl, [di]
    cmp al, bl
    jne .not_equal
    cmp al, 0
    je .equal
    inc si
    inc di
    jmp .loop
.equal:
    stc
    jmp .done
.not_equal:
    clc
.done:
    popa
    ret

compare_string_prefix:
    ; Compare if SI starts with DI
    pusha
.loop:
    mov al, [di]
    cmp al, 0
    je .match
    mov bl, [si]
    cmp al, bl
    jne .no_match
    inc si
    inc di
    jmp .loop
.match:
    stc
    jmp .done
.no_match:
    clc
.done:
    popa
    ret

    parse_vread_simple:
    pusha
    mov si, input_buffer
    add si, 5       ; Skip "VREAD"

    ; Skip space
    cmp byte [si], ' '
    jne .error
    inc si

    ; Use the rest as filename
    mov di, filename_buffer
    call extract_to_end

    ; Read the file
    mov si, filename_buffer
    call read_vector_simple
    jmp .done

.error:
    mov si, vread_usage_msg
    call print_string

.done:
    popa
    ret

extract_to_end:
    pusha
.loop:
    mov al, [si]
    cmp al, 0
    je .done
    mov [di], al
    inc si
    inc di
    jmp .loop
.done:
    mov byte [di], 0
    popa
    ret

read_vector_simple:
    ; SI = filename to find
    pusha
    mov bx, file_table
    mov cx, MAX_FILES

.search:
    cmp byte [bx], 0
    je .next

    ; Simple comparison - just first few chars
    push si
    push bx
    mov di, bx
    mov cx, 8
.check:
    mov al, [si]
    cmp al, 0
    je .found
    mov ah, [di]
    cmp al, ah
    jne .not_found
    inc si
    inc di
    loop .check
    jmp .found

.not_found:
    pop bx
    pop si
    jmp .next

.found:
    pop bx
    pop si

    ; Found it - print content
    mov si, reading_msg
    call print_string
    push bx
    mov si, bx
    call print_string
    mov si, colon_msg
    call print_string
    call newline

    pop bx
    mov si, bx
    add si, vector_file.content
    call print_string
    call newline
    jmp .done

.next:
    add bx, vector_file_size
    loop .search

    ; Not found
    mov si, file_not_found_msg
    call print_string

.done:
    popa
    ret
; ==========================================================================
; DATA SECTION
; ==========================================================================

; Messages
welcome_msg db 'VectorOS v1.0 - File System Ready', 0x0D, 0x0A, 0
prompt db 'vectorOS> ', 0
help_msg db 'Commands: help, info, clear, poweroff, ls, vector, vread filename', 0x0D, 0x0A, 0
info_msg db 'VectorOS Vec1 - With File Content System', 0x0D, 0x0A, 0
shutdown_msg db 'Shutting down...', 0x0D, 0x0A, 0
unknown_msg db 'Unknown command', 0x0D, 0x0A, 0
vread_usage_msg db 'Usage: vread-FILENAME', 0x0D, 0x0A, 0
cmd_test db 'TESTREAD', 0
cmd_first db 'FIRST', 0

; Filesystem messages
fs_init_msg db 'VectorFS with content storage ready', 0x0D, 0x0A, 0
vector_header db 'Vectors:', 0x0D, 0x0A, 0
file_created_msg db 'Vector created: ', 0
with_content_msg db ' with content', 0x0D, 0x0A, 0
no_space_msg db 'No space for new vector', 0x0D, 0x0A, 0
magnitude_msg db 'Magnitude calculated', 0x0D, 0x0A, 0
dot_msg db 'Dot product', 0x0D, 0x0A, 0
cross_msg db 'Cross product', 0x0D, 0x0A, 0
normalize_msg db 'Normalized', 0x0D, 0x0A, 0
reading_msg db 'Reading vector: ', 0
colon_msg db ':', 0
file_not_found_msg db 'Vector not found', 0x0D, 0x0A, 0
size_prefix db ' (', 0
preview_prefix db '): "', 0
ellipsis_msg db '..."', 0

; Commands
cmd_help db 'HELP', 0
cmd_info db 'INFO', 0
cmd_clear db 'CLEAR', 0
cmd_poweroff db 'POWEROFF', 0
cmd_ls db 'LS', 0
cmd_vector db 'VECTOR', 0
cmd_vread db 'VREAD', 0
cmd_magnitude db 'MAGNITUDE', 0
cmd_dot db 'DOT', 0
cmd_cross db 'CROSS', 0
cmd_normalize db 'NORMALIZE', 0

; Default data
welcome_filename db 'WELCOME ', 0
welcome_content db 'Welcome to VectorOS! This is your first vector file.', 0
default_filename db 'NEWFILE ', 0
default_content db 'Default vector content', 0

; Filesystem data
MAX_FILES equ 8
  ; Increased for content storage
file_table times MAX_FILES * vector_file_size db 0
next_sector dw 100

; Buffers
input_buffer times 64 db 0
filename_buffer times 12 db 0
file_content_buffer times 128 db 0

; Pad kernel to appropriate size
times (16*512)-($-kernel_start) db 0
