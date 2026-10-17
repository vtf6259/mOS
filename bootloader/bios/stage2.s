BITS 16
CPU 8086

SECTION .text

GLOBAL stage2_entry
EXTERN stage2_cmain_

stage2_entry:
    cli
    ; The linker now applies the 0x8000 offset to stage2_start automatically!
    jmp 0x0000:stage2_start

stage2_start:
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    cld
    sti

    ; Call the C entry point.
    call stage2_cmain_

.hang:
    cli
    hlt
    jmp .hang
