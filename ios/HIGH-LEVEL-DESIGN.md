# FARO iOS High-Level Design

This document is a high-level map of the native iPhone application. It
describes the major runtime flows and the purpose of every tracked file under
`ios/`. Product and safety intent remain canonical in
[`../project-faro.md`](../project-faro.md); implementation status remains in
[`../IOS-TASKS.md`](../IOS-TASKS.md).

## Design principles

- The iPhone orchestrates camera capture, scene narration, place memory,
  speech, operating mode, and BLE diagnostics.
- Immediate obstacle warnings remain local to the ESP32:
  `sonar -> ESP32 -> passive buzzer`. The iOS app is not in that safety path.
- Every fresh app process starts **Inactive**. Operating mode is deliberately
  not persisted.
- Protocol boundaries provide deterministic simulator and test substitutes for
  camera, embeddings, scene descriptions, location, speech, and Bluetooth.
- Language is explicit data. UI, accessibility, API requests, speech, and
  command recognition resolve to `en-US` or `es-MX`.
- Place recognition returns uncertainty when absolute distance or separation
  thresholds are not met.

## Runtime composition

```text
FAROApp
`-- ContentView
    |-- CaptureViewModel
    |   |-- ImageSource
    |   |   |-- CameraImageSource (physical iPhone)
    |   |   `-- FixtureImageSource (simulator)
    |   |-- SceneDescribing
    |   |   |-- FAROVisionClient (live)
    |   |   `-- MockSceneDescriber (mock)
    |   |-- ImageEmbedder
    |   |   |-- VisionFeaturePrintEmbedder (physical iPhone)
    |   |   `-- PixelGridEmbedder (simulator)
    |   |-- ImageStore + SwiftData Place/PlaceSnapshot
    |   |-- LocationProvider
    |   `-- SpeechOutput
    |-- OperatingModeController
    |   `-- ObstacleModuleViewModel
    |       |-- CoreBluetoothObstacleModuleTransport (physical iPhone)
    |       `-- MockObstaclePeripheral (simulator)
    |-- EvaluationViewModel -> EvaluationStore
    |-- VoiceCommandViewModel
    `-- HandsFreeVoiceViewModel
```

`FAROApp` creates the SwiftData container. `ContentView` is the composition
root: it owns the observable controllers, reads persisted places and
preferences, coordinates app lifecycle, and presents the feature views.
Concrete factories select simulator or physical implementations at compile
time; scene description independently selects mock or live mode from build
configuration.

## Main data flows

### Capture and scene description

1. A touch or voice action asks `CaptureViewModel` for a still image.
2. `CameraImageSource` captures on a physical iPhone;
   `FixtureImageSource` supplies a bundled image in the simulator.
3. `CapturedImage` validates the byte container. JPEG camera output is decoded
   and normalized; PNG and HEIC retain their detected format.
4. `SceneDescriberFactory` routes to the mock or authenticated HTTP client.
5. `FAROVisionClient` derives multipart filename and MIME type from the
   validated bytes, sends locale/detail/prompt options, and validates the
   response language.
6. The result is displayed and spoken through `SpeechOutput`.

### Place enrollment and recognition

1. Enrollment captures one or more views; voice enrollment uses a bounded
   nine-view left-to-right scan.
2. `ImageStore` retains normalized JPEGs in Application Support.
3. The active `ImageEmbedder` creates a model-tagged representation.
4. `PlaceSnapshot` stores the image filename, embedding metadata, optional
   coarse location, and heading under a SwiftData `Place`.
5. Recognition embeds a current frame, re-embeds retained views if the
   representation identifier changed, and filters candidates by coarse site
   when a usable GPS fix exists.
6. `PlaceMatcher` applies nearest-neighbour distance and separation thresholds,
   returning a confident place or an explicit uncertain result.

### Voice and Hands-Free

Manual Start/Finish and Hands-Free share the same parser and executor.
`VoiceInputCoordinator` suspends still-photo requests without stopping the
video-only camera session, records one bounded command, releases the
microphone, then resumes still capture. `VoiceCommandParser` recognizes the six
bilingual commands, and `VoiceCommandExecutor` invokes the existing capture,
place, or mode flow.

When the persisted Hands-Free preference is enabled and FARO is foreground
active, `HandsFreeVoiceViewModel` arms `OnDeviceWakePhraseDetector` after any
competing Siri audio releases. iOS 26 Speech APIs detect only `Hey FARO` or
`Hola FARO` on-device. A wake phrase opens one silence-bounded command window.
Listening stops when the app leaves the foreground and remains disarmed while
FARO speaks.

### Operating mode and BLE

`OperatingModeController` owns the in-memory **Inactive**/**Navigating** state
and gates navigation-oriented iPhone output. `ObstacleModuleViewModel` sends
the requested mode through its transport and keeps it separate from the value
confirmed by the ESP32 characteristic. It decodes versioned telemetry and
removes readings after two seconds without a valid packet.

The physical transport automatically scans for the FARO service UUID; no device
picker is used. A Bluetooth disconnect does not send an Inactive command. If
the ESP32 was already armed, its local warning path continues independently.

### Evaluation

The Evaluation screen runs silent diagnostic recognition captures with
operator-selected known or unknown ground truth, angle, lighting, and current
language. `PlaceMatcher` returns both its final decision and raw nearest
diagnostics so rejected samples remain useful for threshold analysis.

`EvaluationStore` persists versioned JSON under Application Support.
`EvaluationSummary` aggregates accuracy, known-place recall, unknown-place
rejection, false confident identifications, and latency overall and by angle,
lighting, and language. Field observations record usefulness/annoyance and
structured proximity evidence. A user-triggered export includes records and
configuration, but no images, audio, GPS coordinates, or scene descriptions.

## State, storage, and concurrency

| State | Storage/lifetime |
|---|---|
| Places and snapshot metadata | SwiftData |
| Captured and enrolled JPEGs | Application Support through `ImageStore` |
| Evaluation trials and field observations | Application Support through `EvaluationStore` |
| Language and Hands-Free preferences | `@AppStorage` |
| Operating mode | Memory only; every launch begins Inactive |
| Voice command audio | Temporary file, removed after transcription |
| Wake-phrase audio | Streamed only through on-device Speech APIs |

UI controllers and Apple framework delegates that affect UI state are
main-actor isolated. `ImageStore`, `EvaluationStore`, and
`FixtureImageSource` are actors. Camera session work stays on a dedicated
serial queue, while the still-capture continuation is lock-protected. The
protocol boundaries are `Sendable` where they cross concurrency domains.

## File guide

All paths below are relative to `ios/`.

### Project and build configuration

| File | Purpose |
|---|---|
| `HIGH-LEVEL-DESIGN.md` | This architecture overview and tracked-file guide. |
| `project.yml` | XcodeGen source of truth for the iOS 26 app/test targets, Swift 6 settings, resources, generated Info.plist, and scheme. |
| `Config/Shared.xcconfig` | Safe defaults for mock vision mode; optionally includes the ignored local override. |
| `Config/Local.xcconfig.example` | Placeholder template for a developer's live endpoint and client token configuration. |

### Application composition

| File | Purpose |
|---|---|
| `FARO/FAROApp.swift` | SwiftUI entry point; presents `ContentView` and creates the `Place`/`PlaceSnapshot` SwiftData container. |
| `FARO/ContentView.swift` | Root accessible UI and composition root for capture, place, mode, voice, Hands-Free, BLE, evaluation, preferences, and scene lifecycle. |

### Core Bluetooth

| File | Purpose |
|---|---|
| `FARO/Core/Bluetooth/ObstacleModuleProtocol.swift` | Mirrors the BLE UUIDs, warning bands, versioned telemetry packet, one-byte mode codec, errors, and connection states. |
| `FARO/Core/Bluetooth/ObstacleModuleTransport.swift` | Defines the transport boundary and implements the physical Core Bluetooth central plus the simulator mock peripheral. |
| `FARO/Core/Bluetooth/ObstacleModuleViewModel.swift` | Converts transport events into localized observable state, synchronizes requested/confirmed mode, rejects bad packets, and expires stale telemetry. |

### Core configuration and localization

| File | Purpose |
|---|---|
| `FARO/Core/Configuration/AppConfiguration.swift` | Loads mock/live vision settings from Info.plist and validates endpoint and token requirements. |
| `FARO/Core/Configuration/AppLocalization.swift` | Defines application string keys, catalog routing, typed localized messages, formatting, and generic error mapping. |
| `FARO/Core/Configuration/FAROLanguage.swift` | Defines supported languages, persisted preference resolution, API prompts, and simulator descriptions. |

### Core evaluation

| File | Purpose |
|---|---|
| `FARO/Core/Evaluation/EvaluationModels.swift` | Defines recognition ground truth, field observations, outcome classification, aggregate metrics, configuration snapshots, and the versioned export schema. |
| `FARO/Core/Evaluation/EvaluationStore.swift` | Actor that persists evaluation data and writes the shareable JSON report. |

### Core scene description and speech

| File | Purpose |
|---|---|
| `FARO/Core/Description/SceneDescribing.swift` | Defines the scene-description value, service protocol, and shared errors. |
| `FARO/Core/Description/MockSceneDescriber.swift` | Provides deterministic localized success, failure, and timeout behavior without a backend. |
| `FARO/Core/Description/SceneDescriberFactory.swift` | Selects mock or live description from configuration and exposes configuration failures through the protocol. |
| `FARO/Core/Description/FAROVisionClient.swift` | Implements authenticated multipart requests, localized options, finite retry behavior, MIME metadata, and response/error validation. |
| `FARO/Core/Description/SpeechOutput.swift` | Owns speech synthesis/audio-session behavior, accessible pacing, VoiceOver announcements, cancellation, and complete-queue tracking. |

### Core imaging

| File | Purpose |
|---|---|
| `FARO/Core/Imaging/ImageSource.swift` | Defines still-image capture, localized errors, and the simulator/physical factory. |
| `FARO/Core/Imaging/CapturedImage.swift` | Holds captured bytes and timestamp, validates JPEG/PNG/HEIC containers, and normalizes camera JPEG output. |
| `FARO/Core/Imaging/CameraImageSource.swift` | Runs the rear AVFoundation capture session, prefers JPEG, produces validated stills, and suspends still requests during voice capture. |
| `FARO/Core/Imaging/FixtureImageSource.swift` | Actor that cycles through bundled PNG fixtures for simulator and tests. |
| `FARO/Core/Imaging/ImageStore.swift` | Actor that stores, lists, loads, and deletes normalized JPEGs in Application Support. |

### Core location and operating mode

| File | Purpose |
|---|---|
| `FARO/Core/Location/LocationProvider.swift` | Wraps Core Location permission, coarse fix/heading updates, and freshness/accuracy acceptance policy. |
| `FARO/Core/Mode/OperatingMode.swift` | Defines Inactive/Navigating presentation, the non-persisted controller, transition feedback boundary, and navigation-output gate. |
| `FARO/Core/Mode/ModeFeedback.swift` | Produces distinct transition sound/haptic feedback and localized accessibility announcements. |

### Core place recognition

| File | Purpose |
|---|---|
| `FARO/Core/Recognition/ImageEmbedder.swift` | Defines model-tagged embedding payloads, compatible raw-vector distance, the embedder protocol/factory, and errors. |
| `FARO/Core/Recognition/PixelGridEmbedder.swift` | Deterministic 16x16 luminance embedder used only by simulator workflows and tests. |
| `FARO/Core/Recognition/VisionFeaturePrintEmbedder.swift` | Production embedder that stores Codable Vision FeaturePrint observations and uses Vision's official distance API. |
| `FARO/Core/Recognition/PlaceMatcher.swift` | Builds candidates, applies coarse GPS site filtering, performs nearest-neighbour matching, enforces uncertainty thresholds, and exposes raw diagnostics for evaluation. |

### Core voice

| File | Purpose |
|---|---|
| `FARO/Core/Voice/VoiceAuthorization.swift` | Bridges microphone and speech-recognition permission requests into async errors. |
| `FARO/Core/Voice/VoiceTextNormalizer.swift` | Tokenizes, case/diacritic-folds, and normalizes bilingual transcripts while preserving original label text. |
| `FARO/Core/Voice/VoiceCommand.swift` | Defines the six command values, display keys, navigation requirements, errors, and recognition context strings. |
| `FARO/Core/Voice/VoiceCommandParser.swift` | Parses tolerant English and Spanish command patterns and extracts user-provided place labels. |
| `FARO/Core/Voice/VoiceCommandExecutor.swift` | Routes parsed commands into capture/place/mode flows and enforces the Navigating gate. |
| `FARO/Core/Voice/OnDeviceSpeechRecognizer.swift` | Records one temporary command file, detects an endpoint, transcribes on-device with `SFSpeechRecognizer`, and cleans up. |
| `FARO/Core/Voice/SpeechEndpointDetector.swift` | Implements level hysteresis, speech activation, required silence, and maximum-duration endpoint rules. |
| `FARO/Core/Voice/WakePhraseMatcher.swift` | Matches bilingual wake phrases and accumulates split streaming transcripts without duplicate activation. |
| `FARO/Core/Voice/OnDeviceWakePhraseDetector.swift` | Streams foreground microphone audio through iOS 26 SpeechAnalyzer modules and emits bounded wake events. |
| `FARO/Core/Voice/HandsFreeVoiceViewModel.swift` | Owns Hands-Free activation/retry state, ready/wake tones, stale callback protection, and transitions around command handling. |
| `FARO/Core/Voice/VoiceInputCoordinator.swift` | Serializes camera still suspension, command recording, endpoint completion, and camera resume. |

### Feature UI and orchestration

| File | Purpose |
|---|---|
| `FARO/Features/Bluetooth/ObstacleModuleDebugView.swift` | Accessible localized diagnostic screen for connection, telemetry, warning, and requested/confirmed mode. |
| `FARO/Features/Capture/CameraPreview.swift` | SwiftUI wrapper around an `AVCaptureVideoPreviewLayer`. |
| `FARO/Features/Capture/CaptureFeedback.swift` | Emits localized capture success/failure accessibility feedback and system sounds. |
| `FARO/Features/Capture/CaptureViewModel.swift` | Main capture/place orchestrator: preparation, still capture, description, speech, enrollment, recognition, migration, and image cleanup. |
| `FARO/Features/Capture/SavedCapturesView.swift` | Displays saved capture metadata and thumbnails. |
| `FARO/Features/Evaluation/EvaluationView.swift` | Accessible bilingual screen for recognition trials, field observations, summary metrics, export, and clearing evaluation data. |
| `FARO/Features/Evaluation/EvaluationViewModel.swift` | Coordinates diagnostic recognition, structured observations, persistence, export refresh, and localized failures. |
| `FARO/Features/Places/PlacesView.swift` | Lists remembered places and supports rename, add-view, and delete operations. |
| `FARO/Features/Places/RememberPlaceView.swift` | Manual enrollment/add-view sheet with localized guidance and a five-view target. |
| `FARO/Features/Voice/VoiceCommandViewModel.swift` | Observable manual/automatic command-recording state; starts/stops recognition, parses transcripts, and reports localized errors. |

### SwiftData models

| File | Purpose |
|---|---|
| `FARO/Models/Place.swift` | Defines `Place` and cascading `PlaceSnapshot` models, embedding reconstruction/migration helpers, and optional location conversion. |

### Resources

| File | Purpose |
|---|---|
| `FARO/Resources/Assets.xcassets/Contents.json` | Root asset-catalog metadata. |
| `FARO/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json` | Maps the universal iOS app-icon slot to the 1024x1024 source image. |
| `FARO/Resources/Assets.xcassets/AppIcon.appiconset/FARO-AppIcon-1024.png` | FARO application icon source. |
| `FARO/Resources/Fixtures/kitchen-a.png` | First deterministic kitchen frame for simulator capture and recognition tests. |
| `FARO/Resources/Fixtures/kitchen-b.png` | Alternate kitchen view used to test same-place similarity. |
| `FARO/Resources/Fixtures/bedroom-a.png` | Different-room frame used to test recognition separation. |
| `FARO/Resources/Evaluation.xcstrings` | English and Spanish evaluation UI, metric, privacy, outcome, and error strings. |
| `FARO/Resources/InfoPlist.xcstrings` | English and Spanish privacy-permission descriptions. |
| `FARO/Resources/Localizable.xcstrings` | General UI, accessibility, status, error, voice, mode, and BLE strings. |
| `FARO/Resources/Places.xcstrings` | Place enrollment, recognition, management, and migration strings. |

### Tests

| File | Purpose |
|---|---|
| `FAROTests/TestImageFixture.swift` | Shared helper that loads a fixture and generates valid JPEG, HEIC, GIF, or other ImageIO test bytes. |
| `FAROTests/CaptureViewModelTests.swift` | Tests basic capture persistence, success feedback, and localized capture failure. |
| `FAROTests/DescribeFlowTests.swift` | Tests capture-to-description-to-speech flow and live language changes. |
| `FAROTests/EvaluationTests.swift` | Tests ground-truth outcome classification, angle/lighting/language aggregates, latency metrics, persistence, and versioned export. |
| `FAROTests/FAROVisionClientTests.swift` | Tests multipart options/MIME, decoding, retry/auth policy, language validation, and HEIC metadata. |
| `FAROTests/HandsFreeVoiceViewModelTests.swift` | Tests arming, tones, retries, cancellation races, callback isolation, failures, and foreground activation policy. |
| `FAROTests/ImageSourceTests.swift` | Tests fixture capture, real-byte format detection, JPEG normalization, HEIC retention, and invalid/unsupported data. |
| `FAROTests/ImageStoreTests.swift` | Tests persistent JPEG conversion and storage. |
| `FAROTests/LanguageSupportTests.swift` | Tests language preference resolution and completeness of both String Catalog localizations. |
| `FAROTests/LocationProviderTests.swift` | Tests coarse location freshness and accuracy acceptance. |
| `FAROTests/MockSceneDescriberTests.swift` | Tests localized mock success, configured responses, service failure, and timeout. |
| `FAROTests/ObstacleModuleTests.swift` | Tests BLE UUID/packet contract, warning bands, mode synchronization, reconnect/staleness behavior, mock telemetry, and localization. |
| `FAROTests/OperatingModeTests.swift` | Tests Inactive boot, localized transitions, duplicate suppression, and navigation-output gating. |
| `FAROTests/PlaceMatcherTests.swift` | Tests model-specific policies, confident/uncertain matching, raw evaluation diagnostics, tie handling, and coarse GPS filtering. |
| `FAROTests/PlacePersistenceTests.swift` | Tests SwiftData persistence and the `Place`/`PlaceSnapshot` relationship. |
| `FAROTests/PlaceWorkflowTests.swift` | Tests end-to-end enrollment/recognition, nine-view scans, cancellation/failure retention, location, migration, cleanup, and speech stopping. |
| `FAROTests/SpeechEndpointDetectorTests.swift` | Tests activation, silence endpoint detection, and noise hysteresis. |
| `FAROTests/SpeechOutputConfigurationTests.swift` | Tests accessible speech rate/pacing, localization, queued-utterance completion, and delegate concurrency. |
| `FAROTests/VisionFeaturePrintEmbedderTests.swift` | Tests FeaturePrint serialization/compatibility and both production and pixel-grid distance behavior. |
| `FAROTests/VoiceCommandExecutorTests.swift` | Tests routing of all bilingual commands and the Navigating requirement. |
| `FAROTests/VoiceCommandParserTests.swift` | Tests bilingual phrasing, label extraction, rejection, and contextual strings. |
| `FAROTests/VoiceCommandViewModelTests.swift` | Tests recognition/parsing state, automatic endpoint flow, localized errors, and cancellation. |
| `FAROTests/VoiceInputCoordinatorTests.swift` | Tests camera/microphone ordering, restoration after failure, endpoint completion, and cancellation races. |
| `FAROTests/WakePhraseMatcherTests.swift` | Tests both wake phrases, rejection, contextual strings, split transcripts, and one activation per session. |

## Generated and local-only files

These files may appear under `ios/` but are intentionally not tracked:

| Path | Purpose |
|---|---|
| `Config/Local.xcconfig` | Developer-specific live endpoint and token values; copied from the example and never committed. |
| `FARO.xcodeproj/` | Generated by XcodeGen from `project.yml`; regenerate rather than hand-edit. |
| `FARO/Info.plist` | Generated from the `project.yml` `info` section. |
| `xcuserdata/` | Local Xcode UI, signing, and workspace state. |
