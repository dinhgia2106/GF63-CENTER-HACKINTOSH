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
    IOReturn restoreFirmwareAuto();

private:
    IOACPIPlatformDevice *ecDevice { nullptr };
    IOLock *lock { nullptr };
    char firmware[16] {};
    bool firmwareAllowed { false };

    IOReturn readByte(uint8_t address, uint8_t *value);
    IOReturn writeByteVerified(uint8_t address, uint8_t value);
    IOReturn writeByteMaskedVerified(uint8_t address, uint8_t value, uint8_t mask);
    bool readFirmware();
    bool isAllowedFirmware() const;
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
};

#endif
