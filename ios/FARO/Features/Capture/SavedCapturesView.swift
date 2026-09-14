import SwiftUI
import UIKit

struct SavedCapturesView: View {
    let images: [StoredImage]

    var body: some View {
        Group {
            if images.isEmpty {
                ContentUnavailableView(
                    "No saved captures",
                    systemImage: "photo",
                    description: Text("Captured images will appear here.")
                )
            } else {
                List(images) { image in
                    HStack(spacing: 12) {
                        thumbnail(for: image)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(image.createdAt, format: .dateTime)
                                .font(.headline)
                            Text(image.filename)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        "Capture saved \(image.createdAt.formatted())"
                    )
                }
            }
        }
        .navigationTitle("Saved captures")
    }

    @ViewBuilder
    private func thumbnail(for image: StoredImage) -> some View {
        if let uiImage = UIImage(contentsOfFile: image.url.path) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        } else {
            Image(systemName: "photo")
                .frame(width: 72, height: 72)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)
        }
    }
}
