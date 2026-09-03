#ifndef R3_EC_SHARED_H
#define R3_EC_SHARED_H

#include <stdint.h>

#define R3_EC_SERVICE_NAME "R3ECBridge"

enum R3ECSelector : uint32_t {
    R3ECGetStatus = 0,
    R3ECSetFanMode = 1,
    R3ECSetFixedFanSpeed = 2,
    R3ECSetCoolerBoost = 3,
    R3ECSetChargeLimit = 4,
    R3ECSetFanCurve = 5,
    R3ECRestoreFirmwareAuto = 6,
    R3ECSetPerformanceProfile = 7,
    R3ECSetEcoPlus = 8,
    R3ECSelectorCount
};

enum R3ECFanMode : uint8_t {
    R3ECFanModeAuto = 0,
    R3ECFanModeSilent = 1,
    R3ECFanModeBasic = 2,
    R3ECFanModeAdvanced = 3
};

enum R3ECPerformanceProfile : uint8_t {
    R3ECPerformanceEco = 0,
    R3ECPerformanceComfort = 1,
    R3ECPerformanceSport = 2,
    R3ECPerformanceTurbo = 3
};

enum R3ECCapability : uint32_t {
    R3ECCapabilityTelemetry = 1u << 0,
    R3ECCapabilityFanMode = 1u << 1,
    R3ECCapabilityFixedFan = 1u << 2,
    R3ECCapabilityFanCurve = 1u << 3,
    R3ECCapabilityCoolerBoost = 1u << 4,
    R3ECCapabilityChargeLimit = 1u << 5,
    R3ECCapabilityPerformanceProfile = 1u << 6,
    R3ECCapabilityEcoPlus = 1u << 7,
    R3ECCapabilityDirectBattery = 1u << 8
};

typedef struct __attribute__((packed)) {
    uint32_t protocolVersion;
    uint32_t capabilities;
    char firmware[16];
    uint8_t cpuTemperature;
    uint8_t fanPercent;
    uint16_t fanRPM;
    uint8_t fanModeRaw;
    uint8_t coolerBoost;
    uint8_t chargeLimit;
    uint8_t writable;
    uint8_t performanceProfileRaw;
    uint16_t packagePowerLimit1Deciwatts;
    uint16_t packagePowerLimit2Deciwatts;
    uint8_t ecoPlusActive;
    uint8_t powerLimitLocked;
    uint8_t batteryDataValid;
    uint8_t batteryPowerUnit;
    uint16_t batteryCycleCount;
    uint32_t batteryDesignCapacity;
    uint32_t batteryLastFullChargeCapacity;
    uint32_t batteryRemainingCapacity;
    uint32_t batteryPresentRate;
    uint32_t batteryPresentVoltage;
    uint32_t batteryState;
    uint8_t batteryCycleCountValid;
} R3ECStatus;

typedef struct __attribute__((packed)) {
    uint8_t temperatures[6];
    uint8_t speeds[6];
} R3ECFanCurve;

#endif
