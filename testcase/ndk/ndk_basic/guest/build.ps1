#!/usr/bin/env pwsh
# Build script for RISC-V baremetal guest firmware
# Supports GNU toolchain (preferred) and LLVM/Clang fallback

$ErrorActionPreference = "Stop"

# === Configuration ===
$SOURCE_FILE = "main.c"
$ASM_FILE_RVC = "rvc_smoke.S"
$LINKER_SCRIPT = "link.ld"
$BUILD_DIR = "build"
$ELF_OUTPUT = "$BUILD_DIR\baremetal.elf"
$BIN_OUTPUT = "$BUILD_DIR\baremetal.bin"
$MAP_OUTPUT = "$BUILD_DIR\baremetal.map"
$ELF_OUTPUT_RVC = "$BUILD_DIR\baremetal_rvc.elf"
$BIN_OUTPUT_RVC = "$BUILD_DIR\baremetal_rvc.bin"
$MAP_OUTPUT_RVC = "$BUILD_DIR\baremetal_rvc.map"

# Target sync locations
$SYNC_TARGET_1 = "..\scripts\baremetal.bin"
$SYNC_TARGET_1_RVC = "..\scripts\baremetal_rvc.bin"
$SYNC_TARGET_2 = "..\..\..\..\bsp\pc\test\113.ndk_simple\baremetal.bin"
$SYNC_TARGET_2_RVC = "..\..\..\..\bsp\pc\test\113.ndk_simple\baremetal_rvc.bin"

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
    $OBJDUMP = "${Prefix}-objdump"
    
    Write-Host "Using GNU toolchain: $Prefix" -ForegroundColor Green
    
    # Compile and link legacy variant (rv32ima_zicsr)
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
    
    Write-Host "Compiling legacy variant: $GCC $($gcc_args -join ' ')"
    & $GCC $gcc_args
    if ($LASTEXITCODE -ne 0) {
        throw "Legacy compilation failed with exit code $LASTEXITCODE"
    }
    
    # Extract binary
    Write-Host "Extracting binary: $OBJCOPY -O binary $ELF_OUTPUT $BIN_OUTPUT"
    & $OBJCOPY -O binary $ELF_OUTPUT $BIN_OUTPUT
    if ($LASTEXITCODE -ne 0) {
        throw "Binary extraction failed with exit code $LASTEXITCODE"
    }
    
    # Compile and link RV32C variant (rv32imac_zicsr)
    $gcc_args_rvc = @(
        "-march=rv32imac_zicsr",
        "-mabi=ilp32",
        "-ffreestanding",
        "-nostdlib",
        "-fno-stack-protector",
        "-fdata-sections",
        "-ffunction-sections",
        "-Os",
        "-g",
        "-Wl,-T,$LINKER_SCRIPT",
        "-Wl,-Map,$MAP_OUTPUT_RVC",
        "-Wl,--gc-sections",
        "-o", $ELF_OUTPUT_RVC,
        $SOURCE_FILE,
        $ASM_FILE_RVC
    )
    
    Write-Host "Compiling RV32C variant: $GCC $($gcc_args_rvc -join ' ')"
    & $GCC $gcc_args_rvc
    if ($LASTEXITCODE -ne 0) {
        throw "RV32C compilation failed with exit code $LASTEXITCODE"
    }
    
    # Verify RV32C binary contains compressed instructions (before extraction)
    Write-Host "Verifying compressed instructions..."
    $disasm = & $OBJDUMP -d -M no-aliases $ELF_OUTPUT_RVC 2>&1 | Out-String
    if ($disasm -notmatch '\bc\.') {
        throw "RV32C binary does not contain compressed instructions (c. mnemonic not found in disassembly)"
    }
    $cInstructionCount = ([regex]::Matches($disasm, '\bc\.')).Count
    Write-Host "Verified: found $cInstructionCount c. mnemonic(s) in disassembly" -ForegroundColor Green
    
    # Extract binary
    Write-Host "Extracting binary: $OBJCOPY -O binary $ELF_OUTPUT_RVC $BIN_OUTPUT_RVC"
    & $OBJCOPY -O binary $ELF_OUTPUT_RVC $BIN_OUTPUT_RVC
    if ($LASTEXITCODE -ne 0) {
        throw "RV32C binary extraction failed with exit code $LASTEXITCODE"
    }
    
    return
}

function Build-With-LLVM {
    Write-Host "Using LLVM/Clang toolchain" -ForegroundColor Yellow
    
    # Compile and link legacy variant with Clang
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
    
    Write-Host "Compiling legacy variant: clang $($clang_args -join ' ')"
    & clang $clang_args
    if ($LASTEXITCODE -ne 0) {
        throw "Legacy compilation failed with exit code $LASTEXITCODE"
    }
    
    # Extract binary
    Write-Host "Extracting binary: llvm-objcopy -O binary $ELF_OUTPUT $BIN_OUTPUT"
    & llvm-objcopy -O binary $ELF_OUTPUT $BIN_OUTPUT
    if ($LASTEXITCODE -ne 0) {
        throw "Binary extraction failed with exit code $LASTEXITCODE"
    }
    
    # Compile and link RV32C variant with Clang
    $clang_args_rvc = @(
        "--target=riscv32-unknown-elf",
        "-fuse-ld=lld",
        "-fno-stack-protector",
        "-fdata-sections",
        "-ffunction-sections",
        "-g",
        "-Os",
        "-march=rv32imac_zicsr",
        "-mabi=ilp32",
        "-mno-relax",
        "-static",
        "-T", $LINKER_SCRIPT,
        "-nostdlib",
        "-Wl,--no-relax",
        "-Wl,--gc-sections",
        "-Wl,-Map=$MAP_OUTPUT_RVC",
        "-o", $ELF_OUTPUT_RVC,
        $SOURCE_FILE,
        $ASM_FILE_RVC
    )
    
    Write-Host "Compiling RV32C variant: clang $($clang_args_rvc -join ' ')"
    & clang $clang_args_rvc
    if ($LASTEXITCODE -ne 0) {
        throw "RV32C compilation failed with exit code $LASTEXITCODE"
    }
    
    # Verify RV32C binary contains compressed instructions (before extraction)
    Write-Host "Verifying compressed instructions..."
    $disasm = & llvm-objdump -d -M no-aliases $ELF_OUTPUT_RVC 2>&1 | Out-String
    if ($disasm -notmatch '\bc\.') {
        throw "RV32C binary does not contain compressed instructions (c. mnemonic not found in disassembly)"
    }
    $cInstructionCount = ([regex]::Matches($disasm, '\bc\.')).Count
    Write-Host "Verified: found $cInstructionCount c. mnemonic(s) in disassembly" -ForegroundColor Green
    
    # Extract binary
    Write-Host "Extracting binary: llvm-objcopy -O binary $ELF_OUTPUT_RVC $BIN_OUTPUT_RVC"
    & llvm-objcopy -O binary $ELF_OUTPUT_RVC $BIN_OUTPUT_RVC
    if ($LASTEXITCODE -ne 0) {
        throw "RV32C binary extraction failed with exit code $LASTEXITCODE"
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
if (-not (Test-Path $ELF_OUTPUT_RVC)) {
    throw "Build failed: $ELF_OUTPUT_RVC not generated"
}
if (-not (Test-Path $BIN_OUTPUT_RVC)) {
    throw "Build failed: $BIN_OUTPUT_RVC not generated"
}
if (-not (Test-Path $MAP_OUTPUT_RVC)) {
    throw "Build failed: $MAP_OUTPUT_RVC not generated"
}

$bin_size = (Get-Item $BIN_OUTPUT).Length
$bin_size_rvc = (Get-Item $BIN_OUTPUT_RVC).Length
Write-Host "`n=== Build successful ===" -ForegroundColor Green
Write-Host "  Legacy ELF: $ELF_OUTPUT"
Write-Host "  Legacy BIN: $BIN_OUTPUT ($bin_size bytes)"
Write-Host "  Legacy MAP: $MAP_OUTPUT"
Write-Host "  RV32C ELF:  $ELF_OUTPUT_RVC"
Write-Host "  RV32C BIN:  $BIN_OUTPUT_RVC ($bin_size_rvc bytes)"
Write-Host "  RV32C MAP:  $MAP_OUTPUT_RVC"

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
    
    Write-Host "  Copying legacy to: $target_abs"
    Copy-Item -Path $BIN_OUTPUT -Destination $target_abs -Force
}

foreach ($target in @($SYNC_TARGET_1_RVC, $SYNC_TARGET_2_RVC)) {
    $target_abs = (Resolve-Path $target -ErrorAction SilentlyContinue).Path
    if (-not $target_abs) {
        # Target doesn't exist yet, create parent directory
        $target_dir = Split-Path $target -Parent
        if ($target_dir -and -not (Test-Path $target_dir)) {
            New-Item -ItemType Directory -Path $target_dir -Force | Out-Null
        }
        $target_abs = (Resolve-Path $target_dir).Path + "\" + (Split-Path $target -Leaf)
    }
    
    Write-Host "  Copying RV32C to: $target_abs"
    Copy-Item -Path $BIN_OUTPUT_RVC -Destination $target_abs -Force
}

Write-Host "`n=== All done! ===" -ForegroundColor Green
Write-Host "Guest binary rebuilt and synced successfully."
