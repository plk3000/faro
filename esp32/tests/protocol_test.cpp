#include <assert.h>
#include <stdint.h>

#include "faro_protocol.h"

void test_mode_writes_accept_only_contract_values() {
  faro::OperatingMode mode = faro::OperatingMode::Navigating;

  assert(faro::decodeOperatingMode(&faro::kInactiveModeValue, 1, &mode));
  assert(mode == faro::OperatingMode::Inactive);

  assert(faro::decodeOperatingMode(&faro::kNavigatingModeValue, 1, &mode));
  assert(mode == faro::OperatingMode::Navigating);

  const uint8_t invalid = 2;
  assert(!faro::decodeOperatingMode(&invalid, 1, &mode));
  assert(!faro::decodeOperatingMode(&faro::kInactiveModeValue, 0, &mode));
}

void test_telemetry_encodes_contract_packet() {
  const faro::Telemetry telemetry = {
      0x1234,
      true,
      750,
      faro::WarningState::Fast,
      faro::OperatingMode::Navigating,
  };
  uint8_t packet[faro::kTelemetryPacketLength] = {};

  faro::encodeTelemetry(telemetry, packet);

  assert(packet[0] == faro::kProtocolVersion);
  assert(packet[1] == 0x03);
  assert(packet[2] == 0x34);
  assert(packet[3] == 0x12);
  assert(packet[4] == 0xEE);
  assert(packet[5] == 0x02);
  assert(packet[6] == static_cast<uint8_t>(faro::WarningState::Fast));
  assert(packet[7] == 0x00);
}

void test_no_echo_encodes_sensor_unavailable() {
  const faro::Telemetry telemetry = {
      7,
      false,
      0,
      faro::WarningState::SensorUnavailable,
      faro::OperatingMode::Inactive,
  };
  uint8_t packet[faro::kTelemetryPacketLength] = {};

  faro::encodeTelemetry(telemetry, packet);

  assert(packet[1] == 0x00);
  assert(packet[4] == 0xFF);
  assert(packet[5] == 0xFF);
  assert(packet[6] == static_cast<uint8_t>(faro::WarningState::SensorUnavailable));
}

int main() {
  test_mode_writes_accept_only_contract_values();
  test_telemetry_encodes_contract_packet();
  test_no_echo_encodes_sensor_unavailable();
  return 0;
}
