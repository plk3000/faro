import Foundation

enum RecognitionEvaluationAngle:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case enrollmentLike
    case leftOblique
    case rightOblique
    case reverse
    case other

    var id: String { rawValue }

    var displayKey: AppStringKey {
        switch self {
        case .enrollmentLike:
            .evaluationAngleEnrollmentLike
        case .leftOblique:
            .evaluationAngleLeftOblique
        case .rightOblique:
            .evaluationAngleRightOblique
        case .reverse:
            .evaluationAngleReverse
        case .other:
            .evaluationAngleOther
        }
    }
}

enum RecognitionEvaluationLighting:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case similar
    case brighter
    case dimmer
    case artificial
    case mixed

    var id: String { rawValue }

    var displayKey: AppStringKey {
        switch self {
        case .similar:
            .evaluationLightingSimilar
        case .brighter:
            .evaluationLightingBrighter
        case .dimmer:
            .evaluationLightingDimmer
        case .artificial:
            .evaluationLightingArtificial
        case .mixed:
            .evaluationLightingMixed
        }
    }
}

enum RecognitionEvaluationOutcome: String, Codable, Sendable {
    case correctMatch
    case correctRejection
    case uncertainKnownPlace
    case falseConfident

    var displayKey: AppStringKey {
        switch self {
        case .correctMatch:
            .evaluationOutcomeCorrectMatch
        case .correctRejection:
            .evaluationOutcomeCorrectRejection
        case .uncertainKnownPlace:
            .evaluationOutcomeUncertain
        case .falseConfident:
            .evaluationOutcomeFalseConfident
        }
    }
}

struct RecognitionEvaluationTrial:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: UUID
    let recordedAt: Date
    let expectedPlaceID: UUID?
    let expectedPlaceLabel: String?
    let predictedPlaceID: UUID?
    let predictedPlaceLabel: String?
    let nearestPlaceID: UUID?
    let nearestPlaceLabel: String?
    let angle: RecognitionEvaluationAngle
    let lighting: RecognitionEvaluationLighting
    let language: SupportedLanguage
    let outcome: RecognitionEvaluationOutcome
    let latencyMilliseconds: Int
    let modelIdentifier: String
    let nearestDistance: Double?
    let nearestCompetingDistance: Double?
    let maximumDistance: Double
    let minimumSeparation: Double
    let candidateCount: Int
    let snapshotCount: Int

    init(
        id: UUID = UUID(),
        recordedAt: Date = .now,
        expectedPlaceID: UUID?,
        expectedPlaceLabel: String?,
        angle: RecognitionEvaluationAngle,
        lighting: RecognitionEvaluationLighting,
        language: SupportedLanguage,
        attempt: PlaceRecognitionAttempt
    ) {
        let predictedPlaceID: UUID?
        let predictedPlaceLabel: String?
        switch attempt.evaluation.result {
        case let .matched(match):
            predictedPlaceID = match.placeID
            predictedPlaceLabel = match.label
        case .uncertain:
            predictedPlaceID = nil
            predictedPlaceLabel = nil
        }

        let outcome: RecognitionEvaluationOutcome
        if let expectedPlaceID {
            if predictedPlaceID == expectedPlaceID {
                outcome = .correctMatch
            } else if predictedPlaceID == nil {
                outcome = .uncertainKnownPlace
            } else {
                outcome = .falseConfident
            }
        } else {
            outcome = predictedPlaceID == nil
                ? .correctRejection
                : .falseConfident
        }

        self.id = id
        self.recordedAt = recordedAt
        self.expectedPlaceID = expectedPlaceID
        self.expectedPlaceLabel = expectedPlaceLabel
        self.predictedPlaceID = predictedPlaceID
        self.predictedPlaceLabel = predictedPlaceLabel
        nearestPlaceID = attempt.evaluation.nearestPlaceID
        nearestPlaceLabel = attempt.evaluation.nearestLabel
        self.angle = angle
        self.lighting = lighting
        self.language = language
        self.outcome = outcome
        latencyMilliseconds = attempt.latencyMilliseconds
        modelIdentifier = attempt.modelIdentifier
        nearestDistance = attempt.evaluation.nearestDistance
        nearestCompetingDistance =
            attempt.evaluation.nearestCompetingDistance
        maximumDistance = attempt.evaluation.policy.maximumDistance
        minimumSeparation = attempt.evaluation.policy.minimumSeparation
        candidateCount = attempt.evaluation.candidateCount
        snapshotCount = attempt.evaluation.snapshotCount
    }
}

enum FieldObservationCategory:
    String,
    CaseIterable,
    Codable,
    Identifiable,
    Sendable
{
    case languageBehavior
    case narrationPacing
    case proximityAlert
    case wakeBehavior
    case general

    var id: String { rawValue }

    var displayKey: AppStringKey {
        switch self {
        case .languageBehavior:
            .evaluationCategoryLanguage
        case .narrationPacing:
            .evaluationCategoryNarration
        case .proximityAlert:
            .evaluationCategoryProximity
        case .wakeBehavior:
            .evaluationCategoryWake
        case .general:
            .evaluationCategoryGeneral
        }
    }
}

struct FieldEvaluationObservation:
    Codable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: UUID
    let recordedAt: Date
    let category: FieldObservationCategory
    let language: SupportedLanguage
    let usefulnessRating: Int
    let annoyanceRating: Int
    let notes: String
    let measuredDistanceCentimeters: Double?
    let expectedWarningState: ObstacleWarningState?
    let telemetryDistanceMillimeters: UInt16?
    let telemetryWarningState: ObstacleWarningState?
    let telemetryOperatingMode: OperatingMode?
    let alertHeard: Bool?

    init(
        id: UUID = UUID(),
        recordedAt: Date = .now,
        category: FieldObservationCategory,
        language: SupportedLanguage,
        usefulnessRating: Int,
        annoyanceRating: Int,
        notes: String,
        measuredDistanceCentimeters: Double? = nil,
        telemetryDistanceMillimeters: UInt16? = nil,
        telemetryWarningState: ObstacleWarningState? = nil,
        telemetryOperatingMode: OperatingMode? = nil,
        alertHeard: Bool? = nil
    ) {
        precondition((1...5).contains(usefulnessRating))
        precondition((1...5).contains(annoyanceRating))
        self.id = id
        self.recordedAt = recordedAt
        self.category = category
        self.language = language
        self.usefulnessRating = usefulnessRating
        self.annoyanceRating = annoyanceRating
        self.notes = notes
        self.measuredDistanceCentimeters = measuredDistanceCentimeters
        expectedWarningState = Self.expectedWarningState(
            measuredDistanceCentimeters: measuredDistanceCentimeters
        )
        self.telemetryDistanceMillimeters = telemetryDistanceMillimeters
        self.telemetryWarningState = telemetryWarningState
        self.telemetryOperatingMode = telemetryOperatingMode
        self.alertHeard = alertHeard
    }

    private static func expectedWarningState(
        measuredDistanceCentimeters: Double?
    ) -> ObstacleWarningState? {
        guard let measuredDistanceCentimeters else {
            return nil
        }
        let millimeters = measuredDistanceCentimeters * 10
        if millimeters
            >= Double(ObstacleDistanceBands.clearMinimumMillimeters) {
            return .clear
        }
        if millimeters
            >= Double(ObstacleDistanceBands.slowMinimumMillimeters) {
            return .slow
        }
        if millimeters
            >= Double(ObstacleDistanceBands.fastMinimumMillimeters) {
            return .fast
        }
        return .urgent
    }
}

struct EvaluationDataset: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1
    static let empty = EvaluationDataset(
        schemaVersion: currentSchemaVersion,
        recognitionTrials: [],
        fieldObservations: []
    )

    let schemaVersion: Int
    var recognitionTrials: [RecognitionEvaluationTrial]
    var fieldObservations: [FieldEvaluationObservation]
}

struct EvaluationMetricAggregate: Codable, Equatable, Sendable {
    let trialCount: Int
    let knownPlaceTrialCount: Int
    let unknownPlaceTrialCount: Int
    let correctMatchCount: Int
    let correctRejectionCount: Int
    let uncertainKnownPlaceCount: Int
    let falseConfidentCount: Int
    let accuracy: Double?
    let knownPlaceRecall: Double?
    let unknownPlaceRejectionRate: Double?
    let falseConfidentRate: Double?
    let averageLatencyMilliseconds: Double?
    let percentile95LatencyMilliseconds: Int?

    init(trials: [RecognitionEvaluationTrial]) {
        trialCount = trials.count
        let knownTrials = trials.filter { $0.expectedPlaceID != nil }
        let unknownTrials = trials.filter { $0.expectedPlaceID == nil }
        knownPlaceTrialCount = knownTrials.count
        unknownPlaceTrialCount = unknownTrials.count
        correctMatchCount = trials.count {
            $0.outcome == .correctMatch
        }
        correctRejectionCount = trials.count {
            $0.outcome == .correctRejection
        }
        uncertainKnownPlaceCount = trials.count {
            $0.outcome == .uncertainKnownPlace
        }
        falseConfidentCount = trials.count {
            $0.outcome == .falseConfident
        }

        let correctCount = correctMatchCount + correctRejectionCount
        accuracy = Self.ratio(correctCount, trialCount)
        knownPlaceRecall = Self.ratio(
            correctMatchCount,
            knownPlaceTrialCount
        )
        unknownPlaceRejectionRate = Self.ratio(
            correctRejectionCount,
            unknownPlaceTrialCount
        )
        falseConfidentRate = Self.ratio(
            falseConfidentCount,
            trialCount
        )

        let latencies = trials
            .map(\.latencyMilliseconds)
            .sorted()
        if latencies.isEmpty {
            averageLatencyMilliseconds = nil
            percentile95LatencyMilliseconds = nil
        } else {
            averageLatencyMilliseconds =
                Double(latencies.reduce(0, +)) / Double(latencies.count)
            let percentileIndex = max(
                0,
                Int(ceil(Double(latencies.count) * 0.95)) - 1
            )
            percentile95LatencyMilliseconds =
                latencies[percentileIndex]
        }
    }

    private static func ratio(
        _ numerator: Int,
        _ denominator: Int
    ) -> Double? {
        guard denominator > 0 else {
            return nil
        }
        return Double(numerator) / Double(denominator)
    }
}

struct EvaluationMetricBreakdown: Codable, Equatable, Sendable {
    let value: String
    let metrics: EvaluationMetricAggregate
}

struct EvaluationSummary: Codable, Equatable, Sendable {
    let overall: EvaluationMetricAggregate
    let byAngle: [EvaluationMetricBreakdown]
    let byLighting: [EvaluationMetricBreakdown]
    let byLanguage: [EvaluationMetricBreakdown]
    let fieldObservationCount: Int

    init(dataset: EvaluationDataset) {
        let trials = dataset.recognitionTrials
        overall = EvaluationMetricAggregate(trials: trials)
        byAngle = RecognitionEvaluationAngle.allCases.map { angle in
            EvaluationMetricBreakdown(
                value: angle.rawValue,
                metrics: EvaluationMetricAggregate(
                    trials: trials.filter { $0.angle == angle }
                )
            )
        }
        byLighting = RecognitionEvaluationLighting.allCases.map { lighting in
            EvaluationMetricBreakdown(
                value: lighting.rawValue,
                metrics: EvaluationMetricAggregate(
                    trials: trials.filter { $0.lighting == lighting }
                )
            )
        }
        byLanguage = SupportedLanguage.allCases.map { language in
            EvaluationMetricBreakdown(
                value: language.rawValue,
                metrics: EvaluationMetricAggregate(
                    trials: trials.filter { $0.language == language }
                )
            )
        }
        fieldObservationCount = dataset.fieldObservations.count
    }
}

struct EvaluationConfigurationSnapshot:
    Codable,
    Equatable,
    Sendable
{
    let speechRate: Float
    let speechPreUtteranceDelaySeconds: Double
    let speechPhraseDelaySeconds: Double
    let proximityClearMinimumMillimeters: UInt16
    let proximitySlowMinimumMillimeters: UInt16
    let proximityFastMinimumMillimeters: UInt16

    static let current = EvaluationConfigurationSnapshot(
        speechRate: SpeechOutputConfiguration.accessibleDefault.rate,
        speechPreUtteranceDelaySeconds:
            SpeechOutputConfiguration
            .accessibleDefault
            .preUtteranceDelay,
        speechPhraseDelaySeconds:
            SpeechOutputConfiguration
            .accessibleDefault
            .phraseDelay,
        proximityClearMinimumMillimeters:
            ObstacleDistanceBands.clearMinimumMillimeters,
        proximitySlowMinimumMillimeters:
            ObstacleDistanceBands.slowMinimumMillimeters,
        proximityFastMinimumMillimeters:
            ObstacleDistanceBands.fastMinimumMillimeters
    )
}

struct EvaluationExport: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let generatedAt: Date
    let latencyScope: String
    let configuration: EvaluationConfigurationSnapshot
    let summary: EvaluationSummary
    let recognitionTrials: [RecognitionEvaluationTrial]
    let fieldObservations: [FieldEvaluationObservation]

    init(
        dataset: EvaluationDataset,
        generatedAt: Date = .now
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        latencyScope = "camera_capture_through_embedding_and_match"
        configuration = .current
        summary = EvaluationSummary(dataset: dataset)
        recognitionTrials = dataset.recognitionTrials
        fieldObservations = dataset.fieldObservations
    }
}
