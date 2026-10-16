[windows]
set shell := ["powershell.exe", "-NoLogo", "-Command"]

WCC_FLAGS := "-q -0 -ms -s -zl"
all: bootloader kernel

[private]
stage1:
	{{ if os_family() == "windows" { "New-Item -ItemType Directory -Force -Path out/bootloader | Out-Null" } else { "mkdir -p out/bootloader" } }}
	nasm -f bin bootloader/bios/main.s -o out/boot.bin

[private]
stage2:
	wcc {{WCC_FLAGS}} bootloader/bios/stage2.c
	{{ if os_family() == "windows" { "Move-Item -Force stage2.obj out/bootloader/stage2.obj" } else { "mv stage2.obj out/bootloader/stage2.obj" } }}
	nasm -f obj bootloader/bios/stage2.s -o out/bootloader/stage2_start.obj
	wlink @bootloader/bios/stage2.lnk

bootloader: stage1 stage2
	truncate -s 1440k out/main_floppy.img
	mformat -i out/main_floppy.img -f 1440 ::
	{{ if os_family() == "windows" {
	"$b = [IO.File]::ReadAllBytes(\"out/boot.bin\")
	$f = [IO.File]::OpenWrite(\"out/main_floppy.img\")
	$f.Write($b, 0, 512)
	$f.Close()"
	} else {"dd if=out/boot.bin of=out/main_floppy.img bs=512 count=1 conv=notrunc"} }}
	mcopy -i out/main_floppy.img out/bootloader/stage2.bin ::STAGE2.BIN
	
kernel:
	@echo "TODO: implement kernel"
run: all
	qemu-system-x86_64 -fda out/main_floppy.img
