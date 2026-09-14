import SwiftUI
import UIKit

struct SavedCapturesView: View {
    let images: [StoredImage]
    let language: SupportedLanguage

    var body: some View {
        Group {
            if images.isEmpty {
                ContentUnavailableView(
                    language.text(.savedEmptyTitle),
                    systemImage: "photo",
                    description: Text(
                        language.text(.savedEmptyDescription)
                    )
                )
            } else {
                List(images) { image in
                    HStack(spacing: 12) {
                        thumbnail(for: image)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                image.createdAt.formatted(
                                    .dateTime.locale(language.locale)
                                )
                            )
                            .font(.headline)
                            Text(image.filename)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(
                        language.text(
                            .savedCaptureAccessibility,
                            argument: image.createdAt.formatted(
                                .dateTime.locale(language.locale)
                            )
                        )
                    )
                }
            }
        }
        .navigationTitle(language.text(.savedTitle))
        .environment(\.locale, language.locale)
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
