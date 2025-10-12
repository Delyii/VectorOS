; VectorOS Bootloader
[BITS 16]
[ORG 0x7C00]

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti

    mov [boot_drive], dl

    ; Display loading message
    mov si, loading_msg
    call print_string

    ; Load kernel (16 sectors = 8KB)
    mov ah, 0x02
    mov al, 16          ; Load enough sectors for kernel + filesystem
    mov ch, 0
    mov cl, 2           ; Start from sector 2
    mov dh, 0
    mov dl, [boot_drive]
    mov bx, 0x7E00      ; Load at 0x7E00
    int 0x13
    jc disk_error

    ; Jump to kernel
    mov si, success_msg
    call print_string
    jmp 0x7E00

disk_error:
    mov si, error_msg
    call print_string
    jmp $

print_string:
    pusha
    mov ah, 0x0E
.print_loop:
    lodsb
    cmp al, 0
    je .done
    int 0x10
    jmp .print_loop
.done:
    popa
    ret

loading_msg db 'Loading VectorOS...', 0x0D, 0x0A, 0
success_msg db 'Kernel loaded!', 0x0D, 0x0A, 0
error_msg db 'Disk error!', 0x0D, 0x0A, 0
boot_drive db 0

times 510-($-$$) db 0
dw 0xAA55
