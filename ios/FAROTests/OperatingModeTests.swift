import Testing
@testable import FARO

@MainActor
private final class RecordingModeFeedback: ModeFeedbackProviding {
    struct Event: Equatable {
        let mode: OperatingMode
        let language: SupportedLanguage
    }

    private(set) var events: [Event] = []

    func confirmTransition(
        to mode: OperatingMode,
        language: SupportedLanguage
    ) {
        events.append(Event(mode: mode, language: language))
    }
}

@MainActor
struct OperatingModeTests {
    @Test
    func everyControllerBootsInactive() {
        let first = OperatingModeController(
            feedback: RecordingModeFeedback()
        )
        let second = OperatingModeController(
            feedback: RecordingModeFeedback()
        )

        #expect(first.currentMode == .inactive)
        #expect(second.currentMode == .inactive)
        #expect(!first.navigationOutputEnabled)
    }

    @Test(arguments: SupportedLanguage.allCases)
    func transitionsAreConfirmedInTheSelectedLanguage(
        language: SupportedLanguage
    ) {
        let feedback = RecordingModeFeedback()
        let controller = OperatingModeController(feedback: feedback)

        controller.toggle(language: language)
        controller.toggle(language: language)

        #expect(
            feedback.events == [
                .init(mode: .navigating, language: language),
                .init(mode: .inactive, language: language)
            ]
        )
        #expect(
            language.text(.modeNavigatingEnabled)
                != AppStringKey.modeNavigatingEnabled.rawValue
        )
        #expect(
            language.text(.modeInactiveEnabled)
                != AppStringKey.modeInactiveEnabled.rawValue
        )
        #expect(
            OperatingMode.navigating.confirmationTone
                != OperatingMode.inactive.confirmationTone
        )
    }

    @Test
    func repeatedModeDoesNotProduceDuplicateConfirmation() {
        let feedback = RecordingModeFeedback()
        let controller = OperatingModeController(feedback: feedback)

        controller.transition(
            to: .inactive,
            language: .englishUS
        )

        #expect(feedback.events.isEmpty)
    }

    @Test
    func proximityOutputIsSilentWhileInactive() {
        let controller = OperatingModeController(
            feedback: RecordingModeFeedback()
        )
        var deliveredDistances: [Double] = []

        let deliveredWhileInactive = controller.performNavigationOutput {
            deliveredDistances.append(0.5)
        }
        controller.transition(
            to: .navigating,
            language: .englishUS
        )
        let deliveredWhileNavigating = controller.performNavigationOutput {
            deliveredDistances.append(0.5)
        }
        controller.transition(
            to: .inactive,
            language: .englishUS
        )
        let deliveredAfterStopping = controller.performNavigationOutput {
            deliveredDistances.append(0.25)
        }

        #expect(!deliveredWhileInactive)
        #expect(deliveredWhileNavigating)
        #expect(!deliveredAfterStopping)
        #expect(deliveredDistances == [0.5])
    }
}
