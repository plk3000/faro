# FARO ESP32 firmware

Firmware for FARO's local obstacle-awareness module, running on the CENFOTEC IdeaBoard (ESP32) reused from MiSumoBot.

## Hardware baseline

- **Sonar:** HC-SR04-style ultrasonic sensor
  - `TRIG`: GPIO 25
  - `ECHO`: GPIO 26, through a voltage divider or level shifter. The HC-SR04 ECHO signal is 5 V and must not connect directly to the ESP32's 3.3 V GPIO.
- **Required IdeaBoard jumper:** `SELECT` ↔ `Vin`
- **Passive-buzzer POC:** GPIO 27 (`+` to GPIO 27, `−` to GND). This must be a small passive piezo unit suitable for 3.3 V GPIO drive; do not use the identified 5 V active buzzer here.

## Safety behavior

FARO boots in **Inactive** mode. Sonar readings may be measured and reported over BLE, but the local buzzer must remain silent until **Navigating** mode is explicitly armed. Once armed, the local `sonar → ESP32 → passive buzzer` alert path must operate independently of Bluetooth, iOS, or any AI service.

## Planned contents

- Arduino sketch and supporting C++ source
- `secrets.example.h` if device-specific configuration becomes necessary
- BLE implementation matching `docs/ble-contract.md` once that contract exists

Do not commit `secrets.h`; it is ignored by the repository.
