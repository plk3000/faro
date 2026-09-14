import Foundation

private final class FAROResourceBundleMarker {}

extension Bundle {
    static let faroResources = Bundle(for: FAROResourceBundleMarker.self)
}

enum AppStringKey: String, Sendable {
    case languageSelector = "language.selector"
    case languageFollowSystem = "language.followSystem"
    case languageEnglishUS = "language.englishUS"
    case languageSpanishMexico = "language.spanishMexico"
    case actionDescribe = "action.describe"
    case actionDescribing = "action.describing"
    case actionCapture = "action.capture"
    case actionCapturing = "action.capturing"
    case hintDescribe = "hint.describe"
    case hintCapture = "hint.capture"
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
    case modeCurrentInactive = "mode.currentInactive"
    case savedEmptyTitle = "saved.empty.title"
    case savedEmptyDescription = "saved.empty.description"
    case savedCaptureAccessibility = "saved.captureAccessibility"
    case savedTitle = "saved.title"
    case statusReady = "status.ready"
    case statusCapturingImage = "status.capturingImage"
    case statusImageCapturedSaved = "status.imageCapturedSaved"
    case statusCapturingScene = "status.capturingScene"
    case statusDescribingScene = "status.describingScene"
    case statusDescriptionReady = "status.descriptionReady"
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
}

struct AppMessage: Equatable, Sendable {
    let key: AppStringKey
    let argument: String?

    init(_ key: AppStringKey, argument: String? = nil) {
        self.key = key
        self.argument = argument
    }

    func localized(in language: SupportedLanguage) -> String {
        language.text(key, argument: argument)
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
            bundle: bundle,
            locale: locale
        )
        guard let argument else {
            return value
        }
        return String(
            format: value,
            locale: locale,
            arguments: [argument]
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
