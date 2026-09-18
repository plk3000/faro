# FARO ESP32 distance-feedback bench POC

## Board

- CENFOTEC IdeaBoard / ESP32
- Arduino-ESP32 board package index:
  `https://espressif.github.io/arduino-esp32/package_esp32_index.json`

## Library

- Adafruit NeoPixel

## Pins

- HC-SR04 trigger: GPIO 25
- HC-SR04 echo: GPIO 26 — **through a 5 V to 3.3 V voltage divider or level shifter**
- Onboard WS2812B / NeoPixel: GPIO 2
- Passive buzzer: GPIO 27 (`+` to GPIO 27, `−` to GND)

## Connection

- Install the IdeaBoard `SELECT` ↔ `Vin` jumper; the ultrasonic sensor needs it.
- Connect HC-SR04 VCC and GND to the IdeaBoard as specified by the CENFOTEC reference hardware.
- Never connect the sonar's 5 V ECHO output directly to ESP32 GPIO 26.

## LED and passive-buzzer behavior

- No valid echo: purple LED and silent buzzer
- Less than 0.5 m: red LED and 2.2 kHz urgent pulses
- 0.5–1 m: amber LED and 1.6 kHz fast pulses
- 1–2 m: blue LED and 1.2 kHz slow pulses
- Over 2 m: LED and buzzer off

This is a bench electronics proof of concept. It deliberately enables the buzzer to validate the hardware; it is not a user-facing hazard-warning feature and does not yet implement FARO's Inactive/Navigating mode gate.
