typedef unsigned char  u8;
typedef unsigned short u16;

void cpu_halt(void);

#pragma aux cpu_halt = \
    "cli"                \
    "halt_loop:"         \
    "hlt"                \
    "jmp halt_loop";

void stage2_cmain(void)
{
    volatile u8 __far *vram;

    vram = (volatile u8 __far *)0xB8000000UL;

    vram[0] = 'W';
    vram[1] = 0x0F;

    for (;;) {}
}
