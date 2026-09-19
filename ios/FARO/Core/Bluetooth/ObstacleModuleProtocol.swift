import CoreBluetooth
import Foundation

enum ObstacleModuleBluetoothUUID {
    static let serviceString =
        "F0A00001-5E9B-4D7A-8C31-6B7E2D490001"
    static let telemetryString =
        "F0A00002-5E9B-4D7A-8C31-6B7E2D490001"
    static let operatingModeString =
        "F0A00003-5E9B-4D7A-8C31-6B7E2D490001"

    @MainActor
    static var service: CBUUID {
        CBUUID(string: serviceString)
    }

    @MainActor
    static var telemetry: CBUUID {
        CBUUID(string: telemetryString)
    }

    @MainActor
    static var operatingMode: CBUUID {
        CBUUID(string: operatingModeString)
    }
}

enum ObstacleWarningState:
    UInt8,
    CaseIterable,
    Codable,
    Equatable,
    Sendable
{
    case clear = 0
    case slow = 1
    case fast = 2
    case urgent = 3
    case sensorUnavailable = 4

    var displayKey: AppStringKey {
        switch self {
        case .clear:
            .bleWarningClear
        case .slow:
            .bleWarningSlow
        case .fast:
            .bleWarningFast
        case .urgent:
            .bleWarningUrgent
        case .sensorUnavailable:
            .bleWarningSensorUnavailable
        }
    }

    static func classify(
        distanceMillimeters: UInt16?
    ) -> ObstacleWarningState {
        guard let distanceMillimeters else {
            return .sensorUnavailable
        }
        if distanceMillimeters
            >= ObstacleDistanceBands.clearMinimumMillimeters {
            return .clear
        }
        if distanceMillimeters
            >= ObstacleDistanceBands.slowMinimumMillimeters {
            return .slow
        }
        if distanceMillimeters
            >= ObstacleDistanceBands.fastMinimumMillimeters {
            return .fast
        }
        return .urgent
    }
}

enum ObstacleDistanceBands {
    static let clearMinimumMillimeters: UInt16 = 2_000
    static let slowMinimumMillimeters: UInt16 = 1_000
    static let fastMinimumMillimeters: UInt16 = 500
}

struct ObstacleTelemetry: Equatable, Sendable {
    let sequence: UInt16
    let distanceMillimeters: UInt16?
    let warningState: ObstacleWarningState
    let operatingMode: OperatingMode

    var distanceMeters: Double? {
        distanceMillimeters.map { Double($0) / 1_000 }
    }
}

enum ObstacleModuleError: Error, Equatable, Sendable {
    case connectionFailed
    case serviceUnavailable
    case characteristicsUnavailable
    case invalidTelemetry
    case invalidMode
}

extension ObstacleModuleError: AppMessageProviding {
    var appMessage: AppMessage {
        switch self {
        case .connectionFailed:
            AppMessage(.errorBLEConnection)
        case .serviceUnavailable:
            AppMessage(.errorBLEService)
        case .characteristicsUnavailable:
            AppMessage(.errorBLECharacteristics)
        case .invalidTelemetry:
            AppMessage(.errorBLETelemetry)
        case .invalidMode:
            AppMessage(.errorBLEMode)
        }
    }
}

enum ObstacleTelemetryCodec {
    static let protocolVersion: UInt8 = 1
    static let packetLength = 8

    private static let distanceValidFlag: UInt8 = 1 << 0
    private static let navigatingFlag: UInt8 = 1 << 1
    private static let knownFlags =
        distanceValidFlag | navigatingFlag
    private static let invalidDistance = UInt16.max

    static func decode(_ data: Data) throws -> ObstacleTelemetry {
        let bytes = [UInt8](data)
        guard bytes.count == packetLength,
              bytes[0] == protocolVersion,
              bytes[1] & ~knownFlags == 0,
              bytes[7] == 0,
              let warningState = ObstacleWarningState(
                  rawValue: bytes[6]
              )
        else {
            throw ObstacleModuleError.invalidTelemetry
        }

        let sequence = UInt16(bytes[2])
            | UInt16(bytes[3]) << 8
        let encodedDistance = UInt16(bytes[4])
            | UInt16(bytes[5]) << 8
        let distanceIsValid =
            bytes[1] & distanceValidFlag != 0
        let distanceMillimeters: UInt16?

        if distanceIsValid {
            guard encodedDistance != invalidDistance else {
                throw ObstacleModuleError.invalidTelemetry
            }
            distanceMillimeters = encodedDistance
        } else {
            guard encodedDistance == invalidDistance else {
                throw ObstacleModuleError.invalidTelemetry
            }
            distanceMillimeters = nil
        }

        guard warningState == ObstacleWarningState.classify(
            distanceMillimeters: distanceMillimeters
        ) else {
            throw ObstacleModuleError.invalidTelemetry
        }

        return ObstacleTelemetry(
            sequence: sequence,
            distanceMillimeters: distanceMillimeters,
            warningState: warningState,
            operatingMode: bytes[1] & navigatingFlag == 0
                ? .inactive
                : .navigating
        )
    }

    static func encode(
        _ telemetry: ObstacleTelemetry
    ) throws -> Data {
        guard telemetry.warningState
            == ObstacleWarningState.classify(
                distanceMillimeters: telemetry.distanceMillimeters
            ),
              telemetry.distanceMillimeters != invalidDistance
        else {
            throw ObstacleModuleError.invalidTelemetry
        }

        var flags: UInt8 = 0
        if telemetry.distanceMillimeters != nil {
            flags |= distanceValidFlag
        }
        if telemetry.operatingMode == .navigating {
            flags |= navigatingFlag
        }

        let distance =
            telemetry.distanceMillimeters ?? invalidDistance
        return Data([
            protocolVersion,
            flags,
            UInt8(truncatingIfNeeded: telemetry.sequence),
            UInt8(truncatingIfNeeded: telemetry.sequence >> 8),
            UInt8(truncatingIfNeeded: distance),
            UInt8(truncatingIfNeeded: distance >> 8),
            telemetry.warningState.rawValue,
            0
        ])
    }
}

enum ObstacleModeCodec {
    static func decode(_ data: Data) throws -> OperatingMode {
        guard data.count == 1, let value = data.first else {
            throw ObstacleModuleError.invalidMode
        }
        switch value {
        case 0:
            return .inactive
        case 1:
            return .navigating
        default:
            throw ObstacleModuleError.invalidMode
        }
    }

    static func encode(_ mode: OperatingMode) -> Data {
        Data([mode == .navigating ? 1 : 0])
    }
}

enum ObstacleModuleConnectionState:
    CaseIterable,
    Equatable,
    Sendable
{
    case idle
    case bluetoothUnavailable
    case scanning
    case connecting
    case discovering
    case connected
    case disconnected

    var displayKey: AppStringKey {
        switch self {
        case .idle:
            .bleStateIdle
        case .bluetoothUnavailable:
            .bleStateUnavailable
        case .scanning:
            .bleStateScanning
        case .connecting:
            .bleStateConnecting
        case .discovering:
            .bleStateDiscovering
        case .connected:
            .bleStateConnected
        case .disconnected:
            .bleStateDisconnected
        }
    }
}
