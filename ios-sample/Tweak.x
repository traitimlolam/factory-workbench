#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <CoreMotion/CoreMotion.h>
#import <objc/runtime.h>
#import <sys/utsname.h>
#import <dlfcn.h>
#import <math.h>
#import "FactoryConfig.h"
#import "FactoryLicenseGate.h"

@interface SBOrientationLockManager : NSObject
+ (instancetype)sharedInstance;
- (BOOL)isUserLocked;
- (BOOL)isLocked;
- (void)lock;
- (void)unlock;
- (void)lock:(long long)orientation;
@end

@interface SBDeviceOrientationUpdateManager : NSObject
- (void)_enqueueOrientationUpdateToDeviceOrientation:(long long)orientation;
@end

@interface UIApplication (SpringBoardOrientation)
- (void)_overrideDefaultInterfaceOrientationWithOrientation:(long long)orientation;
@end

@interface CRTouchWindow : UIWindow
@end

@implementation CRTouchWindow
- (BOOL)_canBecomeKeyWindow {
    return NO;
}
- (BOOL)_shouldCreateScreenPresentationContext {
    return NO;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) {
        return nil;
    }
    return hit;
}
@end

static UIWindowScene *getMainSpringBoardScene(void) {
    UIApplication *app = [UIApplication sharedApplication];
    for (UIScene *scene in app.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *ws = (UIWindowScene *)scene;
            if (ws.screen == [UIScreen mainScreen]) {
                return ws;
            }
        }
    }
    for (UIScene *scene in app.connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            return (UIWindowScene *)scene;
        }
    }
    return nil;
}

@interface CRRotateManager : NSObject
+ (instancetype)sharedInstance;
- (void)startMonitoring;
- (void)deviceOrientationChangedTo:(long long)deviceOri;
- (void)showCapsulePromptWithTargetOrientation:(UIInterfaceOrientation)targetOri;
- (void)dismissCapsuleAnimated:(BOOL)animated;
@end

@implementation CRRotateManager {
    CMMotionManager *_motionManager;
    CRTouchWindow *_touchWindow;
    UIView *_capsuleContainer;
    UIImageView *_iconView;
    NSTimer *_dismissTimer;
    UIInterfaceOrientation _pendingOrientation;
    long long _lastProcessedOrientation;
    BOOL _isShowing;
}

+ (instancetype)sharedInstance {
    static CRRotateManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CRRotateManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _isShowing = NO;
        _pendingOrientation = UIInterfaceOrientationUnknown;
        _lastProcessedOrientation = 0;
    }
    return self;
}

- (CRTouchWindow *)getOrCreateTouchWindow {
    if (!_touchWindow) {
        UIWindowScene *scene = getMainSpringBoardScene();
        if (scene) {
            _touchWindow = [[CRTouchWindow alloc] initWithWindowScene:scene];
        } else {
            _touchWindow = [[CRTouchWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
        _touchWindow.windowLevel = UIWindowLevelStatusBar + 10000.0;
        _touchWindow.backgroundColor = [UIColor clearColor];
        UIViewController *vc = [[UIViewController alloc] init];
        vc.view.backgroundColor = [UIColor clearColor];
        _touchWindow.rootViewController = vc;
        _touchWindow.hidden = NO;
    }
    return _touchWindow;
}

- (UIView *)getOrCreateCapsuleView {
    if (!_capsuleContainer) {
        // iOS 14 Style Square 48x48 with cornerRadius 12.0
        UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 48.0, 48.0)];
        container.layer.cornerRadius = 12.0;
        container.layer.masksToBounds = NO;
        container.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.88];
        container.layer.borderWidth = 1.0;
        container.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;

        // Drop Shadow
        container.layer.shadowColor = [UIColor blackColor].CGColor;
        container.layer.shadowOpacity = 0.50;
        container.layer.shadowRadius = 8.0;
        container.layer.shadowOffset = CGSizeMake(0, 3);

        // Icon centered inside 48x48 container
        UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(10.0, 10.0, 28.0, 28.0)];
        icon.contentMode = UIViewContentModeScaleAspectFit;

        NSString *imgPath = @"/Library/Application Support/ConfirmRotate/ConfirmRotateBundle.bundle/rotate.png";
        UIImage *img = [UIImage imageWithContentsOfFile:imgPath];
        if (!img) {
            UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightSemibold];
            img = [UIImage systemImageNamed:@"arrow.triangle.2.circlepath" withConfiguration:config];
            icon.tintColor = [UIColor whiteColor];
        }
        icon.image = img;
        [container addSubview:icon];
        self->_iconView = icon;

        // Tap Gesture
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleCapsuleTapped)];
        tap.cancelsTouchesInView = YES;
        [container addGestureRecognizer:tap];
        container.userInteractionEnabled = YES;

        self->_capsuleContainer = container;
    }
    return _capsuleContainer;
}

- (void)startMonitoring {
    if (_motionManager) return;

    _motionManager = [[CMMotionManager alloc] init];
    if (_motionManager.isAccelerometerAvailable) {
        _motionManager.accelerometerUpdateInterval = 0.25;
        [_motionManager startAccelerometerUpdatesToQueue:[NSOperationQueue mainQueue]
                                             withHandler:^(CMAccelerometerData * _Nullable data, NSError * _Nullable error) {
            if (data) {
                double x = data.acceleration.x;
                double y = data.acceleration.y;
                double z = data.acceleration.z;
                if (fabs(z) >= 0.90) return;

                double angle = atan2(x, -y) * 180.0 / M_PI;
                long long ori = 0;
                if (angle >= -45.0 && angle <= 45.0) {
                    ori = 1; // Portrait
                } else if (angle > 45.0 && angle <= 135.0) {
                    ori = 3; // Landscape Right
                } else if (angle >= -135.0 && angle < -45.0) {
                    ori = 4; // Landscape Left
                }

                if (ori != 0) {
                    [self deviceOrientationChangedTo:ori];
                }
            }
        }];
    }
}

- (void)deviceOrientationChangedTo:(long long)deviceOri {
    if (deviceOri <= 0 || deviceOri > 4) return;
    if (deviceOri == _lastProcessedOrientation) return;
    _lastProcessedOrientation = deviceOri;

    UIInterfaceOrientation targetOri = UIInterfaceOrientationUnknown;
    if (deviceOri == 1) {
        targetOri = UIInterfaceOrientationPortrait;
    } else if (deviceOri == 3) {
        targetOri = UIInterfaceOrientationLandscapeLeft;
    } else if (deviceOri == 4) {
        targetOri = UIInterfaceOrientationLandscapeRight;
    } else if (deviceOri == 2) {
        targetOri = UIInterfaceOrientationPortrait;
    }

    if (targetOri == UIInterfaceOrientationUnknown) return;

    UIInterfaceOrientation currentOri = UIInterfaceOrientationPortrait;
    UIWindowScene *scene = getMainSpringBoardScene();
    if (scene) {
        currentOri = scene.interfaceOrientation;
    }

    if (targetOri == currentOri) {
        [self dismissCapsuleAnimated:YES];
        return;
    }

    [self showCapsulePromptWithTargetOrientation:targetOri];
}

- (void)showCapsulePromptWithTargetOrientation:(UIInterfaceOrientation)targetOri {
    _pendingOrientation = targetOri;
    [_dismissTimer invalidate];

    CRTouchWindow *win = [self getOrCreateTouchWindow];
    UIView *capsule = [self getOrCreateCapsuleView];

    if (capsule.superview != win.rootViewController.view) {
        [capsule removeFromSuperview];
        [win.rootViewController.view addSubview:capsule];
    }
    [win.rootViewController.view bringSubviewToFront:capsule];

    CGRect bounds = [UIScreen mainScreen].bounds;
    CGFloat size = 48.0;
    CGFloat marginX = 16.0;
    CGFloat posY = (bounds.size.height / 2.0) - (size / 2.0);

    // Fixed container coordinates on right edge
    capsule.frame = CGRectMake(bounds.size.width - size - marginX,
                               posY,
                               size,
                               size);

    // Rotate only inner icon
    CGFloat iconAngle = 0.0;
    if (targetOri == UIInterfaceOrientationLandscapeLeft) {
        iconAngle = M_PI_2;
    } else if (targetOri == UIInterfaceOrientationLandscapeRight) {
        iconAngle = -M_PI_2;
    } else if (targetOri == UIInterfaceOrientationPortraitUpsideDown) {
        iconAngle = M_PI;
    } else {
        iconAngle = 0.0;
    }
    if (self->_iconView) {
        self->_iconView.transform = CGAffineTransformMakeRotation(iconAngle);
    }

    capsule.alpha = 0.0;
    capsule.transform = CGAffineTransformMakeScale(0.4, 0.4);
    self->_isShowing = YES;

    // Disabled all haptic/vibration feedback

    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.7 initialSpringVelocity:0.7 options:UIViewAnimationOptionCurveEaseOut animations:^{
        capsule.alpha = 1.0;
        capsule.transform = CGAffineTransformIdentity;
    } completion:nil];

    // Auto dismiss after 3.5s
    self->_dismissTimer = [NSTimer scheduledTimerWithTimeInterval:3.5 repeats:NO block:^(NSTimer * _Nonnull timer) {
        [self dismissCapsuleAnimated:YES];
    }];
}

- (void)handleCapsuleTapped {
    [_dismissTimer invalidate];

    // Disabled tap haptic feedback

    UIView *capsule = self->_capsuleContainer;
    [UIView animateWithDuration:0.2 animations:^{
        capsule.transform = CGAffineTransformMakeScale(1.15, 1.15);
        capsule.alpha = 0.0;
    } completion:^(BOOL finished) {
        [capsule removeFromSuperview];
        capsule.transform = CGAffineTransformIdentity;
        self->_isShowing = NO;
    }];

    UIInterfaceOrientation target = _pendingOrientation;
    if (target == UIInterfaceOrientationUnknown) return;

    Class lockClass = NSClassFromString(@"SBOrientationLockManager");
    if (lockClass) {
        id lockMan = [lockClass performSelector:@selector(sharedInstance)];
        if (lockMan) {
            if ([lockMan respondsToSelector:@selector(unlock)]) {
                [lockMan unlock];
            }
            if ([lockMan respondsToSelector:@selector(lock:)]) {
                NSMethodSignature *sig = [lockMan methodSignatureForSelector:@selector(lock:)];
                if (sig) {
                    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
                    [inv setTarget:lockMan];
                    [inv setSelector:@selector(lock:)];
                    long long val = (long long)target;
                    [inv setArgument:&val atIndex:2];
                    [inv invoke];
                }
            }
        }
    }

    UIApplication *app = [UIApplication sharedApplication];
    if ([app respondsToSelector:@selector(_overrideDefaultInterfaceOrientationWithOrientation:)]) {
        NSMethodSignature *sig = [app methodSignatureForSelector:@selector(_overrideDefaultInterfaceOrientationWithOrientation:)];
        if (sig) {
            NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
            [inv setTarget:app];
            [inv setSelector:@selector(_overrideDefaultInterfaceOrientationWithOrientation:)];
            long long val = (long long)target;
            [inv setArgument:&val atIndex:2];
            [inv invoke];
        }
    }
}

- (void)dismissCapsuleAnimated:(BOOL)animated {
    if (!self->_isShowing || !self->_capsuleContainer || !self->_capsuleContainer.superview) return;

    UIView *capsule = self->_capsuleContainer;
    self->_isShowing = NO;

    if (animated) {
        [UIView animateWithDuration:0.25 animations:^{
            capsule.alpha = 0.0;
            capsule.transform = CGAffineTransformMakeScale(0.4, 0.4);
        } completion:^(BOOL finished) {
            [capsule removeFromSuperview];
            capsule.transform = CGAffineTransformIdentity;
        }];
    } else {
        [capsule removeFromSuperview];
        capsule.alpha = 0.0;
        capsule.transform = CGAffineTransformIdentity;
    }
}

@end

%hook SBDeviceOrientationUpdateManager
- (void)_enqueueOrientationUpdateToDeviceOrientation:(long long)orientation {
    %orig;
    dispatch_async(dispatch_get_main_queue(), ^{
        [[CRRotateManager sharedInstance] deviceOrientationChangedTo:orientation];
    });
}
%end

static NSString *factoryDeviceUDID(void) {
    void *library = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY);
    if (!library) return nil;
    CFTypeRef (*copyAnswer)(CFStringRef) = (CFTypeRef (*)(CFStringRef))dlsym(library, "MGCopyAnswer");
    CFTypeRef value = copyAnswer ? copyAnswer(CFSTR("UniqueDeviceID")) : NULL;
    NSString *answer = nil;
    if (value && CFGetTypeID(value) == CFStringGetTypeID())
        answer = [(__bridge NSString *)value copy];
    if (value) CFRelease(value);
    dlclose(library);
    return answer;
}

static long long factoryFirstSeen(long long now) {
    NSString *folder = [NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/ConfirmRotate"];
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
    
    // Check license if configured
    if (strlen(FACTORY_ALLOWED_UDID) > 0 && strcmp(FACTORY_ALLOWED_UDID, "ALL") != 0) {
        FactoryLicenseDecision decision = factory_license_check(udid.UTF8String,
            FACTORY_ALLOWED_UDID, now, first, FACTORY_TRIAL_SECONDS, FACTORY_KIND);
        if (!decision.allowed) {
            NSLog(@"[ConfirmRotate] license blocked (%d)", decision.reason);
            return;
        }
    }
    
    NSLog(@"[ConfirmRotate] SpringBoard started; ConfirmRotate active");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [[CRRotateManager sharedInstance] startMonitoring];
    });
}
%end
