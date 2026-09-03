/*
 * Minimal read-only AppleSMC bridge.
 * The public AppleSMC structure layout follows the long-standing smcFanControl
 * implementation (GPL-2.0-or-later). This bridge intentionally contains no
 * write operation.
 */

#include "SMCBridge.h"
#include <IOKit/IOKitLib.h>
#include <libkern/OSByteOrder.h>
#include <pthread.h>
#include <stddef.h>
#include <string.h>

#define R3_SMC_SELECTOR 2
#define R3_SMC_READ_BYTES 5
#define R3_SMC_READ_KEYINFO 9

typedef struct {
    char major;
    char minor;
    char build;
    char reserved;
    uint16_t release;
} R3SMCVersion;

typedef struct {
    uint16_t version;
    uint16_t length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} R3SMCPLimit;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    char dataAttributes;
} R3SMCKeyInfo;

typedef struct {
    uint32_t key;
    R3SMCVersion vers;
    R3SMCPLimit pLimitData;
    R3SMCKeyInfo keyInfo;
    char result;
    char status;
    char data8;
    uint32_t data32;
    unsigned char bytes[32];
} R3SMCKeyData;

typedef struct {
    char type[5];
    uint32_t size;
    unsigned char bytes[32];
} R3SMCValue;

static io_connect_t r3Connection = IO_OBJECT_NULL;
static pthread_mutex_t r3Lock = PTHREAD_MUTEX_INITIALIZER;
static io_connect_t r3ECConnection = IO_OBJECT_NULL;
static pthread_mutex_t r3ECLock = PTHREAD_MUTEX_INITIALIZER;

static uint32_t r3FourCC(const char *text) {
    return ((uint32_t)(unsigned char)text[0] << 24) |
           ((uint32_t)(unsigned char)text[1] << 16) |
           ((uint32_t)(unsigned char)text[2] << 8) |
           (uint32_t)(unsigned char)text[3];
}

static void r3FourCCString(uint32_t value, char output[5]) {
    output[0] = (char)(value >> 24);
    output[1] = (char)(value >> 16);
    output[2] = (char)(value >> 8);
    output[3] = (char)value;
    output[4] = '\0';
}

static bool r3Open(void) {
    if (r3Connection != IO_OBJECT_NULL) return true;

    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (service == IO_OBJECT_NULL) return false;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &r3Connection);
    IOObjectRelease(service);
    return result == KERN_SUCCESS;
}

static bool r3Call(R3SMCKeyData *input, R3SMCKeyData *output) {
    size_t outputSize = sizeof(*output);
    kern_return_t result = IOConnectCallStructMethod(
        r3Connection,
        R3_SMC_SELECTOR,
        input,
        sizeof(*input),
        output,
        &outputSize
    );
    return result == KERN_SUCCESS;
}

static bool r3Read(const char *key, R3SMCValue *value) {
    if (!key || strlen(key) != 4 || !r3Open()) return false;

    R3SMCKeyData input = {0};
    R3SMCKeyData output = {0};
    input.key = r3FourCC(key);
    input.data8 = R3_SMC_READ_KEYINFO;
    if (!r3Call(&input, &output) || output.keyInfo.dataSize == 0 || output.keyInfo.dataSize > 32) return false;

    value->size = output.keyInfo.dataSize;
    r3FourCCString(output.keyInfo.dataType, value->type);

    memset(&input, 0, sizeof(input));
    memset(&output, 0, sizeof(output));
    input.key = r3FourCC(key);
    input.keyInfo.dataSize = value->size;
    input.data8 = R3_SMC_READ_BYTES;
    if (!r3Call(&input, &output)) return false;
    memcpy(value->bytes, output.bytes, value->size);
    return true;
}

static double r3DecodeFixed(const R3SMCValue *value, int fractionBits, bool signedValue) {
    uint16_t raw = ((uint16_t)value->bytes[0] << 8) | value->bytes[1];
    if (signedValue) return (double)(int16_t)raw / (double)(1 << fractionBits);
    return (double)raw / (double)(1 << fractionBits);
}

bool R3SMCReadDouble(const char *key, double *result) {
    if (!result) return false;
    pthread_mutex_lock(&r3Lock);
    R3SMCValue value = {0};
    bool success = r3Read(key, &value);
    if (success) {
        if (!strcmp(value.type, "sp78") && value.size == 2) *result = r3DecodeFixed(&value, 8, true);
        else if (!strcmp(value.type, "sp96") && value.size == 2) *result = r3DecodeFixed(&value, 6, true);
        else if (!strcmp(value.type, "fpe2") && value.size == 2) *result = r3DecodeFixed(&value, 2, false);
        else if (!strcmp(value.type, "ui8 ") && value.size == 1) *result = value.bytes[0];
        else if (!strcmp(value.type, "ui16") && value.size == 2) *result = ((uint16_t)value.bytes[0] << 8) | value.bytes[1];
        else if (!strcmp(value.type, "flt ") && value.size == 4) {
            float decoded = 0;
            memcpy(&decoded, value.bytes, sizeof(decoded));
            *result = decoded;
        } else success = false;
    }
    pthread_mutex_unlock(&r3Lock);
    return success;
}

bool R3SMCReadUInt8(const char *key, unsigned char *result) {
    if (!result) return false;
    pthread_mutex_lock(&r3Lock);
    R3SMCValue value = {0};
    bool success = r3Read(key, &value) && value.size == 1;
    if (success) *result = value.bytes[0];
    pthread_mutex_unlock(&r3Lock);
    return success;
}

void R3SMCClose(void) {
    pthread_mutex_lock(&r3Lock);
    if (r3Connection != IO_OBJECT_NULL) {
        IOServiceClose(r3Connection);
        r3Connection = IO_OBJECT_NULL;
    }
    pthread_mutex_unlock(&r3Lock);
}

static kern_return_t r3ECOpenLocked(void) {
    if (r3ECConnection != IO_OBJECT_NULL) return KERN_SUCCESS;
    io_service_t service = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching(R3_EC_SERVICE_NAME)
    );
    if (service == IO_OBJECT_NULL) return kIOReturnNotFound;
    kern_return_t result = IOServiceOpen(service, mach_task_self(), 0, &r3ECConnection);
    IOObjectRelease(service);
    return result;
}

bool R3ECIsAvailable(void) {
    pthread_mutex_lock(&r3ECLock);
    bool available = r3ECOpenLocked() == KERN_SUCCESS;
    pthread_mutex_unlock(&r3ECLock);
    return available;
}

int32_t R3ECReadStatus(R3ECStatus *status) {
    if (!status) return kIOReturnBadArgument;
    memset(status, 0, sizeof(*status));
    pthread_mutex_lock(&r3ECLock);
    kern_return_t result = r3ECOpenLocked();
    if (result == KERN_SUCCESS) {
        size_t outputSize = sizeof(*status);
        result = IOConnectCallStructMethod(
            r3ECConnection,
            R3ECGetStatus,
            NULL,
            0,
            status,
            &outputSize
        );
        const size_t version1Size = offsetof(R3ECStatus, performanceProfileRaw);
        const size_t version2Size = offsetof(R3ECStatus, packagePowerLimit1Deciwatts);
        if (result == KERN_SUCCESS && outputSize != sizeof(*status) &&
            outputSize != version1Size && outputSize != version2Size) {
            result = kIOReturnBadMessageID;
        }
    }
    pthread_mutex_unlock(&r3ECLock);
    return result;
}

static int32_t r3ECScalarCall(uint32_t selector, uint64_t value) {
    pthread_mutex_lock(&r3ECLock);
    kern_return_t result = r3ECOpenLocked();
    if (result == KERN_SUCCESS) {
        result = IOConnectCallScalarMethod(r3ECConnection, selector, &value, 1, NULL, NULL);
    }
    pthread_mutex_unlock(&r3ECLock);
    return result;
}

int32_t R3ECApplyFanMode(uint8_t mode) {
    return r3ECScalarCall(R3ECSetFanMode, mode);
}

int32_t R3ECApplyFixedFanSpeed(uint8_t percent) {
    return r3ECScalarCall(R3ECSetFixedFanSpeed, percent);
}

int32_t R3ECApplyCoolerBoost(bool enabled) {
    return r3ECScalarCall(R3ECSetCoolerBoost, enabled ? 1 : 0);
}

int32_t R3ECApplyChargeLimit(uint8_t percent) {
    return r3ECScalarCall(R3ECSetChargeLimit, percent);
}

int32_t R3ECApplyPerformanceProfile(uint8_t profile) {
    return r3ECScalarCall(R3ECSetPerformanceProfile, profile);
}

int32_t R3ECApplyEcoPlus(bool enabled) {
    return r3ECScalarCall(R3ECSetEcoPlus, enabled ? 1 : 0);
}

int32_t R3ECApplyFanCurve(const R3ECFanCurve *curve) {
    if (!curve) return kIOReturnBadArgument;
    pthread_mutex_lock(&r3ECLock);
    kern_return_t result = r3ECOpenLocked();
    if (result == KERN_SUCCESS) {
        result = IOConnectCallStructMethod(
            r3ECConnection,
            R3ECSetFanCurve,
            curve,
            sizeof(*curve),
            NULL,
            NULL
        );
    }
    pthread_mutex_unlock(&r3ECLock);
    return result;
}

int32_t R3ECApplyFanCurveValues(const uint8_t temperatures[6], const uint8_t speeds[6]) {
    if (!temperatures || !speeds) return kIOReturnBadArgument;
    R3ECFanCurve curve = {0};
    memcpy(curve.temperatures, temperatures, sizeof(curve.temperatures));
    memcpy(curve.speeds, speeds, sizeof(curve.speeds));
    return R3ECApplyFanCurve(&curve);
}

int32_t R3ECRestoreAuto(void) {
    pthread_mutex_lock(&r3ECLock);
    kern_return_t result = r3ECOpenLocked();
    if (result == KERN_SUCCESS) {
        result = IOConnectCallScalarMethod(
            r3ECConnection,
            R3ECRestoreFirmwareAuto,
            NULL,
            0,
            NULL,
            NULL
        );
    }
    pthread_mutex_unlock(&r3ECLock);
    return result;
}

void R3ECClose(void) {
    pthread_mutex_lock(&r3ECLock);
    if (r3ECConnection != IO_OBJECT_NULL) {
        IOServiceClose(r3ECConnection);
        r3ECConnection = IO_OBJECT_NULL;
    }
    pthread_mutex_unlock(&r3ECLock);
}
