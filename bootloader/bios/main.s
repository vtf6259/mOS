org 0x7C00
bits 16

%define ENDL 0x0D, 0x0A

; Buffer base addresses. FAT_BASE is referenced by both the FAT loader in
; `main` and the FAT12 entry lookup in `fat_next`; keep them in sync here or
; the cluster chain resolves to garbage.
%define FAT_BASE 0x0500
%define ROOT_BASE 0x7E00

; Where STAGE2.BIN is loaded, and the IP we hand off with.
; Must NOT be 0x0000: physical 0 holds the IVT and BIOS data area, and an
; int 13h transfer to 0:0000 corrupts state SeaBIOS still needs - the call
; never returns. Must also stay clear of STACK_TOP, which grows down from it.
; MUST MATCH STAGE2_ORIGIN in bootloader/bios/stage2.s, which uses it to
; rebase its own entry jump.
%define STAGE2_BASE 0x8000
%define STACK_TOP  0x7C00

; -----------------------------------------------------------------------------
; FAT12 Boot Sector - read-only loader.
; Finds STAGE2.BIN in the root directory, follows its FAT12 cluster chain,
; loads it at physical STAGE2_BASE, then jumps to it. stage2 normalizes CS to
; 0 itself while preserving the physical address.
; stage2 owns FAT write support later; this code only reads.
;
; Memory map while loading (all real-mode, ES always 0):
;   0x0000-0x04FF: IVT + BIOS data area - do not touch
;   0x0500-0x16FF: first FAT copy (9 sectors, read-only use)
;   0x7C00-0x7DFF: this boot sector
;   0x7E00-0x99FF: root directory (14 sectors)
;   0x8000-0x????: STAGE2.BIN destination (grows up from STAGE2_BASE)
; Stack: SS=0, SP=STACK_TOP (grows down, away from everything above).
; The root directory buffer overlaps 0x8000 once stage2 is loaded, which is
; harmless: the root directory is only needed by `.scan`, which has already
; finished by then.
; -----------------------------------------------------------------------------

jmp short start
nop

; --- FAT12 BIOS Parameter Block (must stay byte-identical to the image) ---
bdb_oem:                    db 'MSWIN4.1'           ; 8 bytes
bdb_bytes_per_sector:       dw 512
bdb_sectors_per_cluster:    db 1
bdb_reserved_sectors:       dw 1
bdb_fat_count:              db 2
bdb_dir_entries_count:      dw 0E0h                 ; 224 root entries
bdb_total_sectors:          dw 2880                 ; 2880 * 512 = 1.44MB
bdb_media_descriptor_type:  db 0F0h                 ; F0 = 3.5" floppy
bdb_sectors_per_fat:        dw 9
bdb_sectors_per_track:      dw 18
bdb_heads:                  dw 2
bdb_hidden_sectors:         dd 0
bdb_large_sector_count:     dd 0

; --- Extended Boot Record ---
ebr_drive_number:           db 0                    ; filled in from DL at boot
                            db 0                    ; reserved
ebr_signature:              db 29h
ebr_volume_id:              db 12h, 34h, 56h, 78h
ebr_volume_label:           db 'MOS BOOT   '        ; 11 bytes
ebr_system_id:              db 'FAT12   '           ; 8 bytes

start:
    jmp main

; -----------------------------------------------------------------------------
; puts - print zero-terminated string at DS:SI via BIOS teletype.
; -----------------------------------------------------------------------------
puts:
    push si
    push ax
    push bx

.loop:
    lodsb                                       ; AL = [DS:SI++]
    or al, al
    jz .done
    mov ah, 0x0E
    mov bh, 0
    int 0x10
    jmp .loop

.done:
    pop bx
    pop ax
    pop si
    ret

; -----------------------------------------------------------------------------
; lba_to_chs - convert LBA in AX to CHS for int 0x13.
; OUT: CH = cylinder (low 8 bits; fine, floppy has 80), CL = sector (1-based),
;      DH = head, DL = boot drive. Preserves AX and BX.
; -----------------------------------------------------------------------------
lba_to_chs:
    push ax
    push bx
    xor dx, dx
    div word [bdb_sectors_per_track]            ; AX = LBA/spt, DX = LBA%spt
    inc dx
    mov cx, dx                                  ; CL = sector number
    xor dx, dx
    div word [bdb_heads]                        ; AX = cylinder, DX = head
    mov dh, dl                                  ; DH = head
    mov ch, al                                  ; CH = cylinder
    mov dl, [ebr_drive_number]                  ; DL = drive
    pop bx
    pop ax
    ret

; -----------------------------------------------------------------------------
; disk_read_one - read one 512-byte sector via BIOS int 0x13, 3 retries.
; IN:  AX = LBA, ES:BX = destination buffer. OUT: CF = 1 on failure.
; Preserves all registers and flags-safe (CF is the only intended output).
; Requires DS = 0 (reads BPB/EBR by absolute address) and DF = 0.
; -----------------------------------------------------------------------------
disk_read_one:
    pusha
    push es
    mov di, 3                                   ; retry counter

.retry:
    call lba_to_chs                             ; CH/CL/DH/DL from AX
    mov ah, 0x02                                ; BIOS: read sectors
    mov al, 1
    int 0x13
    jnc .ok
    dec di
    jz .fail
    mov dl, [ebr_drive_number]                  ; reset disk system
    xor ah, ah
    int 0x13
    jmp .retry

.fail:
    stc
    jmp .done

.ok:
    clc

.done:
    pop es
    popa                                        ; popa leaves flags alone, CF survives
    ret

; -----------------------------------------------------------------------------
; fat_next - follow one FAT12 cluster link.
; IN:  DX = current cluster. OUT: DX = next cluster (0xFF8+ = end of chain).
; Reads the FAT copy buffered at 0x0000:FAT_BASE. Requires ES = 0.
; FAT12 packs two 12-bit entries per 3 bytes at byte offset cluster*3/2:
; even clusters live in the low 12 bits, odd clusters in the high 12 bits.
; -----------------------------------------------------------------------------
fat_next:
    push bx
    push ax
    mov ax, dx
    add ax, dx
    add ax, dx                                  ; AX = cluster * 3
    shr ax, 1                                   ; AX = byte offset into FAT
    add ax, FAT_BASE                            ; AX = absolute offset of entry
    mov bx, ax
    mov ax, [bx]                                ; load the 16-bit window
    test dx, 1
    jz .even
    shr ax, 4                                   ; odd cluster: high 12 bits
    jmp .out
.even:
    and ax, 0x0FFF                              ; even cluster: low 12 bits
.out:
    mov dx, ax
    pop ax
    pop bx
    ret

; -----------------------------------------------------------------------------
; disk_error - print message and halt.
; -----------------------------------------------------------------------------
disk_error:
    mov si, msg_disk_error
    call puts
    ; fall through to halt

halt:
    cli
    hlt
    jmp halt

msg_disk_error: db 'Disk read error!', ENDL, 0
msg_not_found:  db 'STAGE2.BIN not found!', ENDL, 0
filename:       db 'STAGE2  BIN'                 ; FAT 8.3: "STAGE2" + "BIN"

; -----------------------------------------------------------------------------
; main - load STAGE2.BIN and jump to it.
; -----------------------------------------------------------------------------
main:
    xor ax, ax
    mov ds, ax                                  ; DS = 0: absolute BPB addressing
    mov es, ax                                  ; ES = 0: absolute buffers
    mov ss, ax
    mov sp, STACK_TOP                         ; stack grows down from boot sector
    mov [ebr_drive_number], dl                  ; BIOS boot drive number
    cld                                         ; forward string ops (cmpsb below)

    mov bx, [bdb_bytes_per_sector]              ; BX = bytes/sector, kept

    ; ---- root directory LBA = reserved + fats * sectors_per_fat ----
    mov al, [bdb_fat_count]
    xor ah, ah
    mul word [bdb_sectors_per_fat]
    add ax, [bdb_reserved_sectors]
    push ax                                     ; [bottom] root LBA

    ; ---- root directory size in sectors = (entries * 32) / bytes/sector ----
    mov ax, [bdb_dir_entries_count]
    mov cx, 32
    mul cx                                      ; DX:AX = entries*32 (DX = 0)
    div bx                                      ; AX = root sector count
    push ax                                     ; [top] root sector count

    ; ---- load root directory to 0x0000:ROOT_BASE, one sector at a time ----
    mov bp, ROOT_BASE                             ; buffer pointer (ES = 0)
    pop si                                      ; SI = sectors left
    pop ax                                      ; AX = root LBA
    push ax                                     ; keep root LBA for data_start calc
    push si                                     ; keep count for data_start calc

.load_root:
    mov bx, bp
    push ax
    push si
    push bp
    call disk_read_one
    pop bp
    pop si
    pop ax
    jc disk_error
    add bp, [bdb_bytes_per_sector]
    inc ax
    dec si
    jnz .load_root

    ; ---- scan the 32-byte root entries for "STAGE2  BIN" ----
    mov cx, [bdb_dir_entries_count]
    mov di, ROOT_BASE                           ; ES:DI = first entry

.scan:
    push cx
    push di
    mov si, filename                            ; DS:SI = wanted name
    mov cx, 11
    repe cmpsb                                  ; flags survive the pops below
    pop di
    pop cx
    je .found
    add di, 32
    loop .scan

    mov si, msg_not_found
    call puts
    jmp halt

.found:
    ; `pop di` above restored DI to the *start* of the entry, so index the
    ; entry from its base. FstClusLO lives at offset 26 of a 32-byte
    ; directory entry (0-10 name, 11 attr, 12-25 timestamps, 26-27 first
    ; cluster low word, 28-31 size).
    mov dx, [es:di+26]
    push dx                                     ; [top] first cluster

    ; ---- load first FAT copy to 0x0000:FAT_BASE ----
    mov ax, [bdb_reserved_sectors]              ; FAT starts after reserved area
    mov cx, [bdb_sectors_per_fat]
    mov bp, FAT_BASE

.load_fat:
    mov bx, bp
    push ax
    push cx
    push bp
    call disk_read_one
    pop bp
    pop cx
    pop ax
    jc disk_error
    add bp, [bdb_bytes_per_sector]
    inc ax
    loop .load_fat

    ; ---- data area LBA = root LBA + root sectors; stack: LBA, count, cluster ----
    pop dx                                      ; DX = current cluster
    pop cx                                      ; CX = root sectors
    pop ax                                      ; AX = root LBA
    add ax, cx
    mov si, ax                                  ; SI = data area LBA (constant)
    mov bp, STAGE2_BASE                         ; ES:BP = load destination

.cluster:
    ; LBA = data_start + (cluster - 2) * sectors_per_cluster
    push dx                                     ; save cluster (mul clobbers DX)
    mov ax, dx
    sub ax, 2
    xor cx, cx
    mov cl, [bdb_sectors_per_cluster]
    mul cx                                      ; AX = (cluster-2)*spc, DX = 0
    add ax, si
    xor ch, ch
    mov cl, [bdb_sectors_per_cluster]           ; CX = sectors to read

.sector:
    push ax
    push cx
    mov bx, bp
    call disk_read_one
    pop cx
    pop ax
    jc disk_error
    add bp, [bdb_bytes_per_sector]
    inc ax
    loop .sector

    pop dx                                      ; restore cluster
    call fat_next                               ; DX = next cluster
    cmp dx, 0x0FF8
    jb .cluster                                 ; 0xFF8+ = end of FAT12 chain

    ; ---- hand off: stage2_entry normalizes CS itself, just far-jump to it ----
    jmp 0x0000:STAGE2_BASE

; --- boot signature ---
times 510-($-$$) db 0
dw 0AA55h
