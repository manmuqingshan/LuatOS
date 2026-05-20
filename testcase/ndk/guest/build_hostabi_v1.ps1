# build_hostabi_v1.ps1
# Builds the NDK host ABI test fixture guest binary

$ErrorActionPreference = "Stop"

$guestDir = "$PSScriptRoot\hostabi_v1"
$outputDir = "$PSScriptRoot\..\ndk_hostabi_basic\scripts"
$outputBin = "$outputDir\hostabi_v1.bin"

# Find RISC-V toolchain
$compiler = $null
$objcopy = $null
$compilerArgs = @()

# Try riscv32-unknown-elf-gcc first
if (Get-Command riscv32-unknown-elf-gcc -ErrorAction SilentlyContinue) {
    $compiler = "riscv32-unknown-elf-gcc"
    $objcopy = "riscv32-unknown-elf-objcopy"
    $compilerArgs = @("-march=rv32ima", "-mabi=ilp32", "-nostdlib", "-nostartfiles")
    Write-Host "[build] Using riscv32-unknown-elf toolchain"
}
# Try riscv64-unknown-elf-gcc as fallback with -march=rv32i
elseif (Get-Command riscv64-unknown-elf-gcc -ErrorAction SilentlyContinue) {
    $compiler = "riscv64-unknown-elf-gcc"
    $objcopy = "riscv64-unknown-elf-objcopy"
    $compilerArgs = @("-march=rv32ima", "-mabi=ilp32", "-nostdlib", "-nostartfiles")
    Write-Host "[build] Using riscv64-unknown-elf toolchain (32-bit mode)"
}
# Try LLVM clang as fallback
elseif (Get-Command clang -ErrorAction SilentlyContinue) {
    $compiler = "clang"
    $objcopy = "llvm-objcopy"
    $compilerArgs = @("--target=riscv32", "-march=rv32ima", "-mabi=ilp32", "-nostdlib", "-Os", "-fno-builtin")
    Write-Host "[build] Using LLVM clang toolchain"
}
elseif (Test-Path "C:\LLVM\bin\clang.exe") {
    $compiler = "C:\LLVM\bin\clang.exe"
    $objcopy = "C:\LLVM\bin\llvm-objcopy.exe"
    $compilerArgs = @("--target=riscv32", "-march=rv32ima", "-mabi=ilp32", "-nostdlib", "-Os", "-fno-builtin")
    Write-Host "[build] Using LLVM clang toolchain (C:\LLVM\bin)"
}
else {
    Write-Error "RISC-V toolchain not found. Install riscv32-unknown-elf-gcc, riscv64-unknown-elf-gcc, or LLVM clang"
    exit 1
}

# Create output directory if needed
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Build the ELF file
Write-Host "[build] Compiling main.c and ndk_stubs.c..."
$elfFile = "$guestDir\hostabi_v1.elf"
$allArgs = $compilerArgs + @(
    "-T", "$guestDir\linker.ld",
    "-o", $elfFile,
    "$guestDir\main.c",
    "$guestDir\ndk_stubs.c"
)
& $compiler $allArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "Compilation failed"
    exit 1
}

# Extract binary
Write-Host "[build] Extracting binary..."
& $objcopy -O binary $elfFile $outputBin

if ($LASTEXITCODE -ne 0) {
    Write-Error "Binary extraction failed"
    exit 1
}

$size = (Get-Item $outputBin).Length
Write-Host "[build] Success: hostabi_v1.bin ($size bytes)"
Write-Host "[build] Output: $outputBin"
