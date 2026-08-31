#ifndef R3_SMC_BRIDGE_H
#define R3_SMC_BRIDGE_H

#include <stdbool.h>

bool R3SMCReadDouble(const char *key, double *value);
bool R3SMCReadUInt8(const char *key, unsigned char *value);
void R3SMCClose(void);

#endif
