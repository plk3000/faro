# FARO Presentation Summary

- **Snapshot:** September 18, 2026
- **Status:** Implemented FHL prototype; Phases 0-6 complete and device-facing
  gates physically validated.

This document is presentation source material. For canonical product and
safety details, use [`project-faro.md`](project-faro.md). For implementation
status, use [`IOS-TASKS.md`](IOS-TASKS.md).

The generated deck is available as
[`presentation/presentation.html`](presentation/presentation.html), with an
exported [`presentation/faro-presentation.pdf`](presentation/faro-presentation.pdf).

## Elevator pitch

**FARO — Familiar-space Awareness, Recognition, and Orientation** — is a
personalized assistive prototype co-designed with a blind user. It helps a
person remember familiar indoor places, request spoken descriptions of nearby
scenes, and receive immediate forward-obstacle tones from an independent
ESP32 module.

> **Remembering places. Recognizing hazards. Co-designed with lived
> experience.**

FARO is a secondary companion. It is not a replacement for a white cane, guide
dog, or orientation-and-mobility training.

## The problem

Familiar indoor spaces can still create practical challenges:

- becoming disoriented or entering the wrong room;
- identifying a location when lighting or approach angle changes;
- understanding what objects are nearby;
- noticing furniture or another obstacle in the forward path;
- accessing all of this without a visually demanding interface.

Generic object recognition alone does not solve the personal question, "Where
am I in my own environment?" FARO combines personal place memory, requested
scene narration, and a separate low-latency obstacle cue.

## The solution

| Capability | User value | How FARO implements it |
|---|---|---|
| Personal place memory | Learns names meaningful to the user and later answers "Where am I?" | Multi-view camera enrollment, on-device Vision embeddings, SwiftData storage, nearest-neighbour retrieval, and an explicit uncertain result |
| Scene narration | Answers "Describe" or "What is ahead?" with concise speech | User-requested still image, private authenticated vision API, localized prompt, and iPhone speech output |
| Immediate obstacle cue | Provides fast distance-based tones without waiting for cloud AI | HC-SR04 sonar, ESP32 filtering, and a local passive buzzer |
| Accessible control | Minimizes touch and supports the user's language | Large accessible controls, VoiceOver, English (US), Spanish, manual voice recording, and foreground Hands-Free commands |

## User experience

FARO has exactly two operating modes:

- **Inactive** is the iPhone app's default at every launch. Once synchronized,
  the ESP32 proximity tones and navigation-oriented iPhone output remain
  silent.
- **Navigating** arms the ESP32's local buzzer path and enables "Where am I?"
  and "What is ahead?"

An already-armed ESP32 intentionally retains Navigating across a BLE
disconnect so loss of the phone cannot silently disable its local warning
path. An ESP32 power cycle or reset always returns the module to Inactive.

The supported commands are:

- "Describe"
- "Where am I?"
- "Remember this as..."
- "What is ahead?"
- "Start navigation"
- "Stop navigation"

The commands also work in Spanish. A persisted, opt-in Hands-Free mode
uses Siri to foreground FARO, then listens on-device for `Hey FARO` or
`Hola FARO`. Manual Start/Finish recording remains available.

Voice place enrollment guides the user through a bounded nine-view,
approximately 180-degree left-to-right scan. Touch enrollment remains
available for manual enrollment and adding views.

## System architecture

```text
                         advisory context and narration
 user-requested still ------------------------------------+
       |                                                   |
       v                                                   v
+--------------------+      authenticated API      +----------------------+
| Native iPhone app  | --------------------------> | Private vision service|
|                    | <-------------------------- | + Azure OpenAI vision |
| - camera           |      concise description   +----------------------+
| - place memory     |
| - voice and speech |
| - mode control     | <--------- BLE telemetry/status --------+
+--------------------+                                          |
       | requested mode                                         |
       +----------------------------- BLE -----------------------+
                                                                 v
                                                       +------------------+
                                                       | ESP32 module     |
                                                       | sonar -> buzzer  |
                                                       +------------------+
```

### iPhone

The native iOS 26 app is the primary interface and orchestrator. It uses
SwiftUI, AVFoundation, Vision FeaturePrint, SwiftData, Core Location, Speech,
AVSpeechSynthesizer, and Core Bluetooth.

### Private vision service

The FastAPI backend validates authentication, request identifiers, image size,
and actual image content. It accepts JPEG, PNG, and HEIC, forwards normalized
content to an Azure OpenAI vision-capable deployment, and returns a concise
description in the requested language. Scene narration is advisory and never
controls the immediate warning path.

### ESP32 obstacle module

The ESP32 samples and filters one forward ultrasonic sensor, classifies the
distance band, drives a passive buzzer locally, and reports telemetry over a
versioned BLE contract. The iPhone automatically discovers the advertised FARO
service; no manual device picker is required.

The critical path is always:

```text
sonar -> ESP32 -> passive buzzer
```

It never becomes:

```text
sonar -> ESP32 -> iPhone -> AI -> warning
```

Once Navigating is armed, the local alert continues if Bluetooth, the app, or
AI processing fails. A board reset always returns the ESP32 to Inactive.

## Important design choices

- **Uncertainty over guessing:** place recognition names a location only when
  its distance and separation thresholds are satisfied.
- **Personal, not generic:** users provide their own place labels and several
  views; labels are never translated automatically.
- **Local where it matters:** place matching, command recognition, wake-phrase
  detection, and the immediate obstacle cue do not depend on cloud inference.
- **Explicit privacy boundaries:** FARO uploads only a user-requested still for
  live narration; it does not stream video. Saved place images remain in the
  app container, and temporary command recordings are deleted after
  transcription.
- **Failure-aware mode synchronization:** the app separates the requested mode
  from the mode confirmed by the ESP32 and removes stale telemetry instead of
  showing old data as current.
- **Testable without every device:** deterministic simulator substitutes cover
  image capture, embeddings, scene descriptions, and BLE behavior.

## Prototype hardware and software

| Area | Prototype choice |
|---|---|
| Phone | iPhone running iOS 26 |
| Mobile app | Swift 6, SwiftUI, XcodeGen |
| Camera and speech | AVFoundation, Speech framework, AVSpeechSynthesizer |
| Place recognition | Vision FeaturePrint and SwiftData |
| Location context | Recent coarse Core Location fix; never room-level GPS evidence |
| Wireless boundary | Core Bluetooth and a versioned custom GATT service |
| Obstacle module | CENFOTEC IdeaBoard/ESP32, HC-SR04-style sonar, passive buzzer, onboard NeoPixel |
| Vision backend | Python/FastAPI and a private Azure OpenAI vision deployment |
| Mechanical asset | Printable `FARO-holder.stl`; scale and physical fit are not yet validated |

## What has been demonstrated

Phases 0-6 are implemented and their device-facing gates have been accepted:

- rear-camera capture and spoken scene description on a physical iPhone;
- live authenticated image requests accepted by the backend;
- JPEG/PNG/HEIC content-aware upload metadata and strict server validation;
- personal place enrollment, storage, recognition, and uncertainty behavior;
- English (US) and Spanish UI, speech, and commands;
- manual and foreground Hands-Free voice flows;
- explicit Inactive/Navigating behavior;
- automatic iPhone-to-ESP32 discovery, mode control, and telemetry;
- ESP32 boot-to-Inactive and local sonar/buzzer behavior.

Automated tests cover the iOS workflows, backend contract, BLE codecs and state,
localization, persistence, place matching, and concurrency-sensitive voice
handoffs. The current iOS suite passes 117 tests, representing 168
parameterized runs, with zero failures. The generic physical-iOS build and
ESP32 host-side protocol test also pass.

## Suggested live demonstration

1. **Start safe:** reset or power the module, launch FARO, and show that both
   begin Inactive and silent.
2. **Show accessible control:** switch language or use a bilingual voice
   command.
3. **Teach a place:** say "Remember this as Kitchen" and follow the guided
   multi-view scan.
4. **Recognize it:** approach from another angle, enter Navigating, and ask
   "Where am I?"
5. **Request context:** ask FARO to describe the scene or what is ahead.
6. **Show the local reflex:** move a suitable obstacle through the documented
   sonar bands and hear the ESP32 buzzer cadence change without waiting for AI.
7. **Stop intentionally:** leave Navigating and confirm the local buzzer is
   silent.

Use the five scoped demonstration locations: kitchen, living room, bedroom,
front door, and office entrance.

## Honest limitations

- One forward sonar does not detect every hazard. It can miss thin, soft,
  angled, high or low obstacles, stairs, and drop-offs.
- Distance bands are prototype defaults, not validated safety limits.
- Vision narration can be wrong or unavailable and must remain advisory.
- Scene narration requires connectivity to the private backend; place
  recognition remains on-device.
- Coarse GPS can filter different sites but cannot identify rooms inside one
  house.
- Custom wake detection works only while FARO is foreground active; Siri or
  another supported action must first open the app.
- Recognition can degrade with substantial viewpoint or lighting changes and
  must report uncertainty instead of forcing a guess.
- The printable phone holder has not yet passed scale, fit, or wearing
  validation.

## Suggested presentation structure

| Slide | Focus | Recommended visual |
|---:|---|---|
| 1 | FARO name, expansion, and tagline | Product name plus lighthouse motif |
| 2 | The lived problem | Three concise indoor challenges |
| 3 | The three-part solution | Place memory, scene narration, local warning |
| 4 | User journey | Inactive -> Navigate -> Remember -> Recognize -> Describe |
| 5 | System architecture | iPhone/backend/ESP32 diagram from this document |
| 6 | Safety and failure design | Highlight the local `sonar -> ESP32 -> buzzer` path |
| 7 | Accessibility and bilingual interaction | English/Spanish commands and VoiceOver screenshots |
| 8 | Prototype demonstration | Photos or short clips of the app and physical module |
| 9 | What is validated | Phases 0-6 and physical integration evidence |
| 10 | Limits and responsible claims | Sonar gaps, advisory AI, foreground wake limitation |
| 11 | Closing value | Personalized assistance designed around lived experience |

## Presentation claim guardrails

**Say:**

- "assistive prototype" or "secondary companion";
- "forward-obstacle cue from one sonar";
- "physically integrated and validated through Phase 6";
- "reports uncertainty when recognition confidence is insufficient."

**Do not say:**

- "replaces a white cane or guide dog";
- "detects all hazards";
- "GPS identifies the room";
- "AI provides the immediate safety warning";
- "always listening in the background";
- "clinically validated," "production ready," or "proven safe."

## Closing message

FARO demonstrates that personalized place memory, requested visual context, and
an independent local obstacle cue can work together in one accessible,
bilingual prototype while keeping uncertainty, privacy, and failure behavior
explicit.
