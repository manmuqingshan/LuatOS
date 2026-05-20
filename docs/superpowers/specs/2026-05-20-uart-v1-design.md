# UART v1 Design for NDK Host ABI

Date: 2026-05-20
Branch: `copilot/ndk-uart-v1`
Status: Approved for planning

## 1. Goal

Add the first practical UART capability family on top of the existing NDK Host ABI foundation and GPIO v2 pattern so an RV32 guest can:

1. configure a UART port
2. transmit bytes through a structured host command
3. observe receive availability through an async event
4. query, read, and acknowledge buffered RX state through explicit commands

This design must preserve the existing foundation and GPIO v2 contracts while establishing a reusable buffered-I/O pattern for future capability families.

## 2. Non-Goals

This phase does not include:

- real PC serial device passthrough as the primary execution path
- DMA, flow control, modem control lines, or RS485 direction control
- blocking guest-side receive loops based purely on CSR polling
- generic stream multiplexing for arbitrary future devices
- redesign of the current exchange buffer, event ring, or runtime lifecycle

## 3. Current Context

The current Host ABI stack already provides:

- ABI discovery: magic, version, feature bits, last_error, event_slots
- time / delay / event core
- GPIO v2 as the first structured capability family
- exchange-buffer layout:
  - command: `0..15`
  - result: `16..31`
  - event header: `32..47`
  - event ring: `48..`

GPIO v2 established the preferred interaction pattern:

1. structured operations use command/result or CSR-backed command helpers
2. async notification uses the event ring
3. authoritative state and acknowledgement remain on the command side

UART v1 should reuse that pattern rather than inventing a separate model.

## 4. Recommended Architecture

UART v1 uses a **buffered hybrid model**:

1. **Foundation stays unchanged**
   - keep current exchange buffer layout
   - keep current event ring
   - keep current `last_error` reporting behavior

2. **Structured UART controls use explicit command/result operations**
   - config
   - transmit
   - RX state query
   - RX read
   - RX clear / acknowledge

3. **RX availability uses the existing event ring**
   - host pushes `UART_RX_READY`
   - event is notification-only
   - guest still uses command side for authoritative length/state

4. **PC simulator uses deterministic loopback/injection**
   - successful UART config creates a reproducible host-side UART context
   - TX and RX behavior is driven by a deterministic host buffer model
   - no dependency on real serial hardware is required for regression

This keeps the UART ABI practical while avoiding a stream-protocol redesign too early.

## 5. ABI Design

### 5.1 Capability Discovery

UART v1 must be discoverable through the Host ABI without speculative probing.

Recommended contract:

- add `LUAT_NDK_FEATURE_UART`
- keep host ABI version stable unless the capability discovery scheme itself changes

Guest code should be able to detect:

- foundation-only host
- foundation + GPIO host
- foundation + GPIO + UART host

### 5.2 Command Families

UART v1 adds five commands to the hostabi fixture protocol:

1. `UART_CONFIG`
   - inputs: `port`, `baud`, `data_bits`, `stop_bits`, `parity`, `rx_enable`
   - result: success or structured parameter/host error

2. `UART_TX`
   - inputs: `port`, exchange-buffer offset, byte length
   - result: bytes accepted or structured error

3. `UART_RX_STATE`
   - inputs: `port`
   - result: pending flag, buffered length, last RX reason

4. `UART_RX_READ`
   - inputs: `port`, exchange-buffer offset, max length
   - result: bytes copied plus updated authoritative state

5. `UART_RX_CLEAR`
   - inputs: `port`
   - result: success or structured error

The first implementation should support a single deterministic port path cleanly, but the command shape should keep `port` explicit so the ABI remains extensible.

### 5.3 Event Types

UART v1 adds one event type:

- `UART_RX_READY`

Event payload must encode enough information to identify:

- which UART port became readable
- why / what kind of RX-ready condition occurred

The event payload is notification-only; it should not attempt to carry the receive bytes themselves.

### 5.4 Error Model

UART v1 uses both:

- `status` in the command result
- `last_error` in host ABI state

Error categories should cover at least:

- `BAD_PORT`
- `BAD_CONFIG`
- `BAD_LENGTH`
- `BUSY`
- `OVERFLOW`
- `UNSUPPORTED`
- `HOST_ERROR`

Rule: failed UART operations must not produce success-shaped ownership or buffered-state side effects.

## 6. Runtime Behavior

### 6.1 Config Flow

Guest sends `UART_CONFIG`.

Host validates arguments, initializes or resets per-context UART state, and enables deterministic RX behavior if `rx_enable` is set.

### 6.2 TX Flow

1. guest places bytes in the exchange buffer
2. guest sends `UART_TX`
3. host validates range and copies bytes into the deterministic UART backend
4. host may optionally make the transmitted bytes observable through a deterministic loopback path

### 6.3 RX Flow

1. host places deterministic bytes into the per-context RX ring
2. host marks the port pending
3. host pushes `UART_RX_READY` into the event ring
4. guest uses `UART_RX_STATE` to inspect authoritative buffered length/state
5. guest uses `UART_RX_READ` to move bytes into the exchange buffer
6. guest uses `UART_RX_CLEAR` to acknowledge pending state

Notification and data movement are intentionally separate:

- **event ring** answers "UART RX is ready"
- **UART commands** answer "how much data is buffered, what bytes are available, and has pending state been acknowledged"

## 7. Deterministic PC Simulator Model

UART v1 should not depend on real COM devices for correctness tests.

The recommended first-step model is:

- per-context host RX ring
- deterministic injected RX payload on config or explicit fixture setup path
- optional TX→RX loopback in the same context

This gives the regression suite stable behavior while preserving a clean path to real-device bridging later.

The deterministic path must remain **context-local**:

- one context's RX state must not leak into another
- reset/deinit must release UART ownership and buffered state

## 8. File/Module Plan

### Modify

- `components/ndk/include/luat_ndk_abi.h`
  - add UART feature bit
  - add UART command IDs / status codes / event IDs
  - add any packed state layout helpers used by both host and guest

- `components/ndk/include/luat_ndk.h`
  - extend `luat_ndk_t` with per-context UART config, ownership, RX ring, and pending state

- `components/ndk/include/luat_ndk_host.h`
  - declare UART host helpers

- `components/ndk/src/luat_ndk.c`
  - initialize/reset/deinit UART state with other ABI state

- `components/ndk/src/luat_ndk_host.c`
  - keep top-level dispatch thin, route UART handling to a dedicated module

- `testcase/ndk/guest/hostabi_v1/protocol.h`
  - add UART v1 command and status constants

- `testcase/ndk/guest/hostabi_v1/main.c`
  - add UART fixture command branches

- `testcase/ndk/guest/hostabi_v1/ndk_stubs.c`
  - add UART guest helper stubs

- `testcase/ndk/ndk_hostabi_basic/scripts/hostabi_proto.lua`
  - add UART constants and narrow decode helpers

- `testcase/ndk/ndk_hostabi_basic/scripts/ndk_hostabi_test.lua`
  - add UART v1 regression coverage

- `components/ndk/README.md`
  - document the UART v1 command family and deterministic simulator model after implementation

### Create

- `components/ndk/src/luat_ndk_host_uart.c`
  - UART config validation
  - deterministic TX / RX handling
  - per-context RX ring logic
  - event emission helper for `UART_RX_READY`

## 9. Testing Strategy

### Red-Green Expectations

Add failing tests first for:

1. `UART_CONFIG` succeeds for a valid deterministic port
2. invalid config returns explicit error
3. `UART_TX` accepts bytes from the exchange buffer
4. `UART_RX_READY` appears in the event ring
5. `UART_RX_STATE` reports buffered bytes correctly
6. `UART_RX_READ` copies bytes into the exchange buffer correctly
7. `UART_RX_CLEAR` clears pending state
8. one context's UART activity does not leak into another

### Regression Safety

Every UART v1 change must continue to pass:

- `testcase\ndk\ndk_basic\scripts\`
- `testcase\ndk\ndk_hostabi_basic\scripts\`

### PC Simulator Constraint

UART v1 tests must remain reproducible in the PC simulator without requiring a physical serial device.

## 10. Success Criteria

UART v1 is complete when all of the following are true:

1. guest can configure a UART port through the Host ABI
2. guest can transmit bytes from the exchange buffer
3. guest can observe `UART_RX_READY` in the event ring
4. guest can query, read, and clear buffered RX state
5. UART capability is discoverable through `features`
6. multi-context isolation holds for UART state
7. both NDK suites remain green

## 11. Follow-On Compatibility

UART v1 should remain a focused buffered-I/O capability, not a generic stream framework.

If future SPI/I2C/VFS work needs larger data movement or richer host buffering, those families should reuse the same pattern proven here:

- structured control commands
- event-ring notification
- exchange-buffer payload movement
- explicit `status` + `last_error`

UART v1 is therefore both a feature and the template for future buffered host ABI families.
