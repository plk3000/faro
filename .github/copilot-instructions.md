# FARO Copilot Instructions

## Repository state and source of truth

- Treat `project-faro.md` as the canonical product, architecture, hardware, and prototype-scope document.
- The native iOS application lives under `ios/`. `ios/project.yml` is the source of truth for the generated Xcode project; do not hand-edit or commit `ios/FARO.xcodeproj`.
- `IOS-TASKS.md` is the implementation roadmap. The ESP32 firmware is intentionally maintained in a separate repository.
- Keep the project framed as a co-designed FHL prototype and secondary assistive companion, not as a replacement for a white cane, guide dog, or orientation-and-mobility training.

## Build and test

Install XcodeGen with `brew install xcodegen`, then run commands from `ios/`:

```bash
# Regenerate the ignored Xcode project after changing project.yml or adding files
xcodegen generate

# Build for the simulator
xcodebuild -project FARO.xcodeproj -scheme FARO \
  -destination 'platform=iOS Simulator,name=iPhone 17' build CODE_SIGNING_ALLOWED=NO

# Run all tests
xcodebuild test -project FARO.xcodeproj -scheme FARO \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO

# Run one Swift Testing test
xcodebuild test -project FARO.xcodeproj -scheme FARO \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  '-only-testing:FAROTests/ImageStoreTests/savesFixturesAsPersistentJPEGs()' \
  CODE_SIGNING_ALLOWED=NO
```

- If `iPhone 17` is unavailable, choose an installed device from `xcrun simctl list devices available`.
- Regenerate before building; XcodeGen discovers Swift source files from the configured source directories.
- No standalone lint command is configured.

## High-level architecture

- The native iPhone app is the primary interface and system orchestrator. It owns AVFoundation camera capture, vision-language scene narration, visual-embedding generation and storage, place retrieval, speech output, phone motion/location context, user-visible mode state, and Core Bluetooth communication.
- The ESP32 obstacle module is the independent low-latency warning subsystem. It reads and filters the forward sonar distance, drives the local passive buzzer, and publishes distance and warning state to the iPhone over BLE.
- Preserve the separation between the two paths:
  - Immediate warning: `sonar -> ESP32 -> passive buzzer`.
  - Context and narration: camera, phone sensors, and BLE telemetry -> iPhone recognition/narration -> speech.
- Immediate warnings must never wait for the iPhone, BLE, or an AI model. BLE telemetry may enrich spoken context but is not the safety path.
- Place learning captures several views, creates image embeddings, and stores them under a user-provided label. Recognition embeds the current frame, performs nearest-neighbour retrieval against saved examples, and names a place only above a confidence threshold; otherwise it reports uncertainty.
- Place data uses SwiftData `Place` and `PlaceSnapshot` models. Keep original JPEGs alongside model-tagged embedding payloads and automatically re-embed retained views when the production representation identifier changes.
- Use the complete Codable Vision FeaturePrint observation and Vision's official distance API on physical devices. The deterministic `PixelGridEmbedder` and its Euclidean distance are simulator-only test infrastructure and must not be treated as the production recognition model.
- Use recent coarse GPS only to filter candidates by site. Recognition must continue without location access, and GPS must never be presented as room-level evidence.

## Behavioral invariants

- FARO has exactly two explicit operating modes: **Inactive** and **Navigating**.
- Boot into **Inactive**. In this mode, proximity tones and hazard notifications remain silent regardless of sonar readings, although the ESP32 may stay powered and connected.
- **Navigating** arms the ESP32's local sonar-to-buzzer path and enables navigation-oriented iPhone context.
- The iPhone app is the prototype's primary mode control. Keep the current mode unambiguous in the app and provide distinct confirmation tones when entering or leaving Navigating mode.
- Do not persist the iOS operating mode. Route “Where am I?” and future iPhone proximity output through `OperatingModeController` so every fresh launch is Inactive and leaving Navigating cancels spoken navigation output.
- Once Navigating mode is armed, local obstacle alerts must continue if Bluetooth, the app, or AI processing fails.
- Use uncertainty rather than a confident guess when place-recognition confidence is insufficient. False confident identifications are a primary prototype metric.
- Keep scene and place commands minimal: `describe`, `where am I?`, `remember this as...`, and `what is ahead?`. The hands-free extension may additionally expose bilingual `start navigation` and `stop navigation` commands as explicit safety-mode controls.
- Preserve explicit Start/Finish recording as a fallback. Hands-Free is a persisted user opt-in: after Siri or another path foregrounds FARO, wait for competing audio to release, play a ready tone, and detect only `Hey FARO` / `Hola FARO` on-device. A wake phrase opens one bounded command window that ends on silence or timeout. Stop wake listening whenever the app leaves the foreground; do not claim custom wake activation while suspended or terminated, send ambient audio off-device, retain it as user content, or let FARO's own speech trigger the detector.
- Keep the video-only `AVCaptureSession` running, prevent it from configuring the shared audio session, suspend still-photo requests during bounded command capture, and never reintroduce camera stop/start cycles for voice input. Parse commands through `VoiceCommandParser`, route them through `VoiceCommandExecutor`, and preserve the Navigating gate for `where am I?` and `what is ahead?`.
- Treat language as explicit data. The prototype supports `en-US` and `es-MX`, plus a persisted Follow iPhone preference. Pass the resolved language through API requests, generated descriptions, speech synthesis, accessibility announcements, and future command recognition.
- Put user-facing UI, accessibility, error, and permission text in the String Catalogs. Do not translate user-provided place labels.

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
