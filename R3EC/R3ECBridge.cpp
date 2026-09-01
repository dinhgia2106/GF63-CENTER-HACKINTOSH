#include "R3ECBridge.hpp"
#include <IOKit/IOLib.h>
#include <libkern/c++/OSBoolean.h>
#include <libkern/c++/OSNumber.h>
#include <libkern/libkern.h>

#define super IOService
OSDefineMetaClassAndStructors(R3ECBridge, IOService)
#undef super

#define super IOUserClient
OSDefineMetaClassAndStructors(R3ECUserClient, IOUserClient)
#undef super

namespace {
constexpr uint32_t kProtocolVersion = 2;
constexpr uint8_t kFirmwareStart = 0xA0;
constexpr size_t kFirmwareLength = 12;
constexpr uint8_t kCPUCurrentTemperature = 0x68;
constexpr uint8_t kCPUFanPercent = 0x71;
constexpr uint8_t kCPUFanRPMHigh = 0xCC;
constexpr uint8_t kCPUFanRPMLow = 0xCD;
constexpr uint8_t kCPUCurveTemperatureStart = 0x6A;
constexpr uint8_t kCPUCurveSpeedStart = 0x72;
constexpr uint8_t kFanMode = 0xF4;
constexpr uint8_t kCoolerBoost = 0x98;
constexpr uint8_t kPerformanceProfile = 0xF2;
constexpr uint8_t kModeAuto = 0x0C;
constexpr uint8_t kModeSilent = 0x1C;
constexpr uint8_t kModeBasic = 0x4C;
constexpr uint8_t kModeAdvanced = 0x8C;
constexpr uint8_t kCoolerBoostMask = 0x80;
constexpr uint8_t kPerformanceEco = 0xC2;
constexpr uint8_t kPerformanceComfort = 0xC1;
constexpr uint8_t kPerformanceSport = 0xC0;
constexpr uint8_t kPerformanceTurbo = 0xC4;

bool equalFirmware(const char *lhs, const char *rhs) {
    return strncmp(lhs, rhs, 15) == 0;
}

}

bool R3ECBridge::start(IOService *provider) {
    if (!IOService::start(provider)) return false;
    ecDevice = OSDynamicCast(IOACPIPlatformDevice, provider);
    if (!ecDevice) return false;
    ecDevice->retain();

    lock = IOLockAlloc();
    if (!lock) return false;

    if (!readFirmware()) {
        IOLog("R3EC: could not read EC firmware; bridge stays read-only\n");
    }
    firmwareAllowed = isAllowedFirmware();
    setProperty("firmware", firmware);
    setProperty("writable", firmwareAllowed);
    setProperty("board", "MS-16R3");
    registerService();

    IOLog("R3EC: firmware %s, writes %s\n", firmware[0] ? firmware : "unknown",
          firmwareAllowed ? "enabled" : "blocked");
    return true;
}

void R3ECBridge::stop(IOService *provider) {
    if (firmwareAllowed) restoreFirmwareAuto();
    IOService::stop(provider);
}

void R3ECBridge::free() {
    if (lock) {
        IOLockFree(lock);
        lock = nullptr;
    }
    if (ecDevice) {
        ecDevice->release();
        ecDevice = nullptr;
    }
    IOService::free();
}

IOReturn R3ECBridge::newUserClient(task_t owningTask, void *securityID, UInt32 type,
                                   OSDictionary *properties, IOUserClient **handler) {
    if (!handler || type != 0) return kIOReturnBadArgument;
    *handler = nullptr;
    if (IOUserClient::clientHasPrivilege(securityID, kIOClientPrivilegeLocalUser) != kIOReturnSuccess) {
        return kIOReturnNotPrivileged;
    }

    auto client = OSTypeAlloc(R3ECUserClient);
    if (!client) return kIOReturnNoMemory;
    if (!client->initWithTask(owningTask, securityID, type, properties) || !client->attach(this) || !client->start(this)) {
        client->release();
        return kIOReturnError;
    }
    *handler = client;
    return kIOReturnSuccess;
}

IOReturn R3ECBridge::readByte(uint8_t address, uint8_t *value) {
    if (!value || !ecDevice) return kIOReturnNotReady;
    UInt64 raw = 0;
    IOACPIAddress acpiAddress {};
    acpiAddress.addr64 = address;
    IOReturn result = ecDevice->readAddressSpace(&raw, kIOACPIAddressSpaceIDEmbeddedController,
                                                 acpiAddress, 8);
    if (result == kIOReturnSuccess) *value = static_cast<uint8_t>(raw);
    return result;
}

IOReturn R3ECBridge::writeByteVerified(uint8_t address, uint8_t value) {
    if (!firmwareAllowed || !ecDevice) return kIOReturnNotPermitted;
    IOACPIAddress acpiAddress {};
    acpiAddress.addr64 = address;
    IOReturn result = ecDevice->writeAddressSpace(value, kIOACPIAddressSpaceIDEmbeddedController,
                                                  acpiAddress, 8);
    if (result != kIOReturnSuccess) return result;
    IOSleep(2);
    uint8_t actual = 0;
    result = readByte(address, &actual);
    if (result != kIOReturnSuccess) return result;
    return actual == value ? kIOReturnSuccess : kIOReturnIOError;
}

IOReturn R3ECBridge::writeByteMaskedVerified(uint8_t address, uint8_t value, uint8_t mask) {
    if (!firmwareAllowed || !ecDevice) return kIOReturnNotPermitted;
    uint8_t current = 0;
    IOReturn result = readByte(address, &current);
    if (result != kIOReturnSuccess) return result;
    const uint8_t next = static_cast<uint8_t>((current & ~mask) | (value & mask));
    IOACPIAddress acpiAddress {};
    acpiAddress.addr64 = address;
    result = ecDevice->writeAddressSpace(next, kIOACPIAddressSpaceIDEmbeddedController, acpiAddress, 8);
    if (result != kIOReturnSuccess) return result;
    IOSleep(2);
    uint8_t actual = 0;
    result = readByte(address, &actual);
    if (result != kIOReturnSuccess) return result;
    return (actual & mask) == (value & mask) ? kIOReturnSuccess : kIOReturnIOError;
}

bool R3ECBridge::readFirmware() {
    bzero(firmware, sizeof(firmware));
    for (size_t index = 0; index < kFirmwareLength; ++index) {
        uint8_t value = 0;
        if (readByte(static_cast<uint8_t>(kFirmwareStart + index), &value) != kIOReturnSuccess) return false;
        if (value < 0x20 || value > 0x7E) return false;
        firmware[index] = static_cast<char>(value);
    }
    return true;
}

bool R3ECBridge::isAllowedFirmware() const {
    return equalFirmware(firmware, "16R3EMS1.100") || equalFirmware(firmware, "16R3EMS1.102");
}

IOReturn R3ECBridge::getStatus(R3ECStatus *status) {
    if (!status) return kIOReturnBadArgument;
    IOLockLock(lock);
    bzero(status, sizeof(*status));
    status->protocolVersion = kProtocolVersion;
    status->capabilities = R3ECCapabilityTelemetry;
    if (firmwareAllowed) {
        status->capabilities |= R3ECCapabilityFanMode | R3ECCapabilityFixedFan |
            R3ECCapabilityFanCurve | R3ECCapabilityCoolerBoost |
            R3ECCapabilityPerformanceProfile;
    }
    strlcpy(status->firmware, firmware, sizeof(status->firmware));
    uint8_t rpmHigh = 0, rpmLow = 0, boost = 0;
    IOReturn result = readByte(kCPUCurrentTemperature, &status->cpuTemperature);
    if (result == kIOReturnSuccess) result = readByte(kCPUFanPercent, &status->fanPercent);
    if (result == kIOReturnSuccess) result = readByte(kCPUFanRPMHigh, &rpmHigh);
    if (result == kIOReturnSuccess) result = readByte(kCPUFanRPMLow, &rpmLow);
    if (result == kIOReturnSuccess) result = readByte(kFanMode, &status->fanModeRaw);
    if (result == kIOReturnSuccess) result = readByte(kCoolerBoost, &boost);
    if (result == kIOReturnSuccess) result = readByte(kPerformanceProfile, &status->performanceProfileRaw);
    const uint16_t rpmRaw = static_cast<uint16_t>((rpmHigh << 8) | rpmLow);
    status->fanRPM = rpmRaw == 0 ? 0 : static_cast<uint16_t>(478000u / rpmRaw);
    status->coolerBoost = (boost & kCoolerBoostMask) != 0;
    status->chargeLimit = 0;
    status->writable = firmwareAllowed;
    IOLockUnlock(lock);
    return result;
}

IOReturn R3ECBridge::setFanMode(uint8_t mode) {
    uint8_t raw = 0;
    switch (mode) {
        case R3ECFanModeAuto: raw = kModeAuto; break;
        case R3ECFanModeSilent: raw = kModeSilent; break;
        case R3ECFanModeBasic: raw = kModeBasic; break;
        case R3ECFanModeAdvanced: raw = kModeAdvanced; break;
        default: return kIOReturnBadArgument;
    }
    IOLockLock(lock);
    IOReturn result = writeByteMaskedVerified(kFanMode, raw, 0xFC);
    IOLockUnlock(lock);
    return result;
}

IOReturn R3ECBridge::setFixedFanSpeed(uint8_t percent) {
    if (percent < 35 || percent > 100) return kIOReturnBadArgument;
    IOLockLock(lock);
    IOReturn result = kIOReturnSuccess;
    for (uint8_t index = 0; index < 7 && result == kIOReturnSuccess; ++index) {
        result = writeByteVerified(static_cast<uint8_t>(kCPUCurveSpeedStart + index), percent);
    }
    if (result == kIOReturnSuccess) result = writeByteMaskedVerified(kFanMode, kModeBasic, 0xFC);
    if (result != kIOReturnSuccess) writeByteMaskedVerified(kFanMode, kModeAuto, 0xFC);
    IOLockUnlock(lock);
    return result;
}

IOReturn R3ECBridge::setCoolerBoost(bool enabled) {
    IOLockLock(lock);
    uint8_t current = 0;
    IOReturn result = readByte(kCoolerBoost, &current);
    if (result == kIOReturnSuccess) {
        const uint8_t next = enabled ? (current | kCoolerBoostMask) : (current & ~kCoolerBoostMask);
        result = writeByteVerified(kCoolerBoost, next);
    }
    IOLockUnlock(lock);
    return result;
}

IOReturn R3ECBridge::setChargeLimit(uint8_t percent) {
    (void)percent;
    return kIOReturnUnsupported;
}

IOReturn R3ECBridge::setFanCurve(const R3ECFanCurve *curve) {
    if (!curve) return kIOReturnBadArgument;
    for (size_t index = 0; index < 6; ++index) {
        if (curve->temperatures[index] < 45 || curve->temperatures[index] > 95 ||
            curve->speeds[index] < 35 || curve->speeds[index] > 100) return kIOReturnBadArgument;
        if (index > 0 && (curve->temperatures[index] <= curve->temperatures[index - 1] ||
                          curve->speeds[index] < curve->speeds[index - 1])) return kIOReturnBadArgument;
    }
    if (curve->speeds[5] < 62) return kIOReturnBadArgument;

    IOLockLock(lock);
    IOReturn result = kIOReturnSuccess;
    for (uint8_t index = 0; index < 6 && result == kIOReturnSuccess; ++index) {
        result = writeByteVerified(static_cast<uint8_t>(kCPUCurveTemperatureStart + index),
                                   curve->temperatures[index]);
    }
    if (result == kIOReturnSuccess) result = writeByteVerified(kCPUCurveSpeedStart, 35);
    for (uint8_t index = 0; index < 6 && result == kIOReturnSuccess; ++index) {
        result = writeByteVerified(static_cast<uint8_t>(kCPUCurveSpeedStart + index + 1),
                                   curve->speeds[index]);
    }
    if (result == kIOReturnSuccess) result = writeByteMaskedVerified(kFanMode, kModeAdvanced, 0xFC);
    if (result != kIOReturnSuccess) writeByteMaskedVerified(kFanMode, kModeAuto, 0xFC);
    IOLockUnlock(lock);
    return result;
}

IOReturn R3ECBridge::setPerformanceProfile(uint8_t profile) {
    uint8_t raw = 0;
    switch (profile) {
        case R3ECPerformanceEco: raw = kPerformanceEco; break;
        case R3ECPerformanceComfort: raw = kPerformanceComfort; break;
        case R3ECPerformanceSport: raw = kPerformanceSport; break;
        case R3ECPerformanceTurbo: raw = kPerformanceTurbo; break;
        default: return kIOReturnBadArgument;
    }
    IOLockLock(lock);
    IOReturn result = writeByteVerified(kPerformanceProfile, raw);
    IOLockUnlock(lock);
    return result;
}

IOReturn R3ECBridge::restoreFirmwareAuto() {
    IOLockLock(lock);
    uint8_t boost = 0;
    IOReturn result = readByte(kCoolerBoost, &boost);
    if (result == kIOReturnSuccess) result = writeByteVerified(kCoolerBoost, boost & ~kCoolerBoostMask);
    if (result == kIOReturnSuccess) result = writeByteMaskedVerified(kFanMode, kModeAuto, 0xFC);
    IOLockUnlock(lock);
    return result;
}

bool R3ECUserClient::initWithTask(task_t owningTask, void *securityID, UInt32 type,
                                  OSDictionary *properties) {
    return IOUserClient::initWithTask(owningTask, securityID, type, properties);
}

bool R3ECUserClient::start(IOService *provider) {
    bridge = OSDynamicCast(R3ECBridge, provider);
    if (!bridge || !IOUserClient::start(provider)) return false;
    bridge->retain();
    return true;
}

IOReturn R3ECUserClient::clientClose() {
    if (changedHardware && bridge) bridge->restoreFirmwareAuto();
    if (changedPerformance && bridge) bridge->setPerformanceProfile(R3ECPerformanceComfort);
    if (bridge) {
        bridge->release();
        bridge = nullptr;
    }
    terminate();
    return kIOReturnSuccess;
}

IOReturn R3ECUserClient::externalMethod(uint32_t selector, IOExternalMethodArguments *arguments,
                                        IOExternalMethodDispatch *, OSObject *, void *) {
    if (!bridge || !arguments) return kIOReturnNotAttached;
    IOReturn result = kIOReturnUnsupported;
    switch (selector) {
        case R3ECGetStatus:
            if (!arguments->structureOutput || arguments->structureOutputSize < sizeof(R3ECStatus)) return kIOReturnNoSpace;
            result = bridge->getStatus(static_cast<R3ECStatus *>(arguments->structureOutput));
            if (result == kIOReturnSuccess) arguments->structureOutputSize = sizeof(R3ECStatus);
            return result;
        case R3ECSetFanMode:
            if (arguments->scalarInputCount != 1) return kIOReturnBadArgument;
            result = bridge->setFanMode(static_cast<uint8_t>(arguments->scalarInput[0]));
            break;
        case R3ECSetFixedFanSpeed:
            if (arguments->scalarInputCount != 1) return kIOReturnBadArgument;
            result = bridge->setFixedFanSpeed(static_cast<uint8_t>(arguments->scalarInput[0]));
            break;
        case R3ECSetCoolerBoost:
            if (arguments->scalarInputCount != 1) return kIOReturnBadArgument;
            result = bridge->setCoolerBoost(arguments->scalarInput[0] != 0);
            break;
        case R3ECSetChargeLimit:
            if (arguments->scalarInputCount != 1) return kIOReturnBadArgument;
            result = bridge->setChargeLimit(static_cast<uint8_t>(arguments->scalarInput[0]));
            break;
        case R3ECSetFanCurve:
            if (!arguments->structureInput || arguments->structureInputSize != sizeof(R3ECFanCurve)) return kIOReturnBadArgument;
            result = bridge->setFanCurve(static_cast<const R3ECFanCurve *>(arguments->structureInput));
            break;
        case R3ECRestoreFirmwareAuto:
            result = bridge->restoreFirmwareAuto();
            break;
        case R3ECSetPerformanceProfile:
            if (arguments->scalarInputCount != 1) return kIOReturnBadArgument;
            result = bridge->setPerformanceProfile(static_cast<uint8_t>(arguments->scalarInput[0]));
            break;
        default:
            return kIOReturnUnsupported;
    }
    if (result == kIOReturnSuccess) {
        if (selector == R3ECSetPerformanceProfile) changedPerformance = true;
        else if (selector == R3ECRestoreFirmwareAuto) changedHardware = false;
        else changedHardware = true;
    }
    return result;
}
