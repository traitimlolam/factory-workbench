#include "FactoryLicenseGate.h"
#include <string.h>

FactoryLicenseDecision factory_license_check(const char *device_udid,
    const char *allowed_udid, long long now, long long first_seen,
    long long trial_seconds, const char *kind) {
    if (!device_udid || !allowed_udid || !kind || !*allowed_udid ||
        now < 0 || first_seen < 0 ||
        (strcmp(kind, "trial") != 0 && strcmp(kind, "paid") != 0) ||
        (strcmp(kind, "trial") == 0 && trial_seconds <= 0))
        return (FactoryLicenseDecision){0, FACTORY_BLOCK_CONFIG};
    if (strcmp(device_udid, allowed_udid) != 0)
        return (FactoryLicenseDecision){0, FACTORY_BLOCK_UDID};
    /* Five minutes permits normal clock correction. Avoid signed overflow. */
    if (first_seen > 300 && now < first_seen - 300)
        return (FactoryLicenseDecision){0, FACTORY_BLOCK_CLOCK};
    if (strcmp(kind, "trial") == 0 && now >= first_seen &&
        now - first_seen >= trial_seconds)
        return (FactoryLicenseDecision){0, FACTORY_BLOCK_EXPIRED};
    return (FactoryLicenseDecision){1, FACTORY_ALLOW};
}
