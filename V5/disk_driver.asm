; ==================================================
; MODULE: FIXED DISK DRIVER (32-BIT ATA PIO)
; ==================================================

; --------------------------------------------------
; DISK_WAIT
; Description: Polls the status register until the
;              drive is ready for data transfer.
; --------------------------------------------------
; CF = 0 → DRQ ready
; CF = 1 → error / timeout
disk_wait:
    mov dx, 0x1F7
    mov ecx, 100000

.retry:
    in al, dx

    test al, 0x01          ; ERR
    jnz .fail

    test al, 0x80          ; BSY
    jnz .spin

    test al, 0x08          ; DRQ
    jnz .ok

.spin:
    dec ecx
    jnz .retry

.fail:
    stc                    ; failure
    ret

.ok:
    clc                    ; success
    ret



; --------------------------------------------------
; DISK_READ
; Inputs:  EAX = LBA Address
;          CL  = Number of sectors to read
;          EDI = Destination buffer address
; --------------------------------------------------
disk_read:
    cli
    pusha
    mov ebx, eax          ; Save LBA for later bits

    ; 1. Setup LBA High & Drive Select
    mov dx, 0x1F6
    shr eax, 24           ; Get bits 24-27
    or al, 0xE0           ; 0xE0 = Master Drive + LBA mode
    out dx, al

    ; 2. Sector Count
    mov dx, 0x1F2
    mov al, cl
    out dx, al

    ; 3. LBA Low, Mid, High
    mov eax, ebx          ; Restore original EAX
    mov dx, 0x1F3
    out dx, al            ; LBA Low (0-7)

    mov dx, 0x1F4
    shr eax, 8
    out dx, al            ; LBA Mid (8-15)

    mov dx, 0x1F5
    shr eax, 16
    out dx, al            ; LBA High (16-23)

    ; 4. Send Read Command (0x20)
    mov dx, 0x1F7
    mov al, 0x20
    out dx, al

    ; 5. Data Transfer Loop
    movzx ecx, cl         ; Use ECX as sector loop counter
.sector_loop:
    push ecx
    call disk_wait
    jc .abort_read         ; ❗ DO NOT insw if DRQ not ready

    mov ecx, 256
    mov dx, 0x1F0
    rep insw

    pop ecx
    loop .sector_loop
    jmp .done

.abort_read:
    pop ecx ; Repeat for all sectors

.done:
    popa
    sti
    ret

; --------------------------------------------------
; DISK_WRITE
; Inputs:  EAX = LBA Address
;          CL  = Number of sectors to write
;          ESI = Source buffer address
; --------------------------------------------------
disk_write:
    pusha
    mov ebx, eax

    ; 1. Setup LBA High & Drive Select
    mov dx, 0x1F6
    shr eax, 24
    or al, 0xE0
    out dx, al

    ; 2. Sector Count
    mov dx, 0x1F2
    mov al, cl
    out dx, al

    ; 3. LBA Low, Mid, High
    mov eax, ebx
    mov dx, 0x1F3
    out dx, al
    mov dx, 0x1F4
    shr eax, 8
    out dx, al
    mov dx, 0x1F5
    shr eax, 16
    out dx, al

    ; 4. Send Write Command (0x30)
    mov dx, 0x1F7
    mov al, 0x30
    out dx, al

    ; 5. Data Transfer Loop
    movzx ecx, cl
.sector_loop:
    push ecx
    call disk_wait        ; Wait for DRQ before sending data

    mov ecx, 256          ; 256 words
    mov dx, 0x1F0
    rep outsw             ; Send data from [DS:ESI]

    pop ecx
    loop .sector_loop

    ; 6. Cache Flush (Important for modern drives/emulators)
    mov dx, 0x1F7
    mov al, 0xE7
    out dx, al

.wait_flush:
    in al, dx
    test al, 0x80
    jnz .wait_flush

    popa
    ret
