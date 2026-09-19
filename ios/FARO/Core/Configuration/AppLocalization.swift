import Foundation

private final class FAROResourceBundleMarker {}

extension Bundle {
    static let faroResources = Bundle(for: FAROResourceBundleMarker.self)
}

enum AppStringKey: String, CaseIterable, Sendable {
    case languageSelector = "language.selector"
    case languageFollowSystem = "language.followSystem"
    case languageEnglishUS = "language.englishUS"
    case languageSpanishMexico = "language.spanishMexico"
    case actionDescribe = "action.describe"
    case actionDescribing = "action.describing"
    case actionCapture = "action.capture"
    case actionCapturing = "action.capturing"
    case actionStartNavigating = "action.startNavigating"
    case actionStopNavigating = "action.stopNavigating"
    case actionStartVoiceCommand = "action.startVoiceCommand"
    case actionFinishVoiceCommand = "action.finishVoiceCommand"
    case hintDescribe = "hint.describe"
    case hintCapture = "hint.capture"
    case hintStartNavigating = "hint.startNavigating"
    case hintStopNavigating = "hint.stopNavigating"
    case hintWhereAmIRequiresNavigating =
        "hint.whereAmIRequiresNavigating"
    case hintStartVoiceCommand = "hint.startVoiceCommand"
    case hintFinishVoiceCommand = "hint.finishVoiceCommand"
    case hintHandsFree = "hint.handsFree"
    case voiceTitle = "voice.title"
    case voiceInstructions = "voice.instructions"
    case voiceTranscript = "voice.transcript"
    case handsFreeToggle = "handsFree.toggle"
    case handsFreeInstructions = "handsFree.instructions"
    case bleTitle = "ble.title"
    case bleHint = "ble.hint"
    case bleConnectionSection = "ble.connection.section"
    case bleConnectionLabel = "ble.connection.label"
    case bleTelemetrySection = "ble.telemetry.section"
    case bleDistanceLabel = "ble.distance.label"
    case bleDistanceValue = "ble.distance.value"
    case bleDistanceUnavailable = "ble.distance.unavailable"
    case bleWarningLabel = "ble.warning.label"
    case bleWarningClear = "ble.warning.clear"
    case bleWarningSlow = "ble.warning.slow"
    case bleWarningFast = "ble.warning.fast"
    case bleWarningUrgent = "ble.warning.urgent"
    case bleWarningSensorUnavailable =
        "ble.warning.sensorUnavailable"
    case bleModeSection = "ble.mode.section"
    case bleRequestedModeLabel = "ble.mode.requested"
    case bleConfirmedModeLabel = "ble.mode.confirmed"
    case bleModeNotConfirmed = "ble.mode.notConfirmed"
    case bleModeSynchronizing = "ble.mode.synchronizing"
    case bleSafetyNote = "ble.safetyNote"
    case bleStateIdle = "ble.state.idle"
    case bleStateUnavailable = "ble.state.unavailable"
    case bleStateScanning = "ble.state.scanning"
    case bleStateConnecting = "ble.state.connecting"
    case bleStateDiscovering = "ble.state.discovering"
    case bleStateConnected = "ble.state.connected"
    case bleStateDisconnected = "ble.state.disconnected"
    case evaluationTitle = "evaluation.title"
    case evaluationHint = "evaluation.hint"
    case evaluationInstructions = "evaluation.instructions"
    case evaluationSummarySection = "evaluation.summary.section"
    case evaluationNoTrials = "evaluation.summary.noTrials"
    case evaluationTrialCount = "evaluation.summary.trialCount"
    case evaluationAccuracy = "evaluation.summary.accuracy"
    case evaluationFalseConfident =
        "evaluation.summary.falseConfident"
    case evaluationAverageLatency =
        "evaluation.summary.averageLatency"
    case evaluationObservationCount =
        "evaluation.summary.observationCount"
    case evaluationRecognitionSection =
        "evaluation.recognition.section"
    case evaluationExpectedPlace =
        "evaluation.recognition.expectedPlace"
    case evaluationUnknownPlace =
        "evaluation.recognition.unknownPlace"
    case evaluationAngle = "evaluation.recognition.angle"
    case evaluationLighting = "evaluation.recognition.lighting"
    case evaluationRunTrial = "evaluation.recognition.run"
    case evaluationRunningTrial = "evaluation.recognition.running"
    case evaluationLatestResult =
        "evaluation.recognition.latestResult"
    case evaluationNoPrediction =
        "evaluation.recognition.noPrediction"
    case evaluationOutcomeCorrectMatch =
        "evaluation.outcome.correctMatch"
    case evaluationOutcomeCorrectRejection =
        "evaluation.outcome.correctRejection"
    case evaluationOutcomeUncertain =
        "evaluation.outcome.uncertain"
    case evaluationOutcomeFalseConfident =
        "evaluation.outcome.falseConfident"
    case evaluationAngleEnrollmentLike =
        "evaluation.angle.enrollmentLike"
    case evaluationAngleLeftOblique =
        "evaluation.angle.leftOblique"
    case evaluationAngleRightOblique =
        "evaluation.angle.rightOblique"
    case evaluationAngleReverse = "evaluation.angle.reverse"
    case evaluationAngleOther = "evaluation.angle.other"
    case evaluationLightingSimilar =
        "evaluation.lighting.similar"
    case evaluationLightingBrighter =
        "evaluation.lighting.brighter"
    case evaluationLightingDimmer =
        "evaluation.lighting.dimmer"
    case evaluationLightingArtificial =
        "evaluation.lighting.artificial"
    case evaluationLightingMixed =
        "evaluation.lighting.mixed"
    case evaluationFieldSection = "evaluation.field.section"
    case evaluationCategory = "evaluation.field.category"
    case evaluationCategoryLanguage =
        "evaluation.category.language"
    case evaluationCategoryNarration =
        "evaluation.category.narration"
    case evaluationCategoryProximity =
        "evaluation.category.proximity"
    case evaluationCategoryWake = "evaluation.category.wake"
    case evaluationCategoryGeneral =
        "evaluation.category.general"
    case evaluationUsefulnessRating =
        "evaluation.field.usefulnessRating"
    case evaluationAnnoyanceRating =
        "evaluation.field.annoyanceRating"
    case evaluationMeasuredDistance =
        "evaluation.field.measuredDistance"
    case evaluationAlertHeard = "evaluation.field.alertHeard"
    case evaluationTelemetrySnapshot =
        "evaluation.field.telemetrySnapshot"
    case evaluationTelemetryUnavailable =
        "evaluation.field.telemetryUnavailable"
    case evaluationNotesPlaceholder =
        "evaluation.field.notesPlaceholder"
    case evaluationSaveObservation =
        "evaluation.field.saveObservation"
    case evaluationSavingObservation =
        "evaluation.field.savingObservation"
    case evaluationExportSection =
        "evaluation.export.section"
    case evaluationShareExport = "evaluation.export.share"
    case evaluationClearData = "evaluation.export.clear"
    case evaluationClearTitle = "evaluation.export.clearTitle"
    case evaluationClearMessage = "evaluation.export.clearMessage"
    case evaluationPrivacyNote = "evaluation.export.privacyNote"
    case evaluationNotAvailable = "evaluation.value.notAvailable"
    case evaluationMilliseconds = "evaluation.value.milliseconds"
    case voiceCommandDescribe = "voice.command.describe"
    case voiceCommandWhereAmI = "voice.command.whereAmI"
    case voiceCommandRememberPlace = "voice.command.rememberPlace"
    case voiceCommandWhatIsAhead = "voice.command.whatIsAhead"
    case voiceCommandStartNavigating =
        "voice.command.startNavigating"
    case voiceCommandStopNavigating =
        "voice.command.stopNavigating"
    case sceneDescriptionLabel = "scene.descriptionLabel"
    case savedTitleCount = "saved.titleCount"
    case savedHint = "saved.hint"
    case previewRear = "preview.rear"
    case previewLatest = "preview.latest"
    case previewSimulatorTitle = "preview.simulatorTitle"
    case previewSimulatorLabel = "preview.simulatorLabel"
    case statusAccessibility = "status.accessibility"
    case modeLabel = "mode.label"
    case modeInactive = "mode.inactive"
    case modeNavigating = "mode.navigating"
    case modeCurrentInactive = "mode.currentInactive"
    case modeCurrentNavigating = "mode.currentNavigating"
    case modeInactiveEnabled = "mode.inactiveEnabled"
    case modeNavigatingEnabled = "mode.navigatingEnabled"
    case savedEmptyTitle = "saved.empty.title"
    case savedEmptyDescription = "saved.empty.description"
    case savedCaptureAccessibility = "saved.captureAccessibility"
    case savedTitle = "saved.title"
    case actionWhereAmI = "action.whereAmI"
    case actionCheckingPlace = "action.checkingPlace"
    case actionRememberPlace = "action.rememberPlace"
    case actionCapturePlaceView = "action.capturePlaceView"
    case actionAddViews = "action.addViews"
    case actionRename = "action.rename"
    case actionClose = "action.close"
    case actionDone = "action.done"
    case actionCancel = "action.cancel"
    case actionSave = "action.save"
    case actionOK = "action.ok"
    case hintWhereAmI = "hint.whereAmI"
    case hintRememberPlace = "hint.rememberPlace"
    case hintRememberedPlaces = "hint.rememberedPlaces"
    case hintCapturePlaceView = "hint.capturePlaceView"
    case placeResultAccessibility = "place.resultAccessibility"
    case placeMatched = "place.matched"
    case placeUncertain = "place.uncertain"
    case placesTitle = "places.title"
    case placesTitleCount = "places.titleCount"
    case placesEmptyTitle = "places.empty.title"
    case placesEmptyDescription = "places.empty.description"
    case placeNameLabel = "place.name.label"
    case placeNamePlaceholder = "place.name.placeholder"
    case placeViewsSection = "place.views.section"
    case placeViewsCount = "place.views.count"
    case placeViewsProgress = "place.views.progress"
    case placeRememberTitle = "place.remember.title"
    case placeAddViewsTitle = "place.addViews.title"
    case placeRenameTitle = "place.rename.title"
    case placeUpdateFailedTitle = "place.updateFailed.title"
    case placeInstructionFirst = "place.instruction.first"
    case placeInstructionLeft = "place.instruction.left"
    case placeInstructionRight = "place.instruction.right"
    case placeInstructionReverse = "place.instruction.reverse"
    case placeInstructionLighting = "place.instruction.lighting"
    case placeInstructionEnough = "place.instruction.enough"
    case placeScanInstructions = "place.scan.instructions"
    case statusReady = "status.ready"
    case statusCapturingImage = "status.capturingImage"
    case statusImageCapturedSaved = "status.imageCapturedSaved"
    case statusCapturingScene = "status.capturingScene"
    case statusDescribingScene = "status.describingScene"
    case statusDescriptionReady = "status.descriptionReady"
    case statusCheckingLocation = "status.checkingLocation"
    case statusPlaceRecognitionComplete = "status.placeRecognitionComplete"
    case statusPlaceScanComplete = "status.placeScanComplete"
    case statusCapturingPlaceView = "status.capturingPlaceView"
    case statusSavedPlaceView = "status.savedPlaceView"
    case statusUpdatingPlaceEmbeddings = "status.updatingPlaceEmbeddings"
    case statusVoiceReady = "status.voiceReady"
    case statusVoicePreparing = "status.voicePreparing"
    case statusVoiceListening = "status.voiceListening"
    case statusVoiceProcessing = "status.voiceProcessing"
    case statusVoiceRecognized = "status.voiceRecognized"
    case statusHandsFreeOff = "status.handsFree.off"
    case statusHandsFreePreparing = "status.handsFree.preparing"
    case statusHandsFreeListening = "status.handsFree.listening"
    case statusHandsFreeWakeDetected =
        "status.handsFree.wakeDetected"
    case statusHandsFreeRecording = "status.handsFree.recording"
    case statusHandsFreeProcessing = "status.handsFree.processing"
    case statusHandsFreeExecuting = "status.handsFree.executing"
    case errorGenericAction = "error.genericAction"
    case errorCameraUnavailable = "error.cameraUnavailable"
    case errorCameraPermission = "error.cameraPermission"
    case errorCameraConfiguration = "error.cameraConfiguration"
    case errorCaptureInProgress = "error.captureInProgress"
    case errorCaptureFailed = "error.captureFailed"
    case errorFixtureNotFound = "error.fixtureNotFound"
    case errorInvalidImageData = "error.invalidImageData"
    case errorStoreDirectory = "error.storeDirectory"
    case errorStoreInvalidImage = "error.storeInvalidImage"
    case errorStoreJPEG = "error.storeJPEG"
    case errorStoreWrite = "error.storeWrite"
    case errorStoreList = "error.storeList"
    case errorVisionInvalidResponse = "error.visionInvalidResponse"
    case errorVisionUnavailable = "error.visionUnavailable"
    case errorVisionTimeout = "error.visionTimeout"
    case errorVisionUnauthorized = "error.visionUnauthorized"
    case errorVisionNetwork = "error.visionNetwork"
    case errorVisionRateLimited = "error.visionRateLimited"
    case errorVisionRejected = "error.visionRejected"
    case errorAudioUnavailable = "error.audioUnavailable"
    case errorVoiceUnavailable = "error.voiceUnavailable"
    case errorInvalidVisionMode = "error.invalidVisionMode"
    case errorInvalidVisionURL = "error.invalidVisionURL"
    case errorMissingVisionToken = "error.missingVisionToken"
    case errorVisionConfiguration = "error.visionConfiguration"
    case errorEmbeddingIncompatible = "error.embeddingIncompatible"
    case errorEmbeddingInvalid = "error.embeddingInvalid"
    case errorPlaceMissingLabel = "error.placeMissingLabel"
    case errorPlaceSave = "error.placeSave"
    case errorPlaceUpdate = "error.placeUpdate"
    case errorPlaceDelete = "error.placeDelete"
    case errorNoRememberedPlaces = "error.noRememberedPlaces"
    case errorPlaceMigration = "error.placeMigration"
    case errorSpeechPermission = "error.speechPermission"
    case errorMicrophonePermission = "error.microphonePermission"
    case errorSpeechRecognizerUnavailable =
        "error.speechRecognizerUnavailable"
    case errorOnDeviceSpeechUnavailable =
        "error.onDeviceSpeechUnavailable"
    case errorSpeechAudioInput = "error.speechAudioInput"
    case errorSpeechRecognition = "error.speechRecognition"
    case errorSpeechNoInput = "error.speechNoInput"
    case errorSpeechAlreadyListening = "error.speechAlreadyListening"
    case errorVoiceCommandUnrecognized =
        "error.voiceCommandUnrecognized"
    case errorVoiceCommandRequiresNavigating =
        "error.voiceCommandRequiresNavigating"
    case errorBLEConnection = "error.ble.connection"
    case errorBLEService = "error.ble.service"
    case errorBLECharacteristics = "error.ble.characteristics"
    case errorBLETelemetry = "error.ble.telemetry"
    case errorBLEMode = "error.ble.mode"
    case errorEvaluationDirectory = "error.evaluation.directory"
    case errorEvaluationRead = "error.evaluation.read"
    case errorEvaluationWrite = "error.evaluation.write"
    case errorEvaluationExport = "error.evaluation.export"
    case errorEvaluationRecognition =
        "error.evaluation.recognition"
    case errorEvaluationDistance = "error.evaluation.distance"

    var tableName: String? {
        if rawValue.hasPrefix("evaluation.")
            || rawValue.hasPrefix("error.evaluation.") {
            return "Evaluation"
        }
        return switch self {
        case .actionWhereAmI,
             .actionCheckingPlace,
             .actionRememberPlace,
             .actionCapturePlaceView,
             .actionAddViews,
             .actionRename,
             .actionClose,
             .actionDone,
             .actionCancel,
             .actionSave,
             .actionOK,
             .hintWhereAmI,
             .hintRememberPlace,
             .hintRememberedPlaces,
             .hintCapturePlaceView,
             .placeResultAccessibility,
             .placeMatched,
             .placeUncertain,
             .placesTitle,
             .placesTitleCount,
             .placesEmptyTitle,
             .placesEmptyDescription,
             .placeNameLabel,
             .placeNamePlaceholder,
             .placeViewsSection,
             .placeViewsCount,
             .placeViewsProgress,
             .placeRememberTitle,
             .placeAddViewsTitle,
             .placeRenameTitle,
             .placeUpdateFailedTitle,
             .placeInstructionFirst,
             .placeInstructionLeft,
             .placeInstructionRight,
             .placeInstructionReverse,
             .placeInstructionLighting,
             .placeInstructionEnough,
             .placeScanInstructions,
             .statusCheckingLocation,
             .statusPlaceRecognitionComplete,
             .statusPlaceScanComplete,
             .statusCapturingPlaceView,
             .statusSavedPlaceView,
             .statusUpdatingPlaceEmbeddings,
             .errorEmbeddingIncompatible,
             .errorEmbeddingInvalid,
             .errorPlaceMissingLabel,
             .errorPlaceSave,
             .errorPlaceUpdate,
             .errorPlaceDelete,
             .errorNoRememberedPlaces,
             .errorPlaceMigration:
            "Places"
        default:
            nil
        }
    }
}

struct AppMessage: Equatable, Sendable {
    let key: AppStringKey
    let arguments: [String]

    init(_ key: AppStringKey, argument: String? = nil) {
        self.key = key
        arguments = argument.map { [$0] } ?? []
    }

    init(_ key: AppStringKey, arguments: [String]) {
        self.key = key
        self.arguments = arguments
    }

    func localized(in language: SupportedLanguage) -> String {
        language.text(key, arguments: arguments)
    }
}

protocol AppMessageProviding: Error {
    var appMessage: AppMessage { get }
}

extension SupportedLanguage {
    func text(
        _ key: AppStringKey,
        argument: String? = nil
    ) -> String {
        text(key, arguments: argument.map { [$0] } ?? [])
    }

    func text(
        _ key: AppStringKey,
        arguments: [String]
    ) -> String {
        let bundle: Bundle
        if let path = Bundle.faroResources.path(
            forResource: localizationResource,
            ofType: "lproj"
        ),
        let localizedBundle = Bundle(path: path) {
            bundle = localizedBundle
        } else {
            bundle = .faroResources
        }

        let value = String(
            localized: String.LocalizationValue(key.rawValue),
            table: key.tableName,
            bundle: bundle,
            locale: locale
        )
        guard !arguments.isEmpty else {
            return value
        }
        return String(
            format: value,
            locale: locale,
            arguments: arguments.map { $0 as CVarArg }
        )
    }
}

enum AppErrorMessage {
    static func message(
        for error: any Error,
        language: SupportedLanguage
    ) -> AppMessage {
        if let provider = error as? any AppMessageProviding {
            return provider.appMessage
        }
        return AppMessage(.errorGenericAction)
    }
}
