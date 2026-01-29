nasm -f bin kernel.asm -o kernel.bin
Start-Sleep -Seconds 1

nasm -f bin boot.asm -o boot.bin
Start-Sleep -Seconds 1

cmd /c "copy /b boot.bin + kernel.bin os.img"
Start-Sleep -Seconds 1

qemu-system-i386 -fda os.img
