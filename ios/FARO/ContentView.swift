import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Place.createdAt, order: .reverse)
    private var places: [Place]

    @AppStorage(LanguagePreference.storageKey)
    private var languagePreferenceRaw = LanguagePreference.followSystem.rawValue

    @State private var captureModel = CaptureViewModel()
    @State private var showingEnrollment = false

    private var languagePreference: LanguagePreference {
        LanguagePreference(rawValue: languagePreferenceRaw) ?? .followSystem
    }

    private var language: SupportedLanguage {
        languagePreference.resolve()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    languagePicker
                    modeCard
                    preview
                    describeButton
                    whereAmIButton
                    rememberPlaceButton
                    captureButton
                    status
                    descriptionCard
                    placeResultCard
                    placesLink
                    savedCapturesLink
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("FARO")
            .task {
                await captureModel.prepare(language: language)
            }
            .sheet(isPresented: $showingEnrollment) {
                NavigationStack {
                    RememberPlaceView(
                        captureModel: captureModel,
                        language: language
                    )
                }
            }
        }
        .environment(\.locale, language.locale)
    }

    private var isBusy: Bool {
        captureModel.isCapturing
            || captureModel.isDescribing
            || captureModel.isRecognizing
            || captureModel.isEnrolling
    }

    private var describeButton: some View {
        Button {
            Task {
                await captureModel.describe(language: language)
            }
        } label: {
            Label(
                language.text(
                    captureModel.isDescribing
                        ? .actionDescribing
                        : .actionDescribe
                ),
                systemImage: "text.bubble"
            )
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isBusy)
        .accessibilityLabel(
            language.text(
                captureModel.isDescribing
                    ? .actionDescribing
                    : .actionDescribe
            )
        )
        .accessibilityHint(language.text(.hintDescribe))
    }

    private var whereAmIButton: some View {
        Button {
            captureModel.preparePlaceMemoryLocation()
            Task {
                await captureModel.recognizePlace(
                    in: places,
                    modelContext: modelContext,
                    language: language
                )
            }
        } label: {
            Label(
                language.text(
                    captureModel.isRecognizing
                        ? .actionCheckingPlace
                        : .actionWhereAmI
                ),
                systemImage: "location.viewfinder"
            )
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(isBusy)
        .accessibilityHint(language.text(.hintWhereAmI))
    }

    private var rememberPlaceButton: some View {
        Button {
            showingEnrollment = true
        } label: {
            Label(
                language.text(.actionRememberPlace),
                systemImage: "plus.viewfinder"
            )
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.bordered)
        .disabled(isBusy)
        .accessibilityHint(language.text(.hintRememberPlace))
    }

    private var captureButton: some View {
        Button {
            Task {
                await captureModel.capture(language: language)
            }
        } label: {
            Label(
                language.text(
                    captureModel.isCapturing
                        ? .actionCapturing
                        : .actionCapture
                ),
                systemImage: "camera.shutter.button"
            )
            .font(.title3.bold())
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .buttonStyle(.borderedProminent)
        .tint(.secondary)
        .disabled(isBusy)
        .accessibilityLabel(
            language.text(
                captureModel.isCapturing
                    ? .actionCapturing
                    : .actionCapture
            )
        )
        .accessibilityHint(language.text(.hintCapture))
    }

    @ViewBuilder
    private var descriptionCard: some View {
        if let description = captureModel.latestDescription {
            Text(description.text)
                .font(.title3)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .accessibilityLabel(
                    descriptionAccessibilityLabel(description)
                )
        }
    }

    @ViewBuilder
    private var placeResultCard: some View {
        if let result = captureModel.latestPlaceResult {
            Text(result.text)
                .font(.title2.bold())
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    .green.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .accessibilityLabel(
                    placeResultAccessibilityLabel(result)
                )
        }
    }

    private var placesLink: some View {
        NavigationLink {
            PlacesView(
                captureModel: captureModel,
                language: language
            )
        } label: {
            Label(
                language.text(
                    .placesTitleCount,
                    argument: String(places.count)
                ),
                systemImage: "mappin.and.ellipse"
            )
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(language.text(.hintRememberedPlaces))
    }

    private var savedCapturesLink: some View {
        NavigationLink {
            SavedCapturesView(
                images: captureModel.storedImages,
                language: language
            )
        } label: {
            Label(
                language.text(
                    .savedTitleCount,
                    argument: String(captureModel.storedImages.count)
                ),
                systemImage: "photo.on.rectangle"
            )
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.bordered)
        .accessibilityHint(language.text(.savedHint))
    }

    private var languagePicker: some View {
        HStack {
            Label(
                language.text(.languageSelector),
                systemImage: "globe"
            )
            Spacer()
            Picker(
                language.text(.languageSelector),
                selection: $languagePreferenceRaw
            ) {
                ForEach(LanguagePreference.allCases) { preference in
                    Text(language.text(preference.displayKey))
                        .tag(preference.rawValue)
                }
            }
            .pickerStyle(.menu)
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
    }

    private var preview: some View {
        Group {
            if let session = captureModel.cameraSession {
                CameraPreview(session: session)
                    .accessibilityLabel(language.text(.previewRear))
            } else if let data = captureModel.latestImageData,
                      let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel(language.text(.previewLatest))
            } else {
                ZStack {
                    Color.black
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.largeTitle)
                        Text(language.text(.previewSimulatorTitle))
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                }
                .accessibilityLabel(language.text(.previewSimulatorLabel))
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .clipped()
    }

    private var status: some View {
        let statusText = captureModel.statusText(language: language)
        return HStack(alignment: .top, spacing: 10) {
            Image(
                systemName: captureModel.errorMessage == nil
                    ? "checkmark.circle"
                    : "exclamationmark.triangle"
            )
            .foregroundStyle(
                captureModel.errorMessage == nil
                    ? Color.secondary
                    : Color.red
            )
            Text(statusText)
                .font(.body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            language.text(
                .statusAccessibility,
                argument: statusText
            )
        )
    }

    private var modeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.secondary)
                .font(.title)

            VStack(alignment: .leading) {
                Text(language.text(.modeLabel))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(language.text(.modeInactive))
                    .font(.headline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(language.text(.modeCurrentInactive))
    }

    private func descriptionAccessibilityLabel(
        _ description: SceneDescription
    ) -> Text {
        accessibilityText(
            description.language.text(
                .sceneDescriptionLabel,
                argument: description.text
            ),
            language: description.language
        )
    }

    private func placeResultAccessibilityLabel(
        _ result: PlaceRecognitionOutput
    ) -> Text {
        accessibilityText(
            result.language.text(
                .placeResultAccessibility,
                argument: result.text
            ),
            language: result.language
        )
    }

    private func accessibilityText(
        _ value: String,
        language: SupportedLanguage
    ) -> Text {
        let attributedValue = NSAttributedString(
            string: value,
            attributes: [
                .accessibilitySpeechLanguage: language.rawValue
            ]
        )
        return Text(AttributedString(attributedValue))
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [Place.self, PlaceSnapshot.self],
            inMemory: true
        )
}
