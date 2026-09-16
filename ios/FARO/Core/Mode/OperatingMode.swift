import Observation

enum OperatingMode: Equatable, Sendable {
    case inactive
    case navigating

    var displayKey: AppStringKey {
        switch self {
        case .inactive:
            .modeInactive
        case .navigating:
            .modeNavigating
        }
    }

    var currentModeKey: AppStringKey {
        switch self {
        case .inactive:
            .modeCurrentInactive
        case .navigating:
            .modeCurrentNavigating
        }
    }

    var transitionAnnouncementKey: AppStringKey {
        switch self {
        case .inactive:
            .modeInactiveEnabled
        case .navigating:
            .modeNavigatingEnabled
        }
    }

    var toggleActionKey: AppStringKey {
        switch self {
        case .inactive:
            .actionStartNavigating
        case .navigating:
            .actionStopNavigating
        }
    }

    var toggleHintKey: AppStringKey {
        switch self {
        case .inactive:
            .hintStartNavigating
        case .navigating:
            .hintStopNavigating
        }
    }

    var confirmationTone: ModeConfirmationTone {
        switch self {
        case .inactive:
            .navigationStopped
        case .navigating:
            .navigationStarted
        }
    }
}

enum ModeConfirmationTone: UInt32, Equatable, Sendable {
    case navigationStarted = 1113
    case navigationStopped = 1114
}

@MainActor
protocol ModeFeedbackProviding: AnyObject {
    func confirmTransition(
        to mode: OperatingMode,
        language: SupportedLanguage
    )
}

struct NavigationOutputGate: Sendable {
    func allowsOutput(in mode: OperatingMode) -> Bool {
        mode == .navigating
    }

    @discardableResult
    func perform(
        in mode: OperatingMode,
        output: () -> Void
    ) -> Bool {
        guard allowsOutput(in: mode) else {
            return false
        }
        output()
        return true
    }
}

@MainActor
@Observable
final class OperatingModeController {
    private let feedback: any ModeFeedbackProviding
    private let outputGate: NavigationOutputGate

    private(set) var currentMode: OperatingMode = .inactive

    init(
        feedback: (any ModeFeedbackProviding)? = nil,
        outputGate: NavigationOutputGate = NavigationOutputGate()
    ) {
        self.feedback = feedback ?? ModeFeedback()
        self.outputGate = outputGate
    }

    var navigationOutputEnabled: Bool {
        outputGate.allowsOutput(in: currentMode)
    }

    func toggle(language: SupportedLanguage) {
        let nextMode: OperatingMode = currentMode == .inactive
            ? .navigating
            : .inactive
        transition(to: nextMode, language: language)
    }

    func transition(
        to mode: OperatingMode,
        language: SupportedLanguage
    ) {
        guard mode != currentMode else {
            return
        }
        currentMode = mode
        feedback.confirmTransition(to: mode, language: language)
    }

    @discardableResult
    func performNavigationOutput(_ output: () -> Void) -> Bool {
        outputGate.perform(in: currentMode, output: output)
    }
}
