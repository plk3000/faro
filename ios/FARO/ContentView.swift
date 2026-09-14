import SwiftUI
import UIKit

struct ContentView: View {
    @State private var captureModel = CaptureViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    modeCard
                    preview

                    Button {
                        Task {
                            await captureModel.describe()
                        }
                    } label: {
                        Label(
                            captureModel.isDescribing
                                ? "Describing..."
                                : "Describe scene",
                            systemImage: "text.bubble"
                        )
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy)
                    .accessibilityLabel(
                        captureModel.isDescribing
                            ? "Describing scene"
                            : "Describe scene"
                    )
                    .accessibilityHint(
                        "Captures an image and speaks a brief description"
                    )

                    Button {
                        Task {
                            await captureModel.capture()
                        }
                    } label: {
                        Label(
                            captureModel.isCapturing
                                ? "Capturing..."
                                : "Capture image",
                            systemImage: "camera.shutter.button"
                        )
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, minHeight: 64)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.secondary)
                    .disabled(isBusy)
                    .accessibilityLabel(
                        captureModel.isCapturing
                            ? "Capturing image"
                            : "Capture image"
                    )
                    .accessibilityHint(
                        "Captures and saves one image from the rear camera"
                    )

                    status

                    if let description = captureModel.latestDescription {
                        Text(description)
                            .font(.title3)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                .regularMaterial,
                                in: RoundedRectangle(cornerRadius: 16)
                            )
                            .accessibilityLabel(
                                "Scene description: \(description)"
                            )
                    }

                    NavigationLink {
                        SavedCapturesView(images: captureModel.storedImages)
                    } label: {
                        Label(
                            "Saved captures (\(captureModel.storedImages.count))",
                            systemImage: "photo.on.rectangle"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityHint("Shows the images saved on this device")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("FARO")
            .task {
                await captureModel.prepare()
            }
        }
    }

    private var isBusy: Bool {
        captureModel.isCapturing || captureModel.isDescribing
    }

    private var preview: some View {
        Group {
            if let session = captureModel.cameraSession {
                CameraPreview(session: session)
                    .accessibilityLabel("Rear camera preview")
            } else if let data = captureModel.latestImageData,
                      let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .accessibilityLabel("Latest captured image")
            } else {
                ZStack {
                    Color.black
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.largeTitle)
                        Text("Simulator camera fixture")
                            .font(.headline)
                    }
                    .foregroundStyle(.white)
                }
                .accessibilityLabel(
                    "Camera fixture preview. Capture an image to continue."
                )
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .clipped()
    }

    private var status: some View {
        HStack(alignment: .top, spacing: 10) {
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
            Text(captureModel.statusMessage)
                .font(.body)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(captureModel.statusMessage)")
    }

    private var modeCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "pause.circle.fill")
                .foregroundStyle(.secondary)
                .font(.title)

            VStack(alignment: .leading) {
                Text("Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Inactive")
                    .font(.headline)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current mode: Inactive")
    }
}

#Preview {
    ContentView()
}
