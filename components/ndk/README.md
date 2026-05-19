# ndk（RV32I 运行时）

`ndk` 用于在 LuatOS 内运行 MiniRV32IMA 镜像，并通过交换区与 Lua 侧交互。

## 1. `ndk.rv32i()` 资源分配与内存布局

```lua
local ctx, err = ndk.rv32i(path, mem_size, exchange_size)
```

- 分配内容：
  - `ctx` userdata（Lua GC 托管，`__gc` 时自动 stop + deinit）
  - 一块 guest RAM（`mem_size`）
  - 一个 RV32 核心状态结构（`MiniRV32IMAState`）
  - 一份镜像路径副本字符串
- 默认值：
  - `mem_size = 8 * 1024`
  - `exchange_size = 4 * 1024`
- 约束：
  - `mem_size <= 32 * 1024`
  - `exchange_size < mem_size`
- 布局：
  - 镜像从 RAM 起始地址加载
  - 交换区位于 RAM 尾部：`exchange_offset = mem_size - exchange_size`

## 2. API 行为契约（当前实现）

### `ndk.exec(ctx, opts, elapsed_us)`
- 仅在空闲态可调用；运行中/停止中返回 `false,"busy",mcause,mtval`。
- 成功返回 `true, retval`（`retval` 来自 a0，退出原因为 `ecall` + `mcause=11`）。
- 超出步数预算或收到 stop 请求时返回 `false,"timeout",mcause,mtval`。
- trap 返回 `false,"trap",mcause,mtval`。
- `opts.steps == 0` 使用默认预算（32768），`elapsed == 0` 使用默认 100us。

### `ndk.thread(ctx, opts, elapsed_us)`
- 空闲态启动异步执行，成功返回线程 ID（递增整数）。
- 运行中/停止中返回 `nil,"busy"`。
- 参数与 `exec` 相同（`steps/elapsed`）。

### `ndk.stop(ctx, wait_ms)`
- 请求停止异步线程并等待。
- 空闲态/已 deinit 为幂等成功（返回 `true`）。
- 默认等待 1000ms；`wait_ms` 到期返回 `false,"timeout"`。

### `ndk.reset(ctx)`
- 仅在空闲态可用，重新加载镜像并清零 RAM/交换区，重置 CPU 状态。
- 运行中/停止中返回 `false,"busy"`。

### `ndk.info(ctx)`
- 返回状态表：
  - `mem`, `exchange`, `exchange_addr`, `image`, `running`, `mcause`, `mtval`

## 3. 当前已实现 CSR / MMIO

### CSR 写（guest -> host）
- `0x136`：打印数字（`vm num`）
- `0x137`：打印指针值（`vm ptr`）
- `0x138`：按 guest 地址打印字符串（最多 120 字节）
- `0x200`：GPIO 输出（`value = (level << 16) | pin`）

### CSR 读
- `0x139`：交换区起始地址
- `0x13A`：交换区大小
- `0x13B`：RAM 总大小
- `0x201`：GPIO 输入（低 16 位为 pin）

### MMIO（当前仅实现 store hook）
- `store 0x11100000 = value`：返回 `value` 并令 PC 前进 4（用于 guest 侧控制出口）
- 其他地址：未定义（记录调试日志，返回 0）

## 4. 最小生命周期示例

```lua
local IMAGE = "/luadb/baremetal.bin"
local ctx, err = ndk.rv32i(IMAGE, 32 * 1024, 1024)
assert(ctx, err)

local info = ndk.info(ctx)
log.info("ndk", "mem", info.mem, "exchange", info.exchange)

local n, err = ndk.setData(ctx, "hello ndk")
assert(n and n ~= false, "ndk.setData failed: " .. tostring(err))

local ok, ret, mcause, mtval = ndk.exec(ctx, {steps = 100000, elapsed = 500})
assert(ok, string.format("exec fail %s mcause=%s mtval=%s", tostring(ret), tostring(mcause), tostring(mtval)))

local data, data_err = ndk.getData(ctx, 64, 0)
assert(data and data ~= false, "ndk.getData failed: " .. tostring(data_err))
log.info("ndk", "ret", ret, "data", data)

assert(ndk.stop(ctx, 1000))
assert(ndk.reset(ctx))

ctx = nil
collectgarbage("collect")
```

## 5. PC 测试运行方式

在仓库根目录执行：

```powershell
cd bsp\pc
cmd /c build_windows_32bit_msvc.bat
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_basic\scripts\
```
