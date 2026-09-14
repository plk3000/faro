import AVFoundation
import Testing
@testable import FARO

struct SpeechOutputConfigurationTests {
    @Test
    func accessibleDefaultIsSlowerThanSystemDefault() {
        let configuration = SpeechOutputConfiguration.accessibleDefault

        #expect(configuration.rate < AVSpeechUtteranceDefaultSpeechRate)
        #expect(configuration.preUtteranceDelay > 0)
    }
}
