# FARO iOS Prototype — Implementation Plan

## Progress

| Phase | Status |
|---|---|
| Phase 0 — Foundation | Complete |
| Phase 1 — Image capture | Verified on physical device |
| Phase 2 — Scene description | Implemented; awaiting physical-device validation |
| Phase 3 — Place memory | Not started |
| Phase 4 — Operating modes | Not started |
| Phase 5 — Voice commands | Not started |
| Phase 6 — ESP32 boundary | Not started |
| Phase 7 — Evaluation | Not started |

## Problem

FARO is currently documentation only (`project-faro.md`, `.github/copilot-instructions.md`). We need
the iOS app built first: capture images, describe scenes through a FARO-owned vision API, and learn
and recognize named places using image embeddings plus GPS. The ESP32 firmware lives in a separate
repository, so this plan only prepares the iOS side of the BLE boundary.

## Approach

Build in small, independently verifiable tasks. Each task ends in something demonstrable and
compiles on its own. Work bottom-up through five capability layers — capture, describe, remember,
modes, voice — so that every later layer has a working layer beneath it to test against.

The concept doc's safety invariant (`sonar -> ESP32 -> passive buzzer` must never depend on the
phone) means the iOS app is deliberately **not** on the critical warning path. iOS work here is
narration, memory, and mode control only.

## Locked decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scene description | Cloud-first via a FARO-owned API added to this repo later | Fastest path; swappable behind a protocol |
| Project scaffolding | XcodeGen from committed `project.yml` | Reviewable in git, no merge conflicts, CLI-verifiable builds |
| Embeddings | Vision `GenerateImageFeaturePrintRequest` | On-device, zero bundle cost, offline; CLIP kept as a measured fallback |
| Persistence | SwiftData | Natural `Place` → `[PlaceSnapshot]` modelling, binds to SwiftUI |
| Deployment target | iOS 26 | Matches installed SDK; modern Swift Vision API |
| Repo layout | App under `ios/` | Keeps root for docs and the future API project |
| First interaction | Accessible buttons, voice added later | Gives a testable capture path before speech complexity |
| Roadmap file | `IOS-TASKS.md` in repo root | Requested deliverable |

## Target repository layout

```
FARO/
├── IOS-TASKS.md                 # task roadmap (deliverable of T01)
├── project-faro.md              # concept source of truth
├── docs/
│   ├── vision-api-contract.md   # HTTP contract for the future API project
│   └── ble-contract.md          # GATT contract for the ESP32 repo
├── ios/
│   ├── project.yml              # XcodeGen source of truth
│   ├── FARO/                    # app sources
│   └── FAROTests/               # unit tests
└── .github/copilot-instructions.md
```

`ios/FARO.xcodeproj` is generated and gitignored.

## Verification commands

```bash
cd ios && xcodegen generate

# full build (from ios/)
xcodebuild -project FARO.xcodeproj -scheme FARO \
  -destination 'platform=iOS Simulator,name=iPhone 17' build

# full test suite (from ios/)
xcodebuild test -project FARO.xcodeproj -scheme FARO \
  -destination 'platform=iOS Simulator,name=iPhone 17'

# a single test (from ios/)
xcodebuild test -project FARO.xcodeproj -scheme FARO \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  '-only-testing:FAROTests/ImageStoreTests/savesFixturesAsPersistentJPEGs()'
```

Resolve the simulator name with `xcrun simctl list devices available` before hardcoding it.

## Critical design constraints

- **The simulator has no camera.** AVFoundation capture cannot run there. An `ImageSource` protocol
  with a `FixtureImageSource` (bundled sample room photos) is built in T05 *before* the camera, so
  every downstream layer — describe, embed, match, speak — stays fully testable in the simulator.
  Without this, most of the app can only be exercised on a physical device.
- **Recognition must survive network loss.** Descriptions come from a remote API, but place matching
  stays on-device so "where am I?" keeps answering when the API is unreachable.
- **Embeddings are model-specific.** Vectors from different models are not comparable, so original
  JPEGs are retained permanently. Swapping to CLIP later becomes a background re-embed rather than
  re-photographing every room with a blind user.
- **Uncertainty beats a confident guess.** False confident identification is an explicit metric in
  the concept doc; the matcher must have a threshold and an "I'm not sure" path from the start.
- **Free provisioning expires.** Device builds need reprovisioning roughly weekly; simulator runs do
  not. Keep verification simulator-based where possible.
- **Home imagery is sensitive.** The API contract should state retention expectations, and uploads
  should be an explicit user action rather than continuous streaming.

## Tasks

### Phase 0 — Foundation

**T01 · roadmap-file** — Write `IOS-TASKS.md` in the repo root from this plan: phases, task list,
done-when criteria, verification commands.
*Done when:* file exists in root and reflects every task below.

**T02 · ios-scaffold** — Create `ios/` with `project.yml` (app target FARO, iOS 26, SwiftUI
lifecycle, bundle id, test target) and Info.plist privacy strings for camera, location, microphone,
and speech. Gitignore `*.xcodeproj` and `xcuserdata`.
*Done when:* `xcodegen generate` then `xcodebuild build` succeeds against the simulator.

**T03 · app-shell** — Root SwiftUI shell with VoiceOver labels, Dynamic Type support, large tap
targets, and a placeholder mode indicator.
*Done when:* app launches in simulator and every control has an accessibility label.

**T04 · doc-build-commands** — Replace the "no build tooling yet" note in
`.github/copilot-instructions.md` with the real generate/build/test/single-test commands.
*Done when:* instructions file documents commands that actually run.

### Phase 1 — Image capture

**T05 · image-source-protocol** — `ImageSource` protocol plus `FixtureImageSource` returning bundled
sample room photos, selected automatically under the simulator.
*Done when:* unit test pulls a fixture frame with no camera present.

**T06 · camera-session** — `CameraImageSource` using AVFoundation rear capture with permission
handling and a SwiftUI preview layer.
*Done when:* live preview renders on a physical device; permission denial is handled gracefully.

**T07 · capture-still** — Capture button producing a still frame, with an audible/haptic confirmation
and a VoiceOver announcement.
*Done when:* tapping capture yields an image from either source and announces success.

**T08 · image-store** — Persist captures as JPEGs in Application Support with stable filenames and a
debug list view.
*Done when:* captured images survive relaunch and appear in the debug view.

### Phase 2 — Scene description

**T09 · vision-api-contract** — Write `docs/vision-api-contract.md`: endpoint, auth, multipart image
upload, request options, response shape (description text, confidence, latency), versioning, error
model, and image-retention expectations.
*Done when:* contract is specific enough for the future API project to implement blind.

**T10 · describer-protocol** — `SceneDescribing` protocol plus `MockSceneDescriber` returning canned
descriptions with simulated latency and injectable failures.
*Done when:* unit tests cover success, timeout, and error paths.

**T11 · describe-flow** — Wire a Describe action: capture → describe → show text on screen.
*Done when:* button produces visible description text using the mock.

**T12 · speech-output** — `AVSpeechSynthesizer` narration with a correctly configured audio session,
interruption handling, and no VoiceOver collisions.
*Done when:* descriptions are spoken and interrupt cleanly when a new request starts.

**T13 · vision-http-client** — `FAROVisionClient` implementing the T09 contract with timeouts,
cancellation, retry policy, and a spoken failure message.
*Done when:* client passes tests against a stubbed URLProtocol.

**T14 · endpoint-config** — Base URL and credentials via gitignored xcconfig, with a build-time
switch between mock and live describer.
*Done when:* no secret or hostname is committed and both modes are selectable.

### Phase 3 — Place memory

**T15 · swiftdata-models** — `Place` (id, label, createdAt) and `PlaceSnapshot` (id, imageFilename,
embedding blob, capturedAt, coordinate, heading) with the relationship modelled.
*Done when:* models persist and reload in tests.

**T16 · embedder-protocol** — `ImageEmbedder` protocol plus `VisionFeaturePrintEmbedder`, storing
vectors as `Data`.
*Done when:* tests show same-room fixtures score closer than different-room fixtures.

**T17 · remember-place** — Enrollment flow: enter a label, capture several guided views, store
snapshots with embeddings.
*Done when:* a place with multiple snapshots is saved and listed.

**T18 · location-capture** — CoreLocation permission and attaching coordinate plus heading to each
snapshot, tolerating poor indoor accuracy.
*Done when:* snapshots carry location data when available and save fine when not.

**T19 · place-matcher** — Nearest-neighbour matching over stored embeddings with k-NN voting, a
confidence threshold, and an explicit uncertain result.
*Done when:* tests cover confident match, wrong-room rejection, and below-threshold uncertainty.

**T20 · where-am-i** — Wire "where am I": capture → embed → match → speak the label or uncertainty.
*Done when:* flow answers correctly from fixtures and speaks the result.

**T21 · gps-gating** — Use coarse location to filter or weight candidates, acknowledging GPS cannot
separate rooms within one house.
*Done when:* matching restricts candidates by site without breaking indoor matching.

**T22 · place-management** — Accessible UI to list, rename, add views to, and delete places.
*Done when:* all operations work under VoiceOver.

### Phase 4 — Operating modes

**T23 · mode-state** — Inactive/Navigating state machine booting into Inactive, with distinct
confirmation tones on transition and a clearly exposed current mode.
*Done when:* mode is announced and visible, and always starts Inactive.

**T24 · mode-gating** — Gate navigation-oriented behaviour and proximity feedback behind Navigating;
guarantee silence in Inactive.
*Done when:* tests prove no proximity output occurs while Inactive.

### Phase 5 — Voice commands

**T25 · speech-recognition** — On-device `SFSpeechRecognizer` with permission handling, push-to-talk
to avoid always-listening complexity.
*Done when:* spoken audio transcribes on device.

**T26 · command-parser** — Parse the four commands — describe, where am I, remember this as X, what
is ahead — with tolerant matching and label extraction.
*Done when:* tests cover phrasing variants and unrecognized input.

**T27 · voice-wiring** — Route parsed commands into the existing flows.
*Done when:* each command triggers its flow by voice alone.

### Phase 6 — ESP32 boundary

**T28 · ble-contract** — Write `docs/ble-contract.md`: service and characteristic UUIDs, distance and
warning-state payloads, mode arming, and reconnection expectations, stating that the ESP32 alert path
stays autonomous.
*Done when:* the separate firmware repo can implement against it without further questions.

**T29 · ble-central** — CoreBluetooth central that scans, connects, and subscribes, with a mock
peripheral so it is testable without hardware, surfacing distance in a debug view.
*Done when:* mock peripheral drives the debug view and disconnects degrade gracefully.

### Phase 7 — Evaluation

**T30 · metrics-harness** — Log and export recognition accuracy across angles and lighting, false
confident identifications, and end-to-end latency.
*Done when:* a run produces an exportable results summary.

**T31 · field-test** — Tune thresholds and proximity bands with the actual user and record findings.
*Done when:* thresholds are updated from real observations, not defaults.

**T32 · clip-fallback** *(conditional)* — Only if T30 shows poor recall: add a CLIP Core ML embedder
behind `ImageEmbedder` and re-embed stored JPEGs in the background.
*Done when:* both embedders are comparable on the same fixture set.

## Notes and risks

- T05 is deliberately ordered before the camera work; skipping it would make Phases 2–3 testable only
  on a physical device.
- One forward sonar misses thin, soft, angled, high/low obstacles, stairs, and drop-offs. iOS
  messaging must not imply full hazard coverage.
- FeaturePrint degrades with large viewpoint and lighting changes; multi-view enrollment (T17) and
  measurement (T30) are the planned mitigations, with T32 as the escape hatch.
- The vision API does not exist yet, so Phase 2 stays fully functional on the mock until T13.
- `project-faro.md` and `.github/copilot-instructions.md` should be updated whenever behaviour,
  architecture, or scope changes.
