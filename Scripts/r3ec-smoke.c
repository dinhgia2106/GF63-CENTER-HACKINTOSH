#include "../R3Control/SMCBridge.h"

#include <IOKit/IOReturn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static void print_status(const char *label, const R3ECStatus *status) {
    printf(
        "%s firmware=%s writable=%u capabilities=0x%02x temp=%uC "
        "fan=%u%% rpm=%u mode_raw=0x%02x boost=%u\n",
        label,
        status->firmware,
        status->writable,
        status->capabilities,
        status->cpuTemperature,
        status->fanPercent,
        status->fanRPM,
        status->fanModeRaw,
        status->coolerBoost
    );
}

static bool read_status(const char *label, R3ECStatus *status) {
    memset(status, 0, sizeof(*status));
    int32_t result = R3ECReadStatus(status);
    if (result != kIOReturnSuccess) {
        fprintf(stderr, "%s read failed: 0x%08x\n", label, result);
        return false;
    }
    print_status(label, status);
    return true;
}

int main(int argc, char **argv) {
    const bool testBasic = argc == 2 && strcmp(argv[1], "--test-basic") == 0;
    const bool testControls = argc == 2 && strcmp(argv[1], "--test-controls") == 0;
    if (argc > 2 || (argc == 2 && !testBasic && !testControls)) {
        fprintf(stderr, "usage: %s [--test-basic|--test-controls]\n", argv[0]);
        return 64;
    }

    R3ECStatus before = {0};
    if (!read_status("before", &before)) {
        R3ECClose();
        return 1;
    }
    if (!testBasic && !testControls) {
        R3ECClose();
        return 0;
    }

    if (!before.writable || strcmp(before.firmware, "16R3EMS1.102") != 0) {
        fprintf(stderr, "write test blocked: unexpected firmware or read-only bridge\n");
        R3ECClose();
        return 2;
    }

    int32_t result = R3ECApplyFixedFanSpeed(50);
    if (result != kIOReturnSuccess) {
        fprintf(stderr, "Basic 50%% failed: 0x%08x\n", result);
        R3ECRestoreAuto();
        R3ECClose();
        return 3;
    }

    sleep(1);
    R3ECStatus basic = {0};
    const bool basicRead = read_status("basic50", &basic);
    const bool basicVerified = basicRead && (basic.fanModeRaw & 0xFC) == 0x4C;

    bool advancedVerified = true;
    bool boostVerified = true;
    if (testControls && basicVerified) {
        const uint8_t temperatures[6] = {55, 64, 73, 76, 82, 88};
        const uint8_t speeds[6] = {38, 42, 45, 50, 55, 62};
        result = R3ECApplyFanCurveValues(temperatures, speeds);
        if (result != kIOReturnSuccess) {
            fprintf(stderr, "Advanced curve failed: 0x%08x\n", result);
            advancedVerified = false;
        } else {
            R3ECStatus advanced = {0};
            advancedVerified = read_status("advanced", &advanced) &&
                (advanced.fanModeRaw & 0xFC) == 0x8C;
        }

        result = R3ECApplyCoolerBoost(true);
        R3ECStatus boostOn = {0};
        boostVerified = result == kIOReturnSuccess && read_status("boost-on", &boostOn) &&
            boostOn.coolerBoost;
        result = R3ECApplyCoolerBoost(false);
        R3ECStatus boostOff = {0};
        boostVerified = boostVerified && result == kIOReturnSuccess &&
            read_status("boost-off", &boostOff) && !boostOff.coolerBoost;
    }

    result = R3ECRestoreAuto();
    if (result != kIOReturnSuccess) {
        fprintf(stderr, "restore Auto failed: 0x%08x\n", result);
        R3ECClose();
        return 4;
    }

    sleep(1);
    R3ECStatus after = {0};
    const bool afterRead = read_status("after", &after);
    const bool autoVerified = afterRead && (after.fanModeRaw & 0xFC) == 0x0C && !after.coolerBoost;
    R3ECClose();

    if (!basicVerified || !advancedVerified || !boostVerified || !autoVerified) {
        fprintf(stderr, "readback verification failed (basic=%d advanced=%d boost=%d auto=%d)\n",
                basicVerified, advancedVerified, boostVerified, autoVerified);
        return 5;
    }
    puts(testControls
        ? "PASS: Basic, Advanced curve and Cooler Boost were verified; Firmware Auto was restored."
        : "PASS: Basic 50% was verified and firmware Auto was restored.");
    return 0;
}
