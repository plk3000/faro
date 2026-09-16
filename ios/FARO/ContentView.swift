import SwiftData
import SwiftUI
import UIKit

private struct EnrollmentRequest: Identifiable {
    let id = UUID()
    let existingPlace: Place?
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Place.createdAt, order: .reverse)
    private var places: [Place]

    @AppStorage(LanguagePreference.storageKey)
    private var languagePreferenceRaw = LanguagePreference.followSystem.rawValue

    @State private var captureModel = CaptureViewModel()
    @State private var modeController = OperatingModeController()
    @State private var voiceModel = VoiceCommandViewModel()
    @State private var navigationTask: Task<Void, Never>?
    @State private var voiceCommandTask: Task<Void, Never>?
    @State private var enrollmentRequest: EnrollmentRequest?

    private var languagePreference: LanguagePreference {
        LanguagePreference(rawValue: languagePreferenceRaw) ?? .followSystem
    }

    private var language: SupportedLanguage {
        languagePreference.resolve()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    languagePicker
                    modeCard
                    voiceCommandCard
                    preview
                    describeButton
                    whereAmIButton
                    rememberPlaceButton
                    captureButton
                    status
                    descriptionCard
                    placeResultCard
                    placesLink
                    savedCapturesLink
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("FARO")
            .task {
                await captureModel.prepare(language: language)
            }
            .sheet(item: $enrollmentRequest) { request in
                NavigationStack {
                    RememberPlaceView(
                        captureModel: captureModel,
                        existingPlace: request.existingPlace,
                        language: language
                    )
                }
            }
            .onDisappear {
                navigationTask?.cancel()
                voiceCommandTask?.cancel()
                voiceModel.cancel()
                Task {
                    await captureModel.resumeCameraCaptureAfterVoiceInput(
                        language: language
                    )
                }
            }
        }
        .environment(\.locale, language.locale)
    }

    private var captureIsBusy: Bool {
        captureModel.isCapturing
            || captureModel.isDescribing
            || captureModel.isRecognizing
            || captureModel.isEnrolling
    }

    private var isBusy: Bool {
        captureIsBusy || voiceModel.isActive
    }

    private var describeButton: some View {
        Button {
            Task {
                await captureModel.describe(language: language)
            }
        } label: {
            Label(
                language.text(
                    captureModel.isDescribing
                        ? .actionDescribing
                        : .actionDescribe
                ),
                systemImage: "text.bubble"
            )
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isBusy)
        .accessibilityLabel(
            language.text(
                captureModel.isDescribing
                    ? .actionDescribing
                    : .actionDescribe
            )
        )
        .accessibilityHint(language.text(.hintDescribe))
    }

    private var whereAmIButton: some View {
        Button {
            modeController.performNavigationOutput {
                captureModel.preparePlaceMemoryLocation()
                navigationTask?.cancel()
                navigationTask = Task {
                    await captureModel.recognizePlace(
                        in: places,
                        modelContext: modelContext,
                        language: language
                    )
                }
            }
        } label: {
            Label(
                language.text(
                    captureModel.isRecognizing
                        ? .actionCheckingPlace
                        : .actionWhereAmI
                ),
                systemImage: "location.viewfinder"
            )
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(
            isBusy || !modeController.navigationOutputEnabled
        )
        .accessibilityHint(
            language.text(
                modeController.navigationOutputEnabled
                    ? .hintWhereAmI
                    : .hintWhereAmIRequiresNavigating
            )
        )
    }

    private var rememberPlaceButton: some View {
        Button {
            enrollmentRequest = EnrollmentRequest(
                existingPlace: nil
            )
        } label: {
            Label(
                language.text(.actionRememberPlace),
                systemImage: "plus.viewfinder"
            )
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.bordered)
        .disabled(isBusy)
        .accessibilityHint(language.text(.hintRememberPlace))
    }

    private var captureButton: some View {
        Button {
            Task {
                await captureModel.capture(language: language)
            }
        } label: {
            Label(
                language.text(
                    captureModel.isCapturing
                        ? .actionCapturing
                        : .actionCapture
                ),
                systemImage: "camera.shutter.button"
            )
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(.secondary)
        .disabled(isBusy)
        .accessibilityLabel(
            language.text(
                captureModel.isCapturing
                    ? .actionCapturing
                    : .actionCapture
            )
        )
        .accessibilityHint(language.text(.hintCapture))
    }

    @ViewBuilder
    private var descriptionCard: some View {
        if let description = captureModel.latestDescription {
            Text(description.text)
                .font(.title3)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .accessibilityLabel(
                    descriptionAccessibilityLabel(description)
                )
        }
    }

    @ViewBuilder
    private var placeResultCard: some View {
        if let result = captureModel.latestPlaceResult {
            Text(result.text)
                .font(.title2.bold())
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    .green.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .accessibilityLabel(
                    placeResultAccessibilityLabel(result)
                )
        }
    }

    private var placesLink: some View {
        NavigationLink {
            PlacesView(
                captureModel: captureModel,
                language: language
            )
        } label: {
            Label(
                language.text(
                    .placesTitleCount,
                    argument: String(places.count)
                ),
                systemImage: "mappin.and.ellipse"
            )
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(language.text(.hintRememberedPlaces))
    }

    private var savedCapturesLink: some View {
        NavigationLink {
            SavedCapturesView(
                images: captureModel.storedImages,
                language: language
            )
        } label: {
            Label(
                language.text(
                    .savedTitleCount,
                    argument: String(captureModel.storedImages.count)
                ),
                systemImage: "photo.on.rectangle"
            )
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(language.text(.savedHint))
    }

    private var languagePicker: some View {
        HStack {
            Label(
                language.text(.languageSelector),
                systemImage: "globe"
            )
            Spacer()
            Picker(
                language.text(.languageSelector),
                selection: $languagePreferenceRaw
            ) {
                ForEach(LanguagePreference.allCases) { preference in
                    Text(language.text(preference.displayKey))
                        .tag(preference.rawValue)
                }
            }
            .pickerStyle(.menu)
            .disabled(voiceModel.isActive)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private var preview: some View {
        Group {
            if let session = captureModel.cameraSession {
                CameraPreview(session: session)
                    .accessibilityLabel(language.text(.previewRear))
            } else if let data = captureModel.latestImageData,
                      let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel(language.text(.previewLatest))
            } else {
                ZStack {
                    Color.black
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.largeTitle)
                        Text(language.text(.previewSimulatorTitle))
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                }
                .accessibilityLabel(language.text(.previewSimulatorLabel))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .clipped()
    }

    private var status: some View {
        let statusText = captureModel.statusText(language: language)
        return HStack(alignment: .top, spacing: 10) {
            Image(
                systemName: captureModel.errorMessage == nil
                    ? "checkmark.circle"
                    : "exclamationmark.triangle"
            )
            .foregroundStyle(
                captureModel.errorMessage == nil
                    ? Color.secondary
                    : Color.red
            )
            Text(statusText)
                .font(.body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            language.text(
                .statusAccessibility,
                argument: statusText
            )
        )
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(
                    systemName: modeController.currentMode == .navigating
                        ? "figure.walk.circle.fill"
                        : "pause.circle.fill"
                )
                .foregroundStyle(
                    modeController.currentMode == .navigating
                        ? Color.green
                        : Color.secondary
                )
                .font(.title)

                VStack(alignment: .leading) {
                    Text(language.text(.modeLabel))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(
                        language.text(
                            modeController.currentMode.displayKey
                        )
                    )
                    .font(.title3.bold())
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                language.text(
                    modeController.currentMode.currentModeKey
                )
            )

            Button {
                if modeController.currentMode == .navigating {
                    navigationTask?.cancel()
                    captureModel.stopNavigationOutput()
                }
                modeController.toggle(language: language)
            } label: {
                Label(
                    language.text(
                        modeController.currentMode.toggleActionKey
                    ),
                    systemImage: modeController.currentMode == .navigating
                        ? "stop.circle.fill"
                        : "play.circle.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
            }
            .buttonStyle(.borderedProminent)
            .disabled(voiceModel.isActive)
            .tint(
                modeController.currentMode == .navigating
                    ? .orange
                    : .green
            )
            .accessibilityHint(
                language.text(
                    modeController.currentMode.toggleHintKey
                )
            )
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var voiceCommandCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                language.text(.voiceTitle),
                systemImage: "waveform.circle.fill"
            )
            .font(.title3.bold())

            Text(language.text(.voiceInstructions))
                .font(.body)
                .foregroundStyle(.secondary)

            if !voiceModel.transcript.isEmpty {
                Text(
                    language.text(
                        .voiceTranscript,
                        argument: voiceModel.transcript
                    )
                )
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(
                    language.text(
                        .voiceTranscript,
                        argument: voiceModel.transcript
                    )
                )
            }

            if let error = voiceModel.errorText(language: language) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
            } else {
                Text(voiceModel.statusText(language: language))
                    .foregroundStyle(.secondary)
            }

            Button {
                if voiceModel.isListening {
                    finishVoiceCommand()
                } else {
                    beginVoiceCommand()
                }
            } label: {
                Label(
                    language.text(
                        voiceModel.isListening
                            ? .actionFinishVoiceCommand
                            : .actionStartVoiceCommand
                    ),
                    systemImage: voiceModel.isListening
                        ? "stop.circle.fill"
                        : "mic.circle.fill"
                )
                .font(.title3.bold())
                .frame(maxWidth: .infinity, minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .tint(voiceModel.isListening ? .red : .blue)
            .disabled(
                captureIsBusy
                    || voiceModel.isPreparing
                    || voiceModel.isProcessing
            )
            .accessibilityHint(
                language.text(
                    voiceModel.isListening
                        ? .hintFinishVoiceCommand
                        : .hintStartVoiceCommand
                )
            )
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func beginVoiceCommand() {
        captureModel.stopNavigationOutput()
        Task {
            await VoiceInputCoordinator(
                camera: captureModel,
                voiceSession: voiceModel
            ).begin(
                language: language
            )
        }
    }

    private func finishVoiceCommand() {
        Task {
            let command = await VoiceInputCoordinator(
                camera: captureModel,
                voiceSession: voiceModel
            ).finish(language: language)
            if let command {
                executeVoiceCommand(command)
            }
        }
    }

    private func executeVoiceCommand(_ command: VoiceCommand) {
        let task = Task {
            do {
                let result = try await VoiceCommandExecutor(
                    captureModel: captureModel,
                    modeController: modeController
                ).execute(
                    command,
                    places: places,
                    modelContext: modelContext,
                    language: language
                )
                try Task.checkCancellation()
                if case let .continueEnrollment(place) = result {
                    enrollmentRequest = EnrollmentRequest(
                        existingPlace: place
                    )
                }
                voiceModel.markExecutionComplete()
            } catch is CancellationError {
                voiceModel.markExecutionComplete()
            } catch {
                voiceModel.reportExecutionError(
                    error,
                    language: language
                )
            }
        }

        if command.requiresNavigating {
            navigationTask?.cancel()
            navigationTask = task
        } else {
            voiceCommandTask?.cancel()
            voiceCommandTask = task
        }
    }

    private func descriptionAccessibilityLabel(
        _ description: SceneDescription
    ) -> Text {
        accessibilityText(
            description.language.text(
                .sceneDescriptionLabel,
                argument: description.text
            ),
            language: description.language
        )
    }

    private func placeResultAccessibilityLabel(
        _ result: PlaceRecognitionOutput
    ) -> Text {
        accessibilityText(
            result.language.text(
                .placeResultAccessibility,
                argument: result.text
            ),
            language: result.language
        )
    }

    private func accessibilityText(
        _ value: String,
        language: SupportedLanguage
    ) -> Text {
        let attributedValue = NSAttributedString(
            string: value,
            attributes: [
                .accessibilitySpeechLanguage: language.rawValue
            ]
        )
        return Text(AttributedString(attributedValue))
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [Place.self, PlaceSnapshot.self],
            inMemory: true
        )
}
