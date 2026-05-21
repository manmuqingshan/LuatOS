# build_hostabi_v1.ps1
# Builds the NDK host ABI test fixture guest binary (legacy and RV32C variants)

$ErrorActionPreference = "Stop"

$guestDir = "$PSScriptRoot\hostabi_v1"
$outputDir = "$PSScriptRoot\..\ndk_hostabi_basic\scripts"
$outputBin = "$outputDir\hostabi_v1.bin"
$outputBinRvc = "$outputDir\hostabi_v1_rvc.bin"

# Find RISC-V toolchain
$compiler = $null
$objcopy = $null
$objdump = $null
$compilerArgs = @()
$compilerArgsRvc = @()

# Try riscv32-unknown-elf-gcc first
if (Get-Command riscv32-unknown-elf-gcc -ErrorAction SilentlyContinue) {
    $compiler = "riscv32-unknown-elf-gcc"
    $objcopy = "riscv32-unknown-elf-objcopy"
    $objdump = "riscv32-unknown-elf-objdump"
    $compilerArgs = @("-march=rv32ima_zicsr", "-mabi=ilp32", "-nostdlib", "-nostartfiles")
    $compilerArgsRvc = @("-march=rv32imac_zicsr", "-mabi=ilp32", "-nostdlib", "-nostartfiles")
    Write-Host "[build] Using riscv32-unknown-elf toolchain"
}
# Try riscv64-unknown-elf-gcc as fallback with -march=rv32i
elseif (Get-Command riscv64-unknown-elf-gcc -ErrorAction SilentlyContinue) {
    $compiler = "riscv64-unknown-elf-gcc"
    $objcopy = "riscv64-unknown-elf-objcopy"
    $objdump = "riscv64-unknown-elf-objdump"
    $compilerArgs = @("-march=rv32ima_zicsr", "-mabi=ilp32", "-nostdlib", "-nostartfiles")
    $compilerArgsRvc = @("-march=rv32imac_zicsr", "-mabi=ilp32", "-nostdlib", "-nostartfiles")
    Write-Host "[build] Using riscv64-unknown-elf toolchain (32-bit mode)"
}
# Try LLVM clang as fallback
elseif (Get-Command clang -ErrorAction SilentlyContinue) {
    $compiler = "clang"
    $objcopy = "llvm-objcopy"
    $objdump = "llvm-objdump"
    $compilerArgs = @("--target=riscv32", "-march=rv32ima_zicsr", "-mabi=ilp32", "-nostdlib", "-Os", "-fno-builtin")
    $compilerArgsRvc = @("--target=riscv32", "-march=rv32imac_zicsr", "-mabi=ilp32", "-nostdlib", "-Os", "-fno-builtin")
    Write-Host "[build] Using LLVM clang toolchain"
}
elseif (Test-Path "C:\LLVM\bin\clang.exe") {
    $compiler = "C:\LLVM\bin\clang.exe"
    $objcopy = "C:\LLVM\bin\llvm-objcopy.exe"
    $objdump = "C:\LLVM\bin\llvm-objdump.exe"
    $compilerArgs = @("--target=riscv32", "-march=rv32ima_zicsr", "-mabi=ilp32", "-nostdlib", "-Os", "-fno-builtin")
    $compilerArgsRvc = @("--target=riscv32", "-march=rv32imac_zicsr", "-mabi=ilp32", "-nostdlib", "-Os", "-fno-builtin")
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

# Build the legacy ELF file (rv32ima_zicsr)
Write-Host "[build] Compiling legacy variant (rv32ima_zicsr)..."
$elfFile = "$guestDir\hostabi_v1.elf"
$allArgs = $compilerArgs + @(
    "-T", "$guestDir\linker.ld",
    "-o", $elfFile,
    "$guestDir\main.c",
    "$guestDir\ndk_stubs.c"
)
& $compiler $allArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "Legacy compilation failed"
    exit 1
}

# Extract binary
Write-Host "[build] Extracting legacy binary..."
& $objcopy -O binary $elfFile $outputBin

if ($LASTEXITCODE -ne 0) {
    Write-Error "Legacy binary extraction failed"
    exit 1
}

$size = (Get-Item $outputBin).Length
Write-Host "[build] Success: hostabi_v1.bin ($size bytes)"

# Build the RV32C ELF file (rv32imac_zicsr)
Write-Host "[build] Compiling RV32C variant (rv32imac_zicsr)..."
$elfFileRvc = "$guestDir\hostabi_v1_rvc.elf"
$allArgsRvc = $compilerArgsRvc + @(
    "-T", "$guestDir\linker.ld",
    "-o", $elfFileRvc,
    "$guestDir\main.c",
    "$guestDir\ndk_stubs.c",
    "$guestDir\rvc_smoke.S"
)
& $compiler $allArgsRvc

if ($LASTEXITCODE -ne 0) {
    Write-Error "RV32C compilation failed"
    exit 1
}

# Verify RV32C binary contains compressed instructions (before extraction)
Write-Host "[build] Verifying compressed instructions..."
$disasm = & $objdump -d -M no-aliases $elfFileRvc 2>&1 | Out-String
if ($disasm -notmatch '\bc\.') {
    Write-Error "RV32C binary does not contain compressed instructions (c. mnemonic not found in disassembly)"
    exit 1
}
$cInstructionCount = ([regex]::Matches($disasm, '\bc\.')).Count
Write-Host "[build] Verified: found $cInstructionCount c. mnemonic(s) in disassembly"

# Extract binary
Write-Host "[build] Extracting RV32C binary..."
& $objcopy -O binary $elfFileRvc $outputBinRvc

if ($LASTEXITCODE -ne 0) {
    Write-Error "RV32C binary extraction failed"
    exit 1
}

$sizeRvc = (Get-Item $outputBinRvc).Length
Write-Host "[build] Success: hostabi_v1_rvc.bin ($sizeRvc bytes)"
Write-Host "[build] Output: $outputBin"
Write-Host "[build] Output: $outputBinRvc"
