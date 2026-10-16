# AGENTS.md

Hobby x86 OS: 16-bit real-mode BIOS bootloader (NASM + Open Watcom C), built into a 1.44MB FAT12 floppy image. No tests, no CI — a successful build is the verification step.

## Commands

- `just all` — build everything: `out/boot.bin` (boot sector), `out/bootloader/stage2.bin`, and `out/main_floppy.img` (FAT12 image with boot sector patched in + `STAGE2.BIN` copied to root). Run from repo root.
- `just run` — `all` + `qemu-system-x86_64 -hda out/boot.bin`. Note: it boots `boot.bin` directly as a hard disk, **not** `out/main_floppy.img`.
- `just --dry-run all` — fast parse/expand check without building.

## Required tools (all must be on PATH)

`nasm`, `wcc`/`wlink` (Open Watcom), `mformat`/`mcopy` (mtools), `truncate` (GNU coreutils — non-obvious on Windows), `qemu-system-x86_64`, `just`.

## Justfile gotchas

- **Recipe lines must be indented with TABs**, not spaces. `just` fails with "inconsistent leading whitespace" on the first mixed line.
- The Justfile is cross-platform: `[windows]` sets a PowerShell shell, and recipes branch on `os_family()` between PowerShell/`Move-Item`/`ReadAllBytes` and `sh`/`mv`/`dd`. Keep **both** branches working when editing a recipe.
- `wcc ... stage2.c` writes `stage2.obj` into the **repo root**; the recipe then moves it to `out/bootloader/`. `wlink @bootloader/bios/stage2.lnk` runs with CWD at repo root — all paths in the `.lnk` are relative to repo root.
- `Warning! W1014: stack segment not found` from wlink is **expected and benign**: output is `format raw bin` and the stack is set manually in `stage2.s` (`SS=0`, `SP=0x7C00`) before calling into C.

## Codebase facts

- `bootloader/bios/main.s` — boot sector (`org 0x7C00`), FAT12 BPB, currently prints a string and halts; it does **not** chain-load stage2 yet.
- `bootloader/bios/stage2.s` — NASM entry, sets up segments/stack, calls `stage2_cmain_`.
- `bootloader/bios/stage2.c` — Open Watcom-specific C: `__far` pointers and `#pragma aux` inline asm, compiled `-0` (8086), small model, `-zl` (no default libs). Not portable ISO C.
- Current status: stage2 writes `'W'` to VRAM then spins; `just kernel` is a TODO stub; `mFS-documentation.md` is an empty placeholder.
- `out/` and editor backups (`*~`) are gitignored.
