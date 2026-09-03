#ifndef R3_EC_BRIDGE_HPP
#define R3_EC_BRIDGE_HPP

#include <IOKit/IOService.h>
#include <IOKit/IOUserClient.h>
#include <IOKit/IOLocks.h>
#include <IOKit/acpi/IOACPIPlatformDevice.h>
#include "R3ECShared.h"

class R3ECBridge : public IOService {
    OSDeclareDefaultStructors(R3ECBridge)

public:
    bool start(IOService *provider) override;
    void stop(IOService *provider) override;
    void free() override;
    IOReturn newUserClient(task_t owningTask, void *securityID, UInt32 type,
                           OSDictionary *properties, IOUserClient **handler) override;

    IOReturn getStatus(R3ECStatus *status);
    IOReturn setFanMode(uint8_t mode);
    IOReturn setFixedFanSpeed(uint8_t percent);
    IOReturn setCoolerBoost(bool enabled);
    IOReturn setChargeLimit(uint8_t percent);
    IOReturn setFanCurve(const R3ECFanCurve *curve);
    IOReturn setPerformanceProfile(uint8_t profile);
    IOReturn setEcoPlus(bool enabled);
    IOReturn restoreFirmwareAuto();

private:
    IOACPIPlatformDevice *ecDevice { nullptr };
    IOACPIPlatformDevice *batteryDevice { nullptr };
    IOLock *lock { nullptr };
    char firmware[16] {};
    bool firmwareAllowed { false };
    bool powerLimitCaptured { false };
    bool ecoPlusActive { false };
    uint64_t originalPackagePowerLimit { 0 };
    uint8_t batteryRefreshCountdown { 0 };
    bool batteryDataValid { false };
    uint8_t batteryPowerUnit { 0 };
    bool batteryCycleCountValid { false };
    uint16_t batteryCycleCount { 0 };
    uint32_t batteryDesignCapacity { 0 };
    uint32_t batteryLastFullChargeCapacity { 0 };
    uint32_t batteryRemainingCapacity { 0 };
    uint32_t batteryPresentRate { 0 };
    uint32_t batteryPresentVoltage { 0 };
    uint32_t batteryState { 0 };

    IOReturn readByte(uint8_t address, uint8_t *value);
    IOReturn writeByteVerified(uint8_t address, uint8_t value);
    IOReturn writeByteMaskedVerified(uint8_t address, uint8_t value, uint8_t mask);
    IOReturn readPackagePowerLimits(uint16_t *pl1Deciwatts, uint16_t *pl2Deciwatts,
                                    bool *locked);
    bool readFirmware();
    bool isAllowedFirmware() const;
    bool locateBattery();
    bool readDirectBattery();
};

class R3ECUserClient : public IOUserClient {
    OSDeclareDefaultStructors(R3ECUserClient)

public:
    bool initWithTask(task_t owningTask, void *securityID, UInt32 type,
                      OSDictionary *properties) override;
    bool start(IOService *provider) override;
    IOReturn clientClose() override;
    IOReturn externalMethod(uint32_t selector, IOExternalMethodArguments *arguments,
                            IOExternalMethodDispatch *dispatch = nullptr,
                            OSObject *target = nullptr, void *reference = nullptr) override;

private:
    R3ECBridge *bridge { nullptr };
    bool changedHardware { false };
    bool changedPerformance { false };
    bool changedEcoPlus { false };
};

#endif
