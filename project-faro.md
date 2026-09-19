# Project FARO

**Status:** implemented FHL prototype; Phases 0-6 complete, device-facing gates physically validated, Phase 7 harness implemented and real-user evaluation pending

**Created:** 2026-09-03

**Origin:** Ghost's employer runs periodic week-long **FHL (Fix, Hack, Learn)** events.

Presentation source material is maintained in
[`PRESENTATION-SUMMARY.md`](PRESENTATION-SUMMARY.md).
The generated reveal.js deck and PDF live under `presentation/`.

## Purpose

FARO is a personalized visual landmark-memory and hazard-awareness prototype for blind users, inspired by and co-designed with Ghost's father, who is blind.

The immediate problems are that his father can:

- become disoriented or lost inside his own house;
- enter the wrong room;
- bump into furniture and other obstacles.

FARO is intended as a secondary assistive companion, not a replacement for a white cane, guide dog, or orientation-and-mobility training.

## Name and tagline

**FARO** — Familiar-space Awareness, Recognition, and Orientation.

“Faro” means lighthouse in Spanish.

**Tagline:** Remembering places. Recognizing hazards. Co-designed with lived experience.

## Core behavior

FARO combines three separate functions:

1. **Scene narration:** describe nearby objects and what lies ahead.
2. **Personal place memory:** learn user-named places such as the kitchen, bedroom, living room, and front door, then recognize them later.
3. **Immediate hazard warning:** detect nearby obstacles locally and issue
   passive-buzzer tones without waiting for a language model.

Example output:

> “You are in the kitchen. There is a chair ahead and slightly to your left.”

## Operating modes

FARO must have an explicit user-controlled operating mode so proximity feedback
is intentional rather than a constant nuisance around nearby people or objects.

### Inactive mode (default)

- No proximity tones or hazard notifications.
- The ESP32 may remain powered and connected over BLE, but its local alert path
  is disarmed.
- Use this mode while seated, conversing closely with someone, or otherwise not
  actively moving through space.

### Navigating mode

- Arms the local `sonar → ESP32 → passive buzzer` proximity-warning path.
- Enables the iPhone's navigation-oriented spoken context, including “where am
  I?” and “what is ahead?” when requested.
- Is intended only while the user is actively moving through the environment.

The iPhone app is the primary mode control for the FHL prototype. FARO boots
into **Inactive** mode and makes the current mode unambiguous through
an app-visible state and a distinct confirmation tone when entering or leaving
Navigating mode. A later hardware control may be added only after real-user
validation.

The iOS mode state is intentionally not persisted, so every fresh app launch
returns to Inactive. “Where am I?” and any iPhone proximity output pass
through the same navigation gate, and leaving Navigating cancels any active
spoken navigation output.

The iPhone synchronizes each mode transition to the ESP32 over the versioned
GATT contract in `docs/ble-contract.md`. The app distinguishes its requested
mode from the mode confirmed by the ESP32. A BLE disconnect never acts as an
Inactive command: if the ESP32 was already armed, its local warning path
continues until an explicit Inactive command or a device reset. On reconnect,
the iPhone sends its current in-memory mode; a fresh app process therefore
resynchronizes the module to Inactive.

## Place-recognition approach

When the user says “remember this as the kitchen,” FARO captures several views, creates image embeddings, and stores them with the label `kitchen`.

Later, the current camera frame is converted into an embedding and compared with saved examples using nearest-neighbour retrieval. The system names the place only when confidence is high; otherwise it reports that the location is uncertain.

The iOS prototype stores places and their snapshots with SwiftData. Physical
devices persist Apple's complete Codable Vision FeaturePrint observation and
compare observations with Vision's official distance API. The simulator uses a
deterministic pixel-grid embedding only so the complete workflow remains
testable without camera or Vision hardware support. Original JPEGs are retained,
and FARO automatically re-embeds saved views when the model or representation
identifier changes.

Coarse, recent iPhone location fixes gate candidates by site but never attempt
to distinguish rooms within one house. Visual matching remains authoritative,
works without location permission, and reports uncertainty instead of guessing.
Compass, accelerometer/gyroscope, known Wi-Fi networks, or BLE beacons may be
evaluated later.

## FHL prototype architecture

### iPhone

The primary interface is a native iPhone app. It provides:

- rear-camera capture through AVFoundation;
- scene descriptions using a vision-language model;
- embedding generation and storage for visual place recognition;
- speech output;
- phone motion/location context;
- Core Bluetooth communication with the ESP32, including mode synchronization
  and diagnostic sonar telemetry.

The runtime layers and responsibilities of every tracked iOS file are mapped in
`ios/HIGH-LEVEL-DESIGN.md`.

The phone would be chest-mounted or carried in a forward-facing harness so the
camera does not depend on handheld aiming. The repository includes the
printable prototype model `FARO-holder.stl`; STL files do not encode units, and
its slicer scale and physical fit still require validation before use.

### Private Azure OpenAI vision service

For FHL scene narration, live mode sends a user-requested camera frame to the
private API under `backend/`, backed by an Azure OpenAI vision deployment. The
service returns a short accessibility-oriented description for the iPhone to
speak. The current client requests `brief` detail and supplies a localized
safety-focused prompt; the service constrains that context behind its own
grounding, language, and hazard-priority instructions.

```text
user-requested camera frame → authenticated FARO API → Azure OpenAI vision model
                                                     → concise description → iPhone speech
```

The API is a **private, single-account service**, not a public provider proxy:

- The iPhone authenticates to the FARO API; it never receives or stores the
  Azure credential.
- The server keeps Azure credentials server-side and binds locally or behind a
  private authenticated network path.
- The service validates MIME type and image size, rate-limits calls, avoids
  logging image payloads or descriptions containing sensitive visual details,
  and discards the upload after the request. Place-learning images are stored
  separately in the iPhone app container only after an explicit enrollment
  action.
- The service must use a vision-capable deployment and return a clear
  unavailable/error response rather than silently sending an image to a
  text-only model.
- This path is advisory narration only. It is never in the immediate obstacle
  warning path and cannot delay or suppress the local sonar alert.

This design is appropriate for personal FHL testing. A multi-user or public
deployment needs a separate credential and access-control model; it must not
share one account's provider credential across users.

### ESP32 obstacle module

An ESP32 with an ultrasonic/sonar sensor provides the fast local reflex:

- measure forward distance;
- filter noisy readings;
- drive a local audible alert directly;
- send distance and warning state to the iPhone over BLE.

The version 1 BLE service uses separate telemetry and operating-mode
characteristics. Telemetry is an eight-byte, little-endian packet carrying a
protocol version, validity and mode flags, a sequence number, distance in
millimetres, and the warning classification. The iPhone rejects malformed or
unknown packets and removes readings that become stale. The simulator uses a
mock obstacle peripheral so scanning, mode synchronization, telemetry display,
and disconnect handling remain testable without hardware.

The checked-in firmware under `esp32/` implements this service and the local
mode gate. The iPhone-to-ESP32 connection, boot-to-Inactive behavior, and
Start/Stop navigation control were physically accepted on September 17, 2026.
Disconnect retention and reset-to-Inactive remain explicit hardware regression
checks.

**Available output inventory:** no free vibration motor is available; the only
DC motors are already soldered to another board. The confirmed audio parts are
one passive buzzer and one active buzzer, not a speech-capable speaker. Use the
**passive buzzer** for distinct programmable proximity tones; reserve the active
buzzer for a simple fixed-pitch alarm. The iPhone remains the speech/narration
output through its built-in speaker or the user's connected audio device.

The safety path must remain local:

`sonar → ESP32 → passive buzzer`

It must not depend on:

`sonar → ESP32 → iPhone → AI → warning`

The iPhone may use the BLE reading to add spoken context, but, while FARO is in
Navigating mode, immediate audible alerts continue if Bluetooth, the app, or the
AI fails. Inactive mode must remain silent regardless of the sonar reading.

If using an HC-SR04, its 5 V `ECHO` output must not connect directly to a 3.3 V ESP32 GPIO. Use a voltage divider or level shifter.

One sonar is suitable for a proof of concept but can miss thin, soft, angled, high/low obstacles, stairs, and drop-offs. A later design may use left/centre/right sensors, a downward sensor, or replace/add time-of-flight depth sensors.

## Prototype interaction

Keep commands minimal:

- “describe”
- “where am I?”
- “remember this as…”
- “what is ahead?”
- “start navigation”
- “stop navigation”

The validated fallback recognizes commands on-device with
`SFSpeechRecognizer` in the selected English or Spanish locale using
explicit Start and Finish controls. The Phase 5 hands-free extension keeps
those controls while adding a persisted opt-in flow: the user says “Siri, open
FARO”; after FARO reaches the foreground and Siri releases the microphone, FARO
plays a ready tone and listens on-device for “Hey FARO” or “Hola FARO.” A wake
phrase opens one bounded command window that ends automatically on silence or a
timeout, then the listener re-arms.

The foreground wake listener uses iOS 26 `SpeechAnalyzer` with a streaming
`SpeechTranscriber`; `SpeechDetector` supplies on-device voice-activity gating.
FARO resolves an equivalent supported locale at runtime and installs required
speech assets locally. If the analyzer or selected locale is unavailable, FARO
reports the limitation and leaves the explicit Start/Finish
`SFSpeechRecognizer` path available instead of sending ambient audio to a
service.

FARO does not claim a custom wake phrase while suspended or terminated. It
stops wake listening whenever it leaves the foreground, never sends ambient
audio to a service, and suppresses detection while speaking so it cannot
trigger itself. “Where am I?” and “what is ahead?” still require Navigating
mode; bilingual start/stop navigation commands provide hands-free mode control.
“Remember this as…” speaks movement guidance and automatically captures nine
timed views across an approximately 180-degree left-to-right sweep. The existing
guided enrollment screen remains available for touch-based enrollment and
adding more views.

Camera and microphone work remain serialized without restarting the live video
session: still-photo requests are suspended during command capture, the camera
cannot configure the shared audio session, and bounded command audio is
transcribed on-device only after capture finishes.

### Prototype languages

The iPhone prototype supports English (United States) and Spanish.
The user may follow the iPhone language or select either language explicitly.
That preference applies consistently to visible UI, accessibility labels,
scene-description requests, spoken output, and later voice commands. Personal
place labels remain exactly as entered and are not translated automatically.

Possible proximity feedback (passive-buzzer cadence/pitch):

- over 2 m: silent;
- 1–2 m: slow tone pulses;
- 0.5–1 m: fast tone pulses;
- under 0.5 m: urgent repeating tone.

Thresholds must be validated and adjusted with Ghost's father.

## FHL demonstration scope

Teach FARO five locations:

- kitchen;
- living room;
- bedroom;
- front door;
- office entrance.

Demonstrate learning a room, leaving, returning from another angle, identifying the room, narrating the scene, and warning about an approaching chair.

Measure:

- recognition across different angles and lighting;
- false confident identifications;
- response latency;
- obstacle-detection range and misses;
- whether alerts are useful or annoying to the actual user.

The Phase 7 iPhone harness records known and unknown ground truth, angle,
lighting, selected language, raw matcher distances, active thresholds, and
capture-to-match latency. It also records structured field observations for
language, narration pacing, wake behavior, and proximity alerts. Its versioned
JSON export contains aggregate and raw results, but no images, audio, GPS
coordinates, or scene descriptions.

The harness makes evaluation repeatable; it is not itself evidence that the
defaults are correct. Recognition thresholds, narration pacing, language
defaults, and proximity bands remain unchanged until the actual user trials
support an adjustment. CLIP remains conditional on measured FeaturePrint
recall.

## Apple developer requirement

A paid Apple Developer Program membership is **not required** for the FHL prototype. A Mac, Xcode, a free Apple Account, an iPhone, and Developer Mode are sufficient for Personal Team device testing.

Free provisioning requires the app to be rebuilt/reprovisioned periodically (typically every seven days). Paid membership is useful later for TestFlight, App Store distribution, multiple testers, and less-fragile long-term deployment. Apple's paid program is USD 99 per membership year or local equivalent.

## Project framing

> A personalized visual landmark-memory and hazard-awareness prototype, co-designed with a blind user.

## References

- [Apple membership comparison](https://developer.apple.com/support/compare-memberships/)
- [Apple AVFoundation capture setup](https://developer.apple.com/documentation/avfoundation/capture-setup)
- [Apple Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)
- [ESP32 BLE GATT server documentation](https://docs.espressif.com/projects/esp-idf/en/stable/esp32/api-reference/bluetooth/esp_gatts.html)
- [Azure OpenAI vision-enabled chat completions](https://learn.microsoft.com/azure/ai-foundry/openai/how-to/gpt-with-vision)
- [Seeing AI](https://www.seeingai.com/)
- [Visual Place Recognition research example](https://openaccess.thecvf.com/content/CVPR2024W/FedVision-2024/papers/Dutto_Collaborative_Visual_Place_Recognition_through_Federated_Learning_CVPRW_2024_paper.pdf)
