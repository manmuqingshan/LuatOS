# NDK Guest Source

This directory contains the source code for the `baremetal.bin` binary used by the NDK test suite.

## Purpose

The binary at `testcase/ndk/ndk_basic/scripts/baremetal.bin` is a ~315-byte RISC-V RV32IMA flat binary. This directory exists to:

1. **Document provenance** - The binary originates from the mini-rv32ima upstream project
2. **Make behavior inspectable** - Provide readable source matching observed test behavior
3. **Enable rebuild** - Provides automated build scripts for reproducible compilation

## Build Status

✅ **The source in this directory is now the verified and active implementation:**
- Source is reconstructed from upstream mini-rv32ima project structure
- Build scripts (`build.bat` / `build.ps1`) automatically compile and sync the binary
- Rebuilt binary passes all NDK testcases (5/5 tests passed)
- Build output is automatically synced to both test locations

**Provenance verified:**
- Based on mini-rv32ima upstream (`baremetal/baremetal.c`, linker script)
- Simplified to match LuatOS NDK CSR/MMIO contract
- Test logs confirm debug messages match this source
- Exit behavior matches: `Control Store: set val to 00005555`

**Current binary characteristics:**
- Size: ~315 bytes (may vary slightly with toolchain)
- Toolchain: GNU riscv64-unknown-elf-gcc (preferred) or LLVM clang (fallback)
- Format: Flat binary loaded at 0x80000000

## Files

- **`main.c`** - C source code matching verified guest behavior
- **`link.ld`** - Linker script for flat binary at 0x80000000
- **`build.ps1`** - PowerShell build script (auto-detects toolchain, syncs binary)
- **`build.bat`** - Batch wrapper for `build.ps1`
- **`README.md`** - This file

## Build Instructions

### Automated Build (Recommended)

```powershell
cd testcase\ndk\ndk_basic\guest
cmd /c build.bat
```

The script will:
1. Auto-detect available toolchain (GNU RISC-V preferred, LLVM fallback)
2. Compile `main.c` with optimized flags
3. Extract flat binary from ELF
4. **Automatically sync** to both target locations:
   - `../scripts/baremetal.bin` (for testcase)
   - `../../../../bsp/pc/test/113.ndk_simple/baremetal.bin` (for PC quick test)

Expected output:
```
=== Building RISC-V Baremetal Guest ===
Using GNU toolchain: riscv64-unknown-elf
...
=== Build successful ===
  BIN: build\baremetal.bin (315 bytes)
...
=== Syncing binary to target locations ===
=== All done! ===
```

### Manual Build

For debugging or custom flags:

```powershell
cd testcase\ndk\ndk_basic\guest
mkdir build -ErrorAction SilentlyContinue

# GNU toolchain (preferred)
riscv64-unknown-elf-gcc -march=rv32ima_zicsr -mabi=ilp32 `
  -ffreestanding -nostdlib -fno-stack-protector `
  -fdata-sections -ffunction-sections -Os -g `
  -Wl,-T,link.ld -Wl,-Map,build\baremetal.map -Wl,--gc-sections `
  -o build\baremetal.elf main.c

riscv64-unknown-elf-objcopy -O binary build\baremetal.elf build\baremetal.bin

# Manual sync
copy build\baremetal.bin ..\scripts\baremetal.bin
copy build\baremetal.bin ..\..\..\..\bsp\pc\test\113.ndk_simple\baremetal.bin
```

### Toolchain Requirements

**Option 1: GNU RISC-V Toolchain** (preferred)
- `riscv64-unknown-elf-gcc` / `riscv64-unknown-elf-objcopy`
- OR `riscv32-unknown-elf-gcc` / `riscv32-unknown-elf-objcopy`
- OR `riscv-none-elf-gcc` / `riscv-none-elf-objcopy` (xPack toolchain)
- Download: [xPack RISC-V GCC](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases)

**Option 2: LLVM/Clang** (fallback)
- `clang` + `ld.lld` + `llvm-objcopy` with RISC-V target support
- Download: [LLVM Releases](https://releases.llvm.org/)

See `components/ndk/README.md` for detailed setup instructions.

## Provenance

This source is based on **mini-rv32ima** by CNLohr:
- **Project**: https://github.com/cnlohr/mini-rv32ima  
- **License**: MIT-x11 or NewBSD (compatible with LuatOS MIT license)
- **Original reference**: `baremetal/baremetal.c`, `baremetal/baremetal.S`, `baremetal/flatfile.lds`

The reconstruction simplifies the upstream to match only the behavior observed in LuatOS NDK tests, removing unused code paths (delay loops, assembly demo functions, timer access, etc.).

## What the Guest Does

**Observed in test logs from the checked-in binary (`scripts/baremetal.bin`):**

1. **Logs via CSR writes**:
   - CSR 0x136: `nprint` - print number
   - CSR 0x137: `pprint` - print pointer (hex)
   - CSR 0x138: `lprint` - print string (pass guest address)

2. **Debug output**:
   ```
   main is at: 0x80000014
   Buffer is at: 0x80001120
   Stack top is at: 0x8000113F
   Testing strlen optimization:
   Length of teststr1: 13
   Length of teststr2: 71
   ```

   **Note**: Addresses (e.g., `0x80000014`) vary by compiler version, optimization level, and toolchain. The message pattern and key values (`13`, `71`, `0x5555`) remain stable.

   Runtime output is emitted as separate `vm:` / `vm num:` log lines. The block above shows the logical sequence in merged form.

3. **Exits via control store**:
   - Writes `0x5555` to `SYSCON` (0x11100000)
   - Runtime logs: `Control Store: set val to 00005555`

## Memory Layout

```
0x80000000  ┌──────────────┐
            │ .text        │  Entry point + main code
            ├──────────────┤
            │ .rodata      │  String literals
            ├──────────────┤
            │ .data        │  Initialized data
            ├──────────────┤
            │ .bss         │  Uninitialized data
            ├──────────────┤
            │ .stack (4KB) │  Grows down from _sstack
            └──────────────┘
```

The LuatOS runtime allocates RAM (8-32KB) and places an exchange area at the end for host-guest data transfer. The guest binary itself doesn't use the exchange area in current tests.

## Why in testcase/ Not components/?

This is **test infrastructure**, not part of the NDK runtime:
- Tests the NDK from guest perspective
- Tightly coupled to test expectations (specific log messages)
- Belongs next to tests for context

## Related Documentation

- **NDK Runtime & Build Guide**: `components/ndk/README.md` — comprehensive zero-to-verification guide
- **Runtime Implementation**: `components/ndk/src/luat_ndk.c`  
- **CSR Handlers**: `components/ndk/src/luat_ndk_host.c`
- **Testcases**: `testcase/ndk/ndk_basic/scripts/ndk_test.lua`
