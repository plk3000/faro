import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage(LanguagePreference.storageKey)
    private var languagePreferenceRaw = LanguagePreference.followSystem.rawValue

    @State private var captureModel = CaptureViewModel()

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

                    status

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

                    NavigationLink {
                        SavedCapturesView(
                            images: captureModel.storedImages,
                            language: language
                        )
                    } label: {
                        Label(
                            language.text(
                                .savedTitleCount,
                                argument: String(
                                    captureModel.storedImages.count
                                )
                            ),
                            systemImage: "photo.on.rectangle"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint(language.text(.savedHint))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("FARO")
            .task {
                await captureModel.prepare(language: language)
            }
        }
        .environment(\.locale, language.locale)
    }

    private var isBusy: Bool {
        captureModel.isCapturing || captureModel.isDescribing
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
        let label = description.language.text(
            .sceneDescriptionLabel,
            argument: description.text
        )
        let attributedLabel = NSAttributedString(
            string: label,
            attributes: [
                .accessibilitySpeechLanguage:
                    description.language.rawValue
            ]
        )
        return Text(AttributedString(attributedLabel))
    }
}

#Preview {
    ContentView()
}
