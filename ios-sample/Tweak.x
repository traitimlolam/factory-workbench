#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import "FactoryConfig.h"
#import "FactoryLicenseGate.h"

@interface _UIStatusBarDataEntry : NSObject
@property (nonatomic, assign, getter=isEnabled) BOOL enabled;
@end

@interface _UIStatusBarDataCellularEntry : _UIStatusBarDataEntry
@property (nonatomic, assign) NSInteger status;
@property (nonatomic, assign) NSInteger bars;
@property (nonatomic, copy) NSString *string;
@property (nonatomic, assign) NSInteger type;
@property (nonatomic, assign) BOOL wifiCalling;
@end

@interface _UIStatusBarDataWifiEntry : _UIStatusBarDataEntry
@property (nonatomic, assign) NSInteger status;
@property (nonatomic, assign) NSInteger bars;
@end

@interface _UIStatusBarData : NSObject
@property (nonatomic, strong) _UIStatusBarDataCellularEntry *cellularEntry;
@property (nonatomic, strong) _UIStatusBarDataWifiEntry *wifiEntry;
- (id)copyWithZone:(struct _NSZone *)zone;
@end

@interface _UIStatusBarDataAggregator : NSObject
- (_UIStatusBarData *)_currentData;
- (void)_updateItemData:(id)data;
@end

static NSString *factoryDeviceUDID(void) {
    void *library = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (!library) return nil;
    CFTypeRef (*copyAnswer)(CFStringRef) = (CFTypeRef (*)(CFStringRef))dlsym(library, "MGCopyAnswer");
    CFTypeRef value = copyAnswer ? copyAnswer(CFSTR("UniqueDeviceID")) : NULL;
    NSString *answer = nil;
    if (value && CFGetTypeID(value) == CFStringGetTypeID()) {
        answer = [(__bridge NSString *)value copy];
    }
    if (value) CFRelease(value);
    dlclose(library);
    return answer;
}

static long long factoryFirstSeen(long long now) {
    NSString *folder = @"/var/mobile/Library/Application Support/FakeCellular5G";
    NSString *file = [folder stringByAppendingPathComponent:[NSString stringWithUTF8String:FACTORY_LICENSE_ID]];
    NSString *value = [NSString stringWithContentsOfFile:file encoding:NSUTF8StringEncoding error:nil];
    if (value.length) {
        NSScanner *scanner = [NSScanner scannerWithString:value];
        long long saved = 0;
        if (![scanner scanLongLong:&saved] || !scanner.isAtEnd || saved <= 0) return -1;
        return saved;
    }
    NSError *error = nil;
    if (![[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:&error]) return -1;
    if (![[NSString stringWithFormat:@"%lld", now] writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:&error]) return -1;
    return now;
}

static BOOL isTweakLicensed(void) {
    static BOOL cachedDecision = NO;
    static NSTimeInterval lastCheckTime = 0;
    
    NSTimeInterval currentTime = [[NSDate date] timeIntervalSince1970];
    if (currentTime - lastCheckTime < 3.0 && lastCheckTime > 0) {
        return cachedDecision;
    }
    lastCheckTime = currentTime;
    
    long long now = (long long)currentTime;
    long long first = factoryFirstSeen(now);
    NSString *udid = factoryDeviceUDID();
    
    if (!udid) {
        cachedDecision = NO;
        return NO;
    }
    
    FactoryLicenseDecision decision = factory_license_check(
        udid.UTF8String,
        FACTORY_ALLOWED_UDID,
        now,
        first,
        FACTORY_TRIAL_SECONDS,
        FACTORY_KIND
    );
    
    cachedDecision = (decision.allowed == 1);
    return cachedDecision;
}

static void applyFakeCellular(_UIStatusBarData *data) {
    if (!data) return;
    
    BOOL wifiActive = NO;
    if (data.wifiEntry && data.wifiEntry.isEnabled && data.wifiEntry.status > 0) {
        wifiActive = YES;
    }
    
    if (!data.cellularEntry) {
        Class cellClass = NSClassFromString(@"_UIStatusBarDataCellularEntry");
        if (cellClass) {
            data.cellularEntry = [[cellClass alloc] init];
        }
    }
    
    if (data.cellularEntry) {
        data.cellularEntry.enabled = YES;
        data.cellularEntry.status = 5;
        data.cellularEntry.bars = 4;
        
        if (wifiActive) {
            data.cellularEntry.string = @"";
        } else {
            data.cellularEntry.string = @"5G";
            data.cellularEntry.type = 5;
        }
    }
}

%hook _UIStatusBarData
- (id)copyWithZone:(struct _NSZone *)zone {
    _UIStatusBarData *copy = %orig;
    if (copy && isTweakLicensed()) {
        applyFakeCellular(copy);
    }
    return copy;
}
%end

%hook _UIStatusBarDataAggregator
- (_UIStatusBarData *)_currentData {
    _UIStatusBarData *data = %orig;
    if (data && isTweakLicensed()) {
        applyFakeCellular(data);
    }
    return data;
}
%end

%hook _UIStatusBarDataCellularEntry
- (NSInteger)bars {
    if (isTweakLicensed()) return 4;
    return %orig;
}
%end
