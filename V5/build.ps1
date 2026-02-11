# 1. Assemble the pieces
nasm -f bin boot.asm -o boot.bin
nasm -f bin kernel.asm -o kernel.bin

# 2. Check if the disk image already exists
if (!(Test-Path "vector_os.img")) {
    echo "Creating new 1MB disk image..."
    # Create a blank 1MB file
    fsutil file createnew vector_os.img 1048576
}

# 3. USE 'dd' or a hex stream to only overwrite the start of the disk
# Since standard Windows doesn't have 'dd', we'll use a temporary combined file
# but we MUST NOT wipe the whole 1MB image.
cmd /c "copy /b boot.bin + kernel.bin system_temp.bin"

# This command puts the new system code at the start of the image
# without touching the sectors at LBA 50+
$fileStream = [System.IO.File]::OpenWrite("$PWD\vector_os.img")
$bytes = [System.IO.File]::ReadAllBytes("$PWD\system_temp.bin")
$fileStream.Write($bytes, 0, $bytes.Length)
$fileStream.Close()

# 4. Clean up temp files
del boot.bin
del kernel.bin
del system_temp.bin

# 5. Run QEMU with the PERSISTENT image
qemu-system-i386 -hda vector_os.img
