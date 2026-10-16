BITS 16
CPU 8086

; Physical address the boot sector loads this file at. MUST MATCH
; STAGE2_BASE in bootloader/bios/main.s. main.s chain-loads us there and far
; jumps to 0x0000:STAGE2_BASE, so CS arrives as 0; we only need to force CS
; to 0 while keeping the physical execution address.
%define STAGE2_ORIGIN 0x8000

SECTION .text

GLOBAL stage2_entry
EXTERN stage2_cmain_

stage2_entry:
    cli

    ; Normalize CS to 0 while preserving physical execution address.
    jmp 0x0000:(stage2_start + STAGE2_ORIGIN)

stage2_start:
	mov ax, 0xB800
	mov es, ax
	mov word [es:0], 0x0F58
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
