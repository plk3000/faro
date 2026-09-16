import Testing
@testable import FARO

struct SpeechEndpointDetectorTests {
    private let configuration = SpeechEndpointConfiguration(
        pollInterval: 0.1,
        initialGracePeriod: 0.3,
        maximumDuration: 1,
        speechActivationLevel: -30,
        silenceLevel: -40,
        requiredSilenceDuration: 0.3
    )

    @Test
    func stopsAfterSpeechFollowedBySilence() {
        var detector = SpeechEndpointDetector(
            configuration: configuration
        )

        let initialSilence = detector.observe(averagePower: -60)
        let speech = detector.observe(averagePower: -20)
        let firstSilence = detector.observe(averagePower: -45)
        let secondSilence = detector.observe(averagePower: -45)
        let endpoint = detector.observe(averagePower: -45)

        #expect(!initialSilence)
        #expect(!speech)
        #expect(!firstSilence)
        #expect(!secondSilence)
        #expect(endpoint)
        #expect(detector.hasDetectedSpeech)
    }

    @Test
    func ignoresSilenceUntilSpeechIsDetected() {
        var detector = SpeechEndpointDetector(
            configuration: configuration
        )

        for _ in 0..<9 {
            let endpoint = detector.observe(averagePower: -60)
            #expect(!endpoint)
        }
        let endpoint = detector.observe(averagePower: -60)
        #expect(endpoint)
        #expect(!detector.hasDetectedSpeech)
    }

    @Test
    func noiseInsideTheHysteresisBandResetsSilence() {
        var detector = SpeechEndpointDetector(
            configuration: configuration
        )

        let speech = detector.observe(averagePower: -20)
        let firstSilence = detector.observe(averagePower: -45)
        let noise = detector.observe(averagePower: -35)
        let restartedSilence = detector.observe(averagePower: -45)
        let secondSilence = detector.observe(averagePower: -45)
        let endpoint = detector.observe(averagePower: -45)

        #expect(!speech)
        #expect(!firstSilence)
        #expect(!noise)
        #expect(!restartedSilence)
        #expect(!secondSilence)
        #expect(endpoint)
    }
}
