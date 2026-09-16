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
    case voiceTitle = "voice.title"
    case voiceInstructions = "voice.instructions"
    case voiceTranscript = "voice.transcript"
    case voiceCommandDescribe = "voice.command.describe"
    case voiceCommandWhereAmI = "voice.command.whereAmI"
    case voiceCommandRememberPlace = "voice.command.rememberPlace"
    case voiceCommandWhatIsAhead = "voice.command.whatIsAhead"
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
    case statusReady = "status.ready"
    case statusCapturingImage = "status.capturingImage"
    case statusImageCapturedSaved = "status.imageCapturedSaved"
    case statusCapturingScene = "status.capturingScene"
    case statusDescribingScene = "status.describingScene"
    case statusDescriptionReady = "status.descriptionReady"
    case statusCheckingLocation = "status.checkingLocation"
    case statusPlaceRecognitionComplete = "status.placeRecognitionComplete"
    case statusCapturingPlaceView = "status.capturingPlaceView"
    case statusSavedPlaceView = "status.savedPlaceView"
    case statusUpdatingPlaceEmbeddings = "status.updatingPlaceEmbeddings"
    case statusVoiceReady = "status.voiceReady"
    case statusVoicePreparing = "status.voicePreparing"
    case statusVoiceListening = "status.voiceListening"
    case statusVoiceProcessing = "status.voiceProcessing"
    case statusVoiceRecognized = "status.voiceRecognized"
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

    var tableName: String? {
        switch self {
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
             .statusCheckingLocation,
             .statusPlaceRecognitionComplete,
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
