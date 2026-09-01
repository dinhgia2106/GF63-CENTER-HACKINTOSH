#ifndef R3_SMC_BRIDGE_H
#define R3_SMC_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>
#include "../R3EC/R3ECShared.h"

bool R3SMCReadDouble(const char *key, double *value);
bool R3SMCReadUInt8(const char *key, unsigned char *value);
void R3SMCClose(void);

bool R3ECIsAvailable(void);
int32_t R3ECReadStatus(R3ECStatus *status);
int32_t R3ECApplyFanMode(uint8_t mode);
int32_t R3ECApplyFixedFanSpeed(uint8_t percent);
int32_t R3ECApplyCoolerBoost(bool enabled);
int32_t R3ECApplyPerformanceProfile(uint8_t profile);
int32_t R3ECApplyFanCurve(const R3ECFanCurve *curve);
int32_t R3ECApplyFanCurveValues(const uint8_t temperatures[6], const uint8_t speeds[6]);
int32_t R3ECRestoreAuto(void);
void R3ECClose(void);

#endif
