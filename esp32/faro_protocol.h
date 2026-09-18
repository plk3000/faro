#pragma once

#include <stddef.h>
#include <stdint.h>

namespace faro {

constexpr uint8_t kProtocolVersion = 0x01;
constexpr size_t kTelemetryPacketLength = 8;
constexpr uint8_t kInactiveModeValue = 0x00;
constexpr uint8_t kNavigatingModeValue = 0x01;
constexpr uint16_t kInvalidDistanceMillimeters = 0xFFFF;

enum class OperatingMode : uint8_t {
  Inactive = kInactiveModeValue,
  Navigating = kNavigatingModeValue,
};

enum class WarningState : uint8_t {
  Clear = 0,
  Slow = 1,
  Fast = 2,
  Urgent = 3,
  SensorUnavailable = 4,
};

struct Telemetry {
  uint16_t sequence;
  bool distanceValid;
  uint16_t distanceMillimeters;
  WarningState warningState;
  OperatingMode operatingMode;
};

inline bool decodeOperatingMode(const uint8_t* value, size_t length,
                                OperatingMode* mode) {
  if (value == nullptr || mode == nullptr || length != 1) {
    return false;
  }
  if (value[0] == kInactiveModeValue) {
    *mode = OperatingMode::Inactive;
    return true;
  }
  if (value[0] == kNavigatingModeValue) {
    *mode = OperatingMode::Navigating;
    return true;
  }
  return false;
}

inline WarningState classifyWarning(bool distanceValid,
                                    uint16_t distanceMillimeters) {
  if (!distanceValid) {
    return WarningState::SensorUnavailable;
  }
  if (distanceMillimeters >= 2000) {
    return WarningState::Clear;
  }
  if (distanceMillimeters >= 1000) {
    return WarningState::Slow;
  }
  if (distanceMillimeters >= 500) {
    return WarningState::Fast;
  }
  return WarningState::Urgent;
}

inline void encodeTelemetry(const Telemetry& telemetry,
                            uint8_t packet[kTelemetryPacketLength]) {
  const uint16_t encodedDistance = telemetry.distanceValid
                                       ? telemetry.distanceMillimeters
                                       : kInvalidDistanceMillimeters;
  packet[0] = kProtocolVersion;
  packet[1] = (telemetry.distanceValid ? 0x01 : 0x00) |
              (telemetry.operatingMode == OperatingMode::Navigating ? 0x02
                                                                      : 0x00);
  packet[2] = static_cast<uint8_t>(telemetry.sequence & 0xFF);
  packet[3] = static_cast<uint8_t>(telemetry.sequence >> 8);
  packet[4] = static_cast<uint8_t>(encodedDistance & 0xFF);
  packet[5] = static_cast<uint8_t>(encodedDistance >> 8);
  packet[6] = static_cast<uint8_t>(telemetry.warningState);
  packet[7] = 0x00;
}

}  // namespace faro
