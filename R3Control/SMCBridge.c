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
