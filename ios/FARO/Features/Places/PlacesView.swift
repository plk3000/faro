import SwiftData
import SwiftUI

struct PlacesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Place.label) private var places: [Place]

    let captureModel: CaptureViewModel
    let language: SupportedLanguage

    @State private var placeAddingViews: Place?
    @State private var placeRenaming: Place?
    @State private var renameText = ""
    @State private var errorMessage: AppMessage?

    var body: some View {
        Group {
            if places.isEmpty {
                ContentUnavailableView(
                    language.text(.placesEmptyTitle),
                    systemImage: "mappin.slash",
                    description: Text(
                        language.text(.placesEmptyDescription)
                    )
                )
            } else {
                List {
                    ForEach(places) { place in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(place.label)
                                .font(.headline)
                            Text(
                                language.text(
                                    .placeViewsCount,
                                    argument: String(
                                        place.snapshots.count
                                    )
                                )
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            HStack {
                                Button(language.text(.actionAddViews)) {
                                    placeAddingViews = place
                                }
                                .buttonStyle(.bordered)

                                Button(language.text(.actionRename)) {
                                    renameText = place.label
                                    placeRenaming = place
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .contain)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle(language.text(.placesTitle))
        .sheet(item: $placeAddingViews) { place in
            NavigationStack {
                RememberPlaceView(
                    captureModel: captureModel,
                    existingPlace: place,
                    language: language
                )
            }
        }
        .alert(
            language.text(.placeRenameTitle),
            isPresented: Binding(
                get: { placeRenaming != nil },
                set: { if !$0 { placeRenaming = nil } }
            )
        ) {
            TextField(
                language.text(.placeNameLabel),
                text: $renameText
            )
            Button(
                language.text(.actionCancel),
                role: .cancel
            ) {
                placeRenaming = nil
            }
            Button(language.text(.actionSave)) {
                renameSelectedPlace()
            }
        }
        .alert(
            language.text(.placeUpdateFailedTitle),
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(language.text(.actionOK), role: .cancel) {}
        } message: {
            Text(errorMessage?.localized(in: language) ?? "")
        }
        .environment(\.locale, language.locale)
    }

    private func renameSelectedPlace() {
        guard let placeRenaming else {
            return
        }
        do {
            try captureModel.rename(
                placeRenaming,
                to: renameText,
                modelContext: modelContext
            )
            self.placeRenaming = nil
        } catch {
            errorMessage = AppErrorMessage.message(
                for: error,
                language: language
            )
        }
    }

    private func delete(at offsets: IndexSet) {
        let selected = offsets.map { places[$0] }
        Task {
            for place in selected {
                do {
                    try await captureModel.delete(
                        place,
                        modelContext: modelContext
                    )
                } catch {
                    errorMessage = AppErrorMessage.message(
                        for: error,
                        language: language
                    )
                    return
                }
            }
        }
    }
}
