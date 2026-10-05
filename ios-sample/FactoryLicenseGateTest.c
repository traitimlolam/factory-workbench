#include "FactoryLicenseGate.h"
#include <stdio.h>

static int test(const char *name, const char *actual, const char *allowed,
                long long now, long long first, long long seconds, const char *kind,
                int want_allowed, FactoryLicenseReason want_reason) {
    FactoryLicenseDecision result = factory_license_check(actual, allowed, now, first, seconds, kind);
    int ok = result.allowed == want_allowed && result.reason == want_reason;
    printf("%s=%s\n", name, ok ? "PASS" : "FAIL");
    return ok;
}

int main(void) {
    const char *id = "00008110-001234567890001E";
    int ok = 1;
    ok &= test("dung_udid", id, id, 1000, 1000, 3600, "trial", 1, FACTORY_ALLOW);
    ok &= test("sai_udid", "00008110-001234567890001F", id, 1000, 1000, 3600, "trial", 0, FACTORY_BLOCK_UDID);
    ok &= test("trial_het_1_gio", id, id, 4600, 1000, 3600, "trial", 0, FACTORY_BLOCK_EXPIRED);
    ok &= test("chinh_dong_ho_lui", id, id, 600, 1000, 3600, "trial", 0, FACTORY_BLOCK_CLOCK);
    ok &= test("paid_khong_het_han", id, id, 999999999, 1000, 0, "paid", 1, FACTORY_ALLOW);
    return ok ? 0 : 1;
}
