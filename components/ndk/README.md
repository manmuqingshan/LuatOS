# ndk（RV32I 运行时）

`ndk` 用于在 LuatOS 内运行 MiniRV32IMA 镜像，并通过交换区与 Lua 侧交互。

本文档既是**运行时 API 参考**，也是**从零重建与验证指南**。

---

## 目录

1. [快速验证流程](#快速验证流程)
2. [前置依赖](#前置依赖)
3. [Guest 镜像重建](#guest-镜像重建)
4. [PC 宿主侧构建](#pc-宿主侧构建)
5. [完整验证流程（从零开始）](#完整验证流程从零开始)
6. [预期结果](#预期结果)
7. [常见问题](#常见问题)
8. [运行时 API 参考](#运行时-api-参考)
9. [CSR/MMIO 接口](#csrmmio-接口)
10. [Host ABI v1 / GPIO v2 / UART v1](#host-abi-v1--gpio-v2--uart-v1)
11. [RV32C 压缩指令支持与兼容性](#rv32c-压缩指令支持与兼容性)
12. [最小使用示例](#最小使用示例)

---

## 快速验证流程

如果你已经有了可用的构建环境，直接执行：

```powershell
# 1.
Set-Location D:\github\LuatOS\testcase\ndk\guest

# 2.
.\build_hostabi_v1.ps1

# 3.
Set-Location D:\github\LuatOS\testcase\ndk\ndk_basic\guest

# 4.
.\build.ps1

# 5.
Set-Location D:\github\LuatOS\bsp\pc

# 6.
cmd /c build_windows_32bit_msvc.bat

# 7.
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_basic\scripts\

# 8.
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_hostabi_basic\scripts\
```

期望输出：所有测试套件 `Total: N passed, 0 failed`

---

## 前置依赖

### 必需

- **操作系统**：Windows 10/11（当前仅 PC 模拟器已验证）
- **编译器**：Visual Studio 2019/2022（MSVC）或等效的 `cl.exe` 环境
- **构建工具**：[xmake](https://xmake.io) ≥ 2.7.0
- **PowerShell**：5.1+ 或 PowerShell Core 7.x

### Guest 镜像编译工具链（二选一）

仅在需要重建 `baremetal.bin` 时必需。优先级顺序：

1. **GNU RISC-V 工具链**（推荐）
   - `riscv64-unknown-elf-gcc` / `riscv64-unknown-elf-objcopy`
   - 或 `riscv32-unknown-elf-gcc` / `riscv32-unknown-elf-objcopy`
   - 或 `riscv-none-elf-gcc` / `riscv-none-elf-objcopy`（xPack 工具链）
   - 获取：[xPack RISC-V GCC](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases)、[SiFive GNU Toolchain](https://github.com/sifive/freedom-tools/releases)

2. **LLVM/Clang** with RISC-V 支持（备用）
   - `clang` + `ld.lld` + `llvm-objcopy`（需要完整的 RISC-V backend 和 LLD 链接器）
   - 获取：[LLVM 官方](https://releases.llvm.org/)，Windows 下需 RISC-V target 编译版或手动开启 target

**验证命令在 PATH 中：**

```powershell
# GNU 工具链（任意一种）
riscv64-unknown-elf-gcc --version
# 或
riscv32-unknown-elf-gcc --version
# 或
riscv-none-elf-gcc --version

# LLVM（三个命令都需要）
clang --version
ld.lld --version
llvm-objcopy --version
```

---

## Guest 镜像重建

**何时需要：** 修改了 `testcase/ndk/ndk_basic/guest/main.c` 或 `link.ld` 后。

### 自动构建（推荐）

```powershell
cd testcase\ndk\ndk_basic\guest
cmd /c build.bat
```

脚本会：
1. 自动检测可用工具链（GNU > LLVM）
2. **同时编译两个指令集变体**：
   - **RV32IMA** (`-march=rv32ima_zicsr`)：传统 32 位定宽指令
   - **RV32IMAC** (`-march=rv32imac_zicsr`)：带 C 扩展的 16/32 位混合指令（更紧凑，约节省 15-25% 代码体积）
3. **自动同步**二进制到目标位置：
   - `testcase/ndk/ndk_basic/scripts/baremetal.bin` (RV32IMA)
   - `testcase/ndk/ndk_basic/scripts/baremetal_rvc.bin` (RV32IMAC)
   - `bsp/pc/test/113.ndk_simple/baremetal.bin` (RV32IMA，快速测试用)
   - `bsp/pc/test/113.ndk_simple/baremetal_rvc.bin` (RV32IMAC，快速测试用)

### 输出产物

| 文件 | 位置 | 说明 |
|------|------|------|
| `baremetal.elf` | `guest/build/` | RV32IMA 带符号的 ELF（调试用） |
| `baremetal.bin` | `guest/build/` | RV32IMA flat binary（约 315 字节） |
| `baremetal_rvc.elf` | `guest/build/` | RV32IMAC 带符号的 ELF（调试用） |
| `baremetal_rvc.bin` | `guest/build/` | RV32IMAC flat binary（约 240-260 字节，具体大小随工具链略有变化） |
| `baremetal.map` | `guest/build/` | RV32IMA 链接映射表 |
| `baremetal_rvc.map` | `guest/build/` | RV32IMAC 链接映射表 |
| ↳ 同步到 | `../scripts/baremetal.bin` | ndk_basic 测试镜像 (RV32IMA) |
| ↳ 同步到 | `../scripts/baremetal_rvc.bin` | ndk_basic 测试镜像 (RV32IMAC) |
| ↳ 同步到 | `../../../../bsp/pc/test/113.ndk_simple/baremetal.bin` | PC 快速测试 (RV32IMA) |
| ↳ 同步到 | `../../../../bsp/pc/test/113.ndk_simple/baremetal_rvc.bin` | PC 快速测试 (RV32IMAC) |

### 手动构建（调试用）

```powershell
cd testcase\ndk\ndk_basic\guest
mkdir build -ErrorAction SilentlyContinue

# RV32IMA 变体（传统 32 位指令）
riscv64-unknown-elf-gcc -march=rv32ima_zicsr -mabi=ilp32 `
  -ffreestanding -nostdlib -fno-stack-protector `
  -fdata-sections -ffunction-sections -Os -g `
  -Wl,-T,link.ld -Wl,-Map,build\baremetal.map -Wl,--gc-sections `
  -o build\baremetal.elf main.c

riscv64-unknown-elf-objcopy -O binary build\baremetal.elf build\baremetal.bin

# RV32IMAC 变体（压缩指令）
riscv64-unknown-elf-gcc -march=rv32imac_zicsr -mabi=ilp32 `
  -ffreestanding -nostdlib -fno-stack-protector `
  -fdata-sections -ffunction-sections -Os -g `
  -Wl,-T,link.ld -Wl,-Map,build\baremetal_rvc.map -Wl,--gc-sections `
  -o build\baremetal_rvc.elf main.c rvc_smoke.S

riscv64-unknown-elf-objcopy -O binary build\baremetal_rvc.elf build\baremetal_rvc.bin

# 手动同步
copy build\baremetal.bin ..\scripts\baremetal.bin
copy build\baremetal_rvc.bin ..\scripts\baremetal_rvc.bin
copy build\baremetal.bin ..\..\..\..\bsp\pc\test\113.ndk_simple\baremetal.bin
copy build\baremetal_rvc.bin ..\..\..\..\bsp\pc\test\113.ndk_simple\baremetal_rvc.bin
```

---

## PC 宿主侧构建

**关键规则：必须使用 helper 脚本，不要直接运行 `xmake -y`**（会触发全量重建且输出被截断）。

### 标准构建

```powershell
cd bsp\pc
cmd /c build_windows_32bit_msvc.bat
```

- **编译时间**：增量约 10-30 秒（首次约 2-5 分钟）
- **输出**：`build\out\luatos-lua.exe`
- **日志**：`build\logs\` 目录（完整编译日志）

### GUI 变体构建

如果修改了 `components/airui/`、LVGL、SDL 显示相关代码：

```powershell
cmd /c build_windows_32bit_msvc_gui.bat
```

### 验证构建成功

脚本输出末尾应显示：

```
[pc-build] Build completed successfully
```

---

## 完整验证流程（从零开始）

### Step 1: 检查依赖

```powershell
# 检查 xmake
xmake --version

# 检查 MSVC（在 VS Developer Command Prompt 中）
cl

# 检查 RISC-V 工具链（可选，仅重建 guest 时需要）
riscv64-unknown-elf-gcc --version
# 或
riscv-none-elf-gcc --version
# 或
clang --version
ld.lld --version
```

### Step 2: 克隆仓库（如果尚未）

```powershell
git clone https://gitee.com/openLuat/LuatOS.git
cd LuatOS
```

### Step 3: 重建 Host ABI v1 Guest 镜像

```powershell
Set-Location D:\github\LuatOS\testcase\ndk\guest
.\build_hostabi_v1.ps1
```

期望输出：
```
=== Building Host ABI v1 fixture ===
Using GNU toolchain: riscv64-unknown-elf
...
=== Build successful ===
  Output: ..\ndk_hostabi_basic\scripts\hostabi_v1.bin (XXX bytes)
  Output: ..\ndk_hostabi_basic\scripts\hostabi_v1_rvc.bin (XXX bytes)
=== All done! ===
```

### Step 4: 重建 ndk_basic Guest 镜像

```powershell
Set-Location D:\github\LuatOS\testcase\ndk\ndk_basic\guest
.\build.ps1
```

期望输出：
```
=== Building RISC-V Baremetal Guest ===
Using GNU toolchain: riscv64-unknown-elf
...
=== Build successful ===
  RV32IMA:  build\baremetal.bin (315 bytes)
  RV32IMAC: build\baremetal_rvc.bin (240-260 bytes)
...
=== Syncing binaries to target locations ===
  Copying to: ...\testcase\ndk\ndk_basic\scripts\
  Copying to: ...\bsp\pc\test\113.ndk_simple\baremetal.bin
  Copying to: ...\bsp\pc\test\113.ndk_simple\baremetal_rvc.bin
=== All done! ===
```

### Step 5: 构建 PC 模拟器

```powershell
Set-Location D:\github\LuatOS\bsp\pc
cmd /c build_windows_32bit_msvc.bat
```

期望输出末尾：
```
[pc-build] Build completed successfully
```

### Step 6: 运行 ndk_basic 测试

```powershell
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_basic\scripts\
```

期望输出：
```
[I]/testcase/ndk/ndk_basic/scripts/main.lua:XX ndk test result Total: 9 passed, 0 failed
```

（包括 RV32IMA 和 RV32IMAC 执行覆盖，以及边界条件回归测试）

### Step 7: 运行 Host ABI 回归测试

```powershell
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_hostabi_basic\scripts\
```

期望输出：
```
[I]/testcase/ndk/ndk_hostabi_basic/scripts/main.lua:XX ndk Host ABI v1 test result Total: 34 passed, 0 failed
```

（包括 RV32IMAC Host ABI fixture 的 CSR 语义验证和压缩指令执行覆盖）

---

## 预期结果

### 成功输出示例

```
[I]/testcase/ndk/ndk_basic/scripts/main.lua:15 ndk test result Total: 5 passed, 0 failed
```

### 关键日志（调试级别）

测试中会看到 guest 通过 CSR 写发出的调试信息：

```
vm:  main is at: 0x80000014
vm:  Buffer is at: 0x80001120
vm:  Stack top is at: 0x8000113F
vm:  Testing strlen optimization:
vm num:  Length of teststr1: 13
vm num:  Length of teststr2: 71
Control Store: set val to 00005555
```

**注意**：上述地址值（`0x80000014` 等）会因编译器版本、优化级别和工具链差异而变化，但消息格式和关键数值（`13`、`71`、`00005555`）保持稳定。

最后一行 `Control Store: set val to 00005555` 表示 guest 正常退出（写 `0x5555` 到 SYSCON）。

### 失败迹象

- **错误 1**：`can't open /luadb/baremetal.bin`
  - **原因**：guest 镜像未同步或路径错误
  - **解决**：重新运行 `build.bat` 确保同步完成

- **错误 2**：`exec fail timeout` 或 trap 错误
  - **原因**：二进制损坏或源码不匹配
  - **解决**：清理 `guest/build/` 后重建

- **错误 3**：测试数量不对（如 `Total: 0 passed`）
  - **原因**：testcase 脚本未找到或加载错误
  - **解决**：检查命令行参数顺序（common 在前，ndk_basic 在后）

---

## 常见问题

### Q1: 找不到 RISC-V 工具链

**症状**：`build.bat` 报错 `No suitable RISC-V toolchain found`

**解决**：

1. **选择工具链**：
   - 推荐 xPack RISC-V GCC：https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases
   - 下载 Windows x64 版本，解压并添加 `bin/` 到 PATH

2. **验证安装**：
   ```powershell
   $env:PATH += ";C:\path\to\xpack-riscv-none-elf-gcc-12.2.0-3\bin"
   riscv-none-elf-gcc --version
   ```

3. **替代方案**：使用 LLVM（如果已安装）
   - 确保 LLVM 编译时启用了 RISC-V target 且安装了 LLD 链接器
   - 测试：`clang --target=riscv32-unknown-elf --version` 和 `ld.lld --version`

### Q2: baremetal.bin 生成路径不对

**症状**：构建成功但测试找不到二进制

**原因**：`build.bat` 自动同步机制依赖相对路径

**解决**：
1. 确保在 `testcase/ndk/ndk_basic/guest/` 目录内运行 `build.bat`
2. 手动验证同步：
   ```powershell
   ls ..\scripts\baremetal.bin
   ls ..\..\..\..\bsp\pc\test\113.ndk_simple\baremetal.bin
   ```

### Q3: PC 模拟器构建失败（MSVC 错误）

**症状**：`build_windows_32bit_msvc.bat` 报链接错误或找不到头文件

**解决**：
1. 确保在 **VS Developer Command Prompt** 中运行（`cl.exe` 在 PATH 中）
2. 或在普通终端中通过 `cmd /c` 串联执行（确保 `vcvars32.bat` 设置的环境变量在同一进程里生效）：
   ```powershell
   cmd /c "\"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars32.bat\" && build_windows_32bit_msvc.bat"
   ```
3. 清理后重试：
   ```powershell
   xmake clean -a
   cmd /c build_windows_32bit_msvc.bat
   ```

### Q4: testcase 找不到 `/luadb/baremetal.bin`

**症状**：运行时报错 `can't open /luadb/baremetal.bin`

**根因**：LuatOS VFS 在 PC 模拟器下将脚本目录挂载为 `/luadb/`，但二进制不在该目录

**解决**：
1. 确保 `testcase/ndk/ndk_basic/scripts/baremetal.bin` 存在
2. 重新运行 guest 构建（会自动同步）：
   ```powershell
   cd testcase\ndk\ndk_basic\guest
   cmd /c build.bat
   ```

### Q5: 修改了 guest 代码但测试结果未变

**原因**：忘记重建或仅重建了 guest 未重建 PC

**完整流程**：
```powershell
# 1. 重建 guest
cd testcase\ndk\ndk_basic\guest
cmd /c build.bat

# 2. 不需要重建 PC（guest 是运行时加载的）

# 3. 直接测试
cd ..\..\..\..\bsp\pc
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_basic\scripts\
```

**注意**：guest 二进制是运行时动态加载，无需重新编译 PC 模拟器。

---

## 运行时 API 参考

### `ndk.rv32i(path, mem_size, exchange_size)`

创建 RV32IMA 执行上下文。

**参数**：
- `path`：guest 镜像路径（相对或绝对）
- `mem_size`：guest RAM 大小（字节，默认 8KB，最大 32KB）
- `exchange_size`：host-guest 交换区大小（字节，默认 4KB，必须 < `mem_size`）

**返回**：
- 成功：`ctx` userdata（Lua GC 托管，`__gc` 时自动清理）
- 失败：`nil, error_message`

**内存布局**：
```
[镜像加载区 | 自由空间 | 交换区（尾部）]
 ^                        ^
 0x80000000              exchange_offset = mem_size - exchange_size
```

**约束**：
- `mem_size <= 32 * 1024`
- `exchange_size < mem_size`

---

### `ndk.exec(ctx, opts)`

同步执行 guest 代码。

**参数**：
- `ctx`：执行上下文
- `opts`：选项表（可选）
  - `steps`：步数预算（默认 32768）
  - `elapsed`：超时时间（微秒，默认 100）

**返回**：
- 成功（SYSCON 写 `0x5555` 退出）：`true, 0`
- 成功（ecall 退出，`mcause = 11`）：`true, retval`（`retval` = a0 寄存器值）
- 超时/停止请求：`false, "timeout", mcause, mtval`
- Trap/异常：`false, "trap", mcause, mtval`
- 繁忙（已在运行）：`false, "busy", mcause, mtval`

**状态约束**：仅在空闲态可调用。

**示例**：
```lua
local ok, ret, mcause, mtval = ndk.exec(ctx, {steps = 100000, elapsed = 500})
```

---

### `ndk.thread(ctx, opts)`

异步执行 guest 代码（后台线程）。

**参数**：同 `exec`

**返回**：
- 成功启动：线程 ID（递增整数）
- 繁忙：`nil, "busy"`

**注意**：需要后续调用 `ndk.stop()` 停止线程。

---

### `ndk.stop(ctx, wait_ms)`

停止异步线程。

**参数**：
- `ctx`：执行上下文
- `wait_ms`：等待超时（毫秒，默认 1000）

**返回**：
- 成功：`true`
- 超时：`false, "timeout"`

**幂等性**：空闲态/已停止时调用为安全幂等。

---

### `ndk.reset(ctx)`

重新加载镜像并重置状态。

**行为**：
- 重新从文件读取镜像
- 清零 RAM 和交换区
- 重置 CPU 寄存器（PC = 0x80000000）

**返回**：
- 成功：`true`
- 繁忙：`false, "busy"`

**状态约束**：仅在空闲态可调用。

---

### `ndk.info(ctx)`

获取上下文状态。

**返回表字段**：
- `mem`：RAM 总大小（字节）
- `exchange`：交换区大小（字节）
- `exchange_addr`：交换区起始地址（guest 视角）
- `image`：镜像路径
- `running`：是否正在运行（boolean）
- `mcause`：最后一次 trap 原因码
- `mtval`：最后一次 trap 值
- `abi_magic`：Host ABI magic（当前为 `NDK1`）
- `abi_version`：Host ABI 版本（当前 `0x00010000`）
- `features`：功能位图
- `last_error`：最近一次 Host ABI 错误码
- `event_slots`：当前事件槽数量

**当前 `features` 位图**：
- bit0 `META`
- bit1 `TIME`
- bit2 `EVENT`
- bit3 `GPIO`
- bit4 `UART`

---

### `ndk.setData(ctx, data_str, offset)`

写数据到交换区。

**参数**：
- `ctx`：执行上下文
- `data_str`：要写入的字符串
- `offset`：交换区内偏移（默认 0）

**返回**：
- 成功：写入字节数
- 失败：`false, error_message`

---

### `ndk.getData(ctx, len, offset)`

从交换区读数据。

**参数**：
- `ctx`：执行上下文
- `len`：读取长度（字节）
- `offset`：交换区内偏移（默认 0）

**返回**：
- 成功：数据字符串
- 失败：`false, error_message`

---

## CSR/MMIO 接口

### CSR 写（guest → host）

| CSR 地址 | 功能 | 参数格式 | 对应 host 行为 |
|----------|------|----------|---------------|
| `0x136` | 打印数字 | 32-bit 整数 | `DBG_ERR("vm num: %d", value)` |
| `0x137` | 打印指针 | 32-bit 地址 | `DBG_ERR("vm ptr: 0x%08X", value)` |
| `0x138` | 打印字符串 | guest 地址 | 读取并打印 C 字符串（最多 120 字节） |
| `0x143` | 延时 | us | 请求 host 延时（PC 实现按 ms 向上取整） |
| `0x144` | 事件开关 | `0/1` | 开启/关闭 timer 事件投递 |
| `0x200` | GPIO 输出 | `(level << 16) \| pin` | 设置 GPIO（未实现） |

### CSR 读（host → guest）

| CSR 地址 | 返回值 | 说明 |
|----------|--------|------|
| `0x139` | 交换区起始地址 | guest 侧的绝对地址 |
| `0x13A` | 交换区大小 | 字节数 |
| `0x13B` | RAM 总大小 | 字节数 |
| `0x13C` | Host ABI magic | 当前为 `NDK1` |
| `0x13D` | Host ABI 版本 | 当前为 `0x00010000` |
| `0x13E` | Host 功能位图 | 对应 `ndk.info(ctx).features` |
| `0x13F` | 最近一次 Host 错误码 | 对应 `ndk.info(ctx).last_error` |
| `0x140` | 事件槽数量 | 对应 `ndk.info(ctx).event_slots` |
| `0x141` | 当前时间低 32 位 | ABI 单位为 us |
| `0x142` | 当前时间高 32 位 | ABI 单位为 us |
| `0x145` | 事件 pending 标志 | `0/1` |
| `0x201` | GPIO 输入 | 低 16 位为 pin 号（未实现） |

### MMIO

| 地址 | 操作 | 行为 |
|------|------|------|
| `0x11100000` | store | 返回写入值到 a0，并把 guest PC 重置到镜像入口；后续 `do_reset=false` 会从 `_start` 重新进入 |

**示例**（guest 侧）：

```c
// 打印调试信息
asm volatile("csrw 0x138, %0" :: "r"("Hello from guest"));

// 获取交换区地址
uint32_t exchange_addr;
asm volatile("csrr %0, 0x139" : "=r"(exchange_addr));

// 退出并返回 0x5555
*(volatile uint32_t*)0x11100000 = 0x5555;
```

---

## Host ABI v1 / GPIO v2 / UART v1

当前基础能力覆盖：

- ABI 发现：magic / version / feature bits / last_error / event_slots
- 时间/事件核心：`delay_us`、`time_us_lo/hi`、`event_enable`、`event_pending`
- GPIO v2：`GPIO_CONFIG`、`GPIO_WRITE`、`GPIO_READ`、`GPIO_IRQ_STATE`、`GPIO_IRQ_CLEAR`
- UART v1：`UART_CONFIG`、`UART_TX`、`UART_RX_STATE`、`UART_RX_READ`、`UART_RX_CLEAR`
- PC 回归 fixture：`testcase\ndk\guest\hostabi_v1`

交换区布局：

- `0..15`：guest 命令区（`hostabi_cmd_t`）
- `16..31`：guest 结果区（`hostabi_result_t`）
- `32..47`：事件头（`luat_ndk_event_header_t`）
- `48..`：事件槽数组（`luat_ndk_event_t[event_slots]`）

其中 `event_slots` 会按交换区可用空间计算，最大为 8。

### GPIO v2 CSR

GPIO v2 通过 `csrrw a0, csr, a0` 的请求/应答模式工作，不再依赖 legacy `0x200/0x201` 语义：

- `0x210` `GPIO_CONFIG`
  - 请求：`a0 = pin[7:0] | mode[15:8] | pull[23:16] | irq_mode[31:24]`
  - 返回：`LUAT_NDK_GPIO_STATUS_*`
- `0x211` `GPIO_WRITE`
  - 请求：`a0 = pin[15:0] | level[16]`
  - 返回：`LUAT_NDK_GPIO_STATUS_*`
- `0x212` `GPIO_READ`
  - 请求：`a0 = pin[15:0]`
  - 返回：成功时为电平 `0/1`；失败时为 `LUAT_NDK_GPIO_STATUS_*`
- `0x213` `GPIO_IRQ_STATE`
  - 请求：`a0 = pin[15:0]`
  - 返回：成功时为 packed IRQ state，布局与 `components/ndk/include/luat_ndk_abi.h` 一致
- `0x214` `GPIO_IRQ_CLEAR`
  - 请求：`a0 = pin[15:0]`
  - 返回：`LUAT_NDK_GPIO_STATUS_*`
  - 语义：清除该 pin 的 pending 位，同时把记录的 reason 归零

GPIO ownership / error policy：

- `GPIO_CONFIG` / `GPIO_WRITE` 成功后才声明 pin 所有权；host HAL 失败返回 `HOST_ERROR`
- 所有权是上下文级别仲裁；另一上下文对已占用 pin 的 `GPIO_CONFIG` / `GPIO_WRITE` 会收到 `HOST_ERROR`
- `GPIO_READ` 是非 owning probe，只读取当前电平，不抢占或释放所有权

GPIO IRQ 事件语义：

- 异步通知仍走 event ring，事件类型为 `GPIO_IRQ`（`type = 2`）
- `source` 为触发 pin，`data` 为与 `GPIO_IRQ_STATE` 相同布局的 packed IRQ payload
- 这是通知型事件；权威状态与 ack 始终来自 `GPIO_IRQ_STATE` / `GPIO_IRQ_CLEAR`

### UART v1 CSR

- `0x220` `UART_CONFIG`
- `0x221` `UART_TX`
- `0x222` `UART_RX_STATE`
- `0x223` `UART_RX_READ`
- `0x224` `UART_RX_CLEAR`

`UART_RX_READY` 通过现有 event ring 异步投递（`type = 3`）。该事件只负责通知，缓冲区长度与确认/清理语义以 `UART_RX_STATE` / `UART_RX_READ` / `UART_RX_CLEAR` 为准。

当前 PC 模拟器回归使用确定性的上下文私有 loopback 模型：

- `UART_CONFIG` 启用 loopback-backed UART 上下文
- `UART_TX` 将交换区数据写入 host loopback backend
- `UART_RX_STATE` / `UART_RX_READ` 读取回环后的接收状态与数据
- `UART_RX_CLEAR` 会丢弃当前 RX buffer 中的全部字节

如果 `bsp\pc\luat_uart_i686.dll` 可用，且 CH340 loopback 接在 `COM14`，可以做手工 smoke；自动回归仍以确定性的 host-backed loopback 为准。

### Host ABI 回归

重建 guest fixture：

```powershell
Set-Location testcase\ndk\guest
.\build_hostabi_v1.ps1
```

运行 Host ABI suite：

```powershell
Set-Location bsp\pc
cmd /c build_windows_32bit_msvc.bat
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_hostabi_basic\scripts\
```

---

## RV32C 压缩指令支持与兼容性

### 概述

LuatOS NDK 同时支持：

- **RV32IMA / RV32IMA_ZICSR**（传统 32 位定宽指令集）
- **RV32IMAC / RV32IMAC_ZICSR**（带 C 扩展的 16/32 位混合指令集，本次变更后支持）

Guest 应用代码可以使用 `-march=rv32imac` 编译，生成更紧凑的二进制镜像（代码体积通常减少 15-25%）。Mini-rv32ima 解释器已正确实现 RV32C 解码与执行。

#### ISA 支持矩阵

| ISA 组合 | 支持状态 | 说明 |
|---------|---------|------|
| **rv32ima** | ✅ 完全支持 | 传统 32 位定宽指令集 |
| **rv32ima_zicsr** | ✅ 完全支持 | 推荐用于需要 CSR 访问的应用 |
| **rv32imac** | ✅ 完全支持 | 带 C 扩展的压缩指令（本次变更后支持） |
| **rv32imac_zicsr** | ✅ 完全支持 | 推荐用于压缩模式 + CSR 访问（本次变更后支持） |
| rv64/rv128 | ❌ 不支持 | 仅支持 32 位架构 |
| F/D/V 扩展 | ❌ 不支持 | 无浮点/向量支持 |
| Zb*/Zk* 等其他扩展 | ❌ 不支持 | 仅限上述基本 ISA 组合 |

#### 性能考虑

**压缩指令的权衡**：

- ✅ **优势**：代码体积减少 15-25%，节省内存/存储
- ⚠️ **劣势**：解释器需要**解压缩**指令流，每次取指增加额外开销
  - RV32C 指令需要先解码为 32 位等价指令，再执行
  - 对于计算密集型任务，fetch 开销可能抵消体积收益
  - 对于 I/O 密集型或内存受限任务，体积优势更明显

**推荐策略**：
- **默认使用 RV32IMA**：已有工具链/测试充分验证
- **仅在内存/存储极度受限时启用 RV32IMAC**：如嵌入式存储 < 64KB 场景
- **性能关键路径避免压缩指令**：hotspot 函数可用 `-fno-compress` 单独编译（部分工具链支持）

### CSR Helper 固定宽度保证

#### `.option norvc` 使用范围

所有 CSR 访问指令（`csrr`/`csrrw`）在 **inline asm 块内局部禁用压缩**：

```c
// luat_ndk_builtin.h / ndk_stubs.c 中的典型模式
static inline uint32_t ndk_exchange_base(void) {
    uint32_t v = 0;
    __asm__ volatile(".option norvc\ncsrr %0, %1" : "=r"(v) : "i"(NDK_CSR_EXCHANGE_BASE));
    return v;
}
```

**设计原则**：

1. **局部作用域**：每个 `.option norvc` 仅影响其所在的单条 inline asm 语句，**不影响整个编译单元**
2. **固定宽度 CSR**：CSR 指令保持 32 位编码，确保 host 侧解释器的 CSR 拦截逻辑无需处理压缩指令变体
3. **应用代码自由**：guest 应用代码（非 CSR wrapper）可自由使用 RV32C 压缩指令，由编译器 `-march=rv32imac` 控制

#### 为何 CSR 不压缩

RISC-V C 扩展不包含 CSR 指令的压缩形式（`csrr`/`csrrw` 无 16 位编码）。`.option norvc` 是**防御性编码**，防止未来工具链优化或非标准扩展意外修改 CSR 指令长度。

### 兼容性边界

| 组件 | 指令集 | 压缩指令 | 说明 |
|------|--------|----------|------|
| **CSR Helper** | RV32IMA | ❌ 禁用 | 所有 `luat_ndk_builtin.h` / `ndk_stubs.c` 内的 CSR inline asm 使用 `.option norvc` |
| **Guest 应用代码** | RV32IMAC | ✅ 允许 | 编译标志 `-march=rv32imac` / `-march=rv32ima` 均支持 |
| **Host 解释器** | N/A | ✅ 支持 | Mini-rv32ima 正确解码并执行 RV32C |

### Host ABI 兼容性声明

**重要**：RV32C 支持是 **guest 代码优化特性**，不改变 Host ABI 语义：

- **不新增 Host ABI 命令族**（GPIO v2 / UART v1 保持不变）
- **不修改现有 CSR 编码或语义**（所有 CSR 号与行为与 RV32IMA 版本完全一致）
- **构建时验证**：guest build 脚本编译并检查 RV32IMAC 镜像包含压缩指令（反汇编验证）
- **运行时兼容性**：RV32IMA Host ABI 测试（`ndk_hostabi_basic`）确保 CSR helper 语义不变（RV32C 执行覆盖由基础测试提供）

### 构建与验证

#### Guest 镜像变体

所有 guest build 脚本自动生成两个变体：

```powershell
# ndk_basic 测试镜像
cd testcase\ndk\ndk_basic\guest
.\build.ps1

# 输出：
#   build/baremetal.bin      (rv32ima_zicsr, ~315 bytes)
#   build/baremetal_rvc.bin  (rv32imac_zicsr, ~240-260 bytes)

# Host ABI v1 fixture
cd testcase\ndk\guest
.\build_hostabi_v1.ps1

# 输出：
#   testcase\ndk\ndk_hostabi_basic\scripts\hostabi_v1.bin     (rv32ima_zicsr)
#   testcase\ndk\ndk_hostabi_basic\scripts\hostabi_v1_rvc.bin (rv32imac_zicsr)
```

#### 完整验证序列

**CRITICAL**: 以下是完整的端到端验证流程，包括所有 RV32C 覆盖：

```powershell
# 1.
Set-Location D:\github\LuatOS\testcase\ndk\guest

# 2.
.\build_hostabi_v1.ps1

# 3.
Set-Location D:\github\LuatOS\testcase\ndk\ndk_basic\guest

# 4.
.\build.ps1

# 5.
Set-Location D:\github\LuatOS\bsp\pc

# 6.
cmd /c build_windows_32bit_msvc.bat

# 7.
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_basic\scripts\

# 8.
.\build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_hostabi_basic\scripts\
```

#### 期望结果

1. **ndk_basic**（Step 7）:
   ```
   [I]/testcase/ndk/ndk_basic/scripts/main.lua:XX ndk test result Total: 9 passed, 0 failed
   ```
   - ✅ RV32IMA 执行（`baremetal.bin`）
   - ✅ RV32IMAC 执行（`baremetal_rvc.bin`，含 `c.li`, `c.addi`, `c.jr` 等压缩指令）
   - ✅ 边界条件回归（非法 PC / 未对齐访问）

2. **ndk_hostabi_basic**（Step 8）:
   ```
   [I]/testcase/ndk/ndk_hostabi_basic/scripts/main.lua:XX ndk Host ABI v1 test result Total: 34 passed, 0 failed
   ```
   - ✅ RV32IMA Host ABI fixture（CSR 语义验证）
   - ✅ RV32IMAC Host ABI fixture（压缩指令 + CSR 语义验证）
   - ✅ GPIO v2 / UART v1 完整回归

### 相关文件

| 文件 | 说明 |
|------|------|
| `components/ndk/include/luat_ndk_builtin.h` | CSR helper 定义（所有函数含 `.option norvc`） |
| `testcase/ndk/guest/hostabi_v1/ndk_stubs.c` | Host ABI fixture（所有 CSR asm 含 `.option norvc`） |
| `testcase/ndk/ndk_basic/guest/rvc_smoke.S` | RV32C 手写汇编烟雾测试 |
| `testcase/ndk/guest/hostabi_v1/rvc_smoke.S` | Host ABI fixture 的 RV32C 烟雾测试 |

---

## 最小使用示例

```lua
-- 完整生命周期示例
local IMAGE = "/luadb/baremetal.bin"
local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
assert(ctx, err)

local info = ndk.info(ctx)
log.info("ndk", "mem", info.mem, "exchange", info.exchange)

-- 写入数据到交换区
local n, err = ndk.setData(ctx, "hello ndk")
assert(n and n ~= false, "ndk.setData failed: " .. tostring(err))

-- 执行 guest
local ok, ret, mcause, mtval = ndk.exec(ctx, {steps = 100000, elapsed = 500})
assert(ok, string.format("exec fail %s mcause=%s mtval=%s", 
    tostring(ret), tostring(mcause), tostring(mtval)))

-- 读取交换区结果
local data, data_err = ndk.getData(ctx, 64, 0)
assert(data and data ~= false, "ndk.getData failed: " .. tostring(data_err))
log.info("ndk", "ret", ret, "data", data)

-- 清理
assert(ndk.stop(ctx, 1000))
assert(ndk.reset(ctx))

ctx = nil
collectgarbage("collect")
```

---

## 相关文档

- **Guest 源码与构建**：`testcase/ndk/ndk_basic/guest/README.md`
- **Testcase 说明**：`testcase/ndk/ndk_basic/README.md`
- **Runtime 实现**：`components/ndk/src/luat_ndk.c`
- **CSR 处理器**：`components/ndk/src/luat_ndk_host.c`
- **mini-rv32ima 上游**：https://github.com/cnlohr/mini-rv32ima

---

## License

NDK runtime 基于 mini-rv32ima（MIT-x11/NewBSD），与 LuatOS MIT License 兼容。
