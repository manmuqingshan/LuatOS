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
  - `abi_magic`, `abi_version`, `features`, `last_error`, `event_slots`
- 当前 `features` 位图：
  - bit0 `META`
  - bit1 `TIME`
  - bit2 `EVENT`
  - bit3 `GPIO`
  - bit4 `UART`

## 3. 当前已实现 CSR / MMIO

### CSR 写（guest -> host）
- `0x136`：打印数字（`vm num`）
- `0x137`：打印指针值（`vm ptr`）
- `0x138`：按 guest 地址打印字符串（最多 120 字节）
- `0x143`：请求延时（单位 us；当前 PC 实现按 ms 向上取整 sleep）
- `0x144`：开启/关闭 timer 事件投递
- `0x200`：legacy GPIO 输出（`value = (level << 16) | pin`）

### CSR 读
- `0x139`：交换区起始地址
- `0x13A`：交换区大小
- `0x13B`：RAM 总大小
- `0x13C`：Host ABI magic（`NDK1`）
- `0x13D`：Host ABI 版本（当前 `0x00010000`）
- `0x13E`：Host 功能位图
- `0x13F`：最近一次 Host 错误码
- `0x140`：事件槽数量
- `0x141`：当前时间低 32 位（ABI 单位为 us，当前 PC 实现来自 ms tick * 1000）
- `0x142`：当前时间高 32 位
- `0x145`：是否存在待处理事件
- `0x201`：legacy GPIO 输入（低 16 位为 pin）

### GPIO v2 CSR（通过 `csrrw a0, csr, a0` 走 CSR 读路径返回）

GPIO v2 不再使用 `0x200/0x201` 的原始读写语义，而是通过 `a0` 载荷 + CSR 返回值完成请求/应答：

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
  - 返回：成功时为 packed IRQ state，布局与 `components/ndk/include/luat_ndk_abi.h` 一致：
    - `bits 0..15`：pin
    - `bit 16`：pending
    - `bits 24..31`：reason（`LUAT_NDK_GPIO_IRQ_*`）
  - 原始 CSR 返回值需要结合 `NDK_CSR_HOST_LAST_ERROR` / `last_error` 一起解释；因为合法 packed 值与错误码在数值上可能重叠，不能只看返回整数本身
  - Host ABI fixture 会把它规范化成明确的 `status/value0/value1` 结果；未启用 IRQ 的 pin 在该层表现为 `LUAT_NDK_GPIO_STATUS_UNSUPPORTED`
- `0x214` `GPIO_IRQ_CLEAR`
  - 请求：`a0 = pin[15:0]`
  - 返回：`LUAT_NDK_GPIO_STATUS_*`
  - 语义：清除该 pin 的 pending 位，同时把记录的 reason 归零

### MMIO（当前仅实现 store hook）
- `store 0x11100000 = value`：将 guest PC 重置到镜像入口点并返回 `value`；下次 `do_reset=false` 的 exec 将从 `_start` 重新进入（而非从陈旧 PC 继续执行）
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

## 6. Host ABI v1 foundation / GPIO v2

当前基础能力覆盖：

- ABI 发现：magic / version / feature bits / last_error / event_slots
- 时间/事件核心：`delay_us`、`time_us_lo/hi`、`event_enable`、`event_pending`
- GPIO v2：`GPIO_CONFIG`、`GPIO_WRITE`、`GPIO_READ`、`GPIO_IRQ_STATE`、`GPIO_IRQ_CLEAR`
- PC regression fixture：`testcase\ndk\guest\hostabi_v1`

交换区布局：

- `0..15`：guest 命令区（`hostabi_cmd_t`）
- `16..31`：guest 结果区（`hostabi_result_t`）
- `32..47`：事件头（`luat_ndk_event_header_t`）
- `48..`：事件槽数组（`luat_ndk_event_t[event_slots]`）

其中 `event_slots` 会按交换区可用空间计算，最大为 8。

### Host ABI fixture 命令族（`testcase\ndk\guest\hostabi_v1`）

- `0x01` `QUERY_META`
- `0x02` `DELAY_US`
- `0x03` `EVENT_STATE`
- `0x10` `GPIO_CONFIG`
- `0x11` `GPIO_WRITE`
- `0x12` `GPIO_READ`
- `0x13` `GPIO_IRQ_STATE`
- `0x14` `GPIO_IRQ_CLEAR`

其中 GPIO v2 命令的 guest 结果区约定为：

- `GPIO_CONFIG`
  - fixture 命令载荷：`arg0 = pin`、`arg1 = mode`、`arg2.low8 = pull`、`arg2.high8 = irq_mode`
  - 这样在不扩展 16-byte fixture 命令结构的前提下，仍可覆盖非默认 IRQ mode

- `GPIO_CONFIG` / `GPIO_WRITE` / `GPIO_IRQ_CLEAR`
  - `status = LUAT_NDK_GPIO_STATUS_*`
- `GPIO_READ`
  - `status = OK` 时 `value0 = 0/1`
- `GPIO_IRQ_STATE`
  - fixture 会把 packed CSR 返回值拆成：
    - `value0 = pending`
    - `value1 = reason`
  - `pin` 不再单独返回，因为请求 pin 已知；若需要完整 packed 语义，应以 ABI 宏布局为准

GPIO ownership / error policy:

- `GPIO_CONFIG` / `GPIO_WRITE` 成功后才会声明 pin 所有权；host HAL 失败会返回 `HOST_ERROR`，不会伪造成功
- 所有权是进程级别仲裁的；另一上下文对已被占用 pin 的 `GPIO_CONFIG` / `GPIO_WRITE` 会收到 `HOST_ERROR`
- `GPIO_READ` 仍然是非 owning probe，可读取当前电平但不会抢占或释放所有权

### GPIO_IRQ 事件语义

- 异步通知仍然走现有 event ring，事件类型为 `GPIO_IRQ`（`type = 2`）
- `source` 为触发 pin
- `data` 为与 `GPIO_IRQ_STATE` 相同布局的 packed IRQ payload
- 该事件是**通知型**的：表示“有 IRQ 发生/可检查”，不是最终 ack 状态
- authoritative 状态与清除语义始终来自：
  - `GPIO_IRQ_STATE`：读取当前 pending/reason
  - `GPIO_IRQ_CLEAR`：执行 ack，清 pending 并清空 reason

### PC 模拟器当前确定性 IRQ 行为

当前 PC regression fixture 为了让用例稳定、可重复，在 `GPIO_CONFIG` 成功把 pin 配置为 IRQ 模式后，会立即合成一次该 pin 的 IRQ：

- 立即标记该 pin 为 pending
- 记录 reason 为配置时传入的 `irq_mode`
- 立即向 event ring 推入一个 `GPIO_IRQ` 事件
- 这一行为**不受** `event_enable` 控制（与 timer 事件不同）

因此在当前 PC 模拟器回归里，IRQ pin 配置成功后应可稳定观察到：

- `GPIO_IRQ_STATE.pending == 1`
- event ring 中出现一个 `GPIO_IRQ`
- 调用 `GPIO_IRQ_CLEAR` 后，后续 `GPIO_IRQ_STATE.pending == 0`，且 `reason == 0`

重建 PC 测试 fixture：

```powershell
Set-Location testcase\ndk\guest
.\build_hostabi_v1.ps1
```

运行 Host ABI foundation suite：

```powershell
Set-Location bsp\pc
cmd /c build_windows_32bit_msvc.bat
build\out\luatos-lua.exe ..\..\testcase\common\scripts\ ..\..\testcase\ndk\ndk_hostabi_basic\scripts\
```

## UART v1

UART v1 uses the Host ABI exchange command/result protocol for:

- `UART_CONFIG`
- `UART_TX`
- `UART_RX_STATE`
- `UART_RX_READ`
- `UART_RX_CLEAR`

Async receive notification is delivered as `UART_RX_READY` in the existing event ring. Event delivery is notification-only; authoritative buffered length and acknowledgement stay on `UART_RX_STATE` / `UART_RX_READ` / `UART_RX_CLEAR`.

Current PC simulator regression uses a deterministic context-local loopback model:

- `UART_CONFIG` enables a loopback-backed UART context
- `UART_TX` copies bytes from exchange buffer into the host loopback backend
- RX-ready data is surfaced through `UART_RX_READY` plus `UART_RX_STATE`
- `UART_RX_READ` copies bytes back into the exchange buffer
- `UART_RX_CLEAR` discards all bytes currently held in the loopback RX buffer

If `bsp\pc\luat_uart_i686.dll` is available and a CH340 loopback is connected on `COM14`, that path may be used for a manual smoke check, but automated regression still relies on the deterministic host-backed loopback above.
