Vector OS V5

A lightweight, educational x86 operating system built in assembly language. Vector OS features a custom filesystem, built-in text editor, scripting language, and command-line interface.

🚀 Overview

Vector OS V5 is a personal learning project developed over ~4-5 months of x86 assembly and OS development experience. It demonstrates core operating system concepts including protected mode switching, interrupt handling, filesystem design, device drivers, and user interface development.

    Note: This OS was developed with assistance from AI and LLMs to accelerate production. It's a personal assessment project rather than a long-term production OS.

✨ Features
Core System

    16-bit to 32-bit protected mode transition

    Custom GDT with code/data segments

    PIC remapping for interrupt management

    IDT setup with keyboard and timer handlers

    RTC (Real-Time Clock) support for time display

Filesystem

    32-byte metadata entries with type, name, permissions, owner, parent ID, and size

    Sector-based storage (metadata: LBA 100-120, data: LBA 200+)

    Hierarchical directory structure with parent/child relationships

    File operations: create, read, write, delete

    Directory operations: mkdir, cd, rmd, ls

Shell Commands
text

help     - Display available commands
ls       - List files in current directory
lsd      - List directories
mkdir    - Create a new directory
write    - Create a file with content
read     - Display file contents
cd       - Change directory (supports "cd ..")
rmf      - Delete a file
rmd      - Delete a directory
clear    - Clear the screen
edit     - Open the built-in VED editor
run      - Execute a Vector script
dump     - Generate filesystem metadata dump
format   - Wipe disk and reset filesystem
compile  - Compile Vector scripts

VED - Vector Editor

A full-screen text editor built into the OS:

    File loading and saving

    Cursor movement

    Backspace and enter handling

    ESC to save and exit

    Up to 4KB file editing

Vector Scripting Language

A simple built-in scripting language with:

    Variables (prefixed with /)

    Commands: print, set, add, sub, sleep

    Number handling and conversion

    Inline variable expansion (e.g., print Value is: /myvar)

Example Vector script:
text

set /counter 5
print /counter
add /counter 3
print "Now: /counter"

Hardware Support

    ATA PIO disk driver (read/write, cache flush)

    PS/2 keyboard driver with scancode translation

    VGA text mode (80x25, 16 colors)

    RTC time reading

    PIC interrupt controller

UI Features

    Taskbar with dynamic time display

    Cursor management and screen scrolling

    Command prompt with current directory

    Colored output

🛠️ Building and Running
Prerequisites

    NASM assembler

    QEMU (for emulation)

    Windows PowerShell (build script included)

Build Script (PowerShell)

Save as build.ps1:
powershell

# 1. Assemble the pieces
nasm -f bin boot.asm -o boot.bin
nasm -f bin kernel.asm -o kernel.bin

# 2. Check if the disk image already exists
if (!(Test-Path "vector_os.img")) {
    echo "Creating new 1MB disk image..."
    # Create a blank 1MB file
    fsutil file createnew vector_os.img 1048576
}

# 3. Combine bootloader and kernel
cmd /c "copy /b boot.bin + kernel.bin system_temp.bin"

# 4. Write to disk image (preserving existing filesystem data)
$fileStream = [System.IO.File]::OpenWrite("$PWD\vector_os.img")
$bytes = [System.IO.File]::ReadAllBytes("$PWD\system_temp.bin")
$fileStream.Write($bytes, 0, $bytes.Length)
$fileStream.Close()

# 5. Clean up temp files
del boot.bin
del kernel.bin
del system_temp.bin

# 6. Run QEMU with the PERSISTENT image
qemu-system-i386 -hda vector_os.img

Manual Build Steps
bash

nasm -f bin boot.asm -o boot.bin
nasm -f bin kernel.asm -o kernel.bin
cat boot.bin kernel.bin > os_image.bin
qemu-system-i386 -hda os_image.bin

📁 Project Structure

    boot.asm - First-stage bootloader (16-bit)

    kernel.asm - Main kernel (32-bit) with all subsystems

    disk_driver.asm - ATA PIO disk driver

    vector.asm - Vector script executor

    veccompiler.asm - Vector language interpreter

    build.ps1 - PowerShell build script

🔧 Technical Details
Memory Layout

    0x7C00 - Bootloader loaded by BIOS

    0x1000 - Kernel load address

    0x90000 - Stack top

    0xB8000 - VGA text buffer

Filesystem Layout

    LBA 0 - Boot sector

    LBA 1-99 - Reserved/Kernel

    LBA 100-120 - Metadata sectors (16 slots per sector)

    LBA 200+ - Data sectors

Metadata Entry Structure (32 bytes)
text

Offset  Field       Size  Description
0       type        1     'f'=file, 'd'=directory
1-11    name        11    Filename (null-terminated)
12      perms       1     Permissions
13      parent      1     Parent directory ID
14      owner       1     Owner ID
16-19   size        4     File size in bytes

🎯 Project Goals

This OS was created as a personal assessment project to:

    Understand x86 architecture and protected mode

    Implement a custom filesystem from scratch

    Build a complete, usable system with shell and editor

    Explore interrupt handling and device drivers

    Create a simple scripting language

It's not intended for long-term development or production use, but rather as a learning exercise and demonstration of OS development concepts.
💡 Development Notes

    Assembly-only for maximum control and learning

    AI-assisted development to accelerate implementation

    Focus on working features rather than theoretical purity

    Emphasis on practical usability (editor, scripting, filesystem)

🐛 Known Limitations

    Filesystem limited to ~320 files (20 metadata sectors × 16 slots)

    Maximum file size: 512 bytes (one sector)

    No memory protection between kernel and applications

    Limited error handling in some areas

    A20 gate uses fast method (not compatible with all hardware)

🔮 Future Possibilities

While this is primarily a learning project, potential enhancements could include:

    Multitasking and process management

    Larger files (multiple sectors)

    Proper memory management

    Network stack

    Simple GUI

📜 License

Feel free to use this code for learning purposes. Attribution appreciated but not required.

Built with: Assembly, NASM, QEMU, and a lot of coffee
Development time: ~6-7 months (including prior experience)
Lines of code: ~2000+ lines of x86 assembly
