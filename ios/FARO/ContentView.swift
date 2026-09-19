import SwiftData
import SwiftUI
import UIKit

private struct EnrollmentRequest: Identifiable {
    let id = UUID()
    let existingPlace: Place?
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(sort: \Place.createdAt, order: .reverse)
    private var places: [Place]

    @AppStorage(LanguagePreference.storageKey)
    private var languagePreferenceRaw = LanguagePreference.followSystem.rawValue
    @AppStorage(HandsFreePreference.storageKey)
    private var handsFreeEnabled = false

    @State private var captureModel = CaptureViewModel()
    @State private var modeController = OperatingModeController()
    @State private var voiceModel = VoiceCommandViewModel()
    @State private var handsFreeModel = HandsFreeVoiceViewModel()
    @State private var obstacleModuleModel =
        ObstacleModuleViewModel()
    @State private var navigationTask: Task<Void, Never>?
    @State private var voiceInputTask: Task<Void, Never>?
    @State private var voiceInputOperationID: UUID?
    @State private var voiceCommandTask: Task<Void, Never>?
    @State private var handsFreeArmTask: Task<Void, Never>?
    @State private var handsFreeCommandTask: Task<Void, Never>?
    @State private var handsFreeCommandID: UUID?
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
                    obstacleModuleLink
                    evaluationLink
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
                obstacleModuleModel.start(
                    mode: modeController.currentMode
                )
                await captureModel.prepare(language: language)
                activateHandsFreeIfNeeded()
            }
            .sheet(item: $enrollmentRequest, onDismiss: {
                activateHandsFreeIfNeeded(after: .milliseconds(500))
            }) { request in
                NavigationStack {
                    RememberPlaceView(
                        captureModel: captureModel,
                        existingPlace: request.existingPlace,
                        language: language
                    )
                }
            }
            .onChange(of: handsFreeEnabled) { _, isEnabled in
                if isEnabled {
                    activateHandsFreeIfNeeded()
                } else {
                    suspendHandsFree(cancelCommand: true)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    obstacleModuleModel.start(
                        mode: modeController.currentMode
                    )
                    activateHandsFreeIfNeeded(
                        after: .milliseconds(450)
                    )
                case .inactive:
                    suspendHandsFree(cancelCommand: false)
                case .background:
                    navigationTask?.cancel()
                    voiceInputTask?.cancel()
                    voiceCommandTask?.cancel()
                    captureModel.stopNavigationOutput()
                    obstacleModuleModel.stop()
                    suspendHandsFree(cancelCommand: true)
                @unknown default:
                    navigationTask?.cancel()
                    voiceInputTask?.cancel()
                    voiceCommandTask?.cancel()
                    captureModel.stopNavigationOutput()
                    obstacleModuleModel.stop()
                    suspendHandsFree(cancelCommand: true)
                }
            }
            .onChange(of: modeController.currentMode) { _, mode in
                obstacleModuleModel.updateOperatingMode(mode)
            }
            .onChange(of: languagePreferenceRaw) {
                _, _ in
                guard handsFreeEnabled else {
                    return
                }
                suspendHandsFree(cancelCommand: false)
                activateHandsFreeIfNeeded()
            }
            .onDisappear {
                navigationTask?.cancel()
                voiceInputTask?.cancel()
                voiceCommandTask?.cancel()
                captureModel.stopNavigationOutput()
                suspendHandsFree(cancelCommand: true)
            }
        }
        .environment(\.locale, language.locale)
    }

    private var captureIsBusy: Bool {
        captureModel.isCapturing
            || captureModel.isDescribing
            || captureModel.isRecognizing
            || captureModel.isEnrolling
            || captureModel.isPreparingPlaceMemory
    }

    private var isBusy: Bool {
        captureIsBusy
            || voiceModel.isActive
            || handsFreeIsHandlingCommand
    }

    private var handsFreeCanArm: Bool {
        HandsFreeActivationPolicy.shouldArm(
            isEnabled: handsFreeEnabled,
            isSceneActive: scenePhase == .active,
            isEnrollmentPresented: enrollmentRequest != nil,
            isCaptureBusy: captureIsBusy,
            isVoiceSessionActive: voiceModel.isActive
        )
        && voiceInputOperationID == nil
        && handsFreeCommandID == nil
    }

    private var handsFreeIsHandlingCommand: Bool {
        switch handsFreeModel.state {
        case .preparing,
             .wakePhraseDetected,
             .recordingCommand,
             .processingCommand,
             .executingCommand:
            true
        case .disabled, .listeningForWakePhrase:
            false
        }
    }

    private var handsFreeStatusSymbol: String {
        switch handsFreeModel.state {
        case .disabled:
            "mic.slash"
        case .preparing, .processingCommand:
            "waveform.badge.magnifyingglass"
        case .listeningForWakePhrase:
            "ear.badge.waveform"
        case .wakePhraseDetected:
            "waveform.circle.fill"
        case .recordingCommand:
            "mic.fill"
        case .executingCommand:
            "bolt.fill"
        }
    }

    private var describeButton: some View {
        Button {
            performTouchCaptureAction {
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
            beginTouchPlaceRecognition()
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
            suspendHandsFree(cancelCommand: false)
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
            performTouchCaptureAction {
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
            .onAppear {
                suspendHandsFree(cancelCommand: false)
            }
            .onDisappear {
                activateHandsFreeIfNeeded(
                    after: .milliseconds(500)
                )
            }
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
        .disabled(isBusy)
        .accessibilityHint(language.text(.hintRememberedPlaces))
    }

    private var savedCapturesLink: some View {
        NavigationLink {
            SavedCapturesView(
                images: captureModel.storedImages,
                language: language
            )
            .onAppear {
                suspendHandsFree(cancelCommand: false)
            }
            .onDisappear {
                activateHandsFreeIfNeeded(
                    after: .milliseconds(500)
                )
            }
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
        .disabled(isBusy)
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
            .disabled(
                voiceModel.isActive
                    || handsFreeIsHandlingCommand
            )
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
                suspendHandsFree(cancelCommand: false)
                if modeController.currentMode == .navigating {
                    navigationTask?.cancel()
                    captureModel.stopNavigationOutput()
                }
                modeController.toggle(language: language)
                activateHandsFreeIfNeeded(
                    after: .milliseconds(700)
                )
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
            .disabled(isBusy)
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

            Divider()

            Toggle(
                language.text(.handsFreeToggle),
                isOn: $handsFreeEnabled
            )
            .font(.headline)
            .accessibilityHint(language.text(.hintHandsFree))

            Text(language.text(.handsFreeInstructions))
                .font(.body)
                .foregroundStyle(.secondary)

            if handsFreeEnabled {
                if let error = handsFreeModel.errorText(
                    language: language
                ) {
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.red)
                } else {
                    Label(
                        handsFreeModel.statusText(language: language),
                        systemImage: handsFreeStatusSymbol
                    )
                    .foregroundStyle(.secondary)
                }

            }

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
                    || handsFreeIsHandlingCommand
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

    private var obstacleModuleLink: some View {
        NavigationLink {
            ObstacleModuleDebugView(
                model: obstacleModuleModel,
                language: language
            )
            .onAppear {
                suspendHandsFree(cancelCommand: false)
            }
            .onDisappear {
                activateHandsFreeIfNeeded(
                    after: .milliseconds(500)
                )
            }
        } label: {
            HStack(spacing: 12) {
                Label(
                    language.text(.bleTitle),
                    systemImage: "sensor"
                )
                .font(.headline)
                Spacer()
                Text(
                    obstacleModuleModel.summaryText(
                        language: language
                    )
                )
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
            }
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(language.text(.bleHint))
    }

    private var evaluationLink: some View {
        NavigationLink {
            EvaluationView(
                captureModel: captureModel,
                obstacleModuleModel: obstacleModuleModel,
                language: language
            )
            .onAppear {
                suspendHandsFree(cancelCommand: false)
            }
            .onDisappear {
                activateHandsFreeIfNeeded(
                    after: .milliseconds(500)
                )
            }
        } label: {
            Label(
                language.text(.evaluationTitle),
                systemImage: "chart.xyaxis.line"
            )
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(language.text(.evaluationHint))
        .disabled(isBusy)
    }

    private func beginVoiceCommand() {
        suspendHandsFree(cancelCommand: false)
        captureModel.stopNavigationOutput()
        let selectedLanguage = language
        voiceInputTask?.cancel()
        let operationID = UUID()
        voiceInputOperationID = operationID
        voiceInputTask = Task {
            let started = await VoiceInputCoordinator(
                camera: captureModel,
                voiceSession: voiceModel
            ).begin(
                language: selectedLanguage
            )
            guard !Task.isCancelled,
                  scenePhase == .active,
                  language == selectedLanguage else {
                if started {
                    voiceModel.cancel()
                    _ = await captureModel
                        .resumeCameraCaptureAfterVoiceInput(
                            language: selectedLanguage
                        )
                }
                finishVoiceInputOperation(operationID)
                activateHandsFreeIfNeeded(
                    after: .milliseconds(500)
                )
                return
            }
            finishVoiceInputOperation(operationID)
            if !started {
                activateHandsFreeIfNeeded(
                    after: .milliseconds(500)
                )
            }
        }
    }

    private func finishVoiceCommand() {
        let selectedLanguage = language
        voiceInputTask?.cancel()
        let operationID = UUID()
        voiceInputOperationID = operationID
        voiceInputTask = Task {
            let command = await VoiceInputCoordinator(
                camera: captureModel,
                voiceSession: voiceModel
            ).finish(language: selectedLanguage)
            guard !Task.isCancelled,
                  scenePhase == .active,
                  language == selectedLanguage else {
                finishVoiceInputOperation(operationID)
                activateHandsFreeIfNeeded(
                    after: .milliseconds(500)
                )
                return
            }
            finishVoiceInputOperation(operationID)
            if let command {
                executeVoiceCommand(
                    command,
                    language: selectedLanguage
                )
            } else {
                activateHandsFreeIfNeeded(
                    after: .milliseconds(700)
                )
            }
        }
    }

    private func finishVoiceInputOperation(_ id: UUID) {
        guard voiceInputOperationID == id else {
            return
        }
        voiceInputOperationID = nil
    }

    private func executeVoiceCommand(
        _ command: VoiceCommand,
        language: SupportedLanguage
    ) {
        if command == .stopNavigating {
            navigationTask?.cancel()
            captureModel.stopNavigationOutput()
        }

        let task = Task {
            let shouldRearm = await performVoiceCommand(
                command,
                language: language
            )
            await captureModel.waitForSpeechOutputToFinish()
            if Task.isCancelled {
                captureModel.stopNavigationOutput()
                activateHandsFreeIfNeeded(
                    after: .milliseconds(500)
                )
                return
            }
            guard shouldRearm else {
                return
            }
            activateHandsFreeIfNeeded(
                after: .milliseconds(700)
            )
        }

        if command.requiresNavigating {
            navigationTask?.cancel()
            navigationTask = task
        } else {
            voiceCommandTask?.cancel()
            voiceCommandTask = task
        }
    }

    private func performVoiceCommand(
        _ command: VoiceCommand,
        language: SupportedLanguage
    ) async -> Bool {
        if command == .stopNavigating {
            navigationTask?.cancel()
            captureModel.stopNavigationOutput()
        }

        do {
            _ = try await VoiceCommandExecutor(
                captureModel: captureModel,
                modeController: modeController
            ).execute(
                command,
                places: places,
                modelContext: modelContext,
                language: language
            )
            try Task.checkCancellation()
            voiceModel.markExecutionComplete()
            return true
        } catch is CancellationError {
            captureModel.stopNavigationOutput()
            voiceModel.markExecutionComplete()
            return false
        } catch {
            voiceModel.reportExecutionError(
                error,
                language: language
            )
            return true
        }
    }

    private func activateHandsFreeIfNeeded(
        after delay: Duration = .zero
    ) {
        guard handsFreeCanArm,
              handsFreeModel.state == .disabled else {
            return
        }

        handsFreeArmTask?.cancel()
        let selectedLanguage = language
        handsFreeArmTask = Task {
            if delay > .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled,
                  handsFreeCanArm,
                  language == selectedLanguage else {
                return
            }
            await handsFreeModel.arm(
                language: selectedLanguage
            ) {
                startHandsFreeCommand(
                    language: selectedLanguage
                )
            }
        }
    }

    private func suspendHandsFree(cancelCommand: Bool) {
        handsFreeArmTask?.cancel()
        handsFreeArmTask = nil
        handsFreeModel.disarm()

        guard cancelCommand else {
            return
        }
        if let handsFreeCommandTask {
            handsFreeCommandTask.cancel()
        } else {
            handsFreeCommandID = nil
        }
        if voiceModel.isActive {
            voiceModel.cancel()
            Task {
                _ = await captureModel
                    .resumeCameraCaptureAfterVoiceInput(
                        language: language
                    )
            }
        }
    }

    private func startHandsFreeCommand(
        language: SupportedLanguage
    ) {
        guard handsFreeEnabled,
              scenePhase == .active,
              enrollmentRequest == nil,
              self.language == language else {
            suspendHandsFree(cancelCommand: true)
            return
        }

        handsFreeCommandTask?.cancel()
        let commandID = UUID()
        handsFreeCommandID = commandID
        handsFreeCommandTask = Task {
            await runHandsFreeCommand(
                id: commandID,
                language: language
            )
        }
    }

    private func runHandsFreeCommand(
        id: UUID,
        language: SupportedLanguage
    ) async {
        do {
            try Task.checkCancellation()
            guard handsFreeCommandID == id,
                  handsFreeEnabled,
                  scenePhase == .active,
                  enrollmentRequest == nil else {
                throw CancellationError()
            }

            handsFreeModel.beginCommandCapture()
            captureModel.stopNavigationOutput()
            let coordinator = VoiceInputCoordinator(
                camera: captureModel,
                voiceSession: voiceModel
            )
            let started = await coordinator.begin(
                language: language
            )
            guard started else {
                await finishHandsFreeCommand(
                    id: id,
                    shouldRearm: true
                )
                return
            }

            let command = await coordinator.finishAutomatically(
                language: language
            ) {
                handsFreeModel.beginCommandProcessing()
            }
            try Task.checkCancellation()
            guard let command else {
                await finishHandsFreeCommand(
                    id: id,
                    shouldRearm: true
                )
                return
            }

            handsFreeModel.beginCommandExecution()
            let shouldRearm = await performVoiceCommand(
                command,
                language: language
            )
            await captureModel.waitForSpeechOutputToFinish()
            try Task.checkCancellation()
            await finishHandsFreeCommand(
                id: id,
                shouldRearm: shouldRearm
            )
        } catch is CancellationError {
            finishCancelledHandsFreeCommand(id: id)
        } catch {
            finishCancelledHandsFreeCommand(id: id)
        }
    }

    private func finishHandsFreeCommand(
        id: UUID,
        shouldRearm: Bool
    ) async {
        guard handsFreeCommandID == id else {
            return
        }
        if shouldRearm {
            do {
                try await Task.sleep(for: .milliseconds(700))
            } catch {
                return
            }
        }
        guard handsFreeCommandID == id else {
            return
        }
        handsFreeCommandID = nil
        handsFreeCommandTask = nil
        handsFreeModel.disarm()
        if shouldRearm {
            activateHandsFreeIfNeeded()
        }
    }

    private func finishCancelledHandsFreeCommand(id: UUID) {
        guard handsFreeCommandID == id else {
            return
        }
        handsFreeCommandID = nil
        handsFreeCommandTask = nil
        captureModel.stopNavigationOutput()
        handsFreeModel.disarm()
        activateHandsFreeIfNeeded(
            after: .milliseconds(500)
        )
    }

    private func performTouchCaptureAction(
        _ operation: @escaping @MainActor () async -> Void
    ) {
        suspendHandsFree(cancelCommand: false)
        voiceCommandTask?.cancel()
        voiceCommandTask = Task {
            await operation()
            await captureModel.waitForSpeechOutputToFinish()
            guard !Task.isCancelled else {
                return
            }
            activateHandsFreeIfNeeded(
                after: .milliseconds(700)
            )
        }
    }

    private func beginTouchPlaceRecognition() {
        modeController.performNavigationOutput {
            suspendHandsFree(cancelCommand: false)
            navigationTask?.cancel()
            let selectedLanguage = language
            navigationTask = Task {
                await captureModel.preparePlaceMemoryLocation()
                guard !Task.isCancelled else {
                    return
                }
                await captureModel.recognizePlace(
                    in: places,
                    modelContext: modelContext,
                    language: selectedLanguage
                )
                await captureModel.waitForSpeechOutputToFinish()
                guard !Task.isCancelled else {
                    return
                }
                activateHandsFreeIfNeeded(
                    after: .milliseconds(700)
                )
            }
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
