# FARO ESP32 firmware

Firmware for FARO's local obstacle-awareness module, running on the CENFOTEC IdeaBoard (ESP32) reused from MiSumoBot.

## Hardware baseline

- **Sonar:** HC-SR04-style ultrasonic sensor
  - `TRIG`: GPIO 25
  - `ECHO`: GPIO 26, through a voltage divider or level shifter. The HC-SR04 ECHO signal is 5 V and must not connect directly to the ESP32's 3.3 V GPIO.
- **Required IdeaBoard jumper:** `SELECT` ↔ `Vin`
- **Passive buzzer:** GPIO 27 (`+` to GPIO 27, `−` to GND). This must be a small passive piezo unit suitable for 3.3 V GPIO drive; do not use the identified 5 V active buzzer here.

## Safety behavior

FARO boots in **Inactive** mode. Sonar readings may be measured and reported over BLE, but the local buzzer must remain silent until **Navigating** mode is explicitly armed. Once armed, the local `sonar → ESP32 → passive buzzer` alert path must operate independently of Bluetooth, iOS, or any AI service.

## BLE control and telemetry

The module advertises as `FARO-Obstacle` and implements the versioned GATT
boundary in [`../docs/ble-contract.md`](../docs/ble-contract.md):

- It boots **Inactive** and keeps the passive buzzer silent until iOS writes
  **Navigating** to the encrypted, bonded operating-mode characteristic.
- It accepts only one-byte mode values: `0x00` (Inactive) and `0x01`
  (Navigating), then reads/notifies the resulting mode.
- It publishes an eight-byte telemetry packet after each filtered sonar sample
  (up to 10 Hz), including distance validity, warning band, sequence, and mode.
- A BLE disconnect does **not** silently disarm an already-Navigating module;
  the autonomous local sonar-to-buzzer path continues until an explicit stop or
  board reset.

## Test, build, and flash

```bash
# Run from the repository root.
c++ -std=c++17 -Iesp32 esp32/tests/protocol_test.cpp \
  -o /tmp/faro-protocol-test
/tmp/faro-protocol-test
arduino-cli compile --fqbn esp32:esp32:esp32 esp32
arduino-cli board list
arduino-cli upload --port <PORT> --fqbn esp32:esp32:esp32 esp32
arduino-cli monitor --port <PORT> --config baudrate=115200
```

The iPhone connection and mode-control path passed physical acceptance on
September 17, 2026. Recheck all of the following after Bluetooth, power, sonar,
or mode-control changes:

1. Fresh boot reports `Mode: Inactive (buzzer disarmed)` and remains silent
   near an obstacle.
2. The iPhone discovers `FARO-Obstacle`, pairs, and receives mode/telemetry
   notifications.
3. Start navigation writes `0x01`, the module reports Navigating, and distance
   bands drive the local buzzer.
4. Stop navigation writes `0x00`, the module reports Inactive, and silences the
   buzzer immediately.
5. Disconnecting iPhone while Navigating leaves the local alert active; resetting
   the ESP32 returns it to silent Inactive mode.

Do not commit `secrets.h`; it is ignored by the repository.
