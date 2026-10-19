#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
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
    NSString *path1 = @"/var/mobile/Library/Preferences/vn.nguyentronghieu.fakecellular5g.plist";
    NSString *path2 = @"/var/jb/var/mobile/Library/Preferences/vn.nguyentronghieu.fakecellular5g.plist";
    
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:path1];
    if (!dict || dict.count == 0) {
        dict = [NSDictionary dictionaryWithContentsOfFile:path2];
    }

    if (dict && dict.count > 0) {
        if (dict[@"enabled"] != nil) {
            g_enabled = [dict[@"enabled"] boolValue];
        } else {
            g_enabled = YES;
        }

        NSString *type = dict[@"networkType"];
        if ([type isEqualToString:@"4G"] || [type isEqualToString:@"LTE"] || [type isEqualToString:@"5G"]) {
            g_netType = type;
        } else {
            g_netType = @"5G";
        }
    } else {
        // Fallback: CFPreferences API
        CFPreferencesAppSynchronize((CFStringRef)@"vn.nguyentronghieu.fakecellular5g");
        CFPropertyListRef val;

        val = CFPreferencesCopyAppValue(CFSTR("enabled"), (CFStringRef)@"vn.nguyentronghieu.fakecellular5g");
        if (val) {
            if (CFGetTypeID(val) == CFBooleanGetTypeID())
                g_enabled = CFBooleanGetValue((CFBooleanRef)val);
            CFRelease(val);
        } else {
            g_enabled = YES;
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
}

// ── Core hook logic ────────────────────────────────────────────────────────────
static void applyEntry(_UIStatusBarDataCellularEntry *entry) {
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
    entry.string = g_netType ?: @"5G";
    entry.crossfadeString = g_netType ?: @"5G";
    entry.badgeString = g_netType ?: @"5G";
    entry.wifiCallingEnabled = NO;
    entry.callForwardingEnabled = NO;
    entry.showsSOSWhenDisabled = NO;
    entry.sosAvailable = NO;
}

static void applyFake(_UIStatusBarData *data) {
    if (!data) return;

    Class cls = NSClassFromString(@"_UIStatusBarDataCellularEntry");
    if (!data.cellularEntry && cls) {
        data.cellularEntry = [[cls alloc] init];
    }
    if (data.cellularEntry) {
        applyEntry(data.cellularEntry);
    }

    if ([data respondsToSelector:@selector(secondaryCellularEntry)]) {
        if (!data.secondaryCellularEntry && cls) {
            data.secondaryCellularEntry = [[cls alloc] init];
        }
        if (data.secondaryCellularEntry) {
            applyEntry(data.secondaryCellularEntry);
        }
    }
}

// ── StringView Override Helper ────────────────────────────────────────────────
static inline BOOL isCellularNetworkIndicator(NSString *text) {
    if (!text || text.length == 0 || text.length > 12) return NO;
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
            [u isEqualToString:@"SOS"] ||
            [u isEqualToString:@"NO SERVICE"] ||
            [u isEqualToString:@"NO SIM"]);
}

// ── Hooks ────────────────────────────────────────────────────────────────────
%hook _UIStatusBarData
- (id)copyWithZone:(struct _NSZone *)z {
    _UIStatusBarData *copy = %orig;
    if (copy && g_enabled) applyFake(copy);
    return copy;
}
%end

%hook _UIStatusBarDataAggregator
- (_UIStatusBarData *)_currentData {
    _UIStatusBarData *data = %orig;
    if (data && g_enabled) applyFake(data);
    return data;
}
%end

%hook _UIStatusBarDataCellularEntry
- (NSInteger)bars {
    return g_enabled ? 4 : %orig;
}
- (NSInteger)displayValue {
    return g_enabled ? 4 : %orig;
}
- (NSInteger)status {
    return g_enabled ? 5 : %orig;
}
- (NSInteger)type {
    if (g_enabled) {
        if ([g_netType isEqualToString:@"4G"]) return 5;
        if ([g_netType isEqualToString:@"LTE"]) return 6;
        return 9; // 5G
    }
    return %orig;
}
- (NSString *)string {
    if (g_enabled) {
        return g_netType ?: @"5G";
    }
    return %orig;
}
- (NSString *)crossfadeString {
    if (g_enabled) {
        return g_netType ?: @"5G";
    }
    return %orig;
}
- (NSString *)badgeString {
    if (g_enabled) {
        return g_netType ?: @"5G";
    }
    return %orig;
}
- (BOOL)isEnabled {
    return g_enabled ? YES : %orig;
}
%end

%hook _UIStatusBarCellularSignalView
- (NSInteger)numberOfActiveBars {
    return g_enabled ? 4 : %orig;
}
- (NSInteger)numberOfBars {
    return g_enabled ? 4 : %orig;
}
%end

%hook _UIStatusBarDualCellularSignalView
- (NSInteger)numberOfActiveBars {
    return g_enabled ? 4 : %orig;
}
%end

%hook _UIStatusBarCellularItem
- (id)_stringForCellularType:(long long)type {
    if (g_enabled && g_netType.length) {
        return g_netType;
    }
    return %orig;
}
%end

%hook _UIStatusBarCellularCondensedItem
- (id)_stringForCellularType:(long long)type {
    if (g_enabled && g_netType.length) {
        return g_netType;
    }
    return %orig;
}
%end

%hook _UIStatusBarStringView
- (void)setText:(NSString *)text {
    if (g_enabled && isCellularNetworkIndicator(text)) {
        %orig(g_netType ?: @"5G");
        return;
    }
    %orig(text);
}

- (void)setOriginalText:(NSString *)text {
    if (g_enabled && isCellularNetworkIndicator(text)) {
        %orig(g_netType ?: @"5G");
        return;
    }
    %orig(text);
}
%end

// ── Constructor ───────────────────────────────────────────────────────────────
%ctor {
    %init;
    reloadPrefs();
    
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)reloadPrefs,
        CFSTR("vn.nguyentronghieu.fakecellular5g/settingsChanged"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}
