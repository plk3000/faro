# FARO Copilot Instructions

## Repository state and source of truth

- Treat `project-faro.md` as the canonical product, architecture, hardware, and prototype-scope document.
- The repository currently has no application source, firmware source, or checked-in build, test, or lint configuration. Do not invent commands; add exact full-suite and single-test commands here when those projects are introduced.
- Keep the project framed as a co-designed FHL prototype and secondary assistive companion, not as a replacement for a white cane, guide dog, or orientation-and-mobility training.

## High-level architecture

- The native iPhone app is the primary interface and system orchestrator. It owns AVFoundation camera capture, vision-language scene narration, visual-embedding generation and storage, place retrieval, speech output, phone motion/location context, user-visible mode state, and Core Bluetooth communication.
- The ESP32 obstacle module is the independent low-latency warning subsystem. It reads and filters the forward sonar distance, drives the local passive buzzer, and publishes distance and warning state to the iPhone over BLE.
- Preserve the separation between the two paths:
  - Immediate warning: `sonar -> ESP32 -> passive buzzer`.
  - Context and narration: camera, phone sensors, and BLE telemetry -> iPhone recognition/narration -> speech.
- Immediate warnings must never wait for the iPhone, BLE, or an AI model. BLE telemetry may enrich spoken context but is not the safety path.
- Place learning captures several views, creates image embeddings, and stores them under a user-provided label. Recognition embeds the current frame, performs nearest-neighbour retrieval against saved examples, and names a place only above a confidence threshold; otherwise it reports uncertainty.

## Behavioral invariants

- FARO has exactly two explicit operating modes: **Inactive** and **Navigating**.
- Boot into **Inactive**. In this mode, proximity tones and hazard notifications remain silent regardless of sonar readings, although the ESP32 may stay powered and connected.
- **Navigating** arms the ESP32's local sonar-to-buzzer path and enables navigation-oriented iPhone context.
- The iPhone app is the prototype's primary mode control. Keep the current mode unambiguous in the app and provide distinct confirmation tones when entering or leaving Navigating mode.
- Once Navigating mode is armed, local obstacle alerts must continue if Bluetooth, the app, or AI processing fails.
- Use uncertainty rather than a confident guess when place-recognition confidence is insufficient. False confident identifications are a primary prototype metric.
- Keep the prototype voice commands minimal and consistent with the concept: `describe`, `where am I?`, `remember this as...`, and `what is ahead?`.

## Hardware constraints

- Use the passive buzzer for programmable proximity cadence and pitch. Reserve the active buzzer for a simple fixed-pitch alarm.
- Do not design around a vibration motor or speech-capable external speaker; neither is available. Speech comes from the iPhone or the user's connected audio device.
- Never connect an HC-SR04's 5 V `ECHO` output directly to a 3.3 V ESP32 GPIO; require a voltage divider or level shifter.
- Treat the documented distance bands as prototype starting points, not validated safety limits: over 2 m silent, 1-2 m slow pulses, 0.5-1 m fast pulses, and under 0.5 m urgent repeating tones.
- Do not claim that one forward sonar detects all hazards. Its known gaps include thin, soft, angled, high/low obstacles, stairs, and drop-offs.

## Prototype scope and terminology

- Keep FHL work focused on learning and recognizing five demonstration locations: kitchen, living room, bedroom, front door, and office entrance.
- Preserve the project terminology and capitalization: **FARO**, **Inactive**, **Navigating**, **iPhone**, and **ESP32**.
- Evaluate changes against the prototype's stated measurements: recognition across angle and lighting changes, false confident identifications, response latency, obstacle range and misses, and whether alerts are useful or annoying to the actual user.
- When behavior, architecture, inventory, or prototype scope changes, update `project-faro.md` and these instructions together.
