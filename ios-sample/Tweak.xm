#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import "FactoryConfig.h"
#import "FactoryLicenseGate.h"

extern void FactoryFeatureDidStart(UIViewController *controller);

static NSString *factoryDeviceUDID(void) {
    void *library = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (!library) return nil;
    CFTypeRef (*copyAnswer)(CFStringRef) = dlsym(library, "MGCopyAnswer");
    CFTypeRef value = copyAnswer ? copyAnswer(CFSTR("UniqueDeviceID")) : NULL;
    NSString *answer = nil;
    if (value && CFGetTypeID(value) == CFStringGetTypeID())
        answer = [(__bridge NSString *)value copy];
    if (value) CFRelease(value);
    dlclose(library);
    return answer;
}

static long long factoryFirstSeen(long long now) {
    /* SpringBoard's mobile-owned data directory works with rootless /var/jb packages. */
    NSString *folder = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/FactorySample"];
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

%hook SpringBoard
- (void)applicationDidFinishLaunching:(id)application {
    %orig;
    long long now = (long long)[[NSDate date] timeIntervalSince1970];
    long long first = factoryFirstSeen(now);
    NSString *udid = factoryDeviceUDID();
    FactoryLicenseDecision decision = factory_license_check(udid.UTF8String,
        FACTORY_ALLOWED_UDID, now, first, FACTORY_TRIAL_SECONDS, FACTORY_KIND);
    if (!decision.allowed) {
        NSLog(@"FactorySample: license blocked (%d)", decision.reason);
        return;
    }
    NSLog(@"FactorySample: SpringBoard started; sample active");
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [UIApplication sharedApplication].keyWindow;
        UIViewController *controller = window.rootViewController;
        if (!controller) return;
        FactoryFeatureDidStart(controller);
    });
}
%end
