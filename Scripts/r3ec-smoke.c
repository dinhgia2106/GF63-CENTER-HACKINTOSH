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
        "fan=%u%% rpm=%u mode_raw=0x%02x boost=%u performance_raw=0x%02x\n",
        label,
        status->firmware,
        status->writable,
        status->capabilities,
        status->cpuTemperature,
        status->fanPercent,
        status->fanRPM,
        status->fanModeRaw,
        status->coolerBoost,
        status->performanceProfileRaw
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
    const bool testLiveControls = argc == 2 && strcmp(argv[1], "--test-live-controls") == 0;
    const bool testPerformance = argc == 2 && strcmp(argv[1], "--test-performance") == 0;
    if (argc > 2 || (argc == 2 && !testBasic && !testControls && !testLiveControls && !testPerformance)) {
        fprintf(stderr, "usage: %s [--test-basic|--test-controls|--test-live-controls|--test-performance]\n", argv[0]);
        return 64;
    }

    R3ECStatus before = {0};
    if (!read_status("before", &before)) {
        R3ECClose();
        return 1;
    }
    if (!testBasic && !testControls && !testLiveControls && !testPerformance) {
        R3ECClose();
        return 0;
    }

    if (!before.writable || strcmp(before.firmware, "16R3EMS1.102") != 0) {
        fprintf(stderr, "write test blocked: unexpected firmware or read-only bridge\n");
        R3ECClose();
        return 2;
    }

    if (testPerformance) {
        const uint8_t profiles[] = {
            R3ECPerformanceEco,
            R3ECPerformanceComfort,
            R3ECPerformanceSport,
            R3ECPerformanceTurbo,
            R3ECPerformanceComfort
        };
        const uint8_t expected[] = {0xC2, 0xC1, 0xC0, 0xC4, 0xC1};
        const char *labels[] = {"eco", "comfort", "sport", "turbo", "final-comfort"};
        bool verified = true;
        for (size_t index = 0; index < sizeof(profiles); ++index) {
            int32_t profileResult = R3ECApplyPerformanceProfile(profiles[index]);
            R3ECStatus status = {0};
            verified = verified && profileResult == kIOReturnSuccess &&
                read_status(labels[index], &status) && status.performanceProfileRaw == expected[index];
        }
        R3ECClose();
        if (!verified) {
            fputs("performance profile readback verification failed\n", stderr);
            return 6;
        }
        puts("PASS: Eco, Comfort, Sport and Turbo were verified; Comfort was restored.");
        return 0;
    }

    bool silentVerified = true;
    if (testControls) {
        int32_t silentResult = R3ECApplyFanMode(R3ECFanModeSilent);
        R3ECStatus silent = {0};
        silentVerified = silentResult == kIOReturnSuccess && read_status("silent", &silent) &&
            (silent.fanModeRaw & 0xFC) == 0x1C;
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

    bool boostVerified = true;
    if ((testControls || testLiveControls) && basicVerified) {
        result = R3ECApplyFanMode(R3ECFanModeAuto);
        if (result == kIOReturnSuccess) result = R3ECApplyCoolerBoost(true);
        R3ECStatus boostOn = {0};
        boostVerified = result == kIOReturnSuccess && read_status("boost-on", &boostOn) &&
            (boostOn.fanModeRaw & 0xFC) == 0x0C && boostOn.coolerBoost;
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

    if (!silentVerified || !basicVerified || !boostVerified || !autoVerified) {
        fprintf(stderr, "readback verification failed (silent=%d custom=%d boost=%d auto=%d)\n",
                silentVerified, basicVerified, boostVerified, autoVerified);
        return 5;
    }
    if (testControls) {
        puts("PASS: Silent, Custom and Boost were verified; Firmware Auto was restored.");
    } else if (testLiveControls) {
        puts("PASS: Custom and Boost were verified; Firmware Auto was restored.");
    } else {
        puts("PASS: Basic 50% was verified and firmware Auto was restored.");
    }
    return 0;
}
