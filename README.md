🛰️ Vector OS V5

A lightweight, educational x86 operating system built entirely in Assembly language. Vector OS features a custom filesystem, user authentication, a built-in text editor, and its own scripting language.
🚀 Overview

Vector OS V5 is a personal learning project developed over ~5 months of x86 assembly exploration. It serves as a deep dive into low-level systems programming, demonstrating:

    Switching from 16-bit real mode to 32-bit protected mode.

    Interrupt Handling via PIC remapping and IDT setup.

    Custom Filesystem design and sector-based storage.

    Device Drivers for keyboard, disk (ATA PIO), and VGA.

    User Security with persistent authentication and permissions.

    Note: This project was developed with assistance from AI/LLMs to accelerate the learning curve. It is an educational assessment project rather than a production-grade OS.

✨ Core Features
🖥️ System Architecture

    Transition: 16-bit → 32-bit protected mode.

    GDT: Custom Global Descriptor Table with code and data segments.

    Interrupts: PIC remapping; IDT with keyboard and timer handlers.

    Hardware: RTC (Real-Time Clock) integration and VGA text mode interface.

🔐 User Authentication

Vector OS V5 includes a persistent login system and user permission model.

    First-boot Setup: Interactive wizard for initial configuration.

    Registry: Persistent user database stored directly on disk.

    Roles: Supports multiple users including a Root administrator (UID 0) who bypasses all permission checks.

User Record Structure (32 bytes):
Offset	Field	Size	Description
0	UID	1 Byte	Unique User ID
1	Username	11 Bytes	Account Name
12	Password	11 Bytes	Account Password
📂 Filesystem Design

The OS utilizes a custom sector-based filesystem designed for simplicity and speed.
Disk Layout
LBA Range	Content
LBA 0	Boot sector
LBA 1-99	Kernel / Reserved
LBA 50	User Registry
LBA 100-120	Metadata Sectors (Directory/File headers)
LBA 200+	File Data Sectors
Metadata Entry (32 bytes)
Offset	Field	Size	Description
0	Type	1	'f' for file, 'd' for directory
1-11	Name	11	Filename string
12	Perms	1	Permission flags
13	Parent	1	Parent directory ID
14	Owner	1	Owner UID
16-19	Size	4	File size in bytes
🛠️ Built-in Tools
⌨️ Command Line Interface

    ls / lsd: List files and directories.

    mkdir / write: Create directories and files.

    rmf / rmd: Delete files and directories.

    edit: Launch the VED (Vector Editor).

    run: Execute a Vector script.

    format: Wipe the disk and reset the filesystem.

📝 VED — Vector Editor

A fullscreen text editor supporting:

    File loading/saving to disk.

    Full cursor movement and backspace handling.

    4KB editing buffer.

    ESC to exit and save.

📜 Vector Scripting Language

A lightweight interpreted language for automation.
Bash

# Example Script
set /counter 5
print "Starting count..."
add /counter 3
print "Current value: /counter"

🔧 Technical Specifications
Memory Layout
Address	Usage
0x7C00	BIOS Bootloader load address
0x1000	Kernel load address
0x90000	System Stack
0xB8000	VGA Text Buffer (Video Memory)
Hardware Drivers

    Disk: ATA PIO driver with sector read/write and cache flushing.

    Input: PS/2 keyboard driver (Scancode → ASCII translation).

    Display: VGA text mode with scrolling and cursor control.

    Clock: RTC hardware access with BCD conversion.

🔨 Building and Running
Requirements

    NASM (Netwide Assembler)

    QEMU (i386 Emulator)

    Windows PowerShell (for the build script)

Build Script
PowerShell

# Assemble the components
nasm -f bin boot.asm -o boot.bin
nasm -f bin kernel.asm -o kernel.bin

# Create 1MB disk image if it doesn't exist
if (!(Test-Path "vector_os.img")) {
    fsutil file createnew vector_os.img 1048576
}

# Combine and write to image
cmd /c "copy /b boot.bin + kernel.bin system_temp.bin"
$fileStream = [System.IO.File]::OpenWrite("$PWD\vector_os.img")
$bytes = [System.IO.File]::ReadAllBytes("$PWD\system_temp.bin")
$fileStream.Write($bytes, 0, $bytes.Length)
$fileStream.Close()

# Run in QEMU
qemu-system-i386 -hda vector_os.img

⚠️ Limitations & Future Work

    Max Entries: Limited to ~320 filesystem entries.

    File Size: Currently limited to one sector (512 bytes).

    Tasks: Single-task execution (no multitasking yet).

    Future Goals: Implement a GUI, memory management, and networking stack.
