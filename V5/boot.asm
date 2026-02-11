; ===============================
; Vector OS V4 Bootloader
; ===============================
; NASM syntax
; Assembled as raw binary
; Loaded by BIOS at 0x7C00

BITS 16
ORG 0x7C00

start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    ; -------------------------------
    ; Load kernel (sectors 2+)
    ; -------------------------------
    mov bx, 0x1000        ; kernel load address
    mov dh, 0             ; head
    mov dl, 0x80          ; boot drive (BIOS sets this, hardrive?)
    mov ch, 0             ; cylinder
    mov cl, 2             ; start at sector 2
    mov al, 40            ; number of sectors to read

    mov ah, 0x02
    int 0x13
    jc disk_error

    ; -------------------------------
    ; Enable A20 (fast method)
    ; -------------------------------
    in al, 0x92
    or al, 00000010b
    out 0x92, al

    ; -------------------------------
    ; Load GDT
    ; -------------------------------
    lgdt [gdt_descriptor]

    ; -------------------------------
    ; Enter protected mode
    ; -------------------------------
    mov eax, cr0
    or eax, 1
    mov cr0, eax

    jmp 0x08:protected_mode

disk_error:
    hlt
    jmp disk_error

; ===============================
; Protected Mode
; ===============================
BITS 32

protected_mode:
    mov ax, 0x10    ; Data segment selector
    mov ds, ax
    mov es, ax      ; CRITICAL: es must be valid for 'insw' to work
    mov fs, ax
    mov gs, ax
    mov ss, ax
    mov esp, 0x90000
    jmp 0x1000   ; jump to kernel

; ===============================
; GDT
; ===============================
gdt_start:
    dq 0x0000000000000000  ; null

    ; Code segment
    dq 0x00CF9A000000FFFF

    ; Data segment
    dq 0x00CF92000000FFFF

gdt_end:

gdt_descriptor:
    dw gdt_end - gdt_start - 1
    dd gdt_start

; ===============================
; Boot Signature
; ===============================
times 510-($-$$) db 0
dw 0xAA55
