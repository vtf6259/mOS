# AGENTS.md

Hobby x86 OS in 16-bit real mode. NASM (boot sector) + Open Watcom C (stage2) linked
into a 1.44MB FAT12 floppy image. Nine tracked files, no README, no tests, no CI —
`just all` succeeding *and* the image booting is the entire verification story.

## Commands (all must run from repo root)

- `just all` — `out/boot.bin`, `out/bootloader/stage2.bin`, `out/main_floppy.img`.
- `just bootloader` — same minus the `kernel` TODO stub; use while iterating on stage2.
- `just run` — `all` then `qemu-system-x86_64 -fda out/main_floppy.img`. It boots the
  **floppy image**, not `out/boot.bin`.
- `just --dry-run all` — expands recipes without building.
- `bochs` with no args — picks up `bochsrc.bxrc` (32MB, `1_44=out/main_floppy.img`,
  log to `bochsout.txt`, `display_library: win32`). This is the interactive debugging
  path; the QEMU target passes no `-s`/serial flags.

Repo root matters: `wlink @bootloader/bios/stage2.lnk` runs with CWD at root and every
path inside the `.lnk` is root-relative.

## Toolchain (all must be on PATH)

`nasm`, `wcc`/`wlink` (Open Watcom; host tools here live in `BINNT64`), `mformat`/`mcopy`
(mtools), `truncate` (GNU coreutils — Windows has no builtin), `qemu-system-x86_64`, `just`.

## Justfile gotchas

- Recipe lines are indented with **TABs**. `just` aborts with "inconsistent leading
  whitespace" on the first space-indented line.
- Every recipe that touches files branches on `os_family()` between PowerShell
  (`Move-Item`, `[IO.File]::ReadAllBytes`, `Get-Content`) and `sh` (`mv`, `dd`, `awk`).
  Keep **both** branches working when editing a recipe.
- `wcc ... stage2.c` drops `stage2.obj` in the repo root (CWD), not next to the source;
  the recipe moves it into `out/bootloader/`.
- `Warning! W1014: stack segment not found` from wlink is **expected and benign**:
  output is `format raw bin`, nothing sets a stack segment because stage2.s sets
  `SS=0 / SP=0x7C00` itself.
- The `.sym` post-processing step strips the map file's `+` local-symbol marker. It has
  two independent regex implementations (PowerShell + `awk`) that must produce identical
  output. Nothing in the repo consumes `.sym`; it is for an external debugger.

## The 0x8000 load-address contract

Changing where stage2 lives requires edits in **two** files, and one comment in
`main.s` will send you to a third place that no longer exists:

- `bootloader/bios/main.s` — `%define STAGE2_BASE 0x8000`, the far-jump target.
- `bootloader/bios/stage2.lnk` — `option offset=0x8000`; this is what makes
  `jmp 0x0000:stage2_start` in stage2.s resolve correctly.
- The comment in `main.s` saying "MUST MATCH `STAGE2_ORIGIN` in `stage2.s`" is **stale** —
  that define was removed when the linker took over the offset.

Memory map while the boot sector loads (all comments already in `main.s`, keep them true):
IVT/BDA `0x0000-0x04FF` (never load here or int 13h corrupts SeaBIOS state and never
returns), FAT copy `0x0500`, boot sector + stack top `0x7C00`, root dir `0x7E00-0x99FF`,
stage2 destination `0x8000+`. The root-dir buffer overlapping `0x8000` is intentional.

## Watcom C conventions (not portable ISO C)

- Entry point is `stage2_entry` (NASM, `stage2.s`) → `stage2_cmain_`. There is no `main`
  and no CRT startup.
- Symbol decoration differs by kind: C functions get a **trailing** underscore
  (`stage2_cmain_`), C globals a **leading** one (`_cursorX`). NASM `EXTERN`/`GLOBAL`
  names are undecorated. Use the decorated name when calling a C function from asm.
- Inline asm is `_asm { ... }`; far pointers use Watcom's `far` keyword
  (`(volatile u16 far *)0xB8000000UL`). No other compiler can build this file, so
  you cannot unit-test or lint it on the host.
- `-zl` links no default libraries, which is why `strlen`/`itoa` are hand-written in
  `stage2.c` instead of `<string.h>`.
- `WCC_FLAGS := "-q -0 -ml -s -zl"` at the top of the Justfile is the single place to
  change codegen flags; `-0` restricts output to 8086 instructions.
- Watcom is C89: declarations must precede statements in a block (see the comment
  above `clearScreen`'s body).

## Current state

- Boot sector is a complete, working FAT12 loader: reads the root directory, scans for
  the 8.3 entry `STAGE2  BIN`, follows the cluster chain, loads it at `0x8000`, far-jumps.
  It only reads; `main.s` notes stage2 is meant to own FAT *writes* later.
- stage2 clears the VGA text buffer at `0xB8000`, prints `Hello, World!`, exercises
  newline + column-wrapping using the width returned by `int 10h AH=0Fh`, prints 0..79,
  then parks in `cli`/`hlt`.
- `kernel/` exists on disk (`kernel/hal/bios/`) but is empty and untracked; `just kernel`
  only echoes `TODO: implement kernel`. Don't look for kernel source — there is none.
- There is no `mFS-documentation.md`. Only an 11-byte emacs backup `mFS-documentation.md~`
  exists, and `*~` is gitignored.
- Gitignored: `out/`, editor backups (`*~`, `\#*\#`), `bochsout.txt`, `bx_enh_dbg.ini`.