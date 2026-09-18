# FARO Developer Onboarding

This guide takes a new contributor from a fresh clone to a running FARO build.
Read [project-faro.md](project-faro.md) for the product and safety model, and
[IOS-TASKS.md](IOS-TASKS.md) for the current implementation phase and device
validation gate.

## Project status

FARO is an iOS-first assistive prototype. The iPhone app currently supports:

- rear-camera still capture;
- bilingual English (US) and Spanish (Mexico) UI and speech;
- mock and HTTP-backed scene descriptions;
- on-device visual place enrollment and recognition;
- explicit Inactive and Navigating operating modes;
- six bilingual voice commands using manual or hands-free capture.

The physically verified voice flow keeps the video-only camera session running,
records one short command to a temporary local file, releases the microphone,
and then performs on-device transcription. The Phase 5 hands-free extension is
also verified on a physical iPhone: after a persisted opt-in, Siri can
foreground FARO, and FARO listens on-device for "Hey FARO" or "Hola FARO"
before opening one automatic command window. See T33-T38 in `IOS-TASKS.md`.

The voice command "Remember this as..." now provides localized movement
guidance and automatically captures nine still views about one second apart
while the user sweeps from left to right through approximately 180 degrees. It
deliberately reuses the proven photo path instead of recording video or
reconfiguring the camera session. The touch enrollment screen remains available
for manual enrollment and adding views.

The checked-in `esp32/` folder contains the physically validated
obstacle-module firmware. It shares the versioned boundary in
`docs/ble-contract.md` with the iOS Core Bluetooth implementation and has a
separate Arduino build/flash workflow.

## Prerequisites

- macOS with Xcode 26.x and an iOS 26 SDK;
- Xcode Command Line Tools selected with `xcode-select`;
- [XcodeGen](https://github.com/yonaskolb/XcodeGen);
- Git and SSH access to the FARO remote;
- an Apple ID and development team for physical-device signing;
- an iPhone running iOS 26 for camera, microphone, speech, and production
  FeaturePrint validation;
- Python 3.10 or newer for the private vision backend;
- for ESP32 work, Arduino CLI with the `esp32:esp32` core and Adafruit
  NeoPixel library.

Verify the command-line setup:

```bash
xcode-select -p
xcodebuild -version
xcodegen --version
python3 --version
```

If macOS's `python3` reports 3.9, use an installed Python 3.10-or-newer
executable, such as `python3.13`, when creating the backend virtual
environment.

Install XcodeGen with Homebrew if needed:

```bash
brew install xcodegen
```

## Clone and generate the project

```bash
git clone ssh://git@git.home.arpa:2222/plk3000/faro.git
cd faro/ios
xcodegen generate
open FARO.xcodeproj
```

`ios/project.yml` is the source of truth. `ios/FARO.xcodeproj` and the generated
`ios/FARO/Info.plist` are ignored by Git. Do not hand-edit or commit either
generated artifact.

Regenerate after:

- changing `ios/project.yml`;
- adding, removing, or moving Swift source files;
- changing target resources or Info.plist properties.

## Fastest local start

The default configuration uses the mock scene describer and requires no
backend:

```bash
cd ios
xcodegen generate
xcodebuild -project FARO.xcodeproj -scheme FARO \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  build CODE_SIGNING_ALLOWED=NO
```

Run all tests:

```bash
xcodebuild test -project FARO.xcodeproj -scheme FARO \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

If that simulator is unavailable, select an installed device:

```bash
xcrun simctl list devices available
```

Run one Swift Testing test:

```bash
xcodebuild test -project FARO.xcodeproj -scheme FARO \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  '-only-testing:FAROTests/ImageStoreTests/savesFixturesAsPersistentJPEGs()' \
  CODE_SIGNING_ALLOWED=NO
```

There is no separate lint command. Swift 6 strict concurrency errors are
enforced by the build.

## Build and run on an iPhone

The simulator cannot exercise the production camera, microphone, on-device
speech assets, or Vision FeaturePrint implementation. Every phase that changes
those surfaces requires a physical-device run.

1. Run `xcodegen generate` from `ios/`.
2. Open `ios/FARO.xcodeproj`.
3. Select the FARO app target and choose your development team under Signing &
   Capabilities.
4. Connect and unlock the iPhone, enable Developer Mode if prompted, and select
   it as the run destination.
5. Run the `FARO` scheme.
6. Grant camera, location, microphone, and speech-recognition permissions when
   the relevant feature is tested.

For the hands-free flow, enable **Hands-Free** once and allow any requested
speech-asset download. Close or background FARO, say "Siri, open FARO," wait
for the ready tone, say "Hey FARO" or "Hola FARO," wait for the acknowledgement
tone, and then say one command. Confirm that backgrounding FARO stops listening.
For place enrollment, say "Remember this as Kitchen" or "Recuerda este lugar
como Cocina," follow the spoken turning instruction, and confirm that FARO
announces completion after saving nine views without opening the enrollment
sheet.

The generated project has an empty `DEVELOPMENT_TEAM`. Selecting a team in
Xcode changes only the ignored generated project, so you may need to select it
again after regeneration. Free provisioning profiles also expire periodically.

Check that the code compiles for a generic physical iOS target without signing:

```bash
cd ios
xcodegen generate
xcodebuild -project FARO.xcodeproj -scheme FARO \
  -destination 'generic/platform=iOS' \
  build CODE_SIGNING_ALLOWED=NO
```

## Bluetooth obstacle-module development

`docs/ble-contract.md` defines the service UUIDs, versioned telemetry packet,
operating-mode values, and reconnect behavior shared with the ESP32 firmware.
The iPhone app scans for the FARO service while running and exposes connection,
distance, warning, requested-mode, and confirmed-mode state in the localized
**Obstacle module** diagnostic view.

Simulator builds automatically use `MockObstaclePeripheral`. It connects
without Bluetooth hardware and cycles through clear, slow, fast, urgent, and
unavailable sonar readings. This lets the complete diagnostic UI and
Inactive/Navigating synchronization path be tested in either supported
language.

For a physical integration test:

1. Flash ESP32 firmware implementing `docs/ble-contract.md`.
2. Power the module and confirm it advertises `FARO-Obstacle`.
3. Launch FARO and open **Obstacle module**.
4. Confirm the connection reaches **Connected**, telemetry updates, and the
   confirmed ESP32 mode matches the iPhone mode.
5. Enter Navigating, disconnect or move the iPhone out of range, and confirm
   local sonar-to-buzzer warnings continue without the phone.
6. Reconnect, leave Navigating, and confirm the ESP32 reports Inactive and
   silences its local buzzer.

The Phase 6 iPhone-to-ESP32 integration was physically validated against this
contract on September 17, 2026.

Do not infer a clear path from missing or stale telemetry. The iPhone removes a
reading after two seconds without a valid packet, while immediate warnings
remain entirely local to the ESP32.

## Mock and live vision configuration

`ios/Config/Shared.xcconfig` defaults to:

```text
FARO_VISION_MODE = mock
```

Mock mode is the normal development baseline. It returns bilingual fixture
descriptions without network access.

To use a FARO vision service:

```bash
cd ios
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Then edit the ignored `Config/Local.xcconfig`:

```text
FARO_VISION_MODE = live
FARO_VISION_BASE_URL = https:/$()/vision.example.internal
FARO_VISION_TOKEN = replace-with-a-development-token
```

The `$()` separates the two slash characters from xcconfig comment syntax; the
value delivered to the app is a normal `https://` URL. Live mode accepts HTTPS,
or HTTP only for `localhost` and `127.0.0.1`. Remember that `localhost` on an
iPhone refers to the iPhone, not the development Mac.

Never commit `Local.xcconfig`, service tokens, private hostnames, or credentials.
The service contract is documented in
[docs/vision-api-contract.md](docs/vision-api-contract.md).
To run and exercise the included FastAPI service locally, follow
[backend/README.md](backend/README.md).
The current iOS client requests `brief` detail and supplies a localized
safety-focused prompt; the backend validates and forwards both options.

## Repository map

```text
FARO/
|-- DEVELOPMENT.md                 Developer setup and contribution workflow
|-- FARO-holder.stl                Printable prototype holder model
|-- IOS-TASKS.md                   Canonical roadmap and phase status
|-- project-faro.md                Product, architecture, and safety model
|-- backend/                       Private FastAPI vision service and tests
|-- docs/
|   |-- ble-contract.md            iPhone/ESP32 GATT boundary
|   `-- vision-api-contract.md     Scene-description HTTP boundary
|-- esp32/                         Obstacle firmware and host protocol tests
|-- ios/
|   |-- project.yml               XcodeGen source of truth
|   |-- Config/                    Mock/live build configuration
|   |-- FARO/
|   |   |-- Core/                 Camera, speech, recognition, mode, and clients
|   |   |-- Features/             SwiftUI feature views and view models
|   |   |-- Models/               SwiftData models
|   |   `-- Resources/            String Catalogs and simulator fixtures
|   `-- FAROTests/                Swift Testing suites
`-- .github/copilot-instructions.md
```

## Architecture at a glance

### Capture and description

- `ImageSource` separates image consumers from capture hardware.
- `FixtureImageSource` supplies deterministic simulator images.
- `CameraImageSource` owns the rear `AVCaptureSession` on a dedicated serial
  queue.
- `CaptureViewModel` orchestrates capture, persistence, description, place
  recognition, and enrollment.
- `SceneDescribing` separates the mock and `FAROVisionClient` implementations.

### Place memory

- SwiftData stores `Place` and `PlaceSnapshot`.
- Original JPEGs are retained so embeddings can be regenerated after a model
  change.
- Physical devices store Codable Vision FeaturePrint observations and compare
  them with Vision's official distance API.
- The simulator uses `PixelGridEmbedder` only for deterministic tests.
- Coarse GPS filters candidate sites; it does not identify an indoor room.
- Uncertain recognition must remain uncertain. Never replace thresholds with a
  forced best guess.

### Modes and voice

- `OperatingModeController` owns Inactive and Navigating state.
- Every fresh launch starts Inactive; the operating mode is never persisted.
- `VoiceCommandParser` parses bilingual commands.
- `VoiceCommandExecutor` routes commands into existing capture and place flows.
- `OnDeviceSpeechRecognizer` records a bounded temporary file and transcribes
  it after releasing the microphone.
- `OnDeviceWakePhraseDetector` streams foreground microphone buffers through
  iOS 26 `SpeechAnalyzer`, `SpeechTranscriber`, and `SpeechDetector`.
- `HandsFreeVoiceViewModel` owns persisted opt-in activation, Siri audio-handoff
  retries, wake feedback, and listening state.
- `VoiceInputCoordinator` serializes command capture and still-photo access.
- "Where am I?" and "What is ahead?" require Navigating mode.
- "Start navigation" and "Stop navigation" provide bilingual voice mode
  control.
- Manual Start and Finish controls remain the physically validated fallback.

### Bluetooth and obstacle module

- `ObstacleModuleProtocol` mirrors the packet and mode values in
  `docs/ble-contract.md`.
- `CoreBluetoothObstacleModuleTransport` discovers the advertised service,
  subscribes to telemetry and mode confirmation, and reconnects automatically.
- `MockObstaclePeripheral` is simulator-only infrastructure.
- The ESP32 firmware under `esp32/` owns sonar filtering, warning
  classification, and local passive-buzzer output.
- Bluetooth disconnects never disarm an already-Navigating ESP32; rebooting the
  ESP32 always returns it to Inactive.

## Camera and audio invariants

Recent iPhone 17 / iOS 26 builds can assert inside `FigCaptureSourceRemote` when
an app repeatedly stops and restarts the camera around voice input. Preserve
these rules:

1. Keep the video-only `AVCaptureSession` running.
2. Set `automaticallyConfiguresApplicationAudioSession` to `false`.
3. Suspend still-photo requests while command audio is being captured.
4. Do not add an audio input to the camera session.
5. Release microphone recording before command transcription and execution.
6. Do not reintroduce camera `stopRunning()` / `startRunning()` cycles for voice
   input.
7. Test repeated camera and microphone transitions on a physical iPhone.

The hands-free detector follows the same rules. It releases the microphone
before the bounded file recorder starts, remains disarmed while FARO speaks,
and stops when FARO leaves the foreground.

## Localization and accessibility

The supported choices are:

- Follow iPhone;
- English (United States), `en-US`;
- Spanish (Mexico), `es-MX`.

User-facing UI, accessibility labels, errors, permission text, and spoken
messages belong in:

- `ios/FARO/Resources/Localizable.xcstrings`;
- `ios/FARO/Resources/Places.xcstrings`;
- `ios/FARO/Resources/InfoPlist.xcstrings`.

When adding a string:

1. Add or reuse an `AppStringKey`.
2. Supply both English and Mexican Spanish translations.
3. Pass `SupportedLanguage` explicitly through the feature.
4. Preserve user-provided place labels exactly; do not translate them.
5. Add or update parameterized localization tests.

Dynamic String Catalog lookup can mark valid entries as `stale`. Do not delete
such entries without checking `AppStringKey` and `LanguageSupportTests`.

All controls need meaningful VoiceOver labels and hints, Dynamic Type support,
and large touch targets. Spoken output must use the selected language rather
than assuming the current system voice.

## Data and privacy

- Captured home imagery is sensitive.
- Still images are uploaded only after an explicit Describe action in live
  mode; FARO does not stream camera frames to the service.
- Saved place JPEGs and embeddings stay in the app container.
- Voice-command recordings are temporary and deleted after transcription.
- Wake-phrase audio remains inside the on-device Speech framework and is not
  retained as user content.
- Never log authorization tokens, image contents, or private place data.

Deleting the app from a simulator or device clears its SwiftData store,
remembered places, and saved images.

## Contribution workflow

1. Read `project-faro.md` and the current phase in `IOS-TASKS.md`.
2. Work only on tasks whose phase gate is open.
3. Reuse the existing protocol boundary before adding another implementation.
4. Keep simulator substitutes deterministic and production behavior
   device-backed.
5. Add focused tests for behavior changes.
6. Regenerate the Xcode project and run the smallest relevant test set.
7. Run the full simulator suite and generic iOS build before device validation.
8. Validate hardware-facing behavior on the physical iPhone.
9. Update the roadmap and architecture docs when behavior or scope changes.
10. Keep each phase in its own commit; use follow-up commits for validation
    fixes and do not begin the next phase before acceptance.

Do not commit generated Xcode files, local xcconfig files, DerivedData, secrets,
or developer-specific signing state.

## Common problems

### Xcode does not see a new Swift file

Run `xcodegen generate` again. The generated project is not updated
automatically when files move.

### The requested simulator does not exist

Run `xcrun simctl list devices available` and substitute an installed iOS 26
simulator in the destination string.

### Camera features do not work in the simulator

This is expected. The simulator uses fixture images. Validate
`CameraImageSource`, microphone capture, and production FeaturePrint behavior on
an iPhone.

### Physical-device signing fails

Choose a valid development team in Xcode, verify the phone is trusted and in
Developer Mode, and allow Xcode to manage signing. Regeneration may clear the
team selection from the ignored project.

### Live descriptions report a configuration error

Confirm `Config/Local.xcconfig` exists, uses `FARO_VISION_MODE = live`, contains
a valid base URL and token, and was present before regenerating/building.

### On-device speech is unavailable

Confirm Speech Recognition and Microphone permissions, verify that the selected
English or Mexican Spanish on-device assets are available, and test without a
Bluetooth route before investigating route-specific behavior.

### A camera/voice transition crashes in AVFoundation

Check that the camera session is not being stopped or restarted, that it cannot
configure the app audio session, and that microphone recording is released
before still capture begins. Preserve the file-based transcription boundary
unless a replacement has equivalent device evidence.

### Tests behave differently after changing place embeddings

Do not compare raw FeaturePrint bytes manually. Physical devices use Vision's
official `distance(to:)`; simulator tests use the separate deterministic
PixelGrid representation. Keep model identifiers and migration behavior intact.

## Source-of-truth order

When documentation disagrees, resolve it in this order:

1. `project-faro.md` for product and safety intent;
2. `IOS-TASKS.md` for current scope, ordering, and phase status;
3. `ios/project.yml` for targets and generated build settings;
4. `docs/vision-api-contract.md` for the remote scene-description boundary;
5. `docs/ble-contract.md` for the iPhone/ESP32 wire boundary;
6. `backend/README.md` and `esp32/README.md` for component operation;
7. `.github/copilot-instructions.md` for repository implementation invariants.

Update all affected documents in the same change when an architectural
decision alters more than one source of truth.
