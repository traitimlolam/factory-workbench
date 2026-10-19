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
@property (nonatomic, assign) NSInteger displayValue;
@property (nonatomic, assign) NSInteger bars;
@property (nonatomic, copy)   NSString *string;
@property (nonatomic, copy)   NSString *crossfadeString;
@property (nonatomic, copy)   NSString *badgeString;
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, assign) BOOL wifiCallingEnabled;
@property (nonatomic, assign) BOOL callForwardingEnabled;
@property (nonatomic, assign) BOOL showsSOSWhenDisabled;
@property (nonatomic, assign) BOOL sosAvailable;
@end

@interface _UIStatusBarDataWifiEntry : _UIStatusBarDataEntry
@property (nonatomic, assign) NSInteger status;
@end

@interface _UIStatusBarData : NSObject
@property (nonatomic, strong) _UIStatusBarDataCellularEntry *cellularEntry;
@property (nonatomic, strong) _UIStatusBarDataCellularEntry *secondaryCellularEntry;
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
        if (CFGetTypeID(val) == CFStringGetTypeID()) {
            NSString *stored = [(__bridge NSString *)val copy];
            if ([stored isEqualToString:@"4G"] || [stored isEqualToString:@"LTE"] || [stored isEqualToString:@"5G"])
                g_netType = stored;
            else
                g_netType = @"5G";
        }
        CFRelease(val);
    } else {
        g_netType = @"5G";
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
static void applyEntry(_UIStatusBarDataCellularEntry *entry, BOOL wifiOn) {
    if (!entry) return;
    entry.enabled = YES;
    entry.bars    = 4;
    entry.status  = 5;
    entry.displayValue = 4;

    NSInteger targetType = 9;
    if ([g_netType isEqualToString:@"4G"])       targetType = 5;
    else if ([g_netType isEqualToString:@"LTE"]) targetType = 6;
    else                                          targetType = 9;

    entry.type = targetType;

    if (wifiOn) {
        entry.string = @"";
        entry.crossfadeString = @"";
        entry.badgeString = @"";
    } else {
        entry.string = g_netType ?: @"5G";
        entry.crossfadeString = g_netType ?: @"5G";
        entry.badgeString = g_netType ?: @"5G";
    }
}

static void applyFake(_UIStatusBarData *data) {
    if (!data) return;
    BOOL wifiOn = (data.wifiEntry && data.wifiEntry.isEnabled && data.wifiEntry.status > 0);

    Class cls = NSClassFromString(@"_UIStatusBarDataCellularEntry");
    if (!data.cellularEntry && cls) {
        data.cellularEntry = [[cls alloc] init];
    }
    if (data.cellularEntry) {
        applyEntry(data.cellularEntry, wifiOn);
    }

    if ([data respondsToSelector:@selector(secondaryCellularEntry)]) {
        if (!data.secondaryCellularEntry && cls) {
            data.secondaryCellularEntry = [[cls alloc] init];
        }
        if (data.secondaryCellularEntry) {
            applyEntry(data.secondaryCellularEntry, wifiOn);
        }
    }
}

// ── StringView Override Helper ────────────────────────────────────────────────
static inline BOOL isCellularNetworkIndicator(NSString *text) {
    if (!text || text.length == 0 || text.length > 8) return NO;
    // Fast rejects: clock strings have ':', battery strings have '%'
    if ([text containsString:@":"] || [text containsString:@"%"]) return NO;

    NSString *t = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *u = [t uppercaseString];

    return ([u isEqualToString:@"5G"] ||
            [u isEqualToString:@"5G+"] ||
            [u isEqualToString:@"5G UC"] ||
            [u isEqualToString:@"5G UW"] ||
            [u isEqualToString:@"5GE"] ||
            [u isEqualToString:@"LTE"] ||
            [u isEqualToString:@"LTE+"] ||
            [u isEqualToString:@"4G"] ||
            [u isEqualToString:@"4G+"] ||
            [u isEqualToString:@"3G"] ||
            [u isEqualToString:@"3G+"] ||
            [u isEqualToString:@"2G"] ||
            [u isEqualToString:@"1X"] ||
            [u isEqualToString:@"1XRTT"] ||
            [u isEqualToString:@"E"] ||
            [u isEqualToString:@"EDGE"] ||
            [u isEqualToString:@"GPRS"] ||
            [u isEqualToString:@"SOS"]);
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
- (NSInteger)displayValue {
    return (g_enabled && isTweakLicensed()) ? 4 : %orig;
}
- (NSInteger)status {
    return (g_enabled && isTweakLicensed()) ? 5 : %orig;
}
- (NSInteger)type {
    if (g_enabled && isTweakLicensed()) {
        if ([g_netType isEqualToString:@"4G"]) return 5;
        if ([g_netType isEqualToString:@"LTE"]) return 6;
        return 9; // 5G
    }
    return %orig;
}
- (NSString *)string {
    if (g_enabled && isTweakLicensed()) {
        return g_netType ?: @"5G";
    }
    return %orig;
}
- (NSString *)crossfadeString {
    if (g_enabled && isTweakLicensed()) {
        return g_netType ?: @"5G";
    }
    return %orig;
}
- (NSString *)badgeString {
    if (g_enabled && isTweakLicensed()) {
        return g_netType ?: @"5G";
    }
    return %orig;
}
- (BOOL)isEnabled {
    return (g_enabled && isTweakLicensed()) ? YES : %orig;
}
%end

%hook _UIStatusBarCellularSignalView
- (NSInteger)numberOfActiveBars {
    return (g_enabled && isTweakLicensed()) ? 4 : %orig;
}
%end

%hook _UIStatusBarDualCellularSignalView
- (NSInteger)numberOfActiveBars {
    return (g_enabled && isTweakLicensed()) ? 4 : %orig;
}
%end

%hook _UIStatusBarCellularItem
- (id)_stringForCellularType:(long long)type {
    if (g_enabled && isTweakLicensed() && g_netType.length) {
        return g_netType;
    }
    return %orig;
}
%end

%hook _UIStatusBarCellularCondensedItem
- (id)_stringForCellularType:(long long)type {
    if (g_enabled && isTweakLicensed() && g_netType.length) {
        return g_netType;
    }
    return %orig;
}
%end

%hook _UIStatusBarStringView
- (void)setText:(NSString *)text {
    if (g_enabled && isTweakLicensed() && isCellularNetworkIndicator(text)) {
        %orig(g_netType ?: @"5G");
        return;
    }
    %orig(text);
}

- (void)setOriginalText:(NSString *)text {
    if (g_enabled && isTweakLicensed() && isCellularNetworkIndicator(text)) {
        %orig(g_netType ?: @"5G");
        return;
    }
    %orig(text);
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
