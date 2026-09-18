import SwiftUI

struct ObstacleModuleDebugView: View {
    let model: ObstacleModuleViewModel
    let language: SupportedLanguage

    var body: some View {
        List {
            Section(language.text(.bleConnectionSection)) {
                statusRow(
                    label: language.text(.bleConnectionLabel),
                    value: model.connectionText(language: language),
                    symbol: connectionSymbol
                )

                if let error = model.errorText(language: language) {
                    Label(
                        error,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                }
            }

            Section(language.text(.bleTelemetrySection)) {
                statusRow(
                    label: language.text(.bleDistanceLabel),
                    value: model.distanceText(language: language),
                    symbol: "ruler"
                )
                statusRow(
                    label: language.text(.bleWarningLabel),
                    value: model.warningText(language: language),
                    symbol: "speaker.wave.2"
                )
            }

            Section(language.text(.bleModeSection)) {
                statusRow(
                    label: language.text(.bleRequestedModeLabel),
                    value: model.requestedModeText(language: language),
                    symbol: "iphone"
                )
                statusRow(
                    label: language.text(.bleConfirmedModeLabel),
                    value: model.confirmedModeText(language: language),
                    symbol: "sensor"
                )

                if !model.isModeSynchronized {
                    Label(
                        language.text(.bleModeSynchronizing),
                        systemImage: "arrow.trianglehead.2.clockwise"
                    )
                    .foregroundStyle(.orange)
                }
            }

            Section {
                Text(language.text(.bleSafetyNote))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(language.text(.bleTitle))
    }

    private var connectionSymbol: String {
        switch model.connectionState {
        case .connected:
            "antenna.radiowaves.left.and.right"
        case .scanning, .connecting, .discovering:
            "dot.radiowaves.left.and.right"
        case .idle,
             .bluetoothUnavailable,
             .disconnected:
            "antenna.radiowaves.left.and.right.slash"
        }
    }

    private func statusRow(
        label: String,
        value: String,
        symbol: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Label(label, systemImage: symbol)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }
}
