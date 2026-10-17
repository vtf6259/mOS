typedef unsigned char  u8;
typedef unsigned short u16;

// Track our current cursor position explicitly
unsigned int cursorX = 0;
unsigned int cursorY = 0;

#define VGA_MEMORY ((volatile u16 far *)0xB8000000UL)

unsigned char getScreenWidth() {
    unsigned char columns;

    _asm {
        mov ah, 0Fh     ; BIOS function: Get Video State
        int 10h         ; Video interrupt
        mov columns, ah ; AH contains the number of screen columns
    }

    return columns;
}

unsigned int strlen(const char *str) {
    unsigned int len = 0;

    while (str[len])
        len++;

    return len;
}

char* itoa(int num, char* str, int base) {
    int i = 0;
    int isNegative = 0;
    int start, end;
    char temp;

    if (num == 0) {
        str[i++] = '0';
        str[i] = '\0';
        return str;
    }

    if (num < 0 && base == 10) {
        isNegative = 1;
        num = -num;
    }

    while (num != 0) {
        int rem = num % base;
        str[i++] = (rem > 9) ? (rem - 10) + 'A' : rem + '0';
        num = num / base;
    }

    if (isNegative) {
        str[i++] = '-';
    }

    str[i] = '\0';

    start = 0;
    end = i - 1;
    while (start < end) {
        temp = str[start];
        str[start] = str[end];
        str[end] = temp;
        start++;
        end--;
    }

    return str;
}

void clearScreen() {
    unsigned int i;
    unsigned int totalCells;
    unsigned int screenWidth;
    u16 clearCharacter;
    
    // Execution assignment logic happens strictly AFTER declarations
    screenWidth = (unsigned int)getScreenWidth();
    totalCells = screenWidth * 25; 

    // 0x0F = White text on Black background
    // 0x20 = ASCII value for a blank space character (' ')
    clearCharacter = (u16)((0x0F << 8) | 0x20);

    // Loop through every cell in the VGA frame buffer and blank it out
    for (i = 0; i < totalCells; i++) {
        VGA_MEMORY[i] = clearCharacter;
    }

    // Reset cursor tracking coordinates back to the top-left corner
    cursorX = 0;
    cursorY = 0;
}

void puts(const char *string) {
    unsigned int i;
    unsigned int len = strlen(string);
    unsigned int screenWidth = (unsigned int)getScreenWidth();

    for (i = 0; i < len; i++) {
        char c = string[i];

        // 1. Handle the newline character
        if (c == '\n') {
            cursorX = 0;   // Carriage return to the start of the line
            cursorY++;     // Line feed down to the next row
            continue;
        }

        // 2. Render normal text characters
        // Formula: (Y * Width) + X calculates the linear array offset
        VGA_MEMORY[(cursorY * screenWidth) + cursorX] = (u16)((0x0F << 8) | c);
        cursorX++;

        // 3. Automatic text-wrapping: If text hits the right boundary, drop down
        if (cursorX >= screenWidth) {
            cursorX = 0;
            cursorY++;
        }
        
        // Safety boundary check for the bottom of the screen (25 rows max)
        if (cursorY >= 25) {
            cursorY = 24; // Simple clamp
        }
    }
}

void stage2_cmain(void) {
  char buf[7];
  int i;
  
  clearScreen();
  puts("Hello, World!\n");
  puts("testing newline support");
  for (i = 0; i < 80; i++) {
	itoa(i, buf,10);
	puts(buf);
	puts("\n");
  }

  for (;;) {
    __asm {
        cli
        hlt
    }
  }
}
