import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    modeCard

                    Text("FARO can describe what is ahead and remember familiar places.")
                        .font(.title2)
                        .accessibilityLabel(
                            "FARO can describe what is ahead and remember familiar places."
                        )

                    VStack(spacing: 16) {
                        actionButton(
                            title: "Describe",
                            systemImage: "camera.viewfinder",
                            hint: "Captures an image and describes the scene"
                        )

                        actionButton(
                            title: "Where am I?",
                            systemImage: "location.viewfinder",
                            hint: "Captures an image and identifies a remembered place"
                        )

                        actionButton(
                            title: "Remember a place",
                            systemImage: "plus.viewfinder",
                            hint: "Starts saving views of a named place"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("FARO")
        }
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

    private func actionButton(
        title: String,
        systemImage: String,
        hint: String
    ) -> some View {
        Button(action: {}) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 56)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}

#Preview {
    ContentView()
}
