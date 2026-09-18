import Foundation
import Testing
@testable import FARO

@MainActor
private final class RecordingObstacleModuleTransport:
    ObstacleModuleTransport
{
    var eventHandler:
        (@MainActor @Sendable (ObstacleModuleTransportEvent) -> Void)?

    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var writtenModes: [OperatingMode] = []

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
    }

    func writeOperatingMode(_ mode: OperatingMode) {
        writtenModes.append(mode)
    }

    func emit(_ event: ObstacleModuleTransportEvent) {
        eventHandler?(event)
    }
}

@MainActor
struct ObstacleModuleTests {
    @Test
    func bluetoothUUIDsMatchThePublishedContract() {
        #expect(
            ObstacleModuleBluetoothUUID.serviceString
                == "F0A00001-5E9B-4D7A-8C31-6B7E2D490001"
        )
        #expect(
            ObstacleModuleBluetoothUUID.telemetryString
                == "F0A00002-5E9B-4D7A-8C31-6B7E2D490001"
        )
        #expect(
            ObstacleModuleBluetoothUUID.operatingModeString
                == "F0A00003-5E9B-4D7A-8C31-6B7E2D490001"
        )
    }

    @Test
    func telemetryCodecUsesVersionedLittleEndianPacket() throws {
        let telemetry = ObstacleTelemetry(
            sequence: 0x1234,
            distanceMillimeters: 750,
            warningState: .fast,
            operatingMode: .navigating
        )

        let data = try ObstacleTelemetryCodec.encode(telemetry)

        #expect(
            data == Data([
                0x01,
                0x03,
                0x34,
                0x12,
                0xEE,
                0x02,
                0x02,
                0x00
            ])
        )
        #expect(try ObstacleTelemetryCodec.decode(data) == telemetry)
    }

    @Test
    func telemetryCodecRepresentsMissingEchoExplicitly() throws {
        let data = Data([
            0x01,
            0x00,
            0x01,
            0x00,
            0xFF,
            0xFF,
            0x04,
            0x00
        ])

        let telemetry = try ObstacleTelemetryCodec.decode(data)

        #expect(telemetry.sequence == 1)
        #expect(telemetry.distanceMillimeters == nil)
        #expect(telemetry.warningState == .sensorUnavailable)
        #expect(telemetry.operatingMode == .inactive)
    }

    @Test
    func warningBandsUseTheDocumentedBoundaries() {
        #expect(
            ObstacleWarningState.classify(
                distanceMillimeters: nil
            ) == .sensorUnavailable
        )
        #expect(
            ObstacleWarningState.classify(
                distanceMillimeters: 499
            ) == .urgent
        )
        #expect(
            ObstacleWarningState.classify(
                distanceMillimeters: 500
            ) == .fast
        )
        #expect(
            ObstacleWarningState.classify(
                distanceMillimeters: 999
            ) == .fast
        )
        #expect(
            ObstacleWarningState.classify(
                distanceMillimeters: 1_000
            ) == .slow
        )
        #expect(
            ObstacleWarningState.classify(
                distanceMillimeters: 1_999
            ) == .slow
        )
        #expect(
            ObstacleWarningState.classify(
                distanceMillimeters: 2_000
            ) == .clear
        )
    }

    @Test(arguments: [
        Data(),
        Data([0x02, 0, 0, 0, 0xFF, 0xFF, 4, 0]),
        Data([0x01, 0x04, 0, 0, 0xFF, 0xFF, 4, 0]),
        Data([0x01, 0x01, 0, 0, 0xFF, 0xFF, 4, 0]),
        Data([0x01, 0x00, 0, 0, 0xFF, 0xFF, 0, 0]),
        Data([0x01, 0x00, 0, 0, 0xFF, 0xFF, 5, 0]),
        Data([0x01, 0x00, 0, 0, 0xFF, 0xFF, 4, 1])
    ])
    func telemetryCodecRejectsMalformedPackets(data: Data) {
        #expect(throws: ObstacleModuleError.invalidTelemetry) {
            _ = try ObstacleTelemetryCodec.decode(data)
        }
    }

    @Test
    func modeCodecAcceptsOnlyOneKnownByte() throws {
        #expect(
            try ObstacleModeCodec.decode(Data([0])) == .inactive
        )
        #expect(
            try ObstacleModeCodec.decode(Data([1])) == .navigating
        )
        #expect(
            ObstacleModeCodec.encode(.inactive) == Data([0])
        )
        #expect(
            ObstacleModeCodec.encode(.navigating) == Data([1])
        )
        #expect(throws: ObstacleModuleError.invalidMode) {
            _ = try ObstacleModeCodec.decode(Data([2]))
        }
        #expect(throws: ObstacleModuleError.invalidMode) {
            _ = try ObstacleModeCodec.decode(Data([0, 1]))
        }
    }

    @Test
    func connectedModelSynchronizesModeAndPublishesTelemetry() throws {
        let transport = RecordingObstacleModuleTransport()
        let model = ObstacleModuleViewModel(transport: transport)
        let telemetry = ObstacleTelemetry(
            sequence: 7,
            distanceMillimeters: 350,
            warningState: .urgent,
            operatingMode: .navigating
        )

        model.start(mode: .navigating)
        transport.emit(.scanning)
        transport.emit(.connected)
        transport.emit(
            .operatingMode(ObstacleModeCodec.encode(.navigating))
        )
        transport.emit(
            .telemetry(try ObstacleTelemetryCodec.encode(telemetry))
        )

        #expect(transport.startCount == 1)
        #expect(transport.writtenModes == [.navigating])
        #expect(model.connectionState == .connected)
        #expect(model.latestTelemetry == telemetry)
        #expect(model.confirmedMode == .navigating)
        #expect(model.isModeSynchronized)
    }

    @Test
    func modeChangesAreSentAfterConnection() {
        let transport = RecordingObstacleModuleTransport()
        let model = ObstacleModuleViewModel(transport: transport)

        model.start(mode: .inactive)
        transport.emit(.connected)
        model.updateOperatingMode(.navigating)

        #expect(
            transport.writtenModes == [
                .inactive,
                .navigating
            ]
        )
        #expect(!model.isModeSynchronized)
        #expect(
            model.summaryText(language: .englishUS)
                == "ESP32 mode is not synchronized"
        )
    }

    @Test
    func reconnectResendsCurrentModeWithoutImplicitlyDisarming() {
        let transport = RecordingObstacleModuleTransport()
        let model = ObstacleModuleViewModel(transport: transport)

        model.start(mode: .navigating)
        transport.emit(.connected)
        transport.emit(.disconnected)
        transport.emit(.scanning)
        transport.emit(.connected)
        model.stop()

        #expect(
            transport.writtenModes == [
                .navigating,
                .navigating
            ]
        )
        #expect(transport.stopCount == 1)
    }

    @Test
    func disconnectClearsPotentiallyStaleHardwareState() throws {
        let transport = RecordingObstacleModuleTransport()
        let model = ObstacleModuleViewModel(transport: transport)
        let telemetry = ObstacleTelemetry(
            sequence: 2,
            distanceMillimeters: 1_500,
            warningState: .slow,
            operatingMode: .navigating
        )

        model.start(mode: .navigating)
        transport.emit(.connected)
        transport.emit(
            .telemetry(try ObstacleTelemetryCodec.encode(telemetry))
        )
        transport.emit(.disconnected)

        #expect(model.connectionState == .disconnected)
        #expect(model.latestTelemetry == nil)
        #expect(model.confirmedMode == nil)
        #expect(!model.isModeSynchronized)
        #expect(
            model.distanceText(language: .englishUS)
                == "No current reading"
        )
    }

    @Test
    func invalidModeConfirmationCannotRemainSynchronized() {
        let transport = RecordingObstacleModuleTransport()
        let model = ObstacleModuleViewModel(transport: transport)

        model.start(mode: .navigating)
        transport.emit(.connected)
        transport.emit(
            .operatingMode(ObstacleModeCodec.encode(.navigating))
        )
        transport.emit(.operatingMode(Data([2])))

        #expect(model.confirmedMode == nil)
        #expect(!model.isModeSynchronized)
        #expect(
            model.errorText(language: .englishUS)
                == "The ESP32 returned an invalid operating mode."
        )
    }

    @Test
    func staleTelemetryIsRemovedWithoutDisconnecting() async throws {
        let transport = RecordingObstacleModuleTransport()
        let model = ObstacleModuleViewModel(
            transport: transport,
            telemetryTimeout: .milliseconds(20)
        )
        let telemetry = ObstacleTelemetry(
            sequence: 3,
            distanceMillimeters: 2_500,
            warningState: .clear,
            operatingMode: .inactive
        )

        model.start(mode: .inactive)
        transport.emit(.connected)
        transport.emit(
            .telemetry(try ObstacleTelemetryCodec.encode(telemetry))
        )
        let expired = await waitUntil {
            model.latestTelemetry == nil
        }

        #expect(expired)
        #expect(model.connectionState == .connected)
    }

    @Test
    func simulatorPeripheralDrivesConnectedTelemetry() async {
        let peripheral = MockObstaclePeripheral(
            configuration: .init(
                connectionDelay: .zero,
                discoveryDelay: .zero,
                sampleInterval: .milliseconds(10),
                distancesMillimeters: [750]
            )
        )
        let model = ObstacleModuleViewModel(
            transport: peripheral,
            telemetryTimeout: .seconds(1)
        )

        model.start(mode: .navigating)
        let received = await waitUntil {
            model.connectionState == .connected
                && model.latestTelemetry?.distanceMillimeters == 750
                && model.isModeSynchronized
        }
        model.stop()

        #expect(received)
        #expect(model.connectionState == .idle)
    }

    @Test(arguments: SupportedLanguage.allCases)
    func bluetoothStatusTextIsLocalized(
        language: SupportedLanguage
    ) {
        for state in ObstacleModuleConnectionState.allCases {
            #expect(
                language.text(state.displayKey)
                    != state.displayKey.rawValue
            )
        }
        for warning in ObstacleWarningState.allCases {
            #expect(
                language.text(warning.displayKey)
                    != warning.displayKey.rawValue
            )
        }

        let keys: [AppStringKey] = [
            .bleTitle,
            .bleHint,
            .bleConnectionLabel,
            .bleDistanceLabel,
            .bleWarningLabel,
            .bleRequestedModeLabel,
            .bleConfirmedModeLabel,
            .bleModeNotConfirmed,
            .bleModeSynchronizing,
            .bleSafetyNote,
            .errorBLEConnection,
            .errorBLEService,
            .errorBLECharacteristics,
            .errorBLETelemetry,
            .errorBLEMode
        ]
        for key in keys {
            #expect(language.text(key) != key.rawValue)
        }
    }

    private func waitUntil(
        attempts: Int = 100,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if condition() {
                return true
            }
            do {
                try await Task.sleep(for: .milliseconds(10))
            } catch is CancellationError {
                return false
            } catch {
                return false
            }
        }
        return condition()
    }
}
