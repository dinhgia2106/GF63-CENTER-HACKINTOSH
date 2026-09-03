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
        "fan=%u%% rpm=%u mode_raw=0x%02x boost=%u performance_raw=0x%02x "
        "pl1=%.1fW pl2=%.1fW eco_plus=%u power_locked=%u charge_limit=%u%% "
        "battery_direct=%u battery=%u/%u cycle_valid=%u cycle=%u state=0x%x rate=%u voltage=%u\n",
        label,
        status->firmware,
        status->writable,
        status->capabilities,
        status->cpuTemperature,
        status->fanPercent,
        status->fanRPM,
        status->fanModeRaw,
        status->coolerBoost,
        status->performanceProfileRaw,
        status->packagePowerLimit1Deciwatts / 10.0,
        status->packagePowerLimit2Deciwatts / 10.0,
        status->ecoPlusActive,
        status->powerLimitLocked,
        status->chargeLimit,
        status->batteryDataValid,
        status->batteryRemainingCapacity,
        status->batteryLastFullChargeCapacity,
        status->batteryCycleCountValid,
        status->batteryCycleCount,
        status->batteryState,
        status->batteryPresentRate,
        status->batteryPresentVoltage
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
    const bool testEcoPlus = argc == 2 && strcmp(argv[1], "--test-eco-plus") == 0;
    const bool testCharge = argc == 2 && strcmp(argv[1], "--test-charge") == 0;
    if (argc > 2 || (argc == 2 && !testBasic && !testControls && !testLiveControls &&
                    !testPerformance && !testEcoPlus && !testCharge)) {
        fprintf(stderr, "usage: %s [--test-basic|--test-controls|--test-live-controls|--test-performance|--test-eco-plus|--test-charge]\n", argv[0]);
        return 64;
    }

    R3ECStatus before = {0};
    if (!read_status("before", &before)) {
        R3ECClose();
        return 1;
    }
    if (!testBasic && !testControls && !testLiveControls && !testPerformance && !testEcoPlus && !testCharge) {
        R3ECClose();
        return 0;
    }

    if (!before.writable || strcmp(before.firmware, "16R3EMS1.102") != 0) {
        fprintf(stderr, "write test blocked: unexpected firmware or read-only bridge\n");
        R3ECClose();
        return 2;
    }

    if (testCharge) {
        if (!(before.capabilities & R3ECCapabilityChargeLimit)) {
            fputs("charge-limit test blocked: bridge did not advertise charge control\n", stderr);
            R3ECClose();
            return 9;
        }
        if (before.chargeLimit != 60 && before.chargeLimit != 80 && before.chargeLimit != 100) {
            int32_t initializeResult = R3ECApplyChargeLimit(80);
            R3ECStatus initialized = {0};
            const bool initializedVerified = initializeResult == kIOReturnSuccess &&
                read_status("charge-initialized", &initialized) && initialized.chargeLimit == 80;
            R3ECClose();
            if (!initializedVerified) {
                fputs("charge-limit initialization/readback failed\n", stderr);
                return 10;
            }
            puts("PASS: uninitialized charge threshold was set to the Balanced 80% preset and verified.");
            return 0;
        }
        const uint8_t presets[] = {60, 80, 100};
        bool changedVerified = true;
        for (size_t index = 0; index < sizeof(presets) / sizeof(presets[0]); ++index) {
            int32_t chargeResult = R3ECApplyChargeLimit(presets[index]);
            R3ECStatus changed = {0};
            changedVerified = changedVerified && chargeResult == kIOReturnSuccess &&
                read_status("charge-test", &changed) && changed.chargeLimit == presets[index];
        }
        int32_t restoreResult = R3ECApplyChargeLimit(before.chargeLimit);
        R3ECStatus restored = {0};
        const bool restoredVerified = restoreResult == kIOReturnSuccess &&
            read_status("charge-restored", &restored) && restored.chargeLimit == before.chargeLimit;
        R3ECClose();
        if (!changedVerified || !restoredVerified) {
            fprintf(stderr, "charge-limit verification failed (changed=%d restored=%d)\n",
                    changedVerified, restoredVerified);
            return 10;
        }
        puts("PASS: 60%, 80% and 100% were read back; the original charge limit was restored.");
        return 0;
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

    if (testEcoPlus) {
        if (before.protocolVersion < 3 || before.powerLimitLocked ||
            !(before.capabilities & R3ECCapabilityEcoPlus)) {
            fputs("Eco+ is unavailable or package power limits are locked\n", stderr);
            R3ECClose();
            return 7;
        }
        int32_t ecoResult = R3ECApplyPerformanceProfile(R3ECPerformanceEco);
        if (ecoResult == kIOReturnSuccess) ecoResult = R3ECApplyCoolerBoost(false);
        if (ecoResult == kIOReturnSuccess) ecoResult = R3ECApplyFanMode(R3ECFanModeAuto);
        if (ecoResult == kIOReturnSuccess) ecoResult = R3ECApplyEcoPlus(true);
        R3ECStatus limited = {0};
        const bool limitedVerified = ecoResult == kIOReturnSuccess &&
            read_status("eco-plus", &limited) && limited.performanceProfileRaw == 0xC2 &&
            (limited.fanModeRaw & 0xFC) == 0x0C && !limited.coolerBoost &&
            limited.ecoPlusActive && limited.packagePowerLimit1Deciwatts == 150 &&
            limited.packagePowerLimit2Deciwatts == 250;

        int32_t restoreResult = R3ECApplyEcoPlus(false);
        if (restoreResult == kIOReturnSuccess) {
            restoreResult = R3ECApplyPerformanceProfile(R3ECPerformanceComfort);
        }
        R3ECStatus restored = {0};
        const bool restoreVerified = restoreResult == kIOReturnSuccess &&
            read_status("restored", &restored) && !restored.ecoPlusActive &&
            restored.performanceProfileRaw == 0xC1 &&
            restored.packagePowerLimit1Deciwatts == before.packagePowerLimit1Deciwatts &&
            restored.packagePowerLimit2Deciwatts == before.packagePowerLimit2Deciwatts;
        R3ECRestoreAuto();
        R3ECClose();
        if (!limitedVerified || !restoreVerified) {
            fprintf(stderr, "Eco+ verification failed (limited=%d restored=%d)\n",
                    limitedVerified, restoreVerified);
            return 8;
        }
        puts("PASS: Eco+ 15W/25W was verified and original limits were restored with Comfort/Auto.");
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
