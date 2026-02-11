; ==================================================
; VECTOR SUBSYSTEM — SCRIPT EXECUTOR
; ==================================================

; --------------------------------------------------
; vec_run
; IN : ESI = filename (null-terminated)
; --------------------------------------------------
vec_run:
    pusha
    call fs_load_silent      ; Load text into scratchpad silently
    jc .nf_error

    mov esi, fs_scratchpad
    call vec_compile         ; Execute the script

    popa
    clc                      ; Clear CF so shell knows we succeeded
    ret

.nf_error:
    mov esi, fs_err_nf
    call puts
    popa
    stc
    ret

.done:
    popa
    ret

vec_return_msg db 10, "Script execution finished.", 10, 0
