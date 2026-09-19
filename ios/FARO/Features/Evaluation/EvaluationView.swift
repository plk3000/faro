import SwiftData
import SwiftUI

struct EvaluationView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Place.createdAt, order: .reverse)
    private var places: [Place]

    let captureModel: CaptureViewModel
    let obstacleModuleModel: ObstacleModuleViewModel
    let language: SupportedLanguage

    @State private var model = EvaluationViewModel()
    @State private var expectedPlaceID: UUID?
    @State private var angle =
        RecognitionEvaluationAngle.enrollmentLike
    @State private var lighting =
        RecognitionEvaluationLighting.similar
    @State private var observationCategory =
        FieldObservationCategory.general
    @State private var usefulnessRating = 3
    @State private var annoyanceRating = 3
    @State private var notes = ""
    @State private var measuredDistanceCentimeters: Double?
    @State private var alertHeard = false
    @State private var isConfirmingClear = false
    @State private var recognitionTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section {
                Text(language.text(.evaluationInstructions))
                    .foregroundStyle(.secondary)
            }

            summarySection
            recognitionSection
            fieldObservationSection
            exportSection

            if let error = model.errorText(language: language) {
                Section {
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(language.text(.evaluationTitle))
        .task {
            await model.load()
        }
        .onDisappear {
            recognitionTask?.cancel()
            recognitionTask = nil
        }
        .confirmationDialog(
            language.text(.evaluationClearTitle),
            isPresented: $isConfirmingClear,
            titleVisibility: .visible
        ) {
            Button(
                language.text(.evaluationClearData),
                role: .destructive
            ) {
                Task {
                    await model.clearAll()
                }
            }
            Button(language.text(.actionCancel), role: .cancel) {}
        } message: {
            Text(language.text(.evaluationClearMessage))
        }
    }

    private var summarySection: some View {
        Section(language.text(.evaluationSummarySection)) {
            let summary = model.summary
            if summary.overall.trialCount == 0 {
                Text(language.text(.evaluationNoTrials))
                    .foregroundStyle(.secondary)
            } else {
                metricRow(
                    label: language.text(.evaluationTrialCount),
                    value: summary.overall.trialCount.formatted(
                        .number.locale(language.locale)
                    )
                )
                metricRow(
                    label: language.text(.evaluationAccuracy),
                    value: formatPercent(summary.overall.accuracy)
                )
                metricRow(
                    label: language.text(.evaluationFalseConfident),
                    value: summary.overall.falseConfidentCount.formatted(
                        .number.locale(language.locale)
                    )
                )
                metricRow(
                    label: language.text(.evaluationAverageLatency),
                    value: formatLatency(
                        summary.overall.averageLatencyMilliseconds
                    )
                )
            }
            metricRow(
                label: language.text(.evaluationObservationCount),
                value: summary.fieldObservationCount.formatted(
                    .number.locale(language.locale)
                )
            )
        }
    }

    private var recognitionSection: some View {
        Section(language.text(.evaluationRecognitionSection)) {
            if places.isEmpty {
                Text(language.text(.errorNoRememberedPlaces))
                    .foregroundStyle(.secondary)
            } else {
                Picker(
                    language.text(.evaluationExpectedPlace),
                    selection: $expectedPlaceID
                ) {
                    Text(language.text(.evaluationUnknownPlace))
                        .tag(nil as UUID?)
                    ForEach(places) { place in
                        Text(place.label)
                            .tag(place.id as UUID?)
                    }
                }

                Picker(
                    language.text(.evaluationAngle),
                    selection: $angle
                ) {
                    ForEach(RecognitionEvaluationAngle.allCases) { value in
                        Text(language.text(value.displayKey))
                            .tag(value)
                    }
                }

                Picker(
                    language.text(.evaluationLighting),
                    selection: $lighting
                ) {
                    ForEach(RecognitionEvaluationLighting.allCases) { value in
                        Text(language.text(value.displayKey))
                            .tag(value)
                    }
                }

                Button {
                    runRecognitionTrial()
                } label: {
                    Label(
                        language.text(
                            model.isRunningRecognition
                                ? .evaluationRunningTrial
                                : .evaluationRunTrial
                        ),
                        systemImage: "camera.metering.matrix"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(model.isRunningRecognition || captureIsBusy)

                if let trial = model.latestTrial {
                    LabeledContent(
                        language.text(.evaluationLatestResult),
                        value: resultText(for: trial)
                    )
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var fieldObservationSection: some View {
        Section(language.text(.evaluationFieldSection)) {
            Picker(
                language.text(.evaluationCategory),
                selection: $observationCategory
            ) {
                ForEach(FieldObservationCategory.allCases) { category in
                    Text(language.text(category.displayKey))
                        .tag(category)
                }
            }

            Stepper(
                language.text(
                    .evaluationUsefulnessRating,
                    argument: usefulnessRating.formatted(
                        .number.locale(language.locale)
                    )
                ),
                value: $usefulnessRating,
                in: 1...5
            )
            Stepper(
                language.text(
                    .evaluationAnnoyanceRating,
                    argument: annoyanceRating.formatted(
                        .number.locale(language.locale)
                    )
                ),
                value: $annoyanceRating,
                in: 1...5
            )

            if observationCategory == .proximityAlert {
                TextField(
                    language.text(.evaluationMeasuredDistance),
                    value: $measuredDistanceCentimeters,
                    format: .number
                        .precision(.fractionLength(0...1))
                        .locale(language.locale)
                )
                .keyboardType(.decimalPad)

                Toggle(
                    language.text(.evaluationAlertHeard),
                    isOn: $alertHeard
                )

                Text(telemetrySnapshotText)
                    .foregroundStyle(.secondary)
            }

            TextField(
                language.text(.evaluationNotesPlaceholder),
                text: $notes,
                axis: .vertical
            )
            .lineLimit(3...6)

            Button {
                saveObservation()
            } label: {
                Label(
                    language.text(
                        model.isSavingObservation
                            ? .evaluationSavingObservation
                            : .evaluationSaveObservation
                    ),
                    systemImage: "square.and.pencil"
                )
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(model.isSavingObservation)
        }
    }

    private var exportSection: some View {
        Section(language.text(.evaluationExportSection)) {
            if let exportURL = model.exportURL {
                ShareLink(item: exportURL) {
                    Label(
                        language.text(.evaluationShareExport),
                        systemImage: "square.and.arrow.up"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
            }

            Button(role: .destructive) {
                isConfirmingClear = true
            } label: {
                Label(
                    language.text(.evaluationClearData),
                    systemImage: "trash"
                )
                .frame(maxWidth: .infinity, minHeight: 44)
            }
            .disabled(!model.hasRecords || model.isClearing)

            Text(language.text(.evaluationPrivacyNote))
                .foregroundStyle(.secondary)
        }
    }

    private var selectedExpectedPlace: Place? {
        guard let expectedPlaceID else {
            return nil
        }
        return places.first { $0.id == expectedPlaceID }
    }

    private var captureIsBusy: Bool {
        captureModel.isCapturing
            || captureModel.isDescribing
            || captureModel.isRecognizing
            || captureModel.isEnrolling
            || captureModel.isPreparingPlaceMemory
    }

    private var telemetrySnapshotText: String {
        guard obstacleModuleModel.latestTelemetry != nil else {
            return language.text(.evaluationTelemetryUnavailable)
        }
        return language.text(
            .evaluationTelemetrySnapshot,
            arguments: [
                obstacleModuleModel.distanceText(language: language),
                obstacleModuleModel.warningText(language: language),
                obstacleModuleModel.confirmedModeText(language: language)
            ]
        )
    }

    private func runRecognitionTrial() {
        recognitionTask?.cancel()
        recognitionTask = Task {
            await model.runRecognitionTrial(
                expectedPlace: selectedExpectedPlace,
                angle: angle,
                lighting: lighting,
                language: language,
                places: places,
                modelContext: modelContext,
                captureModel: captureModel
            )
            recognitionTask = nil
        }
    }

    private func saveObservation() {
        let previousCount = model.dataset.fieldObservations.count
        Task {
            await model.saveObservation(
                category: observationCategory,
                language: language,
                usefulnessRating: usefulnessRating,
                annoyanceRating: annoyanceRating,
                notes: notes,
                measuredDistanceCentimeters:
                    measuredDistanceCentimeters,
                alertHeard: alertHeard,
                telemetry: obstacleModuleModel.latestTelemetry
            )
            if model.dataset.fieldObservations.count > previousCount {
                notes = ""
                measuredDistanceCentimeters = nil
                alertHeard = false
            }
        }
    }

    private func resultText(
        for trial: RecognitionEvaluationTrial
    ) -> String {
        switch trial.outcome {
        case .correctMatch:
            language.text(
                .evaluationOutcomeCorrectMatch,
                argument: trial.predictedPlaceLabel ?? ""
            )
        case .correctRejection:
            language.text(.evaluationOutcomeCorrectRejection)
        case .uncertainKnownPlace:
            language.text(.evaluationOutcomeUncertain)
        case .falseConfident:
            language.text(
                .evaluationOutcomeFalseConfident,
                argument: trial.predictedPlaceLabel
                    ?? language.text(.evaluationNoPrediction)
            )
        }
    }

    private func metricRow(
        label: String,
        value: String
    ) -> some View {
        LabeledContent(label, value: value)
            .accessibilityElement(children: .combine)
    }

    private func formatPercent(_ value: Double?) -> String {
        guard let value else {
            return language.text(.evaluationNotAvailable)
        }
        return value.formatted(
            .percent
                .precision(.fractionLength(1))
                .locale(language.locale)
        )
    }

    private func formatLatency(_ value: Double?) -> String {
        guard let value else {
            return language.text(.evaluationNotAvailable)
        }
        let formatted = value.formatted(
            .number
                .precision(.fractionLength(0))
                .locale(language.locale)
        )
        return language.text(
            .evaluationMilliseconds,
            argument: formatted
        )
    }
}
