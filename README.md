# VectorOS 

Making a simple operating system written in x86 Assembly.

> **Note**: This project is being developed with assistance from AI to explore OS development concepts,I am a solo dev so its hard to program each line by hand so I take use of AI for the core so I can build upon it , I sitll have to debug , add some other features.

## Features
- **Basic Operating System**: Bootloader, kernel, and interactive shell
- **File System**: Create and read files
- **Interactive Shell**: Command-line interface
- **Simple Design**: Clean, minimal architecture

## Commands
- `help` - Show available commands
- `info` - System information  
- `clear` - Clear screen
- `ls` - List all files
- `touch` - Create new file with random content
- `read [name]` - Read file content
- `write [file name] [file content]` - Make a file with content

## Building
### Prerequisites
- NASM (Netwide Assembler)
- QEMU (for emulation)

### Build Steps
```powershell
# Assemble bootloader and kernel
nasm -f bin src/boot/boot.asm -o bin/boot.bin
nasm -f bin src/kernel/kernel.asm -o bin/kernel.bin

# Create disk image
copy /b bin/boot.bin+bin/kernel.bin bin/vectoros.img

# Run in QEMU
qemu-system-x86_64 -fda bin/vectoros.img
