# FARO ESP32 hardware and dependencies

## Board

- CENFOTEC IdeaBoard / ESP32
- Arduino-ESP32 board package index:
  `https://espressif.github.io/arduino-esp32/package_esp32_index.json`

## Libraries

- Adafruit NeoPixel
- ESP32 Arduino core BLE library (`BLEDevice.h`, included with `esp32:esp32`)

## Pins

- HC-SR04 trigger: GPIO 25
- HC-SR04 echo: GPIO 26 — **through a 5 V to 3.3 V voltage divider or level shifter**
- Onboard WS2812B / NeoPixel: GPIO 2
- Passive buzzer: GPIO 27 (`+` to GPIO 27, `−` to GND)

## Connection

- Install the IdeaBoard `SELECT` ↔ `Vin` jumper; the ultrasonic sensor needs it.
- Connect HC-SR04 VCC and GND to the IdeaBoard as specified by the CENFOTEC reference hardware.
- Never connect the sonar's 5 V ECHO output directly to ESP32 GPIO 26.

## Mechanical asset

- `../FARO-holder.stl` is the printable prototype holder model.
- STL files do not encode units. Confirm slicer scale, print orientation, and
  physical fit before using the holder; no print/fit acceptance is recorded.

## LED and passive-buzzer behavior

- No valid echo: purple LED
- Less than 0.5 m: red LED
- 0.5–1 m: amber LED
- 1–2 m: blue LED
- Over 2 m: LED off

The firmware boots **Inactive**, where the buzzer is silent for every reading.
After the encrypted BLE mode characteristic arms **Navigating**, the same bands
produce 2.2 kHz urgent, 1.6 kHz fast, 1.2 kHz slow, or silent output. The bands
remain prototype starting points and require Phase 7 user evaluation; they are
not validated safety limits.
