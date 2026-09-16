import Foundation

struct SpeechEndpointConfiguration: Equatable, Sendable {
    static let voiceCommand = SpeechEndpointConfiguration(
        pollInterval: 0.1,
        initialGracePeriod: 0.5,
        maximumDuration: 7,
        speechActivationLevel: -35,
        silenceLevel: -42,
        requiredSilenceDuration: 1
    )

    let pollInterval: TimeInterval
    let initialGracePeriod: TimeInterval
    let maximumDuration: TimeInterval
    let speechActivationLevel: Float
    let silenceLevel: Float
    let requiredSilenceDuration: TimeInterval
}

struct SpeechEndpointDetector: Sendable {
    let configuration: SpeechEndpointConfiguration

    private(set) var elapsed: TimeInterval = 0
    private(set) var hasDetectedSpeech = false
    private var sampleCount = 0
    private var silenceDuration: TimeInterval = 0

    init(
        configuration: SpeechEndpointConfiguration = .voiceCommand
    ) {
        self.configuration = configuration
    }

    mutating func observe(averagePower: Float) -> Bool {
        sampleCount += 1
        elapsed = Double(sampleCount) * configuration.pollInterval

        if averagePower >= configuration.speechActivationLevel {
            hasDetectedSpeech = true
            silenceDuration = 0
        } else if hasDetectedSpeech,
                  elapsed >= configuration.initialGracePeriod {
            if averagePower <= configuration.silenceLevel {
                silenceDuration += configuration.pollInterval
            } else {
                silenceDuration = 0
            }
        }

        return elapsed >= configuration.maximumDuration
            || (
                hasDetectedSpeech
                    && silenceDuration
                        >= configuration.requiredSilenceDuration
            )
    }
}
