@preconcurrency import CoreBluetooth
import Foundation

enum ObstacleModuleTransportEvent: Equatable, Sendable {
    case bluetoothUnavailable
    case scanning
    case connecting
    case discovering
    case connected
    case disconnected
    case telemetry(Data)
    case operatingMode(Data)
    case failure(ObstacleModuleError)
}

@MainActor
protocol ObstacleModuleTransport: AnyObject {
    var eventHandler:
        (@MainActor @Sendable (ObstacleModuleTransportEvent) -> Void)?
    { get set }

    func start()
    func stop()
    func writeOperatingMode(_ mode: OperatingMode)
}

@MainActor
enum ObstacleModuleTransportFactory {
    static func makeDefault() -> any ObstacleModuleTransport {
#if targetEnvironment(simulator)
        MockObstaclePeripheral()
#else
        CoreBluetoothObstacleModuleTransport()
#endif
    }
}

@MainActor
final class CoreBluetoothObstacleModuleTransport:
    NSObject,
    ObstacleModuleTransport,
    @preconcurrency CBCentralManagerDelegate,
    @preconcurrency CBPeripheralDelegate
{
    var eventHandler:
        (@MainActor @Sendable (ObstacleModuleTransportEvent) -> Void)?

    private var centralManager: CBCentralManager?
    private var peripheral: CBPeripheral?
    private var telemetryCharacteristic: CBCharacteristic?
    private var modeCharacteristic: CBCharacteristic?
    private var cancelledPeripheralIdentifier: UUID?
    private var isRunning = false

    func start() {
        guard !isRunning else {
            return
        }
        isRunning = true

        if let centralManager {
            update(for: centralManager.state)
        } else {
            centralManager = CBCentralManager(
                delegate: self,
                queue: nil,
                options: [
                    CBCentralManagerOptionShowPowerAlertKey: true
                ]
            )
        }
    }

    func stop() {
        guard isRunning else {
            return
        }
        isRunning = false
        centralManager?.stopScan()
        telemetryCharacteristic = nil
        modeCharacteristic = nil
        if let peripheral,
           peripheral.state != .disconnected {
            cancelledPeripheralIdentifier = peripheral.identifier
            centralManager?.cancelPeripheralConnection(peripheral)
        } else {
            clearPeripheral()
        }
    }

    func writeOperatingMode(_ mode: OperatingMode) {
        guard let peripheral, let modeCharacteristic else {
            eventHandler?(.failure(.characteristicsUnavailable))
            return
        }
        peripheral.writeValue(
            ObstacleModeCodec.encode(mode),
            for: modeCharacteristic,
            type: .withResponse
        )
    }

    func centralManagerDidUpdateState(
        _ central: CBCentralManager
    ) {
        update(for: central.state)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        guard isRunning, self.peripheral == nil else {
            return
        }
        central.stopScan()
        self.peripheral = peripheral
        peripheral.delegate = self
        eventHandler?(.connecting)
        central.connect(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        guard isRunning, peripheral == self.peripheral else {
            central.cancelPeripheralConnection(peripheral)
            return
        }
        eventHandler?(.discovering)
        peripheral.discoverServices([
            ObstacleModuleBluetoothUUID.service
        ])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        guard peripheral == self.peripheral else {
            return
        }
        let wasRequested =
            cancelledPeripheralIdentifier == peripheral.identifier
        cancelledPeripheralIdentifier = nil
        if !wasRequested {
            eventHandler?(.failure(.connectionFailed))
        }
        eventHandler?(.disconnected)
        clearPeripheral()
        scanIfPossible()
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: (any Error)?
    ) {
        guard peripheral == self.peripheral else {
            return
        }
        let wasRequested =
            cancelledPeripheralIdentifier == peripheral.identifier
        cancelledPeripheralIdentifier = nil
        if !wasRequested, error != nil {
            eventHandler?(.failure(.connectionFailed))
        }
        eventHandler?(.disconnected)
        clearPeripheral()
        scanIfPossible()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: (any Error)?
    ) {
        guard peripheral == self.peripheral else {
            return
        }
        guard error == nil,
              let service = peripheral.services?.first(
                  where: {
                      $0.uuid == ObstacleModuleBluetoothUUID.service
                  }
              )
        else {
            failConnection(with: .serviceUnavailable)
            return
        }
        peripheral.discoverCharacteristics(
            [
                ObstacleModuleBluetoothUUID.telemetry,
                ObstacleModuleBluetoothUUID.operatingMode
            ],
            for: service
        )
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: (any Error)?
    ) {
        guard peripheral == self.peripheral,
              service.uuid == ObstacleModuleBluetoothUUID.service
        else {
            return
        }
        guard error == nil, let characteristics = service.characteristics
        else {
            failConnection(with: .characteristicsUnavailable)
            return
        }

        let telemetry = characteristics.first {
            $0.uuid == ObstacleModuleBluetoothUUID.telemetry
        }
        let mode = characteristics.first {
            $0.uuid == ObstacleModuleBluetoothUUID.operatingMode
        }
        guard let telemetry,
              telemetry.properties.contains([.read, .notify]),
              let mode,
              mode.properties.contains([.read, .write, .notify])
        else {
            failConnection(with: .characteristicsUnavailable)
            return
        }

        telemetryCharacteristic = telemetry
        modeCharacteristic = mode
        peripheral.setNotifyValue(true, for: telemetry)
        peripheral.setNotifyValue(true, for: mode)
        eventHandler?(.connected)
        peripheral.readValue(for: mode)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard peripheral == self.peripheral else {
            return
        }
        guard error == nil, let value = characteristic.value else {
            eventHandler?(.failure(.connectionFailed))
            return
        }
        switch characteristic.uuid {
        case ObstacleModuleBluetoothUUID.telemetry:
            eventHandler?(.telemetry(value))
        case ObstacleModuleBluetoothUUID.operatingMode:
            eventHandler?(.operatingMode(value))
        default:
            break
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard peripheral == self.peripheral,
              characteristic.uuid
                == ObstacleModuleBluetoothUUID.operatingMode
        else {
            return
        }
        guard error == nil else {
            failConnection(with: .connectionFailed)
            return
        }
        peripheral.readValue(for: characteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: (any Error)?
    ) {
        guard peripheral == self.peripheral, error != nil else {
            return
        }
        failConnection(with: .connectionFailed)
    }

    private func update(for state: CBManagerState) {
        guard isRunning else {
            return
        }
        if state == .poweredOn {
            scanIfPossible()
        } else {
            centralManager?.stopScan()
            clearPeripheral()
            eventHandler?(.bluetoothUnavailable)
        }
    }

    private func scanIfPossible() {
        guard isRunning,
              let centralManager,
              centralManager.state == .poweredOn,
              peripheral == nil,
              !centralManager.isScanning
        else {
            return
        }
        eventHandler?(.scanning)
        centralManager.scanForPeripherals(
            withServices: [ObstacleModuleBluetoothUUID.service],
            options: [
                CBCentralManagerScanOptionAllowDuplicatesKey: false
            ]
        )
    }

    private func failConnection(with error: ObstacleModuleError) {
        eventHandler?(.failure(error))
        guard let peripheral else {
            scanIfPossible()
            return
        }
        centralManager?.cancelPeripheralConnection(peripheral)
    }

    private func clearPeripheral() {
        peripheral?.delegate = nil
        peripheral = nil
        telemetryCharacteristic = nil
        modeCharacteristic = nil
        cancelledPeripheralIdentifier = nil
    }
}

@MainActor
final class MockObstaclePeripheral: ObstacleModuleTransport {
    struct Configuration: Equatable, Sendable {
        let connectionDelay: Duration
        let discoveryDelay: Duration
        let sampleInterval: Duration
        let distancesMillimeters: [UInt16?]

        static let simulator = Configuration(
            connectionDelay: .milliseconds(250),
            discoveryDelay: .milliseconds(150),
            sampleInterval: .seconds(1),
            distancesMillimeters: [
                2_500,
                1_500,
                750,
                350,
                nil
            ]
        )
    }

    var eventHandler:
        (@MainActor @Sendable (ObstacleModuleTransportEvent) -> Void)?

    private let configuration: Configuration
    private var lifecycleTask: Task<Void, Never>?
    private var operatingMode: OperatingMode = .inactive
    private var sequence: UInt16 = 0
    private var isConnected = false

    init(configuration: Configuration = .simulator) {
        self.configuration = configuration
    }

    func start() {
        guard lifecycleTask == nil else {
            return
        }
        eventHandler?(.scanning)
        lifecycleTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                try await Task.sleep(
                    for: configuration.connectionDelay
                )
                try Task.checkCancellation()
                eventHandler?(.connecting)
                try await Task.sleep(
                    for: configuration.discoveryDelay
                )
                try Task.checkCancellation()
                eventHandler?(.discovering)
                isConnected = true
                eventHandler?(.connected)
                try await publishTelemetryUntilCancelled()
            } catch is CancellationError {
                return
            } catch {
                eventHandler?(.failure(.connectionFailed))
            }
        }
    }

    func stop() {
        lifecycleTask?.cancel()
        lifecycleTask = nil
        isConnected = false
    }

    func writeOperatingMode(_ mode: OperatingMode) {
        guard isConnected else {
            return
        }
        operatingMode = mode
        eventHandler?(
            .operatingMode(ObstacleModeCodec.encode(mode))
        )
    }

    private func publishTelemetryUntilCancelled() async throws {
        var index = 0
        while !Task.isCancelled {
            let distances = configuration.distancesMillimeters
            let distance = distances.isEmpty
                ? nil
                : distances[index % distances.count]
            let telemetry = ObstacleTelemetry(
                sequence: sequence,
                distanceMillimeters: distance,
                warningState: .classify(
                    distanceMillimeters: distance
                ),
                operatingMode: operatingMode
            )
            do {
                eventHandler?(
                    .telemetry(
                        try ObstacleTelemetryCodec.encode(telemetry)
                    )
                )
            } catch let error as ObstacleModuleError {
                eventHandler?(.failure(error))
            }

            sequence &+= 1
            index += 1
            try await Task.sleep(
                for: configuration.sampleInterval
            )
        }
    }
}
