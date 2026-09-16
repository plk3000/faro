# Project FARO

**Status:** concept / planned FHL prototype  
**Created:** 2026-09-03  
**Origin:** Ghost's employer runs periodic week-long **FHL (Fix, Hack, Learn)** events.

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
3. **Immediate hazard warning:** detect nearby obstacles locally and issue vibration or audio alerts without waiting for a language model.

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

The iPhone app will be the primary mode control for the FHL prototype. FARO
must boot into **Inactive** mode and make the current mode unambiguous through
an app-visible state and a distinct confirmation tone when entering or leaving
Navigating mode. A later hardware control may be added only after real-user
validation.

The iOS mode state is intentionally not persisted, so every fresh app launch
returns to Inactive. “Where am I?” and future iPhone proximity output pass
through the same navigation gate, and leaving Navigating cancels any active
spoken navigation output.

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

The preferred prototype platform is an iPhone running a native iOS app. It provides:

- rear-camera capture through AVFoundation;
- scene descriptions using a vision-language model;
- embedding generation and storage for visual place recognition;
- speech output;
- phone motion/location context;
- BLE communication with the ESP32.

The phone would be chest-mounted or carried in a forward-facing harness so the camera does not depend on handheld aiming.

### ESP32 obstacle module

An ESP32 with an ultrasonic/sonar sensor provides the fast local reflex:

- measure forward distance;
- filter noisy readings;
- drive a local audible alert directly;
- send distance and warning state to the iPhone over BLE.

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

### Prototype languages

The iPhone prototype supports English (United States) and Spanish (Mexico).
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
- [Seeing AI](https://www.seeingai.com/)
- [Visual Place Recognition research example](https://openaccess.thecvf.com/content/CVPR2024W/FedVision-2024/papers/Dutto_Collaborative_Visual_Place_Recognition_through_Federated_Learning_CVPRW_2024_paper.pdf)
