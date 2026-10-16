typedef unsigned char  u8;
typedef unsigned short u16;

#define VGA_MEMORY ((volatile u16 far *)0xB8000000UL)

void clearScreen() {
  _asm {
        mov ah, 06h     ; Scroll up function
        mov al, 00h     ; Clear entire window
        mov bh, 07h     ; Light gray on black
        mov ch, 00h     ; Top row
        mov cl, 00h     ; Left column
        mov dh, 24      ; Bottom row
        mov dl, 79      ; Right column
        int 10h         ; BIOS video interrupt
  }
}

void stage2_cmain(void)
{
  clearScreen();
  VGA_MEMORY[0] = (u16)((0x0F << 8) | 'H');
  VGA_MEMORY[1] = (u16)((0x0F << 8) | 'i');

  for (;;) {
	/* Halt until interrupted. */
    __asm {
        cli
        hlt
    }
  }
}
