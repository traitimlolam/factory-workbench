#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
#import <dlfcn.h>
#import <objc/runtime.h>
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

@interface STTelephonyStatusDomainSIMInfo : NSObject
@end

@interface SBTelephonyManager : NSObject
+ (id)sharedTelephonyManager;
- (void)_updateState;
@end

@interface SBStatusBarStateAggregator : NSObject
+ (id)sharedInstance;
- (void)_updateServiceItem;
- (void)_updateDataNetworkItem;
- (void)_updateSignalStrengthItem;
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

static void triggerStatusBarRefresh(void) {
    Class aggCls = objc_getClass("SBStatusBarStateAggregator");
    if (aggCls && [aggCls respondsToSelector:@selector(sharedInstance)]) {
        id agg = [aggCls sharedInstance];
        if ([agg respondsToSelector:@selector(_updateSignalStrengthItem)]) {
            [agg _updateSignalStrengthItem];
        }
    }
}

static void onSettingsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    reloadPrefs();
    triggerStatusBarRefresh();
}

// ── Core hook logic ────────────────────────────────────────────────────────────
static void applyEntry(_UIStatusBarDataCellularEntry *entry) {
    if (!entry) return;
    entry.enabled = YES;
    entry.bars    = 4;
    entry.status  = 5;
    entry.displayValue = 4;

    NSInteger targetType = 11; // 5G standard in iOS 17 enum
    if ([g_netType isEqualToString:@"4G"])       targetType = 6;
    else if ([g_netType isEqualToString:@"LTE"]) targetType = 7;
    else                                          targetType = 11;

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
    if (!text || text.length == 0 || text.length > 25) return NO;
    if ([text containsString:@":"] || [text containsString:@"%"]) return NO;

    NSString *folded = [text stringByFoldingWithOptions:NSDiacriticInsensitiveSearch | NSCaseInsensitiveSearch locale:[NSLocale currentLocale]];
    NSString *t = [folded stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];

    if ([t isEqualToString:@"5g"] || [t isEqualToString:@"5g+"] || [t isEqualToString:@"5g uc"] ||
        [t isEqualToString:@"5g uw"] || [t isEqualToString:@"5ge"] || [t isEqualToString:@"lte"] ||
        [t isEqualToString:@"lte+"] || [t isEqualToString:@"4g"] || [t isEqualToString:@"4g+"] ||
        [t isEqualToString:@"3g"] || [t isEqualToString:@"2g"] || [t isEqualToString:@"1x"] ||
        [t isEqualToString:@"e"] || [t isEqualToString:@"edge"] || [t isEqualToString:@"gprs"] ||
        [t isEqualToString:@"sos"] || [t containsString:@"sos"] ||
        [t containsString:@"no sim"] || [t containsString:@"khong co sim"] ||
        [t containsString:@"no service"] || [t containsString:@"khong co dich vu"] ||
        [t containsString:@"searching"] || [t containsString:@"dang tim kiem"]) {
        return YES;
    }
    return NO;
}

// ── Default Group: UIKit & Modern Status Bar ─────────────────────────────────
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
        if ([g_netType isEqualToString:@"4G"]) return 6;
        if ([g_netType isEqualToString:@"LTE"]) return 7;
        return 11; // 5G
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

// ── iOS 16 & 17 Core Group: SystemStatus.framework (STTelephonyStatusDomainSIMInfo) ──
%group iOS17_SystemStatus
%hook STTelephonyStatusDomainSIMInfo
- (unsigned long long)signalStrengthBars {
    return g_enabled ? 4 : %orig;
}

- (unsigned long long)dataNetworkType {
    if (g_enabled) {
        if ([g_netType isEqualToString:@"4G"]) return 6;
        if ([g_netType isEqualToString:@"LTE"]) return 7;
        return 11; // 5G
    }
    return %orig;
}

- (unsigned long long)serviceState {
    return g_enabled ? 2 : %orig;
}

- (unsigned long long)cellularServiceState {
    return g_enabled ? 2 : %orig;
}

- (NSString *)serviceDescription {
    if (g_enabled) {
        NSString *orig = %orig;
        if (orig && orig.length > 0) return orig;
        return @"Viettel";
    }
    return %orig;
}

- (NSString *)secondaryServiceDescription {
    if (g_enabled) {
        NSString *orig = %orig;
        if (orig && orig.length > 0) return orig;
        return @"Viettel";
    }
    return %orig;
}

- (BOOL)isProvidingDataConnection {
    return g_enabled ? YES : %orig;
}

- (BOOL)isPreferredForDataConnections {
    return g_enabled ? YES : %orig;
}

- (BOOL)isRegisteredWithoutCellular {
    return g_enabled ? NO : %orig;
}
%end
%end

// ── Telephony Manager Group ──────────────────────────────────────────────────
%group TelephonyManagerGroup
%hook SBTelephonyManager
- (int)signalStrengthBars {
    return g_enabled ? 4 : %orig;
}

- (int)dataConnectionType {
    if (g_enabled) {
        if ([g_netType isEqualToString:@"4G"]) return 6;
        if ([g_netType isEqualToString:@"LTE"]) return 7;
        return 11; // 5G
    }
    return %orig;
}

- (BOOL)hasCellularData {
    return g_enabled ? YES : %orig;
}

- (BOOL)hasCellularTelephony {
    return g_enabled ? YES : %orig;
}

- (id)operatorName {
    if (g_enabled) {
        return @"Viettel";
    }
    return %orig;
}
%end
%end

// ── Aggregator Group: Prevent iOS from resetting fake status ─────────────────
%group AggregatorGroup
%hook SBStatusBarStateAggregator
- (void)_updateDataNetworkItem {
    if (g_enabled) {
        return; // Suppress original from overwriting our fake network type
    }
    %orig;
}

- (void)_updateServiceItem {
    if (g_enabled) {
        return; // Suppress original from marking "No SIM" / "Searching"
    }
    %orig;
}
%end
%end

// ── Constructor ───────────────────────────────────────────────────────────────
%ctor {
    reloadPrefs();
    
    // 1. Initialize default UIKit hooks
    %init;
    
    // 2. Load SystemStatus private frameworks and initialize group
    dlopen("/System/Library/PrivateFrameworks/SystemStatus.framework/SystemStatus", RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/SystemStatusServer.framework/SystemStatusServer", RTLD_NOW);
    
    Class simInfoCls = objc_getClass("STTelephonyStatusDomainSIMInfo");
    if (!simInfoCls) {
        simInfoCls = NSClassFromString(@"STTelephonyStatusDomainSIMInfo");
    }
    if (simInfoCls) {
        %init(iOS17_SystemStatus, STTelephonyStatusDomainSIMInfo = simInfoCls);
    }
    
    // 3. Initialize SBTelephonyManager group
    Class teleCls = objc_getClass("SBTelephonyManager");
    if (teleCls) {
        %init(TelephonyManagerGroup, SBTelephonyManager = teleCls);
    }

    // 4. Initialize SBStatusBarStateAggregator group
    Class aggCls = objc_getClass("SBStatusBarStateAggregator");
    if (aggCls) {
        %init(AggregatorGroup, SBStatusBarStateAggregator = aggCls);
    }
    
    // 5. Register Darwin notification listener
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        (CFNotificationCallback)onSettingsChanged,
        CFSTR("vn.nguyentronghieu.fakecellular5g/settingsChanged"),
        NULL,
        CFNotificationSuspensionBehaviorDeliverImmediately
    );
}