# FARO ESP32 BLE contract

This document defines the version 1 Bluetooth Low Energy boundary between the
FARO iPhone app and the ESP32 obstacle module. It is the source of truth for
both implementations.

The ESP32 owns the immediate warning path:

`sonar -> ESP32 -> passive buzzer`

BLE is used to arm that local path and report telemetry. Sonar sampling,
distance filtering, warning classification, and buzzer timing must never wait
for the iPhone, Bluetooth, or an AI service.

## Advertising and discovery

| Item | Value |
|---|---|
| Advertised local name | `FARO-Obstacle` |
| Primary service UUID | `F0A00001-5E9B-4D7A-8C31-6B7E2D490001` |
| Telemetry characteristic UUID | `F0A00002-5E9B-4D7A-8C31-6B7E2D490001` |
| Operating-mode characteristic UUID | `F0A00003-5E9B-4D7A-8C31-6B7E2D490001` |

The ESP32 advertises the primary service UUID. The iPhone scans for that UUID
and connects to the first matching module. The FHL prototype assumes one FARO
module is nearby.

The ESP32 should use LE Secure Connections and bonding. At minimum, writes to
the operating-mode characteristic must require an encrypted link. Pairing and
bonding are enforced by the GATT server; Core Bluetooth handles the iPhone
pairing prompt.

## Telemetry characteristic

Properties: **Read**, **Notify**.

The ESP32 publishes one packet after each filtered sonar sample, up to 10 Hz.
All multibyte integers are unsigned and little-endian. Version 1 packets are
exactly eight bytes:

| Offset | Size | Field | Version 1 encoding |
|---|---:|---|---|
| 0 | 1 | Protocol version | `0x01` |
| 1 | 1 | Flags | Bit 0: distance valid; bit 1: ESP32 is armed in **Navigating**; bits 2-7: zero |
| 2 | 2 | Sequence | Wraparound sample counter |
| 4 | 2 | Distance | Millimetres, or `0xFFFF` when no valid echo is available |
| 6 | 1 | Warning state | Values below |
| 7 | 1 | Reserved | `0x00` |

Warning-state values:

| Value | Name | Distance classification |
|---:|---|---|
| 0 | Clear | At least 2 m |
| 1 | Slow | 1 m through less than 2 m |
| 2 | Fast | 0.5 m through less than 1 m |
| 3 | Urgent | Less than 0.5 m |
| 4 | Sensor unavailable | No valid echo; distance must be `0xFFFF` |

The warning state is the current sonar classification, not a claim that the
buzzer is sounding. The ESP32 drives the buzzer only when the Navigating flag
is set. While **Inactive**, it may continue measuring and notifying, but the
local buzzer remains silent regardless of the reported warning state.

Receivers reject packets with an unknown version, incorrect length, nonzero
reserved bits, an unknown warning state, or an inconsistent distance-validity
combination. The iPhone treats telemetry as stale if no valid packet arrives
for two seconds and does not display the old distance as current.

## Operating-mode characteristic

Properties: **Read**, **Write with response**, **Notify**.

The value is exactly one byte:

| Value | Mode |
|---:|---|
| 0 | **Inactive** |
| 1 | **Navigating** |

The ESP32:

1. boots into **Inactive** before starting BLE;
2. validates a one-byte write and ignores any unsupported value;
3. applies a valid mode atomically;
4. responds to the write and notifies the resulting value;
5. returns the current value on reads.

The iPhone does not report the ESP32 mode as synchronized until it reads or is
notified of the matching value.

## Connection and recovery behavior

- On discovery, the iPhone subscribes to telemetry and mode notifications,
  then writes its current `OperatingModeController` mode.
- Every fresh iPhone app launch begins **Inactive**, so its first successful
  synchronization disarms the module.
- If the iPhone changes mode while disconnected, it sends the newest mode when
  the connection is restored.
- If BLE disconnects while **Navigating**, the ESP32 stays armed and the local
  sonar-to-buzzer path continues. A disconnect is never an implicit Inactive
  command.
- If the iPhone backgrounds, it may disconnect. Re-entering the foreground
  restarts scanning and resynchronizes the current in-memory mode.
- An ESP32 reset, watchdog reset, or power cycle always returns to
  **Inactive**. Navigating mode is not persisted in flash.
- The iPhone clears displayed telemetry on disconnect and retries discovery.
  Loss of telemetry must not be presented as a clear path.

Write failures, missing characteristics, malformed packets, and stale telemetry
are visible diagnostics. They do not create success-shaped fallback data and
do not alter the ESP32's independent local warning behavior.

## Prototype limits

The distance bands are starting points for evaluation, not validated safety
limits. One forward sonar can miss thin, soft, angled, high or low obstacles,
stairs, and drop-offs. The BLE status UI is a diagnostic view; it does not turn
the iPhone into the immediate warning path.
