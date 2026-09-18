// FARO ESP32 distance-feedback bench proof of concept.
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
// This is a bench hardware bring-up only. kBenchBuzzerEnabled is deliberately
// true to validate the passive buzzer. Production FARO must boot Inactive and
// remain silent until Navigating mode is explicitly armed.

#include <Adafruit_NeoPixel.h>

namespace {
constexpr uint8_t kSonarTriggerPin = 25;
constexpr uint8_t kSonarEchoPin = 26;
constexpr uint8_t kLedPin = 2;
constexpr uint8_t kLedCount = 1;
constexpr uint8_t kBuzzerPin = 27;
constexpr bool kBenchBuzzerEnabled = true;

constexpr unsigned long kEchoTimeoutMicros = 25000;
constexpr unsigned long kSampleIntervalMillis = 100;
constexpr size_t kSampleCount = 5;

constexpr float kNearDistanceCm = 50.0F;
constexpr float kMediumDistanceCm = 100.0F;
constexpr float kFarDistanceCm = 200.0F;

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
float samples[kSampleCount] = {};
size_t sampleIndex = 0;
size_t samplesCollected = 0;
float latestDistanceCm = -1.0F;
unsigned long lastSampleAt = 0;
unsigned long buzzerPatternStartedAt = 0;
bool buzzerIsOn = false;
unsigned int activeBuzzerFrequencyHz = 0;

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
    setLed(128, 0, 128); // Purple: no valid echo received.
  } else if (distanceCm < kNearDistanceCm) {
    setLed(255, 0, 0); // Red: under 0.5 m.
  } else if (distanceCm < kMediumDistanceCm) {
    setLed(255, 128, 0); // Amber: 0.5–1 m.
  } else if (distanceCm < kFarDistanceCm) {
    setLed(0, 0, 255); // Blue: 1–2 m.
  } else {
    setLed(0, 0, 0); // Off: over 2 m.
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

bool patternsMatch(const BuzzerPattern &left, const BuzzerPattern &right) {
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
      kBenchBuzzerEnabled ? patternForDistance(distanceCm) : kSilentPattern;
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
} // namespace

void setup() {
  Serial.begin(115200);
  pinMode(kSonarTriggerPin, OUTPUT);
  pinMode(kSonarEchoPin, INPUT);
  pinMode(kBuzzerPin, OUTPUT);
  silenceBuzzer();

  pixel.begin();
  pixel.clear();
  pixel.show();

  Serial.println("FARO ESP32 distance-feedback bench POC");
  Serial.println("HC-SR04: TRIG=GPIO25, ECHO=GPIO26 (level-shifted)");
  Serial.println("Passive buzzer: GPIO27");
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

  if (rawDistanceCm < 0.0F) {
    Serial.println("distance: no echo");
  } else {
    Serial.print("distance: ");
    Serial.print(latestDistanceCm, 1);
    Serial.println(" cm");
  }
}
