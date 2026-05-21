# GPIO v2 Design for NDK Host ABI

Date: 2026-05-20
Branch: `copilot/ndk-gpio-v2`
Status: Approved for planning

## 1. Goal

Add the first practical GPIO capability family on top of the existing NDK Host ABI foundation so an RV32 guest can:

1. configure a pin's mode, pull, and IRQ mode
2. set and read pin level
3. observe GPIO IRQ arrival through the existing event ring
4. query and clear per-pin IRQ pending state

This design must preserve the current Host ABI v1 foundation and establish the interaction pattern that UART v1 will reuse next.

## 2. Non-Goals

This phase does not include:

- UART v1 implementation
- batch GPIO operations
- pin groups, port-wide masks, or bulk transfer APIs
- alternate-function / mux configuration beyond what the LuatOS GPIO HAL directly exposes
- redesign of the existing runtime, exchange buffer foundation, or event core

## 3. Current Context

The merged `master` branch already provides:

- ABI discovery: magic, version, features, last_error, event_slots
- time / delay / event core
- exchange-buffer layout:
  - command: `0..15`
  - result: `16..31`
  - event header: `32..47`
  - event ring: `48..`
- existing raw GPIO CSR path:
  - `0x200`: set level
  - `0x201`: get level

That raw GPIO path is too thin for real use because it has no configuration, no IRQ lifecycle, and no structured error reporting.

## 4. Recommended Architecture

GPIO v2 uses a **hybrid model**:

1. **Foundation stays unchanged**
   - keep current meta/time/event CSR surface
   - keep current exchange buffer layout and event ring

2. **Structured GPIO operations use exchange commands**
   - config
   - write
   - read
   - IRQ state query
   - IRQ clear

3. **IRQ delivery uses the existing event ring**
   - host pushes a `GPIO_IRQ` event on interrupt arrival
   - guest uses commands to inspect and clear authoritative pending state

4. **UART v1 follows the same pattern later**
   - simple controls may remain lightweight
   - structured state and async delivery use exchange + event ring

This keeps GPIO v2 practical without fragmenting the ABI into an unstructured CSR-only surface.

## 5. ABI Design

### 5.1 Exchange Command Families

GPIO v2 adds five commands to the guest fixture protocol:

1. `GPIO_CONFIG`
   - inputs: `pin`, `mode`, `pull`, `irq_mode`
   - result: success or structured parameter error

2. `GPIO_WRITE`
   - inputs: `pin`, `level`
   - result: success or error

3. `GPIO_READ`
   - inputs: `pin`
   - result: `level`

4. `GPIO_IRQ_STATE`
   - inputs: `pin`
   - result: pending flag and last IRQ reason if available

5. `GPIO_IRQ_CLEAR`
   - inputs: `pin`
   - result: success or error

### 5.2 Event Types

GPIO v2 adds one event type:

- `GPIO_IRQ`

Event payload must encode at least:

- pin number
- IRQ reason/mode

If event payload space permits, a timestamp or reserved field may be carried, but pin and reason are mandatory.

### 5.3 Error Model

GPIO v2 uses both:

- `status` in the command result
- `last_error` in host ABI state

Error categories:

- `BAD_PIN`
- `BAD_MODE`
- `BAD_PULL`
- `BAD_IRQ_MODE`
- `UNSUPPORTED`
- `BUSY`

Rule: command failure must never silently degrade to success-shaped behavior.

## 6. Runtime Behavior

### 6.1 Configuration Flow

Guest sends `GPIO_CONFIG`.

Host validates arguments, applies LuatOS GPIO HAL configuration, and records any per-pin IRQ bookkeeping needed for later event delivery and pending/clear behavior.

### 6.2 IRQ Flow

1. guest configures IRQ mode on a pin
2. host receives the GPIO callback / notification
3. host marks that pin pending in the NDK context
4. host pushes a `GPIO_IRQ` event into the existing event ring
5. guest consumes the event for notification
6. guest uses `GPIO_IRQ_STATE` and `GPIO_IRQ_CLEAR` to confirm and acknowledge state

Notification and confirmation are intentionally separate:

- **event ring** answers "something happened"
- **GPIO commands** answer "what pin is pending and has it been cleared"

## 7. File/Module Plan

### Modify

- `components/ndk/include/luat_ndk_abi.h`
  - add GPIO v2 command opcodes
  - add GPIO event type and field constants
  - add GPIO mode / pull / irq-mode enumerations aligned with LuatOS HAL where possible

- `components/ndk/include/luat_ndk.h`
  - extend `luat_ndk_t` with per-context GPIO pending bookkeeping needed by IRQ state/clear

- `components/ndk/include/luat_ndk_host.h`
  - declare GPIO host helpers

- `components/ndk/src/luat_ndk_host.c`
  - keep central dispatch, route GPIO v2 requests to dedicated helpers

- `testcase/ndk/guest/hostabi_v1/main.c`
  - add guest command branches for GPIO v2

- `testcase/ndk/ndk_hostabi_basic/scripts/hostabi_proto.lua`
  - extend protocol constants and pack/unpack helpers

- `testcase/ndk/ndk_hostabi_basic/scripts/ndk_hostabi_test.lua`
  - add GPIO v2 regression coverage

### Create

- `components/ndk/src/luat_ndk_host_gpio.c`
  - command handlers
  - parameter validation
  - LuatOS GPIO HAL bridging
  - IRQ pending bookkeeping
  - event emission helper for `GPIO_IRQ`

## 8. Testing Strategy

### Red-Green Expectations

Add failing tests first for:

1. configure pin mode/pull/irq mode successfully
2. write level successfully
3. read level successfully
4. IRQ pending becomes visible after simulated trigger
5. IRQ clear removes pending state
6. at least one `GPIO_IRQ` event appears in the event ring

### Regression Safety

Every GPIO v2 change must continue to pass:

- `testcase\ndk\ndk_basic\scripts\`
- `testcase\ndk\ndk_hostabi_basic\scripts\`

### PC Simulator Constraint

GPIO v2 tests must be reproducible on the PC simulator. If physical IRQ behavior is not directly available, the design must include a simulator-safe trigger path or a narrow host-side test hook that only exists to drive the real GPIO pending/event path, not to bypass it.

## 9. Success Criteria

GPIO v2 is complete when all of the following are true:

1. guest can configure mode/pull/irq mode through the Host ABI
2. guest can write and read pin level
3. guest can observe a `GPIO_IRQ` event in the event ring
4. guest can query and clear pending IRQ state
5. failures return explicit `status` and `last_error`
6. merged verification still passes for both NDK suites

## 10. Follow-On Compatibility

UART v1 should not invent a new control model. It should reuse the same pattern established here:

- structured exchange commands for rich operations
- event ring for async notification
- `last_error` + result status for failure reporting

GPIO v2 is therefore both a feature and the template for UART v1.
