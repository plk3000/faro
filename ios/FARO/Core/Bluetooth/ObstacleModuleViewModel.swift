import Foundation
import Observation

@MainActor
@Observable
final class ObstacleModuleViewModel {
    @ObservationIgnored
    private let transport: any ObstacleModuleTransport
    @ObservationIgnored
    private let telemetryTimeout: Duration
    @ObservationIgnored
    private var staleTelemetryTask: Task<Void, Never>?
    @ObservationIgnored
    private var isStarted = false

    private(set) var connectionState:
        ObstacleModuleConnectionState = .idle
    private(set) var latestTelemetry: ObstacleTelemetry?
    private(set) var requestedMode: OperatingMode = .inactive
    private(set) var confirmedMode: OperatingMode?
    private(set) var errorMessage: AppMessage?

    init(
        transport: (any ObstacleModuleTransport)? = nil,
        telemetryTimeout: Duration = .seconds(2)
    ) {
        let selectedTransport =
            transport ?? ObstacleModuleTransportFactory.makeDefault()
        self.transport = selectedTransport
        self.telemetryTimeout = telemetryTimeout
        selectedTransport.eventHandler = { [weak self] event in
            self?.handle(event)
        }
    }

    var isModeSynchronized: Bool {
        connectionState == .connected
            && requestedMode == confirmedMode
    }

    func start(mode: OperatingMode) {
        requestedMode = mode
        guard !isStarted else {
            synchronizeModeIfConnected()
            return
        }
        isStarted = true
        errorMessage = nil
        transport.start()
    }

    func stop() {
        guard isStarted else {
            return
        }
        isStarted = false
        transport.stop()
        clearLiveState()
        connectionState = .idle
        errorMessage = nil
    }

    func updateOperatingMode(_ mode: OperatingMode) {
        guard mode != requestedMode else {
            return
        }
        requestedMode = mode
        synchronizeModeIfConnected()
    }

    func connectionText(language: SupportedLanguage) -> String {
        language.text(connectionState.displayKey)
    }

    func summaryText(language: SupportedLanguage) -> String {
        if connectionState == .connected, !isModeSynchronized {
            return language.text(.bleModeSynchronizing)
        }
        return connectionText(language: language)
    }

    func distanceText(language: SupportedLanguage) -> String {
        guard let distance = latestTelemetry?.distanceMeters else {
            return language.text(.bleDistanceUnavailable)
        }
        let formattedDistance = distance.formatted(
            .number
                .precision(.fractionLength(2))
                .locale(language.locale)
        )
        return language.text(
            .bleDistanceValue,
            argument: formattedDistance
        )
    }

    func warningText(language: SupportedLanguage) -> String {
        guard let warningState = latestTelemetry?.warningState else {
            return language.text(.bleWarningSensorUnavailable)
        }
        return language.text(warningState.displayKey)
    }

    func requestedModeText(language: SupportedLanguage) -> String {
        language.text(requestedMode.displayKey)
    }

    func confirmedModeText(language: SupportedLanguage) -> String {
        guard let confirmedMode else {
            return language.text(.bleModeNotConfirmed)
        }
        return language.text(confirmedMode.displayKey)
    }

    func errorText(language: SupportedLanguage) -> String? {
        errorMessage?.localized(in: language)
    }

    private func handle(_ event: ObstacleModuleTransportEvent) {
        guard isStarted else {
            return
        }
        switch event {
        case .bluetoothUnavailable:
            clearLiveState()
            connectionState = .bluetoothUnavailable

        case .scanning:
            clearLiveState()
            connectionState = .scanning

        case .connecting:
            connectionState = .connecting

        case .discovering:
            connectionState = .discovering

        case .connected:
            connectionState = .connected
            errorMessage = nil
            synchronizeModeIfConnected()

        case .disconnected:
            clearLiveState()
            connectionState = .disconnected

        case let .telemetry(data):
            do {
                let telemetry = try ObstacleTelemetryCodec.decode(data)
                latestTelemetry = telemetry
                clearError(.invalidTelemetry)
                scheduleTelemetryExpiry()
            } catch {
                latestTelemetry = nil
                staleTelemetryTask?.cancel()
                errorMessage = ObstacleModuleError
                    .invalidTelemetry
                    .appMessage
            }

        case let .operatingMode(data):
            do {
                confirmedMode = try ObstacleModeCodec.decode(data)
                clearError(.invalidMode)
            } catch {
                confirmedMode = nil
                errorMessage = ObstacleModuleError
                    .invalidMode
                    .appMessage
            }

        case let .failure(error):
            errorMessage = error.appMessage
        }
    }

    private func synchronizeModeIfConnected() {
        guard connectionState == .connected else {
            return
        }
        transport.writeOperatingMode(requestedMode)
    }

    private func clearError(_ error: ObstacleModuleError) {
        if errorMessage == error.appMessage {
            errorMessage = nil
        }
    }

    private func scheduleTelemetryExpiry() {
        staleTelemetryTask?.cancel()
        staleTelemetryTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                try await Task.sleep(for: telemetryTimeout)
                try Task.checkCancellation()
                latestTelemetry = nil
            } catch is CancellationError {
                return
            } catch {
                latestTelemetry = nil
                errorMessage = ObstacleModuleError
                    .invalidTelemetry
                    .appMessage
            }
        }
    }

    private func clearLiveState() {
        staleTelemetryTask?.cancel()
        staleTelemetryTask = nil
        latestTelemetry = nil
        confirmedMode = nil
    }
}
