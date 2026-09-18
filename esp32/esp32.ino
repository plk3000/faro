// FARO ESP32 obstacle module.
//
// Hardware:
// - CENFOTEC IdeaBoard (ESP32)
// - HC-SR04-style ultrasonic sensor: TRIG GPIO 25, ECHO GPIO 26
// - Onboard WS2812B / NeoPixel: GPIO 2
// - Passive buzzer: GPIO 27
//
// IMPORTANT: The HC-SR04 ECHO signal is 5 V. A voltage divider or level
// shifter must be installed before connecting it to the ESP32's 3.3 V GPIO 26.
// The IdeaBoard SELECT-to-Vin jumper must be installed for the sonar.
//
// The GATT layout and packet encoding are defined in ../docs/ble-contract.md.
// The module always boots Inactive. BLE disconnection does not disarm an
// already-Navigating module; a reset or explicit encrypted Inactive command
// does.

#include <Adafruit_NeoPixel.h>
#include <BLE2902.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLESecurity.h>

#include "faro_protocol.h"

namespace {
constexpr uint8_t kSonarTriggerPin = 25;
constexpr uint8_t kSonarEchoPin = 26;
constexpr uint8_t kLedPin = 2;
constexpr uint8_t kLedCount = 1;
constexpr uint8_t kBuzzerPin = 27;

constexpr unsigned long kEchoTimeoutMicros = 25000;
constexpr unsigned long kSampleIntervalMillis = 100;
constexpr size_t kSampleCount = 5;

constexpr float kNearDistanceCm = 50.0F;
constexpr float kMediumDistanceCm = 100.0F;
constexpr float kFarDistanceCm = 200.0F;

constexpr char kDeviceName[] = "FARO-Obstacle";
constexpr char kServiceUuid[] = "F0A00001-5E9B-4D7A-8C31-6B7E2D490001";
constexpr char kTelemetryCharacteristicUuid[] =
    "F0A00002-5E9B-4D7A-8C31-6B7E2D490001";
constexpr char kOperatingModeCharacteristicUuid[] =
    "F0A00003-5E9B-4D7A-8C31-6B7E2D490001";

struct BuzzerPattern {
  unsigned int frequencyHz;
  unsigned long toneDurationMillis;
  unsigned long periodMillis;
};

constexpr BuzzerPattern kSilentPattern = {0, 0, 0};
constexpr BuzzerPattern kFarPattern = {1200, 150, 1000};
constexpr BuzzerPattern kMediumPattern = {1600, 150, 500};
constexpr BuzzerPattern kNearPattern = {2200, 120, 240};

Adafruit_NeoPixel pixel(kLedCount, kLedPin, NEO_GRB + NEO_KHZ800);
BLECharacteristic* telemetryCharacteristic = nullptr;
BLECharacteristic* operatingModeCharacteristic = nullptr;

float samples[kSampleCount] = {};
size_t sampleIndex = 0;
size_t samplesCollected = 0;
float latestDistanceCm = -1.0F;
unsigned long lastSampleAt = 0;
unsigned long buzzerPatternStartedAt = 0;
bool buzzerIsOn = false;
unsigned int activeBuzzerFrequencyHz = 0;
uint16_t telemetrySequence = 0;
volatile faro::OperatingMode operatingMode = faro::OperatingMode::Inactive;

float measureDistanceCm() {
  digitalWrite(kSonarTriggerPin, LOW);
  delayMicroseconds(2);
  digitalWrite(kSonarTriggerPin, HIGH);
  delayMicroseconds(10);
  digitalWrite(kSonarTriggerPin, LOW);

  const unsigned long duration =
      pulseIn(kSonarEchoPin, HIGH, kEchoTimeoutMicros);
  if (duration == 0) {
    return -1.0F;
  }

  return static_cast<float>(duration) * 0.0343F / 2.0F;
}

float filteredDistanceCm() {
  if (samplesCollected == 0) {
    return -1.0F;
  }

  float sorted[kSampleCount];
  for (size_t i = 0; i < samplesCollected; ++i) {
    sorted[i] = samples[i];
  }

  for (size_t i = 1; i < samplesCollected; ++i) {
    const float value = sorted[i];
    size_t j = i;
    while (j > 0 && sorted[j - 1] > value) {
      sorted[j] = sorted[j - 1];
      --j;
    }
    sorted[j] = value;
  }

  return sorted[samplesCollected / 2];
}

void setLed(uint8_t red, uint8_t green, uint8_t blue) {
  pixel.setPixelColor(0, pixel.Color(red, green, blue));
  pixel.show();
}

void showDistanceBand(float distanceCm) {
  if (distanceCm < 0.0F) {
    setLed(128, 0, 128);  // Purple: no valid echo received.
  } else if (distanceCm < kNearDistanceCm) {
    setLed(255, 0, 0);  // Red: under 0.5 m.
  } else if (distanceCm < kMediumDistanceCm) {
    setLed(255, 128, 0);  // Amber: 0.5-1 m.
  } else if (distanceCm < kFarDistanceCm) {
    setLed(0, 0, 255);  // Blue: 1-2 m.
  } else {
    setLed(0, 0, 0);  // Off: over 2 m.
  }
}

BuzzerPattern patternForDistance(float distanceCm) {
  if (distanceCm < 0.0F || distanceCm >= kFarDistanceCm) {
    return kSilentPattern;
  }
  if (distanceCm < kNearDistanceCm) {
    return kNearPattern;
  }
  if (distanceCm < kMediumDistanceCm) {
    return kMediumPattern;
  }
  return kFarPattern;
}

bool patternsMatch(const BuzzerPattern& left, const BuzzerPattern& right) {
  return left.frequencyHz == right.frequencyHz &&
         left.toneDurationMillis == right.toneDurationMillis &&
         left.periodMillis == right.periodMillis;
}

void silenceBuzzer() {
  if (buzzerIsOn) {
    noTone(kBuzzerPin);
  }
  buzzerIsOn = false;
  activeBuzzerFrequencyHz = 0;
}

void updateBuzzer(float distanceCm, unsigned long now) {
  const BuzzerPattern pattern =
      operatingMode == faro::OperatingMode::Navigating
          ? patternForDistance(distanceCm)
          : kSilentPattern;
  static BuzzerPattern currentPattern = kSilentPattern;

  if (!patternsMatch(pattern, currentPattern)) {
    currentPattern = pattern;
    buzzerPatternStartedAt = now;
    silenceBuzzer();
  }

  if (pattern.frequencyHz == 0) {
    silenceBuzzer();
    return;
  }

  const unsigned long elapsed = now - buzzerPatternStartedAt;
  const bool shouldSound =
      (elapsed % pattern.periodMillis) < pattern.toneDurationMillis;

  if (shouldSound &&
      (!buzzerIsOn || activeBuzzerFrequencyHz != pattern.frequencyHz)) {
    tone(kBuzzerPin, pattern.frequencyHz);
    buzzerIsOn = true;
    activeBuzzerFrequencyHz = pattern.frequencyHz;
  } else if (!shouldSound && buzzerIsOn) {
    silenceBuzzer();
  }
}

void addSample(float distanceCm) {
  if (distanceCm < 0.0F) {
    return;
  }

  samples[sampleIndex] = distanceCm;
  sampleIndex = (sampleIndex + 1) % kSampleCount;
  if (samplesCollected < kSampleCount) {
    ++samplesCollected;
  }
}

uint16_t distanceMillimeters(float distanceCm) {
  const float millimeters = distanceCm * 10.0F;
  if (millimeters >= 65534.0F) {
    return 65534;
  }
  return static_cast<uint16_t>(millimeters);
}

void publishOperatingMode() {
  if (operatingModeCharacteristic == nullptr) {
    return;
  }
  const uint8_t value = static_cast<uint8_t>(operatingMode);
  operatingModeCharacteristic->setValue(&value, 1);
  operatingModeCharacteristic->notify();
}

void publishTelemetry(float distanceCm) {
  if (telemetryCharacteristic == nullptr) {
    return;
  }
  const bool distanceValid = distanceCm >= 0.0F;
  const uint16_t distance =
      distanceValid ? distanceMillimeters(distanceCm) : 0;
  const faro::Telemetry telemetry = {
      telemetrySequence++,
      distanceValid,
      distance,
      faro::classifyWarning(distanceValid, distance),
      operatingMode,
  };
  uint8_t packet[faro::kTelemetryPacketLength] = {};
  faro::encodeTelemetry(telemetry, packet);
  telemetryCharacteristic->setValue(packet, sizeof(packet));
  telemetryCharacteristic->notify();
}

class OperatingModeCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    const String value = characteristic->getValue();
    faro::OperatingMode requestedMode = faro::OperatingMode::Inactive;
    if (!faro::decodeOperatingMode(
            reinterpret_cast<const uint8_t*>(value.c_str()), value.length(),
            &requestedMode)) {
      Serial.println("BLE mode write rejected: expected exactly 0x00 or 0x01");
      publishOperatingMode();
      return;
    }

    operatingMode = requestedMode;
    silenceBuzzer();
    publishOperatingMode();
    Serial.print("BLE mode: ");
    Serial.println(operatingMode == faro::OperatingMode::Navigating
                       ? "Navigating"
                       : "Inactive");
  }
};

class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*) override { Serial.println("BLE client connected"); }

  void onDisconnect(BLEServer* server) override {
    Serial.println("BLE client disconnected; retaining current mode");
    server->startAdvertising();
  }
};

void startBleServer() {
  BLEDevice::init(kDeviceName);

  // LE Secure Connections + bonding. With no physical display or keypad on
  // this module, pairing uses encrypted Just Works rather than a claimed-MITM
  // passkey flow. The mode characteristic still rejects unencrypted writes.
  BLESecurity::setCapability(ESP_IO_CAP_NONE);
  BLESecurity::setAuthenticationMode(true, false, true);

  BLEServer* server = BLEDevice::createServer();
  server->setCallbacks(new ServerCallbacks());
  server->advertiseOnDisconnect(true);

  BLEService* service = server->createService(kServiceUuid);
  telemetryCharacteristic = service->createCharacteristic(
      kTelemetryCharacteristicUuid,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  operatingModeCharacteristic = service->createCharacteristic(
      kOperatingModeCharacteristicUuid,
      BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_WRITE |
          BLECharacteristic::PROPERTY_NOTIFY);

  telemetryCharacteristic->addDescriptor(new BLE2902());
  operatingModeCharacteristic->addDescriptor(new BLE2902());
  operatingModeCharacteristic->setAccessPermissions(
      ESP_GATT_PERM_READ | ESP_GATT_PERM_WRITE_ENCRYPTED);
  operatingModeCharacteristic->setCallbacks(new OperatingModeCallbacks());

  publishOperatingMode();
  service->start();

  BLEAdvertising* advertising = BLEDevice::getAdvertising();
  advertising->addServiceUUID(kServiceUuid);
  advertising->setScanResponse(true);
  advertising->setMinPreferred(0x06);
  advertising->setMaxPreferred(0x12);
  BLEDevice::startAdvertising();
  Serial.println("BLE advertising as FARO-Obstacle");
}
}  // namespace

void setup() {
  Serial.begin(115200);
  pinMode(kSonarTriggerPin, OUTPUT);
  pinMode(kSonarEchoPin, INPUT);
  pinMode(kBuzzerPin, OUTPUT);
  silenceBuzzer();

  pixel.begin();
  pixel.clear();
  pixel.show();

  // Explicit before BLE initialization: a reboot can never restore armed mode.
  operatingMode = faro::OperatingMode::Inactive;
  Serial.println("FARO ESP32 obstacle module");
  Serial.println("Mode: Inactive (buzzer disarmed)");
  Serial.println("HC-SR04: TRIG=GPIO25, ECHO=GPIO26 (level-shifted)");
  Serial.println("Passive buzzer: GPIO27");
  startBleServer();
}

void loop() {
  const unsigned long now = millis();
  updateBuzzer(latestDistanceCm, now);

  if (now - lastSampleAt < kSampleIntervalMillis) {
    delay(5);
    return;
  }
  lastSampleAt = now;

  const float rawDistanceCm = measureDistanceCm();
  addSample(rawDistanceCm);
  latestDistanceCm = rawDistanceCm < 0.0F ? -1.0F : filteredDistanceCm();

  showDistanceBand(latestDistanceCm);
  updateBuzzer(latestDistanceCm, now);
  publishTelemetry(latestDistanceCm);

  if (rawDistanceCm < 0.0F) {
    Serial.println("distance: no echo");
  } else {
    Serial.print("distance: ");
    Serial.print(latestDistanceCm, 1);
    Serial.println(" cm");
  }
}
