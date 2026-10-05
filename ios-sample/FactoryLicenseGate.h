#ifndef FACTORY_LICENSE_GATE_H
#define FACTORY_LICENSE_GATE_H

typedef enum {
    FACTORY_ALLOW = 0,
    FACTORY_BLOCK_UDID,
    FACTORY_BLOCK_CLOCK,
    FACTORY_BLOCK_EXPIRED,
    FACTORY_BLOCK_CONFIG
} FactoryLicenseReason;

typedef struct {
    int allowed;
    FactoryLicenseReason reason;
} FactoryLicenseDecision;

#ifdef __cplusplus
extern "C" {
#endif

/* Pure function: timestamps are Unix seconds; first_seen comes from the caller's store. */
FactoryLicenseDecision factory_license_check(const char *device_udid,
    const char *allowed_udid, long long now, long long first_seen,
    long long trial_seconds, const char *kind);

#ifdef __cplusplus
}
#endif
#endif
