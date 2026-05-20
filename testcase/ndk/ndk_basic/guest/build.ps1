#!/usr/bin/env pwsh
# Build script for RISC-V baremetal guest firmware
# Supports GNU toolchain (preferred) and LLVM/Clang fallback

$ErrorActionPreference = "Stop"

# === Configuration ===
$SOURCE_FILE = "main.c"
$LINKER_SCRIPT = "link.ld"
$BUILD_DIR = "build"
$ELF_OUTPUT = "$BUILD_DIR\baremetal.elf"
$BIN_OUTPUT = "$BUILD_DIR\baremetal.bin"
$MAP_OUTPUT = "$BUILD_DIR\baremetal.map"

# Target sync locations
$SYNC_TARGET_1 = "..\scripts\baremetal.bin"
$SYNC_TARGET_2 = "..\..\..\..\bsp\pc\test\113.ndk_simple\baremetal.bin"

# === Helper Functions ===
function Test-Command {
    param([string]$Command)
    try {
        $null = Get-Command $Command -ErrorAction Stop
        return $true
    } catch {
        return $false
    }
}

function Build-With-GNU {
    param([string]$Prefix)
    
    $GCC = "${Prefix}-gcc"
    $OBJCOPY = "${Prefix}-objcopy"
    
    Write-Host "Using GNU toolchain: $Prefix" -ForegroundColor Green
    
    # Compile and link
    $gcc_args = @(
        "-march=rv32ima_zicsr",
        "-mabi=ilp32",
        "-ffreestanding",
        "-nostdlib",
        "-fno-stack-protector",
        "-fdata-sections",
        "-ffunction-sections",
        "-Os",
        "-g",
        "-Wl,-T,$LINKER_SCRIPT",
        "-Wl,-Map,$MAP_OUTPUT",
        "-Wl,--gc-sections",
        "-o", $ELF_OUTPUT,
        $SOURCE_FILE
    )
    
    Write-Host "Compiling: $GCC $($gcc_args -join ' ')"
    & $GCC $gcc_args
    if ($LASTEXITCODE -ne 0) {
        throw "Compilation failed with exit code $LASTEXITCODE"
    }
    
    # Extract binary
    Write-Host "Extracting binary: $OBJCOPY -O binary $ELF_OUTPUT $BIN_OUTPUT"
    & $OBJCOPY -O binary $ELF_OUTPUT $BIN_OUTPUT
    if ($LASTEXITCODE -ne 0) {
        throw "Binary extraction failed with exit code $LASTEXITCODE"
    }
    
    return
}

function Build-With-LLVM {
    Write-Host "Using LLVM/Clang toolchain" -ForegroundColor Yellow
    
    # Compile and link with Clang
    $clang_args = @(
        "--target=riscv32-unknown-elf",
        "-fuse-ld=lld",
        "-fno-stack-protector",
        "-fdata-sections",
        "-ffunction-sections",
        "-g",
        "-Os",
        "-march=rv32ima_zicsr",
        "-mabi=ilp32",
        "-mno-relax",
        "-static",
        "-T", $LINKER_SCRIPT,
        "-nostdlib",
        "-Wl,--no-relax",
        "-Wl,--gc-sections",
        "-Wl,-Map=$MAP_OUTPUT",
        "-o", $ELF_OUTPUT,
        $SOURCE_FILE
    )
    
    Write-Host "Compiling: clang $($clang_args -join ' ')"
    & clang $clang_args
    if ($LASTEXITCODE -ne 0) {
        throw "Compilation failed with exit code $LASTEXITCODE"
    }
    
    # Extract binary
    Write-Host "Extracting binary: llvm-objcopy -O binary $ELF_OUTPUT $BIN_OUTPUT"
    & llvm-objcopy -O binary $ELF_OUTPUT $BIN_OUTPUT
    if ($LASTEXITCODE -ne 0) {
        throw "Binary extraction failed with exit code $LASTEXITCODE"
    }
    
    return
}

# === Main Build Logic ===
Write-Host "=== Building RISC-V Baremetal Guest ===" -ForegroundColor Cyan

# Ensure we're in the guest directory
if (-not (Test-Path $SOURCE_FILE)) {
    throw "Error: $SOURCE_FILE not found. Please run this script from the guest directory."
}

if (-not (Test-Path $LINKER_SCRIPT)) {
    throw "Error: $LINKER_SCRIPT not found. Please run this script from the guest directory."
}

# Create build directory
if (-not (Test-Path $BUILD_DIR)) {
    New-Item -ItemType Directory -Path $BUILD_DIR | Out-Null
}

# Toolchain detection priority: GNU riscv64 > GNU riscv32 > GNU riscv-none > LLVM
$toolchain_found = $false

if (Test-Command "riscv64-unknown-elf-gcc") {
    try {
        Build-With-GNU -Prefix "riscv64-unknown-elf"
        $toolchain_found = $true
    } catch {
        Write-Warning "GNU riscv64 toolchain found but build failed: $_"
    }
}

if (-not $toolchain_found -and (Test-Command "riscv32-unknown-elf-gcc")) {
    try {
        Build-With-GNU -Prefix "riscv32-unknown-elf"
        $toolchain_found = $true
    } catch {
        Write-Warning "GNU riscv32 toolchain found but build failed: $_"
    }
}

if (-not $toolchain_found -and (Test-Command "riscv-none-elf-gcc")) {
    try {
        Build-With-GNU -Prefix "riscv-none-elf"
        $toolchain_found = $true
    } catch {
        Write-Warning "GNU riscv-none toolchain found but build failed: $_"
    }
}

if (-not $toolchain_found) {
    if ((Test-Command "clang") -and (Test-Command "ld.lld") -and (Test-Command "llvm-objcopy")) {
        try {
            Build-With-LLVM
            $toolchain_found = $true
        } catch {
            Write-Warning "LLVM toolchain found but build failed: $_"
        }
    }
}

if (-not $toolchain_found) {
    Write-Host "`n=== ERROR: No suitable RISC-V toolchain found ===" -ForegroundColor Red
    Write-Host "Please install one of the following:" -ForegroundColor Yellow
    Write-Host "  1. GNU RISC-V toolchain (riscv64-unknown-elf-gcc, riscv32-unknown-elf-gcc, or riscv-none-elf-gcc)"
    Write-Host "  2. LLVM/Clang with RISC-V support (clang + ld.lld + llvm-objcopy)"
    Write-Host "`nSee guest\README.md for installation instructions." -ForegroundColor Yellow
    exit 1
}

# Verify outputs
if (-not (Test-Path $ELF_OUTPUT)) {
    throw "Build failed: $ELF_OUTPUT not generated"
}
if (-not (Test-Path $BIN_OUTPUT)) {
    throw "Build failed: $BIN_OUTPUT not generated"
}
if (-not (Test-Path $MAP_OUTPUT)) {
    throw "Build failed: $MAP_OUTPUT not generated"
}

$bin_size = (Get-Item $BIN_OUTPUT).Length
Write-Host "`n=== Build successful ===" -ForegroundColor Green
Write-Host "  ELF: $ELF_OUTPUT"
Write-Host "  BIN: $BIN_OUTPUT ($bin_size bytes)"
Write-Host "  MAP: $MAP_OUTPUT"

# Sync to target locations
Write-Host "`n=== Syncing binary to target locations ===" -ForegroundColor Cyan

foreach ($target in @($SYNC_TARGET_1, $SYNC_TARGET_2)) {
    $target_abs = (Resolve-Path $target -ErrorAction SilentlyContinue).Path
    if (-not $target_abs) {
        # Target doesn't exist yet, create parent directory
        $target_dir = Split-Path $target -Parent
        if ($target_dir -and -not (Test-Path $target_dir)) {
            New-Item -ItemType Directory -Path $target_dir -Force | Out-Null
        }
        $target_abs = (Resolve-Path $target_dir).Path + "\" + (Split-Path $target -Leaf)
    }
    
    Write-Host "  Copying to: $target_abs"
    Copy-Item -Path $BIN_OUTPUT -Destination $target_abs -Force
}

Write-Host "`n=== All done! ===" -ForegroundColor Green
Write-Host "Guest binary rebuilt and synced successfully."
