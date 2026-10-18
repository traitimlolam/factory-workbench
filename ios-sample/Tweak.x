#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <notify.h>
#import "FactoryConfig.h"
#import "FactoryLicenseGate.h"

// ── Private headers ──────────────────────────────────────────────────────────
@interface _UIStatusBarDataEntry : NSObject
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
@end

@interface _UIStatusBarDataCellularEntry : _UIStatusBarDataEntry
@property (nonatomic, assign) NSInteger status;
@property (nonatomic, assign) NSInteger bars;
@property (nonatomic, copy)   NSString *string;
@property (nonatomic, assign) NSInteger type;
@end

@interface _UIStatusBarDataWifiEntry : _UIStatusBarDataEntry
@property (nonatomic, assign) NSInteger status;
@end

@interface _UIStatusBarData : NSObject
@property (nonatomic, strong) _UIStatusBarDataCellularEntry *cellularEntry;
@property (nonatomic, strong) _UIStatusBarDataWifiEntry    *wifiEntry;
- (id)copyWithZone:(struct _NSZone *)zone;
@end

@interface _UIStatusBarDataAggregator : NSObject
- (_UIStatusBarData *)_currentData;
@end

// ── Globals ──────────────────────────────────────────────────────────────────
static BOOL  g_enabled     = YES;
static NSString *g_netType = @"5G";

static void reloadPrefs(void) {
    CFPreferencesAppSynchronize((CFStringRef)@"vn.nguyentronghieu.fakecellular5g");
    CFPropertyListRef val;

    val = CFPreferencesCopyAppValue(CFSTR("enabled"), (CFStringRef)@"vn.nguyentronghieu.fakecellular5g");
    if (val) {
        if (CFGetTypeID(val) == CFBooleanGetTypeID())
            g_enabled = CFBooleanGetValue((CFBooleanRef)val);
        CFRelease(val);
    }

    val = CFPreferencesCopyAppValue(CFSTR("networkType"), (CFStringRef)@"vn.nguyentronghieu.fakecellular5g");
    if (val) {
        if (CFGetTypeID(val) == CFStringGetTypeID())
            g_netType = [(__bridge NSString *)val copy];
        CFRelease(val);
    }
}

// ── License helpers ───────────────────────────────────────────────────────────
static NSString *factoryDeviceUDID(void) {
    void *lib = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (!lib) return nil;
    CFTypeRef (*copy)(CFStringRef) = (CFTypeRef (*)(CFStringRef))dlsym(lib, "MGCopyAnswer");
    CFTypeRef v = copy ? copy(CFSTR("UniqueDeviceID")) : NULL;
    NSString *s = nil;
    if (v && CFGetTypeID(v) == CFStringGetTypeID()) s = [(__bridge NSString *)v copy];
    if (v) CFRelease(v);
    dlclose(lib);
    return s;
}

static long long factoryFirstSeen(long long now) {
    NSString *folder = @"/var/mobile/Library/Application Support/FakeCellular5G";
    NSString *file   = [folder stringByAppendingPathComponent:
                        [NSString stringWithUTF8String:FACTORY_LICENSE_ID]];
    NSString *saved  = [NSString stringWithContentsOfFile:file
                                                 encoding:NSUTF8StringEncoding error:nil];
    if (saved.length) {
        long long ts = 0;
        NSScanner *sc = [NSScanner scannerWithString:saved];
        if ([sc scanLongLong:&ts] && sc.isAtEnd && ts > 0) return ts;
        return -1;
    }
    NSError *err = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:folder
                                 withIntermediateDirectories:YES attributes:nil error:&err];
    if (err) return -1;
    [[NSString stringWithFormat:@"%lld", now] writeToFile:file atomically:YES
                                                encoding:NSUTF8StringEncoding error:&err];
    return err ? -1 : now;
}

static BOOL isTweakLicensed(void) {
    static BOOL cached = NO;
    static NSTimeInterval lastCheck = 0;
    NSTimeInterval now_d = [[NSDate date] timeIntervalSince1970];
    if (now_d - lastCheck < 3.0 && lastCheck > 0) return cached;
    lastCheck = now_d;

    long long now   = (long long)now_d;
    long long first = factoryFirstSeen(now);
    NSString *udid  = factoryDeviceUDID();
    if (!udid) { cached = NO; return NO; }

    FactoryLicenseDecision d = factory_license_check(
        udid.UTF8String, FACTORY_ALLOWED_UDID,
        now, first, FACTORY_TRIAL_SECONDS, FACTORY_KIND);
    cached = (d.allowed == 1);
    return cached;
}

// ── Core hook logic ────────────────────────────────────────────────────────────
static void applyFake(_UIStatusBarData *data) {
    if (!data) return;
    BOOL wifiOn = (data.wifiEntry && data.wifiEntry.isEnabled && data.wifiEntry.status > 0);

    if (!data.cellularEntry) {
        Class cls = NSClassFromString(@"_UIStatusBarDataCellularEntry");
        if (cls) data.cellularEntry = [[cls alloc] init];
    }
    if (!data.cellularEntry) return;

    data.cellularEntry.enabled = YES;
    data.cellularEntry.bars    = 4;
    data.cellularEntry.status  = 5;

    if (wifiOn) {
        // Keep Wi-Fi icon; blank the cellular string
        data.cellularEntry.string = @"";
    } else {
        data.cellularEntry.string = g_netType;
        // type: 3=4G, 4=LTE, 5=5G
        if ([g_netType isEqualToString:@"4G"])       data.cellularEntry.type = 3;
        else if ([g_netType isEqualToString:@"LTE"]) data.cellularEntry.type = 4;
        else                                          data.cellularEntry.type = 5;
    }
}

// ── Hooks ────────────────────────────────────────────────────────────────────
%hook _UIStatusBarData
- (id)copyWithZone:(struct _NSZone *)z {
    _UIStatusBarData *copy = %orig;
    if (copy && g_enabled && isTweakLicensed()) applyFake(copy);
    return copy;
}
%end

%hook _UIStatusBarDataAggregator
- (_UIStatusBarData *)_currentData {
    _UIStatusBarData *data = %orig;
    if (data && g_enabled && isTweakLicensed()) applyFake(data);
    return data;
}
%end

%hook _UIStatusBarDataCellularEntry
- (NSInteger)bars {
    return (g_enabled && isTweakLicensed()) ? 4 : %orig;
}
%end

// ── Constructor ───────────────────────────────────────────────────────────────
%ctor {
    reloadPrefs();
    int token = 0;
    notify_register_dispatch("vn.nguyentronghieu.fakecellular5g/settingsChanged", &token, dispatch_get_main_queue(), ^(int t) {
        reloadPrefs();
    });
}
