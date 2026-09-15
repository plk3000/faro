import SwiftData
import SwiftUI

struct RememberPlaceView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let captureModel: CaptureViewModel
    let existingPlace: Place?
    let language: SupportedLanguage

    @State private var label: String
    @State private var enrolledPlace: Place?

    private let targetViewCount = 5

    init(
        captureModel: CaptureViewModel,
        existingPlace: Place? = nil,
        language: SupportedLanguage
    ) {
        self.captureModel = captureModel
        self.existingPlace = existingPlace
        self.language = language
        _label = State(initialValue: existingPlace?.label ?? "")
        _enrolledPlace = State(initialValue: existingPlace)
    }

    var body: some View {
        Form {
            Section(language.text(.placeNameLabel)) {
                TextField(
                    language.text(.placeNamePlaceholder),
                    text: $label
                )
                .textInputAutocapitalization(.words)
                .disabled(
                    enrolledPlace != nil || captureModel.isEnrolling
                )
                .accessibilityLabel(language.text(.placeNameLabel))
            }

            Section(language.text(.placeViewsSection)) {
                Text(instruction)

                ProgressView(
                    value: Double(viewCount),
                    total: Double(targetViewCount)
                ) {
                    Text(
                        language.text(
                            .placeViewsProgress,
                            arguments: [
                                String(viewCount),
                                String(targetViewCount)
                            ]
                        )
                    )
                }

                Button {
                    Task {
                        let place = await captureModel.capturePlaceView(
                            label: label,
                            into: enrolledPlace,
                            modelContext: modelContext,
                            language: language
                        )
                        enrolledPlace = place
                        if let place {
                            label = place.label
                        }
                    }
                } label: {
                    Label(
                        language.text(
                            captureModel.isEnrolling
                                ? .actionCapturing
                                : .actionCapturePlaceView
                        ),
                        systemImage: "camera.shutter.button"
                    )
                    .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    captureModel.isEnrolling
                        || label.trimmingCharacters(
                            in: .whitespacesAndNewlines
                        ).isEmpty
                )
                .accessibilityHint(language.text(.hintCapturePlaceView))
            }

            if let error = captureModel.errorText(language: language) {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityLabel(
                            language.text(
                                .statusAccessibility,
                                argument: error
                            )
                        )
                }
            }
        }
        .navigationTitle(
            language.text(
                existingPlace == nil
                    ? .placeRememberTitle
                    : .placeAddViewsTitle
            )
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(language.text(.actionClose)) {
                    dismiss()
                }
            }
            if viewCount >= 3 {
                ToolbarItem(placement: .confirmationAction) {
                    Button(language.text(.actionDone)) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            captureModel.preparePlaceMemoryLocation()
        }
        .environment(\.locale, language.locale)
    }

    private var viewCount: Int {
        enrolledPlace?.snapshots.count ?? 0
    }

    private var instruction: String {
        let key: AppStringKey
        switch viewCount {
        case 0:
            key = .placeInstructionFirst
        case 1:
            key = .placeInstructionLeft
        case 2:
            key = .placeInstructionRight
        case 3:
            key = .placeInstructionReverse
        case 4:
            key = .placeInstructionLighting
        default:
            key = .placeInstructionEnough
        }
        return language.text(key)
    }
}
