# FARO iOS Prototype — Implementation Plan

## Progress

| Phase | Status |
|---|---|
| Phase 0 — Foundation | Complete |
| Phase 1 — Image capture | Verified on physical device |
| Phase 2 — Scene description | Verified on physical device |
| Phase 3 — Place memory | Verified on physical device |
| Phase 4 — Operating modes | Verified on physical device |
| Phase 5 — Voice commands | Hands-free implemented; physical validation pending |
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

## Phase gates and commits

- Each phase is implemented as its own commit. Validation fixes may be separate
  follow-up commits, but they remain part of the same phase.
- Do not start a new phase until the previous phase has passed simulator tests,
  compiled for a physical iPhone, and been validated on the physical device.
- Update the Progress table when a phase begins, reaches device validation, or
  is accepted.

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
| Languages | Follow iPhone, English (US), and Español (México), established in Phase 2 | Prevents language assumptions from spreading into place, mode, voice, BLE, and metrics features |
| Hands-free entry | Persisted opt-in; Siri opens FARO, then FARO arms after reaching the foreground and acquiring audio | Uses Siri's system-wide wake path without claiming unsupported custom background activation |
| Wake phrases | “Hey FARO” and “Hola FARO,” detected fully on-device | Two-word phrases reduce false activations; manual Start/Finish remains a fallback |
| Roadmap file | `IOS-TASKS.md` in repo root | Requested deliverable |

## Target repository layout

```
FARO/
├── DEVELOPMENT.md               # developer setup and contribution workflow
├── IOS-TASKS.md                 # task roadmap (deliverable of T01)
├── project-faro.md              # concept source of truth
├── docs/
│   ├── vision-api-contract.md   # HTTP contract for the future API project
│   └── ble-contract.md          # GATT contract for the ESP32 repo
├── ios/
│   ├── project.yml              # XcodeGen source of truth
│   ├── FARO/                    # app sources and String Catalogs
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
- **Embeddings are model-specific.** Representations from different models or
  serialization formats are not comparable, so original JPEGs are retained
  permanently. FARO automatically re-embeds retained views when the production
  representation changes instead of asking a blind user to photograph every
  room again.
- **Uncertainty beats a confident guess.** False confident identification is an explicit metric in
  the concept doc; the matcher must have a threshold and an "I'm not sure" path from the start.
- **Free provisioning expires.** Device builds need reprovisioning roughly weekly; simulator runs do
  not. Keep verification simulator-based where possible.
- **Home imagery is sensitive.** The API contract should state retention expectations, and uploads
  should be an explicit user action rather than continuous streaming.
- **Language is explicit data.** Every generated description carries its BCP 47
  language tag. Speech selects its voice from that tag rather than assuming the
  current UI language.
- **One preference controls the prototype.** The selected language applies to
  UI, accessibility text, scene output, spoken feedback, and future voice
  commands. `Follow iPhone` resolves to English or Mexican Spanish.
- **Place labels are user data.** Preserve names exactly as entered; do not
  translate a saved place label when the app language changes.
- **No hard-coded user-facing strings.** Visible text, accessibility labels and
  hints, errors, and privacy permission descriptions belong in String Catalogs.
- **Bilingual validation is a phase gate.** Every phase after Phase 2 must pass
  relevant tests in both English and Spanish before the next phase begins.

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

**T15 · language-domain** — Replace the single global output locale with
`SupportedLanguage` (`en-US`, `es-MX`) and `LanguagePreference` (`followSystem`,
English, Spanish). Add the resolved language tag to `SceneDescription`.
*Done when:* locale resolution is unit tested, unsupported system languages use
an explicit fallback, and generated text always identifies its language.

**T16 · language-settings** — Add a VoiceOver-accessible language selector,
persist it with `@AppStorage`, and inject the resolved language into UI and
services.
*Done when:* changing language updates the UI and the next description request
and spoken response without relaunching the app.

**T17 · string-catalogs** — Add `Localizable.xcstrings` and
`InfoPlist.xcstrings`; migrate current visible strings, accessibility labels and
hints, errors, status messages, and privacy permission descriptions into
English and Mexican Spanish.
*Done when:* the current capture and description surfaces contain no
user-facing hard-coded language and both localizations render correctly.

**T18 · bilingual-description** — Make mock descriptions and API prompts
language-specific, send the resolved BCP 47 locale to the service, require the
response to echo its language, and select the matching speech voice. Keep
phrase pacing punctuation-based or language-aware without mixing language
profiles.
*Done when:* English text uses an English voice, Spanish text uses an `es-MX`
voice, a missing voice produces a clear error, and both mocks pass tests.

**T19 · bilingual-validation** — Add parameterized English/Spanish tests and
run the Phase 2 physical-device matrix: UI switching, mock output, speech
clarity, interruption, VoiceOver behavior, and Phase 1 regression.
*Done when:* both languages pass on the physical iPhone. Phase 3 must not begin
before this task is accepted.

### Phase 3 — Place memory

**T20 · swiftdata-models** — `Place` (id, label, createdAt) and `PlaceSnapshot` (id, imageFilename,
embedding blob, capturedAt, coordinate, heading) with the relationship modelled.
*Done when:* models persist and reload in tests.

**T21 · embedder-protocol** — `ImageEmbedder` protocol plus
`VisionFeaturePrintEmbedder`, persisting the complete Codable FeaturePrint
observation and comparing it with Vision's official distance API.
*Done when:* tests show same-room fixtures score closer than different-room fixtures.

**T22 · remember-place** — Enrollment flow: enter a label, capture several guided views, store
snapshots with embeddings.
*Done when:* a place with multiple snapshots is saved and listed in both app
languages without translating its user-provided label.

**T23 · location-capture** — CoreLocation permission and attaching coordinate plus heading to each
snapshot, tolerating poor indoor accuracy.
*Done when:* snapshots carry location data when available and save fine when not.

**T24 · place-matcher** — Nearest-neighbour matching over stored embeddings with
model-specific absolute distance and cross-place separation thresholds, plus an
explicit uncertain result. A changed embedding representation automatically
reprocesses retained JPEGs before matching.
*Done when:* tests cover confident match, wrong-room rejection, and below-threshold uncertainty.

**T25 · where-am-i** — Wire “where am I?” / “¿dónde estoy?”: capture → embed
→ match → speak the label or a localized uncertainty message.
*Done when:* flow answers correctly from fixtures and speaks the result in the
selected language.

**T26 · gps-gating** — Use coarse location to filter or weight candidates, acknowledging GPS cannot
separate rooms within one house.
*Done when:* matching restricts candidates by site without breaking indoor matching.

**T27 · place-management** — Localized, accessible UI to list, rename, add
views to, and delete places.
*Done when:* all operations work under VoiceOver in English and Spanish.

### Phase 4 — Operating modes

**T28 · mode-state** — Inactive/Navigating state machine booting into
Inactive, with distinct confirmation tones, localized mode names and
announcements, and a clearly exposed current mode.
*Done when:* mode is announced and visible in both languages, and always starts
Inactive.

**T29 · mode-gating** — Gate navigation-oriented behaviour and future
proximity feedback behind Navigating; disable “Where am I?” in Inactive and
cancel spoken navigation output when navigation stops.
*Done when:* tests prove no proximity output occurs while Inactive.

### Phase 5 — Voice commands

**T30 · speech-recognition** — On-device `SFSpeechRecognizer` using the
selected locale, with permission handling and an explicit start/finish
recording control to avoid always-listening complexity. Still-photo requests
are suspended during voice recording, but the video-only camera session stays
running to avoid an iOS 26 / iPhone 17 capture-session restart assertion. The
camera does not configure the shared audio session. FARO records each bounded
command to a temporary local file, releases the microphone, and then passes
that file to an on-device `SFSpeechURLRecognitionRequest`.
*Done when:* English and Spanish spoken audio transcribe on device.

**T31 · command-parser** — Parse the four commands in both languages:
`describe` / `describe`, `where am I?` / `¿dónde estoy?`, `remember this as X`
/ `recuerda este lugar como X`, and `what is ahead?` / `¿qué hay delante?`,
with tolerant matching and label extraction.
*Done when:* parameterized tests cover English and Spanish phrasing variants,
label extraction, and unrecognized input.

**T32 · voice-wiring** — Route parsed commands into the existing flows while
preserving the selected language through generated and spoken results.
Navigation-only commands remain gated by Navigating, and voice enrollment
captures the first named view before opening the existing multi-view flow.
*Done when:* each command triggers its flow by voice alone in English and
Spanish.

**T33 · hands-free-state** — Add a persisted, explicit Hands-Free preference.
When enabled and FARO becomes foreground-active — including after “Siri, open
FARO” — wait for Siri or another audio interruption to release the microphone,
then play a ready tone and arm wake listening. Disarm immediately when the app
leaves the foreground or the preference is disabled. Preserve manual
Start/Finish controls as a fallback, and keep every fresh launch in Inactive
operating mode.
*Done when:* after one-time permissions and opt-in, Siri can open FARO and the
ready tone confirms wake listening without a screen tap; disabling Hands-Free
stops microphone use.

*Implementation status:* Complete in code and simulator tests; physical
acceptance remains part of T38.

**T34 · wake-engine-spike** — Define a `WakePhraseDetecting` boundary and
compare viable fully on-device engines for “Hey FARO” and “Hola FARO,” including
iOS 26 Speech APIs, a native custom sound model, and a dedicated keyword engine.
Measure activation latency, false accepts/rejects, energy use, binary size,
licensing, and support for both phrases. Do not send ambient audio to a service
or retain it as user content.
*Done when:* the selected engine and fallback are recorded with physical-device
evidence, and fixture audio can drive the protocol in tests.

*Implementation status:* `SpeechAnalyzer` with a streaming `SpeechTranscriber`
is selected for phrase recognition, with `SpeechDetector` providing on-device
voice-activity gating. FARO checks runtime/locale support and installs the
required local assets. If unavailable, it reports a localized error and keeps
the verified bounded `SFSpeechRecognizer` Start/Finish path as the fallback.
Latency, energy, and false-activation measurements remain part of T38.

**T35 · wake-phrase-listener** — Implement the selected detector while
Hands-Free is armed. Debounce duplicate detections, ignore FARO's own tones and
speech, expose a clear listening indicator, and keep the video-only camera
session alive without allowing the wake listener to reconfigure or restart it.
The listener may run in either FARO operating mode so the user can arm
Navigating by voice.
*Done when:* both wake phrases trigger once across quiet and representative
room noise, ordinary conversation does not trigger, FARO never triggers itself,
and backgrounding the app stops listening.

*Implementation status:* Complete in code and simulator tests; acoustic and
background lifecycle behavior awaits T38.

**T36 · automatic-command-window** — After a wake phrase, play a distinct
acknowledgement tone, capture the next utterance, and finish automatically on
silence or a bounded timeout. Transcribe on-device, route through the existing
parser/executor, then re-arm the wake listener after success or a localized
error. Keep the audio handoff serialized and never restart the camera session.
*Done when:* after opening FARO, all existing English and Spanish commands can
complete repeatedly without Start or Finish taps.

*Implementation status:* Complete in code and simulator tests; silence levels
and repeated camera/microphone handoffs await T38.

**T37 · voice-mode-control** — Add bilingual `start navigation` / `inicia
navegación` and `stop navigation` / `detén navegación` commands. Route them
through `OperatingModeController`, retain the explicit Inactive boot state, play
the existing transition confirmations, and make Stop cancel navigation-oriented
speech immediately.
*Done when:* the complete Siri-open → wake phrase → start navigation → command
→ stop navigation workflow requires no touch and preserves every mode-gating
test.

*Implementation status:* Complete in code and simulator tests; end-to-end
hands-free acceptance awaits T38.

**T38 · hands-free-validation** — Run the physical-device matrix: Siri audio
handoff, both wake phrases and languages, first-run permissions, repeated
wake/command cycles, camera regression, Bluetooth audio routes, interruptions,
self-speech suppression, foreground exit, manual fallback, VoiceOver, false
activations, activation latency, and battery/thermal impact. Custom wake
activation while FARO is suspended or terminated remains explicitly out of
scope.
*Done when:* the hands-free flow is accepted on the physical iPhone and its
measured limitations are documented before Phase 6 begins.

*Status:* Pending physical-device validation.

### Phase 6 — ESP32 boundary

**T39 · ble-contract** — Write `docs/ble-contract.md`: service and characteristic UUIDs, distance and
warning-state payloads, mode arming, and reconnection expectations, stating that the ESP32 alert path
stays autonomous.
*Done when:* the separate firmware repo can implement against it without further questions.

**T40 · ble-central** — CoreBluetooth central that scans, connects, and
subscribes, with a mock peripheral so it is testable without hardware,
surfacing distance and connection status in a localized debug view.
*Done when:* mock peripheral drives the debug view in both languages and
disconnects degrade gracefully.

### Phase 7 — Evaluation

**T41 · metrics-harness** — Log and export recognition accuracy across angles
and lighting, false confident identifications, end-to-end latency, and selected
language.
*Done when:* a run produces an exportable results summary.

**T42 · field-test** — Tune thresholds, language behavior, narration pacing,
and proximity bands with the actual user and record findings.
*Done when:* thresholds and language defaults are updated from real
observations, not assumptions.

**T43 · clip-fallback** *(conditional)* — Only if T41 shows poor recall: add a CLIP Core ML embedder
behind `ImageEmbedder` and re-embed stored JPEGs in the background.
*Done when:* both embedders are comparable on the same fixture set.

## Notes and risks

- T05 is deliberately ordered before the camera work; skipping it would make Phases 2–3 testable only
  on a physical device.
- One forward sonar misses thin, soft, angled, high/low obstacles, stairs, and drop-offs. iOS
  messaging must not imply full hazard coverage.
- FeaturePrint degrades with large viewpoint and lighting changes; multi-view enrollment (T22) and
  measurement (T41) are the planned mitigations, with T43 as the escape hatch.
- The vision API does not exist yet, so Phase 2 stays fully functional on the mock until T13.
- Bilingual support is intentionally completed now: retrofitting after place,
  mode, voice, BLE, and metrics work would multiply localization and regression
  work across every later surface.
- iOS does not grant third-party apps Siri's system-wide custom wake-word
  privilege. The planned route depends on Siri to foreground FARO first; FARO
  must stop its wake listener whenever it leaves the foreground.
- `project-faro.md` and `.github/copilot-instructions.md` should be updated whenever behaviour,
  architecture, or scope changes.
